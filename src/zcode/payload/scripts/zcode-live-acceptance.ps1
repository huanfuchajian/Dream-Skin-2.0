# ZCode Dream Skin: one-shot live acceptance for Task 5 re-collection and the
# Task 6+7 product scenario. Run ONLY while no ZCode is running (the script
# refuses to touch a live ZCode and exits 3 instead).
#
# Exit codes:
#   0  every check passed; evidence + screenshots are in .lemon\evidence\
#   2  ran, but at least one check failed (see acceptance-report.json)
#   3  blocked: a ZCode instance is already running, nothing was launched
#
# The whole flow is orchestrated by Invoke-ZCodeLiveAcceptance with injectable
# seams (every external process call is a scriptblock parameter), so the
# contract test drives it end to end without launching anything. Phase B runs
# under a global fail-safe: any mid-flow failure triggers one identity-, path-
# and tree-protected Full restore; nothing is ever force-stopped.
[CmdletBinding()]
param(
  [string]$ZCodePath = 'F:\AI\ZCode\ZCode.exe',
  [int]$Port = 9335
)
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'common-windows.ps1')
. (Join-Path $PSScriptRoot 'zcode-product.ps1')
. (Join-Path $PSScriptRoot 'zcode-startup.ps1')
if (-not $NodePath) { $NodePath = (Get-DreamSkinNodeRuntime -MinimumMajor 22).Path }

