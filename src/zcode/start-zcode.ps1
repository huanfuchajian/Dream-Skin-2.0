# ZCode Dream Skin product entry: launch a verified ZCode with loopback CDP,
# apply the theme through the compatibility gate, persist the product state and
# start the lifecycle watch. No ZCode process is ever force-stopped here.
#
# Two records, two meanings:
#   launch-transaction.json  this launch happened and may still need to be undone
#   state.json               an ACTIVE themed session with a running watcher
# The transaction is written before the process starts and is cleared only once the
# active state owns the session, so a failure in between is recoverable even though
# no state exists yet. A failed start rolls back (closes only the instance the
# transaction can prove it owns), writes last-startup-report.json, and still exits 1.
[CmdletBinding()]
param(
  [int]$Port = 0,
  [string]$ZCodePath = '',
  [string]$CautionFile = '',
  [string]$ArtPath = '',
  [string]$ThemePath = '',
  [string]$StateRoot = '',
  [ValidateSet('native', 'theme')][string]$InitialAppearance = 'theme',
  [int]$StartupTimeoutSeconds = 120
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common-windows.ps1')
. (Join-Path $PSScriptRoot 'theme-windows.ps1')
. (Join-Path $PSScriptRoot 'zcode-product.ps1')
. (Join-Path $PSScriptRoot 'zcode-startup.ps1')
. (Join-Path $PSScriptRoot 'zcode-theme-store.ps1')

function Assert-ZCodeThemeApplicationReport {
  <#
  A zero exit code from the apply CLI is not proof that a theme landed: the report
  is the only evidence, and it must belong to THIS launch. The mode that may
  activate a session, the three independently verified nodes, the decoration-layer
  pointer-events contract and this run's browser identity and port are all checked
  here. Anything else throws E09 so the existing launch transaction rolls the
  instance back instead of writing an active state over an unskinned window.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]$Report,
    [Parameter(Mandatory = $true)][string]$BrowserId,
    [Parameter(Mandatory = $true)][int]$Port
  )
  $problems = [System.Collections.Generic.List[string]]::new()
  if ([string]$Report.mode -cne 'zcode-apply') { $problems.Add("mode=$($Report.mode)") }
  # An explicit boolean: a truthy string must never stand in for a verified apply.
  if ($Report.applied -isnot [bool] -or -not $Report.applied) { $problems.Add("applied=$($Report.applied)") }
  if ([string]$Report.failureStage) { $problems.Add("failureStage=$($Report.failureStage)") }
  if (@($Report.errors).Count -gt 0) { $problems.Add("errors=$(@($Report.errors) -join ' | ')") }
  if (@('full', 'safe') -notcontains [string]$Report.compatibilityMode) {
    $problems.Add("compatibilityMode=$($Report.compatibilityMode)")
  }
  if ([int]$Report.port -ne $Port) { $problems.Add("port=$($Report.port) (this launch owns $Port)") }
  if ([string]$Report.browserId -cne $BrowserId) { $problems.Add('browserId does not belong to this session') }
  $verify = $Report.verify
  foreach ($field in @('styleCount', 'backgroundCount', 'overlayCount')) {
    if ([int]$verify.$field -ne 1) { $problems.Add("$field=$($verify.$field)") }
  }
  foreach ($layer in @('background', 'overlay')) {
    if ([string]$verify."${layer}PointerEvents" -cne 'none') { $problems.Add("$layer pointer-events is not none") }
  }
  if ([string]$verify.mode -cne [string]$Report.compatibilityMode) {
    $problems.Add("verified document mode=$($verify.mode)")
  }
  if ($problems.Count -gt 0) {
    throw "E09_RUNTIME_EVALUATE_FAILED: the apply report does not verify this launch ($($problems -join '; '))"
  }
  return $true
}

