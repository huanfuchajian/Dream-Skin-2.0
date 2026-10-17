<#
ZCode Dream Skin 2.0 appearance controller.

One door for every appearance change. The tray, the gallery, the launcher and the
old command line all route through here so that the rules which actually protect
the user - one writer at a time, back up before the first write, verify with a
fresh independent reading, publish the intent only after that verification, and
never claim more than the machine proved - are stated exactly once.

The live boundaries (apply, pause, resume, verify, roll back, full) arrive as the
injected Effects set: this module orchestrates, it does not reach for a process,
a port or a CDP socket itself. The library steps (choose the active theme, publish
an immutable snapshot, import, save, draft) reach for the existing store through
$Library, whose defaults are the real functions.
#>

$script:ZCodeAppearanceActions = @(
  'list', 'status', 'theme', 'native', 'resume', 'full', 'import', 'save', 'background', 'personal-skin', 'apply-draft', 'launch'
)
# What the gallery may ask for. The TypeScript side of this pair is the GalleryAction
# union in src/main/zcode-service.ts, and a test keeps the two lists naming the same
# things: an array nobody reads is not a boundary.
$script:ZCodeAppearanceRendererActions = @('list', 'status', 'theme', 'native', 'resume', 'import', 'background', 'personal-skin')
$script:ZCodeAppearanceRequestSchema = 'zcode-dream-skin-command/1'
$script:ZCodeAppearanceResultSchema = 'zcode-dream-skin-result/1'
$script:ZCodeAppearanceTransactionName = 'appearance-transaction.json'
$script:ZCodeAppearanceTransactionMaxBytes = 65536
$script:ZCodeAppearancePhases = @(
  'prepared', 'library-selected', 'renderer-confirmed', 'preference-committed', 'finished',
  'theme-removed', 'session-cleared', 'native-relaunched'
)
$script:ZCodeAppearanceErrorCodes = @(
  'BUSY', 'INVALID_REQUEST', 'THEME_NOT_FOUND', 'THEME_CHANGED', 'PREFERENCE_INVALID',
  'IDENTITY_CONFLICT', 'APPLY_FAILED', 'VERIFY_FAILED', 'COMMIT_FAILED', 'RECOVERY_PENDING',
  'RELAUNCH_FAILED', 'ACTION_UNAVAILABLE', 'SOURCE_DECLARATION_REQUIRED', 'IMPORT_CONTENT_CHANGED',
  'PERSONAL_IMAGE_REJECTED', 'PERSONAL_SKIN_PUBLISH_FAILED'
)

function Get-ZCodeAppearanceTransactionPath {
  param([Parameter(Mandatory = $true)][string]$StateRoot)
  return Join-Path $StateRoot $script:ZCodeAppearanceTransactionName
}

function Get-ZCodeAppearanceRootLockName {
  <#
  Scoped to this user and this state root, so a second library (or another account
  on the same machine) cannot be locked out by this one. The name is a hash: the
  private path never travels into the kernel namespace.
  #>
  param([Parameter(Mandatory = $true)][string]$StateRoot)
  $normalized = [System.IO.Path]::GetFullPath($StateRoot).TrimEnd('\', '/')
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $digest = ([System.BitConverter]::ToString($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($normalized)))).Replace('-', '').ToLowerInvariant()
  } finally { $sha.Dispose() }
  $sid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
  return "Local\ZCodeDreamSkin-$($sid.Substring($sid.Length - 16))-$($digest.Substring(0, 24))"
}

function Invoke-ZCodeAppearanceLockedAction {
  <#
  WaitOne(0): a contended lock is answered with BUSY immediately rather than by
  blocking the tray's UI thread, and the body never runs, so a double click cannot
  queue a second write.
  #>
  param(
    [Parameter(Mandatory = $true)][string]$StateRoot,
    [Parameter(Mandatory = $true)][string]$Action,
    [Parameter(Mandatory = $true)][scriptblock]$Body
  )
  $mutex = New-Object System.Threading.Mutex($false, (Get-ZCodeAppearanceRootLockName -StateRoot $StateRoot))
  $acquired = $false
  try {
    $acquired = $mutex.WaitOne(0)
    if (-not $acquired) {
      return [pscustomobject]@{ ok = $false; errorCode = 'BUSY'; result = $null }
    }
    return [pscustomobject]@{ ok = $true; errorCode = $null; result = & $Body }
  } finally {
    if ($acquired) {
      $mutex.ReleaseMutex()
    }
    $mutex.Dispose()
  }
}

function Read-ZCodeAppearanceTransaction {
  param([Parameter(Mandatory = $true)][string]$StateRoot)
  $path = Get-ZCodeAppearanceTransactionPath -StateRoot $StateRoot
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    return [pscustomobject]@{ status = 'absent'; journal = $null; errorCode = $null }
  }
  $item = Get-Item -LiteralPath $path
  if ($item.Length -gt $script:ZCodeAppearanceTransactionMaxBytes) {
    return [pscustomobject]@{ status = 'invalid'; journal = $null; errorCode = 'TRANSACTION_TOO_LARGE' }
  }
  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    return [pscustomobject]@{ status = 'invalid'; journal = $null; errorCode = 'TRANSACTION_HAS_BOM' }
  }
  try {
    $journal = (ConvertFrom-Json ([System.Text.UTF8Encoding]::new($false).GetString($bytes)) -ErrorAction Stop)
  } catch {
    return [pscustomobject]@{ status = 'invalid'; journal = $null; errorCode = 'TRANSACTION_MALFORMED_JSON' }
  }
  $phase = [string]$journal.phase
  if ($script:ZCodeAppearancePhases -notcontains $phase) {
    return [pscustomobject]@{ status = 'invalid'; journal = $null; errorCode = 'TRANSACTION_PHASE_UNKNOWN' }
  }
  return [pscustomobject]@{ status = 'valid'; journal = $journal; errorCode = $null }
}

