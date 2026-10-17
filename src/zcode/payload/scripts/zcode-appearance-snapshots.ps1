<#
ZCode Dream Skin 2.0 appearance snapshots and library transactions.

The active theme is a working copy: the user may have changed its background without
ever saving it, and the saved library has no entry that is guaranteed to be equal to
what is on screen. So "restore my previous look" cannot point at a saved theme - it
has to point at an immutable copy of exactly what was confirmed. This module makes
those copies, keeps the backup a failed change needs, and never reaches for state.json:
a backup of an old session is not a ticket back into a new one.
#>

$script:ZCodeAppearanceSnapshotInfoName = 'snapshot-info.json'
$script:ZCodeAppearanceSnapshotMaxBytes = 16384
$script:ZCodeAppearanceCopyableFiles = @('theme.json', 'theme.css', 'LICENSE.txt')

function Get-ZCodeAppearanceSnapshotRoot {
  param([Parameter(Mandatory = $true)][string]$StateRoot)
  return Join-Path $StateRoot 'appearance-snapshots'
}

function Get-ZCodePresetOriginPath {
  # Written when public presets are seeded into the library, so a saved leaf can
  # say which unit its artwork arrived in. It lives outside every theme package:
  # the three-file contract stays untouched.
  param([Parameter(Mandatory = $true)][string]$StateRoot)
  return Join-Path $StateRoot 'preset-origin.json'
}

function Get-ZCodePresetOrigin {
  param([Parameter(Mandatory = $true)][string]$StateRoot, [Parameter(Mandatory = $true)][string]$Leaf)
  $path = Get-ZCodePresetOriginPath -StateRoot $StateRoot
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
  $item = Get-Item -LiteralPath $path
  if ($item.Length -gt 65536) { return $null }
  try { $registry = ConvertFrom-Json ([System.IO.File]::ReadAllText($path)) } catch { return $null }
  $entry = @($registry.entries | Where-Object { [string]$_.savedLeaf -ceq $Leaf } | Select-Object -First 1)
  if ($entry.Count -eq 0) { return $null }
  return $entry[0]
}

function Get-ZCodeAppearanceBackupRoot {
  param([Parameter(Mandatory = $true)][string]$StateRoot)
  return Join-Path $StateRoot 'appearance-backups'
}

function Get-ZCodeAppearanceDraftRoot {
  param([Parameter(Mandatory = $true)][string]$StateRoot)
  return Join-Path $StateRoot 'appearance-drafts'
}

function Get-ZCodeFileSha256 {
  param([Parameter(Mandatory = $true)][string]$Path)
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Copy-ZCodeThemeDirectoryContents {
  <#
  Copies the three-file contract plus the optional licence out of a theme directory.
  Only regular files whose names are the theme's own are taken, and a reparse hop in
  the source is refused: a snapshot must be a copy of bytes, not a pointer to
  something that may later change or escape.
  #>
  param(
    [Parameter(Mandatory = $true)][string]$Source,
    [Parameter(Mandatory = $true)][string]$Destination
  )
  $loaded = Read-DreamSkinTheme -ThemeDirectory $Source
  $null = [System.IO.Directory]::CreateDirectory($Destination)
  $names = @([System.IO.Path]::GetFileName($loaded.ImagePath))
  foreach ($candidate in $script:ZCodeAppearanceCopyableFiles) {
    $path = Join-Path $loaded.Directory $candidate
    if (Test-Path -LiteralPath $path -PathType Leaf) { $names += $candidate }
  }
  $copied = @()
  foreach ($name in $names) {
    $from = Join-Path $loaded.Directory $name
    $to = Join-Path $Destination $name
    $item = Get-Item -LiteralPath $from -Force
    if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
      throw "THEME_COPY_REPARSE: $name is a reparse point"
    }
    Copy-Item -LiteralPath $from -Destination $to -Force
    if ((Get-ZCodeFileSha256 -Path $from) -cne (Get-ZCodeFileSha256 -Path $to)) {
      throw "THEME_COPY_MISMATCH: $name did not copy byte-for-byte"
    }
    $copied += $name
  }
  return $copied
}

