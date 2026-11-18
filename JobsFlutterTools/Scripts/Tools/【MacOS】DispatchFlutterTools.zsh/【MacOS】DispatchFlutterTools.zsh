#!/bin/zsh
# Finder 固定动作分发；静态清理与相对引用修复无需 SDK，其余 SDK 操作使用项目 FVM。
# 校验固定动作并交给原业务入口，取消和退出码由该入口保持。
# JOBS_SOURCE_LAYOUT_V1：源码同名包装与发布旧平铺目录分别解析，不改变运行时资源名。
# 保留实际文件路径；只有源码同名包装才向上还原原资源目录。
jobs_layout_directory() {
  local file="${1:A}" directory="${1:A:h}" levels="${2:-0}"
  [[ "${directory:t}" != "${file:t}" ]] || directory="${directory:h}"
  while (( levels > 0 )); do
    directory="${directory:h}"
    (( levels -= 1 ))
  done
  print -r -- "$directory"
}
# 优先兼容已发布的平铺文件，再尝试源码中的同名包装；不跟随链接文件。
jobs_layout_file() {
  local file="$1" directory="${1:h}" name="${1:t}" candidate="" prefixed=""
  if [[ -f "$file" && ! -L "$file" ]]; then
    print -r -- "$file"
    return 0
  fi
  case "$name" in
    EnableFinderExtension.zsh) prefixed="【MacOS@Xcode】$name" ;;
    *.zsh|*.command|*.sh) [[ "$name" == '【MacOS'* ]] && prefixed="$name" || prefixed="【MacOS】$name" ;;
    *.jxa) prefixed="$name" ;;
    *) print -r -- "$file"; return 0 ;;
  esac
  [[ "${directory:t}" != "$name" ]] || directory="${directory:h}"
  candidate="$directory/$prefixed/$prefixed"
  if [[ ! -L "$directory/$prefixed" && -f "$candidate" && ! -L "$candidate" ]]; then
    print -r -- "$candidate"
  else
    print -r -- "$file"
  fi
}