function Write-ZCodeAppearanceTransaction {
  param(
    [Parameter(Mandatory = $true)][string]$StateRoot,
    [Parameter(Mandatory = $true)]$Journal
  )
  $path = Get-ZCodeAppearanceTransactionPath -StateRoot $StateRoot
  $temp = "$path.tmp-$([guid]::NewGuid().ToString('N'))"
  $json = (ConvertTo-Json $Journal -Depth 8 -Compress)
  if ([System.Text.Encoding]::UTF8.GetByteCount($json) -gt $script:ZCodeAppearanceTransactionMaxBytes) {
    throw 'TRANSACTION_TOO_LARGE: the appearance journal exceeded 64 KiB'
  }
  try {
    [System.IO.File]::WriteAllText($temp, $json, [System.Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temp -Destination $path -Force
  } finally {
    if (Test-Path -LiteralPath $temp) {
      Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
    }
  }
  return $path
}

function Get-ZCodeAppearanceStatus {
  <#
  The shape the tray and the gallery render. confirmed only ever means "a fresh
  independent observation agreed", so a successful download or a successful file
  write cannot borrow it.
  #>
  param(
    [string]$Session = 'unknown',
    [string]$Appearance = 'pending',
    $ThemeId = $null,
    $Revision = $null,
    [bool]$Confirmed = $false,
    $ErrorCode = $null,
    [bool]$CanResume = $false,
    [bool]$Busy = $false
  )
  return [pscustomobject]@{
    session    = $Session
    appearance = $Appearance
    themeId    = $ThemeId
    revision   = $Revision
    confirmed  = $Confirmed
    errorCode  = $ErrorCode
    canResume  = $CanResume
    busy       = $Busy
  }
}

function Get-ZCodeAppearanceResult {
  param(
    [Parameter(Mandatory = $true)][string]$RequestId,
    [bool]$Ok,
    $Status,
    $Data = $null,
    $ErrorCode = $null,
    [Parameter(Mandatory = $true)][string]$Message,
    $OperationId = $null
  )
  return [pscustomobject]@{
    schemaVersion = $script:ZCodeAppearanceResultSchema
    requestId     = $RequestId
    ok            = $Ok
    status        = $Status
    data          = $Data
    errorCode     = $ErrorCode
    message       = $Message
    operationId   = $OperationId
  }
}

function Get-ZCodeCharacterLeafMatches {
  <#
  The personal skin is seeded under a stable leaf prefix; a collision may add a
  suffix, so membership is a prefix test on the leaf, never on a display name.
  #>
  param([AllowEmptyString()][string]$Key)
  return (([string]$Key) -clike 'zds2-character' -or ([string]$Key) -clike 'zds2-character-*')
}

function Get-ZCodeCharacterStateFromCards {
  <#
  One ruler for "is the fourth skin ready", used by the list answer and by the answer
  that just created it. Two copies of this rule would be two chances to disagree about
  whether the user can click the card.
  #>
  param([object[]]$Cards)
  foreach ($card in @($Cards)) {
    if (([string]$card.kind -ceq 'saved') -and (Get-ZCodeCharacterLeafMatches -Key ([string]$card.key)) -and [bool]$card.enabled) {
      return 'built'
    }
  }
  return 'awaiting-image'
}

function Get-ZCodeAppearanceRequestProblem {
  param($Request, [string]$StateRoot)
  if ($null -eq $Request) { return @('INVALID_REQUEST:EMPTY') }
  $names = @($Request.PSObject.Properties | ForEach-Object { [string]$_.Name })
  $allowed = @('schemaVersion', 'requestId', 'action', 'stateRoot', 'themeId', 'archivePath', 'name', 'imagePath', 'draftId', 'sourceFormat',
    'expectedArchiveSha256', 'expectedArchiveBytes', 'artFocusX', 'artFocusY', 'artDim')
  foreach ($extra in @($names | Where-Object { $allowed -notcontains $_ })) {
    return @("INVALID_REQUEST:UNKNOWN_FIELD:$extra")
  }
  foreach ($required in @('schemaVersion', 'requestId', 'action', 'stateRoot')) {
    if ($names -notcontains $required) { return @("INVALID_REQUEST:MISSING_FIELD:$required") }
  }
  if ([string]$Request.schemaVersion -cne $script:ZCodeAppearanceRequestSchema) {
    return @('INVALID_REQUEST:SCHEMA_VERSION')
  }
  if ([string]$Request.requestId -cnotmatch '^[0-9a-f]{32}$') {
    return @('INVALID_REQUEST:REQUEST_ID')
  }
  if ($script:ZCodeAppearanceActions -notcontains [string]$Request.action) {
    return @('INVALID_REQUEST:ACTION')
  }
  try {
    $requested = [System.IO.Path]::GetFullPath([string]$Request.stateRoot)
    $expected = [System.IO.Path]::GetFullPath($StateRoot)
  } catch {
    return @('INVALID_REQUEST:STATE_ROOT')
  }
  if ($requested.TrimEnd('\', ' ') -ine $expected.TrimEnd('\', ' ')) {
    return @('INVALID_REQUEST:STATE_ROOT_MISMATCH')
  }
  $action = [string]$Request.action
  if ($action -eq 'theme') {
    if ($names -notcontains 'themeId' -or [string]$Request.themeId -cnotmatch '^[0-9a-f]{64}$') {
      return @('INVALID_REQUEST:THEME_ID')
    }
  }
  if ($action -eq 'apply-draft') {
    if ($names -notcontains 'draftId' -or [string]$Request.draftId -cnotmatch '^[0-9a-f]{32}$') {
      return @('INVALID_REQUEST:DRAFT_ID')
    }
  }
  if ($action -eq 'import') {
    if ($names -notcontains 'archivePath' -or -not [System.IO.Path]::IsPathRooted([string]$Request.archivePath)) {
      return @('INVALID_REQUEST:ARCHIVE_PATH')
    }
    # The artwork unit is a declaration only the operator or the native import flow can
    # make. An absent field stays undeclared: the importer classifies the package before
    # it becomes a library leaf and refuses to publish an unanswered one, instead of
    # guessing a unit from how large the numbers look or filing a grey card nobody
    # agreed to.
    if ($names -contains 'sourceFormat') {
      if (@('dream-skin-v1-normalized', 'zcode-percent-v1') -notcontains [string]$Request.sourceFormat) {
        return @('INVALID_REQUEST:SOURCE_FORMAT')
      }
    }
    # The archive identity describes the bytes behind archivePath, so it is shaped here,
    # before anything reads them: a lowercase digest and a real size, or no answer at all.
    if ($names -contains 'expectedArchiveSha256') {
      if ([string]$Request.expectedArchiveSha256 -notmatch '^[0-9a-f]{64}$') {
        return @('INVALID_REQUEST:ARCHIVE_SHA256')
      }
    }
    if ($names -contains 'expectedArchiveBytes') {
      $expectedBytes = [long]0
      if (-not [long]::TryParse([string]$Request.expectedArchiveBytes, [ref]$expectedBytes) -or $expectedBytes -lt 1) {
        return @('INVALID_REQUEST:ARCHIVE_BYTES')
      }
    }
  }
  elseif ($names -contains 'sourceFormat') {
    return @('INVALID_REQUEST:SOURCE_FORMAT_NOT_ALLOWED')
  }
  elseif (($names -contains 'expectedArchiveSha256') -or ($names -contains 'expectedArchiveBytes')) {
    return @('INVALID_REQUEST:ARCHIVE_EXPECTATION_NOT_ALLOWED')
  }
  if ($action -eq 'background') {
    if ($names -notcontains 'imagePath' -or -not [System.IO.Path]::IsPathRooted([string]$Request.imagePath)) {
      return @('INVALID_REQUEST:IMAGE_PATH')
    }
  }
  if ($action -eq 'personal-skin') {
    if ($names -contains 'draftId' -and [string]$Request.draftId -cnotmatch '^[0-9a-f]{32}$') {
      return @('INVALID_REQUEST:DRAFT_ID')
    }
    # Focus is authored in the declared 0..1 unit the payload gate validates, and the
    # veil is a fraction the renderer already caps at 0.85; a number outside either is a
    # caller that guessed the unit, which is the one thing this door refuses to repair.
    # A value out of range is named as its own axis first: a caller that sent one bad
    # number deserves the reason for that number, not a complaint about the two it omitted.
    foreach ($field in @('artFocusX', 'artFocusY')) {
      if ($names -notcontains $field) { continue }
      $parsed = [double]0
      if (-not [double]::TryParse([string]$Request.$field, [ref]$parsed)) { return @('INVALID_REQUEST:ART_FOCUS') }
      if ($parsed -lt 0 -or $parsed -gt 1) { return @('INVALID_REQUEST:ART_FOCUS') }
    }
    if ($names -contains 'artDim') {
      $dim = [double]0
      if (-not [double]::TryParse([string]$Request.artDim, [ref]$dim)) { return @('INVALID_REQUEST:ART_DIM') }
      if ($dim -lt 0 -or $dim -gt 0.85) { return @('INVALID_REQUEST:ART_DIM') }
    }
    # All three or none: a half-specified composition would have to guess the missing axis
    # from the generator's default, and a guess is what this door refuses to make.
    $givenArt = @(@('artFocusX', 'artFocusY', 'artDim') | Where-Object { $names -contains $_ })
    if ($givenArt.Count -gt 0 -and $givenArt.Count -ne 3) {
      return @('INVALID_REQUEST:ART_INCOMPLETE')
    }
  }
  elseif (($names -contains 'artFocusX') -or ($names -contains 'artFocusY') -or ($names -contains 'artDim')) {
    return @('INVALID_REQUEST:ART_NOT_ALLOWED')
  }
  if ($action -eq 'save') {
    $name = [string]$Request.name
    if ($names -notcontains 'name' -or $name.Length -lt 1 -or $name.Length -gt 80) {
      return @('INVALID_REQUEST:SAVE_NAME')
    }
    foreach ($ch in $name.ToCharArray()) {
      if ([int]$ch -lt 32) { return @('INVALID_REQUEST:SAVE_NAME') }
    }
  }
  return @()
}

function Get-ZCodeDefaultAppearanceLibrary {
  <#
  The real store behind the controller's internal library steps. Each entry is a
  one-line delegation to an existing product function so the selection, snapshot
  and import rules live in exactly one place; a test replaces this object.
  #>
  return [pscustomobject]@{
    SelectActive  = { param($StateRoot, $ThemeRef) return Select-ZCodeActiveThemeRef -StateRoot $StateRoot -ThemeRef $ThemeRef }
    Publish       = { param($StateRoot, $ThemeDirectory, $ArtSourceFormat = '')
      return New-ZCodeAppearanceSnapshot -StateRoot $StateRoot -ThemeDirectory $ThemeDirectory `
        -ArtSourceFormat ([string]$ArtSourceFormat) }
    Backup        = { param($StateRoot) return New-ZCodeAppearanceLibraryBackup -StateRoot $StateRoot }
    RestoreBackup = { param($StateRoot, $Backup) return Restore-ZCodeAppearanceLibrary -StateRoot $StateRoot -Backup $Backup }
    Import        = {
      param($StateRoot, $Request)
      # Whatever the caller declared about the archive travels to the importer, which is
      # the only place that can refuse mismatched bytes before it publishes.
      $arguments = @{ StateRoot = $StateRoot; ArchivePath = [string]$Request.archivePath; SourceFormat = ([string]$Request.sourceFormat) }
      $names = @($Request.PSObject.Properties | ForEach-Object { [string]$_.Name })
      if ($names -contains 'expectedArchiveSha256') { $arguments['ExpectedArchiveSha256'] = [string]$Request.expectedArchiveSha256 }
      if ($names -contains 'expectedArchiveBytes') { $arguments['ExpectedArchiveBytes'] = [long]$Request.expectedArchiveBytes }
      return (Import-ZCodeAppearanceThemeArchive @arguments)
    }
    Save          = { param($StateRoot, $Request) return Save-ZCodeAppearanceCurrentTheme -StateRoot $StateRoot -Name $Request.name }
    Draft         = { param($StateRoot, $Request) return New-ZCodeAppearanceDraft -StateRoot $StateRoot -ImagePath $Request.imagePath }
    PersonalSkin  = { param($StateRoot, $Request) return New-ZCodePersonalSkin -StateRoot $StateRoot -Request $Request }
    ApplyDraft    = { param($StateRoot, $Request) return Resolve-ZCodeAppearanceDraft -StateRoot $StateRoot -DraftId $Request.draftId }
    List          = { param($StateRoot) return @(Get-ZCodeThemeCatalog -StateRoot $StateRoot).cards }
    # The migration path needs one honest question about the working theme: is it
    # readable and complete? Nothing is written here.
    ValidateActive = { param($StateRoot) return Select-ZCodeNativeAppearance -StateRoot $StateRoot }
  }
}

function Invoke-ZCodeAppearanceOperation {
  <#
  The single orchestration. Order is the contract: validate, lock, journal, back up,
  then and only then touch the library or the live session; verify independently
  before publishing the intent; finish the journal last. Every early exit is a
  result, not an exception, because the caller has to be able to show the user a
  Chinese sentence instead of a stack trace.
  #>
  param(
    [Parameter(Mandatory = $true)][string]$StateRoot,
    [Parameter(Mandatory = $true)]$Request,
    [Parameter(Mandatory = $true)]$Effects,
    $Catalog = $null,
    $Library = $null,
    [scriptblock]$Now = $null
  )
  if ($null -eq $Library) { $Library = Get-ZCodeDefaultAppearanceLibrary }
  $nowOf = if ($Now) { $Now } else { { return (Get-Date) } }
  if ($null -eq $Catalog) { $Catalog = Get-ZCodeThemeCatalog -StateRoot $StateRoot }

  $requestId = if ($Request -and $Request.PSObject.Properties['requestId']) { [string]$Request.requestId } else { '' }
  $problems = @(Get-ZCodeAppearanceRequestProblem -Request $Request -StateRoot $StateRoot)
  if ($problems.Count -gt 0) {
    return Get-ZCodeAppearanceResult -RequestId $requestId -Ok $false `
      -Status (Get-ZCodeAppearanceStatus -ErrorCode $problems[0] -Message '') `
      -ErrorCode 'INVALID_REQUEST' -Message ([string]($problems -join '; '))
  }

  $action = [string]$Request.action

  # The lock is held across the whole orchestration, not just probed: a mutex the
  # same thread can re-enter would otherwise report success while a second writer
  # walked in beside it.
  $inner = {
    Invoke-ZCodeAppearanceHeldOperation -StateRoot $StateRoot -Request $Request -Effects $Effects `
      -Catalog $Catalog -Library $Library -Now $nowOf
  }.GetNewClosure()
  $locked = Invoke-ZCodeAppearanceLockedAction -StateRoot $StateRoot -Action $action -Body $inner
  if (-not $locked.ok) {
    return Get-ZCodeAppearanceResult -RequestId $requestId -Ok $false `
      -Status (Get-ZCodeAppearanceStatus -Busy $true -ErrorCode 'BUSY') `
      -ErrorCode 'BUSY' -Message '另一项外观操作正在进行，请稍后重试'
  }
  return $locked.result
}

function Copy-ZCodeAppearancePreferenceEvidence {
  <#
  The damaged bytes have to survive before anything is published over them: a file the
  product cannot read is still the only copy of what the user's tooling wrote. The
  copy is read-only, bounded and named after the operation that took it, so a later
  diagnosis can say who preserved it and when.
  #>
  param(
    [Parameter(Mandatory = $true)][string]$StateRoot,
    [Parameter(Mandatory = $true)][string]$OperationId
  )
  $source = Get-ZCodeAppearancePreferencePath -StateRoot $StateRoot
  if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
    return [pscustomobject]@{ ok = $false; path = ''; errorCode = 'PREFERENCE_EVIDENCE_SOURCE_MISSING' }
  }
  $item = Get-Item -LiteralPath $source
  if ($item.Length -gt 65536) {
    return [pscustomobject]@{ ok = $false; path = ''; errorCode = 'PREFERENCE_EVIDENCE_TOO_LARGE' }
  }
  $directory = Join-Path $StateRoot 'appearance-evidence'
  $target = Join-Path $directory ('invalid-preference-' + $OperationId + '.json')
  try {
    $null = [System.IO.Directory]::CreateDirectory($directory)
    Copy-Item -LiteralPath $source -Destination $target -Force
    if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -cne
        (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash) {
      return [pscustomobject]@{ ok = $false; path = ''; errorCode = 'PREFERENCE_EVIDENCE_MISMATCH' }
    }
  } catch {
    return [pscustomobject]@{ ok = $false; path = ''; errorCode = 'PREFERENCE_EVIDENCE_WRITE_FAILED' }
  }
  return [pscustomobject]@{ ok = $true; path = $target; errorCode = $null }
}

function Invoke-ZCodeAppearanceHeldOperation {
  param(
    [Parameter(Mandatory = $true)][string]$StateRoot,
    [Parameter(Mandatory = $true)]$Request,
    [Parameter(Mandatory = $true)]$Effects,
    $Catalog,
    $Library,
    $Now
  )
  $action = [string]$Request.action
  $requestId = [string]$Request.requestId
  $operationId = [guid]::NewGuid().ToString('N')
  $startedAt = & $Now

  # --- read-only observations never need a journal or a backup -------------------
  if ($action -eq 'list' -or $action -eq 'status') {
    $snapshot = $Effects.ReadSnapshot.Invoke(
      (New-ZCodeAppearanceContext -StateRoot $StateRoot -OperationId $operationId -StartedAt $startedAt -ExpectedGeneration $null))
    $cards = $null
    $characterState = 'awaiting-image'
    if ($action -eq 'list') {
      $cards = @($Library.List.Invoke($StateRoot))
      # Whether the fourth, personal skin exists is a fact about the library, not a
      # build-time guess: an authored character leaf that is unusable does not count,
      # because the gallery may only offer it as a disabled placeholder.
      $characterState = Get-ZCodeCharacterStateFromCards -Cards $cards
    }
    $status = Get-ZCodeAppearanceObservedStatus -Snapshot $snapshot
    return Get-ZCodeAppearanceResult -RequestId $requestId -Ok $true -Status $status `
      -Data $(if ($action -eq 'list') { [pscustomobject]@{ themes = $cards; characterState = $characterState } } else { $null }) `
      -Message $(if ($action -eq 'list') { '皮肤列表已读取' } else { '外观状态已读取' }) -OperationId $operationId
  }

  # --- launching decides from the journal, then the live session, then the intent --
  if ($action -eq 'launch') {
    return Invoke-ZCodeAppearanceLaunch -StateRoot $StateRoot -Request $Request -Effects $Effects `
      -Catalog $Catalog -Library $Library -OperationId $operationId -StartedAt $startedAt
  }

  # --- library-only actions: they save, they never display -----------------------
  if ($action -in @('import', 'save', 'background', 'personal-skin')) {
    $libraryResult = Invoke-ZCodeAppearanceLibraryOnly -StateRoot $StateRoot -Action $action -Request $Request `
      -Effects $Effects -Catalog $Catalog -Library $Library -OperationId $operationId -StartedAt $startedAt
    return $libraryResult
  }

  # --- display-changing actions --------------------------------------------------
  return Invoke-ZCodeAppearanceDisplayChange -StateRoot $StateRoot -Request $Request -Effects $Effects `
    -Catalog $Catalog -Library $Library -OperationId $operationId -StartedAt $startedAt
}

function New-ZCodeAppearanceContext {
  param(
    [string]$StateRoot, [string]$OperationId, $StartedAt, $ExpectedGeneration,
    $SessionIdentity = $null, $BeforeSnapshot = $null, [string]$ArtSourceFormat = ''
  )
  return [pscustomobject]@{
    StateRoot          = $StateRoot
    OperationId        = $OperationId
    StartedAtUtc       = $(if ($StartedAt) { ([datetime]$StartedAt).ToUniversalTime().ToString('o') } else { $null })
    ExpectedGeneration = $ExpectedGeneration
    SessionIdentity    = $SessionIdentity
    BeforeSnapshot     = $BeforeSnapshot
    ArtSourceFormat    = $ArtSourceFormat
  }
}

function Get-ZCodeAppearanceObservedStatus {
  param($Snapshot)
  $appearance = 'pending'
  if ($Snapshot -and $Snapshot.appearance) { $appearance = [string]$Snapshot.appearance }
  $session = 'unknown'
  if ($Snapshot -and $Snapshot.session) { $session = [string]$Snapshot.session }
  # confirmed means "a fresh observation agreed", so it is taken as a boolean and
  # never inferred from the field merely existing: in PowerShell $false -ne $null is
  # true, which would turn every stopped session into a confirmed appearance.
  $confirmed = [bool]($Snapshot -and $Snapshot.confirmed)
  $resumeTheme = $null
  if ($Snapshot -and $Snapshot.preference -and $Snapshot.preference.resumeTheme) {
    $resumeTheme = $Snapshot.preference.resumeTheme
  }
  return Get-ZCodeAppearanceStatus `
    -Session $session `
    -Appearance $appearance `
    -ThemeId $(if ($resumeTheme) { (Get-ZCodeThemeCardId -Kind ([string]$resumeTheme.kind) -Key ([string]$resumeTheme.key)) } else { $null }) `
    -Revision $(if ($Snapshot) { [string]$Snapshot.revision } else { $null }) `
    -Confirmed $confirmed `
    -CanResume $([bool]$resumeTheme)
}

function Invoke-ZCodeAppearanceLibraryOnly {
  <#
  import/save/background touch only the saved library. The operation wrapper already
  holds the root lock, so a save cannot race an apply; these actions must not reach
  the live session, and the controller never calls ApplyTheme/Pause/Resume here.
  #>
  param($StateRoot, $Action, $Request, $Effects, $Catalog, $Library, $OperationId, $StartedAt)
  $method = if ($Action -eq 'import') { 'Import' } elseif ($Action -eq 'save') { 'Save' } `
    elseif ($Action -eq 'personal-skin') { 'PersonalSkin' } else { 'Draft' }
  $context = New-ZCodeAppearanceContext -StateRoot $StateRoot -OperationId $OperationId `
    -StartedAt $StartedAt -ExpectedGeneration $null
  # A library action that could not even start because another import holds the shared
  # import lock is a refusal to try again shortly, not a half-applied change needing
  # recovery. Letting that exception bubble made the door answer RECOVERY_PENDING for
  # something nothing had been written for, which is both the wrong code and the wrong
  # advice: the caller should wait, not reach for a backup.
  try {
    $result = $Library.$method.Invoke($context.StateRoot, $Request)
  } catch {
    $escaped = $_.Exception.Message
    if (Test-DreamSkinImportLockBusy $escaped) {
      return Get-ZCodeAppearanceResult -RequestId ([string]$Request.requestId) -Ok $false `
        -Status (Get-ZCodeAppearanceStatus -ErrorCode 'BUSY') -ErrorCode 'BUSY' `
        -Message '另一个皮肤写入正在进行，请稍后再试' -OperationId $OperationId
    }
    throw
  }
  $failureMessage = '皮肤库写入失败'
  if ([string]$result.errorCode -ceq 'BUSY') {
    # One wording for one answer, whether the library handed it back as a result or an
    # exception carried it: the person is asked to wait, not to re-check their file and
    # not to reach for a backup over something that was never started.
    $failureMessage = '另一个皮肤写入正在进行，请稍后再试'
  } elseif ($result.errorDetail) {
    $detail = (([string]$result.errorDetail) -replace '\s+', ' ')
    if ($detail.Length -gt 160) { $detail = $detail.Substring(0, 160) }
    $failureMessage = $failureMessage + '：' + $detail
  }
  if (-not $result.ok) {
    # A refusal that asks for information travels as its code; the reason is what the
    # import entry reports, and the answer is bound to content at publication time.
    return Get-ZCodeAppearanceResult -RequestId ([string]$Request.requestId) -Ok $false `
      -Status (Get-ZCodeAppearanceStatus -ErrorCode $result.errorCode) -ErrorCode $result.errorCode `
      -Message $failureMessage -OperationId $OperationId
  }
  return Get-ZCodeAppearanceResult -RequestId ([string]$Request.requestId) -Ok $true `
    -Status (Get-ZCodeAppearanceStatus -Session 'unknown' -Appearance 'pending' -Confirmed $false) `
    -Data $result.data -Message '皮肤已保存，当前外观未改变' -OperationId $OperationId
}

function Invoke-ZCodeAppearanceDisplayChange {
  <#
  theme / native / resume / apply-draft / full. The journal is opened before the
  first write, the library is backed up before the first change, and the preference
  is the last thing published - so an interrupted run can always be read as
  "what had already happened", never as a guess.
  #>
  param($StateRoot, $Request, $Effects, $Catalog, $Library, $OperationId, $StartedAt)
  $requestId = [string]$Request.requestId
  $action = [string]$Request.action

  $context = New-ZCodeAppearanceContext -StateRoot $StateRoot -OperationId $OperationId `
    -StartedAt $StartedAt -ExpectedGeneration $null
  $before = $Effects.ReadSnapshot.Invoke($context)
  if ($null -eq $before) {
    return Get-ZCodeAppearanceResult -RequestId $requestId -Ok $false `
      -Status (Get-ZCodeAppearanceStatus -ErrorCode 'PREFERENCE_INVALID') -ErrorCode 'PREFERENCE_INVALID' `
      -Message '无法读取当前外观偏好' -OperationId $OperationId
  }
  $preferenceStatus = if ($before.preferenceStatus) { [string]$before.preferenceStatus } `
    elseif ($null -ne $before.preference) { 'valid' } else { 'absent' }
  $overInvalidPreference = $false
  if ($null -eq $before.preference -and $preferenceStatus -ne 'absent') {
    $isExplicitApply = ($action -ceq 'theme' -or $action -ceq 'resume' -or $action -ceq 'apply-draft')
    $evidence = $null
    if ($isExplicitApply -and $preferenceStatus -ceq 'invalid') {
      $evidence = Copy-ZCodeAppearancePreferenceEvidence -StateRoot $StateRoot -OperationId $OperationId
      $overInvalidPreference = [bool]$evidence.ok
    }
    if (-not $overInvalidPreference) {
      return Get-ZCodeAppearanceResult -RequestId $requestId -Ok $false `
        -Status (Get-ZCodeAppearanceStatus -ErrorCode 'PREFERENCE_INVALID') -ErrorCode 'PREFERENCE_INVALID' `
        -Message $(if ($isExplicitApply) { '外观偏好文件损坏且无法保留取证副本，未做任何更改' } else { '无法读取当前外观偏好' }) `
        -OperationId $OperationId
    }
  }
  # An absent preference is the migration case: the first 2.0 record is generation 0,
  # and the compare-and-set below only succeeds while no file exists at all.
  $expectedGeneration = if ($null -ne $before.preference) { [long]$before.preference.generation } else { $null }
  $nextGeneration = if ($null -eq $expectedGeneration) { 0 } else { [long]$expectedGeneration + 1 }
  $context = New-ZCodeAppearanceContext -StateRoot $StateRoot -OperationId $OperationId -StartedAt $StartedAt `
    -ExpectedGeneration $expectedGeneration -SessionIdentity $before.identity -BeforeSnapshot $before.librarySnapshot

  $targetRef = $null
  $preAppliedDirectory = ''
  if ($action -eq 'theme' -and [bool]$Request.activeOnly) {
    # Launching onto the theme that is already the working theme: nothing to select,
    # only prove it, apply it, and record it as the confirmed intent.
    $active = $Library.ValidateActive.Invoke($StateRoot)
    if (-not $active.ok) {
      return Get-ZCodeAppearanceResult -RequestId $requestId -Ok $false `
        -Status (Get-ZCodeAppearanceStatus -ErrorCode $active.errorCode -Confirmed $false) -ErrorCode 'THEME_NOT_FOUND' `
        -Message '当前皮肤不可用' -OperationId $OperationId
    }
    $preAppliedDirectory = [string]$active.directory
  } elseif ($action -eq 'theme') {
    $resolved = Resolve-ZCodeThemeRef -StateRoot $StateRoot -ThemeId ([string]$Request.themeId) -Catalog $Catalog
    if (-not $resolved.ok) {
      return Get-ZCodeAppearanceResult -RequestId $requestId -Ok $false `
        -Status (Get-ZCodeAppearanceStatus -ErrorCode $resolved.errorCode -Confirmed $true) `
        -ErrorCode $(if ($resolved.errorCode -eq 'THEME_CHANGED') { 'THEME_CHANGED' } elseif ($resolved.errorCode -eq 'THEME_NOT_FOUND' -or $resolved.errorCode -eq 'THEME_DISABLED') { 'THEME_NOT_FOUND' } else { 'INVALID_REQUEST' }) `
        -Message '所选皮肤当前不可用' -OperationId $OperationId
    }
    $targetRef = $resolved.themeRef
  }
  if ($action -eq 'apply-draft') {
    $draft = $Library.ApplyDraft.Invoke($context.StateRoot, $Request)
    if (-not $draft.ok) {
      return Get-ZCodeAppearanceResult -RequestId $requestId -Ok $false `
        -Status (Get-ZCodeAppearanceStatus -ErrorCode $draft.errorCode -Confirmed $true) -ErrorCode $draft.errorCode `
        -Message '草稿已失效，请先切回原皮肤' -OperationId $OperationId
    }
    $preAppliedDirectory = [string]$draft.directory
    # The draft was built from the working theme and applying it already moved that
    # image into place, so there is no second selection to make: selecting again from
    # an empty reference key would be inventing a path.
    $targetRef = $null
  }
  if ($action -eq 'resume') {
    $resumeRef = $before.preference.resumeTheme
    if ($null -eq $resumeRef) {
      return Get-ZCodeAppearanceResult -RequestId $requestId -Ok $false `
        -Status (Get-ZCodeAppearanceStatus -ErrorCode 'THEME_NOT_FOUND') -ErrorCode 'THEME_NOT_FOUND' `
        -Message '没有可恢复的已确认皮肤' -OperationId $OperationId
    }
    $targetRef = $resumeRef
  }

  $backup = $Library.Backup.Invoke($context.StateRoot)
  $journal = [ordered]@{
    schemaVersion      = 'zcode-dream-skin-transaction/1'
    operationId        = $OperationId
    action             = $action
    expectedGeneration = $expectedGeneration
    beforePreference   = $before.preference
    targetPreference   = $null
    beforeThemeRef     = $before.themeRef
    targetThemeRef     = $targetRef
    managed            = $before.identity
    startedAtUtc       = $context.StartedAtUtc
    phase              = 'prepared'
    reportPaths        = @()
    backupManifest     = [string]$backup.ManifestPath
  }
  $null = Write-ZCodeAppearanceTransaction -StateRoot $StateRoot -Journal $journal

  if ($action -eq 'native') {
    return Invoke-ZCodeAppearanceNative -StateRoot $StateRoot -Request $Request -Effects $Effects `
      -Context $context -Before $before -Journal $journal -Backup $backup -NextGeneration $nextGeneration
  }
  if ($action -eq 'full') {
    return Invoke-ZCodeAppearanceFull -StateRoot $StateRoot -Request $Request -Effects $Effects `
      -Context $context -Before $before -Journal $journal -Backup $backup -NextGeneration $nextGeneration
  }
  return Invoke-ZCodeAppearanceApplyTheme -StateRoot $StateRoot -Request $Request -Effects $Effects `
    -Catalog $Catalog -Library $Library -Context $context -Before $before -Journal $journal -Backup $backup -NextGeneration $nextGeneration `
    -TargetRef $targetRef -PreAppliedDirectory $preAppliedDirectory `
    -OverInvalidPreference ([bool]$overInvalidPreference)
}

function Invoke-ZCodeAppearanceApplyTheme {
  param($StateRoot, $Request, $Effects, $Catalog, $Library, $Context, $Before, $Journal, $Backup, $TargetRef, [string]$PreAppliedDirectory = '', [long]$NextGeneration = 0, [bool]$OverInvalidPreference = $false)
  $requestId = [string]$Request.requestId
  if ($PreAppliedDirectory) {
    # The draft step already placed the chosen image in the working theme.
    $select = [pscustomobject]@{ ok = $true; themeDirectory = $PreAppliedDirectory }
  } else {
    $select = $Library.SelectActive.Invoke($StateRoot, $TargetRef)
  }
  if (-not $select.ok) {
    $Journal.phase = 'prepared'
    $null = Write-ZCodeAppearanceTransaction -StateRoot $StateRoot -Journal $Journal
    return Get-ZCodeAppearanceResult -RequestId $requestId -Ok $false `
      -Status (Get-ZCodeAppearanceStatus -ErrorCode $select.errorCode -Confirmed $true) -ErrorCode $select.errorCode `
      -Message '皮肤未能选中' -OperationId $Context.OperationId
  }
  # Selection is what learns the unit (from the snapshot's own record or the seed
  # registry), so every live boundary after it runs against a context that knows it.
  $Context = New-ZCodeAppearanceContext -StateRoot $StateRoot -OperationId $Context.OperationId `
    -StartedAt $Context.StartedAtUtc -ExpectedGeneration $Context.ExpectedGeneration `
    -SessionIdentity $Context.SessionIdentity -BeforeSnapshot $Context.BeforeSnapshot `
    -ArtSourceFormat ([string]$select.artSourceFormat)
  $Journal.phase = 'library-selected'
  $null = Write-ZCodeAppearanceTransaction -StateRoot $StateRoot -Journal $Journal

  $apply = if ([string]$Request.action -eq 'resume') {
    $Effects.Resume.Invoke($Context, $Request)
  } else {
    $Effects.ApplyTheme.Invoke($Context, $Request)
  }
  if ($apply.exitCode -ne 0) {
    return Complete-ZCodeAppearanceFailedApply -StateRoot $StateRoot -Request $Request -Effects $Effects `
      -Library $Library -Context $Context -Before $Before -Journal $Journal -Backup $Backup -Reason 'apply'
  }
  $Journal.phase = 'renderer-confirmed'
  $null = Write-ZCodeAppearanceTransaction -StateRoot $StateRoot -Journal $Journal

  $publish = $Library.Publish.Invoke($StateRoot, $select.ThemeDirectory, [string]$Context.ArtSourceFormat)
  if (-not $publish.ok) {
    return Complete-ZCodeAppearanceFailedApply -StateRoot $StateRoot -Request $Request -Effects $Effects `
      -Library $Library -Context $Context -Before $Before -Journal $Journal -Backup $Backup -Reason 'publish'
  }

  $verify = $Effects.Verify.Invoke($Context, 'theme', [string]$publish.revision)
  if (-not $verify.confirmed) {
    return Complete-ZCodeAppearanceFailedApply -StateRoot $StateRoot -Request $Request -Effects $Effects `
      -Library $Library -Context $Context -Before $Before -Journal $Journal -Backup $Backup -Reason 'verify'
  }

  $target = [pscustomobject]@{
    schemaVersion              = 'zcode-dream-skin-appearance/1'
    appearance                 = 'theme'
    resumeTheme                = $publish.themeRef
    lastConfirmedThemeRevision = [string]$publish.revision
    generation                 = $NextGeneration
  }
  $committed = Write-ZCodeAppearancePreferences -StateRoot $StateRoot -Preference $target `
    -ExpectedGeneration $Context.ExpectedGeneration `
    -AllowOverInvalidEvidencePreserved ([bool]$OverInvalidPreference)
  if (-not $committed.ok) {
    # The screen already shows the new skin; publishing the intent failed. That is
    # COMMIT_FAILED and a provable roll-back, never a silent success.
    $rollback = $Effects.Rollback.Invoke($Context, $Before)
    $rolledBack = [bool]$rollback.confirmed
    # A disk whose preference is unreadable is a different problem from "the publish
    # itself failed": the first needs the user to know their file is damaged, the
    # second is a transaction that did not commit.
    $commitCode = if (([string]$committed.errorCode) -like 'PREFERENCE_INVALID_ON_DISK*') { 'PREFERENCE_INVALID' } else { 'COMMIT_FAILED' }
    if ($rolledBack) {
      $null = $Library.RestoreBackup.Invoke($StateRoot, $Backup)
    }
    $Journal.phase = 'prepared'
    $null = Write-ZCodeAppearanceTransaction -StateRoot $StateRoot -Journal $Journal
    return Get-ZCodeAppearanceResult -RequestId $requestId -Ok $false `
      -Status (Get-ZCodeAppearanceStatus -Session 'managed' -Appearance $(if ($rolledBack) { 'native' } else { 'pending' }) `
        -Confirmed $rolledBack -ErrorCode $commitCode) `
      -ErrorCode $commitCode `
      -Message $(if ($rolledBack) { '外观偏好写入失败，已回到此前确认的皮肤' } else { '外观状态待确认' }) `
      -OperationId $Context.OperationId
  }
  $Journal.phase = 'preference-committed'
  $Journal.targetPreference = $target
  $Journal.reportPaths = @([string]$apply.productReportPath)
  $null = Write-ZCodeAppearanceTransaction -StateRoot $StateRoot -Journal $Journal
  $Journal.phase = 'finished'
  $null = Write-ZCodeAppearanceTransaction -StateRoot $StateRoot -Journal $Journal

  return Get-ZCodeAppearanceResult -RequestId $requestId -Ok $true `
    -Status (Get-ZCodeAppearanceStatus -Session 'managed' -Appearance 'theme' `
      -ThemeId (Get-ZCodeThemeCardId -Kind 'snapshot' -Key ([string]$publish.themeRef.key)) `
      -Revision ([string]$publish.revision) -Confirmed $true -CanResume $true) `
    -Message '皮肤已应用' -OperationId $Context.OperationId
}

