# ZCode Dream Skin tray. Upstream tray feature set, ZCode product seam:
# apply, pause/resume, change background (PNG/JPEG/WebP), import theme ZIP,
# save current theme, switch saved themes, open theme/image directories,
# full restore, quit. Delegates to the zcode product scripts and reuses the
# upstream theme-store and localization functions unchanged.
#
# The menu is built from injectable actions and the message loop only runs when the
# script is invoked, so the day-to-day control surface is testable without a desktop.
#
# 2.0: every string the user can read comes from zcode-tray-text.ps1, so this file
# carries no localized literal at all, and every appearance change goes through the
# one controller door instead of a per-menu shortcut.
[CmdletBinding()]
param(
  [string]$StateRoot = ''
)
$ErrorActionPreference = 'Stop'
# common-windows.ps1 carries the shared validators and process-identity helpers the
# theme gates rely on; without it those calls fail late, from inside a menu click.
. (Join-Path $PSScriptRoot 'common-windows.ps1')
. (Join-Path $PSScriptRoot 'theme-windows.ps1')
. (Join-Path $PSScriptRoot 'localization-windows.ps1')
. (Join-Path $PSScriptRoot 'zcode-product.ps1')
. (Join-Path $PSScriptRoot 'zcode-theme-catalog.ps1')
. (Join-Path $PSScriptRoot 'zcode-appearance-preferences.ps1')
. (Join-Path $PSScriptRoot 'zcode-appearance-snapshots.ps1')
. (Join-Path $PSScriptRoot 'zcode-appearance-controller.ps1')
. (Join-Path $PSScriptRoot 'zcode-tray-text.ps1')
# Loading the CLI file defines the live effects and never runs its entry point.
. (Join-Path $PSScriptRoot 'set-zcode-appearance.ps1')
$root = if ($StateRoot) { Get-ZCodeDreamSkinStateRoot -StateRoot $StateRoot } else { Get-ZCodeDreamSkinStateRoot }
# Script scope on purpose: the menu handlers and the stop timer run long after the
# function that created them has returned, so everything they touch lives here.
$trayBusy = $false
# Every appearance change goes through the door below; the tray no longer shells out
# to the start and restore scripts, which was a second way to write a session.

$trayGalleryScript = Join-Path (Split-Path -Parent $PSScriptRoot) 'theme-gallery\ZCodeSkinGallery.exe'
$script:ZCodeTrayNotify = $null
$script:ZCodeTrayMenu = $null
$script:ZCodeTrayExitRequested = $false
$script:ZCodeTrayStopRequestPath = Join-Path $root 'tray-stop.request'
# This process' own address. Every stop request is aimed at it, so a flag left by a
# tray that has since died can never decide this one's exit.
$script:ZCodeTrayInstanceId = [guid]::NewGuid().ToString('N')
$script:ZCodeTrayLegacyReported = $false

function Write-ZCodeTrayLog {
  <#
  Child output is kept locally. It must never travel back to a caller: a multi-line
  failure log would read as a truthy value and turn a failed apply into a success
  balloon.
  #>
  param(
    [Parameter(Mandatory = $true)][string]$Name,
    [AllowEmptyString()][string]$Text = ''
  )
  try {
    $logRoot = Join-Path $root 'logs'
    $null = [System.IO.Directory]::CreateDirectory($logRoot)
    $stamp = (Get-Date).ToString('yyyyMMdd-HHmmss-fff')
    $target = Join-Path $logRoot ("$Name-$stamp.log")
    [System.IO.File]::WriteAllText($target, $Text, [System.Text.UTF8Encoding]::new($false))
    return $target
  } catch {
    # Logging is diagnostics: an unwritable log directory must not break the action.
    return ''
  }
}

function Invoke-ZCodeTrayAction {
  <#
  Runs a product script and returns a STRICT boolean. The exit code is read before
  anything is logged, so stdout/stderr can never stand in for the result.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)][string]$ScriptPath,
    [string[]]$Arguments = @(),
    [scriptblock]$InvokeChild = $null,
    [scriptblock]$WriteLog = $null
  )
  $invoke = if ($InvokeChild) { $InvokeChild } else {
    {
      param($Path, $ActionArguments)
      $childOutput = & powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File $Path @ActionArguments 2>&1
      return @{ exitCode = [int]$LASTEXITCODE; output = ($childOutput | Out-String) }
    }
  }
  $log = if ($WriteLog) { $WriteLog } else { { param($Name, $Text) Write-ZCodeTrayLog -Name $Name -Text $Text } }
  $result = & $invoke $ScriptPath $Arguments
  $exitCode = [int]$result.exitCode
  $null = & $log (Split-Path -Leaf $ScriptPath) ([string]$result.output)
  return ($exitCode -eq 0)
}

