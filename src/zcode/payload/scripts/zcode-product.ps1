# ZCode Dream Skin product logic: state schema, port selection, launch plan,
# pause/resume transitions, log tags and the stable error-code table.
#
# Pure and dependency-injected on purpose: every machine touch (process table,
# port probes, file I/O) is either a parameter or a scriptblock, so the contract
# tests run without launching anything. Every ZCode-specific judgement still
# lives in scripts\zcode-adapter.ps1; this file only shapes the product flow.

$script:ZCODE_DREAM_SKIN_SCHEMA_VERSION = 'zcode-dream-skin-state/1'

$script:ZCODE_DREAM_SKIN_LOG_TAGS = @(
  'LAUNCH', 'PROCESS', 'PORT', 'CDP', 'TARGET', 'COMPAT',
  'INJECT', 'VERIFY', 'RELOAD', 'RESTORE', 'ERROR'
)

function Get-ZCodeDreamSkinStateRoot {
  param([string]$StateRoot = (Join-Path $env:LOCALAPPDATA 'ZCodeDreamSkin'))
  return $StateRoot
}

function Get-ZCodeDreamSkinErrorCodes {
  return @{
    'E01_ZCODE_NOT_FOUND'            = 'no ZCode executable candidate exists'
    'E02_ZCODE_IDENTITY_INVALID'     = 'signature or product identity mismatch'
    'E03_ZCODE_MULTIPLE_CANDIDATES'  = 'multiple ZCode candidates exist, user selection required'
    'E04_ZCODE_RUNNING_WITHOUT_CDP'  = 'ZCode is already running outside a managed session and must be closed normally by the user'
    'E05_CDP_PORT_FOREIGN_OWNER'     = 'the CDP port is held by a foreign owner; it is never terminated'
    'E06_CDP_ENDPOINT_UNAVAILABLE'   = 'nothing usable answered on the CDP endpoint'
    'E07_NO_RENDERER_TARGET'         = 'no usable renderer page target was found'
    'E08_TARGET_AMBIGUOUS'           = 'renderer target selection is ambiguous'
    'E09_RUNTIME_EVALUATE_FAILED'    = 'a renderer evaluation failed or did not verify'
    'E10_REMOVE_THEME_FAILED'        = 'skin removal did not verify; state is kept for repair'
    'E11_COMPATIBILITY_DENIED'       = 'the renderer does not match the verified profile'
    'E12_CDP_PORT_SEARCH_EXHAUSTED'  = 'no free CDP port in the automatic search range'
    'E13_STATE_SCHEMA_INVALID'       = 'the on-disk state file does not match the state schema'
    'E14_LOG_TAG_INVALID'            = 'an unknown log tag was requested'
  }
}

function New-ZCodeDreamSkinState {
  param(
    [Parameter(Mandatory = $true)][string]$ZCodePath,
    [Parameter(Mandatory = $true)][int]$RootPid,
    [Parameter(Mandatory = $true)][int]$Port,
    [Parameter(Mandatory = $true)][string]$BrowserWebSocketUrl,
    [Parameter(Mandatory = $true)][string]$Fingerprint,
    [Parameter(Mandatory = $true)][string]$CompatibilityMode,
    # An empty revision is legal only for a paused native session, where nothing has
    # been applied yet; a themed session cannot reach an active state without an
    # apply report carrying a revision, which the start path asserts independently.
    [Parameter(Mandatory = $true)][AllowEmptyString()][string]$ThemeVersion,
    [string]$WatchPid = '0'
  )
  # Validated by hand (not ValidateSet) so an unknown mode surfaces as the
  # stable E11 code instead of a parameter-binding error.
  if (@('full', 'safe', 'deny') -notcontains $CompatibilityMode) {
    throw "E11_COMPATIBILITY_DENIED: unknown compatibility mode $CompatibilityMode"
  }
  return [pscustomobject]@{
    schemaVersion       = $script:ZCODE_DREAM_SKIN_SCHEMA_VERSION
    zcodePath           = $ZCodePath
    rootPid             = $RootPid
    port                = $Port
    browserWebSocketUrl = $BrowserWebSocketUrl
    fingerprint         = $Fingerprint
    compatibilityMode   = $CompatibilityMode
    themeVersion        = $ThemeVersion
    paused              = $false
    stopped             = $false
    watchPid            = [int]$WatchPid
    updatedAt           = (Get-Date).ToString('o')
  }
}