function Complete-ZCodeAppearanceFailedApply {
  param($StateRoot, $Request, $Effects, $Library, $Context, $Before, $Journal, $Backup, [string]$Reason)
  $requestId = [string]$Request.requestId
  $rollback = $Effects.Rollback.Invoke($Context, $Before)
  $restored = $false
  if ([bool]$rollback.confirmed) {
    $restore = $Library.RestoreBackup.Invoke($StateRoot, $Backup)
    $restored = [bool]$restore.ok
  }
  $rollbackRevision = ''
  if ([string]$Before.appearance -cne 'native') { $rollbackRevision = [string]$Before.revision }
  $verified = $Effects.Verify.Invoke($Context, [string]$Before.appearance, $rollbackRevision)
  $confirmed = [bool]($restored -and $verified.confirmed)
  $Journal.phase = 'prepared'
  $null = Write-ZCodeAppearanceTransaction -StateRoot $StateRoot -Journal $Journal
  $code = $(if ($Reason -eq 'verify') { 'VERIFY_FAILED' } elseif (-not $confirmed) { 'RECOVERY_PENDING' } else { 'APPLY_FAILED' })
  return Get-ZCodeAppearanceResult -RequestId $requestId -Ok $false `
    -Status (Get-ZCodeAppearanceStatus -Session 'managed' `
      -Appearance $(if ($confirmed) { [string]$Before.appearance } else { 'pending' }) `
      -Revision [string]$Before.revision -Confirmed $confirmed -ErrorCode $code) `
    -ErrorCode $code `
    -Message $(if ($confirmed) { '本次变更未完成，已回到此前确认的外观' } else { '外观状态待确认' }) `
    -OperationId $Context.OperationId
}

