#!/bin/zsh
# 来源：JobsCommand@Flutter Android SDK / platforms 修复工具；复用已验证的官方工具引导。
# 限定当前项目，使用 FVM；不写 flutter config、Shell 配置或自动同意许可证。
setopt NO_NOMATCH PIPE_FAIL
REPAIR_PROJECT="${1:A}"
REPAIR_TOOLS="${0:A:h}"
[[ $# == 1 && -f "$REPAIR_PROJECT/pubspec.yaml" && -d "$REPAIR_PROJECT/android" && -x "$REPAIR_PROJECT/.fvm/flutter_sdk/bin/flutter" ]] || {
  print -u2 '请选择已绑定 FVM 且包含 android/ 的 Flutter 项目。'; exit 1
}
print -r -- '━━━━━━━━━━ 修复 Android SDK / platforms 缺失 ━━━━━━━━━━'
print -r -- "项目：$REPAIR_PROJECT"
print -r -- '回车授权补齐所需 Java、官方命令行工具及 Android 构建组件；许可仍由本人阅读接受。'
print -r -- '只为此项目更新 android/local.properties（先备份），不安装 Flutter、不改全局配置。'
[[ -t 0 ]] || { print -u2 '请在交互终端运行。'; exit 1; }
IFS= read -r 'answer?回车继续，任意非空输入取消：' || exit 130
[[ -z "$answer" ]] || exit 0
source "$REPAIR_TOOLS/AndroidSdkSupport.zsh"
android_prepare_context
ANDROID_SIM_MODE=prepare
android_initialize_runtime || exit $?
# Honor the project's existing SDK location, including escaped spaces, before considering defaults.
config="$REPAIR_PROJECT/android/local.properties"
[[ ! -L "$config" ]] || { android_log '✖ local.properties 是链接，未修改。'; exit 1; }
if [[ -f "$config" ]]; then
  project_sdk="$(/usr/bin/perl -ne 'if (/^\s*sdk\.dir\s*=\s*(.*)$/) { my $v=$1; $v =~ s/\\([\\:=#! ])/$1/g; print $v; exit }' "$config")"
  if [[ -n "$project_sdk" ]]; then
    [[ "$project_sdk" == /* ]] || { android_log '✖ 项目 sdk.dir 不是绝对路径，请先修正。'; exit 1; }
    export ANDROID_HOME="$project_sdk"
  fi
fi
android_configure_network && android_detect_architecture && android_ensure_sdk && android_ensure_java && android_ensure_command_tools || exit $?

REPAIR_FILES=("$REPAIR_PROJECT"/android/app/build.gradle{,.kts}(N))
REPAIR_API=""
if (( ${#REPAIR_FILES} )); then
REPAIR_API="$(/usr/bin/perl -0777 -ne 'if (/compileSdk(?:Version)?\s*(?:=\s*)?(\d+)/) { print $1; exit }' "${REPAIR_FILES[@]}")"
fi
if [[ -z "$REPAIR_API" ]]; then
  REPAIR_FILES=("$REPAIR_PROJECT"/.fvm/flutter_sdk/packages/flutter_tools/gradle/src/main/kotlin/FlutterExtension.kt(N) "$REPAIR_PROJECT"/.fvm/flutter_sdk/packages/flutter_tools/gradle/src/main/groovy/flutter.groovy(N))
  if (( ${#REPAIR_FILES} )); then
  REPAIR_API="$(/usr/bin/perl -0777 -ne 'if (/compileSdkVersion\s*=\s*(\d+)/) { print $1; exit }' "${REPAIR_FILES[@]}")"
  fi
fi
catalog="$(android_timed 120 "$ANDROID_SIM_SDKMANAGER" --sdk_root="$ANDROID_SIM_SDK" --list --channel=0 "${ANDROID_SIM_SDK_PROXY[@]}" 2>>"$LOG_FILE")" || { android_log '✖ 无法读取官方组件清单。'; exit 1; }
if [[ -z "$REPAIR_API" ]]; then
  REPAIR_API="$(print -r -- "$catalog" | /usr/bin/sed -nE 's/^[[:space:]]*platforms;android-([0-9]+)[[:space:]]*\|.*/\1/p' | /usr/bin/sort -nu | /usr/bin/tail -1)"
fi
[[ "$REPAIR_API" == <-> ]] || { android_log '✖ 无法确定项目 compileSdk；未安装猜测的版本。'; exit 1; }
REPAIR_BUILD_TOOLS="$(print -r -- "$catalog" | /usr/bin/sed -nE 's/^[[:space:]]*build-tools;([0-9]+\.[0-9]+\.[0-9]+)[[:space:]]*\|.*/\1/p' | /usr/bin/sort -t. -k1,1n -k2,2n -k3,3n | /usr/bin/tail -1)"
REPAIR_FILES=("$REPAIR_PROJECT"/android/app/build.gradle{,.kts}(N))
if (( ${#REPAIR_FILES} )); then
  pinned_build="$(/usr/bin/perl -0777 -ne 'if (/buildToolsVersion\s*(?:=\s*)?["\x27](\d+\.\d+\.\d+)/) { print $1; exit }' "${REPAIR_FILES[@]}")"
  [[ -z "$pinned_build" ]] || REPAIR_BUILD_TOOLS="$pinned_build"
fi
[[ -n "$REPAIR_BUILD_TOOLS" ]] || { android_log '✖ 未找到稳定版 build-tools。'; exit 1; }
android_log "计划：platform-tools；platforms;android-$REPAIR_API；build-tools;$REPAIR_BUILD_TOOLS"
[[ -x "$ANDROID_SIM_SDK/platform-tools/adb" ]] || android_install_package platform-tools || exit $?
[[ -f "$ANDROID_SIM_SDK/platforms/android-$REPAIR_API/android.jar" ]] || android_install_package "platforms;android-$REPAIR_API" || exit $?
[[ -x "$ANDROID_SIM_SDK/build-tools/$REPAIR_BUILD_TOOLS/aapt2" ]] || android_install_package "build-tools;$REPAIR_BUILD_TOOLS" || exit $?
[[ -f "$ANDROID_SIM_SDK/platforms/android-$REPAIR_API/android.jar" && -x "$ANDROID_SIM_SDK/platform-tools/adb" && -x "$ANDROID_SIM_SDK/build-tools/$REPAIR_BUILD_TOOLS/aapt2" ]] || { android_log '✖ 组件复检失败，保留已安装内容。'; exit 1; }
config="$REPAIR_PROJECT/android/local.properties"
[[ ! -L "$config" && ( ! -e "$config" || -f "$config" ) ]] || { android_log '✖ local.properties 不是普通文件，未改写。'; exit 1; }
backup="$(/usr/bin/mktemp -d "$REPAIR_PROJECT/android/.jobs-sdk-backup.XXXXXX")" || exit 1
if [[ -f "$config" ]]; then /bin/cp -p "$config" "$backup/local.properties" || exit 1; fi
REPAIR_SDK_VALUE="$ANDROID_SIM_SDK" /usr/bin/perl -e '
  use strict; use warnings;
  my $path=shift; my $text="";
  if (-e $path) { open my $in,"<",$path or die $!; local $/; $text=<$in>; close $in; }
  $text =~ s/^sdk\.dir\s*=.*(?:\r?\n|$)//mg;
  my $sdk=$ENV{REPAIR_SDK_VALUE}; $sdk =~ s/([\\:=#! ])/\\$1/g;
  print $text; print "\n" if length($text) && $text !~ /\n$/; print "sdk.dir=$sdk\n";
' "$config" > "$backup/next.properties" || exit 1
/bin/mv "$backup/next.properties" "$config" || exit 1
android_log "✔ Android SDK 与构建组件已验证；项目 sdk.dir 已更新。备份：$backup"
android_log "Flutter 使用项目 FVM：$REPAIR_PROJECT/.fvm/flutter_sdk；可继续运行原生Flutter项目体检。"
