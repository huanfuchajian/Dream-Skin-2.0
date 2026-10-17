# ZCode theme-store and installer-marker bridge.
#
# Small on purpose: this file only bridges the installer's verified ZCode path and
# the active theme library, so the four product entry points share one resolver
# instead of each reimplementing it. The marker is a CANDIDATE RECORD, never a trust
# token: every consumer re-verifies the executable's identity before using it.

$script:ZCodeInstallerMarkerSchema = 'zcode-dream-skin-installer/1'

function Get-ZCodeDreamSkinThemeArguments {
  # Shared by independent start and restore processes, never a start-only helper.
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)][string]$SkillRoot,
    [Parameter(Mandatory = $true)][string]$StateRoot,
    [string]$ArtPath = '',
    [string]$ThemePath = '',
    # Declared by whoever selected the content, never guessed from the numbers: the
    # renderer consumes percent while a package validated by the shipped gate carries a
    # 0-1 ratio.
    [ValidateSet('', 'dream-skin-v1-normalized', 'zcode-percent-v1')]
    [string]$ArtSourceFormat = ''
  )
  $inputs = Get-ZCodeActiveThemeInputs -SkillRoot $SkillRoot -StateRoot $StateRoot `
    -ImagePath $ArtPath -ThemePath $ThemePath
  $arguments = @('--zcode-art', $inputs.ImagePath, '--zcode-theme', $inputs.ThemePath)
  if ($inputs.SafeCssPath) { $arguments += @('--zcode-user-css', $inputs.SafeCssPath) }
  if ($ArtSourceFormat) { $arguments += @('--zcode-art-source', $ArtSourceFormat) }
  return $arguments
}

function Get-ZCodeActiveThemeInputs {
  <#
  The image, theme metadata and validated user CSS the product must apply.

  Default source is the ACTIVE theme library under the state root the caller is
  using - the same library the tray changes. Explicit -ImagePath / -ThemePath keep
  the CLI working and win outright. Every input is validated before it is returned:
  the image through the shared image gate and the user sheet through the Safe CSS
  policy, so a theme that cannot be trusted is refused instead of half-applied.
  Initialization never overwrites an existing active theme.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)][string]$SkillRoot,
    [Parameter(Mandatory = $true)][string]$StateRoot,
    [string]$ImagePath = '',
    [string]$ThemePath = ''
  )
  # Every intermediate call is captured: the upstream Assert-* helpers return $true,
  # and an uncaptured return would join this function's output and turn the result
  # into an array.
  $null = Initialize-DreamSkinThemeStore -SkillRoot $SkillRoot -StateRoot $StateRoot
  $paths = Get-DreamSkinThemePaths -StateRoot $StateRoot

  # An explicit theme is applied through its own validated directory, so validation
  # and use can never disagree about which file defines the theme.
  $themeDirectory = $paths.Active
  if ($ThemePath) {
    $themeDirectory = Split-Path -Parent ([System.IO.Path]::GetFullPath($ThemePath))
  }
  $loaded = Read-DreamSkinTheme -ThemeDirectory $themeDirectory

  $resolvedImage = $loaded.ImagePath
  if ($ImagePath) {
    $resolvedImage = [System.IO.Path]::GetFullPath($ImagePath)
    $null = Assert-DreamSkinImageFile -Path $resolvedImage
  }

  $safeCssPath = Join-Path $themeDirectory 'theme.css'
  if (Test-Path -LiteralPath $safeCssPath -PathType Leaf) {
    $null = Assert-DreamSkinSafeCssFile -Path $safeCssPath
  } else {
    $safeCssPath = ''
  }

  return [pscustomobject]@{
    ImagePath   = $resolvedImage
    ThemePath   = $loaded.ThemePath
    SafeCssPath = $safeCssPath
  }
}

function Read-ZCodeInstallerMarker {
  <#
  Reads the installer's marker. An absent marker is normal (the product may have
  been started from source); a marker that exists but does not match the schema is a
  hard E13, because silently falling back to another ZCode instance is exactly the
  failure this record exists to prevent.
  #>
  param([Parameter(Mandatory = $true)][string]$StateRoot)
  if (-not $StateRoot) { return $null }
  $path = Join-Path $StateRoot 'installer.json'
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
  $marker = $null
  try {
    $marker = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
  } catch {
    throw "E13_STATE_SCHEMA_INVALID: the installer marker is unreadable: $($_.Exception.Message)"
  }
  if (-not $marker -or [string]$marker.schemaVersion -cne $script:ZCodeInstallerMarkerSchema) {
    throw 'E13_STATE_SCHEMA_INVALID: the installer marker does not match zcode-dream-skin-installer/1'
  }
  if (-not [string]$marker.zcodePath) {
    throw 'E13_STATE_SCHEMA_INVALID: the installer marker records no ZCode path'
  }
  return $marker
}

function Get-ZCodeConfiguredExecutable {
  <#
  The verified candidate path: an explicit request wins outright, otherwise the
  installer marker's recorded path, otherwise nothing (the caller then falls back to
  the normal discovery flow).
  #>
  param(
    [string]$StateRoot = '',
    [string]$ExplicitPath = ''
  )
  if ($ExplicitPath) { return $ExplicitPath }
  $marker = Read-ZCodeInstallerMarker -StateRoot $StateRoot
  if (-not $marker) { return '' }
  return [string]$marker.zcodePath
}

function Resolve-ZCodeDreamSkinExecutable {
  <#
  The launch-path priority every installed entry point shares: an explicit
  -ZCodePath wins outright, then the installer marker's recorded candidate, and
  only an ABSENT marker falls through to the ordinary discovery flow. A marker
  that exists but is unreadable or mistyped is a hard E13 (Read-ZCodeInstallerMarker
  throws) even though discovery is available - silently switching to another ZCode
  instance is exactly what the record exists to prevent. The returned path is a
  CANDIDATE only: the caller re-validates the executable's identity before using it.
  #>
  [CmdletBinding()]
  param(
    [string]$StateRoot = '',
    [string]$ExplicitPath = '',
    [scriptblock]$Discover = { Resolve-DreamSkinZCodeExecutable -ConfiguredPath '' }
  )
  $candidate = Get-ZCodeConfiguredExecutable -StateRoot $StateRoot -ExplicitPath $ExplicitPath
  if ($candidate) { return $candidate }
  return & $Discover
}

function Write-ZCodeInstallerMarker {
  <#
  Atomic publish: the temporary file lands beside the target and is moved over it, so
  an interrupted write can never leave a half marker and a failed write never
  destroys the marker that was already there.
  #>
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Content
  )
  $directory = Split-Path -Parent $Path
  if ($directory -and -not (Test-Path -LiteralPath $directory -PathType Container)) {
    $null = [System.IO.Directory]::CreateDirectory($directory)
  }
  $temp = "$Path.tmp-$([guid]::NewGuid().ToString('N'))"
  try {
    [System.IO.File]::WriteAllText($temp, $Content, [System.Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temp -Destination $Path -Force
  } finally {
    if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
  }
  return $Path
}
