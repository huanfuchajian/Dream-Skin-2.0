# ZCode launch transactions and startup-failure rollback.
#
# `state.json` means an ACTIVE session: theme applied, watcher running, ports and
# pids usable by the product. A launch that failed before that point used to leave
# no record at all, so a ZCode instance created by a failed start could not be
# recovered - the acceptance runner only knew "the start command returned" and the
# Full restore needs an active state it can trust.
#
# This module owns the second record. A launch transaction states what happened,
# not what is currently themed, and it is the only thing a failed start leans on:
#
#   launch-requested -> launched -> cdp-ready -> renderer-ready -> theme-applied -> active
#                                     rolling-back -> rolled-back | rollback-failed
#
# Rollback only ever touches the instance the transaction can prove it owns: same
# executable path, same creation time, same pre-existing pid set, and (when a
# listener exists) the CDP port inside that process tree. It never force-stops an
# unknown process, it keeps the transaction whenever recovery is incomplete, and it
# never reopens ZCode. The active-state semantics (pause / Full restore) are
# unchanged and live in restore-zcode-dream-skin.ps1.
#
# The default seams need the shared product helpers; the guard below keeps the
# module usable on its own without double-loading them.

if (-not (Get-Command Get-ZCodeProcessSnapshot -ErrorAction SilentlyContinue)) {
  . (Join-Path $PSScriptRoot 'common-windows.ps1')
  . (Join-Path $PSScriptRoot 'zcode-product.ps1')
}

$script:ZCODE_LAUNCH_TRANSACTION_SCHEMA = '1'
$script:ZCODE_LAUNCH_TRANSACTION_NAME = 'launch-transaction.json'
$script:ZCODE_STARTUP_REPORT_NAME = 'last-startup-report.json'
$script:ZCODE_LAUNCH_PHASES = @(
  'launch-requested', 'launched', 'cdp-ready', 'renderer-ready', 'paused-native', 'theme-applied', 'active',
  'rolling-back', 'rolled-back', 'rollback-failed'
)
# Phases in which the renderer had been reached, so a theme write may have started
# (and may have been interrupted halfway).
$script:ZCODE_RENDERER_PHASES = @('renderer-ready', 'theme-applied', 'active')

function Get-ZCodeStartupVersion {
  <#
  The one place that reads the verified ZCode version.
  `Get-ZCodeIdentityMetadata` returns a FLAT FileVersion; reading
  `$Metadata.VersionInfo.FileVersion` yields an empty string and silently produced
  an empty version in the acceptance report, so an empty value fails here instead.
  #>
  param([Parameter(Mandatory = $false)]$Metadata)
  $version = ''
  if ($null -ne $Metadata) { $version = [string]$Metadata.FileVersion }
  if ([string]::IsNullOrWhiteSpace($version)) {
    throw 'E02_ZCODE_IDENTITY_INVALID: the verified ZCode metadata carries no FileVersion'
  }
  return $version.Trim()
}

function Get-ZCodeLaunchTransactionPath {
  param([Parameter(Mandatory = $true)][string]$StateRoot)
  return (Join-Path $StateRoot $script:ZCODE_LAUNCH_TRANSACTION_NAME)
}

function Get-ZCodeStartupReportPath {
  param([Parameter(Mandatory = $true)][string]$StateRoot)
  return (Join-Path $StateRoot $script:ZCODE_STARTUP_REPORT_NAME)
}

