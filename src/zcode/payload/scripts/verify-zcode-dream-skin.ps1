# ZCode Dream Skin product entry: verify a running managed session — process
# identity, loopback port ownership, and the live theme contract. Read-only.
[CmdletBinding()]
param(
  [string]$StateRoot = '',
  # 'native' checks the zero-skin-node contract of a paused managed session; the
  # theme contract below stays exactly as strict as it was.
  [ValidateSet('theme', 'native')][string]$ExpectedAppearance = 'theme',
  # An operation may ask for its own report so a caller never mistakes an older
  # file for this reading. The default keeps every existing caller and location.
  [string]$ReportPath = ''
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common-windows.ps1')
. (Join-Path $PSScriptRoot 'zcode-product.ps1')

# One resolver for every installed entry point: the bundled, signature-validated
# runtime wins, and PATH is only a source-tree fallback behind the same gate.
$nodePath = (Get-DreamSkinNodeRuntime -MinimumMajor 22).Path
$root = if ($StateRoot) { Get-ZCodeDreamSkinStateRoot -StateRoot $StateRoot } else { Get-ZCodeDreamSkinStateRoot }
$state = Read-ZCodeDreamSkinState -StateRoot $root

function Write-Log([string]$Tag, [string]$Message) {
  Write-Host (Format-ZCodeDreamSkinLogLine -Tag $Tag -Message $Message)
}

try {
  if (-not $state) { throw 'E13_STATE_SCHEMA_INVALID: no managed session state exists; nothing to verify' }
  $state = ConvertFrom-ZCodeDreamSkinStateJson -Json ($state | ConvertTo-Json -Depth 4 -Compress)

  $metadata = Get-ZCodeIdentityMetadata -Path $state.zcodePath
  $null = Test-ZCodeIdentityMetadata -Metadata $metadata
  Write-Log 'PROCESS' "identity=valid rootPid=$($state.rootPid)"

  $live = Get-Process -Id ([int]$state.rootPid) -ErrorAction SilentlyContinue
  if (-not $live) { throw 'E04_ZCODE_RUNNING_WITHOUT_CDP: the managed ZCode root process is gone' }

  Assert-DreamSkinZCodePortOwnership -Port ([int]$state.port) -RootPid ([int]$state.rootPid)
  Write-Log 'PORT' "owned=$($state.port)"

  if ($ExpectedAppearance -eq 'native') {
    # A native session is still a managed one: paused, with no watcher armed. An
    # unpaused or watcher-armed state labelled native would mean the reading is
    # being inferred from an absence of nodes rather than from the session contract.
    if (-not [bool]$state.paused) {
      throw 'E13_STATE_SCHEMA_INVALID: the native appearance requires a paused managed session'
    }
    if ([int]$state.watchPid -ne 0) {
      throw "E13_STATE_SCHEMA_INVALID: a native session must arm no watcher, the state records watchPid=$($state.watchPid)"
    }
  }

  $reportTarget = if ($ReportPath) { $ReportPath } else { Join-Path $root 'last-verify-report.json' }
  & $nodePath (Join-Path $PSScriptRoot 'injector.mjs') --mode zcode-verify `
    --port $state.port --browser-id (Get-ZCodeDreamSkinBrowserId -State $state) `
    --expect-appearance $ExpectedAppearance `
    --report $reportTarget
  if ($LASTEXITCODE -ne 0) {
    if ($ExpectedAppearance -eq 'native') {
      throw 'E09_RUNTIME_EVALUATE_FAILED: skin nodes survived while the appearance was expected to be native'
    }
    throw 'E09_RUNTIME_EVALUATE_FAILED: the live theme failed verification; run restore-zcode-dream-skin.ps1 -Mode Full'
  }
  # The report is read back rather than trusted from the exit code alone: a caller
  # needs the same numbers the injector observed.
  $verifyReport = $null
  $verifyReportPath = $reportTarget
  if (Test-Path -LiteralPath $verifyReportPath -PathType Leaf) {
    try { $verifyReport = Get-Content -LiteralPath $verifyReportPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $verifyReport = $null }
  }
  if ($ExpectedAppearance -eq 'native' -and $verifyReport) {
    $observed = @($verifyReport.verify.styleCount, $verifyReport.verify.backgroundCount,
      $verifyReport.verify.overlayCount, $verifyReport.verify.taggedParts)
    if (@($observed | Where-Object { [int]$_ -ne 0 }).Count -ne 0) {
      throw "E09_RUNTIME_EVALUATE_FAILED: the native report still counts skin nodes: style=$($verifyReport.verify.styleCount) background=$($verifyReport.verify.backgroundCount) overlay=$($verifyReport.verify.overlayCount) tagged=$($verifyReport.verify.taggedParts)"
    }
  }
  Write-Log 'VERIFY' "appearance=$ExpectedAppearance compatibilityMode=$($state.compatibilityMode) themeVersion=$($state.themeVersion)"
  exit 0
} catch {
  Write-Host (Format-ZCodeDreamSkinLogLine -Tag 'ERROR' -Message ($_.Exception.Message))
  exit 1
}
