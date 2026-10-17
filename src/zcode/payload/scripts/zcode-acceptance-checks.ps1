# Acceptance-check helpers for the local install acceptance runner.
#
# The unattended runner in .lemon drives the INSTALLED product; the assertions
# it must satisfy live here so they are regression-tested like product code
# instead of hiding inside a one-off machine script. Pure logic takes
# injectable inputs so every rule is testable offline; the documented defaults
# are the only parts that touch the real machine.
#
# Depends on zcode-adapter.ps1 (via common-windows.ps1) for the watcher
# identity verdict: Test-ZCodeAcceptanceFullRestore reuses the SAME identity
# rules the product itself uses instead of counting same-path Node processes.

$script:ZCodeAcceptanceShortcutScripts = [ordered]@{
  'ZCode Dream Skin.lnk'          = @{ Script = 'launch-zcode.ps1'; ExtraArguments = '' }
  'ZCode Dream Skin - Tray.lnk'   = @{ Script = 'tray-zcode-dream-skin.ps1'; ExtraArguments = '' }
  'ZCode Dream Skin - Restore.lnk' = @{ Script = 'restore-zcode-dream-skin.ps1'; ExtraArguments = ' -Mode Full' }
}

function ConvertTo-ZCodeInnoArgument {
  # Inno command-line values are quoted as a whole: /LOG="C:\a path\log.log".
  param([Parameter(Mandatory = $true)][string]$Name, [Parameter(Mandatory = $true)][string]$Value)
  return '/' + $Name + '="' + $Value + '"'
}

function Start-ZCodeAcceptanceProcess {
  <#
  Executes one shortcut's real TargetPath with its raw Arguments string and
  WorkingDirectory. Output is captured to files so it is never confused with
  the exit code. The caller owns waiting: Start-Process -Wait waits for the
  whole DESCENDANT TREE, and a resident watcher under the start entry would
  hold the caller forever (measured incident 2026-10-01), so a wait must be a
  direct-process wait with an explicit bound.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)][string]$TargetPath,
    [Parameter(Mandatory = $true)][string]$Arguments,
    [string]$WorkingDirectory = '',
    [Parameter(Mandatory = $true)][string]$StdOutPath,
    [Parameter(Mandatory = $true)][string]$StdErrPath
  )
  foreach ($file in @($StdOutPath, $StdErrPath)) {
    $dir = Split-Path -Parent $file
    if ($dir) { $null = [System.IO.Directory]::CreateDirectory($dir) }
  }
  $startArguments = @{
    FilePath               = $TargetPath
    ArgumentList           = $Arguments
    RedirectStandardOutput = $StdOutPath
    RedirectStandardError  = $StdErrPath
    PassThru               = $true
    WindowStyle            = 'Hidden'
  }
  if ($WorkingDirectory) { $startArguments.WorkingDirectory = $WorkingDirectory }
  $process = Start-Process @startArguments
  # Cache the process handle now: on PowerShell 5.1 a Start-Process -PassThru
  # object cannot read ExitCode after the process has exited unless the handle
  # was forced open while it was still running.
  [void]$process.Handle
  return $process
}

