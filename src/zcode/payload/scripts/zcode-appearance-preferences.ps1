<#
ZCode Dream Skin 2.0 appearance preferences.

The live session state (state.json) is a sample of a running browser, and a Full
restore deletes it on purpose. "What appearance does the user want next time" is a
different fact and needs its own file, so R5/R6 cannot be built on top of a record
that the product legitimately erases.

Everything here is pure file I/O against an explicit -StateRoot: no process query,
no CDP, no theme activation. Both the reader and the writer answer to ONE predicate,
so a file the reader calls invalid can never be published by the writer.
#>

$script:ZCodeAppearanceSchemaVersion = 'zcode-dream-skin-appearance/1'
$script:ZCodeAppearanceFileName = 'appearance-preferences.json'
$script:ZCodeAppearanceMaxBytes = 16384
$script:ZCodeAppearanceFields = @(
  'schemaVersion', 'appearance', 'resumeTheme', 'lastConfirmedThemeRevision', 'generation'
)
$script:ZCodeAppearanceRefFields = @('kind', 'key', 'fingerprint')

function Get-ZCodeAppearancePreferencePath {
  param([Parameter(Mandatory = $true)][string]$StateRoot)
  return Join-Path $StateRoot $script:ZCodeAppearanceFileName
}

function Get-ZCodeAppearancePreferenceProblem {
  <#
  The single ruler. Accepts the parsed object (from ConvertFrom-Json) or an object
  built in memory, and returns a list of stable error codes. An empty list means the
  preference is publishable.

  Deliberately narrower than "anything that looks reasonable": the appearance intent
  drives what the user sees on next launch, so a foreign shape is reported, never
  repaired by guessing.
  #>
  param($Preference)
  $problems = @()
  if ($null -eq $Preference) { return @('PREFERENCE_MISSING') }

  $names = @($Preference.PSObject.Properties | ForEach-Object { [string]$_.Name })
  foreach ($extra in @($names | Where-Object { $script:ZCodeAppearanceFields -notcontains $_ })) {
    $problems += "UNKNOWN_FIELD:$extra"
  }
  foreach ($missing in @($script:ZCodeAppearanceFields | Where-Object { $names -notcontains $_ })) {
    $problems += "MISSING_FIELD:$missing"
  }
  if ($problems.Count -gt 0) { return $problems }

  if ([string]$Preference.schemaVersion -cne $script:ZCodeAppearanceSchemaVersion) {
    $problems += 'SCHEMA_VERSION_MISMATCH'
  }

  $appearance = $Preference.appearance
  if ($appearance -isnot [string] -or ($appearance -cne 'native' -and $appearance -cne 'theme')) {
    $problems += 'APPEARANCE_INVALID'
  }

  $revision = $Preference.lastConfirmedThemeRevision
  if ($revision -isnot [string] -or ($revision -ne '' -and $revision -cnotmatch '^[0-9a-f]{20}$')) {
    $problems += 'REVISION_INVALID'
  }

  $generation = $Preference.generation
  if ($null -eq $generation) {
    $problems += 'GENERATION_INVALID'
  } elseif ($generation -is [double] -or $generation -is [single] -or $generation -is [decimal]) {
    $problems += 'GENERATION_INVALID'
  } elseif ($generation -isnot [int] -and $generation -isnot [long]) {
    $problems += 'GENERATION_INVALID'
  } else {
    $value = [long]$generation
    if ($value -lt 0 -or $value -gt 9007199254740991L) { $problems += 'GENERATION_OUT_OF_RANGE' }
  }

  $resume = $Preference.resumeTheme
  if ($null -eq $resume) {
    if ($appearance -ceq 'theme') { $problems += 'RESUME_THEME_REQUIRED' }
  } else {
    $problems += @(Get-ZCodeAppearanceRefProblem -Ref $resume)
  }

  # A theme appearance is only claimable once a revision has actually been applied
  # and verified; "theme with nothing confirmed yet" would let the launcher promise
  # a skin the product never proved.
  if ($appearance -ceq 'theme' -and [string]$revision -eq '') {
    $problems += 'REVISION_UNCONFIRMED_FOR_THEME'
  }
  return $problems
}