function Invoke-ZCodeDreamSkinStart {
  <#
  The whole launch flow with every machine touch as a seam, so the orchestration is
  testable without launching ZCode. Returns @{ ExitCode; Report; Rollback }.
  #>
  [CmdletBinding()]
  param(
    [int]$Port = 0,
    [string]$ZCodePath = '',
    [string]$CautionFile = '',
    [string]$ArtPath = '',
    [string]$ThemePath = '',
    [string]$StateRoot = '',
    # 'native' cold-starts a managed session that shows the official appearance and
    # arms nothing: no restart, no flash of skin, and a resume that only has to
    # unlock. It governs a cold launch only; switching a live session to default is
    # the controller's native action.
    [ValidateSet('native', 'theme')][string]$InitialAppearance = 'theme',
    # Passed straight to the injector so it can convert a package's 0-1 focus into the
    # percent the renderer expects. Empty keeps the historical behaviour exactly: values
    # are used as written, which is what the pre-2.0 private library stores.
    [ValidateSet('', 'dream-skin-v1-normalized', 'zcode-percent-v1')]
    [string]$ArtSourceFormat = '',
    [int]$StartupTimeoutSeconds = 120,
    # --- injectable seams; $null means "run the real thing" ----------------------
    [scriptblock]$GetProcessRows = $null,
    [scriptblock]$ResolveExecutable = $null,
    [scriptblock]$AssertIdentity = $null,
    [scriptblock]$GetFingerprint = $null,
    [scriptblock]$Launch = $null,
    [scriptblock]$ResolveMainProcess = $null,
    [scriptblock]$WaitForCdpIdentity = $null,
    [scriptblock]$InvokeApply = $null,
    [scriptblock]$VerifyAppearance = $null,
    [scriptblock]$StartWatch = $null,
    [scriptblock]$StopWatch = $null,
    # --- forwarded to the launch rollback ---------------------------------------
    [scriptblock]$ValidateOwner = $null,
    [scriptblock]$RollbackRemoveTheme = $null,
    [scriptblock]$RollbackCloseBrowser = $null,
    [scriptblock]$RollbackCloseWindow = $null,
    [scriptblock]$RollbackStopWatch = $null,
    [scriptblock]$RollbackObserveCleanup = $null,
    [scriptblock]$Now = $null,
    [scriptblock]$Sleep = $null
  )

  $root = if ($StateRoot) { Get-ZCodeDreamSkinStateRoot -StateRoot $StateRoot } else { Get-ZCodeDreamSkinStateRoot }
  $statePath = Join-Path $root 'state.json'
  # One resolver for every installed entry point: the bundled, signature-validated
# runtime wins, and PATH is only a source-tree fallback behind the same gate.
$nodePath = (Get-DreamSkinNodeRuntime -MinimumMajor 22).Path
  function Write-Log([string]$Tag, [string]$Message) {
    Write-Host (Format-ZCodeDreamSkinLogLine -Tag $Tag -Message $Message)
  }

  $rowsOf = if ($GetProcessRows) { $GetProcessRows } else { { @(Get-ZCodeProcessSnapshot) } }
  $resolveOf = if ($ResolveExecutable) { $ResolveExecutable } else {
    {
      param($ConfiguredPath)
      # Explicit -ZCodePath, then the installer marker's verified candidate, then
      # discovery - one shared resolver, and a broken marker is a hard E13 rather
      # than a silent switch to another instance. Whatever comes back is a
      # candidate only: the identity gate below re-validates it.
      Resolve-ZCodeDreamSkinExecutable -StateRoot $root -ExplicitPath $ConfiguredPath
    }
  }
  $identityOf = if ($AssertIdentity) { $AssertIdentity } else { { param($Path) Assert-DreamSkinZCodeIdentity -Path $Path } }
  $fingerprintOf = if ($GetFingerprint) { $GetFingerprint } else { { param($Path) Get-ZCodeFingerprint -Path $Path } }
  $launchOf = if ($Launch) { $Launch } else { { param($Path, $Arguments) Start-Process -FilePath $Path -ArgumentList $Arguments -PassThru } }
  $mainOf = if ($ResolveMainProcess) { $ResolveMainProcess } else {
    {
      param($ProcessRows, $LaunchedPid, $LaunchedProcessExited, $PreExistingProcessIds, $VerifiedExecutablePath)
      Resolve-ZCodeMainProcess -ProcessRows $ProcessRows -LaunchedPid $LaunchedPid `
        -LaunchedProcessExited $LaunchedProcessExited `
        -PreExistingProcessIds $PreExistingProcessIds `
        -VerifiedExecutablePath $VerifiedExecutablePath
    }
  }
  $cdpOf = if ($WaitForCdpIdentity) { $WaitForCdpIdentity } else {
    {
      param($Port_, $TimeoutSeconds)
      $deadline = (Get-Date).AddSeconds([Math]::Max(10, $TimeoutSeconds))
      $identity = $null
      while ((Get-Date) -lt $deadline -and -not $identity) {
        $identity = Get-DreamSkinCdpBrowserIdentity -Port $Port_
        if (-not $identity) { Start-Sleep -Milliseconds 500 }
      }
      $identity
    }
  }
  $applyOf = if ($InvokeApply) { $InvokeApply } else {
    {
      param($Arguments, $StateRoot_)
      & $nodePath @Arguments
      @{ exitCode = [int]$LASTEXITCODE }
    }
  }
  $verifyOf = if ($VerifyAppearance) { $VerifyAppearance } else {
    {
      param($Arguments, $StateRoot_)
      & $nodePath @Arguments
      @{ exitCode = [int]$LASTEXITCODE }
    }
  }
  $watchOf = if ($StartWatch) { $StartWatch } else {
    { param($Arguments) Start-Process -FilePath $nodePath -ArgumentList $Arguments -WindowStyle Hidden -PassThru }
  }
  $stopWatchOf = if ($StopWatch) { $StopWatch } else {
    {
      param($State, $StateRoot_)
      # The restore path's watcher stop: identity-verified (exact injector path,
      # zcode-watch mode, this state file), so a reused PID is never stopped.
      Stop-ZCodeManagedWatch -State $State -StateRoot $StateRoot_ `
        -InjectorPath (Join-Path $PSScriptRoot 'injector.mjs') -NodePath $nodePath
    }
  }
  $nowOf = if ($Now) { $Now } else { { Get-Date } }
  $sleepOf = if ($Sleep) { $Sleep } else { { param($Ms) Start-Sleep -Milliseconds $Ms } }

  $report = [ordered]@{
    mode                  = 'zcode-start'
    startedAt             = (& $nowOf).ToString('o')
    finishedAt            = ''
    phase                 = ''
    zcodePath             = ''
    fileVersion           = ''
    port                  = 0
    launchedPid           = 0
    rootPid               = 0
    browserId             = ''
    watchPid              = 0
    transactionPath       = (Get-ZCodeLaunchTransactionPath -StateRoot $root)
    previousTransaction   = ''
    primaryError          = ''
    rollback              = $null
    errors                = @()
  }
  $transaction = $null
  try {
    $existingState = Read-ZCodeDreamSkinState -StateRoot $root
    $processRows = @(& $rowsOf)
    $action = Get-ZCodeDreamSkinLaunchAction -ProcessRows $processRows -State $existingState
    Write-Log 'LAUNCH' "action=$action"

    if ($action -eq 'request-restart') {
      throw 'E04_ZCODE_RUNNING_WITHOUT_CDP: ZCode is already running. Close it normally (save your work), then start ZCode Dream Skin again.'
    }

    # default, explicit -ArtPath/-ThemePath as an override.
    # A native cold launch never resolves theme inputs at all: a damaged private
    # image must not be able to block the official appearance from starting.
    $themeArguments = @()
    if ($action -ne 'launch' -or $InitialAppearance -eq 'theme') {
      $themeArguments = @(Get-ZCodeDreamSkinThemeArguments -SkillRoot (Split-Path -Parent $PSScriptRoot) `
        -StateRoot $root -ArtPath $ArtPath -ThemePath $ThemePath -ArtSourceFormat $ArtSourceFormat)
    }
    if ($action -eq 'resume' -and -not $Port) {
      # A managed session is still alive. Reapply instead of stacking a second one:
      # the active theme may have changed since this session started, so the theme
      # is re-applied through the verified gate and the watcher is re-armed with the
      # SAME browser/port identity. Pause is preserved: a paused session is left
      # paused and is never injected into.
      $session = $existingState
      $sessionBrowserId = Get-ZCodeDreamSkinBrowserId -State $session
      $report.rootPid = [int]$session.rootPid
      $report.port = [int]$session.port
      $report.browserId = $sessionBrowserId
      if ($session.paused) {
        Write-Log 'RESTORE' 'the managed session is paused; reapply left it paused and injected nothing'
        $report.finishedAt = (& $nowOf).ToString('o')
        $report.phase = 'paused'
        $null = Write-ZCodeStartupReport -StateRoot $root -Report $report
        return @{ ExitCode = 0; Report = $report; Rollback = $null }
      }

      $watchResult = & $stopWatchOf $session $root
      $report.watchPid = 0
      if (-not $watchResult.stopped) {
        throw "E10_REMOVE_THEME_FAILED: this session's watcher could not be stopped ($($watchResult.reason)); the running theme was left alone"
      }
      Write-Log 'RESTORE' "own watcher released ($($watchResult.action): $($watchResult.reason))"

      # The stop result's stopped=true is the contract that no watcher of this
      # session is running anymore. Only now is the stop request retracted and the
      # fresh watch state published: earlier would invite a not-yet-exited watcher
      # back, and leaving the request in place would make the re-armed watcher exit
      # on its very first state-file poll. watchPid goes to 0 so every failure from
      # here on leaves a state that says honestly: no watcher is armed.
      $session = Set-ZCodeDreamSkinStopped -State $session -Stopped $false
      $session = Set-ZCodeDreamSkinStateField -State $session -Name 'watchPid' -Value 0
      $null = Write-ZCodeDreamSkinState -StateRoot $root -State $session

      $sessionMetadata = & $identityOf $session.zcodePath
      $sessionVersion = Get-ZCodeStartupVersion -Metadata $sessionMetadata
      $applyReportPath = Join-Path $root 'last-apply-report.json'
      if (Test-Path -LiteralPath $applyReportPath -PathType Leaf) {
        Remove-Item -LiteralPath $applyReportPath -Force
      }
      $applyArguments = @(
        (Join-Path $PSScriptRoot 'injector.mjs'), '--mode', 'zcode-apply',
        '--port', "$($session.port)", '--browser-id', $sessionBrowserId,
        '--zcode-version', $sessionVersion,
        '--report', $applyReportPath
      ) + $themeArguments
      if ($CautionFile) { $applyArguments += @('--zcode-caution-file', $CautionFile) }
      $applyResult = & $applyOf $applyArguments $root
      if ([int]$applyResult.exitCode -ne 0) {
        throw 'E09_RUNTIME_EVALUATE_FAILED: the reapply failed; see last-apply-report.json'
      }
      if (-not (Test-Path -LiteralPath $applyReportPath -PathType Leaf)) {
        throw 'E09_RUNTIME_EVALUATE_FAILED: the reapply wrote no report; this session is not verified'
      }
      try {
        $applyReport = Get-Content -LiteralPath $applyReportPath -Raw -Encoding UTF8 | ConvertFrom-Json
      } catch {
        throw "E09_RUNTIME_EVALUATE_FAILED: the reapply report is unreadable: $($_.Exception.Message)"
      }
      $null = Assert-ZCodeThemeApplicationReport -Report $applyReport `
        -BrowserId $sessionBrowserId -Port ([int]$session.port)

      # The state keeps its identity (rootPid/port/browser) and records the new theme
      # revision, so a later restore and a later reapply both see the current theme.
      $session = Set-ZCodeDreamSkinStateField -State $session -Name 'themeVersion' -Value ([string]$applyReport.revision)
      $session = Set-ZCodeDreamSkinStateField -State $session -Name 'compatibilityMode' -Value ([string]$applyReport.compatibilityMode)
      $session = Set-ZCodeDreamSkinStateField -State $session -Name 'updatedAt' -Value ((& $nowOf).ToString('o'))
      $null = Write-ZCodeDreamSkinState -StateRoot $root -State $session

      $watchArguments = @(
        (Join-Path $PSScriptRoot 'injector.mjs'), '--mode', 'zcode-watch',
        '--port', "$($session.port)", '--browser-id', $sessionBrowserId,
        '--zcode-version', $sessionVersion,
        '--zcode-state-file', $statePath,
        '--report', (Join-Path $root 'watch-report.json')
      ) + $themeArguments
      if ($CautionFile) { $watchArguments += @('--zcode-caution-file', $CautionFile) }
      $watch = & $watchOf $watchArguments
      $session = Set-ZCodeDreamSkinStateField -State $session -Name 'watchPid' -Value ([int]$watch.Id)
      $null = Write-ZCodeDreamSkinState -StateRoot $root -State $session
      $report.watchPid = [int]$watch.Id
      Write-Log 'INJECT' "reapplied themeVersion=$($applyReport.revision) watchPid=$($watch.Id)"
      $report.finishedAt = (& $nowOf).ToString('o')
      $report.phase = 'active'
      $null = Write-ZCodeStartupReport -StateRoot $root -Report $report
      return @{ ExitCode = 0; Report = $report; Rollback = $null }
    }

    # The user's theme is resolved before any path uses it: the active library by

    # --- port -------------------------------------------------------------------
    if ($Port) {
      Assert-ZCodeExplicitPortFree -Port $Port -IsPortBusy { param($p) @(Get-DreamSkinPortListeners -Port $p).Count -gt 0 }
      $selectedPort = $Port
    } else {
      $selectedPort = Find-ZCodeFreePort -IsPortBusy { param($p) @(Get-DreamSkinPortListeners -Port $p).Count -gt 0 }
    }
    $report.port = $selectedPort
    Write-Log 'PORT' "selected=$selectedPort"

    # --- identity ---------------------------------------------------------------
    $zcodeExe = & $resolveOf $ZCodePath
    $metadata = & $identityOf $zcodeExe
    # The verified version is read through the one flat-field interface: an empty
    # version stops the launch here instead of travelling into the report.
    $fileVersion = Get-ZCodeStartupVersion -Metadata $metadata
    $fingerprint = & $fingerprintOf $zcodeExe
    $report.zcodePath = $zcodeExe
    $report.fileVersion = $fileVersion
    Write-Log 'PROCESS' "zcode=$zcodeExe version=$fileVersion"

    # --- a launch that never became active must be reported, never guessed at ----
    $previousSummary = ''
    $pendingPath = Get-ZCodeLaunchTransactionPath -StateRoot $root
    $pending = $null
    try { $pending = Read-ZCodeLaunchTransaction -StateRoot $root } catch {
      $pending = $null
      $report.errors += "unreadable launch transaction: $($_.Exception.Message)"
      Write-Log 'RESTORE' 'an unreadable launch transaction was set aside'
    }
    if ($null -ne $pending) {
      $previousSummary = "$($pending.transactionId)@$($pending.phase)"
      Write-Log 'RESTORE' "pending launch transaction from an earlier run: $previousSummary (reported, not closed here)"
    }
    if (Test-Path -LiteralPath $pendingPath -PathType Leaf) {
      # Keep the evidence under a dated name; the new transaction takes over the
      # record without pretending the old one never happened.
      Move-Item -LiteralPath $pendingPath -Destination (Join-Path $root ("launch-transaction.superseded-" + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.json')) -Force
    }
    $report.previousTransaction = $previousSummary

    # --- launch -----------------------------------------------------------------
    $preExistingIds = @($processRows | ForEach-Object { [int]$_.ProcessId })
    $launchArguments = @(New-ZCodeLaunchArguments -Port $selectedPort)
    $transaction = New-ZCodeLaunchTransaction -ZCodePath $zcodeExe -FileVersion $fileVersion `
      -ExecutableSha256 ([string]$fingerprint.sha256) -Port $selectedPort `
      -PreExistingPids $preExistingIds -PreviousTransaction $previousSummary `
      -LaunchRequestedAt (& $nowOf)
    $null = Write-ZCodeLaunchTransaction -StateRoot $root -Transaction $transaction
    Write-Log 'LAUNCH' "transaction=$($transaction.transactionId) phase=launch-requested"

    $launched = & $launchOf $zcodeExe $launchArguments
    Write-Log 'LAUNCH' "pid=$($launched.Id) port=$selectedPort"
    $transaction = Set-ZCodeLaunchTransactionPhase -Transaction $transaction -Phase 'launched' -At (& $nowOf)
    $transaction.launchedPid = [int]$launched.Id
    try { $transaction.creationTime = ([datetime]$launched.StartTime).ToString('o') } catch { $transaction.creationTime = '' }
    $null = Write-ZCodeLaunchTransaction -StateRoot $root -Transaction $transaction
    $report.launchedPid = [int]$launched.Id
    $report.phase = 'launched'

    if ($StartupTimeoutSeconds -gt 0) { & $sleepOf 3000 | Out-Null }
    $processRows2 = @(& $rowsOf)
    $resolved = & $mainOf $processRows2 ([int]$launched.Id) ([bool]$launched.HasExited) $preExistingIds $zcodeExe
    $rootPid = [int]$resolved.rootPid
    if (-not $resolved.rootAlive) {
      throw 'E06_CDP_ENDPOINT_UNAVAILABLE: the launched ZCode exited before the CDP endpoint appeared'
    }
    $transaction.rootPid = $rootPid
    $null = Write-ZCodeLaunchTransaction -StateRoot $root -Transaction $transaction
    $report.rootPid = $rootPid
    Write-Log 'PROCESS' "rootPid=$rootPid source=$($resolved.source)"

    # --- CDP endpoint -------------------------------------------------------------
    $identity = & $cdpOf $selectedPort $StartupTimeoutSeconds
    if (-not $identity) { throw "E06_CDP_ENDPOINT_UNAVAILABLE: nothing usable answered on port $selectedPort" }
    $transaction = Set-ZCodeLaunchTransactionPhase -Transaction $transaction -Phase 'cdp-ready' -At (& $nowOf)
    $transaction.browserId = [string]$identity.BrowserId
    $transaction.browserWebSocketUrl = [string]$identity.WebSocketDebuggerUrl
    $null = Write-ZCodeLaunchTransaction -StateRoot $root -Transaction $transaction
    $report.browserId = [string]$identity.BrowserId
    $report.phase = 'cdp-ready'
    Write-Log 'CDP' "browserId=$($identity.BrowserId)"

    # --- theme application ---------------------------------------------------------
    # The injector takes over here: it waits for the main renderer and the hydrated
    # workspace itself. From this point a theme write may have happened even if the
    # call fails, so the phase says the renderer stage was entered.
    $transaction = Set-ZCodeLaunchTransactionPhase -Transaction $transaction -Phase 'renderer-ready' -At (& $nowOf)
    $null = Write-ZCodeLaunchTransaction -StateRoot $root -Transaction $transaction
    $report.phase = 'renderer-ready'

    if ($InitialAppearance -eq 'native') {
      # The zero-skin contract is measured, not assumed: a leftover layer from an
      # earlier session would otherwise be published as "default appearance" while
      # the window still showed a skin. Nothing is applied and no watcher is armed,
      # so the state says paused with watchPid 0 - and a later resume only has to
      # unlock this same root, browser and port.
      $nativeVerifyArguments = @(
        (Join-Path $PSScriptRoot 'injector.mjs'), '--mode', 'zcode-verify',
        '--port', "$selectedPort", '--browser-id', [string]$identity.BrowserId,
        '--expect-appearance', 'native',
        '--report', (Join-Path $root 'last-verify-report.json')
      )
      $nativeVerify = & $verifyOf $nativeVerifyArguments $root
      if ([int]$nativeVerify.exitCode -ne 0) {
        throw 'E09_RUNTIME_EVALUATE_FAILED: the window still carries skin nodes, so it cannot be recorded as the default appearance'
      }
      $state = New-ZCodeDreamSkinState -ZCodePath $zcodeExe -RootPid $rootPid -Port $selectedPort `
        -BrowserWebSocketUrl $identity.WebSocketDebuggerUrl -Fingerprint $fingerprint.sha256 `
        -CompatibilityMode 'deny' -ThemeVersion '' -WatchPid 0
      $state = Set-ZCodeDreamSkinPaused -State $state -Paused $true
      $state = Set-ZCodeDreamSkinStopped -State $state -Stopped $false
      $null = Write-ZCodeDreamSkinState -StateRoot $root -State $state
      $transaction = Set-ZCodeLaunchTransactionPhase -Transaction $transaction -Phase 'paused-native' -At (& $nowOf)
      $null = Write-ZCodeLaunchTransaction -StateRoot $root -Transaction $transaction
      Clear-ZCodeLaunchTransaction -StateRoot $root
      $report.watchPid = 0
      $report.phase = 'paused-native'
      Write-Log 'VERIFY' 'appearance=native skinNodes=0 watcher=none'
      Write-Log 'LAUNCH' 'started in the default appearance'
      $report.finishedAt = (& $nowOf).ToString('o')
      $null = Write-ZCodeStartupReport -StateRoot $root -Report $report
      return @{ ExitCode = 0; Report = $report; Rollback = $null }
    }
    # A report from an earlier run must never stand in for this one, so the file is
    # cleared first and then required to exist.
    $applyReportPath = Join-Path $root 'last-apply-report.json'
    if (Test-Path -LiteralPath $applyReportPath -PathType Leaf) {
      Remove-Item -LiteralPath $applyReportPath -Force
    }
    $applyArguments = @(
      (Join-Path $PSScriptRoot 'injector.mjs'), '--mode', 'zcode-apply',
      '--port', "$selectedPort", '--browser-id', $identity.BrowserId,
      '--zcode-version', $fileVersion,
      '--report', $applyReportPath
    )
    $applyArguments += $themeArguments
    if ($CautionFile) { $applyArguments += @('--zcode-caution-file', $CautionFile) }
    $applyResult = & $applyOf $applyArguments $root
    if ([int]$applyResult.exitCode -ne 0) { throw 'E09_RUNTIME_EVALUATE_FAILED: theme application failed; see last-apply-report.json' }
    if (-not (Test-Path -LiteralPath $applyReportPath -PathType Leaf)) {
      throw 'E09_RUNTIME_EVALUATE_FAILED: the theme application wrote no report; this launch is not verified'
    }
    try {
      $applyReport = Get-Content -LiteralPath $applyReportPath -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
      throw "E09_RUNTIME_EVALUATE_FAILED: the theme application report is unreadable: $($_.Exception.Message)"
    }
    $null = Assert-ZCodeThemeApplicationReport -Report $applyReport `
      -BrowserId ([string]$identity.BrowserId) -Port $selectedPort
    $transaction = Set-ZCodeLaunchTransactionPhase -Transaction $transaction -Phase 'theme-applied' -At (& $nowOf)
    $null = Write-ZCodeLaunchTransaction -StateRoot $root -Transaction $transaction
    $report.phase = 'theme-applied'
    Write-Log 'COMPAT' "mode=$($applyReport.compatibilityMode) reason=$($applyReport.compatibilityReason)"

    # --- state + watch -----------------------------------------------------------------
    $state = New-ZCodeDreamSkinState -ZCodePath $zcodeExe -RootPid $rootPid -Port $selectedPort `
      -BrowserWebSocketUrl $identity.WebSocketDebuggerUrl -Fingerprint $fingerprint.sha256 `
      -CompatibilityMode $applyReport.compatibilityMode -ThemeVersion $applyReport.revision
    $null = Write-ZCodeDreamSkinState -StateRoot $root -State $state
    $watchArguments = @(
      (Join-Path $PSScriptRoot 'injector.mjs'), '--mode', 'zcode-watch',
      '--port', "$selectedPort", '--browser-id', $identity.BrowserId,
      '--zcode-version', $fileVersion,
      '--zcode-state-file', $statePath,
      '--report', (Join-Path $root 'watch-report.json')
    )
    $watchArguments += $themeArguments
    if ($CautionFile) { $watchArguments += @('--zcode-caution-file', $CautionFile) }
    $watch = & $watchOf $watchArguments
    $state.watchPid = [int]$watch.Id
    $null = Write-ZCodeDreamSkinState -StateRoot $root -State $state
    $transaction = Set-ZCodeLaunchTransactionPhase -Transaction $transaction -Phase 'active' -At (& $nowOf)
    $transaction.watchPid = [int]$watch.Id
    $null = Write-ZCodeLaunchTransaction -StateRoot $root -Transaction $transaction
    # Only now does the active state own the session, so the transaction is done.
    Clear-ZCodeLaunchTransaction -StateRoot $root
    $report.phase = 'active'
    $report.watchPid = [int]$watch.Id
    Write-Log 'INJECT' "themeVersion=$($applyReport.revision) watchPid=$($watch.Id)"
    Write-Log 'LAUNCH' 'started'
    $report.finishedAt = (& $nowOf).ToString('o')
    $null = Write-ZCodeStartupReport -StateRoot $root -Report $report
    return @{ ExitCode = 0; Report = $report; Rollback = $null }
  } catch {
    $primaryError = $_.Exception.Message
    Write-Host (Format-ZCodeDreamSkinLogLine -Tag 'ERROR' -Message $primaryError)
    $report.primaryError = $primaryError
    $rollback = $null
    if ($null -ne $transaction) {
      # The transaction is the only record of what this launch created: undo it with
      # the verified-instance rules, and keep it when the undo is incomplete.
      $rollbackSeams = @{
        PrimaryError = $primaryError
        Now = $nowOf
        Sleep = $sleepOf
      }
      if ($ValidateOwner) { $rollbackSeams.ValidateOwner = $ValidateOwner }
      if ($RollbackRemoveTheme) { $rollbackSeams.RemoveTheme = $RollbackRemoveTheme }
      if ($RollbackCloseBrowser) { $rollbackSeams.CloseBrowser = $RollbackCloseBrowser }
      if ($RollbackCloseWindow) { $rollbackSeams.CloseWindow = $RollbackCloseWindow }
      if ($RollbackStopWatch) { $rollbackSeams.StopWatch = $RollbackStopWatch }
      if ($RollbackObserveCleanup) { $rollbackSeams.ObserveCleanup = $RollbackObserveCleanup }
      $rollback = Invoke-ZCodeLaunchRollback -Transaction $transaction -StateRoot $root @rollbackSeams
      Write-Log 'RESTORE' ("rollback attempted=$($rollback.attempted) complete=$($rollback.complete) " +
        "residualPids=$(@($rollback.residualPids) -join ',') portListenerOwners=$(@($rollback.portListenerOwners) -join ',') " +
        "transactionKept=$(Test-Path -LiteralPath (Get-ZCodeLaunchTransactionPath -StateRoot $root))")
    } else {
      Write-Log 'RESTORE' 'no launch transaction exists; nothing was started'
    }
    $report.rollback = $rollback
    $report.finishedAt = (& $nowOf).ToString('o')
    $report.transactionKept = Test-Path -LiteralPath (Get-ZCodeLaunchTransactionPath -StateRoot $root)
    $null = Write-ZCodeStartupReport -StateRoot $root -Report $report
    return @{ ExitCode = 1; Report = $report; Rollback = $rollback }
  }
}

if ($MyInvocation.InvocationName -ne '.') {
  try {
    $door = Join-Path $PSScriptRoot 'set-zcode-appearance.ps1'
    if (-not $ArtPath -and -not $ThemePath -and (Test-Path -LiteralPath $door -PathType Leaf)) {
      # No operator-supplied artwork override means this is the ordinary "apply my
      # skin" entry, so it goes through the appearance door: root lock, journal and
      # independent verification. The start function below stays the effects
      # implementation the door calls back into, so nothing re-enters a held lock.
      . $door
      $root = Get-ZCodeDreamSkinStateRoot -StateRoot $StateRoot
      $request = [pscustomobject]@{
        schemaVersion = 'zcode-dream-skin-command/1'
        requestId     = [guid]::NewGuid().ToString('N')
        action        = 'launch'
        stateRoot     = $root
      }
      $outcome = Invoke-ZCodeAppearanceOperation -StateRoot $root -Request $request `
        -Effects (New-Zds2LiveEffects -StateRoot $root)
      Write-Host (Format-ZCodeDreamSkinLogLine -Tag 'LAUNCH' -Message "door ok=$($outcome.ok) errorCode=$($outcome.errorCode)")
      if ($outcome.ok) { exit 0 }
      if ($outcome.errorCode -eq 'BUSY') { exit 4 }
      exit 1
    }
    if ($ArtPath -or $ThemePath) {
      # An explicit artwork path is an operator instruction, not an appearance change
      # the user recorded: it runs the direct path and says so out loud, because a
      # silent second write path is what this file is supposed to have closed.
      Write-Host (Format-ZCodeDreamSkinLogLine -Tag 'LAUNCH' -Message 'operator override in use: applying -ArtPath/-ThemePath directly, outside the appearance door')
    } elseif (-not (Test-Path -LiteralPath $door -PathType Leaf)) {
      Write-Host (Format-ZCodeDreamSkinLogLine -Tag 'LAUNCH' -Message 'the appearance door is missing; using the direct start path')
    }
    $result = Invoke-ZCodeDreamSkinStart -Port $Port -ZCodePath $ZCodePath -CautionFile $CautionFile `
      -ArtPath $ArtPath -ThemePath $ThemePath -StateRoot $StateRoot `
      -InitialAppearance $InitialAppearance `
      -StartupTimeoutSeconds $StartupTimeoutSeconds
    exit $result.ExitCode
  } catch {
    Write-Host (Format-ZCodeDreamSkinLogLine -Tag 'ERROR' -Message $_.Exception.Message)
    exit 1
  }
}