function Show-ZCodeTrayBalloon {
  param(
    [Parameter(Mandatory = $true)]$Notify,
    [Parameter(Mandatory = $true)][string]$Text,
    [bool]$AsError = $false,
    [int]$Milliseconds = 2000
  )
  $icon = if ($AsError) { [System.Windows.Forms.ToolTipIcon]::Error } else { [System.Windows.Forms.ToolTipIcon]::Info }
  $Notify.ShowBalloonTip($Milliseconds, 'ZCode Dream Skin', $Text, $icon)
}

function Show-ZCodeTrayTextBalloon {
  <#
  The only way the tray shows a sentence: a key plus optional arguments plus the
  machine code. Long exception text goes to the log, never into a bubble the user
  has two seconds to read.
  #>
  param(
    [Parameter(Mandatory = $true)]$Notify,
    [Parameter(Mandatory = $true)][string]$Key,
    [object[]]$FormatArguments = @(),
    [string]$Diagnostic = '',
    [bool]$AsError = $false,
    [int]$Milliseconds = 2000
  )
  Show-ZCodeTrayBalloon -Notify $Notify -AsError $AsError -Milliseconds $Milliseconds `
    -Text (Get-ZCodeTrayBubbleText -Key $Key -FormatArguments $FormatArguments -Diagnostic $Diagnostic)
}

function Invoke-ZCodeTrayDoor {
  <#
  One appearance change, one door: the controller holds the root lock, journals the
  phases, verifies independently and only then records the intent. The tray never
  calls a theme-store writer directly.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)][string]$Action,
    [string]$ThemeId = '',
    [string]$Name = '',
    [string]$ImagePath = '',
    $Effects = $null
  )
  $request = [pscustomobject]@{
    schemaVersion = 'zcode-dream-skin-command/1'
    requestId     = [guid]::NewGuid().ToString('N')
    action        = $Action
    stateRoot     = $root
  }
  if ($ThemeId) { $request | Add-Member -NotePropertyName themeId -NotePropertyValue $ThemeId }
  if ($Name) { $request | Add-Member -NotePropertyName name -NotePropertyValue $Name }
  if ($ImagePath) { $request | Add-Member -NotePropertyName imagePath -NotePropertyValue $ImagePath }
  if ($null -eq $Effects) { $Effects = New-Zds2LiveEffects -StateRoot $root }
  return Invoke-ZCodeAppearanceOperation -StateRoot $root -Request $request -Effects $Effects
}

function Get-ZCodeTrayDraftState {
  <#
  "Apply these changes" only exists while a draft exists. Read-only: listing a
  directory must never look like an appearance change.
  #>
  $draftRoot = Join-Path $root 'appearance-drafts'
  if (-not (Test-Path -LiteralPath $draftRoot -PathType Container)) { return $null }
  $latest = @(Get-ChildItem -LiteralPath $draftRoot -Directory -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1)
  if ($latest.Count -eq 0) { return $null }
  $pendingPath = Join-Path $latest[0].FullName 'pending-artwork.json'
  if (-not (Test-Path -LiteralPath $pendingPath -PathType Leaf)) { return $null }
  try {
    $pending = ConvertFrom-Json ([System.IO.File]::ReadAllText($pendingPath))
  } catch { return $null }
  if (-not $pending.PSObject.Properties['draftId']) { return $null }
  return [pscustomobject]@{ DraftId = [string]$pending.draftId; Directory = [string]$latest[0].FullName }
}

function New-ZCodeTrayMenu {
  <#
  Builds the context menu from a spec plus injectable actions, so labels, order,
  separators and handlers can be asserted without a message loop. Labels are
  resolved from the ZCode wording table; the spec never carries a display string.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)][hashtable]$Actions,
    [Parameter(Mandatory = $true)]$Menu,
    [string]$StatusText = '',
    [bool]$ShowApplyChanges = $false
  )
  $spec = [System.Collections.Generic.List[object]]::new()
  if ($StatusText) { $spec.Add(@{ Kind = 'status'; Text = $StatusText }) }
  $spec.Add(@{ Kind = 'item'; Key = 'MenuOpenGallery'; Action = 'OpenGallery' })
  $spec.Add(@{ Kind = 'item'; Key = 'MenuQuickSwitch'; Action = 'QuickSwitch' })
  $spec.Add(@{ Kind = 'item'; Key = 'MenuUseDefault'; Action = 'UseDefault' })
  $spec.Add(@{ Kind = 'item'; Key = 'MenuRestoreSkin'; Action = 'RestoreSkin' })
  $spec.Add(@{ Kind = 'separator' })
  $spec.Add(@{ Kind = 'item'; Key = 'MenuChangeBackground'; Action = 'ChangeBackground' })
  if ($ShowApplyChanges) {
    $spec.Add(@{ Kind = 'item'; Key = 'MenuApplyChanges'; Action = 'ApplyChanges' })
  }
  $spec.Add(@{ Kind = 'item'; Key = 'MenuImportZip'; Action = 'ImportTheme' })
  $spec.Add(@{ Kind = 'item'; Key = 'MenuSaveTheme'; Action = 'SaveTheme' })
  $spec.Add(@{ Kind = 'separator' })
  $spec.Add(@{ Kind = 'item'; Key = 'MenuOpenThemes'; Action = 'OpenThemes' })
  $spec.Add(@{ Kind = 'item'; Key = 'MenuOpenImages'; Action = 'OpenImages' })
  $spec.Add(@{ Kind = 'separator' })
  $spec.Add(@{ Kind = 'item'; Key = 'MenuFullRestore'; Action = 'FullRestore' })
  $spec.Add(@{ Kind = 'item'; Key = 'MenuQuitTray'; Action = 'Quit' })

  $items = [System.Collections.Generic.List[object]]::new()
  foreach ($entry in $spec) {
    if ($entry.Kind -eq 'separator') {
      $null = $Menu.Items.Add('-')
      continue
    }
    $label = if ($entry.Kind -eq 'status') { $entry.Text } else { Get-ZCodeTrayText -Key $entry.Key }
    if ($entry.Kind -eq 'status') {
      $statusItem = $Menu.Items.Add($label)
      $statusItem.Enabled = $false
      # The status line is an observation, not a command: it is recorded so a test can
      # assert what the user was told, and it can never be clicked into a write.
      $items.Add([pscustomobject]@{ Text = $label; Action = ''; Item = $statusItem; Handler = $null; Kind = 'status' })
      continue
    }
    if (-not $Actions.ContainsKey($entry.Action)) {
      throw "the tray action '$($entry.Action)' has no implementation"
    }
    $item = $Menu.Items.Add($label)
    $handler = $Actions[$entry.Action]
    $item.Add_Click({ & $handler }.GetNewClosure())
    # The handler is kept on the record so a test can invoke exactly what a click
    # would run, without synthesising UI input.
    $items.Add([pscustomobject]@{ Text = $label; Action = $entry.Action; Item = $item; Handler = $handler; Kind = 'item' })
  }
  return $items
}

# The tray owns a mutex for its whole lifetime: acquiring it is how every other
# component (and the uninstaller) proves this tray is gone.
$script:ZCodeTrayMutex = [System.Threading.Mutex]::new($false, (Get-ZCodeDreamSkinTrayMutexName))
$script:ZCodeTrayMutexHeld = $false
$script:ZCodeTrayNotify = $null
$script:ZCodeTrayMenu = $null
$script:ZCodeTrayExitRequested = $false

function Get-ZCodeTrayStatusText {
  <#
  The status line reports what was observed, never what a file hoped for: an
  unreadable or contradicted state says "to be confirmed" instead of a confident lie.
  #>
  param($DoorResult)
  if ($null -ne $DoorResult -and $DoorResult.status.errorCode) {
    return Get-ZCodeTrayText -Key 'StatusAppearance' -FormatArguments @((Get-ZCodeTrayText -Key 'StatusPending'))
  }
  $appearance = if ($DoorResult -and $DoorResult.status) { [string]$DoorResult.status.appearance } else { 'pending' }
  switch ($appearance) {
    'native' { $word = Get-ZCodeTrayText -Key 'StatusNative' }
    'theme' {
      $name = ''
      if ($DoorResult.status.themeId) {
        $card = @( (Get-ZCodeThemeCatalog -StateRoot $root).cards | Where-Object { $_.themeId -ceq $DoorResult.status.themeId } )
        if ($card.Count -eq 1) { $name = [string]$card[0].name }
      }
      if (-not $name) { $name = (Get-ZCodeTrayText -Key 'StatusAppearance' -FormatArguments @('')) }
      return (Get-ZCodeTrayText -Key 'StatusAppearance' -FormatArguments @($name))
    }
    default { $word = Get-ZCodeTrayText -Key 'StatusPending' }
  }
  return (Get-ZCodeTrayText -Key 'StatusAppearance' -FormatArguments @($word))
}

function Get-ZCodeTrayActions {
  <#
  The menu implementations, built fresh each time so a caller can wrap them. The
  scriptblocks run from script scope, which is where every variable they close over
  lives.
  #>
  [CmdletBinding()]
  param()
  $actions = @{

    Apply = {
      if ($trayBusy) { return }
      $trayBusy = $true
      try {
        $result = Invoke-ZCodeTrayDoor -Action 'resume'
        Show-ZCodeTrayResultBalloon -Result $result -OkKey 'BubbleApplied' -FailKey 'BubbleApplyFailed'
      } finally { $trayBusy = $false }
    }
    Pause = {
      if ($trayBusy) { return }
      $trayBusy = $true
      try {
        $result = Invoke-ZCodeTrayDoor -Action 'native'
        Show-ZCodeTrayResultBalloon -Result $result -OkKey 'BubblePaused' -FailKey 'BubblePauseFailed'
      } finally { $trayBusy = $false }
    }
    Resume = {
      if ($trayBusy) { return }
      $trayBusy = $true
      try {
        $result = Invoke-ZCodeTrayDoor -Action 'resume'
        Show-ZCodeTrayResultBalloon -Result $result -OkKey 'BubbleResumed' -FailKey 'BubbleResumeFailed'
      } finally { $trayBusy = $false }
    }
    UseDefault = {
      if ($trayBusy) { return }
      $trayBusy = $true
      try {
        $result = Invoke-ZCodeTrayDoor -Action 'native'
        Show-ZCodeTrayResultBalloon -Result $result -OkKey 'BubbleNativeOn' -FailKey 'BubblePauseFailed'
      } finally { $trayBusy = $false }
    }
    RestoreSkin = {
      if ($trayBusy) { return }
      $trayBusy = $true
      try {
        $result = Invoke-ZCodeTrayDoor -Action 'resume'
        Show-ZCodeTrayResultBalloon -Result $result -OkKey 'BubbleResumed' -FailKey 'BubbleResumeFailed'
      } finally { $trayBusy = $false }
    }
    QuickSwitch = {
      if ($trayBusy) { return }
      $trayBusy = $true
      try {
        $cards = @( (Get-ZCodeThemeCatalog -StateRoot $root).cards | Where-Object { $_.kind -ne 'native' } )
        $picker = New-Object System.Windows.Forms.ContextMenuStrip
        if ($cards.Count -eq 0) {
          Show-ZCodeTrayTextBalloon -Notify $script:ZCodeTrayNotify -Key 'MenuNoSavedThemes'
          return
        }
        foreach ($card in $cards) {
          $cardId = [string]$card.themeId
          $cardName = [string]$card.name
          if (-not $card.enabled) {
            $disabled = $picker.Items.Add($cardName)
            $disabled.Enabled = $false
            continue
          }
          $null = $picker.Items.Add($cardName).Add_Click({
            $pickedId = $cardId
            $pickedName = $cardName
            if ($trayBusy) {
              Show-ZCodeTrayTextBalloon -Notify $script:ZCodeTrayNotify -Key 'BubbleBusy' -AsError $true
              return
            }
            $trayBusy = $true
            try {
              $result = Invoke-ZCodeTrayDoor -Action 'theme' -ThemeId $pickedId
              Show-ZCodeTrayResultBalloon -Result $result -OkKey 'BubbleSwitched' -FailKey 'BubbleSwitchFailed' `
                -OkArguments @($pickedName)
            } finally { $trayBusy = $false }
          }.GetNewClosure())
        }
        $picker.Show([System.Windows.Forms.Cursor]::Position)
      } finally { $trayBusy = $false }
    }
    OpenGallery = {
      if (-not (Test-Path -LiteralPath $trayGalleryScript -PathType Leaf)) {
        Show-ZCodeTrayTextBalloon -Notify $script:ZCodeTrayNotify -Key 'BubbleGalleryMissing' -AsError $true -Milliseconds 3000
        return
      }
      Start-Process -FilePath $trayGalleryScript | Out-Null
      Show-ZCodeTrayTextBalloon -Notify $script:ZCodeTrayNotify -Key 'BubbleGalleryOpened'
    }
    ApplyChanges = {
      if ($trayBusy) { return }
      $trayBusy = $true
      try {
        $draft = Get-ZCodeTrayDraftState
        if ($null -eq $draft) {
          Show-ZCodeTrayTextBalloon -Notify $script:ZCodeTrayNotify -Key 'BubbleCancelled'
          return
        }
        $result = Invoke-ZCodeTrayDoor -Action 'apply-draft' -ThemeId ([string]$draft.DraftId)
        Show-ZCodeTrayResultBalloon -Result $result -OkKey 'BubbleApplied' -FailKey 'BubbleApplyFailed'
      } finally { $trayBusy = $false }
    }
    ChangeBackground = {
      if ($trayBusy) { return }
      $trayBusy = $true
      try {
        $dialog = New-Object System.Windows.Forms.OpenFileDialog
        $dialog.Title = Get-ZCodeTrayText -Key 'DialogImageTitle'
        $dialog.Filter = Get-ZCodeTrayText -Key 'DialogImageFilter'
        if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
          Show-ZCodeTrayTextBalloon -Notify $script:ZCodeTrayNotify -Key 'BubbleCancelled'
          return
        }
        $result = Invoke-ZCodeTrayDoor -Action 'background' -ImagePath $dialog.FileName
        if ($result.ok) {
          Show-ZCodeTrayTextBalloon -Notify $script:ZCodeTrayNotify -Key 'BubbleBackgroundDraft' -Milliseconds 3000
        } else {
          Show-ZCodeTrayResultBalloon -Result $result -OkKey 'BubbleBackgroundDraft' -FailKey 'BubbleBackgroundRejected'
        }
      } catch {
        $null = Write-ZCodeTrayLog -Name 'background' -Text "$($_.Exception.Message)"
        Show-ZCodeTrayTextBalloon -Notify $script:ZCodeTrayNotify -Key 'BubbleBackgroundRejected' -AsError $true -Milliseconds 3000
      } finally { $trayBusy = $false }
    }
    ImportTheme = {
      if ($trayBusy) { return }
      $trayBusy = $true
      try {
        $dialog = New-Object System.Windows.Forms.OpenFileDialog
        $dialog.Title = Get-ZCodeTrayText -Key 'DialogZipTitle'
        $dialog.Filter = Get-ZCodeTrayText -Key 'DialogZipFilter'
        if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
          Show-ZCodeTrayTextBalloon -Notify $script:ZCodeTrayNotify -Key 'BubbleCancelled'
          return
        }
        $result = Invoke-ZCodeTrayDoor -Action 'import' -ImagePath $dialog.FileName
        if ($result.ok) {
          $name = ''
          if ($result.data -and $result.data.themeId) {
            $card = @( (Get-ZCodeThemeCatalog -StateRoot $root).cards | Where-Object { $_.themeId -ceq $result.data.themeId } )
            if ($card.Count -eq 1) { $name = [string]$card[0].name }
          }
          Show-ZCodeTrayTextBalloon -Notify $script:ZCodeTrayNotify -Key 'BubbleImported' -Milliseconds 3000 `
            -FormatArguments $(if ($name) { @($name) } else { @('') })
        } else {
          # A held import lock is its own answer: the person is told to try again shortly,
          # not that their package was rejected or that reading it failed.
          $key = if ($result.errorCode -ceq 'BUSY') { 'BubbleBusy' } elseif ($result.errorCode -ceq 'IMPORT_REJECTED') { 'BubbleZipRejected' } else { 'BubbleZipFailed' }
          Show-ZCodeTrayResultBalloon -Result $result -OkKey 'BubbleImported' -FailKey $key
        }
      } catch {
        $null = Write-ZCodeTrayLog -Name 'import' -Text "$($_.Exception.Message)"
        Show-ZCodeTrayTextBalloon -Notify $script:ZCodeTrayNotify -Key 'BubbleZipRejected' -AsError $true -Milliseconds 3000
      } finally { $trayBusy = $false }
    }
    SaveTheme = {
      if ($trayBusy) { return }
      $trayBusy = $true
      try {
        $name = [Microsoft.VisualBasic.Interaction]::InputBox((Get-ZCodeTrayText -Key 'MenuSaveTheme'), 'ZCode Dream Skin', '')
        if ([string]::IsNullOrWhiteSpace($name)) {
          Show-ZCodeTrayTextBalloon -Notify $script:ZCodeTrayNotify -Key 'BubbleCancelled'
          return
        }
        $result = Invoke-ZCodeTrayDoor -Action 'save' -Name $name
        Show-ZCodeTrayResultBalloon -Result $result -OkKey 'BubbleSaved' -FailKey 'BubbleSaveFailed'
      } catch {
        $null = Write-ZCodeTrayLog -Name 'save' -Text "$($_.Exception.Message)"
        Show-ZCodeTrayTextBalloon -Notify $script:ZCodeTrayNotify -Key 'BubbleSaveFailed' -AsError $true -Milliseconds 3000
      } finally { $trayBusy = $false }
    }
    OpenThemes = {
      Start-Process explorer.exe (Join-Path $root 'themes')
      Show-ZCodeTrayTextBalloon -Notify $script:ZCodeTrayNotify -Key 'BubbleDirectoryOpened' -FormatArguments @('themes')
    }
    OpenImages = {
      Start-Process explorer.exe (Join-Path $root 'images')
      Show-ZCodeTrayTextBalloon -Notify $script:ZCodeTrayNotify -Key 'BubbleDirectoryOpened' -FormatArguments @('images')
    }
    FullRestore = {
      if ($trayBusy) { return }
      $trayBusy = $true
      try {
        $result = Invoke-ZCodeTrayDoor -Action 'full'
        Show-ZCodeTrayResultBalloon -Result $result -OkKey 'BubbleFullRestore' -FailKey 'BubbleRestoreFailed'
      } finally { $trayBusy = $false }
    }
    Quit = {
      $script:ZCodeTrayExitRequested = $true
      $script:ZCodeTrayNotify.Visible = $false
      [System.Windows.Forms.Application]::Exit()
    }
  }
  return $actions
}

function Show-ZCodeTrayResultBalloon {
  <#
  Success and failure share one shape so a code is never dropped: the bubble gets a
  short Chinese sentence, the log keeps the machine code and whatever the child said.
  #>
  param(
    $Result,
    [Parameter(Mandatory = $true)][string]$OkKey,
    [Parameter(Mandatory = $true)][string]$FailKey,
    [object[]]$OkArguments = @()
  )
  $notify = $script:ZCodeTrayNotify
  if ($Result.ok) {
    Show-ZCodeTrayTextBalloon -Notify $notify -Key $OkKey -FormatArguments $OkArguments
    return
  }
  $diagnostic = [string]$Result.errorCode
  if ($Result.message) { $null = Write-ZCodeTrayLog -Name 'tray-action' -Text "$diagnostic $($Result.message)" }
  Show-ZCodeTrayTextBalloon -Notify $notify -Key $FailKey -AsError $true -Milliseconds 3000 -Diagnostic $diagnostic
}

function Initialize-ZCodeTraySurface {
  <#
  Creates the NotifyIcon and the menu. Separated from the loop so a test can inspect
  what the user would see without ever entering Application.Run.
  #>
  [CmdletBinding()]
  param(
    [scriptblock]$NewActionImplementations = $null,
    [scriptblock]$StatusProbe = $null,
    [scriptblock]$DraftProbe = $null
  )
  Add-Type -AssemblyName System.Windows.Forms
  Add-Type -AssemblyName System.Drawing
  # InputBox lives in the VisualBasic assembly: loading it explicitly keeps "Save
  # current theme" working instead of failing the first time it is used.
  Add-Type -AssemblyName Microsoft.VisualBasic

  $actions = Get-ZCodeTrayActions
  $notify = New-Object System.Windows.Forms.NotifyIcon
  $notify.Text = 'ZCode Dream Skin'
  $notify.Icon = [System.Drawing.SystemIcons]::Application
  # Hidden until the loop owns it, so loading this file never puts an icon on screen.
  $notify.Visible = $false
  # Published as soon as it exists: the menu handlers reach the icon through the
  # script-scope handle, not through a function local that is already gone.
  $script:ZCodeTrayNotify = $notify
  $menu = New-Object System.Windows.Forms.ContextMenuStrip
  $notify.ContextMenuStrip = $menu

  if ($NewActionImplementations) { $actions = & $NewActionImplementations $actions }

  $statusResult = if ($StatusProbe) { & $StatusProbe } else { $null }
  $statusText = Get-ZCodeTrayStatusText -DoorResult $statusResult
  $draft = if ($DraftProbe) { & $DraftProbe } else { Get-ZCodeTrayDraftState }
  $items = New-ZCodeTrayMenu -Actions $actions -Menu $menu -StatusText $statusText `
    -ShowApplyChanges $([bool]$draft)
  return [pscustomobject]@{ Notify = $notify; Menu = $menu; Items = $items; Actions = $actions }
}

function Start-ZCodeDreamSkinTray {
  <#
  The real tray: own the mutex, show the icon, run the WinForms loop, and release the
  icon and the mutex in a finally so a throwing menu action cannot leave either
  behind.
  #>
  [CmdletBinding()]
  param(
    [scriptblock]$RunLoop = $null,
    [scriptblock]$NewActionImplementations = $null
  )
  if (-not $script:ZCodeTrayMutex.WaitOne(0)) { return 0 }
  $script:ZCodeTrayMutexHeld = $true
  try {
    $surface = Initialize-ZCodeTraySurface -NewActionImplementations $NewActionImplementations `
      -StatusProbe { return (Invoke-ZCodeTrayDoor -Action 'status') }
    $script:ZCodeTrayNotify = $surface.Notify
    $script:ZCodeTrayMenu = $surface.Menu
    $notify = $surface.Notify
    $notify.Visible = $true
    # Published only once the mutex is ours: the marker is an address, and an address
    # handed out by a tray that never got the lock would misdirect a stop request.
    $null = Write-ZCodeTrayInstanceMarker -StateRoot $root -InstanceId $script:ZCodeTrayInstanceId `
      -ProcessId ([int]$PID) -ScriptPath ((Join-Path $PSScriptRoot 'tray-zcode-dream-skin.ps1'))

    $context = New-Object System.Windows.Forms.ApplicationContext
    $stopTimer = New-Object System.Windows.Forms.Timer
    $stopTimer.Interval = 250
    $stopTimer.Add_Tick({
      # Only requests addressed to this instance are handled, and each is removed by
      # this process alone: a queue a dead tray left behind cannot accumulate into a
      # verdict about a live one.
      $pending = Get-ZCodeTrayStopRequest -StateRoot $root -InstanceId $script:ZCodeTrayInstanceId
      if ($pending.legacyRequestPresent -and -not $script:ZCodeTrayLegacyReported) {
        $script:ZCodeTrayLegacyReported = $true
        $null = Write-ZCodeTrayLog -Name 'tray-legacy-stop-request' -Text `
          'a legacy unaddressed tray-stop.request exists; it is left in place and is not acted on'
      }
      foreach ($request in @($pending.requests)) {
        $null = Complete-ZCodeTrayStopRequest -StateRoot $root -InstanceId $script:ZCodeTrayInstanceId `
          -RequestId $request.RequestId
        $script:ZCodeTrayExitRequested = $true
        if ($script:ZCodeTrayNotify) { $script:ZCodeTrayNotify.Visible = $false }
        [System.Windows.Forms.Application]::Exit()
        return
      }
    })
    try {
      $stopTimer.Start()
      if ($RunLoop) { & $RunLoop $context } else { [System.Windows.Forms.Application]::Run($context) }
    } finally {
      $stopTimer.Stop()
      $stopTimer.Dispose()
      $notify.Visible = $false
      $notify.Dispose()
      $script:ZCodeTrayNotify = $null
      # Only my own address is withdrawn: if another tray has taken over meanwhile,
      # its marker stays valid and its requests still reach it.
      $null = Remove-ZCodeTrayInstanceMarker -StateRoot $root -InstanceId $script:ZCodeTrayInstanceId
    }
    return 0
  } finally {
    if ($script:ZCodeTrayMutexHeld) {
      $script:ZCodeTrayMutex.ReleaseMutex()
      $script:ZCodeTrayMutexHeld = $false
    }
    $script:ZCodeTrayMutex.Dispose()
  }
}

if ($MyInvocation.InvocationName -ne '.') {
  exit (Start-ZCodeDreamSkinTray)
}
