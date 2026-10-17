<#
ZCode Dream Skin 2.0 read-only theme catalog.

The gallery and the tray need a list of what exists without anyone hoping that a
listing has no side effects: the existing store helpers initialise directories,
repair import journals and seed presets. This module only enumerates what is
already on disk and reports every problem as a machine code, so the broken theme a
user already owns stays visible as a disabled card instead of disappearing.

Card identity is an opaque SHA-256 over the reference, never a path: the renderer
can name a card, but it cannot name a directory.
#>

$script:ZCodeThemeCatalogKinds = @('saved', 'snapshot')
$script:ZCodeThemeNativeKey = 'native'

function Get-ZCodeThemeCatalogRoots {
  param([Parameter(Mandatory = $true)][string]$StateRoot)
  return [pscustomobject]@{
    saved     = Join-Path $StateRoot 'themes'
    snapshot  = Join-Path $StateRoot 'appearance-snapshots'
  }
}

function Get-ZCodeThemeCardId {
  <#
  Stable across processes, meaningless off-disk: UTF-8 bytes of
  "kind NUL key.ToLowerInvariant()" hashed with SHA-256. Two library directories
  that share a metadata id still get different card ids, because the leaf differs.
  #>
  param(
    [Parameter(Mandatory = $true)][ValidateSet('saved', 'snapshot', 'native')][string]$Kind,
    [Parameter(Mandatory = $true)][string]$Key
  )
  $normalized = "$Kind`0$($Key.ToLowerInvariant())"
  $hasher = [System.Security.Cryptography.SHA256]::Create()
  try {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($normalized)
    return ([System.BitConverter]::ToString($hasher.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
  } finally {
    $hasher.Dispose()
  }
}

function Get-ZCodeThemeDirectoryLeaf {
  # One directory level below the kind root and nothing else: no nesting, no
  # trailing dot or space Windows would silently strip, no reparse hop.
  param(
    [Parameter(Mandatory = $true)][string]$Key,
    [Parameter(Mandatory = $true)][string]$Kind
  )
  if ([string]::IsNullOrEmpty($Key)) { return $false }
  if ($Key -eq '.' -or $Key -eq '..') { return $false }
  if ($Key.Contains('/') -or $Key.Contains('\') -or $Key.Contains(':')) { return $false }
  foreach ($ch in $Key.ToCharArray()) {
    $code = [int]$ch
    if ($code -lt 32 -or $code -eq 127) { return $false }
  }
  if ($Key.EndsWith('.') -or $Key.EndsWith(' ')) { return $false }
  if ($Kind -eq 'snapshot' -and $Key -cnotmatch '^[0-9a-f]{32}$') { return $false }
  return $true
}

function Get-ZCodeCatalogChildDirectories {
  param([Parameter(Mandatory = $true)][string]$Root)
  if (-not (Test-Path -LiteralPath $Root -PathType Container)) { return @() }
  $rows = @()
  foreach ($item in @(Get-ChildItem -LiteralPath $Root -Directory -Force -ErrorAction SilentlyContinue)) {
    $rows += [pscustomobject]@{
      Key      = [string]$item.Name
      Path     = [string]$item.FullName
      Reparse  = [bool]($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint)
    }
  }
  return $rows
}

function Get-ZCodeSnapshotStalenessNote {
  <#
  Says when the snapshot in use is an earlier version of the saved theme it came from.
  The judgement compares the content fingerprint recorded in snapshot-info.json with the
  fingerprint the saved directory has now; a display name or metadata id survives edits,
  so neither may decide this. The wording lives in the tray text table: nothing here
  carries user-facing copy, and nothing is hidden - recovery needs every snapshot
  enumerable and resolvable, so a shorter gallery listing belongs to the gallery.
  #>
  param([Parameter(Mandatory = $true)][string]$StateRoot, [Parameter(Mandatory = $true)][string]$Key)
  if (-not (Get-Command Read-ZCodeAppearanceSnapshotInfo -ErrorAction SilentlyContinue)) { return '' }
  if (-not (Get-Command Get-ZCodeTrayText -ErrorAction SilentlyContinue)) { return '' }
  $info = $null
  try { $info = Read-ZCodeAppearanceSnapshotInfo -StateRoot $StateRoot -Key $Key } catch { return '' }
  if (-not $info -or ([string]$info.status -cne 'valid')) { return '' }
  $savedRef = [string]$info.info.sourceSavedRef
  $recorded = [string]$info.info.sourceFingerprint
  if (-not $savedRef) { return '' }
  $livePath = Join-Path (Get-ZCodeThemeCatalogRoots -StateRoot $StateRoot).saved $savedRef
  if (-not (Test-Path -LiteralPath $livePath -PathType Container)) { return (Get-ZCodeTrayText -Key 'SnapshotStaleMissing') }
  $live = ''
  try { $live = [string](Get-DreamSkinThemeSemanticFingerprint -ThemeDirectory $livePath) }
  catch { return (Get-ZCodeTrayText -Key 'SnapshotStaleUnreadable') }
  if ($recorded -and $live -and ($live -cne $recorded)) { return (Get-ZCodeTrayText -Key 'SnapshotStaleChanged') }
  return ''
}

function Get-ZCodeThemeCatalog {
  <#
  Read-only: enumerates <StateRoot>\themes and <StateRoot>\appearance-snapshots and
  returns one card per directory, enabled or disabled with a code. It never applies
  a theme, never writes state, never repairs anything, and never creates a snapshot.
  #>
  param([Parameter(Mandatory = $true)][string]$StateRoot)
  $roots = Get-ZCodeThemeCatalogRoots -StateRoot $StateRoot
  $cards = @()

  foreach ($kind in $script:ZCodeThemeCatalogKinds) {
    $kindRoot = if ($kind -eq 'saved') { $roots.saved } else { $roots.snapshot }
    foreach ($child in @(Get-ZCodeCatalogChildDirectories -Root $kindRoot)) {
      $leafOk = Get-ZCodeThemeDirectoryLeaf -Key $child.Key -Kind $kind
      if (-not $leafOk) {
        $cards += New-ZCodeThemeDisabledCard -Kind $kind -Key $child.Key -Code 'THEME_LEAF_REJECTED'
        continue
      }
      if ($child.Reparse) {
        $cards += New-ZCodeThemeDisabledCard -Kind $kind -Key $child.Key -Code 'THEME_DIRECTORY_REPARSE'
        continue
      }
      $entry = Read-ZCodeCatalogThemeDirectory -Kind $kind -Key $child.Key -Directory $child.Path -StateRoot $StateRoot
      if ($kind -eq 'snapshot') {
        $staleNote = Get-ZCodeSnapshotStalenessNote -StateRoot $StateRoot -Key $child.Key
        if ($staleNote) {
          $entry.description = (@([string]$entry.description, $staleNote) | Where-Object { $_ }) -join ' - '
        }
      }
      $cards += $entry
    }
  }

  $cards += [pscustomobject]@{
    themeId        = (Get-ZCodeThemeCardId -Kind 'native' -Key $script:ZCodeThemeNativeKey)
    kind           = 'native'
    key            = $script:ZCodeThemeNativeKey
    name           = 'Native appearance'
    description    = ''
    coverDataUrl   = $null
    enabled        = $true
    disabledReason = $null
    origin         = 'builtin'
    fingerprint    = ''
    revision       = ''
    directory      = ''
  }
  return [pscustomobject]@{
    stateRoot = $StateRoot
    cards     = @($cards)
  }
}

function New-ZCodeThemeDisabledCard {
  param([string]$Kind, [string]$Key, [string]$Code)
  return [pscustomobject]@{
    themeId        = (Get-ZCodeThemeCardId -Kind $Kind -Key $Key)
    kind           = $Kind
    key            = $Key
    name           = $Key
    description    = ''
    coverDataUrl   = $null
    enabled        = $false
    disabledReason = $Code
    origin         = $(if ($Kind -eq 'snapshot') { 'user' } else { 'user' })
    fingerprint    = ''
    revision       = ''
    directory      = ''
  }
}

function Read-ZCodeCatalogThemeDirectory {
  param([string]$Kind, [string]$Key, [string]$Directory)
  try {
    $loaded = Read-DreamSkinTheme -ThemeDirectory $Directory -SkipImageMetadata
    $fingerprint = Get-DreamSkinThemeSemanticFingerprint -ThemeDirectory $Directory
  } catch {
    $message = "$($_.Exception.Message)"
    $code = 'THEME_UNREADABLE'
    if ($message -like '*missing metadata*') { $code = 'THEME_METADATA_MISSING' }
    elseif ($message -like '*invalid JSON*') { $code = 'THEME_METADATA_INVALID_JSON' }
    elseif ($message -like '*relative image*') { $code = 'THEME_METADATA_NO_IMAGE_FIELD' }
    elseif ($message -like '*inside its theme directory*') { $code = 'THEME_IMAGE_ESCAPES_DIRECTORY' }
    elseif ($message -like '*reparse*') { $code = 'THEME_DIRECTORY_REPARSE' }
    return New-ZCodeThemeDisabledCard -Kind $Kind -Key $Key -Code $code
  }
  $theme = $loaded.Theme
  $name = "$($theme.name)"
  if (-not $name) { $name = $Key }
  # A saved package that targets nothing this window renders stays in the library
  # and is reported disabled: enabling it here and refusing it on apply would be two
  # different answers to one question.
  if ($Kind -eq 'saved' -and $StateRoot) {
    $verdict = Get-ZCodeSavedThemeTargetVerdict -StateRoot $StateRoot -Key $Key -Directory ([string]$loaded.Directory)
    if (-not [bool]$verdict.targetCompatible) {
      $disabled = New-ZCodeThemeDisabledCard -Kind $Kind -Key $Key -Code ([string]$verdict.reason)
      $disabled.name = $name
      $disabled.description = "$($theme.description)"
      $disabled.fingerprint = [string]$fingerprint
      $disabled.revision = "$($theme.id)"
      $disabled.directory = [string]$loaded.Directory
      return $disabled
    }
  }
  return [pscustomobject]@{
    themeId        = (Get-ZCodeThemeCardId -Kind $Kind -Key $Key)
    kind           = $Kind
    key            = $Key
    name           = $name
    description    = "$($theme.description)"
    coverDataUrl   = $null
    enabled        = $true
    disabledReason = $null
    origin         = 'user'
    fingerprint    = [string]$fingerprint
    revision       = "$($theme.id)"
    directory      = [string]$loaded.Directory
  }
}

function Resolve-ZCodeThemeRef {
  <#
  Turns a card id back into a reference, then re-proves it against the disk: a stale
  catalog (the user deleted or changed a theme while the gallery was open) must never
  turn into a write. The native card is intentionally unresolvable - it is an
  appearance state, not a directory.
  #>
  param(
    [Parameter(Mandatory = $true)][string]$StateRoot,
    [Parameter(Mandatory = $true)][string]$ThemeId,
    [Parameter(Mandatory = $true)]$Catalog
  )
  if ($ThemeId -cnotmatch '^[0-9a-f]{64}$') {
    return [pscustomobject]@{ ok = $false; themeRef = $null; errorCode = 'THEME_NOT_FOUND' }
  }
  $matches = @(@($Catalog.cards) | Where-Object { $_.themeId -ceq $ThemeId })
  if ($matches.Count -ne 1) {
    $code = if ($matches.Count -gt 1) { 'THEME_AMBIGUOUS' } else { 'THEME_NOT_FOUND' }
    return [pscustomobject]@{ ok = $false; themeRef = $null; errorCode = $code }
  }
  $card = $matches[0]
  if ($card.kind -ceq 'native') {
    return [pscustomobject]@{ ok = $false; themeRef = $null; errorCode = 'THEME_NOT_FOUND' }
  }
  if (-not $card.enabled) {
    return [pscustomobject]@{ ok = $false; themeRef = $null; errorCode = 'THEME_DISABLED' }
  }
  if (-not (Get-ZCodeThemeDirectoryLeaf -Key $card.key -Kind $card.kind)) {
    return [pscustomobject]@{ ok = $false; themeRef = $null; errorCode = 'THEME_LEAF_REJECTED' }
  }

  $roots = Get-ZCodeThemeCatalogRoots -StateRoot $StateRoot
  $kindRoot = if ($card.kind -ceq 'saved') { $roots.saved } else { $roots.snapshot }
  $directory = Join-Path $kindRoot $card.key
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
    return [pscustomobject]@{ ok = $false; themeRef = $null; errorCode = 'THEME_NOT_FOUND' }
  }
  if (-not (Test-DreamSkinThemePathWithin -Path ([System.IO.Path]::GetFullPath($directory)) -Root $kindRoot)) {
    return [pscustomobject]@{ ok = $false; themeRef = $null; errorCode = 'THEME_PATH_ESCAPE' }
  }
  try {
    Assert-DreamSkinNoReparseComponents -Path $directory
    $fingerprint = Get-DreamSkinThemeSemanticFingerprint -ThemeDirectory $directory
  } catch {
    return [pscustomobject]@{ ok = $false; themeRef = $null; errorCode = 'THEME_UNREADABLE' }
  }
  if ($fingerprint -cne [string]$card.fingerprint) {
    return [pscustomobject]@{ ok = $false; themeRef = $null; errorCode = 'THEME_CHANGED' }
  }
  return [pscustomobject]@{
    ok       = $true
    themeRef = [pscustomobject]@{ kind = $card.kind; key = $card.key; fingerprint = $fingerprint }
    errorCode = $null
  }
}

function Get-ZCodeThemeTargetClassification {
  <#
  One pure ruler for two questions that must never disagree: may this package be
  applied, and why is its card disabled. The answer comes from what the stylesheet
  actually targets plus the artwork unit a caller declared - never from how large a
  number happens to be and never from the theme's name.

  A package that passes every safety gate but speaks to another product's parts is
  kept in the library and reported as not target compatible. Unsafe CSS never gets
  this far: the shared gates reject it earlier and nothing is written.
  #>
  param(
    [Parameter(Mandatory = $true)][AllowEmptyString()][string]$CssText,
    [AllowEmptyString()][string]$SourceFormat = '',
    [string]$DeclaredBy = '',
    # A library entry that predates declarations is not "unknown unit": the shipped
    # bridge already treats an absent declaration as the ZCode percentage contract,
    # which is how the existing private themes keep working byte for byte.
    [switch]$LegacyUndeclared
  )
  # Only the exact attribute form counts: a ^= substring operator is not a part
  # reference and must not be read as one.
  $zcodeTargets = @([regex]::Matches($CssText, 'data-ds-part\s*=\s*"zcode-')).Count
  $otherTargets = @([regex]::Matches($CssText, 'data-ds-part\s*=\s*"(?!zcode-)')).Count
  $knownFormats = @('dream-skin-v1-normalized', 'zcode-percent-v1')
  $declared = ($knownFormats -contains $SourceFormat)
  $reason = $null
  $compatible = $false
  if ($zcodeTargets -eq 0 -and $otherTargets -eq 0) {
    $reason = 'TARGET_NONE'
  }
  elseif ($zcodeTargets -eq 0) {
    $reason = 'TARGET_FOREIGN_ONLY'
  }
  elseif ($otherTargets -gt 0) {
    $reason = 'TARGET_MIXED'
  }
  elseif (-not $declared -and -not $LegacyUndeclared) {
    $reason = 'TARGET_SOURCE_UNDECLARED'
  }
  else {
    $compatible = $true
  }
  return [pscustomobject]@{
    targetCompatible = $compatible
    reason           = $reason
    zcodeTargets     = $zcodeTargets
    otherTargets     = $otherTargets
    sourceFormat     = $(if ($declared) { $SourceFormat } else { '' })
    declaredBy       = $(if ($DeclaredBy) { $DeclaredBy } else { 'none' })
  }
}

function Get-ZCodeSavedThemeTargetVerdict {
  # Shared by the catalogue card and by the apply path: a package cannot be enabled in
  # one place and refused in the other. The verdict comes from the stylesheet that is
  # on disk right now, so replacing a package's CSS re-classifies it.
  param(
    [Parameter(Mandatory = $true)][string]$StateRoot,
    [Parameter(Mandatory = $true)][string]$Key,
    [Parameter(Mandatory = $true)][string]$Directory
  )
  $cssPath = Join-Path $Directory 'theme.css'
  $cssText = ''
  if (Test-Path -LiteralPath $cssPath -PathType Leaf) { $cssText = [System.IO.File]::ReadAllText($cssPath) }
  $declaredFormat = ''
  $declaredBy = 'none'
  if (Get-Command Get-ZCodeThemeDeclaration -ErrorAction SilentlyContinue) {
    $record = Get-ZCodeThemeDeclaration -StateRoot $StateRoot -Leaf $Key
    if ($record) {
      # A declaration speaks about the bytes it was made over. When the stylesheet or the
      # artwork on disk is no longer those bytes, the recorded unit is somebody else's
      # answer and must not carry this card.
      $liveFingerprint = ''
      if (Get-Command Get-DreamSkinThemeSemanticFingerprint -ErrorAction SilentlyContinue) {
        try { $liveFingerprint = [string](Get-DreamSkinThemeSemanticFingerprint -ThemeDirectory $Directory) } catch { $liveFingerprint = '' }
      }
      $declaredFormat = [string]$record.sourceFormat
      $declaredBy = [string]$record.declaredBy
      if ($liveFingerprint -and [string]$record.sourceFingerprint -and
          ($liveFingerprint -cne [string]$record.sourceFingerprint)) {
        return Get-ZCodeThemeTargetClassification -CssText $cssText -SourceFormat '' -DeclaredBy 'none'
      }
    }
    return Get-ZCodeThemeTargetClassification -CssText $cssText -SourceFormat $declaredFormat `
      -DeclaredBy $declaredBy -LegacyUndeclared:(-not [bool]$record)
  }
  return Get-ZCodeThemeTargetClassification -CssText $cssText -LegacyUndeclared:$true
}
