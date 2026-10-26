#!/bin/zsh
# 脚本自述：
# - 脚本名称：DispatchIOSTools.zsh
# - 核心用途：将固定 iOS 动作与 Finder 选择的项目目录交给随包脚本。
# - 影响范围：按原脚本处理项目、缓存或 CocoaPods 环境；所有原确认继续生效。
# - 运行提示：Terminal 中阅读原脚本自述并确认；--plan 只检查映射，Ctrl+C 取消。
# shell: zsh

SCRIPT_DIR=""
PROJECT_DIR=""
ACTION=""
SCRIPT_FILE=""
PLAN=0

intro_line() {
  local role="$1"
  local message="$2"
  if [[ -t 1 && -n "${TERM:-}" && "${TERM}" != dumb && -z "${NO_COLOR+x}" ]]; then
    if [[ "$role" == title ]]; then
      /usr/bin/printf '\033[1;31m%s\033[0m\n' "$message"
    else
      /usr/bin/printf '\033[0;34m%s\033[0m\n' "$message"
    fi
  else
    print -r -- "$message"
  fi
}

show_script_intro_and_wait() {
  intro_line title '━━━━━━━━━━ iOS / CocoaPods 辅助工具 ━━━━━━━━━━'
  intro_line body '1、用途：在 Finder 选择的项目执行随包工具，原脚本的回车与危险确认均保留。'
  intro_line body '2、影响：具体动作可能清理缓存、修改 Podfile / Xcode 配置、安装工具或更新依赖。'
  intro_line body '3、策略：先校验项目与固定动作，再进入原脚本；--plan 只读检查。Ctrl+C 取消。'
  intro_line body '4、日志：原脚本各自在系统临时目录保存日志；终端显示完整过程。'
}

initialize_runtime() {
  setopt NO_NOMATCH PIPE_FAIL
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")" && pwd)"
}

resolve_request() {
  [[ "${1:-}" != --plan ]] || { PLAN=1; shift; }
  (( $# == 2 )) || { print -u2 -r -- '✖ 需要固定动作与一个项目目录。'; exit 1; }
  ACTION="$1"
  PROJECT_DIR="$2"
  [[ "$ACTION" != ios-clean-cache ]] || ACTION=ios-clean-build-artifacts
  case "$ACTION" in
    ios-clean-build-artifacts) SCRIPT_FILE="CleanBuildArtifacts.zsh" ;;
    ios-disable-sandbox) SCRIPT_FILE="【MacOS】⚙️双击禁用沙盒保证Cocoapods构建流程.command" ;;
    ios-install-cocoapods) SCRIPT_FILE="【MacOS】⚙️双击安装Cocoapods.command" ;;
    ios-pods-source-github) SCRIPT_FILE="【MacOS】⚙️双击更换Cocoapods源[-]CDN[+]Github.command" ;;
    ios-extract-pods) SCRIPT_FILE="【MacOS】⏳提取项目中所有的pod相关文件.command" ;;
    ios-pod-update) SCRIPT_FILE="【MacOS】⬆️Pod_Update.command" ;;
    ios-xcode-dependencies) SCRIPT_FILE="【MacOS】🔍查询Xcode工程依赖关系.command" ;;
    ios-pod-repo-update) SCRIPT_FILE="【MacOS】⬆️双击更新Cocoapods本地仓库.command" ;;
    ios-pod-build-check) SCRIPT_FILE="【MacOS】自检具体的某个本地pod是否能编译通过.command" ;;
    ios-code-snippets) SCRIPT_FILE="【MacOS】⚙️双击安装JobsCodeSnippets.command" ;;
    *) print -u2 -r -- '✖ 未知动作，停止。'; exit 1 ;;
  esac
  [[ "$PROJECT_DIR" == /* && -d "$PROJECT_DIR" && ! -L "$PROJECT_DIR" ]] || { print -u2 -r -- '✖ 目标须为一个绝对路径的普通项目目录。'; exit 1; }
  PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd -P)" || exit 1
  [[ "$PROJECT_DIR" != "${HOME%/}/Desktop" ]] || { print -u2 -r -- '✖ 系统桌面不提供此工具。'; exit 1; }
  local -a podspecs=("$PROJECT_DIR"/*.podspec(ND.))
  local -a xcodeprojects=("$PROJECT_DIR"/*.xcodeproj(ND/))
  local -a workspaces=("$PROJECT_DIR"/*.xcworkspace(ND/))
  (( ${#podspecs[@]} + ${#xcodeprojects[@]} + ${#workspaces[@]} > 0 )) ||
    [[ -f "$PROJECT_DIR/Podfile" || -f "$PROJECT_DIR/Package.swift" ]] || { print -u2 -r -- '✖ 当前目录没有 iOS / CocoaPods 工程标记。'; exit 1; }
  if [[ "$ACTION" == ios-pod-build-check && ${#podspecs[@]} == 0 ]]; then
    print -u2 -r -- '✖ 本地 Pod 自检仅支持当前目录直接存在 *.podspec。'
    exit 1
  fi
  if [[ "$ACTION" == ios-clean-build-artifacts ]]; then
    [[ "$(/bin/zsh -f "$SCRIPT_DIR/CleanBuildArtifacts.zsh" "$PROJECT_DIR" --detect)" == iOS/Xcode ]] || {
      print -u2 -r -- '✖ 当前目录不是可识别的 iOS/Xcode 构建产物清理目标。'
      exit 1
    }
  fi
  [[ -f "$SCRIPT_DIR/$SCRIPT_FILE" ]] || { print -u2 -r -- '✖ 缺少随包业务脚本，请重新安装。'; exit 1; }
}

run_business() {
  print -r -- "动作：$ACTION"
  print -r -- "目标：$PROJECT_DIR"
  print -r -- "来源：$SCRIPT_DIR/$SCRIPT_FILE"
  (( PLAN == 0 )) || { print -r -- '✔ 只读计划通过，未运行业务。'; return 0; }
  [[ -t 0 ]] || { print -u2 -r -- '✖ 请在可交互终端运行。'; return 1; }
  cd "$PROJECT_DIR" || return 1
  # 通过环境数据传递，禁止 eval、拼接可执行源码或自动喂入确认。
  export JOBS_IOS_PROJECT_DIR="$PROJECT_DIR"
  if [[ "$ACTION" == ios-clean-build-artifacts ]]; then
    /bin/zsh -f "$SCRIPT_DIR/$SCRIPT_FILE" "$PROJECT_DIR"
  elif [[ "$ACTION" == ios-code-snippets ]]; then
    /bin/zsh -f "$SCRIPT_DIR/$SCRIPT_FILE" --finder "$PROJECT_DIR"
  else
    /bin/zsh -f "$SCRIPT_DIR/$SCRIPT_FILE"
  fi
}

main() {
  show_script_intro_and_wait # 展示随包动作的用途、影响与取消方式。
  initialize_runtime # 准备本脚本路径与选项。
  resolve_request "$@" # 验证固定动作、目标目录与同层 Pod 条件。
  run_business # 只读计划或转入保留原确认的业务脚本。
}

main "$@"
