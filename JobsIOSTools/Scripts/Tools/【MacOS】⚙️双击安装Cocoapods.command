#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS】⚙️双击安装Cocoapods.command
# - 核心用途：执行“⚙️双击安装Cocoapods”对应的移动端项目自动化任务。
# - 影响范围：可能修改项目依赖、生成文件、构建产物或开发工具配置。
# - 运行提示：运行后会先打印内置自述；终端模式按回车确认后继续，按 Ctrl+C 可取消。
# =====================================================================
# Jobs 标准化脚本外壳
# 说明：保留原脚本业务逻辑，补齐 README 防误触、彩色日志、zsh 入口、Homebrew 健康自检标准。
# =====================================================================

# 仅渲染自述：标题红色加粗，编号正文蓝色常规字重；非彩色终端输出纯文本。
# >>> Jobs Homebrew install choice >>>
# 输出安装诊断，避免混入返回的命令路径。
jobs_brew_note() {
  print -u2 -r -- "ℹ $*"
}
# 验证候选能够执行；共享安装只读不代表未安装。
jobs_brew_candidate_ok() {
  local candidate="$1" prefix
  [[ -n "$candidate" && -x "$candidate" ]] || return 1
  HOMEBREW_NO_AUTO_UPDATE=1 "$candidate" --version >/dev/null 2>&1 || return 1
  prefix="$("$candidate" --prefix 2>/dev/null)" || return 1
  [[ "$prefix" == /* && -d "$prefix" ]]
}
# 发现既有健康安装，不以目录可写性决定是否重新安装。
jobs_brew_find() {
  local candidate
  local -a candidates
  candidates=("${JOBS_HOMEBREW_BIN:-}" "$(command -v brew 2>/dev/null)" /opt/homebrew/bin/brew /usr/local/bin/brew
    "${JOBS_HOMEBREW_INSTALL_PREFIX:-$HOME/.local/homebrew}/bin/brew" "$HOME/.homebrew/bin/brew")
  for candidate in "${candidates[@]}"; do
    if jobs_brew_candidate_ok "$candidate"; then
      print -r -- "$candidate"
      return 0
    fi
  done
  return 1
}
# 计算官方系统目录；实际支持范围和授权交由官方安装器处理。
jobs_brew_system_prefix() {
  case "$(/usr/bin/uname -m)" in
    arm64) print -r -- /opt/homebrew ;;
    *) print -r -- /usr/local ;;
  esac
}
# 缺失时强提示选择安装路径；YES 只表示选择系统目录，不验证密码或权限。
jobs_brew_choose_installation() {
  local answer="" system_prefix="$(jobs_brew_system_prefix)"
  if [[ ! -t 0 || ! -t 2 || "${IS_SOURCETREE_RUNTIME:-0}" == 1 ]]; then
    jobs_brew_note "缺少 Homebrew，需要人工选择安装路径；请在可交互终端重新运行，未执行安装。"
    return 1
  fi
  print -u2 -r -- "⚠ Homebrew 尚未就绪，必须先选择安装路径："
  print -u2 -r -- "1、输入精确大写 YES：选择系统标准目录 $system_prefix（Apple Silicon：/opt/homebrew；Intel：/usr/local）。"
  print -u2 -r -- "   这表示你准备向系统目录安装；官方安装器可能随后要求管理员密码，并自行验证权限。"
  print -u2 -r -- "2、其它输入或直接回车：选择用户目录 ${JOBS_HOMEBREW_INSTALL_PREFIX:-$HOME/.local/homebrew}，不使用 sudo；有管理员权限也可选此路径。"
  print -u2 -r -- "本步骤只选择路径，不收集或验证密码；选定路径失败就停止，不自动切换。按 Ctrl+C 取消整个任务。"
  print -u2 -n -r -- "➤ 安装路径选择："
  if ! IFS= read -r answer; then
    jobs_brew_note "输入已取消或结束，停止安装。"
    return 1
  fi
  if [[ "$answer" == YES ]]; then
    typeset -g JOBS_HOMEBREW_INSTALL_MODE=system
  else
    typeset -g JOBS_HOMEBREW_INSTALL_MODE=user
  fi
}
# 将官方系统安装器下载到临时文件后执行，失败不自动改装到用户目录。
jobs_brew_install_system() {
  local installer system_prefix="$(jobs_brew_system_prefix)" installer_result=0
  command -v curl >/dev/null 2>&1 || { jobs_brew_note "缺少 curl，无法获取官方安装器。"; return 1; }
  installer="$(mktemp "${TMPDIR:-/tmp}/jobs-homebrew-install.XXXXXX")" || return 1
  if curl -fsSL --connect-timeout 10 --max-time 120 https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh -o "$installer"; then
    /bin/bash "$installer" || installer_result=$?
  else
    installer_result=1
  fi
  rm -- "$installer"
  if (( installer_result != 0 )); then
    jobs_brew_note "系统目录安装失败（退出码 $installer_result）；停止，不自动切换安装路径。"
    return 1
  fi
  typeset -g JOBS_HOMEBREW_BIN="$system_prefix/bin/brew"
  jobs_brew_candidate_ok "$JOBS_HOMEBREW_BIN" || { jobs_brew_note "官方安装器结束后未找到健康 Homebrew：$JOBS_HOMEBREW_BIN"; return 1; }
}
# 克隆官方稳定版本到用户目录；不覆盖非空目录，不调用 sudo。
jobs_brew_install_user() {
  local prefix="${JOBS_HOMEBREW_INSTALL_PREFIX:-$HOME/.local/homebrew}" stage release_tag git_bin
  [[ "$prefix" == /* && "$prefix" != / && "$prefix" != *[[:space:]:]* ]] || {
    jobs_brew_note "Homebrew 用户前缀须为不含空白或冒号的绝对目录：$prefix"
    return 1
  }
  if [[ -L "$prefix" || ( -e "$prefix" && ! -d "$prefix" ) || ( -d "$prefix" && -n "$(ls -A "$prefix" 2>/dev/null)" ) ]]; then
    jobs_brew_note "用户安装目标非空或不是普通目录，不覆盖：$prefix"
    return 1
  fi
  git_bin="$(command -v git 2>/dev/null)"
  [[ -n "$git_bin" ]] && "$git_bin" --version >/dev/null 2>&1 || { jobs_brew_note "用户目录安装需要可用 Git；请先准备 Git / Command Line Tools。"; return 1; }
  command -v curl >/dev/null 2>&1 || { jobs_brew_note "缺少 curl，无法获取官方稳定版本。"; return 1; }
  export HOMEBREW_NO_SUDO=1
  mkdir -p "${prefix:h}" || return 1
  stage="$(mktemp -d "${prefix:h}/.jobs-homebrew.XXXXXX")" || return 1
  if ! curl -fsSL --connect-timeout 10 --max-time 60 https://api.github.com/repos/Homebrew/brew/releases/latest -o "$stage/release.json"; then
    rm -r -- "$stage"
    jobs_brew_note "获取官方稳定版本失败，停止安装。"
    return 1
  fi
  release_tag="$(sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([0-9][0-9.]*\)".*/\1/p' "$stage/release.json" | head -n 1)"
  if [[ ! "$release_tag" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] ||
     ! GIT_TERMINAL_PROMPT=0 "$git_bin" -c http.lowSpeedLimit=1 -c http.lowSpeedTime=60 clone --depth 1 --branch "$release_tag" --single-branch https://github.com/Homebrew/brew.git "$stage/brew" ||
     ! "$git_bin" -C "$stage/brew" checkout -b stable ||
     ! "$git_bin" -C "$stage/brew" config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*' ||
     ! mkdir -p "$stage/brew/Cellar" "$stage/brew/Caskroom" "$stage/brew/etc" "$stage/brew/var"; then
    rm -r -- "$stage"
    jobs_brew_note "Homebrew 用户目录初始化失败，停止安装。"
    return 1
  fi
  # 空目录也只在下载成功后移除，避免提前改动用户的目标目录。
  if [[ -d "$prefix" ]] && ! rmdir -- "$prefix"; then
    rm -r -- "$stage"
    return 1
  fi
  if ! mv "$stage/brew" "$prefix"; then
    rm -r -- "$stage"
    return 1
  fi
  rm -r -- "$stage"
  typeset -g JOBS_HOMEBREW_BIN="$prefix/bin/brew"
  jobs_brew_candidate_ok "$JOBS_HOMEBREW_BIN" || { jobs_brew_note "用户目录安装后复检失败：$prefix"; return 1; }
}
# 只更新本模块的 shellenv 配置块，并保留配置文件的符号链接和权限。
jobs_brew_save_shellenv() {
  local profile_file="$HOME/.zprofile" profile_stage shellenv_line current_shell="${SHELL:-/bin/zsh}"
  [[ "${current_shell##*/}" != bash ]] || profile_file="$HOME/.bash_profile"
  shellenv_line='eval "$('"${(q)JOBS_HOMEBREW_BIN}"' shellenv)"'
  profile_stage="$(mktemp "${TMPDIR:-/tmp}/jobs-homebrew-profile.XXXXXX")" || return 1
  if [[ -e "$profile_file" || -L "$profile_file" ]]; then
    awk '
      $0 == "# >>> Jobs Homebrew shellenv >>>" { inside = 1; block = $0 ORS; next }
      inside {
        block = block $0 ORS
        if ($0 == "# <<< Jobs Homebrew shellenv <<<") { inside = 0; block = "" }
        next
      }
      { print }
      END { if (inside) printf "%s", block }
    ' "$profile_file" > "$profile_stage" || { rm -- "$profile_stage"; return 1; }
  fi
  {
    print -r -- '# >>> Jobs Homebrew shellenv >>>'
    print -rl -- "$shellenv_line" '# <<< Jobs Homebrew shellenv <<<'
  } >> "$profile_stage"
  if ! cmp -s "$profile_stage" "$profile_file"; then
    cat "$profile_stage" > "$profile_file" || { rm -- "$profile_stage"; jobs_brew_note "无法写入用户配置：$profile_file"; return 1; }
  fi
  rm -- "$profile_stage"
}
# 激活当前进程并验证 Ruby 命令层；只有新安装才持久化 shellenv。
jobs_brew_activate() {
  local brew_env
  brew_env="$("$JOBS_HOMEBREW_BIN" shellenv)" || return 1
  eval "$brew_env" || return 1
  typeset -g JOBS_HOMEBREW_PREFIX="$("$JOBS_HOMEBREW_BIN" --prefix)"
  export PATH="$JOBS_HOMEBREW_PREFIX/bin:$JOBS_HOMEBREW_PREFIX/sbin:$PATH"
  rehash
  HOMEBREW_NO_AUTO_UPDATE=1 "$JOBS_HOMEBREW_BIN" config >/dev/null || { jobs_brew_note "Homebrew 命令层复检失败，停止后续业务。"; return 1; }
  if [[ "${1:-}" == installed ]]; then
    if [[ "${JOBS_HOMEBREW_INSTALL_MODE:-}" == user && -z "${HOMEBREW_CASK_OPTS:-}" ]]; then
      export HOMEBREW_CASK_OPTS="--appdir=$HOME/Applications"
    fi
    jobs_brew_save_shellenv || return 1
  fi
}
# 在原版安装位置复用或安装 Homebrew，安装失败必须终止外层业务。
jobs_brew_install_or_exit() {
  local installed=""
  if [[ "${DRY_RUN:-0}" == 1 ]]; then
    jobs_brew_note "演练：Homebrew 系统路径 $(jobs_brew_system_prefix)；用户路径 ${JOBS_HOMEBREW_INSTALL_PREFIX:-$HOME/.local/homebrew}；未询问或执行安装。"
    return 0
  fi
  if ! JOBS_HOMEBREW_BIN="$(jobs_brew_find)"; then
    jobs_brew_choose_installation || exit 1
    case "$JOBS_HOMEBREW_INSTALL_MODE" in
      system) jobs_brew_install_system || exit 1 ;;
      user) jobs_brew_install_user || exit 1 ;;
      *) jobs_brew_note "安装路径选择无效，停止。"; exit 1 ;;
    esac
    installed=installed
  fi
  jobs_brew_activate "$installed" || exit 1
}
# <<< Jobs Homebrew install choice <<<
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
SCRIPT_BASENAME="$(basename "$0" | sed 's/\.[^.]*$//')"
LOG_FILE="/tmp/${SCRIPT_BASENAME}.log"
# 统一输出终端信息并同步记录日志。
log()            { echo -e "$1" | tee -a "$LOG_FILE"; }
# 输出 color echo 对应级别的日志信息。
color_echo()     { log "\033[1;32m$1\033[0m"; }
# 输出 info echo 对应级别的日志信息。
info_echo()      { log "\033[1;34mℹ $1\033[0m"; }
# 输出 success echo 对应级别的日志信息。
success_echo()   { log "\033[1;32m✔ $1\033[0m"; }
# 输出 warn echo 对应级别的日志信息。
warn_echo()      { log "\033[1;33m⚠ $1\033[0m"; }
# 输出 warm echo 对应级别的日志信息。
warm_echo()      { log "\033[1;33m$1\033[0m"; }
# 输出 note echo 对应级别的日志信息。
note_echo()      { log "\033[1;35m➤ $1\033[0m"; }
# 输出 error echo 对应级别的日志信息。
error_echo()     { log "\033[1;31m✖ $1\033[0m"; }
# 输出 err echo 对应级别的日志信息。
err_echo()       { log "\033[1;31m$1\033[0m"; }
# 输出 debug echo 对应级别的日志信息。
debug_echo()     { log "\033[1;35m🐞 $1\033[0m"; }
# 输出 highlight echo 对应级别的日志信息。
highlight_echo() { log "\033[1;36m🔹 $1\033[0m"; }
# 输出 gray echo 对应级别的日志信息。
gray_echo()      { log "\033[0;90m$1\033[0m"; }
# 输出 bold echo 对应级别的日志信息。
bold_echo()      { log "\033[1m$1\033[0m"; }
# 输出 underline echo 对应级别的日志信息。
underline_echo() { log "\033[4m$1\033[0m"; }
# ============================= 标准工具函数 =============================
get_cpu_arch() {
  [[ "$(uname -m)" == "arm64" ]] && echo "arm64" || echo "x86_64"
}
# 封装 abs path 对应的独立处理逻辑。
abs_path() {
  local p="$1"
  [[ -z "$p" ]] && return 1
  p="${p//\"/}"
  [[ "$p" != "/" ]] && p="${p%/}"
  if [[ -d "$p" ]]; then
    (cd "$p" 2>/dev/null && pwd -P)
  elif [[ -f "$p" ]]; then
    (cd "${p:h}" 2>/dev/null && printf "%s/%s\n" "$(pwd -P)" "${p:t}")
  else
    return 1
  fi
}
# 收集并校验 ask run 对应的用户确认。
ask_run() {
  echo ""
  note_echo "👉 $1"
  gray_echo "【回车=跳过，输入任意字符后回车=执行】"
  local input=""
  IFS= read -r "input?➤ "
  [[ -n "$input" ]]
}
# 收集并校验 confirm yes 对应的用户确认。
confirm_yes() {
  echo ""
  warn_echo "⚠ $1"
  gray_echo "危险操作必须输入 YES 后回车；其它输入一律取消。"
  local input=""
  IFS= read -r "input?➤ "
  [[ "$input" == "YES" ]]
}
# 封装 inject shellenv block 对应的独立处理逻辑。
inject_shellenv_block() {
  local profile_file="$1"
  local shellenv_cmd="$2"
  local header="# >>> Homebrew 环境变量 >>>"
  [[ -z "$profile_file" || -z "$shellenv_cmd" ]] && { error_echo "缺少参数：inject_shellenv_block <profile_file> <shellenv_cmd>"; return 1; }
  mkdir -p "$(dirname "$profile_file")"
  touch "$profile_file"
  if grep -Fq "$shellenv_cmd" "$profile_file" 2>/dev/null; then
    info_echo "已存在 Homebrew shellenv：$profile_file"
  elif grep -Fq "$header" "$profile_file" 2>/dev/null; then
    info_echo "已存在 Homebrew 环境变量块：$profile_file"
  else
    {
      echo ""
      echo "$header"
      echo "$shellenv_cmd"
    } >> "$profile_file"
    success_echo "已写入 Homebrew shellenv：$profile_file"
  fi
  eval "$shellenv_cmd" || true
}
# 封装 activate homebrew shellenv 对应的独立处理逻辑。
activate_homebrew_shellenv() {
  local arch="$(get_cpu_arch)"
  local brew_bin=""
  brew_bin="$(jobs_brew_find)" || { error_echo "没有健康 Homebrew，停止激活。"; return 1; }
  JOBS_HOMEBREW_BIN="$brew_bin"
  jobs_brew_activate || { error_echo "Homebrew 激活或命令层复检失败。"; return 1; }

  local shell_name="${SHELL##*/}"
  local profile_file=""
  case "$shell_name" in
    zsh)  profile_file="$HOME/.zprofile" ;;
    bash) profile_file="$HOME/.bash_profile" ;;
    *)    profile_file="$HOME/.profile" ;;
  esac
  inject_shellenv_block "$profile_file" "eval \"\$(${brew_bin} shellenv)\"" || return 1
  eval "$(${brew_bin} shellenv)"
}
# 执行 run brew health update 对应的独立业务步骤。
run_brew_health_update() {
  info_echo "正在执行 Homebrew 健康更新..."
  brew update  || { error_echo "brew update 失败"; return 1; }
  brew upgrade || { error_echo "brew upgrade 失败"; return 1; }
  brew cleanup || { error_echo "brew cleanup 失败"; return 1; }
  brew doctor  || warn_echo "brew doctor 有警告，请按输出处理"
  brew -v      || warn_echo "打印 brew 版本失败，可忽略"
  success_echo "Homebrew 健康更新完成"
}
# 准备并配置 install homebrew 对应的运行条件。
install_homebrew() {
  local arch="$(get_cpu_arch)"
  local brew_bin=""

  if ! brew_bin="$(jobs_brew_find)"; then
    warn_echo "未检测到 Homebrew，准备按架构安装：$arch"
    if [[ "$arch" == "arm64" ]]; then
      jobs_brew_install_or_exit || { error_echo "Homebrew 安装失败（arm64）"; return 1; }
      brew_bin="${JOBS_HOMEBREW_BIN:-$(jobs_brew_find 2>/dev/null || true)}"
    else
      jobs_brew_install_or_exit || { error_echo "Homebrew 安装失败（x86_64）"; return 1; }
      brew_bin="${JOBS_HOMEBREW_BIN:-$(jobs_brew_find 2>/dev/null || true)}"
    fi
    success_echo "Homebrew 安装完成"
    activate_homebrew_shellenv || exit 1
    return 0
  fi

  activate_homebrew_shellenv || exit 1
  info_echo "Homebrew 已安装。"
  if ask_run "是否执行 Homebrew 更新 / 升级 / 清理 / doctor？"; then
    run_brew_health_update || exit 1
  else
    note_echo "已跳过 Homebrew 更新"
  fi
}
# 封装 brew install or upgrade 对应的独立处理逻辑。
brew_install_or_upgrade() {
  local formula="$1"
  [[ -z "$formula" ]] && return 1
  install_homebrew || return 1
  if ! brew list --formula "$formula" >/dev/null 2>&1 && ! command -v "$formula" >/dev/null 2>&1; then
    note_echo "未检测到 $formula，正在安装..."
    brew install "$formula" || { error_echo "$formula 安装失败"; return 1; }
    success_echo "$formula 安装完成"
  else
    info_echo "$formula 已安装。"
    if ask_run "是否升级 $formula？"; then
      brew upgrade "$formula" || warn_echo "$formula 可能已是最新或升级失败，请检查输出"
      brew cleanup || true
    else
      note_echo "已跳过 $formula 升级"
    fi
  fi
}
# 输出 show readme and wait 对应的说明与结果。
show_script_intro_and_wait() {
  clear
  print -r -- '============================== 脚本内置自述 ==============================' | jobs_intro_style title
  print -r -- '脚本名称：【MacOS】⚙️双击安装Cocoapods.command' | jobs_intro_style title
  print -r -- '核心用途：执行“⚙️双击安装Cocoapods”对应的移动端项目自动化任务。' | jobs_intro_style body
  print -r -- '影响范围：可能修改项目依赖、生成文件、构建产物或开发工具配置。' | jobs_intro_style body
  print -r -- '取消方式：确认前按 Ctrl+C 终止，不会继续执行后续业务。' | jobs_intro_style body
  print -r -- '============================================================================' | jobs_intro_style title
  echo "" | jobs_intro_style body
  read -r "?👉 已了解脚本用途与影响，按回车继续；按 Ctrl+C 取消：" _
}
# 执行 run original logic 对应的独立业务步骤。
run_original_logic() {
  # ============================= 原脚本业务逻辑区 =============================
  # ================================== Jobs CocoaPods Installer ==================================
  # - macOS 双击运行（.command）友好
  # - 自动安装/注入 Homebrew 环境
  # - fzf：无则安装，有则可选升级（回车跳过，输入任意字符升级）
  # - Ruby：默认使用 Homebrew Ruby，避免系统 Ruby 权限/版本问题
  # - CocoaPods：默认用 Homebrew 安装（最稳），失败再 fallback 到 gem（配合 brew ruby）
  # - 全流程日志：/tmp/${SCRIPT_BASENAME}.log
  # ==============================================================================================

  set -e

  # ================================== 全局变量 ==================================
  START_TIME=$(date +%s)
  SCRIPT_BASENAME=$(basename "$0" | sed 's/\.[^.]*$//')
  LOG_FILE="/tmp/${SCRIPT_BASENAME}.log"
  # ================================== 日志与彩色输出 ==================================
  log() { echo -e "$1" | tee -a "$LOG_FILE"; }
  # 你原脚本里用到了 _color_echo，这里补齐，并且写入 LOG_FILE
  _color_echo() {
    local color="$1"; shift
    local text="$*"

    case "$color" in
      red)        log "\033[31m${text}\033[0m" ;;
      green)      log "\033[32m${text}\033[0m" ;;
      yellow)     log "\033[33m${text}\033[0m" ;;
      blue)       log "\033[34m${text}\033[0m" ;;
      purple)     log "\033[35m${text}\033[0m" ;;
      cyan)       log "\033[36m${text}\033[0m" ;;
      white)      log "\033[37m${text}\033[0m" ;;
      gray)       log "\033[90m${text}\033[0m" ;;

      bold)       log "\033[1m${text}\033[0m" ;;
      underline)  log "\033[4m${text}\033[0m" ;;

      success)    log "\033[1;32m✔ ${text}\033[0m" ;;
      error)      log "\033[1;31m✖ ${text}\033[0m" ;;
      info)       log "\033[1;34mℹ ${text}\033[0m" ;;
      warning)    log "\033[1;33m⚠ ${text}\033[0m" ;;
      note)       log "\033[1;35m➤ ${text}\033[0m" ;;

      *)          log "${text}" ;;
    esac
  }
  # 输出 info echo 对应级别的日志信息。
  info_echo()      { _color_echo info "$1"; }
  # 输出 success echo 对应级别的日志信息。
  success_echo()   { _color_echo success "$1"; }
  # 输出 warn echo 对应级别的日志信息。
  warn_echo()      { _color_echo warning "$1"; }
  # 输出 note echo 对应级别的日志信息。
  note_echo()      { _color_echo note "$1"; }
  # 输出 error echo 对应级别的日志信息。
  error_echo()     { _color_echo error "$1"; }
  # 输出 gray echo 对应级别的日志信息。
  gray_echo()      { _color_echo gray "$1"; }
  # 输出 bold echo 对应级别的日志信息。
  bold_echo()      { _color_echo bold "$1"; }
  # ================================== UI / 工具函数 ==================================
  print_logo() {
    _color_echo cyan "======================="
    _color_echo cyan "     Jobs Installer    "
    _color_echo cyan "======================="
    gray_echo "日志：$LOG_FILE"
  }
  # 输出 print duration 对应的说明与结果。
  print_duration() {
    local end_time=$(date +%s)
    local duration=$((end_time - START_TIME))
    info_echo "⚙️ 脚本总耗时：${duration}s"
  }
  # 封装 pause to exit 对应的独立处理逻辑。
  pause_to_exit() {
    echo ""
    note_echo "✅ 脚本结束。按回车退出..."
    IFS= read -r _
  }
  # 解析并返回 get cpu arch 所需信息。
  get_cpu_arch() {
    [[ "$(uname -m)" == "arm64" ]] && echo "arm64" || echo "x86_64"
  }
  # 收集并校验 confirm upgrade 对应的用户确认。
  confirm_upgrade() {
    # 回车：跳过；输入任意字符：执行升级（按你的要求）
    local what="$1"
    info_echo "🔄 检测到 ${what} 已安装。"
    echo "👉 回车：跳过升级"
    echo "👉 输入任意字符后回车：执行升级"
    local confirm
    IFS= read -r confirm
    [[ -n "$confirm" ]]
  }
  # 检查 ensure command 所需条件，不满足时阻止继续执行。
  ensure_command() {
    local cmd="$1"
    local hint="$2"
    if ! command -v "$cmd" &>/dev/null; then
      error_echo "❌ 缺少命令：$cmd"
      [[ -n "$hint" ]] && note_echo "$hint"
      return 1
    fi
  }
  # ================================== Xcode Command Line Tools ==================================
  ensure_clt() {
    if xcode-select -p &>/dev/null; then
      success_echo "✅ Xcode Command Line Tools 已安装"
      return 0
    fi

    warn_echo "⚠️ 未检测到 Xcode Command Line Tools（Homebrew 需要它）"
    note_echo "将尝试触发安装：会弹出系统安装窗口，按提示完成后重新运行脚本。"
    xcode-select --install || true

    pause_to_exit
    exit 1
  }
  # ================================== Homebrew ==================================
  detect_brew_bin() {
    if command -v brew &>/dev/null; then
      command -v brew
      return 0
    fi

    # Finder 双击运行时经常 PATH 不完整：这里兜底
    if [[ -x /opt/homebrew/bin/brew ]]; then
      echo /opt/homebrew/bin/brew
      return 0
    fi

    if [[ -x /usr/local/bin/brew ]]; then
      echo /usr/local/bin/brew
      return 0
    fi

    return 1
  }
  # 执行 apply brew shellenv 对应的独立业务步骤。
  apply_brew_shellenv() {
    local brew_bin="$1"
    eval "$("$brew_bin" shellenv)"
  }
  # 准备并配置 install homebrew 对应的运行条件。
  install_homebrew() {
    local arch="$(get_cpu_arch)"
    local shell_name="${SHELL##*/}"
    local profile_file=""
    local brew_bin=""

    if ! command -v brew >/dev/null 2>&1 && [[ ! -x "/opt/homebrew/bin/brew" && ! -x "/usr/local/bin/brew" ]]; then
      warn_echo "未检测到 Homebrew，准备安装（架构：$arch）"
      if [[ "$arch" == "arm64" ]]; then
        jobs_brew_install_or_exit || { error_echo "Homebrew 安装失败（arm64）"; return 1; }
        brew_bin="${JOBS_HOMEBREW_BIN:-$(jobs_brew_find 2>/dev/null || true)}"
      else
        jobs_brew_install_or_exit || { error_echo "Homebrew 安装失败（x86_64）"; return 1; }
        brew_bin="${JOBS_HOMEBREW_BIN:-$(jobs_brew_find 2>/dev/null || true)}"
      fi
      success_echo "Homebrew 安装完成"
    else
      command -v brew >/dev/null 2>&1 && brew_bin="$(command -v brew)"
      [[ -z "$brew_bin" && -x "/opt/homebrew/bin/brew" ]] && brew_bin="/opt/homebrew/bin/brew"
      [[ -z "$brew_bin" && -x "/usr/local/bin/brew" ]] && brew_bin="/usr/local/bin/brew"
    fi

    case "$shell_name" in
      zsh) profile_file="$HOME/.zprofile" ;;
      bash) profile_file="$HOME/.bash_profile" ;;
      *) profile_file="$HOME/.profile" ;;
    esac
    inject_shellenv_block "$profile_file" "eval \"\$(${brew_bin} shellenv)\""
    eval "$(${brew_bin} shellenv)" || true

    info_echo "Homebrew 已安装。"
    if ask_run "是否执行 Homebrew 更新 / 升级 / 清理 / doctor？"; then
      brew update  || { error_echo "brew update 失败"; return 1; }
      brew upgrade || { error_echo "brew upgrade 失败"; return 1; }
      brew cleanup || { error_echo "brew cleanup 失败"; return 1; }
      brew doctor  || warn_echo "brew doctor 有警告，请按输出处理"
      brew -v      || warn_echo "打印 brew 版本失败，可忽略"
      success_echo "Homebrew 健康更新完成"
    else
      note_echo "已跳过 Homebrew 更新"
    fi
  }
  # ================================== fzf（自检/安装/升级） ==================================
  install_fzf() {
    ensure_command brew "Homebrew 不可用，无法安装 fzf。"

    if ! command -v fzf &>/dev/null; then
      note_echo "📦 未检测到 fzf，正在通过 Homebrew 安装..."
      brew install fzf || { error_echo "❌ fzf 安装失败"; pause_to_exit; exit 1; }
      success_echo "✅ fzf 安装成功：$(fzf --version 2>/dev/null || echo 'unknown')"
      return 0
    fi

    # 已安装：是否升级（回车跳过，任意字符升级）
    if confirm_upgrade "fzf"; then
      info_echo "⏳ 正在升级 fzf..."
      brew upgrade fzf || { error_echo "❌ fzf 升级失败"; return 1; }
      brew cleanup || { warn_echo "⚠️ brew cleanup 执行时有警告"; }
      success_echo "✅ fzf 已升级到最新版本：$(fzf --version 2>/dev/null || echo 'unknown')"
    else
      note_echo "⏭️ 已选择跳过 fzf 升级"
    fi
  }
  # ================================== Ruby（优先 Homebrew Ruby） ==================================
  ensure_brew_ruby() {
    ensure_command brew "Homebrew 不可用，无法安装 Ruby。"

    if brew list --formula ruby &>/dev/null; then
      success_echo "✅ Homebrew Ruby 已安装"
    else
      note_echo "💎 未检测到 Homebrew Ruby，正在安装..."
      brew install ruby || { error_echo "❌ Ruby 安装失败"; pause_to_exit; exit 1; }
      success_echo "✅ Ruby 安装成功"
    fi

    # 当前会话注入 PATH，确保 ruby/gem 指向 brew ruby
    local ruby_prefix
    ruby_prefix="$(brew --prefix ruby 2>/dev/null || true)"
    if [[ -n "$ruby_prefix" && -d "$ruby_prefix/bin" ]]; then
      export PATH="$ruby_prefix/bin:$PATH"
    fi

    info_echo "Ruby: $(ruby -v 2>/dev/null || echo 'not found')"
    info_echo "Gem : $(gem -v 2>/dev/null || echo 'not found')"
  }
  # ================================== RubyGems 源（可选） ==================================
  is_in_china() {
    ensure_command curl "无法访问网络，跳过根据 IP 判断。" || return 1

    local json
    json=$(curl -s --max-time 3 https://ipinfo.io || true)
    [[ -z "$json" ]] && return 1

    if command -v jq &>/dev/null; then
      local country
      country=$(echo "$json" | jq -r '.country' 2>/dev/null || true)
      [[ "$country" == "CN" ]] && return 0 || return 1
    fi

    # 无 jq：用简单 grep 兜底
    echo "$json" | grep -q '"country"[[:space:]]*:[[:space:]]*"CN"'
  }
  # 封装 set gem source 对应的独立处理逻辑。
  set_gem_source() {
    command -v gem &>/dev/null || { warn_echo "⚠️ gem 不可用，跳过 RubyGems 源设置"; return 0; }

    if is_in_china; then
      gem sources --remove https://rubygems.org/ 2>/dev/null || true
      gem sources --add https://gems.ruby-china.com/ 2>/dev/null || true
      note_echo "🇨🇳 检测到可能在中国网络环境：已切换 RubyGems 源为 ruby-china"
    else
      gem sources --remove https://gems.ruby-china.com/ 2>/dev/null || true
      gem sources --add https://rubygems.org/ 2>/dev/null || true
      note_echo "🌐 使用官方 RubyGems 源"
    fi

    info_echo "📦 当前 RubyGems 源列表："
    gem sources -l | tee -a "$LOG_FILE" || true
  }
  # ================================== CocoaPods 安装 ==================================
  install_cocoapods() {
    ensure_command brew "Homebrew 不可用，无法安装 CocoaPods。"

    if command -v pod &>/dev/null; then
      success_echo "✅ CocoaPods 已安装：$(pod --version 2>/dev/null || echo 'unknown')"
      return 0
    fi

    note_echo "📦 正在通过 Homebrew 安装 CocoaPods（推荐/最稳）..."
    brew install cocoapods || {
      warn_echo "⚠️ brew 安装 CocoaPods 失败，尝试改用 gem 安装（使用 Homebrew Ruby）"

      ensure_brew_ruby
      set_gem_source

      gem install cocoapods -N || { error_echo "❌ gem 安装 CocoaPods 失败"; pause_to_exit; exit 1; }
    }

    if ! command -v pod &>/dev/null; then
      # gem 安装后 PATH 可能没更新，尝试修复
      if command -v gem &>/dev/null; then
        local gem_bin
        gem_bin=$(ruby -e 'puts Gem.user_dir' 2>/dev/null)/bin
        [[ -d "$gem_bin" ]] && export PATH="$gem_bin:$PATH"
      fi
    fi

    command -v pod &>/dev/null || { error_echo "❌ CocoaPods 安装后仍未找到 pod 命令"; pause_to_exit; exit 1; }

    success_echo "✅ CocoaPods 安装完成：$(pod --version 2>/dev/null || echo 'unknown')"

    # CocoaPods 现在默认走 CDN，通常不需要 pod setup；这里做首次初始化兜底
    if [[ ! -d "$HOME/.cocoapods" ]]; then
      note_echo "🔧 首次初始化 CocoaPods（可选）：pod setup"
      pod setup || warn_echo "⚠️ pod setup 执行失败（通常不影响使用）"
    else
      gray_echo "ℹ 已存在 ~/.cocoapods，跳过 pod setup"
    fi
  }
  # ================================== 备份配置文件（可选） ==================================
  backup_configs() {
    local files=("$HOME/.zshrc" "$HOME/.zprofile" "$HOME/.bash_profile" "$HOME/.profile")
    for f in "${files[@]}"; do
      [[ -f "$f" ]] || continue
      cp "$f" "$f.bak" 2>/dev/null || true
    done
    success_echo "📦 配置文件已备份（*.bak，如存在）"
  }
  # ================================== 主流程 ==================================
  main() {
    : > "$LOG_FILE" 2>/dev/null || true

    print_logo
    backup_configs

    install_homebrew

    # 你的旧脚本里依赖过 fzf（菜单），所以这里先保证它可用
    install_fzf

    # 解决“新系统 ruby 环境安装失败/系统 ruby 权限问题”
    ensure_brew_ruby

    install_cocoapods

    print_duration
    success_echo "🎉 所有步骤已完成，日志保存在：$LOG_FILE"
  }

  trap 'error_echo "❌ 脚本中途失败，详见日志：$LOG_FILE"; pause_to_exit' ERR

  main "$@"
  pause_to_exit

  # =========================== 原脚本业务逻辑区结束 ===========================
}
# 编排脚本的高层业务流程。
# 初始化脚本运行环境，并集中承载原有的顶层执行逻辑。
initialize_script_runtime() {
  : > "$LOG_FILE"
}
# 编排脚本的高层业务流程。
main() {
  # 展示脚本内置自述，并按运行入口完成防误触确认。
  show_script_intro_and_wait
  # 初始化 Shell 选项、日志、依赖和入口运行状态。
  initialize_script_runtime
  # 执行 run_original_logic 对应的核心业务步骤。
  run_original_logic "$@"
  # 输出脚本执行结果、摘要和日志位置。
  success_echo "脚本执行结束。日志：$LOG_FILE"
}

main "$@"