function Get-ZCodeAppearanceRefProblem {
  param($Ref)
  $problems = @()
  if ($Ref -is [string] -or $Ref -is [array]) { return @('RESUME_THEME_NOT_AN_OBJECT') }
  $names = @($Ref.PSObject.Properties | ForEach-Object { [string]$_.Name })
  foreach ($extra in @($names | Where-Object { $script:ZCodeAppearanceRefFields -notcontains $_ })) {
    $problems += "REF_UNKNOWN_FIELD:$extra"
  }
  foreach ($missing in @($script:ZCodeAppearanceRefFields | Where-Object { $names -notcontains $_ })) {
    $problems += "REF_MISSING_FIELD:$missing"
  }
  if ($problems.Count -gt 0) { return $problems }

  $kind = $Ref.kind
  if ($kind -isnot [string] -or ($kind -cne 'saved' -and $kind -cne 'snapshot')) {
    $problems += 'REF_KIND_INVALID'
    return $problems
  }

  $fingerprint = $Ref.fingerprint
  if ($fingerprint -isnot [string] -or $fingerprint -cnotmatch '^[0-9a-f]{64}$') {
    $problems += 'REF_FINGERPRINT_INVALID'
  }

  $key = $Ref.key
  if ($key -isnot [string]) {
    $problems += 'REF_KEY_INVALID'
  } elseif ($kind -ceq 'snapshot') {
    if ($key -cnotmatch '^[0-9a-f]{32}$') { $problems += 'REF_SNAPSHOT_KEY_INVALID' }
  } elseif (-not (Test-ZCodeSavedThemeLeaf -Key $key)) {
    $problems += 'REF_SAVED_KEY_INVALID'
  }
  return $problems
}

