<#
Phase 1 CDP acceptance for ZCode Dream Skin.

Two modes, and only one of them is the acceptance gate.

  Phase 1 (default)               The gate. It refuses to run at all while any
                                  ZCode process exists, and it launches ZCode
                                  with no extra profile flag so the renderer it
                                  inspects is the real signed-in workspace of the
                                  user's default profile.

  -DiagnosticIsolatedProfile      Investigation only. It launches an isolated
                                  instance on its own temporary --user-data-dir.
                                  It can never satisfy the gate: the five gate
                                  booleans stay false and its observations are
                                  written under diagnosticResults instead.

Why Phase 1 refuses to launch alongside a running ZCode: in this environment a
second launch cannot coexist with a running instance. An isolated launch -- with
or without CDP arguments, and with its own --user-data-dir -- starts, spawns
children, then exits with code 0 and never opens a port. That behaviour is
reproducible, but its internal cause is not proven: it is *consistent with* a
machine-wide single-instance guard, and this harness does not attribute it unless
the evidence supports that classification (see launchFailure in the report). A
fresh profile would additionally show an onboarding surface rather than the
workspace the gate must inspect.

Safety, in both modes: only the process tree this script started is ever
inspected or closed, no other process is terminated, CDP stays on loopback, and a
port that is already taken stops the run instead of competing for it.

Launcher handoff: a launch may hand off. The PID returned by Start-Process is
trusted only while it still exists; once it is gone, the main process is
re-resolved from processes that did not exist before this launch, so a delayed
handoff is adopted instead of being misread as a failed launch.

Exit codes: 0 the gate passed 5/5 (the DOM inventory wrote its file and cleaned up);
1 the run happened and did not succeed; 3 the run was blocked by a precondition (an
existing ZCode instance, or a busy port); 4 the DOM inventory was written but cleanup
was incomplete, so the app or its debug port is still around and the run is not a
complete success.
#>
[CmdletBinding()]
param(
  [string]$ZCodePath = '',
  [ValidateRange(1024, 65535)][int]$Port = 9335,
  [string]$ReportPath = '',
  [switch]$DiagnosticIsolatedProfile,
  [switch]$DomInventory,
  [switch]$KeepRunning,
  [ValidateRange(5, 180)][int]$StartupTimeoutSeconds = 60,
  [ValidateRange(5, 120)][int]$ReadinessTimeoutSeconds = 60,
  [ValidateRange(1, 100000)][int]$MinElements = 100,
  [ValidateRange(0, 60)][int]$SettleSeconds = 3
)

$ErrorActionPreference = 'Stop'
$windowsRoot = Split-Path -Parent $PSScriptRoot
$repositoryRoot = Split-Path -Parent $windowsRoot
. (Join-Path $PSScriptRoot 'common-windows.ps1')

if (-not $ReportPath) {
  $ReportPath = Join-Path $repositoryRoot '.lemon\evidence\phase1-report.json'
}
$ReportPath = [System.IO.Path]::GetFullPath($ReportPath)
$evidenceDirectory = Split-Path -Parent $ReportPath
New-Item -ItemType Directory -Path $evidenceDirectory -Force | Out-Null

$gateNames = @('pass1Launch', 'pass2CdpEndpoint', 'pass3MainRenderer',
  'pass4RuntimeEvaluate', 'pass5RemoveTheme')

$runMode = 'phase1'
if ($DiagnosticIsolatedProfile) { $runMode = 'diagnostic-isolated-profile' }
elseif ($DomInventory) { $runMode = 'dom-inventory' }

$report = [ordered]@{
  schemaVersion = 3
  mode = $runMode
  countsTowardPhase1 = ($runMode -eq 'phase1')
  generatedAt = (Get-Date).ToUniversalTime().ToString('o')
  port = $Port
  zcodePath = $ZCodePath
  zcodeFingerprint = @{}
  launchContext = [ordered]@{
    userDataDir = ''
    preExistingZcodeInstances = 0
    preExistingTerminated = $false
    rootPid = 0
  }
  pass1Launch = $false
  pass2CdpEndpoint = $false
  pass3MainRenderer = $false
  pass4RuntimeEvaluate = $false
  pass5RemoveTheme = $false
  stepEvidence = [ordered]@{ pass1 = @{}; pass2 = @{} }
  diagnosticResults = [ordered]@{}
  launchOutcome = ''
  blockers = @()
  blockedReason = ''
  selectedTarget = @{}
  injectorReport = @{}
  inventory = [ordered]@{ path = ''; exitCode = $null }
  screenshots = @{}
  errors = @()
  exitCode = 1
  evidenceDirectory = $evidenceDirectory
}