dispatch_flutter_tools() {
  setopt NO_NOMATCH PIPE_FAIL
  TOOLS_DIR="$(jobs_layout_directory "$ZSH_ARGZERO")"
  [[ $# == 2 && "$2" == /* && ( -d "$2" || ( "$1" == run && -f "$2" && ! -L "$2" ) ) ]] || { print -u2 '用法：DispatchFlutterTools.zsh <动作> <Flutter项目绝对路径>'; exit 2; }
  TOOLS_ACTION="$1"
  TOOLS_SELECTION="${2:a}"
  TOOLS_PROJECT="$TOOLS_SELECTION"
  if [[ "$TOOLS_ACTION" == run && -f "$TOOLS_SELECTION" ]]; then
    TOOLS_PROJECT="$(/usr/bin/osascript -l JavaScript "$(jobs_layout_file "$TOOLS_DIR/FlutterRunner.jxa")" run-project "$TOOLS_SELECTION")" || exit $?
  fi
  [[ -f "$TOOLS_PROJECT/pubspec.yaml" && ( "$TOOLS_ACTION" == clean-build-artifacts || "$TOOLS_ACTION" == import-dependencies || "$TOOLS_ACTION" == import-private-dependencies || "$TOOLS_ACTION" == import-all-dependencies || "$TOOLS_ACTION" == export-all-dependencies || -d "$TOOLS_PROJECT/lib" ) ]] || { print -u2 '请选择 Flutter 项目根目录。'; exit 1; }
  export PATH="$PATH:$HOME/.pub-cache/bin:$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin"
  cd -- "$TOOLS_PROJECT" || exit 1
  # 迁移内核只读写本地文件，先于工程 FVM 门禁解析已有原生 Dart。
  case "$TOOLS_ACTION" in
    export-all-dependencies|import-all-dependencies)
      exec /bin/zsh "$TOOLS_DIR/【MacOS】一键迁移Flutter依赖.zsh/【MacOS】一键迁移Flutter依赖.zsh" --project "$TOOLS_PROJECT" --mode "${TOOLS_ACTION%%-*}" ;;
  esac
  # 静态产物清理不调用 SDK；先限定为 Flutter 根目录，避免绕过统一菜单清理原生项目。
  if [[ "$TOOLS_ACTION" == clean-build-artifacts ]]; then
    [[ ! -L "$2" ]] || { print -u2 '目标必须是实际 Flutter 项目文件夹，不能是符号链接。'; exit 1; }
    TOOLS_PROJECT_KIND="$(/bin/zsh "$(jobs_layout_file "$TOOLS_DIR/CleanBuildArtifacts.zsh")" "$TOOLS_PROJECT" --detect)" || exit $?
    [[ "$TOOLS_PROJECT_KIND" == Flutter ]] || { print -u2 '请选择合法 Flutter 项目根目录；原生项目清理请使用对应工程菜单。'; exit 1; }
    exec /bin/zsh "$(jobs_layout_file "$TOOLS_DIR/CleanBuildArtifacts.zsh")" "$TOOLS_PROJECT"
  fi
  if [[ "$TOOLS_ACTION" == repair-package-imports ]]; then
    [[ ! -L "$2" ]] || { print -u2 '目标必须是实际 Flutter 项目文件夹，不能是符号链接。'; exit 1; }
    TOOLS_PROJECT_KIND="$(/bin/zsh "$(jobs_layout_file "$TOOLS_DIR/CleanBuildArtifacts.zsh")" "$TOOLS_PROJECT" --detect)" || exit $?
    [[ "$TOOLS_PROJECT_KIND" == Flutter ]] || { print -u2 '请选择合法 Flutter 项目根目录。'; exit 1; }
    exec /bin/zsh "$(jobs_layout_file "$TOOLS_DIR/RepairPackageImports.zsh")" --project "$TOOLS_PROJECT"
  fi
  if [[ "$TOOLS_ACTION" == sdk-manage ]]; then
    exec /bin/zsh "$(jobs_layout_file "$TOOLS_DIR/ManageFlutterVersion.zsh")" --project "$TOOLS_PROJECT"
  fi
  if [[ "$TOOLS_ACTION" == ohos-sdk-manage ]]; then
    exec /bin/zsh "$(jobs_layout_file "$TOOLS_DIR/ManageHarmonyFlutterVersion.zsh")" --project "$TOOLS_PROJECT"
  fi
  if [[ "$TOOLS_ACTION" == java-manage ]]; then
    exec /bin/zsh "$(jobs_layout_file "$TOOLS_DIR/ManageProjectJava.zsh")" --project "$TOOLS_PROJECT"
  fi
  # 环境配置自行选择 FVM / 系统 SDK，Gradle 入口按项目 Java 检查，须在旧 FVM 门禁前转交。
  if [[ "$TOOLS_ACTION" == project-setup ]]; then
    exec /bin/zsh "$(jobs_layout_file "$TOOLS_DIR/SetupFlutterProject.zsh")" --project "$TOOLS_PROJECT"
  fi
  if [[ "$TOOLS_ACTION" == gradle-download ]]; then
    exec /bin/zsh "$(jobs_layout_file "$TOOLS_DIR/DownloadProjectGradle.zsh")" --project "$TOOLS_PROJECT"
  fi
  # 每类独立菜单与一键配置共用依赖内核，不能被旧 FVM 硬门禁挡住准备流程。
  case "$TOOLS_ACTION" in
    android-dependencies) exec /bin/zsh "$(jobs_layout_file "$TOOLS_DIR/FetchProjectDependencies.zsh")" --project "$TOOLS_PROJECT" --kind android ;;
    pods-dependencies) exec /bin/zsh "$(jobs_layout_file "$TOOLS_DIR/FetchProjectDependencies.zsh")" --project "$TOOLS_PROJECT" --kind pods ;;
    spm-dependencies) exec /bin/zsh "$(jobs_layout_file "$TOOLS_DIR/FetchProjectDependencies.zsh")" --project "$TOOLS_PROJECT" --kind spm ;;
    ohos-dependencies) exec /bin/zsh "$(jobs_layout_file "$TOOLS_DIR/FetchProjectDependencies.zsh")" --project "$TOOLS_PROJECT" --kind ohos ;;
    native-dependencies) exec /bin/zsh "$(jobs_layout_file "$TOOLS_DIR/FetchProjectDependencies.zsh")" --project "$TOOLS_PROJECT" --kind native ;;
    flutter-precache) exec /bin/zsh "$(jobs_layout_file "$TOOLS_DIR/FetchProjectDependencies.zsh")" --project "$TOOLS_PROJECT" --kind precache ;;
    web-dependencies) exec /bin/zsh "$(jobs_layout_file "$TOOLS_DIR/FetchProjectDependencies.zsh")" --project "$TOOLS_PROJECT" --kind web ;;
  esac
  # 平台快照操作分别核对缓存兼容性；不使用旧 Pub 源码导入逻辑覆盖原生缓存。
  case "$TOOLS_ACTION" in
    export-gradle-dependencies|import-gradle-dependencies|export-pods-dependencies|import-pods-dependencies|export-spm-dependencies|import-spm-dependencies|export-ohos-dependencies|import-ohos-dependencies|export-native-dependencies|import-native-dependencies|export-precache-dependencies|import-precache-dependencies|export-web-dependencies|import-web-dependencies)
      ARCHIVE_MODE="${TOOLS_ACTION%%-*}"
      ARCHIVE_KIND="${TOOLS_ACTION#*-}"
      ARCHIVE_KIND="${ARCHIVE_KIND%-dependencies}"
      exec /bin/zsh "$(jobs_layout_file "$TOOLS_DIR/ArchiveProjectDependencies.zsh")" --project "$TOOLS_PROJECT" --mode "$ARCHIVE_MODE" --kind "$ARCHIVE_KIND" ;;
  esac
  # 拉取依赖由业务入口先确认，再按需绑定 / 修复 SDK，不能被旧门禁提前拦截。
  if [[ "$TOOLS_ACTION" == pub-get ]]; then
    exec /bin/zsh "$(jobs_layout_file "$TOOLS_DIR/InspectFlutterProject.zsh")" "$TOOLS_PROJECT" pub-get
  fi
  if [[ ! -f .fvmrc && ! -f .fvm/fvm_config.json ]]; then
    print -u2 '✖ 本项目尚未通过 FVM 绑定 SDK。请先使用“安装/切换Flutter SDK版本”；不会回退到全局 Flutter。'
    exit 1
  fi
  # 只给使用原生工具链的动作绑定 Java，查看 SDK、解析依赖等仍可独立执行。
  case "$TOOLS_ACTION" in
    run|package|package-android|package-ohos|native-doctor|harmony-doctor|repair-android)
      if [[ -e "$TOOLS_PROJECT/.java-version" || -L "$TOOLS_PROJECT/.java-version" ]]; then
        source "$(jobs_layout_file "$TOOLS_DIR/ManageProjectJava.zsh")" || exit $?
        pj_bind_project_java "$TOOLS_PROJECT" || exit $?
      fi
      ;;
  esac
  # 运行入口已有 FVM 缓存 / 断链恢复流程；声明存在时可交给它修复。
  if [[ "$TOOLS_ACTION" == run ]]; then
    exec /bin/zsh "$(jobs_layout_file "$TOOLS_DIR/RunFlutterProject.zsh")" --project "$TOOLS_SELECTION"
  fi
  TOOLS_FLUTTER="$TOOLS_PROJECT/.fvm/flutter_sdk/bin/flutter"
  TOOLS_DART="$TOOLS_PROJECT/.fvm/flutter_sdk/bin/cache/dart-sdk/bin/dart"
  [[ -x "$TOOLS_FLUTTER" && -x "$TOOLS_DART" ]] || { print -u2 '✖ 项目 FVM SDK 不完整。请先安装/切换所需版本；不会调用全局 Flutter。'; exit 1; }
  case "$TOOLS_ACTION" in
    export-private-dependencies) exec /bin/zsh "$(jobs_layout_file "$TOOLS_DIR/ExtractFlutterDependencies.zsh")" --private-only "$TOOLS_PROJECT" ;;
    import-private-dependencies) exec /bin/zsh "$(jobs_layout_file "$TOOLS_DIR/ImportFlutterDependencies.zsh")" --private-only "$TOOLS_PROJECT" ;;
    extract) exec /bin/zsh "$(jobs_layout_file "$TOOLS_DIR/ExtractFlutterDependencies.zsh")" "$TOOLS_PROJECT" ;;
    import-dependencies) exec /bin/zsh "$(jobs_layout_file "$TOOLS_DIR/ImportFlutterDependencies.zsh")" "$TOOLS_PROJECT" ;;
    sdk-version) exec /bin/zsh "$(jobs_layout_file "$TOOLS_DIR/InspectFlutterSdkVersion.zsh")" --project "$TOOLS_PROJECT" ;;
    package) exec /bin/zsh "$(jobs_layout_file "$TOOLS_DIR/PackageFlutter.zsh")" --project "$TOOLS_PROJECT" ;;
    package-ohos)
      [[ ! -L "$2" && -d "$TOOLS_PROJECT/lib" && ! -L "$TOOLS_PROJECT/lib" &&
         -d "$TOOLS_PROJECT/ohos" && ! -L "$TOOLS_PROJECT/ohos" &&
         -f "$TOOLS_PROJECT/ohos/build-profile.json5" && ! -L "$TOOLS_PROJECT/ohos/build-profile.json5" &&
         -f "$TOOLS_PROJECT/ohos/oh-package.json5" && ! -L "$TOOLS_PROJECT/ohos/oh-package.json5" ]] || {
        print -u2 '✖ 请选择已适配的鸿蒙 Flutter 根目录（普通 ohos 目录与两份清单）。'; exit 1
      }
      # 一次请求固定生成安装模块和发布包，忽略终端遗留的模式与 flavor。
      exec /usr/bin/env FLAVOR= /bin/zsh "$(jobs_layout_file "$TOOLS_DIR/PackageFlutter.zsh")" --project "$TOOLS_PROJECT" --platform ohos --ohos-target all --mode release ;;
    package-ios|package-android)
      exec /bin/zsh "$(jobs_layout_file "$TOOLS_DIR/PackageFlutter.zsh")" --project "$TOOLS_PROJECT" --platform "${TOOLS_ACTION#package-}" ;;
    codegen) exec /bin/zsh "$(jobs_layout_file "$TOOLS_DIR/GenerateFlutterCode.zsh")" "$TOOLS_PROJECT" ;;
    repair-android) exec /bin/zsh "$(jobs_layout_file "$TOOLS_DIR/RepairAndroidSdk.zsh")" "$TOOLS_PROJECT" ;;
    native-doctor|harmony-doctor|repair-imports|repair-namespace|maintenance)
      exec "$TOOLS_DART" "$TOOLS_DIR/FlutterProjectTools.dart" "$TOOLS_ACTION" "$TOOLS_PROJECT" ;;
    *) print -u2 '未知 Flutter 工具动作。'; exit 2 ;;
  esac
}
# 转发器不重复读取业务确认。
main() {
  dispatch_flutter_tools "$@" # 解析来源目录并派发唯一动作。
}
main "$@"
