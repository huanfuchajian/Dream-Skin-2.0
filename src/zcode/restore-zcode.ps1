# ZCode Dream Skin product entry: pause, resume and full restore.
#   Pause  : live-remove the theme only; ZCode keeps running. A reload during a
#            pause is never re-skinned (watch pause gate + renderer lock).
#   Resume : clear the pause; the theme is re-validated and re-injected.
#   Full   : live-remove, gracefully close the managed ZCode (Browser.close),
#            wait for the tree AND the debug port to drain, clear the state, and
#            relaunch ZCode normally without CDP. A failed step keeps the state and
#            reports it so the uninstaller can abort instead of half-removing a skin.
#
# The whole flow lives in Invoke-ZCodeDreamSkinRestore with every machine touch as a
# seam, so the order of a restore is assertable without a real session; the guarded
# entry at the bottom is the only part that touches the real machine.
[CmdletBinding()]
param(
  [ValidateSet('Pause', 'Resume', 'Full')][string]$Mode = 'Full',
  [string]$StateRoot = '',
  [int]$ShutdownTimeoutSeconds = 60
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common-windows.ps1')
. (Join-Path $PSScriptRoot 'theme-windows.ps1')
. (Join-Path $PSScriptRoot 'zcode-product.ps1')
. (Join-Path $PSScriptRoot 'zcode-theme-store.ps1')

function Write-ZCodeRestoreLog {
  param([string]$Tag, [string]$Message)
  Write-Host (Format-ZCodeDreamSkinLogLine -Tag $Tag -Message $Message)
}

function Get-ZCodeStaleStateVerdict {
  <#
  A state whose session is gone is stale evidence, not a live session. It is only
  ever archived when the recorded root, the recorded watcher and the recorded port
  are all released; a live root, a live watcher, a reused root PID or any listener
  on the recorded port is refused and the file stays exactly where it is.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]$State,
    [object[]]$ProcessRows = @(),
    [object[]]$PortListeners = @()
  )
  $rootPid = [int]$State.rootPid
  $recordedPath = "$($State.zcodePath)"
  $rootRows = @($ProcessRows | Where-Object { [int]$_.ProcessId -eq $rootPid })
  if ($rootRows.Count -gt 0) {
    $alivePath = "$($rootRows[0].ExecutablePath)"
    if (-not $alivePath) {
      return @{ action = 'refuse'; reason = "root PID $rootPid is running and cannot be inspected" }
    }
    if (Test-DreamSkinPathEqual -Left $alivePath -Right $recordedPath) {
      return @{ action = 'refuse'; reason = "the recorded ZCode session (PID $rootPid) is still running" }
    }
    return @{ action = 'refuse'; reason = "root PID $rootPid now belongs to a different executable ($alivePath)" }
  }
  $watchPid = [int]$State.watchPid
  if ($watchPid -gt 0 -and @($ProcessRows | Where-Object { [int]$_.ProcessId -eq $watchPid }).Count -gt 0) {
    return @{ action = 'refuse'; reason = "the recorded watcher (PID $watchPid) is still running" }
  }
  $listeners = @($PortListeners)
  if ($listeners.Count -gt 0) {
    $owners = (@($listeners | ForEach-Object { [int]$_.OwningProcess }) | Sort-Object -Unique) -join ','
    return @{ action = 'refuse'; reason = "port $($State.port) is still owned by PID(s) $owners" }
  }
  return @{ action = 'archive'; reason = 'the recorded root, watcher and port are all released' }
}