function Invoke-ZCodeAppearanceNative {
  param($StateRoot, $Request, $Effects, $Context, $Before, $Journal, $Backup, [long]$NextGeneration = 0)
  $requestId = [string]$Request.requestId
  $pause = $Effects.Pause.Invoke($Context, $Request)
  if ($pause.exitCode -ne 0) {
    $Journal.phase = 'prepared'
    $null = Write-ZCodeAppearanceTransaction -StateRoot $StateRoot -Journal $Journal
    return Get-ZCodeAppearanceResult -RequestId $requestId -Ok $false `
      -Status (Get-ZCodeAppearanceStatus -Session 'managed' -Appearance 'pending' -Confirmed $false -ErrorCode 'APPLY_FAILED') `
      -ErrorCode 'APPLY_FAILED' -Message '切换到默认外观失败' -OperationId $Context.OperationId
  }
  # A native session has no skin revision to match: handing it the previous theme's revision
  # would compare the default appearance against a value that is legitimately absent.
  $verify = $Effects.Verify.Invoke($Context, 'native', '')
  if (-not $verify.confirmed) {
    # paused=true may have landed while the live removal failed: the screen still
    # shows a skin, so the answer is pending, never "default".
    $Journal.phase = 'prepared'
    $null = Write-ZCodeAppearanceTransaction -StateRoot $StateRoot -Journal $Journal
    return Get-ZCodeAppearanceResult -RequestId $requestId -Ok $false `
      -Status (Get-ZCodeAppearanceStatus -Session 'managed' -Appearance 'pending' -Confirmed $false -ErrorCode 'VERIFY_FAILED') `
      -ErrorCode 'VERIFY_FAILED' -Message '外观状态待确认' -OperationId $Context.OperationId
  }
  $Journal.phase = 'renderer-confirmed'
  $null = Write-ZCodeAppearanceTransaction -StateRoot $StateRoot -Journal $Journal

  # Choosing the default appearance keeps the resume reference: the user asked for
  # a plain window now, not for their skin to be forgotten.
  $target = [pscustomobject]@{
    schemaVersion              = 'zcode-dream-skin-appearance/1'
    appearance                 = 'native'
    resumeTheme                = $(if ($Before.preference) { $Before.preference.resumeTheme } else { $null })
    lastConfirmedThemeRevision = [string]$Before.lastConfirmedThemeRevision
    generation                 = $NextGeneration
  }
  $committed = Write-ZCodeAppearancePreferences -StateRoot $StateRoot -Preference $target -ExpectedGeneration $Context.ExpectedGeneration
  if (-not $committed.ok) {
    $Journal.phase = 'prepared'
    $null = Write-ZCodeAppearanceTransaction -StateRoot $StateRoot -Journal $Journal
    return Get-ZCodeAppearanceResult -RequestId $requestId -Ok $false `
      -Status (Get-ZCodeAppearanceStatus -Session 'managed' -Appearance 'pending' -Confirmed $false -ErrorCode 'COMMIT_FAILED') `
      -ErrorCode 'COMMIT_FAILED' -Message '外观偏好写入失败' -OperationId $Context.OperationId
  }
  $Journal.phase = 'preference-committed'
  $Journal.targetPreference = $target
  $null = Write-ZCodeAppearanceTransaction -StateRoot $StateRoot -Journal $Journal
  $Journal.phase = 'finished'
  $null = Write-ZCodeAppearanceTransaction -StateRoot $StateRoot -Journal $Journal
  return Get-ZCodeAppearanceResult -RequestId $requestId -Ok $true `
    -Status (Get-ZCodeAppearanceStatus -Session 'managed' -Appearance 'native' -Revision ([string]$Before.revision) `
      -Confirmed $true -CanResume $([bool]$Before.preference.resumeTheme)) `
    -Message '已切到默认外观' -OperationId $Context.OperationId
}

function Invoke-ZCodeAppearanceFull {
  param($StateRoot, $Request, $Effects, $Context, $Before, $Journal, $Backup, [long]$NextGeneration = 0)
  $requestId = [string]$Request.requestId
  if (-not $Effects.PSObject.Properties['Full']) {
    return Get-ZCodeAppearanceResult -RequestId $requestId -Ok $false `
      -Status (Get-ZCodeAppearanceStatus -ErrorCode 'ACTION_UNAVAILABLE') -ErrorCode 'ACTION_UNAVAILABLE' `
      -Message 'the full restore seam is not wired yet' -OperationId $Context.OperationId
  }
  $full = $Effects.Full.Invoke($Context, $Request)
  if ($null -eq $full) {
    return Get-ZCodeAppearanceResult -RequestId $requestId -Ok $false `
      -Status (Get-ZCodeAppearanceStatus -ErrorCode 'ACTION_UNAVAILABLE') -ErrorCode 'ACTION_UNAVAILABLE' `
      -Message '完整恢复由 P2 的启动器接线' -OperationId $Context.OperationId
  }
  $cleared = [bool]$full.sessionCleared
  $relaunched = [bool]$full.relaunched
  if (-not $cleared) {
    $Journal.phase = 'theme-removed'
    $null = Write-ZCodeAppearanceTransaction -StateRoot $StateRoot -Journal $Journal
    return Get-ZCodeAppearanceResult -RequestId $requestId -Ok $false `
      -Status (Get-ZCodeAppearanceStatus -Session 'unknown' -Appearance 'pending' -Confirmed $false -ErrorCode 'APPLY_FAILED') `
      -ErrorCode 'APPLY_FAILED' -Message '受管会话未释放，外观状态待确认' -OperationId $Context.OperationId
  }
  $Journal.phase = 'session-cleared'
  $null = Write-ZCodeAppearanceTransaction -StateRoot $StateRoot -Journal $Journal

  $target = [pscustomobject]@{
    schemaVersion              = 'zcode-dream-skin-appearance/1'
    appearance                 = 'native'
    resumeTheme                = $(if ($Before.preference) { $Before.preference.resumeTheme } else { $null })
    lastConfirmedThemeRevision = [string]$Before.lastConfirmedThemeRevision
    generation                 = $NextGeneration
  }
  $committed = Write-ZCodeAppearancePreferences -StateRoot $StateRoot -Preference $target -ExpectedGeneration $Context.ExpectedGeneration
  if (-not $committed.ok) {
    return Get-ZCodeAppearanceResult -RequestId $requestId -Ok $false `
      -Status (Get-ZCodeAppearanceStatus -Session 'stopped' -Appearance 'pending' -Confirmed $false -ErrorCode 'COMMIT_FAILED') `
      -ErrorCode 'COMMIT_FAILED' -Message '外观偏好写入失败' -OperationId $Context.OperationId
  }
  $Journal.phase = 'preference-committed'
  $Journal.targetPreference = $target
  $null = Write-ZCodeAppearanceTransaction -StateRoot $StateRoot -Journal $Journal
  if (-not $relaunched) {
    # The skin really is gone and the preference really says native; only the
    # ordinary relaunch failed. Saying RELAUNCH_FAILED keeps the two facts apart.
    return Get-ZCodeAppearanceResult -RequestId $requestId -Ok $false `
      -Status (Get-ZCodeAppearanceStatus -Session 'stopped' -Appearance 'native' -Confirmed $true -ErrorCode 'RELAUNCH_FAILED') `
      -ErrorCode 'RELAUNCH_FAILED' -Message '皮肤已移除，普通窗口未能自动重开' -OperationId $Context.OperationId
  }
  $Journal.phase = 'native-relaunched'
  $null = Write-ZCodeAppearanceTransaction -StateRoot $StateRoot -Journal $Journal
  $Journal.phase = 'finished'
  $null = Write-ZCodeAppearanceTransaction -StateRoot $StateRoot -Journal $Journal
  return Get-ZCodeAppearanceResult -RequestId $requestId -Ok $true `
    -Status (Get-ZCodeAppearanceStatus -Session 'stopped' -Appearance 'native' -Confirmed $true `
      -CanResume $([bool]$Before.preference.resumeTheme)) `
    -Message '已完整恢复官方外观' -OperationId $Context.OperationId
}