function Invoke-ZCodeAcceptanceShortcut {
  <#
  Waits for the shortcut's DIRECT process and returns its exit code with stdout
  and stderr captured separately: a script that "merely ran" proves nothing and
  a failing exit code must never surface as success. The wait is deliberately
  bounded to the direct process: the start entry leaves a resident watcher in
  its tree, so a tree wait could never return (measured incident 2026-10-01).
  A target that outlives -WaitTimeoutMs is refused as E_ACC_SHORTCUT_TIMEOUT
  instead of hanging silently, so a hung entry surfaces as a diagnosable FAIL.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)][string]$TargetPath,
    [Parameter(Mandatory = $true)][string]$Arguments,
    [string]$WorkingDirectory = '',
    [Parameter(Mandatory = $true)][string]$StdOutPath,
    [Parameter(Mandatory = $true)][string]$StdErrPath,
    [int]$WaitTimeoutMs = 300000
  )
  $process = Start-ZCodeAcceptanceProcess -TargetPath $TargetPath -Arguments $Arguments `
    -WorkingDirectory $WorkingDirectory -StdOutPath $StdOutPath -StdErrPath $StdErrPath
  if (-not $process.WaitForExit($WaitTimeoutMs)) {
    # The running target may still hold the output files: read what is readable
    # and make the timeout itself the failure reason.
    $partialOut = ''
    if (Test-Path -LiteralPath $StdOutPath) {
      $rawOut = Get-Content -LiteralPath $StdOutPath -Raw -ErrorAction SilentlyContinue
      if ($null -ne $rawOut) { $partialOut = ([string]$rawOut).Trim() }
    }
    $partialErr = ''
    if (Test-Path -LiteralPath $StdErrPath) {
      $rawErr = Get-Content -LiteralPath $StdErrPath -Raw -ErrorAction SilentlyContinue
      if ($null -ne $rawErr) { $partialErr = ([string]$rawErr).Trim() }
    }
    throw ('E_ACC_SHORTCUT_TIMEOUT: the target (pid {0}) did not exit within {1} ms; stdout: {2} | stderr: {3}' -f `
      $process.Id, $WaitTimeoutMs,
      $partialOut.Substring(0, [Math]::Min(200, $partialOut.Length)),
      $partialErr.Substring(0, [Math]::Min(200, $partialErr.Length)))
  }
  $output = if (Test-Path -LiteralPath $StdOutPath) { (Get-Content -LiteralPath $StdOutPath -Raw -ErrorAction SilentlyContinue) } else { '' }
  $errorOutput = if (Test-Path -LiteralPath $StdErrPath) { (Get-Content -LiteralPath $StdErrPath -Raw -ErrorAction SilentlyContinue) } else { '' }
  return @{
    ExitCode    = [int]$process.ExitCode
    Output      = [string]$output
    ErrorOutput = [string]$errorOutput
  }
}