function Invoke-ZCodeStaleStateArchive {
  <#
  Archives the stale state under a dated name instead of deleting it: the file is
  the only record of the session that produced it, and a silently removed file is a
  proven failure to diagnose. The verdict is the caller's decision; this only moves
  the file that is actually there.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)][string]$StateRoot,
    [scriptblock]$Now = $null
  )
  $nowFn = if ($Now) { $Now } else { { Get-Date } }
  $root = Get-ZCodeDreamSkinStateRoot -StateRoot $StateRoot
  $source = Join-Path $root 'state.json'
  if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { return '' }
  $stamp = (& $nowFn).ToString('yyyyMMdd-HHmmss')
  $target = Join-Path $root "state.stale-$stamp.json"
  $suffix = 1
  while (Test-Path -LiteralPath $target) {
    $target = Join-Path $root "state.stale-$stamp-$suffix.json"
    $suffix += 1
  }
  Move-Item -LiteralPath $source -Destination $target -Force
  return $target
}

function Invoke-ZCodeDreamSkinRestore {
  <#
  The whole restore with every machine touch as a seam. Returns a result object; it
  never calls exit, so both the CLI and the tests use the same code path.
  #>
  [CmdletBinding()]
  param(
    [ValidateSet('Pause', 'Resume', 'Full')][string]$Mode = 'Full',
    [string]$StateRoot = '',
    [int]$ShutdownTimeoutSeconds = 60,
    [scriptblock]$GetProcessRows = $null,
    [scriptblock]$GetPortListeners = $null,
    [scriptblock]$InvokeInjector = $null,
    [scriptblock]$Reapply = $null,
    [scriptblock]$Relaunch = $null,
    [scriptblock]$Sleep = $null,
    [scriptblock]$StopProcess = $null,
    [scriptblock]$Now = $null
  )
  $root = if ($StateRoot) { Get-ZCodeDreamSkinStateRoot -StateRoot $StateRoot } else { Get-ZCodeDreamSkinStateRoot }
  # One resolver for every installed entry point: the bundled, signature-validated
# runtime wins, and PATH is only a source-tree fallback behind the same gate.
$nodePath = (Get-DreamSkinNodeRuntime -MinimumMajor 22).Path
  $injector = Join-Path $PSScriptRoot 'injector.mjs'

  $rowsOf = if ($GetProcessRows) { $GetProcessRows } else { { @(Get-ZCodeProcessSnapshot) } }
  $listenersOf = if ($GetPortListeners) { $GetPortListeners } else {
    { param($Port) @(Get-ZCodePortListenerRows -Port $Port) }
  }
  $injectorOf = if ($InvokeInjector) { $InvokeInjector } else {
    {
      # A positional array is already one scriptblock argument. Do not comma-wrap
      # it: that nests the flags and native argument binding loses their boundaries.
      param($InjectorMode, $State, $ReportName, $ExtraArguments = @())
      $arguments = @($injector, '--mode', $InjectorMode, '--port', $State.port,
        '--browser-id', (Get-ZCodeDreamSkinBrowserId -State $State),
        '--report', (Join-Path $root $ReportName))
      if ($ExtraArguments) { $arguments += @($ExtraArguments) }
      & $nodePath @arguments
      return @{ exitCode = [int]$LASTEXITCODE; arguments = $arguments }
    }
  }
  $relaunchOf = if ($Relaunch) { $Relaunch } else { { param($Path) Start-Process -FilePath $Path } }
  $reapplyOf = if ($Reapply) { $Reapply } else {
    {
      param($StateDirectory)
      # Reuse the authoritative reapply orchestration: executable version,
      # fresh report validation, selected theme and owned watcher re-arming.
      # An independent process avoids dot-source parameter/scope contamination.
      $startEntry = Join-Path $PSScriptRoot 'start-zcode-dream-skin.ps1'
      & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy RemoteSigned -File $startEntry -StateRoot $StateDirectory | Out-Host
      return @{ exitCode = [int]$LASTEXITCODE }
    }
  }
  $sleepOf = if ($Sleep) { $Sleep } else { { param($Ms) Start-Sleep -Milliseconds $Ms } }

  $steps = [System.Collections.Generic.List[string]]::new()
  $result = [ordered]@{
    mode          = $Mode
    exitCode      = 0
    primaryError  = ''
    steps         = $steps
    browserId     = ''
    rootPid       = 0
    port          = 0
    watchAction   = ''
    watchReason   = ''
    residualPids  = @()
    portOwners    = @()
  }
  try {
    $state = Read-ZCodeDreamSkinState -StateRoot $root
    if (-not $state) {
      $steps.Add('no-state')
      Write-ZCodeRestoreLog 'RESTORE' 'no managed session state; nothing to restore'
      return $result
    }
    $result.rootPid = [int]$state.rootPid
    $result.port = [int]$state.port
    $result.browserId = Get-ZCodeDreamSkinBrowserId -State $state

    if ($Mode -eq 'Pause') {
      $state = Set-ZCodeDreamSkinPaused -State $state -Paused $true
      $null = Write-ZCodeDreamSkinState -StateRoot $root -State $state
      $steps.Add('state-paused')
      if ([int](& $injectorOf 'zcode-pause' $state 'last-pause-report.json').exitCode -ne 0) {
        throw 'E10_REMOVE_THEME_FAILED: the live pause failed; state kept with paused=true for repair'
      }
      $steps.Add('live-pause')
      Write-ZCodeRestoreLog 'RESTORE' 'paused: theme removed live, ZCode keeps running'
      return $result
    }

    if ($Mode -eq 'Resume') {
      $state = Set-ZCodeDreamSkinPaused -State $state -Paused $false
      $null = Write-ZCodeDreamSkinState -StateRoot $root -State $state
      $steps.Add('state-resumed')
      if ([int](& $injectorOf 'zcode-resume' $state 'last-resume-report.json' (,@())).exitCode -ne 0) {
        throw 'E09_RUNTIME_EVALUATE_FAILED: the renderer resume unlock failed'
      }
      if ([int](& $reapplyOf $root).exitCode -ne 0) {
        throw 'E09_RUNTIME_EVALUATE_FAILED: the resumed application failed; see last-apply-report.json'
      }
      $steps.Add('live-apply')
      Write-ZCodeRestoreLog 'RESTORE' 'resumed: theme re-validated and re-applied'
      return $result
    }

    # --- Full restore -----------------------------------------------------------
    $watch = Stop-ZCodeManagedWatch -State $state -StateRoot $root -InjectorPath $injector `
      -NodePath $nodePath -GetProcessRows $GetProcessRows -Sleep $Sleep -StopProcess $StopProcess `
      -TimeoutSeconds 10
    $state = $watch.state
    $result.watchAction = $watch.action
    $result.watchReason = $watch.reason
    $steps.Add("watch-$($watch.action)")
    if ($watch.action -eq 'refuse') {
      # The recorded PID is not this product's watcher, so nothing is stopped. The
      # restore still continues: a foreign process cannot re-inject this theme, and
      # blanking the reported reason would hide a genuinely unreachable watcher.
      Write-ZCodeRestoreLog 'RESTORE' "the recorded watcher was not stopped: $($watch.reason)"
    }

    Write-ZCodeRestoreLog 'RESTORE' 'live removal started'
    if ([int](& $injectorOf 'zcode-remove' $state 'last-remove-report.json' (,@())).exitCode -ne 0) {
      # State and run files stay untouched so the failure can be repaired and an
      # uninstaller must abort rather than leave a half-removed skin.
      throw 'E10_REMOVE_THEME_FAILED: live removal did not verify; state kept for repair'
    }
    $steps.Add('live-remove')
    Write-ZCodeRestoreLog 'RESTORE' 'live removal verified'

    $null = & $injectorOf 'zcode-close' $state 'last-close-report.json' (,@())
    $steps.Add('browser-close')

    # Success is judged by the machine, never by a command's exit code: the recorded
    # tree must be gone AND the debug port must be free before the state is cleared.
    $drained = $false
    $attempts = [Math]::Max(1, [int]($ShutdownTimeoutSeconds * 2))
    for ($attempt = 0; $attempt -lt $attempts; $attempt++) {
      $rows = @(& $rowsOf)
      $treeIds = @(Get-ZCodeDescendantProcessIds -RootPid ([int]$state.rootPid) -ProcessRows $rows)
      $alive = @($rows | Where-Object { $treeIds -contains [int]$_.ProcessId })
      $listeners = @(& $listenersOf ([int]$state.port))
      if ($alive.Count -eq 0 -and $listeners.Count -eq 0) { $drained = $true; break }
      if ($attempt -lt ($attempts - 1)) { & $sleepOf 500 | Out-Null }
    }
    if (-not $drained) {
      $result.residualPids = @($alive | ForEach-Object { [int]$_.ProcessId })
      $result.portOwners = @($listeners | ForEach-Object { [int]$_.OwningProcess })
      throw ('E06_CDP_ENDPOINT_UNAVAILABLE: the managed ZCode tree or its debug port did not drain ' +
        "after the graceful close (residualPids=$($result.residualPids -join ',') " +
        "portListenerOwners=$($result.portOwners -join ',')); state kept")
    }
    $steps.Add('drained')
    Write-ZCodeRestoreLog 'PROCESS' 'managed tree and debug port drained'

    Clear-ZCodeDreamSkinState -StateRoot $root
    $steps.Add('state-cleared')
    Write-ZCodeRestoreLog 'RESTORE' 'state cleared'
    & $relaunchOf "$($state.zcodePath)" | Out-Null
    $steps.Add('relaunch')
    Write-ZCodeRestoreLog 'LAUNCH' 'zcode relaunched normally without CDP'
    Write-ZCodeRestoreLog 'RESTORE' 'full restore complete'
    return $result
  } catch {
    $result.primaryError = $_.Exception.Message
    $result.exitCode = 1
    Write-ZCodeRestoreLog 'ERROR' $result.primaryError
    return $result
  }
}