function New-ZCodeAppearanceSnapshot {
  <#
  Publishes an immutable copy under appearance-snapshots\<32-hex>. The bytes land in
  a temp directory first and only become visible once every file has been verified,
  so a half-written snapshot can never be named by a preference. A failed publish
  cleans up its own temp directory and nothing else.
  #>
  param(
    [Parameter(Mandatory = $true)][string]$StateRoot,
    [Parameter(Mandatory = $true)][string]$ThemeDirectory,
    $SourceSavedRef = $null,
    [string]$ConfirmedRevision = '',
    # Which unit the artwork in this directory was authored in. Recorded, never
    # inferred: the renderer needs percent, the package gate validates 0-1, and the
    # pre-2.0 private library stores percent with no marker at all.
    [ValidateSet('', 'dream-skin-v1-normalized', 'zcode-percent-v1')]
    [string]$ArtSourceFormat = ''
  )
  $key = [guid]::NewGuid().ToString('N')
  $snapshotRoot = Get-ZCodeAppearanceSnapshotRoot -StateRoot $StateRoot
  $null = [System.IO.Directory]::CreateDirectory($snapshotRoot)
  $temp = Join-Path $snapshotRoot ('.tmp-' + $key)
  $final = Join-Path $snapshotRoot $key
  $published = $false
  try {
    $sourceFingerprint = Get-DreamSkinThemeSemanticFingerprint -ThemeDirectory $ThemeDirectory
    $names = Copy-ZCodeThemeDirectoryContents -Source $ThemeDirectory -Destination $temp
    $info = [ordered]@{
      schemaVersion      = 'zcode-dream-skin-snapshot-info/1'
      sourceSavedRef     = $SourceSavedRef
      sourceFingerprint  = [string]$sourceFingerprint
      confirmedRevision  = [string]$ConfirmedRevision
      artSourceFormat    = [string]$ArtSourceFormat
      createdAtUtc       = (Get-Date).ToUniversalTime().ToString('o')
      files              = @($names)
    }
    $infoJson = ConvertTo-Json $info -Depth 6 -Compress
    if ([System.Text.Encoding]::UTF8.GetByteCount($infoJson) -gt $script:ZCodeAppearanceSnapshotMaxBytes) {
      return [pscustomobject]@{ ok = $false; themeRef = $null; errorCode = 'SNAPSHOT_INFO_TOO_LARGE' }
    }
    [System.IO.File]::WriteAllText((Join-Path $temp $script:ZCodeAppearanceSnapshotInfoName), $infoJson, [System.Text.UTF8Encoding]::new($false))
    $copyFingerprint = Get-DreamSkinThemeSemanticFingerprint -ThemeDirectory $temp
    if ($copyFingerprint -cne $sourceFingerprint) {
      return [pscustomobject]@{ ok = $false; themeRef = $null; errorCode = 'SNAPSHOT_FINGERPRINT_MISMATCH' }
    }
    Move-Item -LiteralPath $temp -Destination $final -Force
    $published = $true
    return [pscustomobject]@{
      ok        = $true
      themeRef  = [pscustomobject]@{ kind = 'snapshot'; key = $key; fingerprint = $copyFingerprint }
      revision  = $copyFingerprint.Substring(0, 20)
      directory = $final
      errorCode = $null
    }
  } finally {
    if (-not $published -and (Test-Path -LiteralPath $temp)) {
      Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
    }
  }
}

function Read-ZCodeAppearanceSnapshotInfo {
  param([Parameter(Mandatory = $true)][string]$StateRoot, [Parameter(Mandatory = $true)][string]$Key)
  if ($Key -cnotmatch '^[0-9a-f]{32}$') {
    return [pscustomobject]@{ status = 'invalid'; info = $null; errorCode = 'SNAPSHOT_KEY_INVALID' }
  }
  $path = Join-Path (Join-Path (Get-ZCodeAppearanceSnapshotRoot -StateRoot $StateRoot) $Key) $script:ZCodeAppearanceSnapshotInfoName
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    return [pscustomobject]@{ status = 'absent'; info = $null; errorCode = 'SNAPSHOT_MISSING' }
  }
  $item = Get-Item -LiteralPath $path
  if ($item.Length -gt $script:ZCodeAppearanceSnapshotMaxBytes) {
    return [pscustomobject]@{ status = 'invalid'; info = $null; errorCode = 'SNAPSHOT_INFO_TOO_LARGE' }
  }
  try {
    $info = ConvertFrom-Json ([System.IO.File]::ReadAllText($path))
  } catch {
    return [pscustomobject]@{ status = 'invalid'; info = $null; errorCode = 'SNAPSHOT_INFO_MALFORMED' }
  }
  return [pscustomobject]@{ status = 'valid'; info = $info; errorCode = $null }
}

function Get-ZCodeThemeRefDirectory {
  <#
  Turns a reference into a directory and re-proves the containment every time. The
  key is a leaf, never a path fragment: this is the last place a reference can be
  stopped before it becomes a write.
  #>
  param([Parameter(Mandatory = $true)][string]$StateRoot, [Parameter(Mandatory = $true)]$ThemeRef)
  $kind = [string]$ThemeRef.kind
  $key = [string]$ThemeRef.key
  if ($kind -eq 'saved') {
    if (-not (Get-ZCodeThemeDirectoryLeaf -Key $key -Kind 'saved')) {
      return [pscustomobject]@{ ok = $false; directory = ''; errorCode = 'THEME_LEAF_REJECTED' }
    }
    $root = Join-Path $StateRoot 'themes'
  } elseif ($kind -eq 'snapshot') {
    if ($key -cnotmatch '^[0-9a-f]{32}$') {
      return [pscustomobject]@{ ok = $false; directory = ''; errorCode = 'SNAPSHOT_KEY_INVALID' }
    }
    $root = Get-ZCodeAppearanceSnapshotRoot -StateRoot $StateRoot
  } else {
    return [pscustomobject]@{ ok = $false; directory = ''; errorCode = 'THEME_REF_KIND_INVALID' }
  }
  $directory = [System.IO.Path]::GetFullPath((Join-Path $root $key))
  if (-not (Test-DreamSkinThemePathWithin -Path $directory -Root $root)) {
    return [pscustomobject]@{ ok = $false; directory = ''; errorCode = 'THEME_PATH_ESCAPE' }
  }
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
    return [pscustomobject]@{ ok = $false; directory = ''; errorCode = 'THEME_NOT_FOUND' }
  }
  $item = Get-Item -LiteralPath $directory -Force
  if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
    return [pscustomobject]@{ ok = $false; directory = ''; errorCode = 'THEME_DIRECTORY_REPARSE' }
  }
  return [pscustomobject]@{ ok = $true; directory = $directory; errorCode = $null }
}