function New-ZCodeLaunchTransaction {
  param(
    [Parameter(Mandatory = $true)][string]$ZCodePath,
    [Parameter(Mandatory = $true)][string]$FileVersion,
    [string]$ExecutableSha256 = '',
    [int]$Port = 0,
    [AllowEmptyCollection()][int[]]$PreExistingPids = @(),
    [string]$TransactionId = '',
    [datetime]$LaunchRequestedAt = (Get-Date),
    [string]$PreviousTransaction = ''
  )
  if ([string]::IsNullOrWhiteSpace($ZCodePath)) {
    throw 'E01_ZCODE_NOT_FOUND: a launch transaction needs the verified ZCode path'
  }
  if ([string]::IsNullOrWhiteSpace($FileVersion)) {
    throw 'E02_ZCODE_IDENTITY_INVALID: a launch transaction needs the verified ZCode version'
  }
  $id = if ($TransactionId) { $TransactionId } else { [guid]::NewGuid().ToString('N') }
  return [pscustomobject][ordered]@{
    schemaVersion        = $script:ZCODE_LAUNCH_TRANSACTION_SCHEMA
    transactionId        = $id
    phase                = 'launch-requested'
    phaseHistory         = @("launch-requested@$($LaunchRequestedAt.ToString('o'))")
    zcodePath            = $ZCodePath
    fileVersion          = $FileVersion
    executableSha256     = $ExecutableSha256
    launchedPid          = 0
    rootPid              = 0
    creationTime         = ''
    preExistingPids      = @($PreExistingPids | ForEach-Object { [int]$_ })
    port                 = [int]$Port
    browserId            = ''
    browserWebSocketUrl  = ''
    watchPid             = 0
    createdAt            = $LaunchRequestedAt.ToString('o')
    updatedAt            = $LaunchRequestedAt.ToString('o')
    previousTransaction  = $PreviousTransaction
  }
}

function Set-ZCodeLaunchTransactionPhase {
  param(
    [Parameter(Mandatory = $true)]$Transaction,
    [Parameter(Mandatory = $true)][string]$Phase,
    $At = (Get-Date)
  )
  if ($script:ZCODE_LAUNCH_PHASES -notcontains $Phase) {
    throw "Unknown launch phase: $Phase"
  }
  $stamp = ([datetime]$At).ToString('o')
  $Transaction.phase = $Phase
  $Transaction.phaseHistory = @($Transaction.phaseHistory) + @("$Phase@$stamp")
  $Transaction.updatedAt = $stamp
  return $Transaction
}

function Write-ZCodeLaunchTransaction {
  # Atomic write, same shape as the state writer: the temp file lands next to the
  # target and is moved over it, so a crash cannot leave a half transaction behind.
  param(
    [Parameter(Mandatory = $true)][string]$StateRoot,
    [Parameter(Mandatory = $true)]$Transaction
  )
  if ([string]$Transaction.schemaVersion -ne $script:ZCODE_LAUNCH_TRANSACTION_SCHEMA) {
    throw "Invalid launch transaction schema: $($Transaction.schemaVersion)"
  }
  $null = [System.IO.Directory]::CreateDirectory($StateRoot)
  $final = Get-ZCodeLaunchTransactionPath -StateRoot $StateRoot
  $temp = Join-Path $StateRoot ($script:ZCODE_LAUNCH_TRANSACTION_NAME + '.tmp-' + [guid]::NewGuid().ToString('N'))
  $json = ConvertTo-Json -InputObject $Transaction -Depth 6
  [System.IO.File]::WriteAllText($temp, $json, [System.Text.UTF8Encoding]::new($false))
  Move-Item -LiteralPath $temp -Destination $final -Force
  return $final
}

function Read-ZCodeLaunchTransaction {
  # Missing means "no launch is pending". A file that exists but cannot be parsed
  # must never be read as "clean": it is reported and left for the operator.
  param([Parameter(Mandatory = $true)][string]$StateRoot)
  $path = Get-ZCodeLaunchTransactionPath -StateRoot $StateRoot
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
  $raw = Get-Content -LiteralPath $path -Raw -Encoding UTF8
  try {
    $transaction = $raw | ConvertFrom-Json
  } catch {
    throw "Invalid launch transaction: $path ($($_.Exception.Message))"
  }
  if ($null -eq $transaction -or [string]$transaction.schemaVersion -ne $script:ZCODE_LAUNCH_TRANSACTION_SCHEMA) {
    throw "Invalid launch transaction: $path (schemaVersion)"
  }
  return $transaction
}

function Clear-ZCodeLaunchTransaction {
  param([Parameter(Mandatory = $true)][string]$StateRoot)
  $path = Get-ZCodeLaunchTransactionPath -StateRoot $StateRoot
  if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
}