function Resolve-ZCodeAppearancePendingJournal {
  <#
  What an interrupted run means now. The phases are ordered, so the reading is:
  a finished journal is history; a committed one whose generation is exactly what
  the disk shows only needs its last phase written; a disk that moved further ahead
  belongs to a newer user choice and is never rolled back; anything else is an
  honest needs-recovery, which the tray shows as an unconfirmed appearance.
  #>
  param([Parameter(Mandatory = $true)][string]$StateRoot)
  $read = Read-ZCodeAppearanceTransaction -StateRoot $StateRoot
  if ($read.status -eq 'absent') {
    return [pscustomobject]@{ verdict = 'nothing'; journal = $null; errorCode = $null }
  }
  if ($read.status -eq 'invalid') {
    return [pscustomobject]@{ verdict = 'pending'; journal = $null; errorCode = $read.errorCode }
  }
  $journal = $read.journal
  if ([string]$journal.phase -eq 'finished') {
    return [pscustomobject]@{ verdict = 'complete'; journal = $journal; errorCode = $null }
  }
  $preference = Read-ZCodeAppearancePreferences -StateRoot $StateRoot
  $generation = if ($preference.status -eq 'valid') { [long]$preference.preference.generation } else { -1 }
  $target = $journal.targetPreference
  $intendedGeneration = if ($null -ne $target) { [long]$target.generation } else { ([long]$journal.expectedGeneration + 1) }
  if ($generation -gt $intendedGeneration) {
    return [pscustomobject]@{ verdict = 'superseded'; journal = $journal; errorCode = $null }
  }
  if ([string]$journal.phase -eq 'preference-committed' -and $null -ne $target -and
      $preference.status -eq 'valid' -and $generation -eq $intendedGeneration -and
      [string]$preference.preference.appearance -ceq [string]$target.appearance) {
    return [pscustomobject]@{ verdict = 'finalize'; journal = $journal; errorCode = $null }
  }
  return [pscustomobject]@{ verdict = 'needs-recovery'; journal = $journal; errorCode = $null }
}