function Select-ZCodeActiveThemeRef {
  <#
  Copies a reference into the working active-theme directory through the existing
  product selector, with the state root named explicitly: the store helpers default
  to the Codex library, and silently writing there would be a private-data accident.
  #>
  param([Parameter(Mandatory = $true)][string]$StateRoot, [Parameter(Mandatory = $true)]$ThemeRef)
  $resolved = Get-ZCodeThemeRefDirectory -StateRoot $StateRoot -ThemeRef $ThemeRef
  if (-not $resolved.ok) {
    return [pscustomobject]@{ ok = $false; themeDirectory = ''; errorCode = $resolved.errorCode }
  }
  try {
    $loaded = Read-DreamSkinTheme -ThemeDirectory $resolved.directory
  } catch {
    return [pscustomobject]@{ ok = $false; themeDirectory = ''; errorCode = 'THEME_UNREADABLE' }
  }
  $cssPath = Join-Path $loaded.Directory 'theme.css'
  try {
    $null = Set-DreamSkinActiveTheme -ImagePath $loaded.ImagePath -Theme $loaded.Theme `
      -Name ([string]$loaded.Theme.name) `
      -SafeCssPath $(if (Test-Path -LiteralPath $cssPath -PathType Leaf) { $cssPath } else { $null }) `
      -StateRoot $StateRoot
  } catch {
    return [pscustomobject]@{ ok = $false; themeDirectory = $resolved.directory; errorCode = 'THEME_SELECT_FAILED' }
  }
  $sourceFormat = ''
  if ([string]$ThemeRef.kind -ceq 'snapshot') {
    $info = Read-ZCodeAppearanceSnapshotInfo -StateRoot $StateRoot -Key ([string]$ThemeRef.key)
    if ($info.status -eq 'valid') { $sourceFormat = [string]$info.info.artSourceFormat }
  } else {
    $origin = Get-ZCodePresetOrigin -StateRoot $StateRoot -Leaf ([string]$ThemeRef.key)
    if ($origin) { $sourceFormat = [string]$origin.artSourceFormat }
  }
  return [pscustomobject]@{ ok = $true; themeDirectory = $resolved.directory;
    artSourceFormat = $sourceFormat; errorCode = $null }
}

function New-ZCodeAppearanceLibraryBackup {
  <#
  A file-level backup of the things this operation is about to change: the working
  active theme and the saved library, each with the bytes recorded in a manifest. A
  hash list alone is not a backup - nothing would be recoverable from it.
  #>
  param([Parameter(Mandatory = $true)][string]$StateRoot)
  $stamp = (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
  $backupRoot = Get-ZCodeAppearanceBackupRoot -StateRoot $StateRoot
  $directory = Join-Path $backupRoot $stamp
  $null = [System.IO.Directory]::CreateDirectory($directory)
  $entries = @()
  foreach ($setName in @('active-theme', 'themes')) {
    $source = Join-Path $StateRoot $setName
    if (-not (Test-Path -LiteralPath $source -PathType Container)) { continue }
    foreach ($file in @(Get-ChildItem -LiteralPath $source -Recurse -File -Force -ErrorAction SilentlyContinue)) {
      $relative = Join-Path $setName $file.FullName.Substring($source.Length).TrimStart('\', '/')
      $target = Join-Path $directory $relative
      $null = [System.IO.Directory]::CreateDirectory((Split-Path -Parent $target))
      Copy-Item -LiteralPath $file.FullName -Destination $target -Force
      if ((Get-ZCodeFileSha256 -Path $file.FullName) -cne (Get-ZCodeFileSha256 -Path $target)) {
        return [pscustomobject]@{ ok = $false; manifestPath = ''; directory = ''; errorCode = 'BACKUP_MISMATCH' }
      }
      $entries += [ordered]@{
        relative = ($relative -replace '\\', '/')
        bytes    = [long]$file.Length
        sha256   = (Get-ZCodeFileSha256 -Path $file.FullName)
      }
    }
  }
  $manifest = [ordered]@{
    schemaVersion = 'zcode-dream-skin-backup/1'
    stateRoot     = $StateRoot
    takenAtUtc    = (Get-Date).ToUniversalTime().ToString('o')
    files         = @($entries)
  }
  $manifestPath = Join-Path $directory 'manifest.json'
  [System.IO.File]::WriteAllText($manifestPath, (ConvertTo-Json $manifest -Depth 6), [System.Text.UTF8Encoding]::new($false))
  return [pscustomobject]@{
    ok           = $true
    manifestPath = $manifestPath
    directory    = $directory
    fileCount    = @($entries).Count
    errorCode    = $null
  }
}

function Restore-ZCodeAppearanceLibrary {
  <#
  Writes back only the files this backup owns, byte for byte, and verifies each one.
  It never creates or rewrites state.json: bringing an old session's identity back
  into a live browser is exactly the mistake this generation is not allowed to repeat.
  #>
  param([Parameter(Mandatory = $true)][string]$StateRoot, [Parameter(Mandatory = $true)]$Backup)
  if (-not $Backup -or -not (Test-Path -LiteralPath ([string]$Backup.ManifestPath) -PathType Leaf)) {
    return [pscustomobject]@{ ok = $false; restored = 0; errorCode = 'BACKUP_MISSING' }
  }
  $manifest = ConvertFrom-Json ([System.IO.File]::ReadAllText([string]$Backup.ManifestPath))
  $restored = 0
  foreach ($entry in @($manifest.files)) {
    $relative = [string]$entry.relative
    if ($relative -eq '' -or $relative -match '(^|/)\.\.($|/)') { continue }
    if ($relative -like 'state.json' -or $relative -like '*/state.json') { continue }
    $source = Join-Path ([string]$Backup.Directory) ($relative -replace '/', '\')
    $target = Join-Path $StateRoot ($relative -replace '/', '\')
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
      return [pscustomobject]@{ ok = $false; restored = $restored; errorCode = 'BACKUP_FILE_MISSING' }
    }
    $null = [System.IO.Directory]::CreateDirectory((Split-Path -Parent $target))
    Copy-Item -LiteralPath $source -Destination $target -Force
    if ((Get-ZCodeFileSha256 -Path $target) -cne [string]$entry.sha256) {
      return [pscustomobject]@{ ok = $false; restored = $restored; errorCode = 'RESTORE_MISMATCH' }
    }
    $restored++
  }
  return [pscustomobject]@{ ok = $true; restored = $restored; errorCode = $null }
}

function Find-ZCodeThemeDeclarationByFingerprint {
  <#
  The same artwork numbers over two different sets of bytes are two different questions.
  Look a declaration up by the content it was made over, so a package that was already
  answered keeps its answer and a package whose bytes changed has to be asked again.
  #>
  param(
    [Parameter(Mandatory = $true)][string]$StateRoot,
    [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Fingerprint
  )
  if (-not $Fingerprint) { return $null }
  $root = Get-ZCodeDreamSkinStateRoot -StateRoot $StateRoot
  $document = Read-ZCodeThemeDeclarations -StateRoot $root
  if ([string]$document.status -cne 'ok') { return $null }
  foreach ($entry in @($document.entries)) {
    if ([string]$entry.sourceFingerprint -ceq $Fingerprint) { return $entry }
  }
  return $null
}

function Import-ZCodeAppearanceThemeArchive {
  <#
  The existing importer, with one addition: the artwork unit has to be settled before the
  package becomes a library leaf. An import that cannot settle it publishes nothing and
  says so; an import that settles it writes the saved library and stops there - it never
  selects, never applies and never touches the preference, because browsing a library
  must be safe.
  #>
  param(
    [Parameter(Mandatory = $true)][string]$StateRoot,
    [Parameter(Mandatory = $true)][string]$ArchivePath,
    # The artwork unit is declared by whoever owns the choice (the gallery's native
    # import flow or an operator CLI), never guessed from how large a number is.
    [ValidateSet('', 'dream-skin-v1-normalized', 'zcode-percent-v1')][string]$SourceFormat = '',
    # Whoever answers for the unit also says which bytes the answer was made over. The
    # shared importer already refuses an archive that does not match, before anything is
    # published, so an answer can never be spent on different content.
    [int64]$ExpectedArchiveBytes = -1,
    [AllowNull()][string]$ExpectedArchiveSha256 = $null
  )
  if (-not [System.IO.Path]::IsPathRooted($ArchivePath)) {
    return [pscustomobject]@{ ok = $false; data = $null; errorCode = 'INVALID_REQUEST' }
  }
  # The probe runs inside the importer's private extraction, before the artwork-unit
  # check and before anything is published. What it settles is remembered for the record
  # written after publishing, over the same bytes it was derived from.
  $script:Zds2ImportProbe = [pscustomobject]@{ settled = $false; classification = $null; fingerprint = '' }
  $probe = {
    param($ExtractedDirectory)
    $cssText = ''
    $cssPath = Join-Path $ExtractedDirectory 'theme.css'
    if (Test-Path -LiteralPath $cssPath -PathType Leaf) { $cssText = [System.IO.File]::ReadAllText($cssPath) }
    $fingerprint = ''
    try { $fingerprint = [string](Get-DreamSkinThemeSemanticFingerprint -ThemeDirectory $ExtractedDirectory) } catch { $fingerprint = '' }
    $unit = [string]$SourceFormat
    $declaredBy = $(if ($unit) { 'request' } else { 'none' })
    if (-not $unit) {
      $byContent = Find-ZCodeThemeDeclarationByFingerprint -StateRoot $StateRoot -Fingerprint $fingerprint
      if ($byContent) { $unit = [string]$byContent.sourceFormat; $declaredBy = 'declaration' }
    }
    if (-not $unit -and (Get-Command Get-ZCodePresetOrigin -ErrorAction SilentlyContinue)) {
      $presetId = ''
      try {
        $meta = [System.IO.File]::ReadAllText((Join-Path $ExtractedDirectory 'theme.json')) | ConvertFrom-Json
        $presetId = [string]$meta.id
      } catch { $presetId = '' }
      if ($presetId) {
        $origin = Get-ZCodePresetOrigin -StateRoot $StateRoot -Leaf $presetId
        # An id is a claim, not a proof: the origin entry only answers for the bytes its
        # own fingerprint was taken over.
        if ($origin -and [string]$origin.sourceFingerprint -and
            ([string]$origin.sourceFingerprint -ceq $fingerprint)) {
          $unit = [string]$origin.artSourceFormat; $declaredBy = 'preset'
        }
      }
    }
    $found = Get-ZCodeThemeTargetClassification -CssText $cssText -SourceFormat $unit -DeclaredBy $declaredBy
    if ([string]$found.reason -ceq 'TARGET_SOURCE_UNDECLARED') {
      $script:Zds2ImportProbe = [pscustomobject]@{ settled = $false; classification = $found; fingerprint = $fingerprint }
      throw 'SOURCE_DECLARATION_REQUIRED'
    }
    $script:Zds2ImportProbe = [pscustomobject]@{ settled = $true; classification = $found; fingerprint = $fingerprint }
    return [string]$unit
  }.GetNewClosure()

  try {
    $imported = Import-DreamSkinThemeZip -ArchivePath $ArchivePath -StateRoot $StateRoot `
      -ArtSourceFormat $SourceFormat -BeforePublish $probe `
      -ExpectedArchiveBytes $ExpectedArchiveBytes -ExpectedArchiveSha256 $ExpectedArchiveSha256
  } catch {
    # The code is for machines and the sentence is for people: a rejection that only
    # says IMPORT_REJECTED cannot be told apart from an out-of-memory crash.
    $detail = ("$($_.Exception.Message)" -replace '\s+', ' ')
    if ($detail.Length -gt 200) { $detail = $detail.Substring(0, 200) }
    if (Test-DreamSkinImportLockBusy $detail) {
      # Somebody else holds the shared import lock. Nothing was read wrong about this
      # package and nothing was written; answering IMPORT_REJECTED would tell the person
      # their file is the problem, and answering a recovery code would tell them the
      # library is torn. Both are lies - the true answer is "wait and try again".
      return [pscustomobject]@{ ok = $false; data = $null; errorCode = 'BUSY'; errorDetail = $detail }
    }
    if ($detail.Contains('SOURCE_DECLARATION_REQUIRED')) {
      # Nothing was published and nothing was declared: the package stays where it is
      # and the person who drew it is asked.
      return [pscustomobject]@{
        ok = $false
        data = [pscustomobject]@{
          targetCompatible = $false
          targetReason = 'TARGET_SOURCE_UNDECLARED'
        }
        errorCode = 'SOURCE_DECLARATION_REQUIRED'
        errorDetail = 'the artwork unit of this package has to be declared before it is saved'
      }
    }
    return [pscustomobject]@{ ok = $false; data = $null; errorCode = 'IMPORT_REJECTED'; errorDetail = $detail }
  }
  $leaf = ''
  $directory = ''
  # The importer reports Id (the saved leaf) and Path (its directory). Name is a
  # display label and was never a directory: reading it handed back a ThemeId that
  # resolved to nothing in the catalogue the caller was about to refresh.
  if ($imported) {
    if ($imported.PSObject.Properties['Id'] -and [string]$imported.Id) { $leaf = [string]$imported.Id }
    if ($imported.PSObject.Properties['Path'] -and [string]$imported.Path) { $directory = [string]$imported.Path }
  }
  if (-not $leaf) {
    return [pscustomobject]@{ ok = $false; data = $null; errorCode = 'IMPORT_UNIDENTIFIED' }
  }
  if (-not $directory) { $directory = Join-Path (Join-Path $StateRoot 'themes') $leaf }
  $resolved = ''
  try { $resolved = [System.IO.Path]::GetFullPath($directory) } catch { $resolved = '' }
  $themesRoot = [System.IO.Path]::GetFullPath((Join-Path $StateRoot 'themes'))
  $separator = [System.IO.Path]::DirectorySeparatorChar
  if (-not $resolved.StartsWith($themesRoot + $separator, [StringComparison]::OrdinalIgnoreCase)) {
    return [pscustomobject]@{ ok = $false; data = $null; errorCode = 'IMPORT_PATH_OUTSIDE_LIBRARY' }
  }
  if (((Get-Item -LiteralPath $resolved -Force).Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
    return [pscustomobject]@{ ok = $false; data = $null; errorCode = 'IMPORT_PATH_OUTSIDE_LIBRARY' }
  }
  $cssPath = Join-Path $resolved 'theme.css'
  $cssText = ''
  if (Test-Path -LiteralPath $cssPath -PathType Leaf) { $cssText = [System.IO.File]::ReadAllText($cssPath) }
  $classification = $script:Zds2ImportProbe.classification
  $fingerprint = [string]$script:Zds2ImportProbe.fingerprint
  if (-not $classification) {
    $classification = Get-ZCodeThemeTargetClassification -CssText $cssText -SourceFormat $SourceFormat `
      -DeclaredBy $(if ($SourceFormat) { 'request' } else { 'none' })
    try { $fingerprint = [string](Get-DreamSkinThemeSemanticFingerprint -ThemeDirectory $resolved) } catch { $fingerprint = '' }
  }
  $publishedFingerprint = ''
  try { $publishedFingerprint = [string](Get-DreamSkinThemeSemanticFingerprint -ThemeDirectory $resolved) } catch { $publishedFingerprint = '' }
  if ($fingerprint -and $publishedFingerprint -and ($fingerprint -cne $publishedFingerprint)) {
    # The bytes that were answered for are not the bytes that landed.
    return [pscustomobject]@{ ok = $false; data = $null; errorCode = 'IMPORT_CONTENT_CHANGED' }
  }
  $stored = Set-ZCodeThemeTargetRecord -StateRoot $StateRoot -Leaf $leaf -Fingerprint $fingerprint -Classification $classification
  if (-not [bool]$stored.ok) {
    return [pscustomobject]@{ ok = $false; data = $null; errorCode = [string]$stored.errorCode }
  }
  return [pscustomobject]@{
    ok   = $true
    data = [pscustomobject]@{
      themeId          = (Get-ZCodeThemeCardId -Kind 'saved' -Key $leaf)
      targetCompatible = [bool]$classification.targetCompatible
      targetReason     = [string]$classification.reason
      savedLeaf        = $leaf
    }
    errorCode = $null
  }
}

