<#
ZCode adapter for Dream Skin.

This file holds every ZCode-specific decision that upstream's Codex logic cannot
express: executable discovery, Authenticode identity, and the version
fingerprint. Pure logic takes injectable inputs so it can be tested without a
real install; the system wrappers at the bottom are the only parts that touch
the machine.
#>

# Publisher: Beijing Zhipu Huazhang Technology Co., Ltd. (Zhipu AI), spelled as
# code points so the check cannot be silently defeated by a mis-decoded literal:
# Windows PowerShell 5.1 reads a BOM-less .ps1 as ANSI and would mojibake it.
$script:ZCodeSignerSubjectToken = -join @(
  0x5317, 0x4EAC, 0x667A, 0x8C31, 0x534E, 0x7AE0, 0x79D1, 0x6280,
  0x80A1, 0x4EFD, 0x6709, 0x9650, 0x516C, 0x53F8 | ForEach-Object { [char]$_ }
)
$script:ZCodeProductName = 'ZCode'
$script:ZCodeRelativeCandidatePaths = @(
  'AI\ZCode\ZCode.exe',
  'Apps\ZCode\ZCode.exe',
  'Program Files\ZCode\ZCode.exe',
  'ZCode\ZCode.exe'
)

function Resolve-ZCodeExecutable {
  <#
  Picks the one ZCode executable to use. A configured path wins outright; otherwise
  the surviving candidate list must be exactly one entry, so an ambiguous machine
  asks the user instead of guessing.
  #>
  param(
    [string]$ConfiguredPath,
    [string[]]$CandidatePaths = @(),
    [scriptblock]$PathExists = { param($p) Test-Path -LiteralPath $p -PathType Leaf }
  )
  if ($ConfiguredPath -and (& $PathExists $ConfiguredPath)) { return $ConfiguredPath }
  $valid = @($CandidatePaths | Where-Object { $_ -and (& $PathExists $_) } | Select-Object -Unique)
  if ($valid.Count -eq 0) { throw 'E01_ZCODE_NOT_FOUND: no executable candidate' }
  if ($valid.Count -gt 1) { throw 'E03_ZCODE_MULTIPLE_CANDIDATES: user selection required' }
  return $valid[0]
}

function Test-ZCodeIdentityMetadata {
  <#
  Accepts only a valid Authenticode signature by the Zhipu publisher on a binary
  that calls itself ZCode. There is no override: a caller that cannot satisfy this
  must refuse to inject.
  #>
  param([Parameter(Mandatory = $true)]$Metadata)
  $ok = $Metadata.SignatureStatus -ceq 'Valid' -and
        $Metadata.SignerSubject -like "*$($script:ZCodeSignerSubjectToken)*" -and
        $Metadata.ProductName -ceq $script:ZCodeProductName
  if (-not $ok) { throw 'E02_ZCODE_IDENTITY_INVALID: signature or product mismatch' }
  return $true
}

function Get-ZCodeIdentityMetadata {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "E01_ZCODE_NOT_FOUND: $Path"
  }
  $signature = Get-AuthenticodeSignature -LiteralPath $Path
  $versionInfo = (Get-Item -LiteralPath $Path).VersionInfo
  $subject = ''
  $thumbprint = ''
  if ($signature.SignerCertificate) {
    $subject = [string]$signature.SignerCertificate.Subject
    $thumbprint = [string]$signature.SignerCertificate.Thumbprint
  }
  [pscustomobject]@{
    Path              = $Path
    SignatureStatus   = [string]$signature.Status
    SignerSubject     = $subject
    SignerThumbprint  = $thumbprint
    ProductName       = [string]$versionInfo.ProductName
    FileVersion       = [string]$versionInfo.FileVersion
    ProductVersion    = [string]$versionInfo.ProductVersion
  }
}

