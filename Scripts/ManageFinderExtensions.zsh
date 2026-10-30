#!/bin/zsh
# shell: zsh
# 脚本自述：
# - 脚本名称：ManageFinderExtensions.zsh（App 内部后台管理器）
# - 核心用途：在同一分组面板安装、更新或按项卸载 Finder 功能；未选中的菜单保留。
# - 影响范围：安装构建并登记所选扩展；卸载只关闭所选叶子，最后一项移除后卸载该扩展；刷新 Finder。
# - 运行提示：直接打开原生管理面板，后台执行；同名 .app 入口不启动 Terminal。

# ━━━━━━━━━━ 维护索引：面板 → 叶 ID → 安装单元 → 菜单 → 宿主业务 ━━━━━━━━━━
# 1、面板来源：Scripts/SelectFinderExtensionFeatures.swift 的 FeatureOption.all 与 FeatureGroup.all。
# 2、下方 SELECTABLE_FUNCTION_TITLE/PROJECT_KEY 将面板 leaf ID 映射到唯一安装单元；
#    parse_feature_selection 保留逐叶选择并去重工程，install_feature 负责分发。
# 3、IDE/Git：project-tools → JobsProjectTools/Shared/ProjectMenuAction.swift →
#    JobsProjectToolsFinderSync/FinderSync.swift → AppDelegate.swift；配置在真实账户 Home
#    的 Library/Application Support/JobsProjectTools/EnabledFeatures.txt。
#    git-sourcetree 已移除；旧 ID 只保留卸载兼容，不在管理面板或右键菜单显示。
# 4、桌面：desktop-tools → JobsDesktopTools/Shared/DesktopMenuAction/DesktopMenuAction.swift。
#    固定顺序：ios-simulator-create → android-simulator-create → harmony-simulator-create →
#    android-simulator-repair → harmony-simulator-repair → hidden-files-toggle。
#    JobsDesktopToolsFinderSync/FinderSync.swift 一次生成同一 NSMenu，前三项因此始终相邻；
#    普通目录背景仅保留隐藏开关，不显示模拟器；不控制本仓以外的菜单插入位置。
#    JobsDesktopTools/AppDelegate.swift → DesktopActionExecutor → Core 中的原功能启动器，
#    Resource/ 的五份完整脚本逐字节来源见 SourceManifest.json；隐藏开关使用本包 CFPreferences。
#    六个旧 leaf ID 和独立安装/卸载入口保持兼容，统一转交 Scripts/ManageDesktopTools.zsh。
#    配置：真实账户 Home/Library/Application Support/JobsDesktopTools/EnabledFeatures.txt；
#    首次迁移仅带入 PlugInKit 明确启用的旧叶，安装取并集、卸载只去掉指定项。
#    产物：JobsDesktopTools/work/DerivedData/Build/Products/Debug/JobsDesktopTools.app，
#    内嵌 JobsDesktopToolsFinderSync.appex；每次仅构建注册一次，失败恢复配置和旧状态。
# 5、Flutter：flutter-tools → JobsFlutterToolsFinderSync/FinderSync.swift，按共享动作表分发；
#    精确选择写 JobsFinderExtensions/flutter-tools-features.conf，不依赖原脚本仓运行。
# 6、iOS：ios-tools → JobsIOSToolsFinderSync/FinderSync.swift → AppDelegate/IOSToolsLauncher；
#    脚本位于 JobsIOSTools/Scripts/Tools；Terminal 仍由 terminal_opener 单元承接通用动作。
#    file_content → file-content → JobsTerminalOpener 的 FinderSync / TerminalOpener →
#    file_merge/file_split → file-merge/file-split → 同一宿主 Scripts/FileVolumes.zsh；
#    多选完整组才合并，单个普通文件才拆分；两动作各自开关且保留兄弟配置。
#    Scripts/ViewFileContent.zsh；只读普通单文件，终端内按阈值确认，不和打开所在目录混用。
# 7、其它单元：FEATURE_PROJECT_DIR/SCHEME/APP/EXTENSION 各表决定工程与身份；
#    file-create → JobsFileCreator，FinderSync 仅接收桌面/普通目录背景，点击时复核目录；
#    Shared/FileCreationRequest → 宿主 AppDelegate/FileCreationController → FileCreationService；
#    原生输入文件名，排他创建空文件后 Finder 定位，不覆盖已有文件；无额外持久配置。
#    产物：JobsFileCreator/work/DerivedData/Build/Products/Debug/JobsFileCreator.app，
#    宿主 com.jobs.filecreator，扩展 com.jobs.filecreator.findersync；独立管理器仅处理该项。
#    同项目 FinderSync 是菜单文字/资格/置灰入口，宿主 Model/Launcher 与 Scripts 是执行入口。
#    图标改菜单显示标题，不改 leaf ID/URL/资源名；增加功能同时核对选择器、安装、卸载和测试。
#    标题未命中时先追 leaf ID/旧别名，再查 PlugInKit 实际登记路径与 Bundle ID，
#    最后对照 Git 历史；不能仅凭当前文字搜索排除旧安装产物。
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# 仅渲染自述：标题红色加粗，编号正文蓝色常规字重；非彩色终端输出纯文本。
jobs_intro_style() {
  local intro_color=0
  if [ -t 1 ] && [ -n "${TERM:-}" ] && [ "${TERM:-}" != dumb ] &&
     [ -z "${NO_COLOR+x}" ] && [ "${PLAIN_OUTPUT:-0}" != 1 ] &&
     [ "${IS_SOURCETREE_RUNTIME:-0}" != 1 ]; then
    intro_color=1
  fi
  /usr/bin/awk -v color="$intro_color" -v role="${1:-body}" '
    BEGIN { esc = sprintf("%c", 27) }
    {
      gsub(esc "\\[[0-9;]*m", "")
      gsub(/\\(033|e|x1[bB])\[[0-9;]*m/, "")
      if (!color || $0 ~ /^[[:space:]]*$/) { print; next }
      numbered = ($0 ~ /^[[:space:]➤ℹ🔹✔⚠]*([0-9]+[、.)）]|[0-9]+️⃣|[-•])/)
      heading = ($0 ~ /^[[:space:]]*#{1,6}[[:space:]]/ || $0 ~ /[：:][[:space:]]*$/ || $0 ~ /^[[:space:]]*[=━─-]{3}/)
      title = (!numbered && (role == "title" || heading))
      if (role == "auto" && !seen && !numbered) title = 1
      if ($0 !~ /^[[:space:]]*[=━─-]+[[:space:]]*$/) seen = 1
      printf "%s%s%s\n", esc (title ? "[1;31m" : "[0;34m"), $0, esc "[0m"
    }
  '
}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")" && pwd)"
SCRIPT_PATH="${SCRIPT_DIR}/$(basename -- "$0")"
WORKSPACE_DIR="${SCRIPT_DIR:h}"
SCRIPT_BASENAME="【MacOS】🧩管理Finder扩展"
LOG_FILE="${TMPDIR:-/tmp/}${SCRIPT_BASENAME}.log"
BUILD_CONFIGURATION="Debug"
FEATURE_SELECTOR_SOURCE_PATH="${WORKSPACE_DIR}/Scripts/SelectFinderExtensionFeatures.swift"
FEATURE_SELECTOR_BINARY_PATH="${WORKSPACE_DIR}/work/SelectFinderExtensionFeatures"
TERMINAL_FEATURE_CONFIG_DIR=""
TERMINAL_FEATURE_CONFIG_PATH=""
IOS_FEATURE_CONFIG_DIR=""
IOS_FEATURE_CONFIG_PATH=""
FLUTTER_FEATURE_CONFIG_DIR=""
FLUTTER_FEATURE_CONFIG_PATH=""
FINAL_EXIT_STATUS=0
SELECTED_KEYS=()
SELECTED_FUNCTION_IDS=()
SUCCEEDED_FEATURES=()
FAILED_FEATURES=()
REGISTERED_PATHS=()
TERMINAL_OPENER_ENABLED_FEATURES=""
IOS_TOOLS_ENABLED_FEATURES=""
IOS_EXISTING_DEFAULT_FEATURES=""
FLUTTER_TOOLS_ENABLED_FEATURES=""
MANAGEMENT_ACTION="install"
FEATURE_SCOPE=""
CLI_FEATURES=""
MANAGER_NON_INTERACTIVE=0
MANAGER_GUI_SESSION=0
REMAINING_CONFIG_FEATURES=""

FEATURE_KEYS=(project-tools path_copier file-create run-authorize run-revoke ipa-resign desktop-tools flutter-tools terminal_opener ios-tools)
typeset -A FEATURE_TITLE
typeset -A FEATURE_PROJECT_DIR
typeset -A FEATURE_SCHEME
typeset -A FEATURE_APP_NAME
typeset -A FEATURE_APP_ID
typeset -A FEATURE_EXTENSION_NAME
typeset -A FEATURE_EXTENSION_ID
typeset -A SELECTABLE_FUNCTION_TITLE
typeset -A SELECTABLE_FUNCTION_PROJECT_KEY
typeset -A SELECTABLE_FUNCTION_TERMINAL_ACTION
typeset -A SELECTABLE_FUNCTION_FLUTTER_ACTION

# 桌面六个可选叶共用一个扩展，以单菜单生成固定顺序；旧工程映射保留用于兼容诊断。
FEATURE_TITLE[desktop-tools]="桌面模拟器与文件显示工具"
FEATURE_PROJECT_DIR[desktop-tools]="JobsDesktopTools"
FEATURE_SCHEME[desktop-tools]="JobsDesktopTools"
FEATURE_APP_NAME[desktop-tools]="JobsDesktopTools"
FEATURE_APP_ID[desktop-tools]="com.jobs.desktoptools"
FEATURE_EXTENSION_NAME[desktop-tools]="JobsDesktopToolsFinderSync.appex"
FEATURE_EXTENSION_ID[desktop-tools]="com.jobs.desktoptools.findersync"

FEATURE_TITLE[project-tools]="IDE 项目工具 / Git操作"
FEATURE_PROJECT_DIR[project-tools]="JobsProjectTools"
FEATURE_SCHEME[project-tools]="JobsProjectTools"
FEATURE_APP_NAME[project-tools]="JobsProjectTools"
FEATURE_EXTENSION_NAME[project-tools]="JobsProjectToolsFinderSync.appex"
FEATURE_EXTENSION_ID[project-tools]="com.jobs.JobsProjectTools.FinderSyncExtension"

FEATURE_TITLE[git_remote]="打开 Git 远程地址"
FEATURE_PROJECT_DIR[git_remote]="JobsGitRemoteOpener"
FEATURE_SCHEME[git_remote]="JobsGitRemoteOpener"
FEATURE_APP_NAME[git_remote]="JobsGitRemoteOpener"
FEATURE_EXTENSION_NAME[git_remote]="JobsGitRemoteFinderSync.appex"
FEATURE_EXTENSION_ID[git_remote]="com.jobs.JobsGitRemoteOpener.FinderSyncExtension"

FEATURE_TITLE[git_remote_copier]="复制 Git 远程地址"
FEATURE_PROJECT_DIR[git_remote_copier]="JobsGitRemoteCopier"
FEATURE_SCHEME[git_remote_copier]="JobsGitRemoteCopier"
FEATURE_APP_NAME[git_remote_copier]="JobsGitRemoteCopier"
FEATURE_EXTENSION_NAME[git_remote_copier]="JobsGitRemoteCopyFinderSync.appex"
FEATURE_EXTENSION_ID[git_remote_copier]="com.jobs.JobsGitRemoteCopier.FinderSyncExtension"

FEATURE_TITLE[path_copier]="复制绝对路径"
FEATURE_PROJECT_DIR[path_copier]="JobsPathCopier"
FEATURE_SCHEME[path_copier]="JobsPathCopier"
FEATURE_APP_NAME[path_copier]="JobsPathCopier"
FEATURE_EXTENSION_NAME[path_copier]="JobsPathCopyFinderSync.appex"
FEATURE_EXTENSION_ID[path_copier]="com.jobs.JobsPathCopier.FinderSyncExtension"

FEATURE_TITLE[file-create]="新建文件"
FEATURE_PROJECT_DIR[file-create]="JobsFileCreator"
FEATURE_SCHEME[file-create]="JobsFileCreator"
FEATURE_APP_NAME[file-create]="JobsFileCreator"
FEATURE_APP_ID[file-create]="com.jobs.filecreator"
FEATURE_EXTENSION_NAME[file-create]="JobsFileCreatorFinderSync.appex"
FEATURE_EXTENSION_ID[file-create]="com.jobs.filecreator.findersync"

FEATURE_TITLE[run-authorize]="运行授权"
FEATURE_PROJECT_DIR[run-authorize]="JobsRunAuthorizer"
FEATURE_SCHEME[run-authorize]="JobsRunAuthorizer"
FEATURE_APP_NAME[run-authorize]="JobsRunAuthorizer"
FEATURE_APP_ID[run-authorize]="com.jobs.JobsRunAuthorizer"
FEATURE_EXTENSION_NAME[run-authorize]="JobsRunAuthorizerFinderSync.appex"
FEATURE_EXTENSION_ID[run-authorize]="com.jobs.JobsRunAuthorizer.FinderSyncExtension"

FEATURE_TITLE[run-revoke]="解除运行授权"
FEATURE_PROJECT_DIR[run-revoke]="JobsRunAuthorizationRevoker"
FEATURE_SCHEME[run-revoke]="JobsRunAuthorizationRevoker"
FEATURE_APP_NAME[run-revoke]="JobsRunAuthorizationRevoker"
FEATURE_APP_ID[run-revoke]="com.jobs.JobsRunAuthorizationRevoker"
FEATURE_EXTENSION_NAME[run-revoke]="JobsRunAuthorizationRevokerFinderSync.appex"
FEATURE_EXTENSION_ID[run-revoke]="com.jobs.JobsRunAuthorizationRevoker.FinderSyncExtension"