function Save-ZCodeAppearanceCurrentTheme {
  param([Parameter(Mandatory = $true)][string]$StateRoot, [Parameter(Mandatory = $true)][string]$Name)
  try {
    $saved = Save-DreamSkinCurrentTheme -Name $Name -StateRoot $StateRoot
  } catch {
    return [pscustomobject]@{ ok = $false; data = $null; errorCode = 'SAVE_REJECTED' }
  }
  $leaf = ''
  if ($saved -and $saved.PSObject.Properties['Directory']) {
    $leaf = [System.IO.Path]::GetFileName([string]$saved.Directory)
  }
  return [pscustomobject]@{
    ok        = $true
    data      = [pscustomobject]@{ themeId = $(if ($leaf) { Get-ZCodeThemeCardId -Kind 'saved' -Key $leaf } else { '' }); targetCompatible = $true }
    errorCode = $null
  }
}

function New-ZCodeAppearanceDraft {
  <#
  Choosing a background is an edit, not an apply. The chosen image is validated and
  copied into its own draft directory beside a pending-artwork.json that remembers
  which reference it was made from; the working theme and every confirmed snapshot
  stay untouched until the user presses apply.
  #>
  param([Parameter(Mandatory = $true)][string]$StateRoot, [Parameter(Mandatory = $true)][string]$ImagePath)
  if (-not [System.IO.Path]::IsPathRooted($ImagePath) -or -not (Test-Path -LiteralPath $ImagePath -PathType Leaf)) {
    return [pscustomobject]@{ ok = $false; data = $null; errorCode = 'IMAGE_NOT_FOUND' }
  }
  try {
    Assert-DreamSkinImageFile -Path $ImagePath
  } catch {
    return [pscustomobject]@{ ok = $false; data = $null; errorCode = 'IMAGE_REJECTED' }
  }
  $draftId = [guid]::NewGuid().ToString('N')
  $directory = Join-Path (Get-ZCodeAppearanceDraftRoot -StateRoot $StateRoot) $draftId
  $null = [System.IO.Directory]::CreateDirectory($directory)
  $extension = [System.IO.Path]::GetExtension($ImagePath).ToLowerInvariant()
  $imageTarget = Join-Path $directory ('draft' + $extension)
  Copy-Item -LiteralPath $ImagePath -Destination $imageTarget -Force
  if ((Get-ZCodeFileSha256 -Path $ImagePath) -cne (Get-ZCodeFileSha256 -Path $imageTarget)) {
    return [pscustomobject]@{ ok = $false; data = $null; errorCode = 'DRAFT_COPY_MISMATCH' }
  }
  $base = $null
  try { $base = Read-DreamSkinTheme -ThemeDirectory (Join-Path $StateRoot 'active-theme') } catch {}
  $originalRef = $null
  $originalFingerprint = ''
  if ($base) {
    $originalFingerprint = Get-DreamSkinThemeSemanticFingerprint -ThemeDirectory $base.Directory
    $originalRef = [pscustomobject]@{ kind = 'snapshot'; key = ''; fingerprint = $originalFingerprint }
  }
  $pending = [ordered]@{
    schemaVersion       = 'zcode-dream-skin-draft/1'
    draftId             = $draftId
    image               = ('draft' + $extension)
    originalFingerprint = [string]$originalFingerprint
    createdAtUtc        = (Get-Date).ToUniversalTime().ToString('o')
  }
  [System.IO.File]::WriteAllText((Join-Path $directory 'pending-artwork.json'), (ConvertTo-Json $pending -Depth 5), [System.Text.UTF8Encoding]::new($false))
  return [pscustomobject]@{ ok = $true; data = [pscustomobject]@{ draftId = $draftId }; errorCode = $null }
}