function Write-ZCodeStartupReport {
  param(
    [Parameter(Mandatory = $true)][string]$StateRoot,
    [Parameter(Mandatory = $true)]$Report
  )
  $null = [System.IO.Directory]::CreateDirectory($StateRoot)
  $final = Get-ZCodeStartupReportPath -StateRoot $StateRoot
  $temp = Join-Path $StateRoot ($script:ZCODE_STARTUP_REPORT_NAME + '.tmp-' + [guid]::NewGuid().ToString('N'))
  $json = ConvertTo-Json -InputObject $Report -Depth 6
  [System.IO.File]::WriteAllText($temp, $json, [System.Text.UTF8Encoding]::new($false))
  Move-Item -LiteralPath $temp -Destination $final -Force
  return $final
}

function Read-ZCodeStartupReport {
  # Diagnostic record only: a missing or unreadable report means "no launcher report
  # to read", never "the launch was clean". The transaction reader is the strict one.
  param([Parameter(Mandatory = $true)][string]$StateRoot)
  $path = Get-ZCodeStartupReportPath -StateRoot $StateRoot
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
  try {
    return (Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json)
  } catch {
    return $null
  }
}

function Invoke-ZCodeLaunchRollback {
  <#
  Undo a launch that never became an active session. Every machine touch is a seam
  so the behaviour is testable without launching anything, and the verdict is taken
  from the observed process/port state - never from a single command's exit code.
  Returns an object; it never sets an exit code itself.
  #>
  param(
    [Parameter(Mandatory = $false)]$Transaction,
    [Parameter(Mandatory = $true)][string]$StateRoot,
    [string]$PrimaryError = '',
    [scriptblock]$ValidateOwner = $null,
    [scriptblock]$RemoveTheme = $null,
    [scriptblock]$CloseBrowser = $null,
    [scriptblock]$CloseWindow = $null,
    [scriptblock]$StopWatch = $null,
    [scriptblock]$ObserveCleanup = $null,
    [scriptblock]$Now = $null,
    [scriptblock]$Sleep = $null
  )
  $nowOf = if ($Now) { $Now } else { { Get-Date } }
  $sleepOf = if ($Sleep) { $Sleep } else { { param($Ms) Start-Sleep -Milliseconds $Ms } }

  $result = [ordered]@{
    attempted          = $false
    complete           = $false
    primaryError       = [string]$PrimaryError
    errors             = @()
    steps              = @()
    removedTheme       = $false
    closedBrowser      = $false
    closedWindow       = $false
    stoppedWatch       = $false
    residualPids       = @()
    portListenerOwners = @()
    statePath          = (Join-Path $StateRoot 'state.json')
    transactionPath    = (Get-ZCodeLaunchTransactionPath -StateRoot $StateRoot)
    startedAt          = (& $nowOf).ToString('o')
    finishedAt         = ''
  }
  if ($null -eq $Transaction) {
    # Nothing was launched: nothing may be closed, and this is not a failure.
    $result.complete = $true
    $result.finishedAt = (& $nowOf).ToString('o')
    return [pscustomobject]$result
  }

  $errors = [System.Collections.Generic.List[string]]::new()
  $steps = [System.Collections.Generic.List[string]]::new()
  $observed = $null
  $observationFailed = $false
  $identityVerified = $false
  $result.attempted = $true

  $validateOwnerOf = if ($ValidateOwner) { $ValidateOwner } else {
    {
      param($Transaction)
      $path = [string]$Transaction.zcodePath
      $launchedPid = [int]$Transaction.launchedPid
      $rootPid = [int]$Transaction.rootPid
      if (-not $path -or ($launchedPid -le 0 -and $rootPid -le 0)) {
        return @{ ok = $false; detail = 'the transaction has no verified pid to anchor on' }
      }
      $preExisting = @($Transaction.preExistingPids | ForEach-Object { [int]$_ })
      $rows = @(Get-ZCodeProcessSnapshot)
      $anchor = 0
      foreach ($candidate in @($launchedPid, $rootPid)) {
        if ($candidate -le 0 -or $preExisting -contains $candidate) { continue }
        $row = $rows | Where-Object { [int]$_.ProcessId -eq $candidate } | Select-Object -First 1
        if (-not $row) { continue }
        if (-not (Test-DreamSkinPathEqual -Left ([string]$row.ExecutablePath) -Right $path)) { continue }
        if ($candidate -eq $launchedPid -and $Transaction.creationTime) {
          # Creation time is what makes a pid trustworthy: the same number can be
          # reused by an unrelated process after a crash.
          $creation = ''
          try { $creation = (Get-Process -Id $candidate -ErrorAction Stop).StartTime.ToString('o') } catch { }
          if ($creation -and $creation -ne [string]$Transaction.creationTime) { continue }
        }
        $anchor = $candidate
        break
      }
      if ($anchor -le 0) {
        return @{ ok = $false; detail = 'no live process matches the recorded path, pid set and creation time' }
      }
      try {
        $null = Assert-DreamSkinZCodeIdentity -Path $path
      } catch {
        return @{ ok = $false; detail = "the recorded executable no longer passes identity verification: $($_.Exception.Message)" }
      }
      $tree = @(Get-ZCodeDescendantProcessIds -RootPid $anchor -ProcessRows $rows)
      if ([int]$Transaction.port -gt 0) {
        $listeners = @(Get-ZCodePortListenerRows -Port ([int]$Transaction.port))
        $foreign = @($listeners | Where-Object { $tree -notcontains [int]$_.OwningProcess })
        if ($foreign.Count -gt 0) {
          return @{ ok = $false; detail = "port $($Transaction.port) is owned outside this launch; the owner is never terminated" }
        }
      }
      return @{ ok = $true; detail = "launched pid $anchor verified inside $($tree.Count) process(es)"; anchorPid = $anchor; treePids = $tree }
    }
  }
  $removeThemeOf = if ($RemoveTheme) { $RemoveTheme } else {
    {
      param($Transaction)
      $injector = Join-Path $PSScriptRoot 'injector.mjs'
      # One resolver for every installed entry point: the bundled, signature-validated
# runtime wins, and PATH is only a source-tree fallback behind the same gate.
$nodePath = (Get-DreamSkinNodeRuntime -MinimumMajor 22).Path
      $output = & $nodePath $injector --mode zcode-remove --port ([int]$Transaction.port) `
        --browser-id ([string]$Transaction.browserId) `
        --report (Join-Path $StateRoot 'last-remove-report.json') 2>&1
      @{ exitCode = [int]$LASTEXITCODE; output = (($output | Out-String).Trim()) }
    }
  }
  $closeBrowserOf = if ($CloseBrowser) { $CloseBrowser } else {
    {
      param($Transaction)
      $injector = Join-Path $PSScriptRoot 'injector.mjs'
      # One resolver for every installed entry point: the bundled, signature-validated
# runtime wins, and PATH is only a source-tree fallback behind the same gate.
$nodePath = (Get-DreamSkinNodeRuntime -MinimumMajor 22).Path
      $output = & $nodePath $injector --mode zcode-close --port ([int]$Transaction.port) `
        --browser-id ([string]$Transaction.browserId) `
        --report (Join-Path $StateRoot 'last-close-report.json') 2>&1
      @{ exitCode = [int]$LASTEXITCODE; output = (($output | Out-String).Trim()) }
    }
  }
  $closeWindowOf = if ($CloseWindow) { $CloseWindow } else {
    {
      param($Transaction)
      $anchor = [int]$Transaction.rootPid
      if ($anchor -le 0) { $anchor = [int]$Transaction.launchedPid }
      $process = Get-Process -Id $anchor -ErrorAction SilentlyContinue
      if (-not $process) { return @{ closed = $true; detail = 'the launched process already exited' } }
      if (-not $process.CloseMainWindow()) {
        return @{ closed = $false; detail = 'the verified window refused the normal close request' }
      }
      $preExisting = @($Transaction.preExistingPids | ForEach-Object { [int]$_ })
      $deadline = (Get-Date).AddSeconds(30)
      while ((Get-Date) -lt $deadline) {
        $rows = @(Get-ZCodeProcessSnapshot)
        $tree = @(Get-ZCodeDescendantProcessIds -RootPid $anchor -ProcessRows $rows)
        $alive = @($rows | Where-Object {
          ($tree -contains [int]$_.ProcessId) -and ($preExisting -notcontains [int]$_.ProcessId)
        })
        if ($alive.Count -eq 0) { return @{ closed = $true; detail = 'the verified window closed and its tree drained' } }
        Start-Sleep -Milliseconds 500
      }
      return @{ closed = $false; detail = 'the verified window did not close within 30s' }
    }
  }
  $stopWatchOf = if ($StopWatch) { $StopWatch } else {
    {
      param($Transaction)
      $watchPid = [int]$Transaction.watchPid
      if ($watchPid -le 0) { return @{ stopped = $true; detail = 'no watcher was recorded' } }
      $rows = @(Get-ZCodeProcessSnapshot)
      if (@($rows | Where-Object { [int]$_.ProcessId -eq $watchPid }).Count -eq 0) {
        return @{ stopped = $true; detail = 'the recorded watcher is already gone' }
      }
      # One ruler for the rollback and the tray restore: a command-line substring
      # is not ownership. The recorded pid is stopped only when it is provably this
      # session's watcher (trusted node, watch mode, this injector, this state file,
      # this port, this browser id); anything unprovable is reported, never killed.
      $scan = Get-ZCodeSessionWatchers -State $Transaction -ProcessRows $rows `
        -InjectorPath (Join-Path $PSScriptRoot 'injector.mjs') `
        -NodePath (Get-DreamSkinNodeRuntime -MinimumMajor 22).Path -StateRoot $StateRoot
      $ownedIds = @($scan.owned | ForEach-Object { [int]$_.ProcessId })
      if ($ownedIds -notcontains $watchPid) {
        return @{ stopped = $false; detail = "pid $watchPid is not provably this session's watcher ($($scan.reason))" }
      }
      foreach ($ownedId in $ownedIds) {
        try { Stop-Process -Id $ownedId -ErrorAction Stop } catch {
          return @{ stopped = $false; detail = "the watcher could not be stopped: $($_.Exception.Message)" }
        }
      }
      $deadline = (Get-Date).AddSeconds(10)
      while ((Get-Date) -lt $deadline) {
        $alive = @($ownedIds | Where-Object { Get-Process -Id $_ -ErrorAction SilentlyContinue })
        if ($alive.Count -eq 0) {
          return @{ stopped = $true; detail = "watcher(s) $($ownedIds -join ', ') stopped" }
        }
        Start-Sleep -Milliseconds 250
      }
      return @{ stopped = $false; detail = "watcher $watchPid is still alive" }
    }
  }
  $observeCleanupOf = if ($ObserveCleanup) { $ObserveCleanup } else {
    {
      param($Transaction)
      $preExisting = @($Transaction.preExistingPids | ForEach-Object { [int]$_ })
      $rows = @(Get-ZCodeProcessSnapshot)
      $anchor = [int]$Transaction.rootPid
      if ($anchor -le 0) { $anchor = [int]$Transaction.launchedPid }
      $tree = if ($anchor -gt 0) { @(Get-ZCodeDescendantProcessIds -RootPid $anchor -ProcessRows $rows) } else { @() }
      $residual = @($rows | Where-Object {
        ($tree -contains [int]$_.ProcessId) -and ($preExisting -notcontains [int]$_.ProcessId)
      } | ForEach-Object { [int]$_.ProcessId })
      $owners = @()
      if ([int]$Transaction.port -gt 0) {
        $owners = @(Get-ZCodePortListenerRows -Port ([int]$Transaction.port) |
          ForEach-Object { [int]$_.OwningProcess })
      }
      @{ residualPids = $residual; portListenerOwners = $owners }
    }
  }

  # 1. Only the instance this transaction can prove it owns may be touched.
  $steps.Add('validate')
  $verdict = $null
  try { $verdict = & $validateOwnerOf $Transaction } catch {
    $verdict = @{ ok = $false; detail = "identity verification failed: $($_.Exception.Message)" }
  }
  if (-not $verdict.ok) {
    $errors.Add("the launched instance could not be verified: $($verdict.detail)")
  } else {
    $identityVerified = $true
    # 2. The watcher first: while it is alive it would fight the removal.
    if ([int]$Transaction.watchPid -gt 0) {
      $steps.Add('stop-watch')
      try {
        $watch = & $stopWatchOf $Transaction
        if ($watch.stopped) { $result.stoppedWatch = $true }
        else { $errors.Add("the watcher did not stop: $($watch.detail)") }
      } catch { $errors.Add("the watcher stop failed: $($_.Exception.Message)") }
    }
    # 3. A theme write may have been interrupted halfway: remove before closing.
    $rendererReached = $script:ZCODE_RENDERER_PHASES -contains [string]$Transaction.phase
    if ($rendererReached -and [string]$Transaction.browserId) {
      $steps.Add('remove')
      try {
        $remove = & $removeThemeOf $Transaction
        if ([int]$remove.exitCode -eq 0) { $result.removedTheme = $true }
        else { $errors.Add("the live removal failed (exit $($remove.exitCode)): $($remove.output)") }
      } catch { $errors.Add("the live removal failed: $($_.Exception.Message)") }
    }
    # 4. Close the verified instance: through the browser identity when CDP came up,
    #    through the verified main window when it never did.
    if ([string]$Transaction.browserId) {
      $steps.Add('close-browser')
      try {
        $close = & $closeBrowserOf $Transaction
        if ([int]$close.exitCode -eq 0) { $result.closedBrowser = $true }
        else { $errors.Add("the graceful Browser.close failed (exit $($close.exitCode)): $($close.output)") }
      } catch { $errors.Add("the graceful Browser.close failed: $($_.Exception.Message)") }
    } else {
      $steps.Add('close-window')
      try {
        $window = & $closeWindowOf $Transaction
        if ($window.closed) { $result.closedWindow = $true }
        else { $errors.Add("the verified window did not close: $($window.detail)") }
      } catch { $errors.Add("the window close failed: $($_.Exception.Message)") }
    }
    & $sleepOf 500 | Out-Null
  }

  # 5. Observed state decides, not an exit code: a recorded step error does not by
  #    itself mean the launch survived (a failing best-effort theme removal before a
  #    successful close still ends with nothing left behind), but any live process,
  #    live watcher or foreign listener does.
  $steps.Add('observe')
  try {
    $observed = & $observeCleanupOf $Transaction
    $result.residualPids = @($observed.residualPids)
    $result.portListenerOwners = @($observed.portListenerOwners)
  } catch {
    $observationFailed = $true
    $errors.Add("cleanup could not be observed: $($_.Exception.Message)")
  }
  # A watcher is not part of the ZCode process tree, so it needs its own check: a
  # live watcher would re-inject the theme the rollback just removed. An instance
  # that could not be verified is never called recovered either: the rollback has
  # no proof that what it refused to touch is gone.
  $watchStillLive = [int]$Transaction.watchPid -gt 0 -and -not $result.stoppedWatch
  $result.complete = (
    $identityVerified -and
    -not $observationFailed -and
    @($result.residualPids).Count -eq 0 -and
    -not $watchStillLive
  )

  if ($result.complete) {
    Clear-ZCodeLaunchTransaction -StateRoot $StateRoot
    # Only this launch's state is cleared; an unrelated session file is left alone.
    $state = $null
    try { $state = Read-ZCodeDreamSkinState -StateRoot $StateRoot } catch { $state = $null }
    if ($null -ne $state -and (
        ([int]$state.rootPid -gt 0 -and [int]$state.rootPid -eq [int]$Transaction.rootPid) -or
        ([int]$state.port -gt 0 -and [int]$state.port -eq [int]$Transaction.port))) {
      Clear-ZCodeDreamSkinState -StateRoot $StateRoot
    }
  }

  $result.errors = @($errors)
  $result.steps = @($steps)
  $result.finishedAt = (& $nowOf).ToString('o')
  return [pscustomobject]$result
}