FEATURE_TITLE[ipa-resign]="IPA 免编译重签"
FEATURE_PROJECT_DIR[ipa-resign]="JobsIPAResigner"
FEATURE_SCHEME[ipa-resign]="JobsIPAResigner"
FEATURE_APP_NAME[ipa-resign]="JobsIPAResigner"
FEATURE_APP_ID[ipa-resign]="com.jobs.JobsIPAResigner"
FEATURE_EXTENSION_NAME[ipa-resign]="JobsIPAResignerFinderSync.appex"
FEATURE_EXTENSION_ID[ipa-resign]="com.jobs.JobsIPAResigner.FinderSyncExtension"

FEATURE_TITLE[xcode_opener]="用 Xcode 打开项目"
FEATURE_PROJECT_DIR[xcode_opener]="JobsXcodeOpener"
FEATURE_SCHEME[xcode_opener]="JobsXcodeOpener"
FEATURE_APP_NAME[xcode_opener]="JobsXcodeOpener"
FEATURE_EXTENSION_NAME[xcode_opener]="JobsXcodeFinderSync.appex"
FEATURE_EXTENSION_ID[xcode_opener]="com.jobs.JobsXcodeOpener.FinderSyncExtension"

FEATURE_TITLE[vscode_opener]="用 VSCode 打开项目"
FEATURE_PROJECT_DIR[vscode_opener]="JobsVSCodeOpener"
FEATURE_SCHEME[vscode_opener]="JobsVSCodeOpener"
FEATURE_APP_NAME[vscode_opener]="JobsVSCodeOpener"
FEATURE_EXTENSION_NAME[vscode_opener]="JobsVSCodeFinderSync.appex"
FEATURE_EXTENSION_ID[vscode_opener]="com.jobs.JobsVSCodeOpener.FinderSyncExtension"

FEATURE_TITLE[android_studio_opener]="用 Android Studio 打开项目"
FEATURE_PROJECT_DIR[android_studio_opener]="JobsAndroidStudioOpener"
FEATURE_SCHEME[android_studio_opener]="JobsAndroidStudioOpener"
FEATURE_APP_NAME[android_studio_opener]="JobsAndroidStudioOpener"
FEATURE_EXTENSION_NAME[android_studio_opener]="JobsAndroidStudioFinderSync.appex"
FEATURE_EXTENSION_ID[android_studio_opener]="com.jobs.JobsAndroidStudioOpener.FinderSyncExtension"

FEATURE_TITLE[flutter_version_manager]="安装/切换 Flutter SDK（FVM）"
FEATURE_PROJECT_DIR[flutter_version_manager]="JobsFlutterVersionMgr"
FEATURE_SCHEME[flutter_version_manager]="JobsFlutterVersionMgr"
FEATURE_APP_NAME[flutter_version_manager]="JobsFlutterVersionMgr"
FEATURE_EXTENSION_NAME[flutter_version_manager]="JobsFlutterVersionFinderSync.appex"
FEATURE_EXTENSION_ID[flutter_version_manager]="com.jobs.JobsFlutterVersionMgr.FinderSyncExtension"

FEATURE_TITLE[flutter_sdk_version]="查看当前 Flutter SDK 版本"
FEATURE_PROJECT_DIR[flutter_sdk_version]="JobsFlutterSdkInspector"
FEATURE_SCHEME[flutter_sdk_version]="JobsFlutterSdkInspector"
FEATURE_APP_NAME[flutter_sdk_version]="JobsFlutterSdkInspector"
FEATURE_EXTENSION_NAME[flutter_sdk_version]="JobsFlutterSdkInspectorFinderSync.appex"
FEATURE_EXTENSION_ID[flutter_sdk_version]="com.jobs.JobsFlutterSdkInspector.FinderSyncExtension"

FEATURE_TITLE[git-pull]="拉取 Git 到最新"
FEATURE_PROJECT_DIR[git-pull]="JobsGitPuller"
FEATURE_SCHEME[git-pull]="JobsGitPuller"
FEATURE_APP_NAME[git-pull]="JobsGitPuller"
FEATURE_EXTENSION_NAME[git-pull]="JobsGitPullFinderSync.appex"
FEATURE_EXTENSION_ID[git-pull]="com.jobs.JobsGitPuller.FinderSyncExtension"

FEATURE_TITLE[flutter-dependency-extract]="提取 Flutter 第三方依赖"
FEATURE_PROJECT_DIR[flutter-dependency-extract]="JobsFlutterDependencyExtractor"
FEATURE_SCHEME[flutter-dependency-extract]="JobsFlutterDependencyExtractor"
FEATURE_APP_NAME[flutter-dependency-extract]="JobsFlutterDependencyExtractor"
FEATURE_EXTENSION_NAME[flutter-dependency-extract]="JobsFlutterDependencyFinderSync.appex"
FEATURE_EXTENSION_ID[flutter-dependency-extract]="com.jobs.JobsFlutterDependencyExtractor.FinderSync"

FEATURE_TITLE[flutter-run]="从终端运行 Flutter 项目"
FEATURE_PROJECT_DIR[flutter-run]="JobsFlutterRunner"
FEATURE_SCHEME[flutter-run]="JobsFlutterRunner"
FEATURE_APP_NAME[flutter-run]="JobsFlutterRunner"
FEATURE_EXTENSION_NAME[flutter-run]="JobsFlutterRunFinderSync.appex"
FEATURE_EXTENSION_ID[flutter-run]="com.jobs.JobsFlutterRunner.FinderSyncExtension"

FEATURE_TITLE[flutter-package]="Flutter打包"
FEATURE_PROJECT_DIR[flutter-package]="JobsFlutterPackager"
FEATURE_SCHEME[flutter-package]="JobsFlutterPackager"
FEATURE_APP_NAME[flutter-package]="JobsFlutterPackager"
FEATURE_EXTENSION_NAME[flutter-package]="JobsFlutterPackagerFinderSync.appex"
FEATURE_EXTENSION_ID[flutter-package]="com.jobs.JobsFlutterPackager.findersync"

FEATURE_TITLE[flutter-doctor]="Flutter 项目体检"
FEATURE_PROJECT_DIR[flutter-doctor]="JobsFlutterDoctor"
FEATURE_SCHEME[flutter-doctor]="JobsFlutterDoctor"
FEATURE_APP_NAME[flutter-doctor]="JobsFlutterDoctor"
FEATURE_EXTENSION_NAME[flutter-doctor]="JobsFlutterDoctorFinderSync.appex"
FEATURE_EXTENSION_ID[flutter-doctor]="com.jobs.JobsFlutterDoctor.FinderSyncExtension"

FEATURE_TITLE[flutter-codegen]="Flutter 自动化生产代码"
FEATURE_PROJECT_DIR[flutter-codegen]="JobsFlutterCodegen"
FEATURE_SCHEME[flutter-codegen]="JobsFlutterCodegen"
FEATURE_APP_NAME[flutter-codegen]="JobsFlutterCodegen"
FEATURE_EXTENSION_NAME[flutter-codegen]="JobsFlutterCodegenFinderSync.appex"
FEATURE_EXTENSION_ID[flutter-codegen]="com.jobs.JobsFlutterCodegen.FinderSyncExtension"

FEATURE_TITLE[ios-simulator-create]="新建 iOS 模拟器"
FEATURE_PROJECT_DIR[ios-simulator-create]="JobsIOSSimulatorCreator"
FEATURE_SCHEME[ios-simulator-create]="JobsIOSSimulatorCreator"
FEATURE_APP_NAME[ios-simulator-create]="JobsIOSSimulatorCreator"
FEATURE_APP_ID[ios-simulator-create]="com.jobs.iossimulatorcreator"
FEATURE_EXTENSION_NAME[ios-simulator-create]="JobsIOSSimulatorFinderSync.appex"
FEATURE_EXTENSION_ID[ios-simulator-create]="com.jobs.iossimulatorcreator.findersync"

FEATURE_TITLE[android-simulator-create]="新建 Android 模拟器"
FEATURE_PROJECT_DIR[android-simulator-create]="JobsAndroidSimulatorCreator"
FEATURE_SCHEME[android-simulator-create]="JobsAndroidSimulatorCreator"
FEATURE_APP_NAME[android-simulator-create]="JobsAndroidSimulatorCreator"
FEATURE_APP_ID[android-simulator-create]="com.jobs.androidsimulatorcreator"
FEATURE_EXTENSION_NAME[android-simulator-create]="JobsAndroidSimulatorFinderSync.appex"
FEATURE_EXTENSION_ID[android-simulator-create]="com.jobs.androidsimulatorcreator.findersync"

FEATURE_TITLE[android-simulator-repair]="Android 模拟器检测与修复"
FEATURE_PROJECT_DIR[android-simulator-repair]="JobsAndroidSimulatorRepairer"
FEATURE_SCHEME[android-simulator-repair]="JobsAndroidSimulatorRepairer"
FEATURE_APP_NAME[android-simulator-repair]="JobsAndroidSimulatorRepairer"
FEATURE_APP_ID[android-simulator-repair]="com.jobs.androidsimulatorrepairer"
FEATURE_EXTENSION_NAME[android-simulator-repair]="JobsAndroidSimulatorRepairFinderSync.appex"
FEATURE_EXTENSION_ID[android-simulator-repair]="com.jobs.androidsimulatorrepairer.findersync"

FEATURE_TITLE[harmony-simulator-create]="新建 Harmony 模拟器"
FEATURE_PROJECT_DIR[harmony-simulator-create]="JobsHarmonySimulatorCreator"
FEATURE_SCHEME[harmony-simulator-create]="JobsHarmonySimulatorCreator"
FEATURE_APP_NAME[harmony-simulator-create]="JobsHarmonySimulatorCreator"
FEATURE_APP_ID[harmony-simulator-create]="com.jobs.harmonysimulatorcreator"
FEATURE_EXTENSION_NAME[harmony-simulator-create]="JobsHarmonySimulatorFinderSync.appex"
FEATURE_EXTENSION_ID[harmony-simulator-create]="com.jobs.harmonysimulatorcreator.findersync"

FEATURE_TITLE[harmony-simulator-repair]="Harmony 模拟器检测与修复"
FEATURE_PROJECT_DIR[harmony-simulator-repair]="JobsHarmonySimulatorRepairer"
FEATURE_SCHEME[harmony-simulator-repair]="JobsHarmonySimulatorRepairer"
FEATURE_APP_NAME[harmony-simulator-repair]="JobsHarmonySimulatorRepairer"
FEATURE_APP_ID[harmony-simulator-repair]="com.jobs.harmonysimulatorrepairer"
FEATURE_EXTENSION_NAME[harmony-simulator-repair]="JobsHarmonySimulatorRepairFinderSync.appex"
FEATURE_EXTENSION_ID[harmony-simulator-repair]="com.jobs.harmonysimulatorrepairer.findersync"

FEATURE_TITLE[git-proxy-configure]="配置 Git 动态代理"
FEATURE_PROJECT_DIR[git-proxy-configure]="JobsGitProxyConfigurator"
FEATURE_SCHEME[git-proxy-configure]="JobsGitProxyConfigurator"
FEATURE_APP_NAME[git-proxy-configure]="JobsGitProxyConfigurator"
FEATURE_APP_ID[git-proxy-configure]="com.jobs.gitproxyconfigurator"
FEATURE_EXTENSION_NAME[git-proxy-configure]="JobsGitProxyFinderSync.appex"
FEATURE_EXTENSION_ID[git-proxy-configure]="com.jobs.gitproxyconfigurator.findersync"

FEATURE_TITLE[hidden-files-toggle]="显示 / 隐藏文件"
FEATURE_PROJECT_DIR[hidden-files-toggle]="JobsHiddenFilesToggler"
FEATURE_SCHEME[hidden-files-toggle]="JobsHiddenFilesToggler"
FEATURE_APP_NAME[hidden-files-toggle]="JobsHiddenFilesToggler"
FEATURE_APP_ID[hidden-files-toggle]="com.jobs.hiddenfilestoggler"
FEATURE_EXTENSION_NAME[hidden-files-toggle]="JobsHiddenFilesFinderSync.appex"
FEATURE_EXTENSION_ID[hidden-files-toggle]="com.jobs.hiddenfilestoggler.findersync"

FEATURE_TITLE[flutter-tools]="Flutter开发相关辅助工具 / Flutter项目修复"
FEATURE_PROJECT_DIR[flutter-tools]="JobsFlutterTools"
FEATURE_SCHEME[flutter-tools]="JobsFlutterTools"
FEATURE_APP_NAME[flutter-tools]="JobsFlutterTools"
FEATURE_APP_ID[flutter-tools]="com.jobs.JobsFlutterTools"
FEATURE_EXTENSION_NAME[flutter-tools]="JobsFlutterToolsFinderSync.appex"
FEATURE_EXTENSION_ID[flutter-tools]="com.jobs.JobsFlutterTools.FinderSyncExtension"
SELECTABLE_FUNCTION_TITLE[flutter-tools]="Flutter开发相关辅助工具 / Flutter项目修复"
SELECTABLE_FUNCTION_PROJECT_KEY[flutter-tools]="flutter-tools"

FEATURE_TITLE[terminal_opener]="JobsTerminalOpener"
FEATURE_PROJECT_DIR[terminal_opener]="JobsTerminalOpener"
FEATURE_SCHEME[terminal_opener]="JobsTerminalOpener"
FEATURE_APP_NAME[terminal_opener]="JobsTerminalOpener"
FEATURE_EXTENSION_NAME[terminal_opener]="JobsTerminalFinderSync.appex"
FEATURE_EXTENSION_ID[terminal_opener]="com.jobs.JobsTerminalOpener.FinderSyncExtension"