function Resolve-ZCodeAppearanceDraft {
  <#
  Applying a draft only succeeds while the theme it was made from is still the one on
  disk. If the user switched skins in the meantime the draft is refused with
  THEME_CHANGED and kept on disk: the draft is never silently re-based onto a
  different skin, and never deleted as a side effect of a refusal.
  #>
  param([Parameter(Mandatory = $true)][string]$StateRoot, [Parameter(Mandatory = $true)][string]$DraftId)
  if ($DraftId -cnotmatch '^[0-9a-f]{32}$') {
    return [pscustomobject]@{ ok = $false; themeRef = $null; errorCode = 'DRAFT_NOT_FOUND' }
  }
  $directory = Join-Path (Get-ZCodeAppearanceDraftRoot -StateRoot $StateRoot) $DraftId
  $pendingPath = Join-Path $directory 'pending-artwork.json'
  if (-not (Test-Path -LiteralPath $pendingPath -PathType Leaf)) {
    return [pscustomobject]@{ ok = $false; themeRef = $null; errorCode = 'DRAFT_NOT_FOUND' }
  }
  $pending = ConvertFrom-Json ([System.IO.File]::ReadAllText($pendingPath))
  $activeDirectory = Join-Path $StateRoot 'active-theme'
  $currentFingerprint = ''
  try { $currentFingerprint = Get-DreamSkinThemeSemanticFingerprint -ThemeDirectory $activeDirectory } catch {}
  if ($currentFingerprint -cne [string]$pending.originalFingerprint) {
    return [pscustomobject]@{ ok = $false; themeRef = $null; errorCode = 'THEME_CHANGED' }
  }
  $imagePath = Join-Path $directory ([string]$pending.image)
  if (-not (Test-Path -LiteralPath $imagePath -PathType Leaf)) {
    return [pscustomobject]@{ ok = $false; themeRef = $null; errorCode = 'DRAFT_IMAGE_MISSING' }
  }
  try {
    $null = Set-DreamSkinActiveThemeImage -ImagePath $imagePath -StateRoot $StateRoot
  } catch {
    return [pscustomobject]@{ ok = $false; themeRef = $null; errorCode = 'THEME_SELECT_FAILED' }
  }
  return [pscustomobject]@{
    ok       = $true
    themeRef = [pscustomobject]@{ kind = 'snapshot'; key = ''; fingerprint = '' }
    directory = $activeDirectory
    errorCode = $null
  }
}