function Test-ZCodeSavedThemeLeaf {
  <#
  A saved theme key is one directory leaf under StateRoot\themes. The rejections are
  exactly the ones that would make a path ambiguous or escape the library: empty,
  '.' and '..', separators, colon, control characters, and a trailing dot or space
  that Windows silently strips. Ordinary names - including spaces inside the name -
  stay legal, because the existing library is not rewritten to satisfy this file.
  #>
  param([string]$Key)
  if ([string]::IsNullOrEmpty($Key)) { return $false }
  if ($Key -eq '.' -or $Key -eq '..') { return $false }
  if ($Key.Contains('/') -or $Key.Contains('\')) { return $false }
  if ($Key.Contains(':')) { return $false }
  foreach ($ch in $Key.ToCharArray()) {
    $code = [int]$ch
    if ($code -lt 32 -or $code -eq 127) { return $false }
  }
  if ($Key.EndsWith('.') -or $Key.EndsWith(' ')) { return $false }
  return $true
}

function Read-ZCodeAppearancePreferences {
  param([Parameter(Mandatory = $true)][string]$StateRoot)
  $path = Get-ZCodeAppearancePreferencePath -StateRoot $StateRoot
  if (-not (Test-Path -LiteralPath $path)) {
    return [pscustomobject]@{ status = 'absent'; preference = $null; errorCode = $null }
  }

  $item = Get-Item -LiteralPath $path
  if ($item.PSIsContainer) {
    return [pscustomobject]@{ status = 'invalid'; preference = $null; errorCode = 'PREFERENCE_NOT_A_FILE' }
  }
  if ($item.Length -gt $script:ZCodeAppearanceMaxBytes) {
    # Never read an oversized file into memory: the cap is also the denial-of-service
    # guard, and the bytes stay on disk for diagnosis.
    return [pscustomobject]@{ status = 'invalid'; preference = $null; errorCode = 'PREFERENCE_TOO_LARGE' }
  }

  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    return [pscustomobject]@{ status = 'invalid'; preference = $null; errorCode = 'PREFERENCE_HAS_BOM' }
  }
  $text = [System.Text.UTF8Encoding]::new($false).GetString($bytes)
  try {
    $parsed = ConvertFrom-Json $text
  } catch {
    return [pscustomobject]@{ status = 'invalid'; preference = $null; errorCode = 'PREFERENCE_MALFORMED_JSON' }
  }
  if ($null -eq $parsed) {
    return [pscustomobject]@{ status = 'invalid'; preference = $null; errorCode = 'PREFERENCE_MALFORMED_JSON' }
  }

  $problems = @(Get-ZCodeAppearancePreferenceProblem -Preference $parsed)
  if ($problems.Count -gt 0) {
    return [pscustomobject]@{ status = 'invalid'; preference = $null; errorCode = ($problems -join ';') }
  }
  return [pscustomobject]@{ status = 'valid'; preference = $parsed; errorCode = $null }
}

function Write-ZCodeAppearancePreferences {
  <#
  Compare-and-set publish: the caller states the generation it built its change on.
  A disk that moved underneath (another window, an interrupted run) is a conflict,
  not something to overwrite. The bytes land in a temp file in the same directory and
  are moved over the target, so an interrupted publication leaves the previous file
  byte-for-byte intact and cleans up only its own temp.

  An unreadable preference on disk is refused by default, because a file nobody can
  parse is still somebody's evidence. The explicit switch exists for the one case the
  contract allows: an applied change by the user, after the damaged bytes were copied
  somewhere they survive. It is never turned on by a read path.
  #>
  param(
    [Parameter(Mandatory = $true)][string]$StateRoot,
    [Parameter(Mandatory = $true)]$Preference,
    $ExpectedGeneration,
    [scriptblock]$AfterTempWrite = $null,
    [bool]$AllowOverInvalidEvidencePreserved = $false
  )
  $path = Get-ZCodeAppearancePreferencePath -StateRoot $StateRoot
  $temp = Join-Path $StateRoot ($script:ZCodeAppearanceFileName + '.tmp-' + [guid]::NewGuid().ToString('N'))

  $problems = @(Get-ZCodeAppearancePreferenceProblem -Preference $Preference)
  if ($problems.Count -gt 0) {
    return [pscustomobject]@{ ok = $false; preference = $null; errorCode = ($problems -join ';') }
  }

  $current = Read-ZCodeAppearancePreferences -StateRoot $StateRoot
  if ($current.status -eq 'invalid') {
    # An existing but unreadable file is preserved untouched unless the caller both
    # declares that it copied the damaged bytes first and is acting for the user.
    if (-not [bool]$AllowOverInvalidEvidencePreserved) {
      return [pscustomobject]@{ ok = $false; preference = $null; errorCode = "PREFERENCE_INVALID_ON_DISK:$($current.errorCode)" }
    }
  } else {
    $diskGeneration = if ($current.status -eq 'valid') { [long]$current.preference.generation } else { $null }
    if ($null -eq $ExpectedGeneration) {
      if ($null -ne $diskGeneration) {
        return [pscustomobject]@{ ok = $false; preference = $null; errorCode = 'GENERATION_CONFLICT' }
      }
    } elseif ([long]$ExpectedGeneration -ne $diskGeneration) {
      return [pscustomobject]@{ ok = $false; preference = $null; errorCode = 'GENERATION_CONFLICT' }
    }
  }

  $published = $null
  try {
    $null = [System.IO.Directory]::CreateDirectory((Split-Path -Parent $path))
    $json = ConvertTo-ZCodeAppearancePreferenceJson -Preference $Preference
    [System.IO.File]::WriteAllText($temp, $json, [System.Text.UTF8Encoding]::new($false))
    if ($AfterTempWrite) { & $AfterTempWrite }
    Move-Item -LiteralPath $temp -Destination $path -Force
    $published = $Preference
  } finally {
    if (Test-Path -LiteralPath $temp) {
      Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
    }
  }
  return [pscustomobject]@{ ok = $true; preference = $published; errorCode = $null }
}

function ConvertTo-ZCodeAppearancePreferenceJson {
  param([Parameter(Mandatory = $true)]$Preference)
  $ordered = [ordered]@{
    schemaVersion              = [string]$Preference.schemaVersion
    appearance                 = [string]$Preference.appearance
    resumeTheme                = $null
    lastConfirmedThemeRevision = [string]$Preference.lastConfirmedThemeRevision
    generation                 = [long]$Preference.generation
  }
  if ($null -ne $Preference.resumeTheme) {
    $ordered.resumeTheme = [ordered]@{
      kind        = [string]$Preference.resumeTheme.kind
      key         = [string]$Preference.resumeTheme.key
      fingerprint = [string]$Preference.resumeTheme.fingerprint
    }
  }
  return (ConvertTo-Json -InputObject $ordered -Depth 5 -Compress)
}
