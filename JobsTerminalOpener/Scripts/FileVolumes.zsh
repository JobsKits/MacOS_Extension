#!/bin/zsh
# 脚本自述：
# - 脚本名称：FileVolumes.zsh（Jobs 文件拆分与分卷合并）。
# - 核心用途：单个文件拆分，或只合并参数明确选中的完整分卷组。
# - 影响范围：仅新增经大小及 SHA-256 校验的结果；原文件与分卷始终保留，已有目标不覆盖。
# - 运行提示：先阅读内置自述并回车；Ctrl+C 取消，失败候选保留；不安装软件或修改环境。

FV_LOG=''
FV_STAGE=''
FV_NAME=''
FV_INDEX=0
FV_TOTAL=0
FV_LIMIT=0
FV_PARTS=()
FV_STATES=()
FV_BYTES=0
FV_RESULT=0

# 展示与日志分离，日志只保存纯文本。
fv_message() {
  local text="$1" style="${2:-0;34}"
  if [[ -t 1 && -n "${TERM:-}" && "$TERM" != dumb && -z "${NO_COLOR+x}" ]]; then
    printf '\033[%sm%s\033[0m\n' "$style" "$text"
  else
    print -r -- "$text"
  fi
  [[ -z "$FV_LOG" ]] || print -r -- "$text" >> "$FV_LOG"
  return 0
}
# 确认前不写文件，所有业务在当前交互终端进行。
fv_intro() {
  fv_message '======== Jobs 文件拆分 / 分卷合并 ========' '1;31'
  fv_message '1、拆分只接收一个普通文件；合并只接收同目录、同名、完整且不重复的一组所选分卷。'
  fv_message '2、上限支持 50 / 100 / 1900 MiB 或自定义；兼容 文件名@序号of总数，按数字顺序合并。'
  fv_message '3、大小与 SHA-256 校验通过才发布；已有目标不覆盖，原文件和分卷始终保留。'
  fv_message '4、失败或 Ctrl+C 保留候选目录；日志在系统临时目录 JobsFileVolumes.log.*。'
  [[ -t 0 ]] || { fv_message '✖ 请在可交互终端运行。' '1;31'; return 1; }
  local answer=''
  IFS= read -r 'answer?➤ 按回车继续；Ctrl+C 取消：' || return 1
}
# 拒绝链接、特殊文件及会干扰终端日志的控制字符。
fv_regular_file() {
  [[ "$1" == /* && -f "$1" && ! -L "$1" && -r "$1" && "$1" != *[[:cntrl:]]* ]]
}
# 解析最后一个 @ 后缀，原文件名中的 @ 保持不变。
fv_parse_name() {
  local filename="$1"
  [[ "$filename" =~ '^(.+)@([0-9]{1,9})of([0-9]{1,9})$' ]] || return 1
  FV_NAME="$match[1]"
  FV_INDEX=$((10#${match[2]}))
  FV_TOTAL=$((10#${match[3]}))
  [[ "$FV_NAME" != . && "$FV_NAME" != .. ]] && (( FV_TOTAL >= 2 && FV_INDEX >= 1 && FV_INDEX <= FV_TOTAL ))
}
# 快照包含设备、inode、长度和修改状态；业务结束时再次比较。
fv_state() {
  /usr/bin/stat -f '%d:%i:%z:%m:%c' "$1"
}
# 用标准输入避免摘要工具把文件名当成选项或格式控制。
fv_hash() {
  /usr/bin/shasum -a 256 | /usr/bin/awk '{print $1}'
}
# 串流读入参数指定的文件，不扫描相邻目录。
fv_stream() {
  local file=''
  for file in "$@"; do
    /bin/cat -- "$file" || return 1
  done
}
# 验证选择并生成数值顺序；同一卷的补零别名也视为重复。
fv_validate_merge() {
  local file='' name='' directory='' total=0 size=0 index=0
  local -A indexed=()
  FV_PARTS=()
  FV_STATES=()
  FV_BYTES=0
  (( $# >= 2 )) || return 1
  for file in "$@"; do
    fv_regular_file "$file" && fv_parse_name "${file:t}" || return 1
    [[ -z "$name" || "$name" == "$FV_NAME" ]] || return 1
    [[ -z "$directory" || "$directory" == "${file:A:h}" ]] || return 1
    (( total == 0 || total == FV_TOTAL )) || return 1
    [[ -z "${indexed[$FV_INDEX]-}" ]] || return 1
    name="$FV_NAME"; directory="${file:A:h}"; total=$FV_TOTAL
    indexed[$FV_INDEX]="$file"
    size="$(/usr/bin/stat -f %z "$file")" || return 1
    (( size > 0 )) || return 1
    FV_BYTES=$((FV_BYTES + size))
  done
  (( $# == total )) || return 1
  for (( index=1; index<=total; index++ )); do
    [[ -n "${indexed[$index]-}" ]] || return 1
    FV_PARTS+=("${indexed[$index]}")
    FV_STATES+=("$(fv_state "${indexed[$index]}")") || return 1
  done
  FV_NAME="$name"
}
# 不覆盖重名目标；Darwin RENAME_EXCL 在同卷内原子发布文件或目录。
fv_publish() {
  /usr/bin/osascript -l JavaScript - "$1" "$2" <<'JXA'
ObjC.bindFunction('renamex_np', ['int', ['char *', 'char *', 'unsigned int']]);
ObjC.bindFunction('__error', ['int *', []]);
ObjC.bindFunction('strerror', ['char *', ['int']]);
function run(argv) {
    if (argv.length !== 2) throw new Error('需要来源和目标');
    if ($.renamex_np(argv[0], argv[1], 4) !== 0) {
        throw new Error('无覆盖发布失败：' + $.strerror($.__error()[0]));
    }
}
JXA
}
# 只在成功后清除本次临时空目录；失败保留用于核查。
fv_merge() {
  fv_validate_merge "$@" || { fv_message '✖ 请选择同目录同名、非空且完整的一组分卷；缺卷、重复或混组均拒绝。' '1;31'; return 1; }
  local output="${FV_PARTS[1]:A:h}/$FV_NAME" candidate='' expected='' actual='' index=0
  [[ ! -e "$output" && ! -L "$output" ]] || { fv_message "✖ 目标已存在，拒绝覆盖：$output" '1;31'; return 1; }
  FV_STAGE="$(/usr/bin/mktemp -d "${output:h}/.jobs-merge.XXXXXXXX")" || return 1
  candidate="$FV_STAGE/result"
  fv_message "来源：明确选中的 ${#FV_PARTS} 个分卷；目标：$output"
  fv_message "候选目录：$FV_STAGE"
  fv_stream "${FV_PARTS[@]}" | /usr/bin/tee "$candidate" | fv_hash > "$FV_STAGE/hash" || return 1
  expected="$(<"$FV_STAGE/hash")"
  actual="$(fv_hash < "$candidate")" || return 1
  [[ "$actual" == "$expected" && "$(/usr/bin/stat -f %z "$candidate")" == "$FV_BYTES" ]] || return 1
  for (( index=1; index<=${#FV_PARTS}; index++ )); do
    fv_regular_file "${FV_PARTS[index]}" && [[ "$(fv_state "${FV_PARTS[index]}")" == "${FV_STATES[index]}" ]] || return 1
  done
  [[ "$(fv_stream "${FV_PARTS[@]}" | fv_hash)" == "$expected" ]] || return 1
  fv_publish "$candidate" "$output" || return 1
  /bin/rm -- "$FV_STAGE/hash" && /bin/rmdir -- "$FV_STAGE" || return 1
  FV_STAGE=''
  fv_message "✔ 已合并并校验：$output；SHA-256：$expected；全部原分卷保留。" '1;32'
}
# GUI 已限定单个文件；上限仍在终端选择，空选和取消不启动拆分。
fv_choose_limit() {
  local selection='' answer='' picker_status=0
  command -v fzf >/dev/null 2>&1 && fzf --version >/dev/null 2>&1 || { fv_message '✖ 缺少可用 fzf；请手动安装或修复（brew install fzf）。' '1;31'; return 1; }
  while true; do
    selection="$(printf '%s\n' '50 MiB' '100 MiB' '1900 MiB' '自定义 MiB' | FZF_DEFAULT_OPTS= FZF_DEFAULT_OPTS_FILE= fzf --no-multi --height=45% --border --header='回车选择；Esc 取消' --prompt='分卷上限 > ')"
    picker_status=$?
    (( picker_status == 0 )) || { (( picker_status == 1 || picker_status == 130 )) && return 10; return "$picker_status"; }
    case "$selection" in
      '50 MiB') FV_LIMIT=$((50*1024*1024)); return 0 ;;
      '100 MiB') FV_LIMIT=$((100*1024*1024)); return 0 ;;
      '1900 MiB') FV_LIMIT=$((1900*1024*1024)); return 0 ;;
      '自定义 MiB')
        while true; do
          IFS= read -r 'answer?输入正整数 MiB（回车返回上层）：' || return 10
          [[ -n "$answer" ]] || break
          if [[ "$answer" == <-> ]] && (( ${#answer} <= 9 && 10#$answer > 0 )); then
            FV_LIMIT=$((10#$answer*1024*1024)); return 0
          fi
          fv_message '⚠ 请输入大于零的整数。' '1;33'
        done ;;
      *) return 1 ;;
    esac
  done
}
# 均衡分卷保持原脚本算法；完整候选验证后独占发布整个 .chunks 目录。
fv_split() {
  local file="$1" bytes=0 count=0 chunk=0 index=1 width=0 source_state='' source_hash='' part_hash='' part='' destination="${1}.chunks" total_bytes=0
  local -a parts=()
  fv_regular_file "$file" || { fv_message '✖ 拆分只接受一个普通文件。' '1;31'; return 1; }
  [[ ! -e "$destination" && ! -L "$destination" ]] || { fv_message "✖ 目标已存在，拒绝覆盖：$destination" '1;31'; return 1; }
  bytes="$(/usr/bin/stat -f %z "$file")" || return 1
  (( bytes > FV_LIMIT && FV_LIMIT > 0 )) || { fv_message 'ℹ 文件未超过分卷上限，已保留原文件，没有生成分卷。'; return 0; }
  count=$((1+(bytes-1)/FV_LIMIT)); chunk=$((1+(bytes-1)/count)); count=$((1+(bytes-1)/chunk))
  (( count <= 1000000 )) || { fv_message '✖ 预计分卷超过一百万，请增大上限。' '1;31'; return 1; }
  FV_STAGE="$(/usr/bin/mktemp -d "${file:h}/.jobs-split.XXXXXXXX")" || return 1
  fv_message "来源：$file；目标：$destination；计划 $count 卷，上限 $FV_LIMIT 字节。"
  fv_message "候选目录：$FV_STAGE"
  source_state="$(fv_state "$file")" || return 1
  source_hash="$(fv_hash < "$file")" || return 1
  /usr/bin/split -b "$chunk" -a 6 "$file" "$FV_STAGE/part_" || return 1
  parts=("$FV_STAGE"/part_*(N.))
  (( ${#parts} == count )) || return 1
  for part in "${parts[@]}"; do
    local size="$(/usr/bin/stat -f %z "$part")"
    (( size > 0 && size <= FV_LIMIT )) || return 1
    total_bytes=$((total_bytes+size))
  done
  part_hash="$(fv_stream "${parts[@]}" | fv_hash)" || return 1
  (( total_bytes == bytes )) && [[ "$part_hash" == "$source_hash" && "$(fv_hash < "$file")" == "$source_hash" ]] || return 1
  fv_regular_file "$file" && [[ "$(fv_state "$file")" == "$source_state" ]] || return 1
  width=${#count}
  for part in "${parts[@]}"; do
    local suffix=''
    printf -v suffix "%0${width}dof%0${width}d" "$index" "$count"
    /bin/mv -- "$part" "$FV_STAGE/${file:t}@${suffix}" || return 1
    index=$((index+1))
  done
  fv_publish "$FV_STAGE" "$destination" || return 1
  FV_STAGE=''
  fv_message "✔ 已拆分并通过大小及 SHA-256 校验：$destination；SHA-256：$source_hash；原文件保留。" '1;32'
}
# 首先展示内置自述；未确认或没有终端时停止，初始化尚未写文件。
fv_confirm_intro() {
  fv_intro || exit $?
}
# 不修改 Shell 配置；中断和失败均保留未发布候选。
fv_initialize_runtime() {
  setopt NO_NOMATCH PIPE_FAIL
  umask 077
  FV_LOG="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/JobsFileVolumes.log.XXXXXXXX")" || exit 1
  trap 'fv_message "⚠ 已中断；源文件保留，未发布候选：${FV_STAGE:-无}" "1;33"; exit 130' INT
  trap 'fv_message "⚠ 已终止；源文件保留，未发布候选：${FV_STAGE:-无}" "1;33"; exit 143' TERM HUP
}
# 参数和业务动作集中派发，最终状态交给结果函数统一处理。
fv_dispatch_action() {
  local mode="${1:-}" result=0
  if ! shift; then
    FV_RESULT=1
    return 0
  fi
  case "$mode" in
    merge) fv_merge "$@" || result=$? ;;
    split)
      if (( $# == 3 )) && [[ "$2" == --limit-bytes && "$3" == <-> ]] && (( ${#3} <= 15 && 10#$3 > 0 )); then
        FV_LIMIT=$((10#$3))
      elif (( $# == 1 )); then
        fv_choose_limit || result=$?
      else
        result=2
      fi
      if (( result == 0 )); then
        fv_split "$1" || result=$?
      fi ;;
    *) fv_message '用法：FileVolumes.zsh merge <全部分卷路径...> 或 split <文件路径> [--limit-bytes 正整数字节]'; result=2 ;;
  esac
  FV_RESULT=$result
}
# 取消保持成功退出；真实失败保留非零状态及候选位置。
fv_finish() {
  if (( FV_RESULT == 10 )); then
    fv_message 'ℹ 已取消，没有生成结果。'
    return 0
  fi
  (( FV_RESULT == 0 )) || fv_message "✖ 操作失败；原件保留，未发布候选：${FV_STAGE:-无}；日志：$FV_LOG" '1;31'
  return "$FV_RESULT"
}
# 主入口只编排确认、初始化、业务和结果，不散落真实业务。
fv_main() {
  fv_confirm_intro
  fv_initialize_runtime
  fv_dispatch_action "$@"
  fv_finish
}

fv_main "$@"