function New-ZCodePersonalSkin {
  <#
  The fourth skin, from the artwork the user just chose. This is a library write and
  nothing else: it resolves the draft the gallery named (or, when no draft is named, the
  artwork the working theme already references), hands it to the same seeder the shipped
  presets use, and reports what the library now holds. It never selects, never applies,
  never writes the preference, and never edits the working theme - a skin somebody
  generated but did not ask for must not be on the screen.
  #>
  param([Parameter(Mandatory = $true)][string]$StateRoot, $Request)
  $root = Get-ZCodeDreamSkinStateRoot -StateRoot $StateRoot
  $names = @($Request.PSObject.Properties | ForEach-Object { [string]$_.Name })
  $art = $null
  if (($names -contains 'artFocusX') -or ($names -contains 'artFocusY') -or ($names -contains 'artDim')) {
    $art = [pscustomobject]@{
      focusX = [double]$Request.artFocusX
      focusY = [double]$Request.artFocusY
      dim    = [double]$Request.artDim
    }
  }
  $imagePath = ''
  $draftId = [string]$Request.draftId
  if ($draftId) {
    $directory = Join-Path (Get-ZCodeAppearanceDraftRoot -StateRoot $root) $draftId
    $pendingPath = Join-Path $directory 'pending-artwork.json'
    if (-not (Test-Path -LiteralPath $pendingPath -PathType Leaf)) {
      return [pscustomobject]@{ ok = $false; data = $null; errorCode = 'DRAFT_NOT_FOUND' }
    }
    try { $pendingImage = [string](ConvertFrom-Json ([System.IO.File]::ReadAllText($pendingPath))).image } catch {
      return [pscustomobject]@{ ok = $false; data = $null; errorCode = 'DRAFT_NOT_FOUND' }
    }
    $imagePath = Join-Path $directory $pendingImage
    if (-not (Test-Path -LiteralPath $imagePath -PathType Leaf)) {
      return [pscustomobject]@{ ok = $false; data = $null; errorCode = 'DRAFT_IMAGE_MISSING' }
    }
  }
  # The seeder publishes through the same shared import lock the ZIP entry uses, and it
  # answers a held lock by throwing. This is the boundary that owes the door a result, so
  # the refusal is turned into the same BUSY answer here instead of being left to bubble
  # out of the product as an unclassified exception.
  try {
    $seeded = Seed-ZCodePersonalPreset -StateRoot $root -ImagePath $imagePath -Art $art
  } catch {
    $why = ("$($_.Exception.Message)" -replace '\s+', ' ')
    if (Test-DreamSkinImportLockBusy $why) {
      return [pscustomobject]@{ ok = $false; data = $null; errorCode = 'BUSY'; errorDetail = $why }
    }
    throw
  }
  if (-not [bool]$seeded.ok) {
    $code = [string]$seeded.errorCode
    if (-not $code) { $code = 'PERSONAL_SKIN_PUBLISH_FAILED' }
    return [pscustomobject]@{ ok = $false; data = $null; errorCode = $code }
  }
  $leaf = ''
  if (@($seeded.seeded).Count -ge 1) { $leaf = [string]@($seeded.seeded)[0].savedLeaf }
  elseif (@($seeded.reused).Count -ge 1) { $leaf = [string]@($seeded.reused)[0].savedLeaf }
  $registry = Read-ZCodePresetRegistry -StateRoot $root
  $entry = @()
  if ([string]$registry.status -ceq 'valid') {
    $entry = @($registry.entries | Where-Object { [string]$_.publicPresetId -ceq 'zds2-character' })
  }
  $cards = @(Get-ZCodeThemeCatalog -StateRoot $root).cards
  return [pscustomobject]@{
    ok = $true
    data = [pscustomobject]@{
      savedLeaf      = $leaf
      themeId        = (Get-ZCodeThemeCardId -Kind 'saved' -Key $leaf)
      characterState = (Get-ZCodeCharacterStateFromCards -Cards $cards)
      sourceSha256   = [string]@($entry)[0].sourceSha256
      rebuilt        = (@($seeded.seeded).Count -gt 0)
    }
    errorCode = $null
  }
}

