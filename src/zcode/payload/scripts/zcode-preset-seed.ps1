<#
ZCode Dream Skin 2.0 public preset seeding.

A distributed preset must arrive through the same door a user's own ZIP does: the
package validator, the image gate and the Safe CSS policy all run, and the atomic
publish rules decide what happens to a colliding name. Copying directories into the
library by hand would skip exactly the checks that make a theme safe to apply.

The seed registry lives beside the library, never inside a theme package, because the
shipped three-file contract allows no extra member - and it is what lets a later
selection state which unit the artwork was authored in.
#>

$script:ZCodePresetOriginSchema = 'zcode-dream-skin-preset-origin/1'
# The fourth skin has one identity in every register; a second constant would be a second
# answer to the same question.
$script:ZCodePersonalPresetId = 'zds2-character'

function Get-ZCodePresetRegistryPath {
  param([Parameter(Mandatory = $true)][string]$StateRoot)
  return Join-Path (Get-ZCodeDreamSkinStateRoot -StateRoot $StateRoot) 'preset-origin.json'
}

function Read-ZCodePresetRegistry {
  param([Parameter(Mandatory = $true)][string]$StateRoot)
  $path = Get-ZCodePresetRegistryPath -StateRoot $StateRoot
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    return [pscustomobject]@{ status = 'absent'; entries = @(); errorCode = $null }
  }
  $item = Get-Item -LiteralPath $path
  if ($item.Length -gt 65536) {
    return [pscustomobject]@{ status = 'invalid'; entries = @(); errorCode = 'PRESET_ORIGIN_TOO_LARGE' }
  }
  try {
    $parsed = ConvertFrom-Json ([System.IO.File]::ReadAllText($path))
  } catch {
    return [pscustomobject]@{ status = 'invalid'; entries = @(); errorCode = 'PRESET_ORIGIN_MALFORMED_JSON' }
  }
  if (-not $parsed -or [string]$parsed.schemaVersion -cne $script:ZCodePresetOriginSchema) {
    return [pscustomobject]@{ status = 'invalid'; entries = @(); errorCode = 'PRESET_ORIGIN_SCHEMA_INVALID' }
  }
  return [pscustomobject]@{ status = 'valid'; entries = @($parsed.entries); errorCode = $null }
}