function Save-Phase1Report {
  $report.exitCode = $script:finalExitCode
  [System.IO.File]::WriteAllText($ReportPath, ($report | ConvertTo-Json -Depth 8),
    [System.Text.UTF8Encoding]::new($false))
}

# Called from the finally block, because a blocked run leaves the try body early
# and must still report its exit code rather than falling out as a success.
function Write-Phase1Summary {
  $gateTrue = @($gateNames | Where-Object { $report[$_] }).Count
  if ($report.countsTowardPhase1) {
    Write-Host "Phase 1: $gateTrue/5 PASS (launch=$($report.pass1Launch) cdp=$($report.pass2CdpEndpoint) renderer=$($report.pass3MainRenderer) inject=$($report.pass4RuntimeEvaluate) remove=$($report.pass5RemoveTheme))"
  } elseif ($report.mode -eq 'dom-inventory') {
    if ($report.inventory.path) {
      Write-Host "[INVENTORY] written to $($report.inventory.path)"
    } else {
      Write-Host '[INVENTORY] no inventory file was written'
    }
  } else {
    $diagnosticTrue = @($gateNames | Where-Object { $report.diagnosticResults[$_] }).Count
    Write-Host "[DIAGNOSTIC] $diagnosticTrue/5 observed on an isolated profile - NOT counted toward Phase 1 (gate booleans remain false)."
  }
  if ($report.blockers.Count -gt 0) { Write-Host "[BLOCKED] $($report.blockedReason)" }
  if ($report.launchOutcome) { Write-Host "[LAUNCH-OUTCOME] $($report.launchOutcome)" }
  if ($report.stepEvidence.cleanup) {
    $cleanup = $report.stepEvidence.cleanup
    Write-Host ("[CLEANUP] appExited=$($cleanup.rootExited) portReleased=$($cleanup.portReleased) " +
      "remainingListenerPids=$(if ($cleanup.remainingListenerPids.Count) { $cleanup.remainingListenerPids -join ',' } else { 'none' })")
  }
  Write-Host "[REPORT] $ReportPath"
}

function Add-Phase1Error([string]$Message) {
  $script:report.errors += $Message
}

function Add-Phase1Blocker([string]$Blocker, [string]$Reason) {
  $script:report.blockers += $Blocker
  if (-not $script:report.blockedReason) { $script:report.blockedReason = $Reason }
}

# In diagnostic mode a gate boolean is never written: observations go to their
# own section, so an isolated-profile run cannot be mistaken for acceptance.
function Set-GateResult([string]$Name, [bool]$Value) {
  if ($report.countsTowardPhase1) { $report[$Name] = $Value }
  else { $report.diagnosticResults[$Name] = $Value }
}