function Select-ZCodeNativeAppearance {
  <#
  Produces the theme-directory view of the current working theme so a snapshot can be
  taken of "what the user is looking at right now", including a skin that was never
  saved. Read-only.
  #>
  param([Parameter(Mandatory = $true)][string]$StateRoot)
  $directory = Join-Path $StateRoot 'active-theme'
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
    return [pscustomobject]@{ ok = $false; directory = ''; errorCode = 'THEME_NOT_FOUND' }
  }
  try {
    $loaded = Read-DreamSkinTheme -ThemeDirectory $directory
    return [pscustomobject]@{ ok = $true; directory = $loaded.Directory; errorCode = $null }
  } catch {
    return [pscustomobject]@{ ok = $false; directory = $directory; errorCode = 'THEME_UNREADABLE' }
  }
}

function Get-ZCodeThemeDeclarationPath {
  param([Parameter(Mandatory = $true)][string]$StateRoot)
  # Outside every theme directory, so the three-file package contract and the bytes
  # of an existing private library stay untouched.
  return (Join-Path (Get-ZCodeDreamSkinStateRoot -StateRoot $StateRoot) 'theme-declarations.json')
}

function Read-ZCodeThemeDeclarations {
  <#
  Three states, never a bare null: absent (no file yet, which is normal), ok, or
  invalid (a file that exists but cannot be trusted). A caller that treats absent as
  invalid refuses its own first write, and one that treats invalid as absent silently
  rewrites somebody's damaged record.
  #>
  param([Parameter(Mandatory = $true)][string]$StateRoot)
  $path = Get-ZCodeThemeDeclarationPath -StateRoot $StateRoot
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    return [pscustomobject]@{ status = 'absent'; entries = @() }
  }
  $item = Get-Item -LiteralPath $path
  if ($item.Length -gt 65536) { return [pscustomobject]@{ status = 'invalid'; entries = @() } }
  $doc = $null
  try { $doc = ConvertFrom-Json ([System.IO.File]::ReadAllText($path)) } catch {
    return [pscustomobject]@{ status = 'invalid'; entries = @() }
  }
  if (-not $doc -or [string]$doc.schemaVersion -cne 'zcode-dream-skin-declarations/1') {
    return [pscustomobject]@{ status = 'invalid'; entries = @() }
  }
  return [pscustomobject]@{ status = 'ok'; entries = @($doc.entries | Where-Object { $null -ne $_ }) }
}