function Invoke-ZCodeAppearanceLaunch {
  <#
  The unified entry's decision, in one place: an unfinished transaction is honoured
  before anything is applied, a live managed window is only observed (clicking the
  entry twice must never re-apply or silently flip the user's newer choice), and a
  cold start follows the recorded intent. An unreadable preference file starts the
  official appearance and says so - it is never deleted and never guessed around.
  #>
  param($StateRoot, $Request, $Effects, $Catalog, $Library, $OperationId, $StartedAt)
  $requestId = [string]$Request.requestId

  $pending = Resolve-ZCodeAppearancePendingJournal -StateRoot $StateRoot
  if ($pending.verdict -eq 'needs-recovery' -or $pending.verdict -eq 'pending') {
    return Get-ZCodeAppearanceResult -RequestId $requestId -Ok $false `
      -Status (Get-ZCodeAppearanceStatus -Session 'unknown' -Appearance 'pending' -Confirmed $false `
        -ErrorCode $(if ($pending.errorCode) { 'PREFERENCE_INVALID' } else { 'RECOVERY_PENDING' })) `
      -ErrorCode $(if ($pending.errorCode) { 'PREFERENCE_INVALID' } else { 'RECOVERY_PENDING' }) `
      -Message '上次外观操作未完成，当前状态待确认' -OperationId $OperationId
  }
  if ($pending.verdict -eq 'finalize') {
    # The intent is already on disk; only the last phase was never written. Closing
    # it out is bookkeeping, not a new change.
    $pending.journal.phase = 'finished'
    $null = Write-ZCodeAppearanceTransaction -StateRoot $StateRoot -Journal $pending.journal
  }

  $context = New-ZCodeAppearanceContext -StateRoot $StateRoot -OperationId $OperationId `
    -StartedAt $StartedAt -ExpectedGeneration $null
  $before = $Effects.ReadSnapshot.Invoke($context)
  if ($before -and $before.session -eq 'managed') {
    return Get-ZCodeAppearanceResult -RequestId $requestId -Ok $true `
      -Status (Get-ZCodeAppearanceObservedStatus -Snapshot $before) `
      -Message '已有受管窗口，本次只读取状态，未重复应用' -OperationId $OperationId
  }

  $preferenceStatus = if ($before -and $before.preferenceStatus) { [string]$before.preferenceStatus } else { 'absent' }
  $preference = if ($before) { $before.preference } else { $null }

  if ($preferenceStatus -eq 'invalid') {
    $nativeResult = Invoke-ZCodeAppearanceNativeLaunch -StateRoot $StateRoot -Request $Request -Effects $Effects `
      -Context $context -Reason 'invalid'
    if ($nativeResult.ok) {
      return Get-ZCodeAppearanceResult -RequestId $requestId -Ok $true `
        -Status $nativeResult.status -ErrorCode 'PREFERENCE_INVALID' `
        -Message '外观偏好文件无法读取，本次以官方默认外观启动；原文件已保留' -OperationId $OperationId
    }
    return $nativeResult
  }

  if ($preferenceStatus -eq 'valid' -and [string]$preference.appearance -ceq 'theme' -and $null -ne $preference.resumeTheme) {
    # Remembering a skin means applying the confirmed content again through the same
    # verified chain; nothing is invented and the reference is re-snapshotted.
    $themeRequest = New-ZCodeAppearanceLaunchThemeRequest -Request $Request -Preference $preference
    $display = Invoke-ZCodeAppearanceDisplayChange -StateRoot $StateRoot -Request $themeRequest -Effects $Effects `
      -Catalog $Catalog -Library $Library -OperationId $OperationId -StartedAt $StartedAt
    if ($display.ok) {
      $display.message = '已恢复上次确认的皮肤'
    }
    return $display
  }

  if ($preferenceStatus -eq 'absent') {
    # First 2.0 start on an existing library: keep the pre-2.0 behaviour when the
    # working theme is actually valid, and record it as the confirmed intent. A
    # damaged private image must not block the official appearance.
    $active = $Library.ValidateActive.Invoke($StateRoot)
    if ($active.ok) {
      $themeRequest = New-ZCodeAppearanceLaunchThemeRequest -Request $Request -ActiveOnly
      $display = Invoke-ZCodeAppearanceDisplayChange -StateRoot $StateRoot -Request $themeRequest -Effects $Effects `
        -Catalog $Catalog -Library $Library -OperationId $OperationId -StartedAt $StartedAt
      if ($display.ok) {
        $display.message = '已按当前皮肤启动，并记为下次的外观'
        return $display
      }
      $fallback = Invoke-ZCodeAppearanceNativeLaunch -StateRoot $StateRoot -Request $Request -Effects $Effects `
        -Context $context -Reason 'theme-failed'
      return $fallback
    }
    return (Invoke-ZCodeAppearanceNativeLaunch -StateRoot $StateRoot -Request $Request -Effects $Effects `
      -Context $context -Reason 'no-preference')
  }

  return (Invoke-ZCodeAppearanceNativeLaunch -StateRoot $StateRoot -Request $Request -Effects $Effects `
    -Context $context -Reason 'native')
}

function New-ZCodeAppearanceLaunchThemeRequest {
  <#
  A launch that ends in a skin still has to name a target, and the only honest target
  is the reference the user confirmed. The copy carries the same request identity so
  the result can be matched to the caller's request.
  #>
  param($Request, $Preference, [switch]$ActiveOnly)
  $themeId = $null
  if (-not $ActiveOnly) {
    $themeId = (Get-ZCodeThemeCardId -Kind ([string]$Preference.resumeTheme.kind) -Key ([string]$Preference.resumeTheme.key))
  }
  return [pscustomobject]@{
    schemaVersion = $script:ZCodeAppearanceRequestSchema
    requestId     = [string]$Request.requestId
    action        = 'theme'
    stateRoot     = [string]$Request.stateRoot
    themeId       = $themeId
    activeOnly    = [bool]$ActiveOnly
  }
}

function Invoke-ZCodeAppearanceNativeLaunch {
  param($StateRoot, $Request, $Effects, $Context, [string]$Reason)
  $requestId = [string]$Request.requestId
  if (-not $Effects.PSObject.Properties['Launch']) {
    return Get-ZCodeAppearanceResult -RequestId $requestId -Ok $false `
      -Status (Get-ZCodeAppearanceStatus -ErrorCode 'ACTION_UNAVAILABLE') -ErrorCode 'ACTION_UNAVAILABLE' `
      -Message 'the launch seam is not wired'
  }
  $launch = $Effects.Launch.Invoke($Context, 'native')
  if ($null -eq $launch -or [int]$launch.exitCode -ne 0) {
    return Get-ZCodeAppearanceResult -RequestId $requestId -Ok $false `
      -Status (Get-ZCodeAppearanceStatus -Session 'unknown' -Appearance 'pending' -Confirmed $false -ErrorCode 'APPLY_FAILED') `
      -ErrorCode 'APPLY_FAILED' -Message '默认外观未能启动'
  }
  $verify = $Effects.Verify.Invoke($Context, 'native', '')
  if (-not [bool]$verify.confirmed) {
    return Get-ZCodeAppearanceResult -RequestId $requestId -Ok $false `
      -Status (Get-ZCodeAppearanceStatus -Session 'managed' -Appearance 'pending' -Confirmed $false -ErrorCode 'VERIFY_FAILED') `
      -ErrorCode 'VERIFY_FAILED' -Message '默认外观状态待确认'
  }
  $status = Get-ZCodeAppearanceStatus -Session 'managed' -Appearance 'native' -Confirmed $true `
    -CanResume $(if ($Reason -eq 'invalid') { $false } else { $true })
  return [pscustomobject]@{ ok = $true; status = $status; reason = $Reason }
}