function Set-ZCodeDreamSkinStateField {
  # Sets (or adds, on a JSON read-back that never carried the field) one property.
  # Assigning to a missing property is what threw "the property cannot be found"
  # and aborted Full restore, so every write to a state object goes through here.
  param(
    [Parameter(Mandatory = $true)]$State,
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)]$Value
  )
  if ($State.PSObject.Properties[$Name]) { $State.$Name = $Value }
  else { $null = $State | Add-Member -NotePropertyName $Name -NotePropertyValue $Value }
  return $State
}

function Get-ZCodeDreamSkinBoolField {
  # Schema 1 states written before a flag existed simply do not carry it, so a
  # missing flag is normalised to its default. A present value must be a real JSON
  # boolean: PowerShell would happily coerce "false" to $true, which is exactly how
  # a written stop request could read back as "keep running".
  param(
    [Parameter(Mandatory = $true)]$State,
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][bool]$Default
  )
  $property = $State.PSObject.Properties[$Name]
  if (-not $property) { return $Default }
  if ($property.Value -is [bool]) { return [bool]$property.Value }
  throw "E13_STATE_SCHEMA_INVALID: the state field $Name must be a JSON boolean"
}

function ConvertTo-ZCodeDreamSkinStateJson {
  param([Parameter(Mandatory = $true)]$State)
  return ($State | ConvertTo-Json -Depth 4 -Compress)
}

function ConvertFrom-ZCodeDreamSkinStateJson {
  param([Parameter(Mandatory = $true)][string]$Json)
  $state = $Json | ConvertFrom-Json
  if (-not $state -or [string]$state.schemaVersion -ne $script:ZCODE_DREAM_SKIN_SCHEMA_VERSION) {
    throw 'E13_STATE_SCHEMA_INVALID: the state file does not match zcode-dream-skin-state/1'
  }
  # Schema 1 stays readable. Only the two boolean flags are filled in, and only when
  # they are genuinely absent: identity fields (rootPid, port, browserWebSocketUrl,
  # watchPid, the verified path and fingerprint) are never rewritten, so a restored
  # session is still the session that was recorded and identity checks still apply.
  $state = Set-ZCodeDreamSkinStateField -State $state -Name 'paused' `
    -Value (Get-ZCodeDreamSkinBoolField -State $state -Name 'paused' -Default $false)
  $state = Set-ZCodeDreamSkinStateField -State $state -Name 'stopped' `
    -Value (Get-ZCodeDreamSkinBoolField -State $state -Name 'stopped' -Default $false)
  return $state
}

function Read-ZCodeDreamSkinState {
  param([Parameter(Mandatory = $true)][string]$StateRoot)
  $path = Join-Path (Get-ZCodeDreamSkinStateRoot -StateRoot $StateRoot) 'state.json'
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
  return ConvertFrom-ZCodeDreamSkinStateJson -Json (Get-Content -LiteralPath $path -Raw -Encoding UTF8)
}

function Write-ZCodeDreamSkinState {
  # Atomic write: the temp file lands in the same directory and is moved over
  # the target, so a crash mid-write can never leave a half state behind.
  # UTF-8 WITHOUT BOM: the watcher reads this file with JSON.parse, which throws
  # on a BOM - a BOM'd state file would make every stop and pause request
  # invisible to it (Set-Content -Encoding UTF8 writes a BOM on PowerShell 5.1).
  param(
    [Parameter(Mandatory = $true)][string]$StateRoot,
    [Parameter(Mandatory = $true)]$State
  )
  $root = Get-ZCodeDreamSkinStateRoot -StateRoot $StateRoot
  $null = [System.IO.Directory]::CreateDirectory($root)
  $final = Join-Path $root 'state.json'
  $temp = Join-Path $root ('state.json.tmp-' + [guid]::NewGuid().ToString('N'))
  [System.IO.File]::WriteAllText($temp, (ConvertTo-ZCodeDreamSkinStateJson -State $State), [System.Text.UTF8Encoding]::new($false))
  Move-Item -LiteralPath $temp -Destination $final -Force
  return $final
}