function Get-ZCodeFingerprint {
  <#
  Diagnostic identity of one verified build. The hash deliberately is not pinned
  across versions: a legitimate upgrade changes the bytes, and identity is carried
  by the signature, product name, path, and version instead.
  #>
  param([Parameter(Mandatory = $true)][string]$Path)
  $metadata = Get-ZCodeIdentityMetadata -Path $Path
  [pscustomobject]@{
    path             = $metadata.Path
    sha256           = (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
    fileVersion      = $metadata.FileVersion
    productVersion   = $metadata.ProductVersion
    signerThumbprint = $metadata.SignerThumbprint
  }
}

function Get-ZCodeStartMenuShortcutTargets {
  # Bounded scan: the two Start Menu roots only, never the whole disk.
  param([string[]]$Roots = @(
    (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'),
    (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs')
  ))
  $targets = New-Object System.Collections.Generic.List[string]
  $shell = $null
  try {
    foreach ($root in $Roots) {
      if (-not $root -or -not (Test-Path -LiteralPath $root -PathType Container)) { continue }
      foreach ($shortcut in Get-ChildItem -LiteralPath $root -Filter '*.lnk' -Recurse -File -ErrorAction SilentlyContinue) {
        if ($shortcut.BaseName -notlike '*ZCode*') { continue }
        if ($null -eq $shell) { $shell = New-Object -ComObject WScript.Shell }
        $target = $shell.CreateShortcut($shortcut.FullName).TargetPath
        if ($target -and [System.IO.Path]::GetFileName($target) -ieq 'ZCode.exe') {
          $targets.Add($target)
        }
      }
    }
  } catch {
    # Shortcut resolution is best effort; the drive scan below still covers an install.
  }
  return @($targets)
}

function Get-ZCodeCandidatePaths {
  <#
  Candidate executables for the picker, assembled from the user's configuration,
  Start Menu shortcuts, both Program Files roots, and a fixed short list of app
  directories on ready fixed drives. Never recurse a whole volume.
  #>
  param([string]$ConfiguredPath)
  $candidates = New-Object System.Collections.Generic.List[string]
  if ($ConfiguredPath) { $candidates.Add($ConfiguredPath) }
  foreach ($target in Get-ZCodeStartMenuShortcutTargets) { $candidates.Add($target) }
  foreach ($base in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
    if ($base) { $candidates.Add((Join-Path $base 'ZCode\ZCode.exe')) }
  }
  foreach ($drive in [System.IO.DriveInfo]::GetDrives()) {
    if ($drive.DriveType -ne [System.IO.DriveType]::Fixed -or -not $drive.IsReady) { continue }
    foreach ($relative in $script:ZCodeRelativeCandidatePaths) {
      $candidates.Add((Join-Path $drive.RootDirectory.FullName $relative))
    }
  }
  return @($candidates | Where-Object { $_ } | Select-Object -Unique)
}

function New-ZCodeLaunchArguments {
  <#
  Loopback-only CDP launch arguments. The address flag is deliberately not
  configurable: a non-loopback debugging endpoint would expose the renderer to
  the network, which the design forbids outright.
  #>
  param([ValidateRange(1024, 65535)][int]$Port)
  @('--remote-debugging-address=127.0.0.1', "--remote-debugging-port=$Port")
}

function Get-ZCodeDescendantProcessIds {
  <#
  The root PID plus every transitive descendant, computed from a process
  snapshot. The root is included so callers can test membership against one set.
  #>
  param(
    [Parameter(Mandatory = $true)][int]$RootPid,
    [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$ProcessRows
  )
  $ids = New-Object System.Collections.Generic.HashSet[int]
  $null = $ids.Add($RootPid)
  do {
    $added = $false
    foreach ($row in $ProcessRows) {
      $childId = [int]$row.ProcessId
      $parentId = [int]$row.ParentProcessId
      if ($ids.Contains($parentId) -and -not $ids.Contains($childId)) {
        $null = $ids.Add($childId)
        $added = $true
      }
    }
  } while ($added)
  return @($ids)
}

function Test-ZCodePortOwner {
  <#
  Accepts a CDP port only when the owning PID belongs to the ZCode process tree
  this run launched. A foreign owner is never terminated; it is reported.
  #>
  param(
    [Parameter(Mandatory = $true)][int]$RootPid,
    [Parameter(Mandatory = $true)][int]$OwnerPid,
    [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$ProcessRows
  )
  $ids = Get-ZCodeDescendantProcessIds -RootPid $RootPid -ProcessRows $ProcessRows
  if ($ids -notcontains $OwnerPid) {
    throw "E05_CDP_PORT_FOREIGN_OWNER: PID $OwnerPid is outside the verified ZCode process tree"
  }
  return $true
}

function Assert-ZCodePortListeners {
  <#
  Every listener on the CDP port must be loopback and owned by the verified tree.
  A foreign or network-published listener is reported, never terminated: this
  tool does not hold the right to end a process it did not start.
  #>
  param(
    [Parameter(Mandatory = $true)][int]$Port,
    [Parameter(Mandatory = $true)][int]$RootPid,
    [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Listeners,
    [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$ProcessRows
  )
  $relevant = @($Listeners | Where-Object { [int]$_.LocalPort -eq $Port })
  if ($relevant.Count -eq 0) {
    throw "E06_CDP_ENDPOINT_UNAVAILABLE: nothing is listening on port $Port"
  }
  $ids = Get-ZCodeDescendantProcessIds -RootPid $RootPid -ProcessRows $ProcessRows
  foreach ($listener in $relevant) {
    $address = [string]$listener.LocalAddress
    if (@('127.0.0.1', '::1', 'localhost') -notcontains $address) {
      throw "E05_CDP_PORT_FOREIGN_OWNER: port $Port is published outside loopback as $address"
    }
    $owner = [int]$listener.OwningProcess
    if ($ids -notcontains $owner) {
      throw "E05_CDP_PORT_FOREIGN_OWNER: port $Port is owned by PID $owner outside the verified ZCode process tree"
    }
  }
  return $true
}

function Get-ZCodeRunningProcessRows {
  param([Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$ProcessRows)
  return @($ProcessRows | Where-Object { [string]$_.Name -imatch '^ZCode(\.exe)?$' })
}

function Assert-ZCodeNoUnmanagedInstance {
  <#
  Fail closed before launching when ZCode is already running outside a verified
  Dream Skin session. The caller's only safe move is to ask the user to close it
  normally; force-killing it could discard their unsaved work.
  #>
  param(
    [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$ProcessRows,
    [int]$ManagedRootPid = 0
  )
  $running = @(Get-ZCodeRunningProcessRows -ProcessRows $ProcessRows |
    ForEach-Object { [int]$_.ProcessId })
  $unmanaged = @($running | Where-Object { $_ -ne $ManagedRootPid })
  if ($unmanaged.Count -gt 0) {
    throw "E04_ZCODE_RUNNING_WITHOUT_CDP: ZCode is already running (PID $($unmanaged -join ', ')) without a verified Dream Skin session; close it normally and retry"
  }
  return $true
}

function Test-ZCodeMainInstanceEvidence {
  <#
  The Phase 1 launch gate. A process that was briefly alive proves nothing, so a
  launch only counts when the main process is still alive after a settle interval,
  has at least one descendant (a real Electron instance rather than a stub), and
  shows usable main-instance evidence: a window, or a CDP endpoint that already
  lists a page target.
  #>
  param(
    [Parameter(Mandatory = $true)][bool]$RootAlive,
    [Parameter(Mandatory = $true)][bool]$RootAliveAtSecondSample,
    [Parameter(Mandatory = $true)][int]$ZcodeDescendantCount,
    [Parameter(Mandatory = $true)][bool]$MainWindowPresent,
    [Parameter(Mandatory = $true)][bool]$CdpEndpointWithPageTarget
  )
  if (-not $RootAlive -or -not $RootAliveAtSecondSample) { return $false }
  if ($ZcodeDescendantCount -lt 1) { return $false }
  return ($MainWindowPresent -or $CdpEndpointWithPageTarget)
}

function Get-ZCodeLaunchOutcome {
  <#
  Classifies a launch attempt. An immediate exit is attributed to the machine-wide
  single-instance guard only when an older instance exists, the process exited
  cleanly, and no new main process appeared; every other exit stays a generic
  launch failure so the raw evidence is never explained away.
  #>
  param(
    [Parameter(Mandatory = $true)][int]$PreExistingInstanceCount,
    [Parameter(Mandatory = $true)][bool]$LaunchedProcessExited,
    [AllowNull()]$ExitCode,
    [Parameter(Mandatory = $true)][bool]$NewMainProcessFound
  )
  if (-not $LaunchedProcessExited) { return 'running' }
  if ($PreExistingInstanceCount -gt 0 -and -not $NewMainProcessFound -and $ExitCode -eq 0) {
    return 'existing-instance-single-instance-guard'
  }
  return 'launch-failed'
}

function Resolve-ZCodeMainProcess {
  <#
  Resolves the one process that represents this launch's main ZCode instance.

  A launcher may hand off: the PID Start-Process returns can be alive at the first
  sample and gone a moment later, while the real main process is a different, newer
  PID. That PID is therefore trusted only while it still exists; once it is gone the
  main process is re-resolved from processes that did not exist before this launch,
  carry no --type= switch, and are named ZCode. When a verified executable path is
  supplied, identity is that path rather than the process name, so a same-named
  binary installed elsewhere is never adopted. Zero or several candidates stay
  unresolved rather than guess, and a process that was already running before this
  launch is never adopted.
  #>
  param(
    [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$ProcessRows,
    [Parameter(Mandatory = $true)][int]$LaunchedPid,
    [Parameter(Mandatory = $true)][bool]$LaunchedProcessExited,
    [Parameter(Mandatory = $true)][AllowEmptyCollection()][int[]]$PreExistingProcessIds,
    [string]$VerifiedExecutablePath = ''
  )
  $rows = @($ProcessRows)
  $stillLaunched = (-not $LaunchedProcessExited) -and
    (@($rows | Where-Object { [int]$_.ProcessId -eq $LaunchedPid }).Count -eq 1)
  if ($stillLaunched) {
    return [pscustomobject]@{
      rootPid = $LaunchedPid; source = 'launched'; candidateCount = 1; rootAlive = $true
    }
  }
  $expectedPath = ''
  if ($VerifiedExecutablePath) { $expectedPath = $VerifiedExecutablePath.TrimEnd('\') }
  $candidates = @($rows | Where-Object {
      $pathMatches = $true
      if ($expectedPath) {
        $pathMatches = $false
        $candidatePath = [string]$_.ExecutablePath
        if ($candidatePath) { $pathMatches = ($candidatePath.TrimEnd('\') -ieq $expectedPath) }
      }
      ([string]$_.Name -imatch '^ZCode(\.exe)?$') -and $pathMatches -and
      ([string]$_.CommandLine -notmatch '--type=') -and
      ($PreExistingProcessIds -notcontains [int]$_.ProcessId) -and
      ([int]$_.ProcessId -ne $LaunchedPid)
    })
  if ($candidates.Count -eq 1) {
    return [pscustomobject]@{
      rootPid = [int]$candidates[0].ProcessId
      source = 'successor'
      candidateCount = 1
      rootAlive = $true
    }
  }
  return [pscustomobject]@{
    rootPid = 0; source = 'unresolved'; candidateCount = $candidates.Count; rootAlive = $false
  }
}

function Get-ZCodeDreamSkinTrayMutexName {
  # The same name the ZCode tray creates for its lifetime. Kept in one place so a
  # check can never test a different product's tray.
  return "Local\ZCodeDreamSkin.$env:USERNAME.Tray"
}

function Test-ZCodeDreamSkinTrayActive {
  <#
  A running tray holds this mutex for its whole lifetime, so acquiring it proves the
  tray is gone. Abandoned mutexes count as acquired: the owning process died.
  #>
  $mutex = [System.Threading.Mutex]::new($false, (Get-ZCodeDreamSkinTrayMutexName))
  $acquired = $false
  try {
    try { $acquired = $mutex.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $acquired = $true }
    if ($acquired) { $mutex.ReleaseMutex(); $acquired = $false; return $false }
    return $true
  } finally {
    if ($acquired) { try { $mutex.ReleaseMutex() } catch { } }
    $mutex.Dispose()
  }
}

function Get-ZCodeTrayInstanceMarkerPath {
  param([Parameter(Mandatory = $true)][string]$StateRoot)
  return Join-Path $StateRoot 'tray-instance.json'
}

function Get-ZCodeTrayRequestRoot {
  param([Parameter(Mandatory = $true)][string]$StateRoot)
  return Join-Path (Join-Path $StateRoot 'tray-requests') ''
}

function Test-ZCodeTrayInstanceId {
  # An instance directory name is one 32-hex leaf and nothing else: a stop request
  # must never become a path into another product's state root.
  param([string]$InstanceId)
  return ($InstanceId -cmatch '^[0-9a-f]{32}$')
}

function Write-ZCodeTrayInstanceMarker {
  <#
  Published by the tray that owns the mutex, and only by it. The marker is what turns
  "some tray is alive" into "THIS tray is alive", so a stop request can be addressed
  to an instance instead of being a flag any future tray trips over on startup.
  #>
  param(
    [Parameter(Mandatory = $true)][string]$StateRoot,
    [Parameter(Mandatory = $true)][string]$InstanceId,
    [Parameter(Mandatory = $true)][int]$ProcessId,
    [Parameter(Mandatory = $true)][string]$ScriptPath,
    $CreatedAt = $null
  )
  if (-not (Test-ZCodeTrayInstanceId -InstanceId $InstanceId)) {
    throw 'E13_STATE_SCHEMA_INVALID: the tray instance id must be 32 lowercase hex characters'
  }
  $marker = [ordered]@{
    schemaVersion = 'zcode-dream-skin-tray-instance/1'
    instanceId    = $InstanceId
    processId     = $ProcessId
    scriptPath    = $ScriptPath
    createdAtUtc  = $(if ($CreatedAt) { ([datetime]$CreatedAt).ToUniversalTime().ToString('o') } else { (Get-Date).ToUniversalTime().ToString('o') })
  }
  $path = Get-ZCodeTrayInstanceMarkerPath -StateRoot $StateRoot
  $temp = "$path.tmp-$([guid]::NewGuid().ToString('N'))"
  try {
    $null = [System.IO.Directory]::CreateDirectory($StateRoot)
    [System.IO.File]::WriteAllText($temp, (ConvertTo-Json $marker -Depth 5 -Compress), [System.Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temp -Destination $path -Force
  } finally {
    if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
  }
  return $path
}

function Read-ZCodeTrayInstanceMarker {
  param([Parameter(Mandatory = $true)][string]$StateRoot)
  $path = Get-ZCodeTrayInstanceMarkerPath -StateRoot $StateRoot
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    return [pscustomobject]@{ status = 'absent'; marker = $null; errorCode = $null }
  }
  $item = Get-Item -LiteralPath $path
  if ($item.Length -gt 16384) {
    return [pscustomobject]@{ status = 'invalid'; marker = $null; errorCode = 'TRAY_INSTANCE_TOO_LARGE' }
  }
  try { $marker = ConvertFrom-Json ([System.IO.File]::ReadAllText($path)) } catch {
    return [pscustomobject]@{ status = 'invalid'; marker = $null; errorCode = 'TRAY_INSTANCE_MALFORMED_JSON' }
  }
  if (-not $marker -or [string]$marker.schemaVersion -cne 'zcode-dream-skin-tray-instance/1' -or
      -not (Test-ZCodeTrayInstanceId -InstanceId ([string]$marker.instanceId))) {
    return [pscustomobject]@{ status = 'invalid'; marker = $null; errorCode = 'TRAY_INSTANCE_SCHEMA_INVALID' }
  }
  return [pscustomobject]@{ status = 'valid'; marker = $marker; errorCode = $null }
}

function Remove-ZCodeTrayInstanceMarker {
  <#
  Only the instance that owns the marker may take it away: a tray that started later
  must never delete its predecessor's record and inherit a stop request aimed at it.
  #>
  param(
    [Parameter(Mandatory = $true)][string]$StateRoot,
    [Parameter(Mandatory = $true)][string]$InstanceId
  )
  $read = Read-ZCodeTrayInstanceMarker -StateRoot $StateRoot
  if ($read.status -eq 'absent') { return @{ removed = $false; reason = 'no marker to remove' } }
  if ($read.status -eq 'invalid') { return @{ removed = $false; reason = $read.errorCode } }
  if ([string]$read.marker.instanceId -cne $InstanceId) {
    return @{ removed = $false; reason = 'the marker belongs to another tray instance' }
  }
  Remove-Item -LiteralPath (Get-ZCodeTrayInstanceMarkerPath -StateRoot $StateRoot) -Force -ErrorAction SilentlyContinue
  return @{ removed = $true; reason = 'removed' }
}

function Register-ZCodeTrayStopRequest {
  <#
  Addressed to one instance and published atomically, so a tray either sees the
  request or does not - never half of it.
  #>
  param(
    [Parameter(Mandatory = $true)][string]$StateRoot,
    [Parameter(Mandatory = $true)][string]$InstanceId,
    [string]$RequestId = ''
  )
  if (-not (Test-ZCodeTrayInstanceId -InstanceId $InstanceId)) {
    throw 'E13_STATE_SCHEMA_INVALID: refusing to publish a stop request for an unverifiable tray instance'
  }
  if (-not $RequestId) { $RequestId = [guid]::NewGuid().ToString('N') }
  if ($RequestId -cnotmatch '^[0-9a-f]{32}$') { throw 'E13_STATE_SCHEMA_INVALID: the request id must be 32 lowercase hex characters' }
  $directory = Join-Path (Get-ZCodeTrayRequestRoot -StateRoot $StateRoot) $InstanceId
  $null = [System.IO.Directory]::CreateDirectory($directory)
  $final = Join-Path $directory ($RequestId + '.stop.json')
  $temp = "$final.tmp"
  $body = [ordered]@{
    schemaVersion = 'zcode-dream-skin-tray-request/1'
    requestId     = $RequestId
    instanceId    = $InstanceId
    action        = 'stop'
    requestedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
  }
  $body = ConvertTo-Json -InputObject $body -Depth 4 -Compress
  try {
    [System.IO.File]::WriteAllText($temp, $body, [System.Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temp -Destination $final -Force
  } finally {
    if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
  }
  return $final
}

function Get-ZCodeTrayStopRequest {
  <#
  The consumer's whole view: requests addressed to MY instance, in publication order.
  A legacy unaddressed tray-stop.request is reported and left in place - acting on it
  would let a stale flag from a previous run kill a tray that has not done anything
  wrong, which is exactly how a residue made the next launch exit immediately.
  #>
  param(
    [Parameter(Mandatory = $true)][string]$StateRoot,
    [Parameter(Mandatory = $true)][string]$InstanceId
  )
  $legacyPath = Join-Path $StateRoot 'tray-stop.request'
  $result = [pscustomobject]@{
    requests = @()
    legacyRequestPresent = [bool](Test-Path -LiteralPath $legacyPath -PathType Leaf)
    errorCode = $null
  }
  if (-not (Test-ZCodeTrayInstanceId -InstanceId $InstanceId)) {
    return [pscustomobject]@{ requests = @(); legacyRequestPresent = $result.legacyRequestPresent; errorCode = 'TRAY_INSTANCE_SCHEMA_INVALID' }
  }
  $directory = Join-Path (Get-ZCodeTrayRequestRoot -StateRoot $StateRoot) $InstanceId
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) { return $result }
  $found = @()
  foreach ($file in @(Get-ChildItem -LiteralPath $directory -Filter '*.stop.json' | Sort-Object CreationTime, Name)) {
    $item = Get-Item -LiteralPath $file.FullName
    if ($item.Length -gt 16384) { continue }
    try { $request = ConvertFrom-Json ([System.IO.File]::ReadAllText($file.FullName)) } catch { continue }
    if ([string]$request.instanceId -cne $InstanceId -or [string]$request.action -cne 'stop') { continue }
    $found += [pscustomobject]@{
      RequestId = [string]$request.requestId
      Path      = $file.FullName
      Created   = $item.CreationTime
    }
  }
  $result.requests = @($found | Sort-Object Created)
  return $result
}

function Complete-ZCodeTrayStopRequest {
  param(
    [Parameter(Mandatory = $true)][string]$StateRoot,
    [Parameter(Mandatory = $true)][string]$InstanceId,
    [Parameter(Mandatory = $true)][string]$RequestId
  )
  if (-not (Test-ZCodeTrayInstanceId -InstanceId $InstanceId) -or $RequestId -cnotmatch '^[0-9a-f]{32}$') {
    return @{ removed = $false; reason = 'TRAY_REQUEST_IDENTITY_INVALID' }
  }
  $path = Join-Path (Join-Path (Get-ZCodeTrayRequestRoot -StateRoot $StateRoot) $InstanceId) ($RequestId + '.stop.json')
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return @{ removed = $false; reason = 'already handled' } }
  Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
  return @{ removed = $true; reason = 'handled by its own instance' }
}

function Stop-ZCodeDreamSkinTray {
  <#
  Graceful first, precise fallback, never a sweep.

  The tray is asked to exit through a request file in the state root and given a
  bounded chance to release its mutex. Only if it does not is the upstream precise
  stop used, which matches this product's exact tray script path on the current
  user's PowerShell processes. A tray that cannot be confirmed gone is reported as
  not stopped so the caller can abort instead of removing files under a live tray.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)][string]$PayloadRoot,
    [string]$StateRoot = '',
    [int]$GracefulSeconds = 5,
    [scriptblock]$Sleep = $null,
    [scriptblock]$StopMatchingTray = $null,
    [scriptblock]$TestActive = $null
  )
  $sleepOf = if ($Sleep) { $Sleep } else { { param($Ms) Start-Sleep -Milliseconds $Ms } }
  $activeOf = if ($TestActive) { $TestActive } else { { Test-ZCodeDreamSkinTrayActive } }
  $trayScript = Join-Path (Join-Path $PayloadRoot 'scripts') 'tray-zcode-dream-skin.ps1'

  if (-not (& $activeOf)) {
    return @{ stopped = $true; graceful = $false; reason = 'the tray is not running' }
  }
  $legacyPath = Join-Path $StateRoot 'tray-stop.request'
  $legacyPresent = [bool]($StateRoot -and (Test-Path -LiteralPath $legacyPath -PathType Leaf))
  if ($StateRoot) {
    # The request is addressed to the instance that published its marker, and only
    # while that marker's process is actually alive. A ghost marker, an unreadable
    # marker, or a leftover flag from a previous run never buys a graceful stop:
    # acting on those is how a residue made the NEXT tray exit on its first poll.
    $targetInstanceId = ''
    $markerRead = Read-ZCodeTrayInstanceMarker -StateRoot $StateRoot
    if ($markerRead.status -eq 'valid') {
      $candidatePid = [int]$markerRead.marker.processId
      if (Get-Process -Id $candidatePid -ErrorAction SilentlyContinue) {
        $targetInstanceId = [string]$markerRead.marker.instanceId
      }
    }
    $requestPath = $null
    if ($targetInstanceId) {
      try {
        $requestPath = Register-ZCodeTrayStopRequest -StateRoot $StateRoot -InstanceId $targetInstanceId
      } catch {
        $requestPath = $null
      }
    }
    if ($requestPath) {
      $attempts = [Math]::Max(1, [int]($GracefulSeconds * 4))
      for ($attempt = 0; $attempt -lt $attempts; $attempt++) {
        if (-not (& $activeOf)) { break }
        & $sleepOf 250 | Out-Null
      }
      if (-not (& $activeOf)) {
        return @{ stopped = $true; graceful = $true; reason = 'the tray exited on its stop request';
          targetInstanceId = $targetInstanceId; legacyRequestPresent = $legacyPresent }
      }
    }
  }

  $stopOf = if ($StopMatchingTray) { $StopMatchingTray } else {
    { param($ScriptPath) Stop-DreamSkinTrayProcess -ScriptPaths @($ScriptPath) -RequireStopped }
  }
  try {
    & $stopOf $trayScript
  } catch {
    return @{ stopped = $false; graceful = $false; reason = $_.Exception.Message; legacyRequestPresent = $legacyPresent }
  }
  if (& $activeOf) {
    return @{ stopped = $false; graceful = $false; reason = 'the tray is still active after the precise stop'; legacyRequestPresent = $legacyPresent }
  }
  return @{ stopped = $true; graceful = $false; reason = 'the precise tray stop closed the tray'; legacyRequestPresent = $legacyPresent }
}

function Split-ZCodeCommandLineArgument {
  <#
  A Windows command line is one flat string, so substring tests can invent
  arguments: a single quoted blob "--port 9445" contains the flag but is one
  argument, not two tokens. Ownership is decided on real argument boundaries.
  #>
  param([string]$CommandLine)
  $tokens = @()
  if (-not $CommandLine) { return $tokens }
  foreach ($match in [regex]::Matches($CommandLine, '"([^"]*)"|[^\s"]+')) {
    if ($match.Groups[1].Success) { $tokens += $match.Groups[1].Value }
    else { $tokens += $match.Value }
  }
  return $tokens
}

function Get-ZCodeCommandLineFlagValue {
  param([string[]]$Tokens, [Parameter(Mandatory = $true)][string]$Flag)
  for ($index = 0; $index -lt $Tokens.Count; $index++) {
    if ($Tokens[$index] -ceq $Flag -and ($index + 1) -lt $Tokens.Count) { return $Tokens[$index + 1] }
  }
  return $null
}

function Test-ZCodeCommandLineArgumentToken {
  param([string[]]$Tokens, [Parameter(Mandatory = $true)][string]$Value)
  foreach ($token in $Tokens) { if ($token -ieq $Value) { return $true } }
  return $false
}

function Get-ZCodeSessionWatchers {
  <#
  The recorded state PID is a sample, not the session's watcher set: a reapply that
  survived a failed state write leaves live watchers the recording never names, and
  one of those keeps re-injecting the previous artwork. This enumerates every row
  that provably belongs to THIS session identity - trusted Node image, watch mode,
  this product's injector, this state file, this browser id, this port, and a
  creation time that cannot predate the verified root process.

  Anything that cannot be proven is returned as suspicious: never stopped, never
  silently treated as absent. conclusive=false is the caller's instruction to fail
  closed instead of arming another watcher.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]$State,
    [object[]]$ProcessRows = @(),
    [Parameter(Mandatory = $true)][string]$InjectorPath,
    [Parameter(Mandatory = $true)][string]$NodePath,
    [Parameter(Mandatory = $true)][string]$StateRoot
  )
  $owned = @()
  $suspicious = @()
  $foreign = @()
  $statePath = Join-Path $StateRoot 'state.json'

  $browserId = ''
  try { $browserId = [string](Get-ZCodeDreamSkinBrowserId -State $State) } catch { $browserId = '' }
  $port = [string]$State.port

  $trustedNode = ''
  if ($NodePath -and $NodePath -match '[\\/]') {
    try { $trustedNode = [System.IO.Path]::GetFullPath($NodePath) } catch { $trustedNode = $NodePath }
  }

  $rootRow = @($ProcessRows | Where-Object { [int]$_.ProcessId -eq [int]$State.rootPid } | Select-Object -First 1)
  $rootCreated = $null
  if ($rootRow.Count -eq 1 -and $rootRow[0].CreationDate) {
    try { $rootCreated = [datetime]$rootRow[0].CreationDate } catch { $rootCreated = $null }
  }

  foreach ($row in @($ProcessRows)) {
    if ($null -eq $row) { continue }
    $rowId = [int]$row.ProcessId
    $name = [string]$row.Name
    if ($name -and $name -ine 'node.exe') { $foreign += $row; continue }

    $executablePath = [string]$row.ExecutablePath
    if (-not $executablePath) { $suspicious += @{ processId = $rowId; reason = 'the executable path cannot be read' }; continue }
    if ($trustedNode) {
      $full = ''
      try { $full = [System.IO.Path]::GetFullPath($executablePath) } catch { $full = $executablePath }
      if ($full -ine $trustedNode) { $foreign += $row; continue }
    } elseif ([System.IO.Path]::GetFileName($executablePath) -ine 'node.exe') {
      $foreign += $row; continue
    }

    $commandLine = [string]$row.CommandLine
    if (-not $commandLine) { $suspicious += @{ processId = $rowId; reason = 'the command line cannot be read' }; continue }
    $tokens = @(Split-ZCodeCommandLineArgument -CommandLine $commandLine)

    if ((Get-ZCodeCommandLineFlagValue -Tokens $tokens -Flag '--mode') -cne 'zcode-watch') { $foreign += $row; continue }
    if (-not (Test-ZCodeCommandLineArgumentToken -Tokens $tokens -Value $InjectorPath)) { $foreign += $row; continue }
    $watchedState = Get-ZCodeCommandLineFlagValue -Tokens $tokens -Flag '--zcode-state-file'
    if (-not $watchedState -or $watchedState -ine $statePath) { $foreign += $row; continue }

    $rowPort = Get-ZCodeCommandLineFlagValue -Tokens $tokens -Flag '--port'
    if ($null -eq $rowPort) { $suspicious += @{ processId = $rowId; reason = 'no --port argument token proves the session port' }; continue }
    if ($rowPort -cne $port) { $suspicious += @{ processId = $rowId; reason = "port $rowPort is not this session's port $port" }; continue }

    $rowBrowser = Get-ZCodeCommandLineFlagValue -Tokens $tokens -Flag '--browser-id'
    if ($null -eq $rowBrowser) { $suspicious += @{ processId = $rowId; reason = 'no --browser-id argument token' }; continue }
    if (-not $browserId) { $suspicious += @{ processId = $rowId; reason = 'the state does not name a browser id' }; continue }
    if ($rowBrowser -cne $browserId) { $suspicious += @{ processId = $rowId; reason = 'a different browser id watches this state file' }; continue }

    if (-not $row.CreationDate) { $suspicious += @{ processId = $rowId; reason = 'the creation time cannot be read' }; continue }
    try {
      $rowCreated = [datetime]$row.CreationDate
    } catch {
      $suspicious += @{ processId = $rowId; reason = 'the creation time cannot be parsed' }; continue
    }
    if ($rootCreated -and $rowCreated -lt $rootCreated) {
      $suspicious += @{ processId = $rowId; reason = 'the process predates the verified root process' }; continue
    }
    $owned += $row
  }

  $conclusive = ($suspicious.Count -eq 0) -and [bool]$browserId -and [bool]$port
  $reason = "owned=$(@($owned).Count) suspicious=$(@($suspicious).Count) foreign=$(@($foreign).Count)"
  return @{
    owned      = @($owned)
    suspicious = @($suspicious)
    foreign    = @($foreign)
    conclusive = $conclusive
    reason     = $reason
  }
}

function Get-ZCodeManagedWatcherVerdict {
  <#
  A live PID is not a live watcher: PIDs are reused. The recorded PID is only
  accepted as this product's watcher when it is a Node executable whose command line
  carries the exact injector script, zcode-watch mode and the exact state file this
  restore is using. Anything else is reported and never stopped.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]$State,
    [object[]]$ProcessRows = @(),
    [Parameter(Mandatory = $true)][string]$InjectorPath,
    [Parameter(Mandatory = $true)][string]$StatePath,
    [string]$NodePath = 'node.exe'
  )
  $watchPid = [int]$State.watchPid
  if ($watchPid -le 0) { return @{ action = 'none'; reason = 'the state records no watcher' } }
  $rows = @($ProcessRows | Where-Object { [int]$_.ProcessId -eq $watchPid })
  if ($rows.Count -eq 0) { return @{ action = 'gone'; reason = "watcher PID $watchPid is not running" } }

  $executablePath = "$($rows[0].ExecutablePath)"
  if (-not $executablePath) {
    return @{ action = 'refuse'; reason = "watcher PID $watchPid cannot be inspected" }
  }
  if ([System.IO.Path]::GetFileName($executablePath) -ine 'node.exe') {
    return @{ action = 'refuse'; reason = "PID $watchPid is no longer a Node process ($executablePath)" }
  }
  if ($NodePath -and [System.IO.Path]::GetFileName($NodePath) -ieq 'node.exe' -and
      [System.IO.Path]::GetFileName($NodePath) -ine [System.IO.Path]::GetFileName($executablePath)) {
    return @{ action = 'refuse'; reason = "PID $watchPid runs a different Node executable" }
  }
  $commandLine = "$($rows[0].CommandLine)"
  if (-not $commandLine) {
    return @{ action = 'refuse'; reason = "watcher PID $watchPid command line cannot be read" }
  }
  if (-not (Test-DreamSkinCommandLineToken -CommandLine $commandLine -Token $InjectorPath)) {
    return @{ action = 'refuse'; reason = "PID $watchPid does not run this product's injector" }
  }
  if (-not (Test-DreamSkinCommandLineToken -CommandLine $commandLine -Token 'zcode-watch')) {
    return @{ action = 'refuse'; reason = "PID $watchPid is not in zcode-watch mode" }
  }
  if (-not (Test-DreamSkinCommandLineToken -CommandLine $commandLine -Token $StatePath)) {
    return @{ action = 'refuse'; reason = "PID $watchPid watches a different state file" }
  }
  return @{ action = 'stop'; reason = "watcher PID $watchPid is verified as this session's watcher" }
}

function Stop-ZCodeManagedWatch {
  <#
  The watcher is asked to stop through its own state-file flag first, so it exits
  cleanly and releases its CDP session; only an identity-verified watcher is ever
  ended by PID. A stop request is never retracted: a watcher that somehow outlives
  its session must not be able to come back and re-inject the theme.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]$State,
    [Parameter(Mandatory = $true)][string]$StateRoot,
    [Parameter(Mandatory = $true)][string]$InjectorPath,
    [string]$NodePath = 'node.exe',
    [scriptblock]$GetProcessRows = $null,
    [scriptblock]$Sleep = $null,
    [scriptblock]$StopProcess = $null,
    [int]$TimeoutSeconds = 10
  )
  $rowsOf = if ($GetProcessRows) { $GetProcessRows } else { { @(Get-ZCodeProcessSnapshot) } }
  $sleepOf = if ($Sleep) { $Sleep } else { { param($Ms) Start-Sleep -Milliseconds $Ms } }
  $stopOf = if ($StopProcess) { $StopProcess } else { { param($ProcessId) Stop-Process -Id $ProcessId -ErrorAction Stop } }
  $statePath = Join-Path (Get-ZCodeDreamSkinStateRoot -StateRoot $StateRoot) 'state.json'

  $verdict = Get-ZCodeManagedWatcherVerdict -State $State -ProcessRows @(& $rowsOf) `
    -InjectorPath $InjectorPath -StatePath $statePath -NodePath $NodePath
  $session = Get-ZCodeSessionWatchers -State $State -ProcessRows @(& $rowsOf) `
    -InjectorPath $InjectorPath -NodePath $NodePath -StateRoot $StateRoot
  $ownedIds = @($session.owned | ForEach-Object { [int]$_.ProcessId })
  $suspiciousIds = @($session.suspicious | ForEach-Object { [int]$_.processId })

  if ($verdict.action -eq 'refuse') {
    # A PID that no longer carries this session's identity is never touched, and no
    # stop request is published for it either.
    return @{ action = 'refuse'; stopped = $false; attempted = $false; reason = $verdict.reason; state = $State;
      owned = @($session.owned); suspicious = @($session.suspicious) }
  }
  if ($ownedIds.Count -eq 0 -and $suspiciousIds.Count -eq 0) {
    if ($verdict.action -eq 'stop') {
      # The recording proves the identity but the enumerable set could not be
      # built (no readable creation time): the recorded PID stays stoppable, the
      # enumeration is not allowed to pretend nothing is live.
      $ownedIds = @([int]$State.watchPid)
    } else {
      return @{ action = $verdict.action; stopped = $true; attempted = $false; reason = $verdict.reason; state = $State;
        owned = @(); suspicious = @($session.suspicious) }
    }
  }

  # The stop flag is published to the state file every one of these watchers
  # polls, so a watcher the recording never named exits on its own accord.
  $State = Set-ZCodeDreamSkinStopped -State $State -Stopped $true
  $null = Write-ZCodeDreamSkinState -StateRoot $StateRoot -State $State
  $targets = @($ownedIds + $suspiciousIds | Select-Object -Unique)
  $attempts = [Math]::Max(1, [int]($TimeoutSeconds * 4))
  $aliveOf = {
    param([int[]]$Ids)
    @(@(& $rowsOf) | Where-Object { $Ids -contains [int]$_.ProcessId }).Count
  }
  for ($attempt = 0; $attempt -lt $attempts; $attempt++) {
    if ((& $aliveOf $targets) -eq 0) {
      return @{ action = 'stopped'; stopped = $true; attempted = $false; reason = 'the watcher exited on its stop request'; state = $State;
        owned = @(); suspicious = @($session.suspicious) }
    }
    if ($attempt -lt ($attempts - 1)) { & $sleepOf 250 | Out-Null }
  }

  # Only a fully identified watcher may be ended by PID. A suspicious one is
  # reported and left running: killing an unproven process is never allowed.
  $attempted = $false
  foreach ($ownedId in $ownedIds) {
    try {
      & $stopOf $ownedId | Out-Null
      $attempted = $true
    } catch {
      return @{ action = 'refuse'; stopped = $false; attempted = $true; reason = "the verified watcher could not be stopped: $($_.Exception.Message)"; state = $State;
        owned = @($session.owned); suspicious = @($session.suspicious) }
    }
  }
  # A caller may retract the stop request only once every watcher is GONE, so the
  # PID path confirms the exit exactly like the graceful path does. A watcher that
  # somehow survives is reported as not stopped: the caller must fail closed
  # instead of publishing a fresh state under a live process.
  for ($attempt = 0; $attempt -lt 8; $attempt++) {
    if ((& $aliveOf $targets) -eq 0) {
      return @{ action = 'stopped'; stopped = $true; attempted = $attempted; reason = 'the verified watcher was stopped by PID'; state = $State;
        owned = @(); suspicious = @($session.suspicious) }
    }
    & $sleepOf 250 | Out-Null
  }
  $leftover = @($session.owned | Where-Object { $targets -contains [int]$_.ProcessId })
  return @{ action = 'refuse'; stopped = $false; attempted = $attempted; reason = 'the verified watcher survived its forced stop'; state = $State;
    owned = @($leftover); suspicious = @($session.suspicious) }
}