function Invoke-ZCodeAcceptanceShortcutAsync {
  <#
  The same launch without waiting: the caller holds the Process object for
  entries that keep running (the tray), and observes exit and output itself.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)][string]$TargetPath,
    [Parameter(Mandatory = $true)][string]$Arguments,
    [string]$WorkingDirectory = '',
    [Parameter(Mandatory = $true)][string]$StdOutPath,
    [Parameter(Mandatory = $true)][string]$StdErrPath
  )
  return Start-ZCodeAcceptanceProcess -TargetPath $TargetPath -Arguments $Arguments `
    -WorkingDirectory $WorkingDirectory -StdOutPath $StdOutPath -StdErrPath $StdErrPath
}

function Invoke-ZCodeAcceptanceChildReport {
  <#
  Runs a launcher CHILD (Windows PowerShell) that starts a long-lived process and
  reports it through a FILE, then exits. The child's stdout and stderr go to
  files, never a capture pipe: a redirect-started grandchild inherits the capture
  pipe's write end, so a '& ... 2>&1' read would not reach EOF until that
  grandchild exits (measured 2026-10-01: 21.5s with the pipe, 2.7s without). The
  wait is a bounded wait for the DIRECT child, a planted stale report is removed
  before the launch so it can never carry the call, and with -RequirePid the
  report must parse as a positive PID: a launcher that merely exited proves
  nothing about what it started.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)][string]$EncodedCommand,
    [Parameter(Mandatory = $true)][string]$ReportPath,
    [Parameter(Mandatory = $true)][string]$StdOutPath,
    [Parameter(Mandatory = $true)][string]$StdErrPath,
    [int]$WaitTimeoutMs = 120000,
    [switch]$RequirePid,
    [string]$PowerShellPath = ''
  )
  $exe = if ($PowerShellPath) { $PowerShellPath } else {
    Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
  }
  foreach ($file in @($ReportPath, $StdOutPath, $StdErrPath)) {
    $dir = Split-Path -Parent $file
    if ($dir) { $null = [System.IO.Directory]::CreateDirectory($dir) }
  }
  Remove-Item -LiteralPath $ReportPath -Force -ErrorAction SilentlyContinue
  $process = Start-Process -FilePath $exe -PassThru -WindowStyle Hidden `
    -ArgumentList @('-NoProfile', '-WindowStyle', 'Hidden', '-ExecutionPolicy', 'RemoteSigned', '-EncodedCommand', $EncodedCommand) `
    -RedirectStandardOutput $StdOutPath -RedirectStandardError $StdErrPath
  # Cache the handle while it is alive: PS 5.1 cannot read ExitCode afterwards.
  [void]$process.Handle
  if (-not $process.WaitForExit($WaitTimeoutMs)) {
    throw ('E_ACC_CHILD_TIMEOUT: the launcher child (pid {0}) did not exit within {1} ms' -f $process.Id, $WaitTimeoutMs)
  }
  $exitCode = [int]$process.ExitCode
  $report = ''
  if (Test-Path -LiteralPath $ReportPath) {
    $raw = Get-Content -LiteralPath $ReportPath -Raw -ErrorAction SilentlyContinue
    if ($null -ne $raw) { $report = ([string]$raw).Trim() }
  }
  $startedPid = 0
  if ($RequirePid) {
    if (-not $report) { throw 'E_ACC_CHILD_REPORT: the launcher child did not report the started PID' }
    if (-not [int]::TryParse($report, [ref]$startedPid) -or $startedPid -le 0) {
      throw ("E_ACC_CHILD_REPORT: the launcher child reported an invalid PID ('{0}')" -f $report)
    }
  }
  return @{ ExitCode = $exitCode; Report = $report; Pid = $startedPid }
}

function Get-ZCodeAcceptanceThemeArguments {
  <#
  The theme arguments a reapply's apply must carry: the ACTIVE library inputs,
  exactly what the launcher resolves for a fresh start. Dot-sourcing the real
  launcher keeps one implementation of this contract; its dot-source guard
  makes the load side-effect free.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)][string]$LauncherScriptPath,
    [Parameter(Mandatory = $true)][string]$SkillRoot,
    [Parameter(Mandatory = $true)][string]$StateRoot,
    [string]$ImagePath = '',
    [string]$ThemePath = ''
  )
  if (-not (Test-Path -LiteralPath $LauncherScriptPath -PathType Leaf)) {
    throw "E_ACC_LAUNCHER_MISSING: $LauncherScriptPath"
  }
  # Copy the parameters to differently-named locals FIRST: dot-sourcing the
  # launcher runs its param block in this scope, and its defaults ($StateRoot='',
  # $ThemePath='') would silently overwrite same-named parameters.
  $launcherOf = $LauncherScriptPath
  $skill = $SkillRoot
  $state = $StateRoot
  $image = $ImagePath
  $theme = $ThemePath
  . $launcherOf
  return @(Get-ZCodeDreamSkinThemeArguments -SkillRoot $skill -StateRoot $state -ArtPath $image -ThemePath $theme)
}

function Test-ZCodeAcceptanceVerifyReport {
  <#
  The only verify report that may carry a step is one that is FRESH (written
  no earlier than -NotBefore; a planted old PASS report must never pass),
  belongs to THIS session (browser id and port), carries exactly the expected
  node counts, and records no errors.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)][string]$ReportPath,
    [Parameter(Mandatory = $true)][string]$BrowserId,
    [Parameter(Mandatory = $true)][int]$Port,
    [Parameter(Mandatory = $true)][int]$StyleCount,
    [Parameter(Mandatory = $true)][int]$BackgroundCount,
    [Parameter(Mandatory = $true)][int]$OverlayCount,
    [Parameter(Mandatory = $true)][datetime]$NotBefore
  )
  if (-not (Test-Path -LiteralPath $ReportPath -PathType Leaf)) {
    throw "E_ACC_NO_REPORT: the verify report was not written: $ReportPath"
  }
  $file = Get-Item -LiteralPath $ReportPath
  if ($file.LastWriteTime -lt $NotBefore) {
    throw ("E_ACC_REPORT_STALE: the verify report predates this step (written {0}, gate {1})" -f `
      $file.LastWriteTime.ToString('o'), $NotBefore.ToString('o'))
  }
  $report = Get-Content -LiteralPath $ReportPath -Raw -Encoding UTF8 | ConvertFrom-Json
  if ([string]$report.browserId -cne $BrowserId -or [int]$report.port -ne $Port) {
    throw "E_ACC_IDENTITY: the report belongs to browser '$($report.browserId)' port $($report.port), not this session"
  }
  $verify = $report.verify
  if ([int]$verify.styleCount -ne $StyleCount -or [int]$verify.backgroundCount -ne $BackgroundCount -or
      [int]$verify.overlayCount -ne $OverlayCount) {
    throw ("E_ACC_COUNT: nodes are {0}/{1}/{2}, expected {3}/{4}/{5}" -f `
      [int]$verify.styleCount, [int]$verify.backgroundCount, [int]$verify.overlayCount, $StyleCount, $BackgroundCount, $OverlayCount)
  }
  if (@($report.errors).Count -gt 0) {
    throw "E_ACC_REPORT_ERRORS: the report records errors ($(@($report.errors) -join ' | '))"
  }
  return $true
}

function Test-ZCodeAcceptanceInstallLayout {
  <#
  The installed layout gate: the bootstrap where the ISS actually installs it
  ({app}\setup-bootstrap-zcode.ps1, not payload\), the payload scripts, the
  bundled Node's identity and version, the marker's candidate record against
  the live executable, every shortcut aimed at THIS install root, and a
  per-file payload inventory for before/after compares.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)][string]$InstallRoot,
    [Parameter(Mandatory = $true)][string]$StateRoot,
    [Parameter(Mandatory = $true)][string]$ExpectedZCodePath,
    [Parameter(Mandatory = $true)][string]$StartMenuDir,
    [Parameter(Mandatory = $true)][string]$Label,
    [Parameter(Mandatory = $true)][string]$InventoryPath,
    [Parameter(Mandatory = $true)][string]$LiveExecutableHash,
    [scriptblock]$GetShortcut = $null,
    [scriptblock]$ProbeNodeVersion = $null,
    [scriptblock]$GetSignature = $null
  )
  $shortcutOf = if ($GetShortcut) { $GetShortcut } else {
    {
      param($LnkPath)
      $shell = New-Object -ComObject WScript.Shell
      $lnk = $shell.CreateShortcut($LnkPath)
      return @{ Target = [string]$lnk.TargetPath; Arguments = [string]$lnk.Arguments; WorkingDir = [string]$lnk.WorkingDirectory }
    }
  }
  $nodeVersionOf = if ($ProbeNodeVersion) { $ProbeNodeVersion } else {
    { param($NodePath) (& $NodePath --version) -join '' }
  }
  $signatureOf = if ($GetSignature) { $GetSignature } else { { param($Path) Get-AuthenticodeSignature -LiteralPath $Path } }

  # The bootstrap is installed at {app}, one level above payload - the ISS
  # [Files] entry, and the exact file the uninstall flow re-runs.
  $requiredAtRoot = @('unins000.exe', 'setup-bootstrap-zcode.ps1')
  foreach ($name in $requiredAtRoot) {
    if (-not (Test-Path -LiteralPath (Join-Path $InstallRoot $name) -PathType Leaf)) {
      throw "E_ACC_LAYOUT: the install root is missing $name"
    }
  }
  $payloadRoot = Join-Path $InstallRoot 'payload'
  foreach ($relative in @(
    'payload\scripts\start-zcode-dream-skin.ps1',
    'payload\scripts\restore-zcode-dream-skin.ps1',
    'payload\scripts\verify-zcode-dream-skin.ps1',
    'payload\scripts\injector.mjs',
    'payload\scripts\zcode-theme-store.ps1',
    'payload\scripts\common-windows.ps1',
    'payload\runtime\node\node.exe'
  )) {
    if (-not (Test-Path -LiteralPath (Join-Path $InstallRoot $relative) -PathType Leaf)) {
      throw "E_ACC_LAYOUT: the install is missing $relative"
    }
  }

  $bundledNode = Join-Path $payloadRoot 'runtime\node\node.exe'
  $nodeVersion = & $nodeVersionOf $bundledNode
  if ("$nodeVersion" -notmatch '^v(\d+)\.') {
    throw "E_ACC_LAYOUT: the bundled node version is unreadable ('$nodeVersion')"
  }
  if ([int]$Matches[1] -lt 22) {
    throw "E_ACC_LAYOUT: the bundled node major is $($Matches[1]), the product pins 22+"
  }
  $signature = & $signatureOf $bundledNode
  if ([string]$signature.Status -cne 'Valid') {
    throw "E_ACC_LAYOUT: the bundled node signature is $($signature.Status)"
  }

  $markerPath = Join-Path $StateRoot 'installer.json'
  if (-not (Test-Path -LiteralPath $markerPath -PathType Leaf)) {
    throw "E_ACC_LAYOUT: the installer marker is missing"
  }
  $marker = Get-Content -LiteralPath $markerPath -Raw -Encoding UTF8 | ConvertFrom-Json
  if ([string]$marker.schemaVersion -cne 'zcode-dream-skin-installer/1') {
    throw "E_ACC_LAYOUT: the marker schema is '$($marker.schemaVersion)'"
  }
  if (-not [string]$marker.zcodePath -or ("$($marker.zcodePath)" -ine $ExpectedZCodePath)) {
    throw "E_ACC_LAYOUT: the marker records '$($marker.zcodePath)', expected $ExpectedZCodePath"
  }
  if (-not [string]$marker.fileVersion) {
    throw 'E_ACC_LAYOUT: the marker fileVersion is empty'
  }
  if ([string]$marker.sha256 -cne $LiveExecutableHash) {
    throw "E_ACC_LAYOUT: the marker sha256 does not match the live executable (marker '$($marker.sha256)')"
  }

  # Shortcuts: full Target/Arguments/WorkingDirectory, anchored at THIS install
  # root - a same-named shortcut into another directory is not this install.
  $payloadScripts = Join-Path $payloadRoot 'scripts'
  foreach ($lnkName in $script:ZCodeAcceptanceShortcutScripts.Keys) {
    $lnkPath = Join-Path $StartMenuDir $lnkName
    if (-not (Test-Path -LiteralPath $lnkPath -PathType Leaf)) {
      throw "E_ACC_LAYOUT: shortcut missing $lnkName"
    }
    $lnk = & $shortcutOf $lnkPath
    $expectedScript = $script:ZCodeAcceptanceShortcutScripts[$lnkName]
    if ("$($lnk.Target)" -notmatch 'powershell\.exe$') {
      throw "E_ACC_LAYOUT: $lnkName targets '$($lnk.Target)', expected a Windows PowerShell host"
    }
    $expectedFileToken = '-File "' + (Join-Path $payloadScripts $expectedScript.Script) + '"'
    if ("$($lnk.Arguments)".IndexOf($expectedFileToken, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) {
      throw "E_ACC_LAYOUT: $lnkName does not launch this install's $($expectedScript.Script) (arguments: $($lnk.Arguments))"
    }
    if ($expectedScript.ExtraArguments -and -not "$($lnk.Arguments)".EndsWith($expectedScript.ExtraArguments, [System.StringComparison]::OrdinalIgnoreCase)) {
      throw "E_ACC_LAYOUT: $lnkName is missing the '$($expectedScript.ExtraArguments)' argument"
    }
    if ("$($lnk.WorkingDir)" -ine $InstallRoot) {
      throw "E_ACC_LAYOUT: $lnkName works from '$($lnk.WorkingDir)', not this install root"
    }
  }

  $rows = Get-ChildItem -LiteralPath $payloadRoot -Recurse -File | ForEach-Object {
    '{0},{1}' -f (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant(),
      $_.FullName.Substring($payloadRoot.Length + 1)
  }
  [System.IO.File]::WriteAllLines($InventoryPath, $rows, [System.Text.UTF8Encoding]::new($false))
  return "node=$nodeVersion files=$($rows.Count) markerVersion=$($marker.fileVersion)"
}

function Test-ZCodeAcceptanceFullRestore {
  <#
  The Full-restore verdict: no active state file, no process that passes the
  PRODUCT'S OWN watcher identity rules (never "any same-path Node"), and no
  listener on the session's RECORDED port. A normally relaunched ZCode is
  expected and allowed - Full restores one by design.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]$State,
    [Parameter(Mandatory = $true)][string]$StateRoot,
    [Parameter(Mandatory = $true)][string]$InjectorPath,
    [Parameter(Mandatory = $true)][string]$BundledNode,
    [AllowEmptyCollection()][object[]]$ProcessRows = @(),
    [AllowEmptyCollection()][object[]]$PortListeners = @()
  )
  if (Test-Path -LiteralPath (Join-Path $StateRoot 'state.json') -PathType Leaf) {
    throw 'E_ACC_FULL: state.json still exists after the full restore'
  }
  $verdict = Get-ZCodeManagedWatcherVerdict -State $State -ProcessRows $ProcessRows `
    -InjectorPath $InjectorPath -StatePath (Join-Path $StateRoot 'state.json') -NodePath $BundledNode
  if ($verdict.action -eq 'stop') {
    throw "E_ACC_FULL: a managed watcher is still running ($($verdict.reason))"
  }
  $recordedPort = [int]$State.port
  $listeners = @($PortListeners | Where-Object { [int]$_.LocalPort -eq $recordedPort })
  if ($listeners.Count -gt 0) {
    throw "E_ACC_FULL: the recorded debug port $recordedPort is still listening (owners $(@($listeners | ForEach-Object { [int]$_.OwningProcess }) -join ','))"
  }
  return $true
}

function Test-ZCodeAcceptanceRunbookOrder {
  <#
  The runner validates its own step sequence against this canonical order
  before it may touch the machine. The load-bearing invariant: the update runs
  BEFORE the first ZCode launch - a Full restore relaunches normal ZCode, and
  the installer refuses any running ZCode, so an update placed after a start
  can only fail (or tempt someone into force-closing the user's app).
  #>
  [CmdletBinding()]
  param([Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$StepNames)
  $canonical = @(
    'session-check', 'setup-hash', 'pre-install-evidence', 'gate-1', 'install-1', 'verify-install-1',
    'prepare-custom-library', 'update-overwrite', 'verify-install-after-update',
    'entry-start-shortcut', 'entry-verify-first', 'entry-screenshot-themed',
    'entry-tray-shortcut', 'lifecycle-verify-themed', 'lifecycle-apply-idempotent',
    'lifecycle-reapply-resume', 'lifecycle-reload-restores', 'lifecycle-pause',
    'lifecycle-pause-reload', 'lifecycle-resume', 'lifecycle-live-remove',
    'lifecycle-full-restore', 'uninstall', 'uninstall-preservation', 'gate-2',
    'reinstall', 'verify-install-after-reinstall', 'final-session'
  )
  if ($StepNames.Count -ne $canonical.Count) {
    throw ("E_ACC_RUNBOOK: the runbook has {0} steps, the canonical order has {1}" -f $StepNames.Count, $canonical.Count)
  }
  for ($i = 0; $i -lt $canonical.Count; $i++) {
    if ($StepNames[$i] -cne $canonical[$i]) {
      throw ("E_ACC_RUNBOOK: step {0} is '{1}', the canonical order requires '{2}'" -f $i, $StepNames[$i], $canonical[$i])
    }
  }
  return $true
}

function Get-ZCodeAcceptanceFailurePlan {
  <#
  What the runner must do when a step fails: always stop, never answer a
  failure with a destructive continuation, keep the install when the problem
  may be repairable, and use the product's protected Full on its own session.
  #>
  [CmdletBinding()]
  param([Parameter(Mandatory = $true)][string]$StepName)
  if ($StepName -like 'lifecycle-*') {
    return [pscustomobject]@{ action = 'stop'; keepInstall = $true; keepFiles = $true; recovery = 'protective-full' }
  }
  if ($StepName -like 'gate-*') {
    return [pscustomobject]@{ action = 'stop'; keepInstall = $false; keepFiles = $true; recovery = 'none' }
  }
  if ($StepName -like 'uninstall*') {
    return [pscustomobject]@{ action = 'stop'; keepInstall = $true; keepFiles = $true; recovery = 'none' }
  }
  # Install, update, layout and pre-flight failures: stop with the install kept
  # for repair - never uninstall as a reaction to a failed check.
  return [pscustomobject]@{ action = 'stop'; keepInstall = $true; keepFiles = $true; recovery = 'none' }
}


function ConvertTo-ZCodeAcceptanceScriptParameterMap {
  <#
  Normalizes the named parameters one installed product script is invoked with.
  The map travels to the child as JSON and is SPLATTED there, so a parameter can
  never be rebound as a positional value: the retired form sent each argument
  pre-quoted ("-Mode" "Pause"), PowerShell bound '-Mode' as the VALUE of $Mode,
  and the product's ValidateSet rejected it before Pause/Resume/Full ever ran.
  #>
  param([System.Collections.IDictionary]$Parameters = $null)
  $map = [ordered]@{}
  if ($null -eq $Parameters) { return $map }
  foreach ($key in $Parameters.Keys) {
    $name = "$key"
    if ($name -notmatch '^[A-Za-z][A-Za-z0-9]{0,63}$') {
      throw "E_ACC_ARGUMENTS: '$name' is not a PowerShell parameter name"
    }
    $value = $Parameters[$key]
    if ($value -is [bool]) { $map[$name] = [bool]$value; continue }
    if ($value -is [int] -or $value -is [long]) { $map[$name] = [int64]$value; continue }
    $text = "$value"
    if ($text -match '[
]') { throw "E_ACC_ARGUMENTS: the value of '$name' carries a line break" }
    $map[$name] = $text
  }
  return $map
}

function New-ZCodeAcceptanceInstalledScriptCommand {
  <#
  The child command that runs one installed product script with a hostile
  environment and EXPLICIT NAMED PARAMETERS: the JSON map is read back and
  splatted (& script @argMap), so no argument text is ever concatenated and
  quoting can never turn a parameter name into a value.
  #>
  param(
    [Parameter(Mandatory = $true)][string]$ScriptPath,
    [Parameter(Mandatory = $true)][string]$ParameterMapPath,
    [Parameter(Mandatory = $true)][string]$HostileNodePath,
    [string]$PathValue = ''
  )
  $scriptLiteral = $ScriptPath.Replace("'", "''")
  $mapLiteral = $ParameterMapPath.Replace("'", "''")
  $nodeLiteral = $HostileNodePath.Replace("'", "''")
  $pathLiteral = $PathValue.Replace("'", "''")
  $source = @"
`$ErrorActionPreference = 'Stop'
`$env:ZCODE_DREAM_SKIN_NODE = '$nodeLiteral'
`$env:PATH = '$pathLiteral'
`$argMap = [ordered]@{}
foreach (`$property in ((Get-Content -LiteralPath '$mapLiteral' -Raw -Encoding UTF8) | ConvertFrom-Json).PSObject.Properties) {
  `$argMap[`$property.Name] = `$property.Value
}
& '$scriptLiteral' @argMap
exit `$LASTEXITCODE
"@
  return [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($source))
}