function Clear-ZCodeDreamSkinState {
  param([Parameter(Mandatory = $true)][string]$StateRoot)
  $root = Get-ZCodeDreamSkinStateRoot -StateRoot $StateRoot
  if (Test-Path -LiteralPath $root) {
    Remove-Item -LiteralPath (Join-Path $root 'state.json') -Force -ErrorAction SilentlyContinue
  }
}

function Set-ZCodeDreamSkinPaused {
  param(
    [Parameter(Mandatory = $true)]$State,
    [Parameter(Mandatory = $true)][bool]$Paused
  )
  $State = Set-ZCodeDreamSkinStateField -State $State -Name 'paused' -Value $Paused
  $State = Set-ZCodeDreamSkinStateField -State $State -Name 'updatedAt' -Value (Get-Date).ToString('o')
  return $State
}

function Set-ZCodeDreamSkinStopped {
  <#
  The stop request is written through this function because the target is a real
  JSON read-back, not a hand-built object: assigning straight to a field the file
  never carried throws "the property cannot be found", which is what aborted Full
  restore before the theme was removed or the browser was closed.
  #>
  param(
    [Parameter(Mandatory = $true)]$State,
    [Parameter(Mandatory = $true)][bool]$Stopped
  )
  $State = Set-ZCodeDreamSkinStateField -State $State -Name 'stopped' -Value $Stopped
  $State = Set-ZCodeDreamSkinStateField -State $State -Name 'updatedAt' -Value (Get-Date).ToString('o')
  return $State
}

function Find-ZCodeFreePort {
  param(
    [Parameter(Mandatory = $true)][scriptblock]$IsPortBusy,
    [int]$StartPort = 9335,
    [int]$MaxPort = 9435
  )
  for ($port = $StartPort; $port -le $MaxPort; $port++) {
    if (-not (& $IsPortBusy $port)) { return $port }
  }
  throw "E12_CDP_PORT_SEARCH_EXHAUSTED: no free CDP port between $StartPort and $MaxPort"
}

function Assert-ZCodeExplicitPortFree {
  param(
    [Parameter(Mandatory = $true)][int]$Port,
    [Parameter(Mandatory = $true)][scriptblock]$IsPortBusy,
    [scriptblock]$StopProcess = { param($p) throw 'E05_CDP_PORT_FOREIGN_OWNER: port owners are never terminated' }
  )
  if (& $IsPortBusy $Port) {
    # The owner is reported, never killed: it may be any process on the machine.
    throw "E05_CDP_PORT_FOREIGN_OWNER: port $Port is already owned by another process"
  }
  return $true
}

function Get-ZCodeDreamSkinBrowserId {
  param([Parameter(Mandatory = $true)]$State)
  $match = [regex]::Match([string]$State.browserWebSocketUrl, '/devtools/browser/([^/?]+)')
  if (-not $match.Success) {
    throw 'E13_STATE_SCHEMA_INVALID: the browser WebSocket URL does not carry a browser id'
  }
  return $match.Groups[1].Value
}

function Get-ZCodeDreamSkinLaunchAction {
  param(
    [object[]]$ProcessRows,
    $State
  )
  $zcodeRows = @($ProcessRows | Where-Object { [string]$_.Name -ieq 'ZCode.exe' })
  if ($zcodeRows.Count -eq 0) { return 'launch' }
  if ($null -ne $State) {
    $managedAlive = @($zcodeRows | Where-Object { [int]$_.ProcessId -eq [int]$State.rootPid }).Count -gt 0
    if ($managedAlive) { return 'resume' }
  }
  # Unmanaged ZCode (or a managed session whose root died): the user closes the
  # app normally. This product never force-stops a ZCode it did not launch.
  return 'request-restart'
}

function Format-ZCodeDreamSkinLogLine {
  param(
    [Parameter(Mandatory = $true)][string]$Tag,
    [Parameter(Mandatory = $true)][string]$Message
  )
  if ($script:ZCODE_DREAM_SKIN_LOG_TAGS -notcontains $Tag) {
    throw "E14_LOG_TAG_INVALID: unknown log tag $Tag"
  }
  # Log lines carry structural facts only, and are forced onto one line so a
  # hostile or accidental multi-line string cannot forge log entries.
  $single = ($Message -replace '[\r\n\t]+', ' ').Trim()
  return "[$Tag] $single"
}