if ($MyInvocation.InvocationName -ne '.') {
  # The old command line is a supported operator surface, so it stays usable - but it
  # now enters through the one appearance door. Two writers editing a session without a
  # lock is exactly the class of fault that left orphaned watchers re-injecting an old
  # skin, and the door is where the lock, the journal and the independent verification
  # live. The functions above remain the effects implementation, so delegating here
  # cannot re-enter a lock this process already holds.
  $door = Join-Path $PSScriptRoot 'set-zcode-appearance.ps1'
  $doorAction = switch ($Mode) {
    'Pause' { 'native' }
    'Resume' { 'resume' }
    'Full' { 'full' }
  }
  if (Test-Path -LiteralPath $door -PathType Leaf) {
    . $door
    $root = Get-ZCodeDreamSkinStateRoot -StateRoot $StateRoot
    $request = [pscustomobject]@{
      schemaVersion = 'zcode-dream-skin-command/1'
      requestId     = [guid]::NewGuid().ToString('N')
      action        = $doorAction
      stateRoot     = $root
    }
    # The operation takes the root lock itself; wrapping it here would only add a
    # re-entrant acquisition that a same-thread mutex always grants.
    $outcome = Invoke-ZCodeAppearanceOperation -StateRoot $root -Request $request `
      -Effects (New-Zds2LiveEffects -StateRoot $root)
    Write-Host (Format-ZCodeDreamSkinLogLine -Tag 'RESTORE' -Message ("door action=$doorAction ok=$($outcome.ok) errorCode=$($outcome.errorCode)"))
    if ($outcome.ok) { exit 0 }
    if ($outcome.errorCode -eq 'BUSY') { exit 4 }
    exit 1
  }
  # A torn installation without the door script still has to be able to restore the
  # user's machine; that path is refused only for changes, never for recovery.
  Write-Host (Format-ZCodeDreamSkinLogLine -Tag 'ERROR' -Message 'the appearance door is missing; falling back to the direct restore path')
  $result = Invoke-ZCodeDreamSkinRestore -Mode $Mode -StateRoot $StateRoot `
    -ShutdownTimeoutSeconds $ShutdownTimeoutSeconds
  exit $result.exitCode
}