function Write-ZCodePresetRegistry {
  param(
    [Parameter(Mandatory = $true)][string]$StateRoot,
    [Parameter(Mandatory = $true)][object[]]$Entries
  )
  $path = Get-ZCodePresetRegistryPath -StateRoot $StateRoot
  $body = [ordered]@{
    schemaVersion = $script:ZCodePresetOriginSchema
    entries       = @($Entries | ForEach-Object { [ordered]@{
      savedLeaf        = [string]$_.savedLeaf
      publicPresetId   = [string]$_.publicPresetId
      sourceFingerprint = [string]$_.sourceFingerprint
      artSourceFormat  = [string]$_.artSourceFormat
      # Additive: an older reader ignores it and a newer one refuses to reuse a personal
      # skin whose source bytes it cannot name.
      sourceSha256     = [string]$_.sourceSha256
      artTuning        = [string]$_.artTuning
    } })
  }
  $json = ConvertTo-Json $body -Depth 5
  if ([System.Text.Encoding]::UTF8.GetByteCount($json) -gt 65536) {
    throw 'PRESET_ORIGIN_TOO_LARGE: the seed registry exceeded 64 KiB'
  }
  $temp = "$path.tmp-$([guid]::NewGuid().ToString('N'))"
  try {
    [System.IO.File]::WriteAllText($temp, $json, [System.Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temp -Destination $path -Force
  } finally {
    if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
  }
  return $path
}

function Read-ZCodePresetCatalog {
  param([Parameter(Mandatory = $true)][string]$PresetRoot)
  $path = Join-Path $PresetRoot 'catalog.json'
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    throw "PRESET_CATALOG_MISSING: no catalog.json under $PresetRoot"
  }
  $item = Get-Item -LiteralPath $path
  if ($item.Length -gt 65536) { throw 'PRESET_CATALOG_TOO_LARGE' }
  try { $catalog = ConvertFrom-Json ([System.IO.File]::ReadAllText($path)) } catch { throw 'PRESET_CATALOG_MALFORMED_JSON' }
  if (-not $catalog -or [string]$catalog.schemaVersion -cne 'zcode-dream-skin-preset-catalog/1') {
    throw 'PRESET_CATALOG_SCHEMA_INVALID'
  }
  return $catalog
}

function New-ZCodePresetArchive {
  # A preset is handed to the importer as an ordinary ZIP, so every package rule
  # applies to our own shipped content as well.
  param(
    [Parameter(Mandatory = $true)][string]$SourceDirectory,
    [Parameter(Mandatory = $true)][string]$ArchivePath
  )
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  if (Test-Path -LiteralPath $ArchivePath) { Remove-Item -LiteralPath $ArchivePath -Force }
  $null = [System.IO.Compression.ZipFile]::CreateFromDirectory($SourceDirectory, $ArchivePath)
  return $ArchivePath
}

function Seed-ZCodePublicPresets {
  <#
  Idempotent by content, never by name: a preset that is already in the library
  byte-for-byte is reused, and a private theme that happens to carry the same
  metadata id is left alone because the importer itself refuses to overwrite
  unrelated content. Nothing here selects or applies a theme: seeding must not be
  able to change what the user is looking at.
  #>
  param(
    [Parameter(Mandatory = $true)][string]$StateRoot,
    [Parameter(Mandatory = $true)][string]$PresetRoot,
    [string]$WorkRoot = ''
  )
  $root = Get-ZCodeDreamSkinStateRoot -StateRoot $StateRoot
  $catalog = Read-ZCodePresetCatalog -PresetRoot $PresetRoot
  $publicEntries = @($catalog.presets | Where-Object { [string]$_.kind -eq 'public' })
  if ($publicEntries.Count -eq 0) {
    return [pscustomobject]@{ ok = $true; seeded = @(); reused = @(); skipped = @(); errorCode = $null }
  }
  $registryRead = Read-ZCodePresetRegistry -StateRoot $root
  $registry = @()
  if ($registryRead.status -eq 'valid') { $registry = @($registryRead.entries) }
  elseif ($registryRead.status -eq 'invalid') {
    # A damaged registry must not be silently replaced: report it and refuse, so the
    # reason a preset does not declare its unit stays visible instead of looking like
    # an intentional choice.
    return [pscustomobject]@{ ok = $false; seeded = @(); reused = @(); skipped = @(); errorCode = $registryRead.errorCode }
  }
  $work = if ($WorkRoot) { $WorkRoot } else { Join-Path $root ('.preset-seed-' + [guid]::NewGuid().ToString('N')) }
  $null = [System.IO.Directory]::CreateDirectory($work)
  $seeded = @()
  $reused = @()
  try {
    foreach ($entry in $publicEntries) {
      $sourceDirectory = Join-Path $PresetRoot ([string]$entry.directory)
      if (-not (Test-Path -LiteralPath $sourceDirectory -PathType Container)) {
        return [pscustomobject]@{ ok = $false; seeded = $seeded; reused = $reused; skipped = @(); errorCode = 'PRESET_SOURCE_MISSING' }
      }
      $fingerprint = Get-DreamSkinThemeSemanticFingerprint -ThemeDirectory $sourceDirectory
      # Reuse is decided by content first and identity second. A scalar object has no
      # reliable .Count, so the presence test is an explicit null check rather than a
      # count comparison that silently reads as "not found" and re-imports everything.
      $already = $null
      foreach ($candidate in @($registry)) {
        $leafPath = Join-Path (Join-Path $root 'themes') ([string]$candidate.savedLeaf)
        $sameContent = ([string]$candidate.sourceFingerprint -ceq $fingerprint)
        $samePreset = (([string]$candidate.publicPresetId -ceq [string]$entry.id) -and (Test-Path -LiteralPath $leafPath -PathType Container))
        if ($sameContent -or $samePreset) { $already = $candidate; break }
      }
      # A saved leaf that carries this preset's id but different bytes belongs to the
      # user, not to us: the importer updates an id in place, so clashing content has
      # to be routed around instead of straight in.
      $namesake = Join-Path (Join-Path $root 'themes') ([string]$entry.id)
      $collision = $false
      if (Test-Path -LiteralPath $namesake -PathType Container) {
        try {
          $namesakeFingerprint = Get-DreamSkinThemeSemanticFingerprint -ThemeDirectory $namesake
          $collision = ($namesakeFingerprint -cne $fingerprint)
        } catch {
          $collision = $true
        }
      }

      if ($null -ne $already) {
        if (-not (Test-Path -LiteralPath (Join-Path (Join-Path $root 'themes') ([string]$already.savedLeaf)) -PathType Container)) {
          return [pscustomobject]@{ ok = $false; seeded = $seeded; reused = $reused; skipped = @(); errorCode = 'PRESET_ORIGIN_ENTRY_STALE' }
        }
        $reused += [pscustomobject]@{ publicPresetId = [string]$entry.id; savedLeaf = [string]$already.savedLeaf }
        continue
      }
      $archive = New-ZCodePresetArchive -SourceDirectory $sourceDirectory -ArchivePath (Join-Path $work ("$([string]$entry.id).zip"))
      $imported = $null
      if ($collision) {
        # The importer updates an id in place, which is right for a new version of the
        # same theme and wrong here: the private library entry that merely happens to
        # carry this id is somebody's work. Ship a distinct tool id derived from the
        # source content instead, so both survive and neither is rewritten.
        $toolId = [string]$entry.id + '-' + $fingerprint.Substring(0, 8)
        $staged = Join-Path $work $toolId
        Copy-ZCodePresetDirectory -Source $sourceDirectory -Destination $staged -NewId $toolId
        $toolFingerprint = Get-DreamSkinThemeSemanticFingerprint -ThemeDirectory $staged
        $existingTool = @($registry | Where-Object {
          ([string]$_.publicPresetId -ceq [string]$entry.id) -and ([string]$_.sourceFingerprint -ceq $toolFingerprint)
        })
        if ($existingTool.Count -gt 0 -and
            (Test-Path -LiteralPath (Join-Path (Join-Path $root 'themes') ([string]$existingTool[0].savedLeaf)) -PathType Container)) {
          $reused += [pscustomobject]@{ publicPresetId = [string]$entry.id; savedLeaf = [string]$existingTool[0].savedLeaf }
          continue
        }
        $fingerprint = [string]$toolFingerprint
        $archive = New-ZCodePresetArchive -SourceDirectory $staged -ArchivePath (Join-Path $work "$toolId.zip")
        $imported = Import-DreamSkinThemeZip -ArchivePath $archive -StateRoot $root
      } else {
        $imported = Import-DreamSkinThemeZip -ArchivePath $archive -StateRoot $root
      }
      $leaf = [string]$imported.Id
      $registry = @($registry | Where-Object { [string]$_.publicPresetId -cne [string]$entry.id })
      $registry += [pscustomobject]@{
        savedLeaf         = $leaf
        publicPresetId    = [string]$entry.id
        sourceFingerprint = [string]$fingerprint
        artSourceFormat   = 'dream-skin-v1-normalized'
      }
      $seeded += [pscustomobject]@{ publicPresetId = [string]$entry.id; savedLeaf = $leaf; fingerprint = [string]$fingerprint }
    }
    $null = Write-ZCodePresetRegistry -StateRoot $root -Entries $registry
    return [pscustomobject]@{ ok = $true; seeded = $seeded; reused = $reused; skipped = @(); errorCode = $null }
  } finally {
    if ($work -and (Test-Path -LiteralPath $work)) {
      Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }
  }
}

function Copy-ZCodePresetDirectory {
  # Stages a preset under a different metadata id. Only the id changes: the image
  # bytes and the stylesheet are carried over untouched so the content fingerprint
  # still describes the shipped artwork.
  param(
    [Parameter(Mandatory = $true)][string]$Source,
    [Parameter(Mandatory = $true)][string]$Destination,
    [Parameter(Mandatory = $true)][string]$NewId
  )
  if (Test-Path -LiteralPath $Destination) { Remove-Item -LiteralPath $Destination -Recurse -Force }
  $null = [System.IO.Directory]::CreateDirectory($Destination)
  foreach ($file in @(Get-ChildItem -LiteralPath $Source -File)) {
    Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $Destination $file.Name) -Force
  }
  $themePath = Join-Path $Destination 'theme.json'
  $theme = Get-Content -LiteralPath $themePath -Raw | ConvertFrom-Json
  $theme.id = $NewId
  [System.IO.File]::WriteAllText($themePath, (ConvertTo-Json $theme -Depth 8), (New-Object System.Text.UTF8Encoding($false)))
  return $Destination
}