function Set-ZCodeThemeTargetRecord {
  <#
  Records only what a caller declared about a saved leaf: the artwork unit it arrived
  in, plus the content fingerprint that was current when it was judged. The verdict
  itself is never stored, because the stylesheet can be replaced under the same leaf.
  #>
  param(
    [Parameter(Mandatory = $true)][string]$StateRoot,
    [Parameter(Mandatory = $true)][string]$Leaf,
    [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Fingerprint,
    [Parameter(Mandatory = $true)]$Classification
  )
  $root = Get-ZCodeDreamSkinStateRoot -StateRoot $StateRoot
  $path = Get-ZCodeThemeDeclarationPath -StateRoot $root
  $existing = Read-ZCodeThemeDeclarations -StateRoot $root
  if ($existing.status -eq 'invalid') {
    return [pscustomobject]@{ ok = $false; errorCode = 'DECLARATIONS_INVALID' }
  }
  $entries = @($existing.entries | Where-Object { [string]$_.savedLeaf -cne $Leaf })
  $entries += [pscustomobject]@{
    savedLeaf = $Leaf; sourceFormat = [string]$Classification.sourceFormat;
    declaredBy = [string]$Classification.declaredBy; sourceFingerprint = [string]$Fingerprint
  }
  $document = [ordered]@{ schemaVersion = 'zcode-dream-skin-declarations/1'; entries = @($entries) }
  $temp = Join-Path $root ('theme-declarations.tmp-' + [guid]::NewGuid().ToString('N'))
  try {
    [System.IO.File]::WriteAllText($temp, ($document | ConvertTo-Json -Depth 6),
      (New-Object System.Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $temp -Destination $path -Force
  } catch {
    if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
    return [pscustomobject]@{ ok = $false; errorCode = 'DECLARATIONS_WRITE_FAILED' }
  }
  return [pscustomobject]@{ ok = $true; errorCode = $null }
}

function Get-ZCodeThemeDeclaration {
  param([Parameter(Mandatory = $true)][string]$StateRoot, [Parameter(Mandatory = $true)][string]$Leaf)
  $read = Read-ZCodeThemeDeclarations -StateRoot $StateRoot
  if ($read.status -ne 'ok') { return $null }
  $entry = @($read.entries | Where-Object { [string]$_.savedLeaf -ceq $Leaf } | Select-Object -First 1)
  if ($entry.Count -eq 0) { return $null }
  return $entry[0]
}