function Invoke-ZCodeLiveAcceptance {
  [CmdletBinding()]
  param(
    [string]$ZCodePath = 'F:\AI\ZCode\ZCode.exe',
    [int]$Port = 9335,
    [string]$ScriptsDir = $PSScriptRoot,
    # The repository root is two levels up (windows\scripts\..\..), never one:
    # resolving it to windows\ silently relocated every piece of evidence.
    [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path,
    [string]$EvidenceDir = '',
    [string]$AcceptanceDir = '',
    [string]$StateRoot = '',
    # Injectable seam: an empty value resolves through the shared bundled-first
    # resolver below. The old environment override let anyone able to write
    # HKCU\Environment redirect every validator the acceptance runs.
    [string]$NodePath = '',
    [switch]$AsExitCodeObject,
    # --- injectable seams; $null means "run the real product" ------------------
    [scriptblock]$GetZCodeProcessRows = $null,
    [scriptblock]$AssertZCodeIdentity = $null,
    [scriptblock]$ArchivePreviousInventory = $null,
    [scriptblock]$RunInventoryCollection = $null,
    [scriptblock]$RunInventoryAudit = $null,
    [scriptblock]$StartProduct = $null,
    [scriptblock]$ReadState = $null,
    [scriptblock]$InvokeInjectorMode = $null,
    [scriptblock]$RestoreProduct = $null,
    [scriptblock]$RollbackLaunch = $null,
    [scriptblock]$GetProcessAlive = $null,
    [scriptblock]$GetPortListeners = $null,
    [scriptblock]$TestPathExists = $null,
    [scriptblock]$GetNow = $null,
    [scriptblock]$Sleep = $null
  )

  if (-not $EvidenceDir) { $EvidenceDir = Join-Path $RepoRoot '.lemon\evidence' }
  if (-not $AcceptanceDir) { $AcceptanceDir = Join-Path $EvidenceDir 'acceptance' }
  $reportPath = Join-Path $AcceptanceDir 'acceptance-report.json'
  $stateRoot = if ($StateRoot) { Get-ZCodeDreamSkinStateRoot -StateRoot $StateRoot } else { Get-ZCodeDreamSkinStateRoot }
  $order = [System.Collections.Generic.List[string]]::new()
  $finalExitCode = 0
  $productStarted = $false
  $fullRestoreCompleted = $false
  $managedState = $null
  $report = [ordered]@{
    startedAt = (Get-Date).ToString('o')
    zcodeVersion = $null
    phaseA = [ordered]@{ }
    phaseB = [ordered]@{ }
    launchRecovery = $null
    failSafeRestore = $null
    screenshots = @()
    errors = @()
  }

  function Write-AcceptanceReport {
    $report.finishedAt = (Get-Date).ToString('o')
    $null = [System.IO.Directory]::CreateDirectory($AcceptanceDir)
    # -InputObject (never a pipeline): piping a dictionary enumerates its
    # entries and silently produces an empty file for some shapes.
    $json = ConvertTo-Json -InputObject $report -Depth 8 -ErrorAction Stop
    [System.IO.File]::WriteAllText($reportPath, $json, [System.Text.UTF8Encoding]::new($false))
  }
  function Add-Step {
    param([string]$Name, [bool]$Passed, [string]$Detail)
    if (-not $report.phaseB.Contains($Name)) { $order.Add($Name) }
    $report.phaseB[$Name] = [ordered]@{ passed = $Passed; detail = $Detail }
    $tag = if ($Passed) { 'VERIFY' } else { 'ERROR' }
    Write-Host (Format-ZCodeDreamSkinLogLine -Tag $tag -Message "$Name : $Detail")
  }
  # Every step failure aborts Phase B into the fail-safe path; the exception is
  # the transport, the step verdict is the contract.
  function Assert-Step {
    param([string]$Name, [bool]$Condition, [string]$Detail)
    Add-Step -Name $Name -Passed $Condition -Detail $Detail
    if (-not $Condition) { throw "ACCEPTANCE_STEP_FAILED:$Name" }
  }

  # --- seam dispatch: explicit fallbacks keep the real product one hop away ----
  $rowsOf = if ($GetZCodeProcessRows) { $GetZCodeProcessRows } else { { param() @(Get-ZCodeProcessSnapshot | Where-Object { [string]$_.Name -ieq 'ZCode.exe' }) } }
  $identityOf = if ($AssertZCodeIdentity) { $AssertZCodeIdentity } else {
    {
      param($Path)
      # Returns the verified metadata itself (flat FileVersion), never a pre-digested
      # version: the runner owns the single version read so a fake metadata object and
      # the real identity check go through the same contract.
      $m = Get-ZCodeIdentityMetadata -Path $Path
      $null = Test-ZCodeIdentityMetadata -Metadata $m
      $m
    }
  }
  $archiveOf = if ($ArchivePreviousInventory) { $ArchivePreviousInventory } else { { param($InventoryPath, $Dir) if (Test-Path -LiteralPath $InventoryPath -PathType Leaf) { $archiveName = 'zcode-dom-inventory-archived-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.json'; Move-Item -LiteralPath $InventoryPath -Destination (Join-Path $Dir $archiveName) -Force; return $archiveName } return $null } }
  $collect = if ($RunInventoryCollection) { $RunInventoryCollection } else { { param($P, $Z, $Dir, $S) & powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File (Join-Path $S 'zcode-poc.ps1') -ZCodePath $Z -Port $P -DomInventory -ReportPath (Join-Path $Dir 'zcode-dom-inventory-run.json') 2>&1 | Tee-Object -FilePath (Join-Path $Dir 'zcode-dom-inventory-acceptance.log') | Out-Null; return $LASTEXITCODE } }
  $audit = if ($RunInventoryAudit) { $RunInventoryAudit } else {
    {
      param($N, $S, $Dir, $Root)
      # The audit is a CLI over explicit absolute paths — the evidence under the
      # evidence dir, the profile and DOM map under the repository root. It is
      # never left to guess a root of its own.
      $auditArguments = @(
        (Join-Path $S 'zcode-inventory-audit.mjs'),
        '--inventory', (Join-Path $Dir 'zcode-dom-inventory.json'),
        '--run-report', (Join-Path $Dir 'zcode-dom-inventory-run.json'),
        '--profile', (Join-Path $Root 'windows\assets\zcode-profile.json'),
        '--dom-map', (Join-Path $Root 'windows\references\zcode-dom-map.md')
      )
      $out = & $N @auditArguments 2>&1
      @{ exitCode = $LASTEXITCODE; output = ($out | Out-String).Trim() }
    }
  }
  $start = if ($StartProduct) { $StartProduct } else {
    {
      param($Args_, $S, $Dir, $StateRoot_)
      $null = [System.IO.Directory]::CreateDirectory($Dir)
      & powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File (Join-Path $S 'start-zcode-dream-skin.ps1') @Args_ 2>&1 |
        Tee-Object -FilePath (Join-Path $Dir 'start.log') | Out-Null
      $exit = $LASTEXITCODE
      # The launcher's own report is the first place a started instance is recorded;
      # a missing report is not an error, it just means there is nothing to read.
      $reportPath = Get-ZCodeStartupReportPath -StateRoot $StateRoot_
      $report = Read-ZCodeStartupReport -StateRoot $StateRoot_
      $transactionPresent = Test-Path -LiteralPath (Get-ZCodeLaunchTransactionPath -StateRoot $StateRoot_) -PathType Leaf
      @{
        exitCode   = $exit
        reportPath = $reportPath
        report     = $report
        launched   = ($transactionPresent -or ($null -ne $report -and [int]$report.launchedPid -gt 0))
      }
    }
  }
  $readState = if ($ReadState) { $ReadState } else { { param($Root) Read-ZCodeDreamSkinState -StateRoot $Root } }
  $injector = if ($InvokeInjectorMode) { $InvokeInjectorMode } else {
    {
      param($Mode, $State, $ScreenshotPath, $S, $Dir, $Version, $ArtPath)
      $arguments = @((Join-Path $S 'injector.mjs'), '--mode', $Mode,
        '--port', "$($State.port)", '--browser-id', (Get-ZCodeDreamSkinBrowserId -State $State),
        '--report', (Join-Path $Dir 'last-verify.json'))
      if ($Version) { $arguments += @('--zcode-version', $Version) }
      if ($ArtPath) { $arguments += @('--zcode-art', $ArtPath) }
      if ($ScreenshotPath) { $arguments += @('--screenshot', $ScreenshotPath) }
      if ($Mode -eq 'zcode-apply' -or $Mode -eq 'zcode-remove' -or $Mode -eq 'zcode-reload') {
        $arguments = @((Join-Path $S 'injector.mjs'), '--mode', $Mode,
          '--port', "$($State.port)", '--browser-id', (Get-ZCodeDreamSkinBrowserId -State $State),
          '--report', (Join-Path $Dir "$Mode-report.json"))
        if ($Version -and $Mode -eq 'zcode-apply') { $arguments += @('--zcode-version', $Version) }
        if ($ArtPath -and $Mode -eq 'zcode-apply') { $arguments += @('--zcode-art', $ArtPath) }
      }
      & $NodePath @arguments | Out-Null
      $exit = $LASTEXITCODE
      $verifyReport = $null
      if ($Mode -eq 'zcode-verify' -and (Test-Path -LiteralPath (Join-Path $Dir 'last-verify.json') -PathType Leaf)) {
        $verifyReport = Get-Content -LiteralPath (Join-Path $Dir 'last-verify.json') -Raw -Encoding UTF8 | ConvertFrom-Json
      }
      @{ exitCode = $exit; verifyReport = $verifyReport }
    }
  }
  $restore = if ($RestoreProduct) { $RestoreProduct } else { { param($Mode, $S) $out = & powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File (Join-Path $S 'restore-zcode-dream-skin.ps1') -Mode $Mode 2>&1; @{ exitCode = $LASTEXITCODE; output = ($out | Out-String).Trim() } } }
  $rollbackLaunchOf = if ($RollbackLaunch) { $RollbackLaunch } else {
    {
      param($Transaction_, $StateRoot_)
      Invoke-ZCodeLaunchRollback -Transaction $Transaction_ -StateRoot $StateRoot_
    }
  }
  $aliveOf = if ($GetProcessAlive) { $GetProcessAlive } else { { param($Pid_) [bool](Get-Process -Id ([int]$Pid_) -ErrorAction SilentlyContinue) } }
  $listenersOf = if ($GetPortListeners) { $GetPortListeners } else { { param($P) @(Get-DreamSkinPortListeners -Port $P) } }
  $pathExists = if ($TestPathExists) { $TestPathExists } else { { param($Path) Test-Path -LiteralPath $Path -PathType Leaf } }
  $nowOf = if ($GetNow) { $GetNow } else { { param() Get-Date } }
  $sleepOf = if ($Sleep) { $Sleep } else { { param($Ms) Start-Sleep -Milliseconds $Ms } }

  # --- pre-flight: the machine must be ZCode-free, and the target verified -----
  $existingRows = @(& $rowsOf)
  if ($existingRows.Count -gt 0) {
    Write-Host (Format-ZCodeDreamSkinLogLine -Tag 'ERROR' -Message 'E04_ZCODE_RUNNING_WITHOUT_CDP: close ZCode normally and re-run this script; nothing was launched')
    return @{ ExitCode = 3; Events = $order; Report = $report }
  }
  if (-not (& $pathExists $ZCodePath)) {
    Write-Host (Format-ZCodeDreamSkinLogLine -Tag 'ERROR' -Message "E01_ZCODE_NOT_FOUND: $ZCodePath does not exist")
    $finalExitCode = 2
    Write-AcceptanceReport
    return @{ ExitCode = $finalExitCode; Events = $order; Report = $report }
  }
  try {
    $metadata = & $identityOf $ZCodePath
    # One version interface for the report and for the re-apply. An empty value stops
    # the run here, before anything is launched.
    $report.zcodeVersion = Get-ZCodeStartupVersion -Metadata $metadata
  } catch {
    $report.errors += "E02_ZCODE_IDENTITY_INVALID: $($_.Exception.Message)"
    $finalExitCode = 2
    Write-AcceptanceReport
    return @{ ExitCode = $finalExitCode; Events = $order; Report = $report }
  }

  # --- Phase A: fresh DOM inventory over the old (leaked) evidence --------------
  $order.Add('inventory'); $order.Add('audit')
  $archiveName = & $archiveOf (Join-Path $EvidenceDir 'zcode-dom-inventory.json') $EvidenceDir
  if ($archiveName) {
    Write-Host (Format-ZCodeDreamSkinLogLine -Tag 'RESTORE' -Message "archived previous inventory as $archiveName (git-ignored)")
  }
  $inventoryExit = & $collect $Port $ZCodePath $EvidenceDir $ScriptsDir
  $report.phaseA.inventoryExitCode = $inventoryExit
  $auditResult = & $audit $NodePath $ScriptsDir $EvidenceDir $RepoRoot
  $report.phaseA.auditExitCode = $auditResult.exitCode
  $report.phaseA.audit = $auditResult.output
  Write-Host $auditResult.output
  if ($inventoryExit -ne 0 -or $auditResult.exitCode -ne 0) {
    $report.errors += "phase A failed (inventory exit $inventoryExit, audit exit $($auditResult.exitCode)); theme scenario skipped"
    $finalExitCode = 2
    Write-AcceptanceReport
    return @{ ExitCode = $finalExitCode; Events = $order; Report = $report }
  }

  # --- Phase B: the ten-step product scenario under a global fail-safe ----------
  $presetArt = Join-Path $RepoRoot 'windows\presets\preset-gothic-void-crusade\background.jpg'
  $verifyTimestampBeforeReapply = $null

  # A failed launch is recovered through its launch transaction, never through the
  # active-session Full restore: a start that never reached an active state has no
  # state to restore. The record of what was created is the transaction the launcher
  # left behind (or already cleared), and the verdict is re-measured here instead of
  # being taken from a single command's exit code.
  function Invoke-LaunchRecovery {
    param($StartResult)
    $record = [ordered]@{
      exitCode           = [int]$StartResult.exitCode
      reportPath         = [string]$StartResult.reportPath
      report             = $StartResult.report
      launched           = [bool]$StartResult.launched
      transactionPresent = $false
      transactionId      = ''
      rollback           = $null
      residualPids       = @()
      portListenerOwners = @()
      verified           = $false
      recovered          = $false
      detail             = ''
    }
    $transaction = $null
    try { $transaction = Read-ZCodeLaunchTransaction -StateRoot $stateRoot } catch {
      $record.detail = String-Clean -Text $_.Exception.Message
    }
    if ($null -ne $transaction) {
      $record.transactionPresent = $true
      $record.transactionId = [string]$transaction.transactionId
      try {
        $record.rollback = & $rollbackLaunchOf $transaction $stateRoot
      } catch {
        $record.rollback = [ordered]@{
          attempted = $false
          complete  = $false
          errors    = @(String-Clean -Text $_.Exception.Message)
        }
      }
    }

    $preExisting = @()
    $roots = @()
    if ($null -ne $transaction) {
      $preExisting = @($transaction.preExistingPids | ForEach-Object { [int]$_ })
      foreach ($candidate in @([int]$transaction.launchedPid, [int]$transaction.rootPid)) {
        if ($candidate -gt 0 -and $preExisting -notcontains $candidate) { $roots += $candidate }
      }
    }
    $rows = @(& $rowsOf)
    $tree = @($roots)
    $growing = $true
    while ($growing) {
      $growing = $false
      foreach ($row in $rows) {
        if (($tree -contains [int]$row.ParentProcessId) -and ($tree -notcontains [int]$row.ProcessId)) {
          $tree += [int]$row.ProcessId
          $growing = $true
        }
      }
    }
    $record.residualPids = @($rows | Where-Object {
      ($tree -contains [int]$_.ProcessId) -and ($preExisting -notcontains [int]$_.ProcessId)
    } | ForEach-Object { [int]$_.ProcessId })
    $record.portListenerOwners = @(& $listenersOf $Port | ForEach-Object { [int]$_.OwningProcess })
    $record.verified = (@($record.residualPids).Count -eq 0)
    $rollbackComplete = ($null -eq $transaction) -or ([bool]$record.rollback.complete)
    $record.recovered = ($record.verified -and $rollbackComplete)
    if (-not $record.recovered -and -not $record.detail) {
      $record.detail = "residualPids=$(@($record.residualPids) -join ',') portListenerOwners=$(@($record.portListenerOwners) -join ',') rollbackComplete=$rollbackComplete"
    }
    return [pscustomobject]$record
  }

  function Invoke-Verify {
    param([string]$ScreenshotName)
    $shot = $null
    if ($ScreenshotName) {
      $shot = Join-Path $AcceptanceDir "$ScreenshotName.png"
      $report.screenshots += $shot
    }
    $result = & $injector 'zcode-verify' $managedState $shot $ScriptsDir $AcceptanceDir $null $null
    if ($result.exitCode -ne 0) { throw "zcode-verify exited $($result.exitCode)" }
    return $result.verifyReport
  }
  function Get-Counts {
    param($VerifyReport)
    if ($VerifyReport -and $VerifyReport.verify) { return $VerifyReport.verify }
    return @{ styleCount = -1; backgroundCount = -1; overlayCount = -1 }
  }

  try {
    # Step 1+2: apply the full theme and verify the rendered workspace.
    $startResult = & $start @(@('-Port', "$Port", '-ZCodePath', $ZCodePath, '-ArtPath', $presetArt)) $ScriptsDir $AcceptanceDir $stateRoot
    if ($startResult.exitCode -eq 0) {
      Assert-Step 'start' $true "start-zcode-dream-skin exit 0"
      $productStarted = $true
    } else {
      # Take recovery responsibility as soon as an instance was really created, and
      # keep the run failed: the theme scenario never ran.
      $report.launchRecovery = Invoke-LaunchRecovery -StartResult $startResult
      Add-Step 'launch-recovery' ([bool]$report.launchRecovery.recovered) `
        ("exit=$($startResult.exitCode) launched=$($report.launchRecovery.launched) " +
         "transaction=$($report.launchRecovery.transactionPresent) " +
         "recovered=$($report.launchRecovery.recovered) " +
         "residualPids=$(@($report.launchRecovery.residualPids) -join ',') " +
         "portListenerOwners=$(@($report.launchRecovery.portListenerOwners) -join ',') $($report.launchRecovery.detail)")
      Assert-Step 'start' $false "start-zcode-dream-skin exit $($startResult.exitCode)"
    }
    $managedState = & $readState $stateRoot
    if (-not $managedState) { throw 'ACCEPTANCE_STEP_FAILED:start-state-missing' }
    Assert-Step 'state-readable' ($null -ne (Get-ZCodeDreamSkinBrowserId -State $managedState)) "state port=$($managedState.port) rootPid=$($managedState.rootPid)"

    $verify1 = Invoke-Verify 'workspace-themed'
    $counts1 = Get-Counts $verify1
    Assert-Step 'injector:zcode-verify' ($counts1.styleCount -eq 1 -and $counts1.backgroundCount -eq 1 -and $counts1.overlayCount -eq 1) `
      "style=$($counts1.styleCount) background=$($counts1.backgroundCount) overlay=$($counts1.overlayCount)"

    # Step 3: apply again, then VERIFY AGAIN — the first verify is stale the
    # moment the second apply runs, so reusing it would prove nothing.
    $apply2 = & $injector 'zcode-apply' $managedState $null $ScriptsDir $AcceptanceDir $report.zcodeVersion $presetArt
    Assert-Step 'injector:zcode-apply:2' ($apply2.exitCode -eq 0) "second zcode-apply exit $($apply2.exitCode)"
    $verifyTimestampBeforeReapply = $verify1.reportedAt
    $verify2 = Invoke-Verify $null
    $counts2 = Get-Counts $verify2
    $fresh = $verify2.reportedAt -and ($verifyTimestampBeforeReapply -ne $verify2.reportedAt)
    Assert-Step 'reapply-idempotent' `
      ($apply2.exitCode -eq 0 -and $fresh -and
       $counts2.styleCount -eq 1 -and $counts2.backgroundCount -eq 1 -and $counts2.overlayCount -eq 1) `
      "after second apply style=$($counts2.styleCount) background=$($counts2.backgroundCount) overlay=$($counts2.overlayCount) freshVerify=$fresh"

    # Step 4: renderer reload -> the watch must restore the theme automatically.
    $reload1 = & $injector 'zcode-reload' $managedState $null $ScriptsDir $AcceptanceDir $null $null
    $restored = $false
    $deadline = (& $nowOf).AddSeconds(60)
    while ((& $nowOf) -lt $deadline) {
      & $sleepOf 2000
      $poll = Invoke-Verify $null
      $pollCounts = Get-Counts $poll
      if ($pollCounts.styleCount -eq 1 -and $pollCounts.backgroundCount -eq 1) { $restored = $true; break }
    }
    Assert-Step 'reload-auto-restore' ($reload1.exitCode -eq 0 -and $restored) "reload=$($reload1.exitCode) restored=$restored"

    # Step 5: pause -> live removal only, ZCode keeps running.
    $pauseResult = & $restore 'Pause' $ScriptsDir
    $managedState = & $readState $stateRoot
    $counts3 = Get-Counts (Invoke-Verify $null)
    $zcodeAlive = & $aliveOf $managedState.rootPid
    Assert-Step 'pause-live-removal' `
      ($pauseResult.exitCode -eq 0 -and $counts3.styleCount -eq 0 -and $zcodeAlive -and [bool]$managedState.paused) `
      "exit=$($pauseResult.exitCode) style=$($counts3.styleCount) zcodeAlive=$zcodeAlive paused=$($managedState.paused)"

    # Step 6: reload while paused -> the theme must NOT come back.
    $reload2 = & $injector 'zcode-reload' $managedState $null $ScriptsDir $AcceptanceDir $null $null
    & $sleepOf 15000
    $counts4 = Get-Counts (Invoke-Verify $null)
    Assert-Step 'reload-paused-no-reinject' ($reload2.exitCode -eq 0 -and $counts4.styleCount -eq 0) "after paused reload style=$($counts4.styleCount)"

    # Step 7: resume -> re-validate and re-inject.
    $resumeResult = & $restore 'Resume' $ScriptsDir
    $counts5 = Get-Counts (Invoke-Verify 'workspace-resumed')
    Assert-Step 'resume-reapply' ($resumeResult.exitCode -eq 0 -and $counts5.styleCount -eq 1) "exit=$($resumeResult.exitCode) style=$($counts5.styleCount)"

    # Step 8: live removeTheme; ZCode keeps running.
    $removeResult = & $injector 'zcode-remove' $managedState $null $ScriptsDir $AcceptanceDir $null $null
    $managedState = & $readState $stateRoot
    $counts6 = Get-Counts (Invoke-Verify $null)
    $zcodeAlive = & $aliveOf $managedState.rootPid
    Assert-Step 'live-remove' ($removeResult.exitCode -eq 0 -and $counts6.styleCount -eq 0 -and $zcodeAlive) `
      "exit=$($removeResult.exitCode) style=$($counts6.styleCount) zcodeAlive=$zcodeAlive"

    # Step 9: full restore -> graceful close, drain, state cleared, normal relaunch.
    $fullResult = & $restore 'Full' $ScriptsDir
    & $sleepOf 5000
    $managedLeft = 0
    if ($managedState.rootPid) { $managedLeft = $(if (& $aliveOf $managedState.rootPid) { 1 } else { 0 }) }
    $listenerCount = @(& $listenersOf $managedState.port).Count
    $stateGone = -not (& $pathExists (Join-Path $stateRoot 'state.json'))
    $fullOk = ($fullResult.exitCode -eq 0 -and $managedLeft -eq 0 -and $listenerCount -eq 0 -and $stateGone)
    Assert-Step 'full-restore' $fullOk `
      "exit=$($fullResult.exitCode) managedRootLeft=$managedLeft portListeners=$listenerCount stateCleared=$stateGone"
    $fullRestoreCompleted = $fullOk
  } catch {
    $detail = String-Clean -Text $_.Exception.Message
    $report.errors += "phase B aborted: $detail"
    Add-Step 'phase-b-aborted' $false $detail
    $finalExitCode = 2
  } finally {
    # --- global fail-safe: never leave a themed ZCode behind --------------------
    if ($productStarted -and -not $fullRestoreCompleted) {
      $failSafe = [ordered]@{ triggered = $true; reason = 'phase B did not complete a full restore'; success = $false }
      try {
        $failSafeResult = & $restore 'Full' $ScriptsDir
        $failSafe.exitCode = $failSafeResult.exitCode
        $failSafe.output = $failSafeResult.output
        $failSafe.success = ($failSafeResult.exitCode -eq 0)
      } catch {
        $failSafe.exitCode = $null
        $failSafe.output = $_.Exception.Message
        $failSafe.success = $false
      }
      if (-not $failSafe.success) {
        $finalExitCode = 2
        $residualRows = @(& $rowsOf)
        $listeners = @(& $listenersOf $(if ($managedState -and $managedState.port) { $managedState.port } else { $Port }))
        $statePath = Join-Path $stateRoot 'state.json'
        $failSafe.residuals = [ordered]@{
          zcodePids = @($residualRows | ForEach-Object { [int]$_.ProcessId })
          managedRootPid = $(if ($managedState -and $managedState.rootPid) { [int]$managedState.rootPid } else { $null })
          port = $(if ($managedState -and $managedState.port) { $managedState.port } else { $Port })
          portListenerOwners = @($listeners | ForEach-Object { [int]$_.OwningProcess })
          statePath = $statePath
          statePathPresent = (& $pathExists $statePath)
        }
        Write-Host (Format-ZCodeDreamSkinLogLine -Tag 'ERROR' -Message `
          "fail-safe restore failed; residual zcodePids=$($failSafe.residuals.zcodePids -join ',') port=$($failSafe.residuals.port) listenerOwners=$($failSafe.residuals.portListenerOwners -join ',') statePath=$statePath present=$($failSafe.residuals.statePathPresent)")
      }
      $report.failSafeRestore = $failSafe
    }
    Write-AcceptanceReport
  }

  # Every step failure records an error (Assert-Step throws into the catch above), so
  # a recorded error is the one thing that can still fail an otherwise clean run.
  if ($report.errors.Count -gt 0 -and $finalExitCode -eq 0) { $finalExitCode = 2 }
  # A dictionary ENTRY, not Add-Member: ConvertTo-Json serializes the entries of an
  # ordered dictionary, so a property added to the wrapper never reaches the file.
  $report.stepOrder = @($order)
  Write-AcceptanceReport
  return @{ ExitCode = $finalExitCode; Events = $order; Report = $report }
}

function String-Clean {
  param([string]$Text)
  ($Text -replace '[\r\n\t]+', ' ').Trim()
}

if ($MyInvocation.InvocationName -ne '.') {
  $result = Invoke-ZCodeLiveAcceptance -ZCodePath $ZCodePath -Port $Port
  exit $result.ExitCode
}
