<#
ZCode Dream Skin 2.0 unified launch entry.

This is the icon the user clicks. It decides nothing on its own: it opens the one
appearance door, and afterwards makes sure a tray exists so the controls are reachable
without a second permanent resident. The official ZCode shortcut is left exactly as the
vendor made it - only this entry carries the remembered appearance.
#>
[CmdletBinding()]
param(
  [string]$StateRoot = '',
  [switch]$NoTray,
  [string]$PresetRoot = '',
  [switch]$NoSeed,
  # --- injectable seams; $null means "run the real thing" ----------------------
  [scriptblock]$NewEffects = $null,
  [scriptblock]$InvokeOperation = $null,
  [scriptblock]$TrayActive = $null,
  [scriptblock]$StartTray = $null,
  [scriptblock]$Now = $null
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common-windows.ps1')
. (Join-Path $PSScriptRoot 'theme-windows.ps1')
. (Join-Path $PSScriptRoot 'zcode-product.ps1')
. (Join-Path $PSScriptRoot 'zcode-theme-catalog.ps1')
. (Join-Path $PSScriptRoot 'zcode-appearance-preferences.ps1')
. (Join-Path $PSScriptRoot 'zcode-appearance-snapshots.ps1')
. (Join-Path $PSScriptRoot 'zcode-appearance-controller.ps1')
# The live boundaries live in one file only; loading it defines functions and never
# runs the CLI entry point.
. (Join-Path $PSScriptRoot 'set-zcode-appearance.ps1')
. (Join-Path $PSScriptRoot 'zcode-preset-seed.ps1')

function Invoke-ZCodeAppearanceLaunchEntry {
  <#
  Returns the controller's own result plus the tray decision and an exit code, so the
  caller never has to re-derive whether the appearance actually landed.
  #>
  param(
    [Parameter(Mandatory = $true)][string]$StateRoot,
    [bool]$NoTray = $false,
    $Effects = $null,
    $Operation = $null,
    $TrayProbe = $null,
    $TrayStarter = $null,
    # Public presets arrive through the same importer a user's ZIP goes through.
    # Seeding is idempotent by content and writes only inside -StateRoot.
    [string]$PresetRoot = '',
    [bool]$NoSeed = $false,
    $Seeder = $null,
    $Now = $null
  )
  $root = Get-ZCodeDreamSkinStateRoot -StateRoot $StateRoot
  # Seeded before the appearance door is opened: the remembered skin may be a preset
  # that has not reached this library yet, and a first launch must not offer less than
  # a later one. A refusal here never turns into a half-applied appearance.
  $seed = [pscustomobject]@{ attempted = $false; seeded = @(); reused = @(); errorCode = $null }
  if (-not [bool]$NoSeed -and $PresetRoot) {
    try {
      $seedResult = if ($Seeder) { & $Seeder $root $PresetRoot } else {
        Seed-ZCodePublicPresets -StateRoot $root -PresetRoot $PresetRoot
      }
      $seed = [pscustomobject]@{
        attempted = $true
        seeded    = @($seedResult.seeded)
        reused    = @($seedResult.reused)
        errorCode = [string]$seedResult.errorCode
      }
      if (-not $seedResult.ok) { $seed.errorCode = [string]$seedResult.errorCode }
    } catch {
      $seed = [pscustomobject]@{ attempted = $true; seeded = @(); reused = @(); errorCode = 'PRESET_SEED_FAILED' }
    }
  }
  $nowOf = if ($Now) { $Now } else { { return (Get-Date) } }
  $request = [pscustomobject]@{
    schemaVersion = 'zcode-dream-skin-command/1'
    requestId     = [guid]::NewGuid().ToString('N')
    action        = 'launch'
    stateRoot     = $root
  }
  if ($null -eq $Effects) { $Effects = New-Zds2LiveEffects -StateRoot $root }
  if ($null -eq $Operation) {
    $result = Invoke-ZCodeAppearanceOperation -StateRoot $root -Request $request -Effects $Effects
  } else {
    $result = & $Operation $root $request $Effects
  }

  $tray = 'skipped'
  if (-not [bool]$NoTray) {
    if ($null -eq $TrayProbe) { $TrayProbe = { return [bool](Test-ZCodeDreamSkinTrayActive) } }
    if ($null -eq $TrayStarter) {
      $trayScript = Join-Path $PSScriptRoot 'tray-zcode-dream-skin.ps1'
      $TrayStarter = {
        param($ScriptPath)
        Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') `
          -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'RemoteSigned', '-WindowStyle', 'Hidden',
            '-File', (ConvertTo-DreamSkinProcessArgument -Value $ScriptPath)) `
          -WindowStyle Hidden | Out-Null
      }
    }
    if (& $TrayProbe) {
      $tray = 'already-running'
    } else {
      & $TrayStarter (Join-Path $PSScriptRoot 'tray-zcode-dream-skin.ps1')
      $tray = 'started'
    }
  }

  $exitCode = 1
  if ($result.ok) { $exitCode = 0 } elseif ($result.errorCode -eq 'BUSY') { $exitCode = 4 }
  return [pscustomobject]@{
    result   = $result
    tray     = $tray
    seed     = $seed
    exitCode = $exitCode
    at       = (& $nowOf).ToString('o')
  }
}

if ($MyInvocation.InvocationName -ne '.') {
  $outcome = Invoke-ZCodeAppearanceLaunchEntry -StateRoot $StateRoot -NoTray ([bool]$NoTray.IsPresent) `
    -PresetRoot $PresetRoot -NoSeed ([bool]$NoSeed.IsPresent)
  $status = $outcome.result.status
  Write-Host ("[LAUNCH] presets attempted=$($outcome.seed.attempted) seeded=$(@($outcome.seed.seeded).Count) reused=$(@($outcome.seed.reused).Count) errorCode=$($outcome.seed.errorCode)")
  # The wording comes from the controller, never from a second table here, so a
  # Chinese sentence cannot drift away from the code that produced it.
  Write-Host ("[LAUNCH] appearance=$($status.appearance) confirmed=$($status.confirmed) tray=$($outcome.tray) errorCode=$($outcome.result.errorCode)")
  Write-Host ("[LAUNCH] " + $outcome.result.message)
  exit $outcome.exitCode
}