function Get-ZCodePersonalSourceImage {
  <#
  The personal skin may only be built from the image the live active theme already
  references, copied whole. A spare tuning image on the desktop is not the artwork the
  user chose, and a missing reference is reported instead of being substituted.
  #>
  param([Parameter(Mandatory = $true)][string]$StateRoot)
  $root = Get-ZCodeDreamSkinStateRoot -StateRoot $StateRoot
  $active = Join-Path $root 'active-theme'
  $themePath = Join-Path $active 'theme.json'
  $refusal = { param($code) return [pscustomobject]@{ ok = $false; imagePath = ''; errorCode = $code } }
  if (-not (Test-Path -LiteralPath $themePath -PathType Leaf)) {
    return [pscustomobject]@{ ok = $false; imagePath = ''; errorCode = 'PERSONAL_SOURCE_THEME_MISSING' }
  }
  $referenced = ''
  try { $referenced = [string](Get-Content -LiteralPath $themePath -Raw | ConvertFrom-Json).image } catch {
    return [pscustomobject]@{ ok = $false; imagePath = ''; errorCode = 'PERSONAL_SOURCE_THEME_MALFORMED' }
  }
  $isLeafOnly = ($referenced -and $referenced -ne '.' -and $referenced -ne '..' -and
    ([System.IO.Path]::GetFileName($referenced) -ceq $referenced) -and
    (-not $referenced.Contains(':')))
  if (-not $isLeafOnly) {
    return [pscustomobject]@{ ok = $false; imagePath = ''; errorCode = 'PERSONAL_SOURCE_IMAGE_INVALID' }
  }
  $imagePath = Join-Path $active $referenced
  if (-not (Test-Path -LiteralPath $imagePath -PathType Leaf)) {
    return [pscustomobject]@{ ok = $false; imagePath = ''; errorCode = 'PERSONAL_SOURCE_IMAGE_MISSING' }
  }
  return [pscustomobject]@{ ok = $true; imagePath = $imagePath; errorCode = $null }
}