FEATURE_TITLE[ios-tools]="iOS / CocoaPods 辅助工具"
FEATURE_PROJECT_DIR[ios-tools]="JobsIOSTools"
FEATURE_SCHEME[ios-tools]="JobsIOSTools"
FEATURE_APP_NAME[ios-tools]="JobsIOSTools"
FEATURE_APP_ID[ios-tools]="com.jobs.JobsIOSTools"
FEATURE_EXTENSION_NAME[ios-tools]="JobsIOSToolsFinderSync.appex"
FEATURE_EXTENSION_ID[ios-tools]="com.jobs.JobsIOSTools.FinderSyncExtension"

IOS_FUNCTION_IDS=(ios-disable-sandbox ios-install-cocoapods ios-pods-source-github ios-extract-pods ios-pod-install ios-pod-update ios-xcode-dependencies ios-pod-repo-update ios-pod-build-check ios-code-snippets ios-clean-build-artifacts)
SELECTABLE_FUNCTION_IDS=(android_studio_opener vscode_opener xcode_opener git-pull git-rollback git_remote git_remote_copier path_copier file-create run-authorize run-revoke ipa-resign hidden-files-toggle ios-simulator-create android-simulator-create harmony-simulator-create android-simulator-repair harmony-simulator-repair git-proxy-configure terminal_open file_content file_merge file_split pod_install clean_build_artifacts codegraph_bootstrap git_empty_commit_push ios-disable-sandbox ios-install-cocoapods ios-pods-source-github ios-extract-pods ios-pod-update ios-xcode-dependencies ios-pod-repo-update ios-pod-build-check ios-code-snippets ios-clean-build-artifacts flutter-project-setup flutter-run flutter-pub-get flutter-android-dependencies flutter-pods-dependencies flutter-spm-dependencies flutter-ohos-dependencies flutter-native-dependencies flutter-flutter-precache flutter-web-dependencies flutter-extract flutter-export-private-dependencies flutter-import-dependencies flutter-import-private-dependencies flutter-export-gradle-dependencies flutter-import-gradle-dependencies flutter-export-pods-dependencies flutter-import-pods-dependencies flutter-export-spm-dependencies flutter-import-spm-dependencies flutter-export-ohos-dependencies flutter-import-ohos-dependencies flutter-export-native-dependencies flutter-import-native-dependencies flutter-export-precache-dependencies flutter-import-precache-dependencies flutter-export-web-dependencies flutter-import-web-dependencies flutter-sdk-version flutter-sdk-manage flutter-ohos-sdk-manage flutter-java-manage flutter-gradle-download flutter-codegen flutter-package-ios flutter-package-android flutter-package-ohos flutter-native-doctor flutter-harmony-doctor flutter-repair-android flutter-repair-imports flutter-repair-namespace flutter-repair-package-imports flutter-clean-build-artifacts flutter-maintenance)
SELECTABLE_FUNCTION_TITLE[git_remote]="打开 Git 远程地址"
SELECTABLE_FUNCTION_PROJECT_KEY[git_remote]="project-tools"
SELECTABLE_FUNCTION_TITLE[git_remote_copier]="复制 Git 远程地址"
SELECTABLE_FUNCTION_PROJECT_KEY[git_remote_copier]="project-tools"
SELECTABLE_FUNCTION_TITLE[path_copier]="复制绝对路径"
SELECTABLE_FUNCTION_PROJECT_KEY[path_copier]="path_copier"
SELECTABLE_FUNCTION_TITLE[file-create]="新建文件"
SELECTABLE_FUNCTION_PROJECT_KEY[file-create]="file-create"
SELECTABLE_FUNCTION_TITLE[run-authorize]="运行授权"
SELECTABLE_FUNCTION_PROJECT_KEY[run-authorize]="run-authorize"
SELECTABLE_FUNCTION_TITLE[run-revoke]="解除运行授权"
SELECTABLE_FUNCTION_PROJECT_KEY[run-revoke]="run-revoke"
SELECTABLE_FUNCTION_TITLE[ipa-resign]="IPA 免编译重签"
SELECTABLE_FUNCTION_PROJECT_KEY[ipa-resign]="ipa-resign"
SELECTABLE_FUNCTION_TITLE[hidden-files-toggle]="显示 / 隐藏文件"
SELECTABLE_FUNCTION_PROJECT_KEY[hidden-files-toggle]="desktop-tools"
SELECTABLE_FUNCTION_TITLE[xcode_opener]="用 Xcode 打开项目"
SELECTABLE_FUNCTION_PROJECT_KEY[xcode_opener]="project-tools"
SELECTABLE_FUNCTION_TITLE[vscode_opener]="用 VSCode 打开项目"
SELECTABLE_FUNCTION_PROJECT_KEY[vscode_opener]="project-tools"
SELECTABLE_FUNCTION_TITLE[android_studio_opener]="用 Android Studio 打开项目"
SELECTABLE_FUNCTION_PROJECT_KEY[android_studio_opener]="project-tools"
SELECTABLE_FUNCTION_TITLE[flutter_version_manager]="安装/切换 Flutter SDK（FVM）"
SELECTABLE_FUNCTION_PROJECT_KEY[flutter_version_manager]="flutter-tools"
SELECTABLE_FUNCTION_TITLE[flutter_sdk_version]="查看当前 Flutter SDK 版本"
SELECTABLE_FUNCTION_PROJECT_KEY[flutter_sdk_version]="flutter-tools"
SELECTABLE_FUNCTION_TITLE[git-pull]="拉取 Git 到最新"
SELECTABLE_FUNCTION_PROJECT_KEY[git-pull]="project-tools"
SELECTABLE_FUNCTION_TITLE[git-rollback]="Git 提交回退"
SELECTABLE_FUNCTION_PROJECT_KEY[git-rollback]="project-tools"
SELECTABLE_FUNCTION_TITLE[git-sourcetree]="用 Sourcetree 打开"
SELECTABLE_FUNCTION_PROJECT_KEY[git-sourcetree]="project-tools"
SELECTABLE_FUNCTION_TITLE[flutter-dependency-extract]="提取 Flutter 第三方依赖"
SELECTABLE_FUNCTION_PROJECT_KEY[flutter-dependency-extract]="flutter-tools"
SELECTABLE_FUNCTION_TITLE[flutter-run]="从终端运行 Flutter 项目"
SELECTABLE_FUNCTION_PROJECT_KEY[flutter-run]="flutter-tools"
SELECTABLE_FUNCTION_TITLE[flutter-package]="Flutter打包"
SELECTABLE_FUNCTION_PROJECT_KEY[flutter-package]="flutter-tools"
SELECTABLE_FUNCTION_TITLE[flutter-doctor]="Flutter 项目体检"
SELECTABLE_FUNCTION_PROJECT_KEY[flutter-doctor]="flutter-tools"
SELECTABLE_FUNCTION_TITLE[flutter-codegen]="Flutter 自动化生产代码"
SELECTABLE_FUNCTION_PROJECT_KEY[flutter-codegen]="flutter-tools"
SELECTABLE_FUNCTION_TITLE[ios-simulator-create]="新建 iOS 模拟器"
SELECTABLE_FUNCTION_PROJECT_KEY[ios-simulator-create]="desktop-tools"
SELECTABLE_FUNCTION_TITLE[android-simulator-create]="新建 Android 模拟器"
SELECTABLE_FUNCTION_PROJECT_KEY[android-simulator-create]="desktop-tools"
SELECTABLE_FUNCTION_TITLE[android-simulator-repair]="Android 模拟器检测与修复"
SELECTABLE_FUNCTION_PROJECT_KEY[android-simulator-repair]="desktop-tools"
SELECTABLE_FUNCTION_TITLE[harmony-simulator-create]="新建 Harmony 模拟器"
SELECTABLE_FUNCTION_PROJECT_KEY[harmony-simulator-create]="desktop-tools"
SELECTABLE_FUNCTION_TITLE[harmony-simulator-repair]="Harmony 模拟器检测与修复"
SELECTABLE_FUNCTION_PROJECT_KEY[harmony-simulator-repair]="desktop-tools"
SELECTABLE_FUNCTION_TITLE[git-proxy-configure]="配置 Git 动态代理"
SELECTABLE_FUNCTION_PROJECT_KEY[git-proxy-configure]="project-tools"
SELECTABLE_FUNCTION_TITLE[terminal_open]="用终端打开"
SELECTABLE_FUNCTION_PROJECT_KEY[terminal_open]="terminal_opener"
SELECTABLE_FUNCTION_TERMINAL_ACTION[terminal_open]="open"
SELECTABLE_FUNCTION_TITLE[file_content]="用终端查看文件内容"
SELECTABLE_FUNCTION_PROJECT_KEY[file_content]="terminal_opener"
SELECTABLE_FUNCTION_TERMINAL_ACTION[file_content]="file-content"
SELECTABLE_FUNCTION_TITLE[file_merge]="合并分卷"
SELECTABLE_FUNCTION_PROJECT_KEY[file_merge]="terminal_opener"
SELECTABLE_FUNCTION_TERMINAL_ACTION[file_merge]="file-merge"
SELECTABLE_FUNCTION_TITLE[file_split]="拆分文件"
SELECTABLE_FUNCTION_PROJECT_KEY[file_split]="terminal_opener"
SELECTABLE_FUNCTION_TERMINAL_ACTION[file_split]="file-split"
SELECTABLE_FUNCTION_TITLE[pod_install]="Pod Install"
SELECTABLE_FUNCTION_PROJECT_KEY[pod_install]="ios-tools"
SELECTABLE_FUNCTION_TERMINAL_ACTION[pod_install]="pod-install"
SELECTABLE_FUNCTION_TITLE[flutter_pub_get]="在终端执行 flutter pub get"
SELECTABLE_FUNCTION_PROJECT_KEY[flutter_pub_get]="flutter-tools"
SELECTABLE_FUNCTION_TERMINAL_ACTION[flutter_pub_get]="flutter-pub-get"
SELECTABLE_FUNCTION_TITLE[clean_build_artifacts]="清理 Android / OpenHarmony 构建产物"
SELECTABLE_FUNCTION_PROJECT_KEY[clean_build_artifacts]="terminal_opener"
SELECTABLE_FUNCTION_TERMINAL_ACTION[clean_build_artifacts]="clean-build-artifacts"
SELECTABLE_FUNCTION_TITLE[codegraph_bootstrap]="更新代码地图（.codegraph）"
SELECTABLE_FUNCTION_PROJECT_KEY[codegraph_bootstrap]="terminal_opener"
SELECTABLE_FUNCTION_TERMINAL_ACTION[codegraph_bootstrap]="codegraph-bootstrap"
SELECTABLE_FUNCTION_TITLE[git_empty_commit_push]="在终端创建空白 Commit 并 Push"
SELECTABLE_FUNCTION_PROJECT_KEY[git_empty_commit_push]="project-tools"
SELECTABLE_FUNCTION_TERMINAL_ACTION[git_empty_commit_push]="git-empty-commit-push"
SELECTABLE_FUNCTION_TITLE[ios-disable-sandbox]="禁用 CocoaPods 构建沙盒"
SELECTABLE_FUNCTION_PROJECT_KEY[ios-disable-sandbox]="ios-tools"
SELECTABLE_FUNCTION_TITLE[ios-install-cocoapods]="安装 CocoaPods"
SELECTABLE_FUNCTION_PROJECT_KEY[ios-install-cocoapods]="ios-tools"
SELECTABLE_FUNCTION_TITLE[ios-pods-source-github]="CocoaPods 源从 CDN 切换到 GitHub"
SELECTABLE_FUNCTION_PROJECT_KEY[ios-pods-source-github]="ios-tools"
SELECTABLE_FUNCTION_TITLE[ios-extract-pods]="提取项目全部 Pod 相关文件"
SELECTABLE_FUNCTION_PROJECT_KEY[ios-extract-pods]="ios-tools"
SELECTABLE_FUNCTION_TITLE[ios-pod-update]="Pod Update"
SELECTABLE_FUNCTION_PROJECT_KEY[ios-pod-update]="ios-tools"
SELECTABLE_FUNCTION_TITLE[ios-xcode-dependencies]="查询 Xcode 工程依赖关系"
SELECTABLE_FUNCTION_PROJECT_KEY[ios-xcode-dependencies]="ios-tools"
SELECTABLE_FUNCTION_TITLE[ios-pod-repo-update]="更新 CocoaPods 本地仓库"
SELECTABLE_FUNCTION_PROJECT_KEY[ios-pod-repo-update]="ios-tools"
SELECTABLE_FUNCTION_TITLE[ios-pod-build-check]="自检当前本地 Pod 编译"
SELECTABLE_FUNCTION_PROJECT_KEY[ios-pod-build-check]="ios-tools"
SELECTABLE_FUNCTION_TITLE[ios-code-snippets]="安装 / 升级 JobsCodeSnippets"
SELECTABLE_FUNCTION_PROJECT_KEY[ios-code-snippets]="ios-tools"
SELECTABLE_FUNCTION_TITLE[ios-clean-build-artifacts]="清理 iOS/Xcode 构建产物"
SELECTABLE_FUNCTION_PROJECT_KEY[ios-clean-build-artifacts]="ios-tools"

