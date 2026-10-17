<#
ZCode Dream Skin 2.0 tray wording.

One table, owned by the ZCode product. The upstream dictionary already carries Chinese
for the Codex tray, but its strings name Codex ("完全恢复 Codex") and its menus are not
this product's menus, so reusing them wholesale would put another client's name in
front of the user. Keys that genuinely mean the same thing are delegated to the shared
dictionary; everything the user can click or read that is ZCode-specific lives here.

Callers must never build a sentence out of a machine code: the code travels in a
separate diagnostic field so a Chinese bubble stays short and readable.
#>

$script:ZCodeTrayTextVersion = 'zcode-tray-text/1'

$script:ZCodeTrayText = @{
  # 菜单
  MenuApply            = '应用皮肤'
  MenuPause            = '暂停皮肤'
  MenuResume           = '恢复皮肤'
  MenuOpenGallery      = '打开皮肤库…'
  MenuQuickSwitch      = '快速换肤'
  MenuUseDefault       = '使用默认外观'
  MenuRestoreSkin      = '恢复所选皮肤'
  MenuChangeBackground = '更换背景…'
  MenuApplyChanges     = '应用当前更改'
  MenuImportZip        = '导入皮肤 ZIP…'
  MenuSaveTheme        = '保存当前皮肤…'
  # 快照状态说明：图库卡片用它表达"正在用的是更早的那一版"
  SnapshotStaleChanged     = '此前版本（原主题已在此确认后变更）'
  SnapshotStaleUnreadable  = '此前版本（原主题当前不可读）'
  SnapshotStaleMissing     = '此前版本（原主题目录已不在）'
  MenuSwitchTheme      = '切换已保存皮肤'
  MenuOpenThemes       = '打开主题文件夹'
  MenuOpenImages       = '打开图片文件夹'
  MenuFullRestore      = '完整恢复并重启 ZCode…'
  MenuQuitTray         = '退出托盘'
  MenuCheckUpdate      = '检查更新…'
  MenuNoSavedThemes    = '（暂无已保存皮肤）'
  MenuDefaultCard      = '默认外观'

  # 状态行
  StatusAppearance     = '外观：{0}'
  StatusNative         = '默认外观'
  StatusPending        = '外观状态待确认'

  # 对话框
  DialogImageTitle     = '选择背景图片'
  DialogImageFilter    = '图片文件|*.png;*.jpg;*.jpeg;*.webp|所有文件|*.*'
  DialogZipTitle       = '选择皮肤压缩包'
  DialogZipFilter      = 'ZIP 文件|*.zip|所有文件|*.*'

  # 气泡：成功
  BubbleApplied        = '皮肤已应用'
  BubblePaused         = '皮肤已暂停，ZCode 继续运行'
  BubbleResumed        = '皮肤已恢复'
  BubbleNativeOn       = '已切到默认外观'
  BubbleBackgroundDraft = '背景已选择，点击「应用当前更改」后生效'
  BubbleSaved          = '已保存当前皮肤'
  BubbleImported       = '已导入：{0}（当前外观未改变）'
  BubbleSwitched       = '皮肤已切换'
  BubbleGalleryOpened  = '皮肤库已打开'
  BubbleGalleryMissing = '皮肤库尚未安装，需先安装 2.0 候选包'
  BubbleDirectoryOpened = '已打开：{0}'
  BubbleFullRestore    = '已恢复官方外观并重启 ZCode'
  BubbleQuit           = '托盘已退出，皮肤与已保存内容保持不变'

  # 气泡：失败与取消（诊断码另走一个字段）
  BubbleCancelled      = '已取消，未改变任何内容'
  BubbleBusy           = '另一项外观操作正在进行，请稍后重试'
  BubbleApplyFailed    = '皮肤应用失败'
  BubblePauseFailed    = '暂停失败，状态已保留以便修复'
  BubbleResumeFailed   = '恢复皮肤失败'
  BubbleBackgroundRejected = '背景图未通过校验，已保持原样'
  BubbleZipRejected    = '皮肤包被拒绝'
  BubbleZipFailed      = '皮肤包读取失败'
  BubbleSaveFailed     = '皮肤保存失败'
  BubbleSwitchFailed   = '切换皮肤失败'
  BubbleRestoreFailed  = '完整恢复未完成'
  BubbleUnknown        = '操作未完成，请查看诊断信息'

  # 诊断码前缀（气泡里以「（码：X）」短附带，长文本进日志）
  DiagnosticSuffix     = '（码：{0}）'
}

function Get-ZCodeTrayText {
  <#
  Returns the Chinese text for a key, formatted with optional arguments. An unknown
  key is a programming error, not something to paper over with an empty bubble:
  it throws so a test or a tray log names the missing key immediately.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)][string]$Key,
    [object[]]$FormatArguments = @()
  )
  if (-not $script:ZCodeTrayText.ContainsKey($Key)) {
    throw "ZCODE_TRAY_TEXT_MISSING_KEY:$Key"
  }
  $text = [string]$script:ZCodeTrayText[$Key]
  if ($null -ne $FormatArguments -and @($FormatArguments).Count -gt 0) {
    $text = [string]::Format([System.Globalization.CultureInfo]::InvariantCulture, $text, $FormatArguments)
  }
  return $text
}

function Get-ZCodeTrayBubbleText {
  <#
  A user-facing sentence, with the diagnostic code appended in short form. The long
  exception text never travels here: it belongs in the tray log, not in a bubble the
  user has a few seconds to read.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)][string]$Key,
    [object[]]$FormatArguments = @(),
    [string]$Diagnostic = ''
  )
  $text = Get-ZCodeTrayText -Key $Key -FormatArguments $FormatArguments
  if ($Diagnostic) {
    $text += (Get-ZCodeTrayText -Key 'DiagnosticSuffix' -FormatArguments @($Diagnostic))
  }
  return $text
}

function Get-ZCodeTrayTextKeys {
  return @($script:ZCodeTrayText.Keys | Sort-Object)
}
