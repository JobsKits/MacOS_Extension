#!/bin/zsh
# Finder 固定动作分发；静态清理与相对引用修复无需 SDK，其余 SDK 操作使用项目 FVM。
setopt NO_NOMATCH PIPE_FAIL
TOOLS_DIR="${0:A:h}"
[[ $# == 2 && "$2" == /* && -d "$2" ]] || { print -u2 '用法：DispatchFlutterTools.zsh <动作> <Flutter项目绝对路径>'; exit 2; }
TOOLS_ACTION="$1"
TOOLS_PROJECT="${2:A}"
[[ -f "$TOOLS_PROJECT/pubspec.yaml" && ( "$TOOLS_ACTION" == clean-build-artifacts || -d "$TOOLS_PROJECT/lib" ) ]] || { print -u2 '请选择 Flutter 项目根目录。'; exit 1; }
export PATH="$PATH:$HOME/.pub-cache/bin:$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin"
cd -- "$TOOLS_PROJECT" || exit 1
# 静态产物清理不调用 SDK；先限定为 Flutter 根目录，避免绕过统一菜单清理原生项目。
if [[ "$TOOLS_ACTION" == clean-build-artifacts ]]; then
  [[ ! -L "$2" ]] || { print -u2 '目标必须是实际 Flutter 项目文件夹，不能是符号链接。'; exit 1; }
  TOOLS_PROJECT_KIND="$(/bin/zsh "$TOOLS_DIR/CleanBuildArtifacts.zsh" "$TOOLS_PROJECT" --detect)" || exit $?
  [[ "$TOOLS_PROJECT_KIND" == Flutter ]] || { print -u2 '请选择合法 Flutter 项目根目录；原生项目清理请使用对应工程菜单。'; exit 1; }
  exec /bin/zsh "$TOOLS_DIR/CleanBuildArtifacts.zsh" "$TOOLS_PROJECT"
fi
if [[ "$TOOLS_ACTION" == repair-package-imports ]]; then
  [[ ! -L "$2" ]] || { print -u2 '目标必须是实际 Flutter 项目文件夹，不能是符号链接。'; exit 1; }
  TOOLS_PROJECT_KIND="$(/bin/zsh "$TOOLS_DIR/CleanBuildArtifacts.zsh" "$TOOLS_PROJECT" --detect)" || exit $?
  [[ "$TOOLS_PROJECT_KIND" == Flutter ]] || { print -u2 '请选择合法 Flutter 项目根目录。'; exit 1; }
  exec /bin/zsh "$TOOLS_DIR/RepairPackageImports.zsh" --project "$TOOLS_PROJECT"
fi
if [[ "$TOOLS_ACTION" == sdk-manage ]]; then
  exec /bin/zsh "$TOOLS_DIR/ManageFlutterVersion.zsh" --project "$TOOLS_PROJECT"
fi
if [[ "$TOOLS_ACTION" == ohos-sdk-manage ]]; then
  exec /bin/zsh "$TOOLS_DIR/ManageHarmonyFlutterVersion.zsh" --project "$TOOLS_PROJECT"
fi
if [[ "$TOOLS_ACTION" == java-manage ]]; then
  exec /bin/zsh "$TOOLS_DIR/ManageProjectJava.zsh" --project "$TOOLS_PROJECT"
fi
if [[ ! -f .fvmrc && ! -f .fvm/fvm_config.json ]]; then
  print -u2 '✖ 本项目尚未通过 FVM 绑定 SDK。请先使用“安装/切换Flutter SDK版本”；不会回退到全局 Flutter。'
  exit 1
fi
# 只给使用原生工具链的动作绑定 Java，查看 SDK、解析依赖等仍可独立执行。
case "$TOOLS_ACTION" in
  run|package|package-android|package-ohos|native-doctor|harmony-doctor|repair-android)
    if [[ -e "$TOOLS_PROJECT/.java-version" || -L "$TOOLS_PROJECT/.java-version" ]]; then
      source "$TOOLS_DIR/ManageProjectJava.zsh" || exit $?
      pj_bind_project_java "$TOOLS_PROJECT" || exit $?
    fi
    ;;
esac
# 运行入口已有 FVM 缓存 / 断链恢复流程；声明存在时可交给它修复。
if [[ "$TOOLS_ACTION" == run ]]; then
  exec /bin/zsh "$TOOLS_DIR/RunFlutterProject.zsh" --project "$TOOLS_PROJECT"
fi
TOOLS_FLUTTER="$TOOLS_PROJECT/.fvm/flutter_sdk/bin/flutter"
TOOLS_DART="$TOOLS_PROJECT/.fvm/flutter_sdk/bin/cache/dart-sdk/bin/dart"
[[ -x "$TOOLS_FLUTTER" && -x "$TOOLS_DART" ]] || { print -u2 '✖ 项目 FVM SDK 不完整。请先安装/切换所需版本；不会调用全局 Flutter。'; exit 1; }
case "$TOOLS_ACTION" in
  pub-get) exec /bin/zsh "$TOOLS_DIR/InspectFlutterProject.zsh" "$TOOLS_PROJECT" pub-get ;;
  extract) exec /bin/zsh "$TOOLS_DIR/ExtractFlutterDependencies.zsh" "$TOOLS_PROJECT" ;;
  sdk-version) exec /bin/zsh "$TOOLS_DIR/InspectFlutterSdkVersion.zsh" --project "$TOOLS_PROJECT" ;;
  package) exec /bin/zsh "$TOOLS_DIR/PackageFlutter.zsh" --project "$TOOLS_PROJECT" ;;
  package-ios|package-android|package-ohos)
    exec /bin/zsh "$TOOLS_DIR/PackageFlutter.zsh" --project "$TOOLS_PROJECT" --platform "${TOOLS_ACTION#package-}" ;;
  codegen) exec /bin/zsh "$TOOLS_DIR/GenerateFlutterCode.zsh" "$TOOLS_PROJECT" ;;
  repair-android) exec /bin/zsh "$TOOLS_DIR/RepairAndroidSdk.zsh" "$TOOLS_PROJECT" ;;
  native-doctor|harmony-doctor|repair-imports|repair-namespace|maintenance)
    exec "$TOOLS_DART" "$TOOLS_DIR/FlutterProjectTools.dart" "$TOOLS_ACTION" "$TOOLS_PROJECT" ;;
  *) print -u2 '未知 Flutter 工具动作。'; exit 2 ;;
esac