FLUTTER_ACTION_IDS=(project-setup run pub-get android-dependencies pods-dependencies spm-dependencies ohos-dependencies native-dependencies flutter-precache web-dependencies extract export-private-dependencies import-dependencies import-private-dependencies export-gradle-dependencies import-gradle-dependencies export-pods-dependencies import-pods-dependencies export-spm-dependencies import-spm-dependencies export-ohos-dependencies import-ohos-dependencies export-native-dependencies import-native-dependencies export-precache-dependencies import-precache-dependencies export-web-dependencies import-web-dependencies sdk-version sdk-manage ohos-sdk-manage java-manage gradle-download codegen package-ios package-android package-ohos native-doctor harmony-doctor repair-android repair-imports repair-namespace repair-package-imports clean-build-artifacts maintenance)
SELECTABLE_FUNCTION_TITLE[flutter-project-setup]="一键配置 Flutter 项目"
SELECTABLE_FUNCTION_PROJECT_KEY[flutter-project-setup]="flutter-tools"
SELECTABLE_FUNCTION_FLUTTER_ACTION[flutter-project-setup]="project-setup"
SELECTABLE_FUNCTION_TITLE[flutter-gradle-download]="下载Gradled分发与构建插件"
SELECTABLE_FUNCTION_PROJECT_KEY[flutter-gradle-download]="flutter-tools"
SELECTABLE_FUNCTION_FLUTTER_ACTION[flutter-gradle-download]="gradle-download"
SELECTABLE_FUNCTION_TITLE[flutter-run]="从终端运行 Flutter 项目"
SELECTABLE_FUNCTION_PROJECT_KEY[flutter-run]="flutter-tools"
SELECTABLE_FUNCTION_FLUTTER_ACTION[flutter-run]="run"
SELECTABLE_FUNCTION_TITLE[flutter-pub-get]="拉取 Flutter Pub 依赖"
SELECTABLE_FUNCTION_PROJECT_KEY[flutter-pub-get]="flutter-tools"
SELECTABLE_FUNCTION_FLUTTER_ACTION[flutter-pub-get]="pub-get"
SELECTABLE_FUNCTION_TITLE[flutter-android-dependencies]="拉取 Android 原生依赖"
SELECTABLE_FUNCTION_PROJECT_KEY[flutter-android-dependencies]="flutter-tools"
SELECTABLE_FUNCTION_FLUTTER_ACTION[flutter-android-dependencies]="android-dependencies"
SELECTABLE_FUNCTION_TITLE[flutter-pods-dependencies]="拉取 CocoaPods 依赖"
SELECTABLE_FUNCTION_PROJECT_KEY[flutter-pods-dependencies]="flutter-tools"
SELECTABLE_FUNCTION_FLUTTER_ACTION[flutter-pods-dependencies]="pods-dependencies"
SELECTABLE_FUNCTION_TITLE[flutter-spm-dependencies]="拉取 Swift Package 依赖"
SELECTABLE_FUNCTION_PROJECT_KEY[flutter-spm-dependencies]="flutter-tools"
SELECTABLE_FUNCTION_FLUTTER_ACTION[flutter-spm-dependencies]="spm-dependencies"
SELECTABLE_FUNCTION_TITLE[flutter-ohos-dependencies]="拉取 OpenHarmony 依赖"
SELECTABLE_FUNCTION_PROJECT_KEY[flutter-ohos-dependencies]="flutter-tools"
SELECTABLE_FUNCTION_FLUTTER_ACTION[flutter-ohos-dependencies]="ohos-dependencies"
SELECTABLE_FUNCTION_TITLE[flutter-native-dependencies]="准备原生库与构建依赖（组合操作）"
SELECTABLE_FUNCTION_PROJECT_KEY[flutter-native-dependencies]="flutter-tools"
SELECTABLE_FUNCTION_FLUTTER_ACTION[flutter-native-dependencies]="native-dependencies"
SELECTABLE_FUNCTION_TITLE[flutter-flutter-precache]="下载Flutter平台资源"
SELECTABLE_FUNCTION_PROJECT_KEY[flutter-flutter-precache]="flutter-tools"
SELECTABLE_FUNCTION_FLUTTER_ACTION[flutter-flutter-precache]="flutter-precache"
SELECTABLE_FUNCTION_TITLE[flutter-web-dependencies]="拉取 Web 工程依赖"
SELECTABLE_FUNCTION_PROJECT_KEY[flutter-web-dependencies]="flutter-tools"
SELECTABLE_FUNCTION_FLUTTER_ACTION[flutter-web-dependencies]="web-dependencies"
SELECTABLE_FUNCTION_TITLE[flutter-export-private-dependencies]="🔐 提取Flutter项目工程私库依赖"
SELECTABLE_FUNCTION_PROJECT_KEY[flutter-export-private-dependencies]="flutter-tools"
SELECTABLE_FUNCTION_FLUTTER_ACTION[flutter-export-private-dependencies]="export-private-dependencies"
SELECTABLE_FUNCTION_TITLE[flutter-import-private-dependencies]="📥 导入Flutter项目工程私库依赖"
SELECTABLE_FUNCTION_PROJECT_KEY[flutter-import-private-dependencies]="flutter-tools"
SELECTABLE_FUNCTION_FLUTTER_ACTION[flutter-import-private-dependencies]="import-private-dependencies"
SELECTABLE_FUNCTION_TITLE[flutter-extract]="提取 Flutter Pub 依赖"
SELECTABLE_FUNCTION_PROJECT_KEY[flutter-extract]="flutter-tools"
SELECTABLE_FUNCTION_FLUTTER_ACTION[flutter-extract]="extract"
SELECTABLE_FUNCTION_TITLE[flutter-import-dependencies]="导入 Flutter Pub 依赖"
SELECTABLE_FUNCTION_PROJECT_KEY[flutter-import-dependencies]="flutter-tools"
SELECTABLE_FUNCTION_FLUTTER_ACTION[flutter-import-dependencies]="import-dependencies"
SELECTABLE_FUNCTION_TITLE[flutter-export-gradle-dependencies]="提取 Gradle 分发与依赖缓存"
SELECTABLE_FUNCTION_PROJECT_KEY[flutter-export-gradle-dependencies]="flutter-tools"
SELECTABLE_FUNCTION_FLUTTER_ACTION[flutter-export-gradle-dependencies]="export-gradle-dependencies"
SELECTABLE_FUNCTION_TITLE[flutter-import-gradle-dependencies]="导入 Gradle 分发与依赖缓存"
SELECTABLE_FUNCTION_PROJECT_KEY[flutter-import-gradle-dependencies]="flutter-tools"
SELECTABLE_FUNCTION_FLUTTER_ACTION[flutter-import-gradle-dependencies]="import-gradle-dependencies"
SELECTABLE_FUNCTION_TITLE[flutter-export-pods-dependencies]="提取 CocoaPods 依赖"
SELECTABLE_FUNCTION_PROJECT_KEY[flutter-export-pods-dependencies]="flutter-tools"
SELECTABLE_FUNCTION_FLUTTER_ACTION[flutter-export-pods-dependencies]="export-pods-dependencies"
SELECTABLE_FUNCTION_TITLE[flutter-import-pods-dependencies]="导入 CocoaPods 依赖"
SELECTABLE_FUNCTION_PROJECT_KEY[flutter-import-pods-dependencies]="flutter-tools"
SELECTABLE_FUNCTION_FLUTTER_ACTION[flutter-import-pods-dependencies]="import-pods-dependencies"
SELECTABLE_FUNCTION_TITLE[flutter-export-spm-dependencies]="提取 Swift Package 依赖"
SELECTABLE_FUNCTION_PROJECT_KEY[flutter-export-spm-dependencies]="flutter-tools"
SELECTABLE_FUNCTION_FLUTTER_ACTION[flutter-export-spm-dependencies]="export-spm-dependencies"
SELECTABLE_FUNCTION_TITLE[flutter-import-spm-dependencies]="导入 Swift Package 依赖"
SELECTABLE_FUNCTION_PROJECT_KEY[flutter-import-spm-dependencies]="flutter-tools"
SELECTABLE_FUNCTION_FLUTTER_ACTION[flutter-import-spm-dependencies]="import-spm-dependencies"
SELECTABLE_FUNCTION_TITLE[flutter-export-ohos-dependencies]="提取 OpenHarmony 依赖"
SELECTABLE_FUNCTION_PROJECT_KEY[flutter-export-ohos-dependencies]="flutter-tools"
SELECTABLE_FUNCTION_FLUTTER_ACTION[flutter-export-ohos-dependencies]="export-ohos-dependencies"
SELECTABLE_FUNCTION_TITLE[flutter-import-ohos-dependencies]="导入 OpenHarmony 依赖"
SELECTABLE_FUNCTION_PROJECT_KEY[flutter-import-ohos-dependencies]="flutter-tools"
SELECTABLE_FUNCTION_FLUTTER_ACTION[flutter-import-ohos-dependencies]="import-ohos-dependencies"
SELECTABLE_FUNCTION_TITLE[flutter-export-native-dependencies]="提取 原生构建缓存"
SELECTABLE_FUNCTION_PROJECT_KEY[flutter-export-native-dependencies]="flutter-tools"
SELECTABLE_FUNCTION_FLUTTER_ACTION[flutter-export-native-dependencies]="export-native-dependencies"
SELECTABLE_FUNCTION_TITLE[flutter-import-native-dependencies]="导入 原生构建缓存"
SELECTABLE_FUNCTION_PROJECT_KEY[flutter-import-native-dependencies]="flutter-tools"
SELECTABLE_FUNCTION_FLUTTER_ACTION[flutter-import-native-dependencies]="import-native-dependencies"
SELECTABLE_FUNCTION_TITLE[flutter-export-precache-dependencies]="提取 Flutter 平台资源"
SELECTABLE_FUNCTION_PROJECT_KEY[flutter-export-precache-dependencies]="flutter-tools"
SELECTABLE_FUNCTION_FLUTTER_ACTION[flutter-export-precache-dependencies]="export-precache-dependencies"
SELECTABLE_FUNCTION_TITLE[flutter-import-precache-dependencies]="导入 Flutter 平台资源"
SELECTABLE_FUNCTION_PROJECT_KEY[flutter-import-precache-dependencies]="flutter-tools"
SELECTABLE_FUNCTION_FLUTTER_ACTION[flutter-import-precache-dependencies]="import-precache-dependencies"
SELECTABLE_FUNCTION_TITLE[flutter-export-web-dependencies]="提取 Web 依赖"
SELECTABLE_FUNCTION_PROJECT_KEY[flutter-export-web-dependencies]="flutter-tools"
SELECTABLE_FUNCTION_FLUTTER_ACTION[flutter-export-web-dependencies]="export-web-dependencies"
SELECTABLE_FUNCTION_TITLE[flutter-import-web-dependencies]="导入 Web 依赖"
SELECTABLE_FUNCTION_PROJECT_KEY[flutter-import-web-dependencies]="flutter-tools"
SELECTABLE_FUNCTION_FLUTTER_ACTION[flutter-import-web-dependencies]="import-web-dependencies"
SELECTABLE_FUNCTION_TITLE[flutter-sdk-version]="查看当前Flutter项目工程的SDK版本"
SELECTABLE_FUNCTION_PROJECT_KEY[flutter-sdk-version]="flutter-tools"
SELECTABLE_FUNCTION_FLUTTER_ACTION[flutter-sdk-version]="sdk-version"
SELECTABLE_FUNCTION_TITLE[flutter-sdk-manage]="安装/切换Flutter SDK"
SELECTABLE_FUNCTION_PROJECT_KEY[flutter-sdk-manage]="flutter-tools"
SELECTABLE_FUNCTION_FLUTTER_ACTION[flutter-sdk-manage]="sdk-manage"
SELECTABLE_FUNCTION_TITLE[flutter-ohos-sdk-manage]="安装/切换Flutter@OpenHarmony SDK"
SELECTABLE_FUNCTION_PROJECT_KEY[flutter-ohos-sdk-manage]="flutter-tools"
SELECTABLE_FUNCTION_FLUTTER_ACTION[flutter-ohos-sdk-manage]="ohos-sdk-manage"
SELECTABLE_FUNCTION_TITLE[flutter-java-manage]="安装/切换Java SDK"
SELECTABLE_FUNCTION_PROJECT_KEY[flutter-java-manage]="flutter-tools"
SELECTABLE_FUNCTION_FLUTTER_ACTION[flutter-java-manage]="java-manage"
SELECTABLE_FUNCTION_TITLE[flutter-codegen]="Flutter 自动化生产代码"
SELECTABLE_FUNCTION_PROJECT_KEY[flutter-codegen]="flutter-tools"
SELECTABLE_FUNCTION_FLUTTER_ACTION[flutter-codegen]="codegen"
SELECTABLE_FUNCTION_TITLE[flutter-package-ios]="打包 iOS"
SELECTABLE_FUNCTION_PROJECT_KEY[flutter-package-ios]="flutter-tools"
SELECTABLE_FUNCTION_FLUTTER_ACTION[flutter-package-ios]="package-ios"
SELECTABLE_FUNCTION_TITLE[flutter-package-android]="打包 Android"
SELECTABLE_FUNCTION_PROJECT_KEY[flutter-package-android]="flutter-tools"
SELECTABLE_FUNCTION_FLUTTER_ACTION[flutter-package-android]="package-android"
SELECTABLE_FUNCTION_TITLE[flutter-package-ohos]="打包鸿蒙（HAP + APP）"
SELECTABLE_FUNCTION_PROJECT_KEY[flutter-package-ohos]="flutter-tools"
SELECTABLE_FUNCTION_FLUTTER_ACTION[flutter-package-ohos]="package-ohos"
SELECTABLE_FUNCTION_TITLE[flutter-native-doctor]="原生 Flutter 项目体检"
SELECTABLE_FUNCTION_PROJECT_KEY[flutter-native-doctor]="flutter-tools"
SELECTABLE_FUNCTION_FLUTTER_ACTION[flutter-native-doctor]="native-doctor"
SELECTABLE_FUNCTION_TITLE[flutter-harmony-doctor]="OpenHarmony Flutter 环境体检"
SELECTABLE_FUNCTION_PROJECT_KEY[flutter-harmony-doctor]="flutter-tools"
SELECTABLE_FUNCTION_FLUTTER_ACTION[flutter-harmony-doctor]="harmony-doctor"
SELECTABLE_FUNCTION_TITLE[flutter-repair-android]="修复 Android SDK / platforms 缺失"
SELECTABLE_FUNCTION_PROJECT_KEY[flutter-repair-android]="flutter-tools"
SELECTABLE_FUNCTION_FLUTTER_ACTION[flutter-repair-android]="repair-android"
SELECTABLE_FUNCTION_TITLE[flutter-repair-imports]="修复 Flutter 项目中文路径"
SELECTABLE_FUNCTION_PROJECT_KEY[flutter-repair-imports]="flutter-tools"
SELECTABLE_FUNCTION_FLUTTER_ACTION[flutter-repair-imports]="repair-imports"
SELECTABLE_FUNCTION_TITLE[flutter-repair-namespace]="修复 Flutter 插件 namespace"
SELECTABLE_FUNCTION_PROJECT_KEY[flutter-repair-namespace]="flutter-tools"
SELECTABLE_FUNCTION_FLUTTER_ACTION[flutter-repair-namespace]="repair-namespace"
SELECTABLE_FUNCTION_TITLE[flutter-repair-package-imports]="修复 Dart 相对 import 为 package 引用"
SELECTABLE_FUNCTION_PROJECT_KEY[flutter-repair-package-imports]="flutter-tools"
SELECTABLE_FUNCTION_FLUTTER_ACTION[flutter-repair-package-imports]="repair-package-imports"
SELECTABLE_FUNCTION_TITLE[flutter-clean-build-artifacts]="清理当前 Flutter 项目构建产物"
SELECTABLE_FUNCTION_PROJECT_KEY[flutter-clean-build-artifacts]="flutter-tools"
SELECTABLE_FUNCTION_FLUTTER_ACTION[flutter-clean-build-artifacts]="clean-build-artifacts"
SELECTABLE_FUNCTION_TITLE[flutter-maintenance]="依赖与缓存维护"
SELECTABLE_FUNCTION_PROJECT_KEY[flutter-maintenance]="flutter-tools"
SELECTABLE_FUNCTION_FLUTTER_ACTION[flutter-maintenance]="maintenance"
SELECTABLE_FUNCTION_FLUTTER_ACTION[flutter_version_manager]="sdk-manage"
SELECTABLE_FUNCTION_FLUTTER_ACTION[flutter_sdk_version]="sdk-version"
SELECTABLE_FUNCTION_FLUTTER_ACTION[flutter_pub_get]="pub-get"
SELECTABLE_FUNCTION_FLUTTER_ACTION[flutter-dependency-extract]="extract"