function Get-CdpPageTargetCount {
  param([Parameter(Mandatory = $true)][int]$TargetPort)
  try {
    $listed = Invoke-RestMethod -Uri "http://127.0.0.1:$TargetPort/json/list" `
      -TimeoutSec 3 -MaximumRedirection 0
    return @($listed | Where-Object { $_.type -eq 'page' }).Count
  } catch {
    return 0
  }
}

$launchedProcess = $null
$profileDirectory = $null
$rootPid = 0
$finalExitCode = 1
try {
  # --- Step 0: executable identity ------------------------------------------
  if (-not $ZCodePath) { $ZCodePath = Resolve-DreamSkinZCodeExecutable }
  $report.zcodePath = $ZCodePath
  $metadata = Assert-DreamSkinZCodeIdentity -Path $ZCodePath
  $fingerprint = Get-ZCodeFingerprint -Path $ZCodePath
  $report.zcodeFingerprint = $fingerprint
  Write-Host "[IDENTITY] $($metadata.ProductName) $($metadata.FileVersion) sha256=$($fingerprint.sha256)"

  # --- Step 1: preconditions -------------------------------------------------
  $processRows = @(Get-ZCodeProcessSnapshot)
  $preExisting = @(Get-ZCodeRunningProcessRows -ProcessRows $processRows)
  $preExistingIds = @($preExisting | ForEach-Object { [int]$_.ProcessId })
  $report.launchContext.preExistingZcodeInstances = $preExisting.Count

  if ($preExisting.Count -gt 0) {
    Write-Host "[PROCESS] $($preExisting.Count) ZCode process(es) already running; none will be touched."
  }
  if (-not $DiagnosticIsolatedProfile -and $preExisting.Count -gt 0) {
    $blockerDetail = if ($runMode -eq 'dom-inventory') {
      "The DOM inventory needs the app to itself: a second launch cannot coexist with a running " +
      "instance in this environment, and the inventory must come from your real workspace."
    } else {
      "Phase 1 requires no ZCode running: a second launch cannot coexist with a running instance " +
      "in this environment, and the gate must launch with your default profile so the renderer it " +
      "inspects is the real workspace."
    }
    Add-Phase1Blocker 'existing-zcode-instance' (
      "$blockerDetail Close ZCode normally, then run this script again. " +
      'Nothing was launched and no process was touched.')
    Write-Host "[BLOCKED] an existing ZCode instance is running; $runMode did not launch anything."
    $finalExitCode = 3
    return
  }

  $listeners = @(Get-ZCodePortListenerRows -Port $Port)
  if ($listeners.Count -gt 0) {
    $owners = ($listeners | ForEach-Object { [int]$_.OwningProcess }) -join ', '
    Add-Phase1Blocker 'port-in-use' (
      "port $Port is already in use by PID $owners; the run stops instead of competing for it, " +
      'and the owner is left untouched')
    Write-Host "[BLOCKED] port $Port is already in use by PID $owners."
    $finalExitCode = 3
    return
  }

  # --- Step 2: launch --------------------------------------------------------
  if ($DiagnosticIsolatedProfile) {
    $profileDirectory = Join-Path $env:TEMP ('zcode-dream-skin-diagnostic-profile-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $profileDirectory -Force | Out-Null
    $report.launchContext.userDataDir = $profileDirectory
    Write-Host '[DIAGNOSTIC] isolated temporary profile; this run can never count toward Phase 1.'
  } else {
    $report.launchContext.userDataDir = '<default user profile>'
  }
  $launchArguments = @(New-ZCodeLaunchArguments -Port $Port)
  if ($DiagnosticIsolatedProfile) {
    $launchArguments += (ConvertTo-DreamSkinProcessArgument -Value "--user-data-dir=$profileDirectory")
  }
  $launchedProcess = Start-Process -FilePath $ZCodePath -ArgumentList $launchArguments -PassThru
  Write-Host "[LAUNCH] ZCode PID $($launchedProcess.Id) with $($launchArguments -join ' ')"

  # --- Step 3: first sample of the launched process --------------------------
  # The launcher PID is trusted only while it exists; a delayed handoff is
  # re-resolved from the settled snapshot in Step 4, so it is adopted rather than
  # misreported as a failed launch.
  $launchSample = Resolve-ZCodeMainProcess -ProcessRows @(Get-ZCodeProcessSnapshot) `
    -LaunchedPid ([int]$launchedProcess.Id) `
    -LaunchedProcessExited ([bool]$launchedProcess.HasExited) `
    -PreExistingProcessIds $preExistingIds `
    -VerifiedExecutablePath $ZCodePath
  $rootPid = $launchSample.rootPid
  $rootResolvedAtLaunch = $launchSample.rootAlive
  $report.launchContext.rootPid = $rootPid

  # --- Step 4: settle, then one settled fact block ---------------------------
  # Every launch fact is sampled once, after the settle interval, so a report can
  # never mix an "alive" sample with an "exited" sample taken at another moment.
  # A process that appears briefly is not a launch.
  if ($SettleSeconds -gt 0) { Start-Sleep -Seconds $SettleSeconds }
  # Sample the launch handle before the process table: an exit observed here also
  # explains an absent row below, so the two recorded facts cannot contradict.
  $launchedExitedSettled = [bool]$launchedProcess.HasExited
  $settledExitCode = $null
  if ($launchedExitedSettled) { $settledExitCode = [int]$launchedProcess.ExitCode }
  $processRows = @(Get-ZCodeProcessSnapshot)
  $settledResolution = Resolve-ZCodeMainProcess -ProcessRows $processRows `
    -LaunchedPid ([int]$launchedProcess.Id) `
    -LaunchedProcessExited $launchedExitedSettled `
    -PreExistingProcessIds $preExistingIds `
    -VerifiedExecutablePath $ZCodePath
  $rootPid = $settledResolution.rootPid
  $rootAliveSecond = $settledResolution.rootAlive
  $report.launchContext.rootPid = $rootPid
  $descendantCount = 0
  $mainWindowPresent = $false
  if ($rootAliveSecond) {
    $treeIds = @(Get-ZCodeDescendantProcessIds -RootPid $rootPid -ProcessRows $processRows)
    $descendantCount = @($processRows | Where-Object {
        [string]$_.Name -ieq 'ZCode.exe' -and $treeIds -contains [int]$_.ProcessId -and
        [int]$_.ProcessId -ne $rootPid
      }).Count
    $live = Get-Process -Id $rootPid -ErrorAction SilentlyContinue
    if ($live) { $mainWindowPresent = ([int]$live.MainWindowHandle -ne 0) }
  }
  $newMainProcessFound = $rootAliveSecond

  # --- Step 5: CDP endpoint facts -------------------------------------------
  $deadline = (Get-Date).AddSeconds($StartupTimeoutSeconds)
  $identity = $null
  while ((Get-Date) -lt $deadline -and -not $identity) {
    $identity = Get-DreamSkinCdpBrowserIdentity -Port $Port
    if (-not $identity) { Start-Sleep -Milliseconds 500 }
  }
  $pageTargetCount = if ($identity) { Get-CdpPageTargetCount -TargetPort $Port } else { 0 }

  # --- Step 6: classify from the settled evidence, then gate -----------------
  $report.launchOutcome = Get-ZCodeLaunchOutcome `
    -PreExistingInstanceCount $preExisting.Count `
    -LaunchedProcessExited ($launchedExitedSettled -or -not $rootAliveSecond) `
    -ExitCode $settledExitCode -NewMainProcessFound $newMainProcessFound

  $report.stepEvidence.pass1 = [ordered]@{
    launchedPid = [int]$launchedProcess.Id
    rootPid = $rootPid
    rootSource = $settledResolution.source
    successorCandidateCount = $settledResolution.candidateCount
    settleSeconds = $SettleSeconds
    rootResolvedAtLaunch = $rootResolvedAtLaunch
    exitedBySettleSample = $launchedExitedSettled
    exitCodeBySettleSample = $settledExitCode
    rootAliveAfterSettle = $rootAliveSecond
    zcodeDescendantCount = $descendantCount
    mainWindowPresent = $mainWindowPresent
    cdpPageTargetCount = $pageTargetCount
    newMainProcessFound = $newMainProcessFound
  }
  $pass1 = Test-ZCodeMainInstanceEvidence -RootAlive $rootResolvedAtLaunch `
    -RootAliveAtSecondSample $rootAliveSecond -ZcodeDescendantCount $descendantCount `
    -MainWindowPresent $mainWindowPresent -CdpEndpointWithPageTarget ($pageTargetCount -gt 0)
  Set-GateResult 'pass1Launch' $pass1

  if (-not $identity) {
    $report.stepEvidence.pass2 = [ordered]@{
      jsonVersionAvailable = $false
      jsonListAvailable = $false
      note = 'no CDP endpoint ever opened, so /json/version and /json/list were never reachable'
    }
    # A process that stayed alive but never served CDP is a failure mode of its
    # own; only a clean exit is eligible for the guard classification.
    $failureClassification = if ($report.launchOutcome -ceq 'running') {
      'launch-without-cdp-endpoint'
    } else {
      $report.launchOutcome
    }
    $report.launchFailure = [ordered]@{
      classification = $failureClassification
      processOutcome = $report.launchOutcome
      exitCode = $settledExitCode
      exitedBySettleSample = $launchedExitedSettled
      newMainProcessFound = $newMainProcessFound
      preExistingZcodeInstances = $preExisting.Count
      rawEvidence = 'the launch never opened a CDP endpoint; see stepEvidence.pass1 and phase1-process-tree.json'
    }
    if ($failureClassification -ceq 'existing-instance-single-instance-guard') {
      $report.launchFailure.supportedBy = @(
        'a ZCode instance was already running before this launch',
        'the launched process exited with code 0',
        'no new main process appeared'
      )
    } elseif ($preExisting.Count -gt 0) {
      $report.launchFailure.suspectedCause = (
        'an existing instance was present, but this evidence does not prove it caused the outcome')
    }
    throw "E06_CDP_ENDPOINT_UNAVAILABLE: no CDP endpoint appeared on port $Port within $StartupTimeoutSeconds s"
  }

  $listeners = @(Get-ZCodePortListenerRows -Port $Port)
  $null = Assert-DreamSkinZCodePortOwnership -Port $Port -RootPid $rootPid `
    -Listeners $listeners -ProcessRows $processRows
  $loopbackOnly = (Test-DreamSkinWebSocketUrl -Value $identity.WebSocketDebuggerUrl -Port $Port)
  $report.stepEvidence.pass2 = [ordered]@{
    browserId = $identity.BrowserId
    browser = $identity.Browser
    targetCount = $identity.TargetCount
    pageTargetCount = $pageTargetCount
    loopbackWebSocket = [bool]$loopbackOnly
    portOwnerPid = @($listeners | ForEach-Object { [int]$_.OwningProcess })
    rootPid = $rootPid
  }
  Set-GateResult 'pass2CdpEndpoint' ([bool]($loopbackOnly -and $identity.BrowserId))
  Write-Host "[CDP] browserId=$($identity.BrowserId) pageTargets=$pageTargetCount loopback=$loopbackOnly"

  if ($runMode -eq 'dom-inventory') {
    # Read-only pass: no marker, no style, no theme. It waits for the workspace to
    # hydrate, then records selectors and stable attributes for the DOM map.
    $node = Get-DreamSkinNodeRuntime
    $injectorPath = Join-Path $PSScriptRoot 'injector.mjs'
    $inventoryPath = Join-Path $evidenceDirectory 'zcode-dom-inventory.json'
    $inventoryArguments = @(
      $injectorPath,
      '--mode', 'zcode-dom-inventory',
      '--port', "$Port",
      '--browser-id', $identity.BrowserId,
      '--report', $inventoryPath,
      '--min-elements', "$MinElements",
      '--zcode-version', $metadata.FileVersion,
      '--timeout-ms', "$($ReadinessTimeoutSeconds * 1000)"
    )
    if (-not $KeepRunning) { $inventoryArguments += '--close-browser' }
    $inventoryResult = Invoke-DreamSkinNative -FilePath $node.Path -ArgumentList $inventoryArguments
    $inventoryLog = @($inventoryResult.Output) -join [Environment]::NewLine
    [System.IO.File]::WriteAllText((Join-Path $evidenceDirectory 'zcode-dom-inventory.log'),
      $inventoryLog, [System.Text.UTF8Encoding]::new($false))
    Write-Host $inventoryLog
    $report.inventory = [ordered]@{
      path = if (Test-Path -LiteralPath $inventoryPath -PathType Leaf) { $inventoryPath } else { '' }
      exitCode = [int]$inventoryResult.ExitCode
    }
    if (-not $report.inventory.path) {
      Add-Phase1Error 'E11_WORKSPACE_NOT_READY: the injector produced no inventory file'
    } elseif ($inventoryResult.ExitCode -ne 0) {
      Add-Phase1Error "the inventory injector exited with code $($inventoryResult.ExitCode)"
    }
    $finalExitCode = if ($report.errors.Count -eq 0) { 0 } else { 1 }
    return
  }

  # --- Step 6: renderer selection, marker injection, removal ----------------
  $node = Get-DreamSkinNodeRuntime
  $injectorPath = Join-Path $PSScriptRoot 'injector.mjs'
  $injectorReportPath = Join-Path $evidenceDirectory 'phase1-injector.json'
  $screenshotInjected = Join-Path $evidenceDirectory 'phase1-poc-injected.png'
  $screenshotRemoved = Join-Path $evidenceDirectory 'phase1-poc-removed.png'
  $injectorArguments = @(
    $injectorPath,
    '--mode', 'zcode-poc',
    '--port', "$Port",
    '--browser-id', $identity.BrowserId,
    '--report', $injectorReportPath,
    '--screenshot-injected', $screenshotInjected,
    '--screenshot-removed', $screenshotRemoved,
    '--timeout-ms', '30000'
  )
  if (-not $KeepRunning) { $injectorArguments += '--close-browser' }
  $injectorResult = Invoke-DreamSkinNative -FilePath $node.Path -ArgumentList $injectorArguments
  $injectorLog = @($injectorResult.Output) -join [Environment]::NewLine
  [System.IO.File]::WriteAllText((Join-Path $evidenceDirectory 'phase1-injector.log'), $injectorLog,
    [System.Text.UTF8Encoding]::new($false))
  Write-Host $injectorLog

  if (Test-Path -LiteralPath $injectorReportPath -PathType Leaf) {
    $injectorData = Get-Content -LiteralPath $injectorReportPath -Raw | ConvertFrom-Json
    $report.injectorReport = $injectorData
    Set-GateResult 'pass3MainRenderer' ([bool]$injectorData.pass3MainRenderer)
    Set-GateResult 'pass4RuntimeEvaluate' ([bool]$injectorData.pass4RuntimeEvaluate)
    Set-GateResult 'pass5RemoveTheme' ([bool]$injectorData.pass5RemoveTheme)
    if ($injectorData.pass2CdpEndpoint) { Set-GateResult 'pass2CdpEndpoint' $true }
    $report.selectedTarget = $injectorData.selectedTarget
    foreach ($injectorError in @($injectorData.errors)) { Add-Phase1Error "injector: $injectorError" }
  } else {
    Add-Phase1Error 'E07_NO_RENDERER_TARGET: the injector produced no report'
  }
  if ($injectorResult.ExitCode -ne 0) {
    Add-Phase1Error "injector exited with code $($injectorResult.ExitCode)"
  }
  $report.screenshots = [ordered]@{
    injected = if (Test-Path -LiteralPath $screenshotInjected) { $screenshotInjected } else { '' }
    removed = if (Test-Path -LiteralPath $screenshotRemoved) { $screenshotRemoved } else { '' }
  }

  # The gate is only ever read in Phase 1 mode: a diagnostic run reports its own
  # observations and leaves the five gate booleans untouched.
  if ($report.countsTowardPhase1) {
    $passed = @($gateNames | Where-Object { $report[$_] }).Count
    $finalExitCode = if ($passed -eq 5) { 0 } else { 1 }
  } else {
    $finalExitCode = 0
  }
} catch {
  Add-Phase1Error $_.Exception.Message
  if ($finalExitCode -ne 3) { $finalExitCode = 1 }
} finally {
  # Cleanup is part of the result, not an afterthought: an app left running on a
  # bound debug port means this run did not finish, however complete its output file.
  $cleanupRequested = (-not $KeepRunning)
  $closeTargets = @()
  if ($cleanupRequested) {
    if ($launchedProcess) { $closeTargets += [int]$launchedProcess.Id }
    if ($rootPid -ne 0) { $closeTargets += [int]$rootPid }
    $closeTargets = @($closeTargets | Select-Object -Unique)
  }
  foreach ($targetPid in $closeTargets) {
    try {
      $live = Get-Process -Id $targetPid -ErrorAction SilentlyContinue
      if ($live -and $live.MainWindowHandle -ne 0) { $null = $live.CloseMainWindow() }
    } catch {
      Add-Phase1Error "graceful close request failed for PID ${targetPid}: $($_.Exception.Message)"
    }
  }
  if ($closeTargets.Count -gt 0) {
    $closeDeadline = (Get-Date).AddSeconds(20)
    while ((Get-Date) -lt $closeDeadline -and
      @($closeTargets | Where-Object { Get-Process -Id $_ -ErrorAction SilentlyContinue }).Count -gt 0) {
      Start-Sleep -Milliseconds 500
    }
    $survivors = @($closeTargets | Where-Object { Get-Process -Id $_ -ErrorAction SilentlyContinue })
    if ($survivors.Count -gt 0) {
      Add-Phase1Error "the ZCode instance this script started (PID $($survivors -join ', ')) did not close within 20 s; it was left running rather than force-killed"
    }
  }
  $remainingListeners = @(Get-ZCodePortListenerRows -Port $Port)
  $portDeadline = (Get-Date).AddSeconds(15)
  while ($remainingListeners.Count -gt 0 -and (Get-Date) -lt $portDeadline) {
    Start-Sleep -Milliseconds 500
    $remainingListeners = @(Get-ZCodePortListenerRows -Port $Port)
  }
  $rootExited = $null
  if ($rootPid -ne 0) {
    $rootExited = -not [bool](Get-Process -Id $rootPid -ErrorAction SilentlyContinue)
  }
  $report.stepEvidence.cleanup = [ordered]@{
    gracefulCloseRequested = $cleanupRequested
    closeTargets           = $closeTargets
    rootExited             = $rootExited
    portReleased           = ($remainingListeners.Count -eq 0)
    remainingListenerPids  = @($remainingListeners | ForEach-Object { [int]$_.OwningProcess })
  }
  if ($profileDirectory -and (Test-Path -LiteralPath $profileDirectory)) {
    if (-not $launchedProcess -or $launchedProcess.HasExited) {
      try { Remove-Item -LiteralPath $profileDirectory -Recurse -Force -ErrorAction Stop } catch {
        Add-Phase1Error "could not remove the diagnostic profile directory: $($_.Exception.Message)"
      }
    }
  }
  try {
    $tree = @(Get-ZCodeProcessSnapshot | ForEach-Object {
        [pscustomobject]@{
          processId = [int]$_.ProcessId
          parentProcessId = [int]$_.ParentProcessId
          name = [string]$_.Name
          typeSwitch = if ([string]$_.CommandLine -match '--type=') { 'child' } else { 'main' }
        }
      })
    [System.IO.File]::WriteAllText((Join-Path $evidenceDirectory 'phase1-process-tree.json'),
      ($tree | ConvertTo-Json -Depth 4), [System.Text.UTF8Encoding]::new($false))
  } catch {
    Add-Phase1Error "process tree evidence failed: $($_.Exception.Message)"
  }
  # The settle sample above is a point in time; this is what happened after it, so
  # the reader is never left guessing whether the process survived the run.
  if ($launchedProcess) {
    try {
      $exitedAtEnd = [bool]$launchedProcess.HasExited
      $report.stepEvidence.launchFate = [ordered]@{
        exitedAtEndOfRun = $exitedAtEnd
        exitCodeAtEndOfRun = if ($exitedAtEnd) { [int]$launchedProcess.ExitCode } else { $null }
      }
    } catch {
      Add-Phase1Error "launch fate evidence failed: $($_.Exception.Message)"
    }
  }
  $cleanup = $report.stepEvidence.cleanup
  $cleanupComplete = $true
  if ($cleanup) {
    $cleanupComplete = [bool]$cleanup.portReleased -and ($cleanup.rootExited -ne $false)
    $report.cleanupComplete = $cleanupComplete
  }
  if ($runMode -eq 'dom-inventory' -and $finalExitCode -eq 0 -and -not $cleanupComplete) {
    $finalExitCode = 4
  }
  Save-Phase1Report
  Write-Phase1Summary
  exit $finalExitCode
}