function Seed-ZCodePersonalPreset {
  <#
  Builds the fourth skin from the user's own referenced artwork and hands it to the
  private library through the same importer the shipped presets use. Seeding never
  selects or applies anything: a seed that repainted the window would change the
  appearance nobody asked to change. The built artwork carries focus in 0..1, so the
  origin this function records is the normalised unit, never a guessed percentage.
  #>
  param(
    [Parameter(Mandatory = $true)][string]$StateRoot,
    [string]$NodePath = '',
    [string]$BuilderPath = '',
    [string]$WorkRoot = '',
    [string]$ImagePath = '',
    $Art = $null
  )
  $root = Get-ZCodeDreamSkinStateRoot -StateRoot $StateRoot
  if ($ImagePath) {
    # An explicitly named artwork is how the gallery builds from the draft the user just
    # chose. Falling back to the working theme would mean a skin had to be applied before
    # anybody could generate one, and the working theme is not this call's to touch.
    if (-not [System.IO.Path]::IsPathRooted($ImagePath) -or
      -not (Test-Path -LiteralPath $ImagePath -PathType Leaf)) {
      return [pscustomobject]@{ ok = $false; seeded = @(); reused = @(); errorCode = 'PERSONAL_SOURCE_IMAGE_INVALID' }
    }
    try { Assert-DreamSkinImageFile -Path $ImagePath } catch {
      return [pscustomobject]@{ ok = $false; seeded = @(); reused = @(); errorCode = 'PERSONAL_IMAGE_REJECTED' }
    }
    $source = [pscustomobject]@{ ok = $true; imagePath = [System.IO.Path]::GetFullPath($ImagePath); errorCode = $null }
  } else {
    $source = Get-ZCodePersonalSourceImage -StateRoot $root
  }
  if (-not $source.ok) {
    return [pscustomobject]@{ ok = $false; seeded = @(); reused = @(); errorCode = $source.errorCode }
  }
  if (-not $NodePath) { $NodePath = (Get-DreamSkinNodeRuntime -MinimumMajor 22).Path }
  if (-not $BuilderPath) { $BuilderPath = Join-Path $PSScriptRoot '..\tools\build-zcode-presets.mjs' }
  $BuilderPath = [System.IO.Path]::GetFullPath($BuilderPath)
  if (-not (Test-Path -LiteralPath $BuilderPath -PathType Leaf)) {
    return [pscustomobject]@{ ok = $false; seeded = @(); reused = @(); errorCode = 'PERSONAL_BUILDER_MISSING' }
  }
  $registryRead = Read-ZCodePresetRegistry -StateRoot $root
  $registry = @()
  if ($registryRead.status -eq 'valid') { $registry = @($registryRead.entries) }
  elseif ($registryRead.status -eq 'invalid') {
    return [pscustomobject]@{ ok = $false; seeded = @(); reused = @(); errorCode = $registryRead.errorCode }
  }
  $sourceSha = [string](Get-FileHash -LiteralPath $source.imagePath -Algorithm SHA256).Hash.ToLowerInvariant()
  # Reuse is keyed on the picture and the composition together: the same artwork with a
  # different focus or veil is a different skin, and a slider that only took effect after
  # a restart would be indistinguishable from a broken one.
  $tuningKey = ''
  if ($Art) { $tuningKey = ('{0}/{1}/{2}' -f [string]$Art.focusX, [string]$Art.focusY, [string]$Art.dim) }
  $already = @($registry | Where-Object { [string]$_.publicPresetId -ceq $script:ZCodePersonalPresetId }) | Select-Object -First 1
  if ($already) {
    $existingLeaf = Join-Path (Join-Path $root 'themes') ([string]$already.savedLeaf)
    # Reuse is a statement about bytes, not about a name having been seen once: an
    # artwork that changed underneath has to rebuild, and a record written before digests
    # existed is unknown provenance, which is treated as changed rather than guessed.
    if ((Test-Path -LiteralPath $existingLeaf -PathType Container) -and [string]$already.sourceSha256 -ceq $sourceSha -and
      [string]$already.artTuning -ceq $tuningKey) {
      $reusedEntry = [pscustomobject]@{ publicPresetId = $script:ZCodePersonalPresetId; savedLeaf = [string]$already.savedLeaf }
      return [pscustomobject]@{ ok = $true; seeded = @(); reused = @($reusedEntry); errorCode = $null }
    }
  }
  $work = if ($WorkRoot) { $WorkRoot } else { Join-Path $root ('.personal-seed-' + [guid]::NewGuid().ToString('N')) }
  $built = Join-Path $work 'built'
  try {
    $null = [System.IO.Directory]::CreateDirectory($work)
    # Personal only: the shipped presets were composed at build time, and redrawing them
    # on every skin change would make one click do unbounded work on a user's machine.
    $buildOutput = @(& $NodePath $BuilderPath '--output' $built '--personal-image' $source.imagePath '--personal-only' 2>&1)
    if ($LASTEXITCODE -ne 0) {
      $detail = (($buildOutput | Select-Object -First 2) -join ' ')
      $code = 'PERSONAL_BUILD_FAILED_EXIT' + $LASTEXITCODE
      return [pscustomobject]@{ ok = $false; seeded = @(); reused = @(); errorCode = ($code + ':' + $detail) }
    }
    $catalog = Read-ZCodePresetCatalog -PresetRoot $built
    $personalEntries = @($catalog.presets | Where-Object { [string]$_.kind -eq 'personal' })
    if ($personalEntries.Count -ne 1) {
      return [pscustomobject]@{ ok = $false; seeded = @(); reused = @(); errorCode = 'PERSONAL_ENTRY_MISSING' }
    }
    $entry = $personalEntries[0]
    $sourceDirectory = Join-Path $built ([string]$entry.directory)
    if (-not (Test-Path -LiteralPath $sourceDirectory -PathType Container)) {
      return [pscustomobject]@{ ok = $false; seeded = @(); reused = @(); errorCode = 'PRESET_SOURCE_MISSING' }
    }
    # The composition the person set goes into the generated theme before anything is
    # fingerprinted or published, so the fingerprint, the leaf and the payload all describe
    # the same skin. Focus stays a 0..1 ratio: that is the unit this artwork is authored in,
    # and the payload gate converts it once, on the way to the renderer.
    if ($Art) {
      $generatedThemePath = Join-Path $sourceDirectory 'theme.json'
      $generatedTheme = ConvertFrom-Json ([System.IO.File]::ReadAllText($generatedThemePath))
      $generatedTheme.art.focusX = [double]$Art.focusX
      $generatedTheme.art.focusY = [double]$Art.focusY
      $generatedTheme.art | Add-Member -NotePropertyName dim -NotePropertyValue ([double]$Art.dim) -Force
      [System.IO.File]::WriteAllText($generatedThemePath, (ConvertTo-Json $generatedTheme -Depth 8),
        (New-Object System.Text.UTF8Encoding($false)))
    }
    $fingerprint = Get-DreamSkinThemeSemanticFingerprint -ThemeDirectory $sourceDirectory
    if ([string]$entry.id -cne $script:ZCodePersonalPresetId) {
      # The reuse decision above is keyed by the constant; a generator that starts calling
      # the personal skin anything else has to fail here rather than duplicate silently.
      return [pscustomobject]@{ ok = $false; seeded = @(); reused = @(); errorCode = 'PERSONAL_ENTRY_ID_UNEXPECTED' }
    }
    $stagedDirectory = $sourceDirectory
    $namesake = Join-Path (Join-Path $root 'themes') ([string]$entry.id)
    if (Test-Path -LiteralPath $namesake -PathType Container) {
      $collision = $true
      try { $collision = ((Get-DreamSkinThemeSemanticFingerprint -ThemeDirectory $namesake) -cne $fingerprint) } catch { $collision = $true }
      if ($collision) {
        $toolId = [string]$entry.id + '-' + $fingerprint.Substring(0, 8)
        $stagedDirectory = Copy-ZCodePresetDirectory -Source $sourceDirectory -Destination (Join-Path $work $toolId) -NewId $toolId
        $fingerprint = Get-DreamSkinThemeSemanticFingerprint -ThemeDirectory $stagedDirectory
      }
    }
    $archiveName = [string]$entry.id + '.zip'
    $archive = New-ZCodePresetArchive -SourceDirectory $stagedDirectory -ArchivePath (Join-Path $work $archiveName)
    $imported = Import-DreamSkinThemeZip -ArchivePath $archive -StateRoot $root
    $leaf = [string]$imported.Id
    $registry = @($registry | Where-Object { [string]$_.publicPresetId -cne [string]$entry.id })
    $registry += [pscustomobject]@{
      savedLeaf = $leaf; publicPresetId = [string]$entry.id;
      sourceFingerprint = [string]$fingerprint; artSourceFormat = 'dream-skin-v1-normalized'
      sourceSha256 = $sourceSha
      artTuning = $tuningKey
    }
    $null = Write-ZCodePresetRegistry -StateRoot $root -Entries $registry
    $seededEntry = [pscustomobject]@{ publicPresetId = [string]$entry.id; savedLeaf = $leaf; fingerprint = [string]$fingerprint }
    return [pscustomobject]@{ ok = $true; seeded = @($seededEntry); reused = @(); errorCode = $null }
  } finally {
    if ($work -and (Test-Path -LiteralPath $work)) {
      Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }
  }
}