# 判断当前终端是否适合输出 ANSI 彩色文本。
supports_color() {
  [[ -t 1 && -n "${TERM:-}" && "${TERM:-}" != "dumb" && -z "${NO_COLOR:-}" ]]
}
# 输出文本并同步追加到日志文件。
log() {
  print -r -- "$1" | tee -a "$LOG_FILE"
}
# 按需给日志文本套色，非 TTY 环境自动降级为纯文本。
color_log() {
  local code="$1"
  local message="$2"

  if supports_color; then
    log "$(printf '\033[%sm%s\033[0m' "$code" "$message")"
  else
    log "$message"
  fi
}
# 输出普通绿色提示。
color_echo() {
  color_log "1;32" "$1"
}
# 输出信息提示。
info_echo() {
  color_log "1;34" "ℹ $1"
}
# 输出成功提示。
success_echo() {
  color_log "1;32" "✔ $1"
}
# 输出警告提示。
warn_echo() {
  color_log "1;33" "⚠ $1"
}
# 输出温馨提示。
warm_echo() {
  color_log "1;33" "$1"
}
# 输出说明提示。
note_echo() {
  color_log "1;35" "➤ $1"
}
# 输出错误提示。
error_echo() {
  color_log "1;31" "✖ $1"
}
# 输出错误纯文本。
err_echo() {
  color_log "1;31" "$1"
}
# 输出调试提示。
debug_echo() {
  color_log "1;35" "🐞 $1"
}
# 输出高亮提示。
highlight_echo() {
  color_log "1;36" "🔹 $1"
}
# 输出次要说明。
gray_echo() {
  color_log "0;90" "$1"
}
# 输出加粗文本。
bold_echo() {
  color_log "1" "$1"
}
# 输出下划线文本。
underline_echo() {
  color_log "4" "$1"
}
# 判断是否可以安全清屏，避免瘦身终端里出现 TERM 报错。
can_clear_terminal() {
  [[ -t 1 && -n "${TERM:-}" && "${TERM:-}" != "dumb" ]]
}
# GUI 直接展示用途，worker 在面板日志中输出相同的操作范围。
show_script_intro_and_wait() {
  parse_management_options "$@" || exit $?
  (( MANAGER_NON_INTERACTIVE )) || return 0
  highlight_echo "============================== 脚本自述 ==============================" | jobs_intro_style title
  note_echo "当前脚本：${SCRIPT_PATH}" | jobs_intro_style body
  note_echo '核心用途：安装、更新或按叶卸载 Finder 右键功能，保留未选中的菜单。' | jobs_intro_style body
  warn_echo '影响范围：构建并登记所选扩展；卸载仅移除所选功能，最后一项才移除共享 App。' | jobs_intro_style body
  warn_echo '完成后刷新 Finder；源码、SDK 和业务文件保留。' | jobs_intro_style body
  gray_echo '执行方式：面板操作按钮即最终确认；日志与各项状态实时回传面板。' | jobs_intro_style body
  return 0
}
# 初始化 zsh 运行选项和日志文件。
init_runtime() {
  setopt NO_NOMATCH
  : > "$LOG_FILE"
  if [[ -z "${HOME:-}" || ! -d "$HOME" ]]; then
    error_echo "无法确定当前用户目录，不能安全保存 Terminal 功能选择。"
    exit 1
  fi
  TERMINAL_FEATURE_CONFIG_DIR="${HOME}/Library/Application Support/JobsTerminalOpener"
  TERMINAL_FEATURE_CONFIG_PATH="${TERMINAL_FEATURE_CONFIG_DIR}/EnabledFinderMenuFeatures.txt"
  IOS_FEATURE_CONFIG_DIR="${HOME}/Library/Application Support/JobsIOSTools"
  IOS_FEATURE_CONFIG_PATH="${IOS_FEATURE_CONFIG_DIR}/EnabledFeatures.txt"
  FLUTTER_FEATURE_CONFIG_DIR="${HOME}/Library/Application Support/JobsFinderExtensions"
  FLUTTER_FEATURE_CONFIG_PATH="${FLUTTER_FEATURE_CONFIG_DIR}/flutter-tools-features.conf"
}
# 获取当前 Mac CPU 架构，用于收敛 xcodebuild 目标。
get_cpu_arch() {
  [[ "$(uname -m)" == "arm64" ]] && print -r -- "arm64" || print -r -- "x86_64"
}
# 返回 LaunchServices 注册工具路径。
lsregister_path() {
  local tool_path="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

  [[ -x "$tool_path" ]] && print -r -- "$tool_path"
}
# 返回指定 Finder 扩展功能对应的 Xcode 工程路径。
project_file_for_key() {
  local key="$1"

  print -r -- "${WORKSPACE_DIR}/${FEATURE_PROJECT_DIR[$key]}/${FEATURE_PROJECT_DIR[$key]}.xcodeproj"
}
# 校验指定安装单元；省略参数时只查当前计划，无计划时供完整源码诊断。
feature_projects_ready() {
  local key=""
  local project_file=""
  local keys=("$@")
  (( ${#keys[@]} > 0 )) || keys=("${SELECTED_KEYS[@]}")
  (( ${#keys[@]} > 0 )) || keys=("${FEATURE_KEYS[@]}")

  for key in "${keys[@]}"; do
    project_file="$(project_file_for_key "$key")"
    [[ ! -f "${project_file}/project.pbxproj" ]] && return 1
  done

  return 0
}
# 输出缺失的本仓工程配置和完整源码取得方式。
print_missing_feature_projects() {
  local key=""
  local project_file=""
  local keys=("$@")
  (( ${#keys[@]} > 0 )) || keys=("${SELECTED_KEYS[@]}")
  (( ${#keys[@]} > 0 )) || keys=("${FEATURE_KEYS[@]}")

  error_echo "Finder 扩展工程源码不完整；${#FEATURE_KEYS[@]} 个工程均随当前仓库统一管理。"
  for key in "${keys[@]}"; do
    project_file="$(project_file_for_key "$key")"
    if [[ ! -f "${project_file}/project.pbxproj" ]]; then
      gray_echo "- ${FEATURE_TITLE[$key]}：${project_file}/project.pbxproj"
    fi
  done
  error_echo "请重新取得包含全部工程源码的完整 MacOS@Extension 仓库，或补齐上述缺失安装单元后重试。"
  warn_echo "仅跳过缺少源码的安装单元；其它已选安装单元继续处理。"
}
# 缺少工程配置时只拒绝对应安装单元，不让缺失源码进入构建或注册。
ensure_feature_projects_exist() {
  feature_projects_ready "$@" && return 0

  print_missing_feature_projects "$@"
  return 1
}
# 检查所有所选安装单元共用的系统命令与 MacOS 环境。
check_environment() {
  local missing_commands=()
  local command_name=""

  if [[ "$(uname -s)" != "Darwin" ]]; then
    error_echo "当前系统不是 MacOS，无法安装 Finder 扩展。"
    exit 1
  fi

  for command_name in pluginkit killall pkill grep head awk find mkdir tee sed; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
      missing_commands+=("$command_name")
    fi
  done

  if (( ${#missing_commands[@]} > 0 )); then
    error_echo "缺少必要命令：${(j:, :)missing_commands}"
    exit 1
  fi

  if [[ "$MANAGEMENT_ACTION" == uninstall ]]; then
    return 0
  fi

  if ! /usr/bin/xcode-select -p >/dev/null 2>&1; then
    error_echo "未检测到 Xcode 命令行工具，请先安装或选择 Xcode。"
    gray_echo "可执行：xcode-select --install"
    exit 1
  fi

  if [[ -z "$(lsregister_path)" ]]; then
    error_echo "未找到 LaunchServices 注册工具 lsregister。"
    exit 1
  fi

  if [[ ! -f "$FEATURE_SELECTOR_SOURCE_PATH" ]]; then
    error_echo "未找到 Finder 功能选择 UI 源码：${FEATURE_SELECTOR_SOURCE_PATH}"
    exit 1
  fi
}
# 去重追加一个待安装功能。
append_selected_key_if_needed() {
  local key="$1"
  local existed_key=""

  for existed_key in "${SELECTED_KEYS[@]}"; do
    [[ "$existed_key" == "$key" ]] && return 0
  done
  SELECTED_KEYS+=("$key")
}
# 去重追加一个用户勾选的右键菜单功能。
append_selected_function_id_if_needed() {
  local function_id="$1"
  local existed_function_id=""

  for existed_function_id in "${SELECTED_FUNCTION_IDS[@]}"; do
    [[ "$existed_function_id" == "$function_id" ]] && return 1
  done
  SELECTED_FUNCTION_IDS+=("$function_id")
  return 0
}
# 把原生 UI 返回的功能标识解析成工程和 Terminal 子功能。
parse_feature_selection() {
  local selection_output="$1"
  local selected_function_id=""
  local project_key=""
  local terminal_action=""
  local terminal_actions=()
  local ios_actions=()
  local flutter_actions=()
  typeset -U flutter_actions
  typeset -U ios_actions

  SELECTED_KEYS=()
  SELECTED_FUNCTION_IDS=()
  TERMINAL_OPENER_ENABLED_FEATURES=""
  IOS_TOOLS_ENABLED_FEATURES=""
  FLUTTER_TOOLS_ENABLED_FEATURES=""
  for selected_function_id in ${(s:,:)selection_output}; do
    [[ "$selected_function_id" == ios-clean-cache ]] && selected_function_id=ios-clean-build-artifacts
    project_key="${SELECTABLE_FUNCTION_PROJECT_KEY[$selected_function_id]}"
    if [[ -z "$project_key" ]]; then
      error_echo "功能选择 UI 返回了未知标识：${selected_function_id}"
      return 1
    fi

    append_selected_function_id_if_needed "$selected_function_id" || continue
    append_selected_key_if_needed "$project_key"
    if [[ "$project_key" == "terminal_opener" ]]; then
      terminal_action="${SELECTABLE_FUNCTION_TERMINAL_ACTION[$selected_function_id]}"
      [[ -n "$terminal_action" ]] && terminal_actions+=("$terminal_action")
    elif [[ "$project_key" == "flutter-tools" ]]; then
      if [[ "$selected_function_id" == flutter-tools ]]; then
        flutter_actions+=("${FLUTTER_ACTION_IDS[@]}")
      elif [[ "$selected_function_id" == flutter-package ]]; then
        flutter_actions+=(package-ios package-android package-ohos)
      elif [[ "$selected_function_id" == flutter-doctor ]]; then
        flutter_actions+=(native-doctor harmony-doctor)
      else
        flutter_actions+=("${SELECTABLE_FUNCTION_FLUTTER_ACTION[$selected_function_id]}")
      fi
    elif [[ "$project_key" == "ios-tools" ]]; then
      if [[ "$selected_function_id" == pod_install ]]; then
        ios_actions+=(ios-pod-install)
      else
        ios_actions+=("$selected_function_id")
      fi
    fi
  done
  TERMINAL_OPENER_ENABLED_FEATURES="${(j:,:)terminal_actions}"
  IOS_TOOLS_ENABLED_FEATURES="${(j:,:)ios_actions}"
  FLUTTER_TOOLS_ENABLED_FEATURES="${(j:,:)flutter_actions}"
}
# 编译功能选择窗口（源码更新后自动重编），产物缓存在 work 目录。
build_feature_selector_if_needed() {
  if [[ -x "$FEATURE_SELECTOR_BINARY_PATH" && ! "$FEATURE_SELECTOR_SOURCE_PATH" -nt "$FEATURE_SELECTOR_BINARY_PATH" ]]; then
    return 0
  fi

  note_echo "正在编译功能选择窗口（首次或源码更新后会多几秒）..."
  /bin/mkdir -p "${WORKSPACE_DIR}/work"
  /usr/bin/xcrun swiftc -O "$FEATURE_SELECTOR_SOURCE_PATH" -o "$FEATURE_SELECTOR_BINARY_PATH" 2>&1 | tee -a "$LOG_FILE"
  if (( ${pipestatus[1]} != 0 )); then
    error_echo "功能选择窗口编译失败，无法继续安装。"
    return 1
  fi

  return 0
}

# 使用原生 macOS 复选框 UI 选择本次需要安装的右键菜单功能。
select_features_with_ui() {
  local selection_output=""
  local selector_status=0

  build_feature_selector_if_needed || exit 1
  local selector_arguments=(--action "$MANAGEMENT_ACTION")
  [[ -z "$FEATURE_SCOPE" ]] || selector_arguments+=(--scope "$FEATURE_SCOPE")
  selection_output="$("$FEATURE_SELECTOR_BINARY_PATH" "${selector_arguments[@]}")"
  selector_status=$?

  if (( selector_status != 0 )); then
    error_echo "Finder 功能选择 UI 运行失败，退出码：${selector_status}"
    exit "$selector_status"
  fi

  if [[ "$selection_output" == "__CANCELLED__" ]]; then
    warn_echo "已取消功能选择，未修改功能。"
    exit 0
  fi
  if [[ "$selection_output" == "__NONE__" || -z "$selection_output" ]]; then
    warn_echo "没有选择任何功能，未修改功能。"
    exit 0
  fi

  case "$selection_output" in
    install\|*|uninstall\|*)
      MANAGEMENT_ACTION="${selection_output%%|*}"
      selection_output="${selection_output#*|}"
      ;;
    *) error_echo '功能面板返回了无效操作，已停止。'; exit 1 ;;
  esac
  validate_feature_scope "$selection_output" || exit 1
  parse_feature_selection "$selection_output" || exit 1
  if (( ${#SELECTED_KEYS[@]} == 0 || ${#SELECTED_FUNCTION_IDS[@]} == 0 )); then
    warn_echo "没有解析到有效功能，未执行安装。"
    exit 0
  fi
}
# 输出用户已经选择的功能，便于日志排查。
print_selected_features() {
  local selected_function_id=""

  note_echo "本次操作：${MANAGEMENT_ACTION}；已选择功能："
  for selected_function_id in "${SELECTED_FUNCTION_IDS[@]}"; do
    gray_echo "- ${SELECTABLE_FUNCTION_TITLE[$selected_function_id]}"
  done
}
# 返回指定功能的本地 DerivedData 目录。
derived_data_dir_for_key() {
  local key="$1"

  print -r -- "${WORKSPACE_DIR}/work/${FEATURE_PROJECT_DIR[$key]}DerivedData"
}
# 返回指定功能构建后的宿主 App 路径。
app_path_for_key() {
  local key="$1"
  local derived_data_dir=""

  derived_data_dir="$(derived_data_dir_for_key "$key")"
  print -r -- "${derived_data_dir}/Build/Products/${BUILD_CONFIGURATION}/${FEATURE_APP_NAME[$key]}.app"
}
# 返回指定功能构建后的 Finder Sync appex 路径。
extension_path_for_key() {
  local key="$1"
  local app_path=""

  app_path="$(app_path_for_key "$key")"
  print -r -- "${app_path}/Contents/PlugIns/${FEATURE_EXTENSION_NAME[$key]}"
}
# 返回指定功能构建目录下的散落 appex 路径。
standalone_extension_path_for_key() {
  local key="$1"
  local derived_data_dir=""

  derived_data_dir="$(derived_data_dir_for_key "$key")"
  print -r -- "${derived_data_dir}/Build/Products/${BUILD_CONFIGURATION}/${FEATURE_EXTENSION_NAME[$key]}"
}
# 运行 xcodebuild 构建指定功能的宿主 App 和 Finder Sync Extension。
build_feature() {
  local key="$1"
  local project_file="${WORKSPACE_DIR}/${FEATURE_PROJECT_DIR[$key]}/${FEATURE_PROJECT_DIR[$key]}.xcodeproj"
  local derived_data_dir=""
  local destination=""
  local build_status=0
  local extra_build_settings=()

  derived_data_dir="$(derived_data_dir_for_key "$key")"
  destination="platform=macOS,arch=$(get_cpu_arch)"
  /bin/mkdir -p "${WORKSPACE_DIR}/work"

  note_echo "开始构建：${FEATURE_TITLE[$key]}"
  gray_echo "工程路径：${project_file}"
  gray_echo "构建缓存：${derived_data_dir}"
  gray_echo "注册策略：构建阶段跳过自动注册，构建完成后由当前安装脚本统一处理。"
  if [[ "$key" == "terminal_opener" ]]; then
    extra_build_settings+=("JOBS_TERMINAL_ENABLED_FEATURES=${TERMINAL_OPENER_ENABLED_FEATURES}")
    gray_echo "Terminal 右键功能：${TERMINAL_OPENER_ENABLED_FEATURES}"
  fi

  JOBS_SKIP_FINDER_EXTENSION_BUILD_PHASE=1 /usr/bin/xcodebuild \
    -project "$project_file" \
    -scheme "${FEATURE_SCHEME[$key]}" \
    -configuration "$BUILD_CONFIGURATION" \
    -destination "$destination" \
    -derivedDataPath "$derived_data_dir" \
    "${extra_build_settings[@]}" \
    build 2>&1 | tee -a "$LOG_FILE"
  build_status=${pipestatus[1]}

  if (( build_status != 0 )); then
    error_echo "构建失败：${FEATURE_TITLE[$key]}"
    return "$build_status"
  fi

  success_echo "构建完成：${FEATURE_TITLE[$key]}"
  return 0
}
# 只查询当前产物的注册状态，旧路径已启用不能代替本次安装成功。
status_line_for_extension() {
  local extension_id="$1"
  local extension_path="$2"
  local lines=""
  local current_line=""

  lines="$(/usr/bin/pluginkit -m -p com.apple.FinderSync -A -v 2>/dev/null | /usr/bin/grep -F "$extension_id" || true)"
  while IFS= read -r current_line; do
    if [[ "$current_line" == *[[:space:]]"$extension_path" ]]; then
      print -r -- "$current_line"
      return 0
    fi
  done <<< "$lines"

  return 1
}
# 等待 pluginkit 完成异步登记并进入启用状态。
wait_until_extension_enabled() {
  local extension_id="$1"
  local extension_path="$2"
  local attempt=""
  local line=""

  for attempt in {1..90}; do
    line="$(status_line_for_extension "$extension_id" "$extension_path")"
    gray_echo "轮询 ${attempt}/90：${line:-未登记}"
    if [[ "$line" == +* ]]; then
      return 0
    fi
    if [[ -n "$line" ]]; then
      /usr/bin/pluginkit -e use -i "$extension_id" 2>&1 | tee -a "$LOG_FILE" || true
    fi
    /bin/sleep 0.5
  done

  return 1
}
# 去重收集一个路径。
append_unique_path_if_needed() {
  local candidate_path="$1"
  local existed_path=""

  [[ -z "$candidate_path" ]] && return 0
  for existed_path in "${REGISTERED_PATHS[@]}"; do
    [[ "$existed_path" == "$candidate_path" ]] && return 0
  done
  REGISTERED_PATHS+=("$candidate_path")
}
# 返回宿主 Bundle ID，保留旧功能按产品名推导的兼容规则。
app_bundle_id_for_key() {
  local key="$1"

  print -r -- "${FEATURE_APP_ID[$key]:-com.jobs.${FEATURE_APP_NAME[$key]}}"
}
# 从 LaunchServices / PlugInKit 里收集当前功能可能残留的注册路径。
collect_registered_paths_for_feature() {
  local key="$1"
  local app_id="$(app_bundle_id_for_key "$key")"
  local extension_id="${FEATURE_EXTENSION_ID[$key]}"
  local extension_name="${FEATURE_EXTENSION_NAME[$key]}"
  local lsregister=""
  local registered_path=""

  REGISTERED_PATHS=()
  lsregister="$(lsregister_path)"

  while IFS= read -r registered_path; do
    append_unique_path_if_needed "$registered_path"
  done < <(
    /usr/bin/pluginkit -m -i "$extension_id" -A -D -vv 2>/dev/null \
      | /usr/bin/awk -F '= ' '/Path = / {print $2}'
  )

  while IFS= read -r registered_path; do
    append_unique_path_if_needed "$registered_path"
  done < <(
    "$lsregister" -dump 2>/dev/null | /usr/bin/awk -v app_id="$app_id" -v extension_id="$extension_id" '
      function flush_record() {
        if ((bundle_id == app_id || bundle_id == extension_id) && bundle_path != "") {
          print bundle_path
        }
        bundle_id = ""
        bundle_path = ""
      }
      /^--------------------------------------------------------------------------------$/ {
        flush_record()
        next
      }
      /^path:[[:space:]]+/ {
        bundle_path = $0
        sub(/^path:[[:space:]]+/, "", bundle_path)
        sub(/[[:space:]]+[(]0x[0-9a-fA-F]+[)].*$/, "", bundle_path)
      }
      /^identifier:[[:space:]]+/ {
        bundle_id = $0
        sub(/^identifier:[[:space:]]+/, "", bundle_id)
      }
      END {
        flush_record()
      }
    '
  )

  append_unique_path_if_needed "$(standalone_extension_path_for_key "$key")"
  while IFS= read -r registered_path; do
    append_unique_path_if_needed "$registered_path"
  done < <(
    /usr/bin/find "${HOME}/Library/Developer/Xcode/DerivedData" \
      \( -path "*/Build/Products/${BUILD_CONFIGURATION}/${extension_name}" -o -path "*/Index.noindex/Build/Products/${BUILD_CONFIGURATION}/${extension_name}" \) \
      -type d \
      -print 2>/dev/null
  )
}
# 清理同 Bundle ID 的旧注册记录，避免 Finder 发现阶段跳过当前扩展。
cleanup_stale_registration_records() {
  local key="$1"
  local app_path="$2"
  local extension_path="$3"
  local extension_id="${FEATURE_EXTENSION_ID[$key]}"
  local lsregister=""
  local registered_path=""

  lsregister="$(lsregister_path)"
  collect_registered_paths_for_feature "$key"

  note_echo "清理旧扩展注册记录：${extension_id}"
  for registered_path in "${REGISTERED_PATHS[@]}"; do
    [[ -z "$registered_path" ]] && continue
    if [[ "$registered_path" == "$app_path" || "$registered_path" == "$extension_path" ]]; then
      continue
    fi

    gray_echo "移除旧 LaunchServices 记录：${registered_path}"
    "$lsregister" -u "$registered_path" 2>&1 | tee -a "$LOG_FILE" || true

    if [[ -e "$registered_path" ]]; then
      /usr/bin/pluginkit -r "$registered_path" 2>&1 | tee -a "$LOG_FILE" || true
    fi
  done
}
# 先停止旧扩展进程，避免 Finder 持有旧构建产物。
stop_feature_processes() {
  local key="$1"
  local app_name="${FEATURE_APP_NAME[$key]}"
  local extension_process_name="${FEATURE_EXTENSION_NAME[$key]%.appex}"

  /usr/bin/pkill -x "$app_name" 2>/dev/null || true
  /usr/bin/pkill -f "${extension_process_name}.appex/Contents/MacOS/${extension_process_name}" 2>/dev/null || true
}
# 注册宿主 App 到 LaunchServices。
register_app_with_launchservices() {
  local app_path="$1"
  local lsregister=""
  local register_status=0

  lsregister="$(lsregister_path)"
  note_echo "注册宿主 App 到 LaunchServices：${app_path}"
  "$lsregister" -f "$app_path" 2>&1 | tee -a "$LOG_FILE"
  register_status=${pipestatus[1]}
  if (( register_status != 0 )); then
    error_echo "LaunchServices 注册失败：${app_path}"
    return "$register_status"
  fi

  return 0
}
# 后台初始化扩展；单文件授权、模拟器与代理配置宿主使用显式初始化参数。
open_host_for_extension_registration() {
  local key="$1"
  local app_path="$2"
  local open_arguments=(-gj "$app_path")

  if [[ "$key" == file-create ]]; then
    open_arguments+=(--args --initialize-finder-extension)
  fi
  if [[ "$key" == "run-authorize" || "$key" == "run-revoke" || "$key" == "ipa-resign" || "$key" == "hidden-files-toggle" || "$key" == "ios-tools" || "$key" == "ios-simulator-create" || "$key" == "android-simulator-create" || "$key" == "android-simulator-repair" || "$key" == "harmony-simulator-create" || "$key" == "harmony-simulator-repair" || "$key" == "git-proxy-configure" ]]; then
    open_arguments+=(--args --initialize-finder-extension)
  fi
  /usr/bin/open "${open_arguments[@]}"
}
# 注册并启用构建产物中的 Finder Sync Extension。
register_and_enable_feature() {
  local key="$1"
  local app_path=""
  local extension_path=""
  local extension_id="${FEATURE_EXTENSION_ID[$key]}"

  app_path="$(app_path_for_key "$key")"
  extension_path="$(extension_path_for_key "$key")"

  if [[ ! -d "$app_path" ]]; then
    error_echo "未找到构建后的 App：${app_path}"
    return 1
  fi

  if [[ ! -d "$extension_path" ]]; then
    error_echo "未找到构建后的 Finder Sync Extension：${extension_path}"
    return 1
  fi

  stop_feature_processes "$key"
  cleanup_stale_registration_records "$key" "$app_path" "$extension_path"
  register_app_with_launchservices "$app_path" || return 1

  note_echo "清除当前扩展旧登记：${extension_path}"
  /usr/bin/pluginkit -r "$extension_path" 2>&1 | tee -a "$LOG_FILE" || true

  note_echo "注册扩展：${extension_id}"
  /usr/bin/pluginkit -a "$extension_path" 2>&1 | tee -a "$LOG_FILE"
  if (( ${pipestatus[1]} != 0 )); then
    error_echo "pluginkit 注册失败：${extension_path}"
    return 1
  fi

  note_echo "启用扩展：${extension_id}"
  /usr/bin/pluginkit -e use -i "$extension_id" 2>&1 | tee -a "$LOG_FILE"
  if (( ${pipestatus[1]} != 0 )); then
    error_echo "pluginkit 启用失败：${extension_id}"
    return 1
  fi

  if wait_until_extension_enabled "$extension_id" "$extension_path"; then
    if [[ "$key" == flutter-tools ]]; then
      /bin/zsh "$WORKSPACE_DIR/JobsFlutterTools/Scripts/Tools/RetireLegacyFlutterMenus.zsh" || return 1
    fi
    success_echo "扩展已启用：${FEATURE_TITLE[$key]}"
    return 0
  fi

  warn_echo "扩展尚未进入启用状态，尝试后台启动宿主 App 完成自注册。"
  open_host_for_extension_registration "$key" "$app_path" 2>&1 | tee -a "$LOG_FILE" || true
  /bin/sleep 2
  if [[ "$key" == file-create ]]; then
    # 首次发现可能未落入 PlugInKit；仅重发启用不会补回缺失的登记。
    note_echo "重新登记新建文件扩展，再核验当前精确路径：${extension_path}"
    /usr/bin/pluginkit -a "$extension_path" 2>&1 | tee -a "$LOG_FILE"
    local registration_status=${pipestatus[1]}
    if (( registration_status != 0 )); then
      error_echo '新建文件扩展重新登记失败，已停止。'
      return "$registration_status"
    fi
  fi
  /usr/bin/pluginkit -e use -i "$extension_id" 2>&1 | tee -a "$LOG_FILE" || true

  if wait_until_extension_enabled "$extension_id" "$extension_path"; then
    if [[ "$key" == flutter-tools ]]; then
      /bin/zsh "$WORKSPACE_DIR/JobsFlutterTools/Scripts/Tools/RetireLegacyFlutterMenus.zsh" || return 1
    fi
    success_echo "扩展已启用：${FEATURE_TITLE[$key]}"
    return 0
  fi

  error_echo "扩展启用超时：${FEATURE_TITLE[$key]}"
  return 1
}
# 解析管理参数；非交互只接受明确的操作和非空功能清单。
parse_management_options() {
  local explicit_action=0
  while (( $# > 0 )); do
    case "$1" in
      --action|--scope|--features)
        (( $# >= 2 )) && [[ -n "$2" ]] || { print -u2 -- "参数缺少非空值：$1"; return 2; }
        case "$1" in
          --action) MANAGEMENT_ACTION="$2"; explicit_action=1 ;;
          --scope) FEATURE_SCOPE="$2" ;;
          --features) CLI_FEATURES="$2" ;;
        esac
        shift 2
        ;;
      --non-interactive) MANAGER_NON_INTERACTIVE=1; shift ;;
      --gui-session) MANAGER_GUI_SESSION=1; shift ;;
      *) print -u2 -- "未知参数：$1"; return 2 ;;
    esac
  done
  [[ "$MANAGEMENT_ACTION" == install || "$MANAGEMENT_ACTION" == uninstall ]] || return 2
  if (( MANAGER_NON_INTERACTIVE )); then
    (( explicit_action )) && [[ -n "$CLI_FEATURES" ]] || { print -u2 '非交互管理必须指定 --action 和 --features。'; return 2; }
  elif [[ -n "$CLI_FEATURES" ]]; then
    print -u2 '交互模式请用 --scope 限定面板；--features 仅用于明确授权的非交互编排。'
    return 2
  fi
  local identifier=""
  for identifier in ${(s:,:)FEATURE_SCOPE}; do
    (( ${SELECTABLE_FUNCTION_IDS[(Ie)$identifier]} )) || { print -u2 -- "未知范围：$identifier"; return 2; }
  done
  [[ -z "$CLI_FEATURES" ]] || validate_feature_scope "$CLI_FEATURES"
}
# 严格限制面板返回值；不能从单功能入口越过其声明范围。
validate_feature_scope() {
  local identifier="" scope_ids=(${(s:,:)FEATURE_SCOPE})
  [[ -n "$1" && "$1" != ,* && "$1" != *, && "$1" != *,,* ]] || return 1
  for identifier in ${(s:,:)1}; do
    (( ${SELECTABLE_FUNCTION_IDS[(Ie)$identifier]} )) || { print -u2 -- "未知功能：$identifier"; return 1; }
    if [[ -n "$FEATURE_SCOPE" ]] && (( ! ${scope_ids[(Ie)$identifier]} )); then
      print -u2 -- "功能超出当前管理范围：$identifier"
      return 1
    fi
  done
}
# 返回分组配置路径；所有写入都只作用于当前分组。
configuration_path_for_key() {
  case "$1" in
    flutter-tools) print -r -- "$FLUTTER_FEATURE_CONFIG_PATH" ;;
    terminal_opener) print -r -- "$TERMINAL_FEATURE_CONFIG_PATH" ;;
  esac
}
# 损坏的配置不能作为全选或旧默认值处理，防止意外重新启用其它菜单。
validate_group_configuration() {
  local key="$1" value="$2" identifier="" allowed=() seen=()
  [[ -n "$value" ]] || return 0
  [[ "$value" != ,* && "$value" != *, && "$value" != *,,* ]] || return 1
  if [[ "$key" == flutter-tools ]]; then
    allowed=("${FLUTTER_ACTION_IDS[@]}")
  else
    allowed=(open file-content file-merge file-split pod-install flutter-pub-get clean-build-artifacts codegraph-bootstrap git-empty-commit-push)
  fi
  for identifier in ${(s:,:)value}; do
    (( ${allowed[(Ie)$identifier]} && ! ${seen[(Ie)$identifier]} )) || return 1
    seen+=("$identifier")
  done
}
# 读取安装前的实际开关；Terminal 的旧安装从当前启用产物 Info 中恢复默认值。
read_group_configuration() {
  local key="$1" config_path="$(configuration_path_for_key "$1")"
  local registered_path="" value="" values=() metadata=""
  typeset -U values
  if [[ -e "$config_path" || -L "$config_path" ]]; then
    [[ -f "$config_path" && ! -L "$config_path" && -r "$config_path" ]] || return 1
    (( $(/usr/bin/wc -c < "$config_path") <= 8192 )) || return 1
    value="$(/bin/cat "$config_path")" || return 1
    validate_group_configuration "$key" "$value" || { print -u2 -- "功能配置损坏，已停止：$config_path"; return 1; }
    print -nr -- "$value"
    return 0
  fi
  metadata="$(/usr/bin/pluginkit -m -i "${FEATURE_EXTENSION_ID[$key]}" -A -D -vv 2>/dev/null)" || return 1
  if [[ "$key" == flutter-tools ]]; then
    if print -r -- "$metadata" | /usr/bin/awk '/^\+/ {found=1} END {exit !found}'; then
      print -nr -- "${(j:,:)FLUTTER_ACTION_IDS}"
    fi
    return 0
  fi
  while IFS= read -r registered_path; do
    [[ -n "$registered_path" ]] || continue
    registered_path="${registered_path%/Contents/PlugIns/${FEATURE_EXTENSION_NAME[$key]}}"
    [[ "${registered_path:t}" == JobsTerminalOpener.app && -d "$registered_path" && ! -L "$registered_path" ]] || return 1
    [[ -r "$registered_path/Contents/Info.plist" ]] || return 1
    /usr/libexec/PlistBuddy -c Print "$registered_path/Contents/Info.plist" >/dev/null 2>&1 || return 1
    value="$(/usr/libexec/PlistBuddy -c 'Print :JobsTerminalEnabledFeatures' "$registered_path/Contents/Info.plist" 2>/dev/null)" || value='open,pod-install,flutter-pub-get,clean-build-artifacts,codegraph-bootstrap,git-empty-commit-push'
    validate_group_configuration "$key" "$value" || return 1
    values+=(${(s:,:)value})
  done < <(print -r -- "$metadata" | /usr/bin/awk '/^[+!-]/ {enabled=($1=="+")} /Path = / && enabled {sub(/^.*Path = /, ""); print}')
  print -nr -- "${(j:,:)values}"
}
# 原子保存功能开关，失败时保留原文件，不删除或重写签名后的 App 资源。
write_group_configuration() {
  local config_path="$1" value="$2" temporary="" directory="${1:h}"
  [[ ! -L "$config_path" && ! -L "$directory" ]] || return 1
  /bin/mkdir -p "$directory" || return 1
  temporary="$(/usr/bin/mktemp "$directory/.features.XXXXXXXX")" || return 1
  if ! print -nr -- "$value" > "$temporary" || ! /bin/chmod 600 "$temporary" || ! /bin/mv -f "$temporary" "$config_path"; then
    /bin/rm -f "$temporary"
    return 1
  fi
}
# 只减去所选动作，保留未选动作和旧 Terminal 兼容项。
plan_group_feature_removal() {
  local key="$1" configured="" requested="" identifier="" remaining=() removed=()
  configured="$(read_group_configuration "$key")" || return 1
  case "$key" in
    flutter-tools) requested="$FLUTTER_TOOLS_ENABLED_FEATURES" ;;
    terminal_opener) requested="$TERMINAL_OPENER_ENABLED_FEATURES" ;;
  esac
  removed=(${(s:,:)requested})
  if [[ "$key" == terminal_opener ]]; then
    (( ${SELECTED_FUNCTION_IDS[(Ie)pod_install]} == 0 )) || removed+=(pod-install)
    (( ${SELECTED_FUNCTION_IDS[(Ie)flutter-pub-get]} == 0 )) || removed+=(flutter-pub-get)
    (( ${SELECTED_FUNCTION_IDS[(Ie)git_empty_commit_push]} == 0 )) || removed+=(git-empty-commit-push)
  fi
  for identifier in ${(s:,:)configured}; do
    (( ${removed[(Ie)$identifier]} )) || remaining+=("$identifier")
  done
  REMAINING_CONFIG_FEATURES="${(j:,:)remaining}"
  note_echo "${FEATURE_TITLE[$key]} 保留动作：${REMAINING_CONFIG_FEATURES:-无}"
}
# 一个公开管理入口包含安装和卸载两分支，独立工程仍可整体拷走使用。
run_independent_uninstall() {
  local key="$1" entries=("${WORKSPACE_DIR}/${FEATURE_PROJECT_DIR[$1]}/Scripts/ManageExtension.zsh"(N))
  (( ${#entries} == 1 )) || { error_echo "无法确定唯一的功能管理入口：$key"; return 1; }
  local arguments=(--action uninstall --non-interactive --skip-finder-restart)
  [[ "$key" != ios-tools ]] || arguments+=(--features "$IOS_TOOLS_ENABLED_FEATURES")
  JOBS_SKIP_FINDER_RESTART=1 /bin/zsh "${entries[1]}" "${arguments[@]}" 2>&1 | tee -a "$LOG_FILE"
  return ${pipestatus[1]}
}
# 与安装共用叶 ID 和安装单元映射；共享扩展只关闭勾选动作。
uninstall_feature() {
  local key="$1" identifier="" features=()
  if [[ "$key" == project-tools || "$key" == desktop-tools ]]; then
    for identifier in "${SELECTED_FUNCTION_IDS[@]}"; do
      [[ "${SELECTABLE_FUNCTION_PROJECT_KEY[$identifier]}" != "$key" ]] || features+=("$identifier")
    done
    if [[ "$key" == project-tools ]]; then
      JOBS_SKIP_FINDER_RESTART=1 /bin/zsh "$WORKSPACE_DIR/JobsProjectTools/Scripts/ManageProjectTools.zsh" uninstall "${features[@]}" 2>&1 | tee -a "$LOG_FILE"
    else
      JOBS_SKIP_FINDER_RESTART=1 /bin/zsh "$WORKSPACE_DIR/JobsDesktopTools/Scripts/ManageDesktopTools.zsh" uninstall "${features[@]}" --non-interactive --skip-finder-restart 2>&1 | tee -a "$LOG_FILE"
    fi
    return ${pipestatus[1]}
  fi
  if [[ "$key" == flutter-tools || "$key" == terminal_opener ]]; then
    plan_group_feature_removal "$key" || return 1
    if [[ -n "$REMAINING_CONFIG_FEATURES" ]]; then
      write_group_configuration "$(configuration_path_for_key "$key")" "$REMAINING_CONFIG_FEATURES"
      return $?
    fi
  fi
  run_independent_uninstall "$key" || return 1
  if [[ "$key" == terminal_opener ]]; then
    write_group_configuration "$TERMINAL_FEATURE_CONFIG_PATH" '' || return 1
  fi
  return 0
}
# 汇总到实际菜单功能；某一安装单元失败时继续汇报其它已选功能的结果。
uninstall_selected_features() {
  local key=""
  FINAL_EXIT_STATUS=0
  for key in "${SELECTED_KEYS[@]}"; do
    emit_project_progress "$key" running
    if uninstall_feature "$key"; then
      record_project_install_result "$key" 1
    else
      record_project_install_result "$key" 0
      FINAL_EXIT_STATUS=1
    fi
  done
}
# 保存 JobsTerminalOpener 的右键功能选择，供宿主 App 和 Finder 扩展共同读取。
persist_terminal_feature_selection() {
  local key="$1"

  [[ "$key" != "terminal_opener" ]] && return 0
  if ! /bin/mkdir -p "$TERMINAL_FEATURE_CONFIG_DIR"; then
    error_echo "无法创建 Terminal 功能配置目录：${TERMINAL_FEATURE_CONFIG_DIR}"
    return 1
  fi
  if ! print -nr -- "$TERMINAL_OPENER_ENABLED_FEATURES" > "$TERMINAL_FEATURE_CONFIG_PATH"; then
    error_echo "无法保存 Terminal 功能选择：${TERMINAL_FEATURE_CONFIG_PATH}"
    return 1
  fi

  success_echo "Terminal 功能选择已保存，之后可在 JobsTerminalOpener App 内修改。"
  return 0
}
# 已有 iOS 配置损坏时停止，不能把无法识别的旧选择解释为全部关闭。
validate_ios_configuration() {
  [[ -e "$IOS_FEATURE_CONFIG_PATH" || -L "$IOS_FEATURE_CONFIG_PATH" ]] || return 0
  [[ -f "$IOS_FEATURE_CONFIG_PATH" && ! -L "$IOS_FEATURE_CONFIG_PATH" && -r "$IOS_FEATURE_CONFIG_PATH" ]] || return 1
  local value="" identifier=""
  value="$(/bin/cat "$IOS_FEATURE_CONFIG_PATH")" || return 1
  [[ -n "$value" ]] || return 0
  [[ "$value" != ,* && "$value" != *, && "$value" != *,,* ]] || return 1
  for identifier in ${(s:,:)value}; do
    [[ "$identifier" != ios-clean-cache ]] || identifier=ios-clean-build-artifacts
    (( ${IOS_FUNCTION_IDS[(Ie)$identifier]} )) || { error_echo 'iOS 功能配置损坏，已停止。'; return 1; }
  done
}
# 合并已经安装的 iOS 子功能，原子写入用户配置；不改签名后的 App 资源。
persist_ios_feature_selection() {
  local key="$1"
  local existing_value="$IOS_EXISTING_DEFAULT_FEATURES"
  local feature_id=""
  local selected_id=""
  local enabled_features=()
  local temporary_path=""
  typeset -A enabled

  [[ "$key" != "ios-tools" ]] && return 0
  validate_ios_configuration || return 1
  if [[ -f "$IOS_FEATURE_CONFIG_PATH" ]]; then
    existing_value="$(<"$IOS_FEATURE_CONFIG_PATH")"
  fi
  for selected_id in ${(s:,:)existing_value} ${(s:,:)IOS_TOOLS_ENABLED_FEATURES}; do
    [[ "$selected_id" == ios-clean-cache ]] && selected_id=ios-clean-build-artifacts
    (( ${IOS_FUNCTION_IDS[(Ie)$selected_id]} )) && enabled[$selected_id]=1
  done
  for feature_id in "${IOS_FUNCTION_IDS[@]}"; do
    [[ "${enabled[$feature_id]:-0}" == 1 ]] && enabled_features+=("$feature_id")
  done
  if ! /bin/mkdir -p "$IOS_FEATURE_CONFIG_DIR"; then
    error_echo "无法创建 iOS 功能配置目录：${IOS_FEATURE_CONFIG_DIR}"
    return 1
  fi
  temporary_path="$(/usr/bin/mktemp "${IOS_FEATURE_CONFIG_DIR}/.features.XXXXXX")" || return 1
  if ! print -nr -- "${(j:,:)enabled_features}" > "$temporary_path" ||
     ! /bin/mv -f "$temporary_path" "$IOS_FEATURE_CONFIG_PATH"; then
    /bin/rm -f "$temporary_path"
    error_echo "无法保存 iOS 功能选择：${IOS_FEATURE_CONFIG_PATH}"
    return 1
  fi
  success_echo "iOS 辅助功能选择已合并保存：${(j:,:)enabled_features}"
  return 0
}
# 按本次勾选原子替换 Flutter 子菜单开关，取消的旧动作不会被合并回来。
persist_flutter_feature_selection() {
  local key="$1"
  local temporary_path=""

  [[ "$key" != flutter-tools ]] && return 0
  if ! /bin/mkdir -p "$FLUTTER_FEATURE_CONFIG_DIR"; then
    error_echo "无法创建 Flutter 功能配置目录：${FLUTTER_FEATURE_CONFIG_DIR}"
    return 1
  fi
  temporary_path="$(/usr/bin/mktemp "${FLUTTER_FEATURE_CONFIG_DIR}/.flutter-features.XXXXXX")" || return 1
  if ! print -nr -- "$FLUTTER_TOOLS_ENABLED_FEATURES" > "$temporary_path" ||
     ! /bin/mv -f "$temporary_path" "$FLUTTER_FEATURE_CONFIG_PATH"; then
    /bin/rm -f "$temporary_path"
    error_echo "无法保存 Flutter 功能选择：${FLUTTER_FEATURE_CONFIG_PATH}"
    return 1
  fi
  success_echo "Flutter 子菜单选择已保存：${FLUTTER_TOOLS_ENABLED_FEATURES}"
}
# 安装单个 Finder 扩展功能。
install_feature() {
  local key="$1"

  if [[ "$key" == desktop-tools ]]; then
    local selected_id="" desktop_features=()
    for selected_id in "${SELECTED_FUNCTION_IDS[@]}"; do
      [[ "${SELECTABLE_FUNCTION_PROJECT_KEY[$selected_id]}" == desktop-tools ]] && desktop_features+=("$selected_id")
    done
    JOBS_SKIP_FINDER_RESTART=1 /bin/zsh "$WORKSPACE_DIR/JobsDesktopTools/Scripts/ManageDesktopTools.zsh" install "${desktop_features[@]}" --non-interactive --skip-finder-restart 2>&1 | tee -a "$LOG_FILE"
    return ${pipestatus[1]}
  fi

  if [[ "$key" == project-tools ]]; then
    local selected_id="" project_features=()
    for selected_id in "${SELECTED_FUNCTION_IDS[@]}"; do
      [[ "${SELECTABLE_FUNCTION_PROJECT_KEY[$selected_id]}" == project-tools ]] && project_features+=("$selected_id")
    done
    JOBS_SKIP_FINDER_RESTART=1 /bin/zsh "$WORKSPACE_DIR/JobsProjectTools/Scripts/ManageProjectTools.zsh" install "${project_features[@]}" 2>&1 | tee -a "$LOG_FILE"
    return ${pipestatus[1]}
  fi

  highlight_echo "============================== ${FEATURE_TITLE[$key]} =============================="
  if [[ "$key" == ios-tools ]]; then
    validate_ios_configuration || return 1
    IOS_EXISTING_DEFAULT_FEATURES=""
    if [[ -n "$IOS_FEATURE_CONFIG_PATH" && ! -e "$IOS_FEATURE_CONFIG_PATH" ]]; then
      local existing_registration=""
      existing_registration="$(/usr/bin/pluginkit -m -i "${FEATURE_EXTENSION_ID[$key]}" -A -D -vv 2>/dev/null)" || return 1
      if print -r -- "$existing_registration" | /usr/bin/awk '/^\+/ {found=1} END {exit !found}'; then
        IOS_EXISTING_DEFAULT_FEATURES="${(j:,:)IOS_FUNCTION_IDS}"
      fi
    fi
  fi
  local previous_features="" added_features=()
  typeset -U added_features
  if [[ "$key" == flutter-tools || "$key" == terminal_opener ]]; then
    previous_features="$(read_group_configuration "$key")" || return 1
    if [[ "$key" == flutter-tools ]]; then
      added_features=(${(s:,:)previous_features} ${(s:,:)FLUTTER_TOOLS_ENABLED_FEATURES})
      FLUTTER_TOOLS_ENABLED_FEATURES="${(j:,:)added_features}"
    else
      added_features=(${(s:,:)previous_features} ${(s:,:)TERMINAL_OPENER_ENABLED_FEATURES})
      TERMINAL_OPENER_ENABLED_FEATURES="${(j:,:)added_features}"
    fi
  fi
  build_feature "$key" || return 1
  persist_ios_feature_selection "$key" || return 1
  register_and_enable_feature "$key" || return 1
  persist_flutter_feature_selection "$key" || return 1
  persist_terminal_feature_selection "$key" || return 1
  return 0
}
# 用机器可读行同步状态，不把估算时间当成真实百分比。
emit_feature_progress() {
  local identifier="$1" state="$2" message=""
  case "$state" in
    running) [[ "$MANAGEMENT_ACTION" == uninstall ]] && message='正在卸载' || message='正在安装 / 更新' ;;
    succeeded) message='成功' ;;
    failed) message='失败，请查看下方日志' ;;
  esac
  /usr/bin/printf '\nJOBS_MANAGER_EVENT\t%s\t%s\t%s\n' "$identifier" "$state" "$message"
}
# 同一工程的所选叶子共享构建与登记过程，逐叶报告当前单元状态。
emit_project_progress() {
  local key="$1" state="$2" identifier=""
  for identifier in "${SELECTED_FUNCTION_IDS[@]}"; do
    [[ "${SELECTABLE_FUNCTION_PROJECT_KEY[$identifier]}" == "$key" ]] || continue
    emit_feature_progress "$identifier" "$state"
  done
}
# 把一个工程的安装结果展开为用户勾选的右键菜单功能。
record_project_install_result() {
  local key="$1"
  local did_succeed="$2"
  local selected_function_id=""

  for selected_function_id in "${SELECTED_FUNCTION_IDS[@]}"; do
    [[ "${SELECTABLE_FUNCTION_PROJECT_KEY[$selected_function_id]}" != "$key" ]] && continue
    if [[ "$did_succeed" == "1" ]]; then
      SUCCEEDED_FEATURES+=("${SELECTABLE_FUNCTION_TITLE[$selected_function_id]}")
      emit_feature_progress "$selected_function_id" succeeded
    else
      FAILED_FEATURES+=("${SELECTABLE_FUNCTION_TITLE[$selected_function_id]}")
      emit_feature_progress "$selected_function_id" failed
    fi
  done
}
# 逐个安装用户选择的 Finder 扩展功能。
install_selected_features() {
  local key=""

  FINAL_EXIT_STATUS=0
  for key in "${SELECTED_KEYS[@]}"; do
    emit_project_progress "$key" running
    if ensure_feature_projects_exist "$key" && install_feature "$key"; then
      record_project_install_result "$key" "1"
    else
      record_project_install_result "$key" "0"
      FINAL_EXIT_STATUS=1
    fi
  done
}
# 安装成功后统一重启 Finder，刷新右键菜单缓存。
restart_finder_after_install() {
  if (( ${#SUCCEEDED_FEATURES[@]} == 0 )); then
    warn_echo "没有成功处理的功能，跳过 Finder 重启。"
    return 0
  fi

  note_echo "重启 Finder，刷新 Finder Sync 右键菜单缓存。"
  note_echo "重启 PlugInKit Daemon，刷新扩展发现索引。"
  /usr/bin/pkill -x pkd 2>/dev/null || true
  /usr/bin/killall Finder 2>&1 | tee -a "$LOG_FILE" || true
}
# 输出安装结果、日志路径和后续排查提示。
print_done_tips() {
  local feature_name=""

  echo ""
  if (( ${#SUCCEEDED_FEATURES[@]} > 0 )); then
    success_echo "${MANAGEMENT_ACTION} 成功："
    for feature_name in "${SUCCEEDED_FEATURES[@]}"; do
      gray_echo "- ${feature_name}"
    done
  fi

  if (( ${#FAILED_FEATURES[@]} > 0 )); then
    error_echo "${MANAGEMENT_ACTION} 失败："
    for feature_name in "${FAILED_FEATURES[@]}"; do
      gray_echo "- ${feature_name}"
    done
    gray_echo "请查看日志中的 xcodebuild / pluginkit 输出。"
  fi

  gray_echo "日志位置：${LOG_FILE}"
  gray_echo "如果 Finder 右键菜单仍未出现，请到 系统设置 -> 隐私与安全性 -> 扩展 -> Finder 扩展 中确认开关。"
  return "$FINAL_EXIT_STATUS"
}
# 复用同一面板和解析器；内部编排以明确功能清单代替重复打开窗口。
select_management_features() {
  if (( MANAGER_NON_INTERACTIVE )); then
    parse_feature_selection "$CLI_FEATURES" || return 1
  else
    select_features_with_ui
  fi
}
# 仅 worker 执行真实操作，界面进程不再等待选择器返回计划。
run_management_worker() {
  init_runtime
  parse_feature_selection "$CLI_FEATURES" || return $?
  print_selected_features
  check_environment
  if [[ "$MANAGEMENT_ACTION" == uninstall ]]; then
    uninstall_selected_features
  else
    install_selected_features
  fi
  restart_finder_after_install
  print_done_tips
}
# 公开脚本只启动 App；App 会话持续显示 GUI，后台 worker 才接触扩展。
dispatch_management_mode() {
  if (( MANAGER_NON_INTERACTIVE )); then
    run_management_worker
  else
    source "$WORKSPACE_DIR/Scripts/FinderManagerGUI.zsh" || return 1
    jobs_launch_finder_manager_gui "$SCRIPT_PATH" "$FEATURE_SCOPE" "$MANAGEMENT_ACTION" "$MANAGER_GUI_SESSION"
  fi
}
# 编排用途、模式校验与 GUI / worker 分流。
main() {
  show_script_intro_and_wait "$@" # GUI 以面板按钮确认，worker 展示已确认操作的范围。
  dispatch_management_mode # 普通入口打开 App，显式后台调用才执行安装或卸载。
}

main "$@"
