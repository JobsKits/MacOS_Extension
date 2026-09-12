--
--  SelectFinderExtensionFeatures.applescript
--  MacOS@Extension
--
--  Created by Jobs on 2026年9月13日，星期日.
--

use framework "AppKit"
use scripting additions

-- 创建一个默认勾选的 Finder 右键功能复选框。
on makeFeatureCheckbox(titleText, yPosition, containerView)
    set checkboxFrame to current application's NSMakeRect(0, yPosition, 520, 24)
    set featureCheckbox to current application's NSButton's alloc()'s initWithFrame:checkboxFrame
    featureCheckbox's setButtonType:(current application's NSButtonTypeSwitch)
    featureCheckbox's setTitle:titleText
    featureCheckbox's setState:(current application's NSControlStateValueOn)
    containerView's addSubview:featureCheckbox
    return featureCheckbox
end makeFeatureCheckbox

-- 创建用于区分两组功能的标题。
on makeGroupLabel(titleText, yPosition, containerView)
    set labelFrame to current application's NSMakeRect(0, yPosition, 520, 22)
    set groupLabel to current application's NSTextField's labelWithString:titleText
    groupLabel's setFrame:labelFrame
    groupLabel's setFont:(current application's NSFont's boldSystemFontOfSize:13)
    containerView's addSubview:groupLabel
end makeGroupLabel

-- 返回用户在原生复选框窗口中选择的功能标识。
on run
    current application's NSApplication's sharedApplication()'s activateIgnoringOtherApps:true
    set accessoryView to current application's NSView's alloc()'s initWithFrame:(current application's NSMakeRect(0, 0, 520, 274))
    my makeGroupLabel("独立 Finder 扩展", 246, accessoryView)
    set gitRemoteCheckbox to my makeFeatureCheckbox("打开 Git 远程地址", 218, accessoryView)
    set gitRemoteCopierCheckbox to my makeFeatureCheckbox("复制 Git 远程地址", 190, accessoryView)
    set pathCopierCheckbox to my makeFeatureCheckbox("复制绝对路径", 162, accessoryView)

    my makeGroupLabel("JobsTerminalOpener 内含功能", 130, accessoryView)
    set terminalOpenCheckbox to my makeFeatureCheckbox("用终端打开", 102, accessoryView)
    set podInstallCheckbox to my makeFeatureCheckbox("在终端执行 pod install", 78, accessoryView)
    set flutterPubGetCheckbox to my makeFeatureCheckbox("在终端执行 flutter pub get", 54, accessoryView)
    set codeGraphCheckbox to my makeFeatureCheckbox("安装/升级 CodeGraph 代码地图", 30, accessoryView)
    set gitEmptyCommitPushCheckbox to my makeFeatureCheckbox("在终端创建空白 Commit 并 Push", 6, accessoryView)

    set featureAlert to current application's NSAlert's alloc()'s init()
    featureAlert's setAlertStyle:(current application's NSAlertStyleInformational)
    featureAlert's setMessageText:"选择要安装的 Finder 右键功能"
    featureAlert's setInformativeText:"每个右键菜单功能都可以独立勾选；全部默认选中。"
    featureAlert's setAccessoryView:accessoryView
    featureAlert's addButtonWithTitle:"安装勾选项"
    featureAlert's addButtonWithTitle:"全部安装"
    featureAlert's addButtonWithTitle:"取消"

    set responseCode to featureAlert's runModal()
    if responseCode is current application's NSAlertThirdButtonReturn then return "__CANCELLED__"
    if responseCode is current application's NSAlertSecondButtonReturn then return "git_remote,git_remote_copier,path_copier,terminal_open,pod_install,flutter_pub_get,codegraph_bootstrap,git_empty_commit_push"

    set featureIdentifiers to {"git_remote", "git_remote_copier", "path_copier", "terminal_open", "pod_install", "flutter_pub_get", "codegraph_bootstrap", "git_empty_commit_push"}
    set featureCheckboxes to {gitRemoteCheckbox, gitRemoteCopierCheckbox, pathCopierCheckbox, terminalOpenCheckbox, podInstallCheckbox, flutterPubGetCheckbox, codeGraphCheckbox, gitEmptyCommitPushCheckbox}
    set selectedIdentifiers to {}
    repeat with featureIndex from 1 to count featureIdentifiers
        set featureCheckbox to item featureIndex of featureCheckboxes
        if (featureCheckbox's state()) as integer is (current application's NSControlStateValueOn as integer) then
            set end of selectedIdentifiers to item featureIndex of featureIdentifiers
        end if
    end repeat

    if (count selectedIdentifiers) is 0 then return "__NONE__"
    set originalDelimiters to AppleScript's text item delimiters
    set AppleScript's text item delimiters to ","
    set selectedOutput to selectedIdentifiers as text
    set AppleScript's text item delimiters to originalDelimiters
    return selectedOutput
end run
