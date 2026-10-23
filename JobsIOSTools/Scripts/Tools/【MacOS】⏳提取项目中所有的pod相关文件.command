#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS】⏳提取项目中所有的pod相关文件.command
# - 核心用途：执行“⏳提取项目中所有的pod相关文件”对应的移动端项目自动化任务。
# - 影响范围：可能修改项目依赖、生成文件、构建产物或开发工具配置。
# - 运行提示：运行后会先打印内置自述；终端模式按回车确认后继续，按 Ctrl+C 可取消。


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
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[34m'
NC='\033[0m'

PROJECT_PATH=''
OUTPUT_DIR=''
PODSPEC_COUNT=0
PODFILE_COUNT=0
TOTAL_COUNT=0
COPIED_SOURCE_LIST=''
# 展示脚本用途和影响范围，并在执行前等待用户确认。
print_intro() {
    printf "${BLUE}============================================================${NC}\n" | jobs_intro_style title
    printf "${BLUE} 提取项目中的 CocoaPods 相关文件${NC}\n" | jobs_intro_style title
    printf "${BLUE}============================================================${NC}\n" | jobs_intro_style title
    printf "\n" | jobs_intro_style body
    printf "功能说明：\n" | jobs_intro_style body
    printf "1. 从你拖入的 Xcode 工程目录中递归查找并复制所有 .podspec 文件。\n" | jobs_intro_style body
    printf "2. 只从你拖入的工程根目录复制 Podfile.deps、Podfile、Podfile.lock。\n" | jobs_intro_style body
    printf "3. Podfile.deps、Podfile、Podfile.lock 不会递归查找子目录，避免把 Pods、Example、Demo 里的 Podfile 全复制出来。\n" | jobs_intro_style body
    printf "4. 复制结果会放到桌面新建的 PodspecFiles_时间戳 文件夹中。\n" | jobs_intro_style body
    printf "5. 如果 Podfile.deps、Podfile、Podfile.lock 不存在，只会用红字提示，不会影响脚本继续执行。\n" | jobs_intro_style body
    printf "6. 如果出现同名文件，会自动追加 _1、_2 等序号，避免覆盖。\n" | jobs_intro_style body
    printf "7. 支持拖入 Finder 替身、软链接，会尽量解析到背后的真实目录。\n" | jobs_intro_style body
    printf "8. 支持 .podspec、Podfile.deps、Podfile、Podfile.lock 本身是 Finder 替身或软链接，会复制其真正指向的文件。\n" | jobs_intro_style body
    printf "9. 支持 Finder 默认生成的 podspec 替身文件名，例如 xxx.podspec 替身、xxx.podspec alias。\n" | jobs_intro_style body
    printf "\n" | jobs_intro_style body
    printf "${YELLOW}按回车开始执行...${NC}" | jobs_intro_style body
    read -r _
    printf "\n" | jobs_intro_style body
}
# 封装 normalize_dragged_path 对应的独立处理逻辑。
normalize_dragged_path() {
    local RAW_PATH="$1"

    # 去掉首尾空白
    RAW_PATH="$(echo "$RAW_PATH" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

    # 去掉首尾引号
    RAW_PATH="${RAW_PATH%\"}"
    RAW_PATH="${RAW_PATH#\"}"
    RAW_PATH="${RAW_PATH%\'}"
    RAW_PATH="${RAW_PATH#\'}"

    # 处理 macOS 终端拖入路径时的反斜杠转义，例如 My\ Project
    RAW_PATH="$(printf '%s\n' "$RAW_PATH" | sed 's/\\\(.\)/\1/g')"

    # 支持手动输入 ~/Desktop/xxx
    if [[ "$RAW_PATH" == "~" || "$RAW_PATH" == ~/* ]]; then
        RAW_PATH="${RAW_PATH/#\~/$HOME}"
    fi

    printf '%s\n' "$RAW_PATH"
}
# 封装 canonicalize_path 对应的独立处理逻辑。
canonicalize_path() {
    local INPUT_PATH="$1"
    local DIR_NAME
    local BASE_NAME

    if [ -d "$INPUT_PATH" ]; then
        (
            cd "$INPUT_PATH" 2>/dev/null && pwd -P
        ) || printf '%s\n' "$INPUT_PATH"
        return
    fi

    if [ -e "$INPUT_PATH" ] || [ -L "$INPUT_PATH" ]; then
        DIR_NAME="$(dirname "$INPUT_PATH")"
        BASE_NAME="$(basename "$INPUT_PATH")"
        (
            cd "$DIR_NAME" 2>/dev/null && printf '%s/%s\n' "$(pwd -P)" "$BASE_NAME"
        ) || printf '%s\n' "$INPUT_PATH"
        return
    fi

    printf '%s\n' "$INPUT_PATH"
}
# 解析并返回后续流程需要的目标信息。
resolve_unix_symlink_path() {
    local INPUT_PATH="$1"
    local LINK_TARGET
    local LINK_DIR

    if [ ! -L "$INPUT_PATH" ]; then
        printf '%s\n' "$INPUT_PATH"
        return
    fi

    LINK_TARGET="$(readlink "$INPUT_PATH" 2>/dev/null)"

    if [ -z "$LINK_TARGET" ]; then
        printf '%s\n' "$INPUT_PATH"
        return
    fi

    if [[ "$LINK_TARGET" != /* ]]; then
        LINK_DIR="$(dirname "$INPUT_PATH")"
        LINK_TARGET="$LINK_DIR/$LINK_TARGET"
    fi

    canonicalize_path "$LINK_TARGET"
}
# 解析并返回后续流程需要的目标信息。
resolve_finder_alias_path() {
    local INPUT_PATH="$1"
    local RESOLVED_PATH

    # Finder 的“替身”不是 Unix 软链接，readlink 解析不了。
    # 这里用 Finder 的 original item 解析替身背后的真实资源路径。
    RESOLVED_PATH="$(osascript - "$INPUT_PATH" <<'APPLESCRIPT' 2>/dev/null
on run argv
    set inputPath to item 1 of argv
    try
        tell application "Finder"
            set inputItem to (POSIX file inputPath) as alias
            try
                set originalItemPath to POSIX path of ((original item of inputItem) as alias)
                return originalItemPath
            on error
                return inputPath
            end try
        end tell
    on error
        return inputPath
    end try
end run
APPLESCRIPT
)"

    if [ -n "$RESOLVED_PATH" ]; then
        printf '%s\n' "$RESOLVED_PATH"
    else
        printf '%s\n' "$INPUT_PATH"
    fi
}
# 解析并返回后续流程需要的目标信息。
resolve_real_path() {
    local INPUT_PATH="$1"
    local CURRENT_PATH
    local NEXT_PATH
    local INDEX

    CURRENT_PATH="$(canonicalize_path "$INPUT_PATH")"
    INDEX=0

    # 最多解析 10 层：软链接 -> Finder 替身 -> 软链接这种组合也能处理。
    while [ "$INDEX" -lt 10 ]; do
        NEXT_PATH="$(resolve_unix_symlink_path "$CURRENT_PATH")"
        NEXT_PATH="$(resolve_finder_alias_path "$NEXT_PATH")"
        NEXT_PATH="$(canonicalize_path "$NEXT_PATH")"

        if [ "$NEXT_PATH" = "$CURRENT_PATH" ]; then
            break
        fi

        CURRENT_PATH="$NEXT_PATH"
        INDEX=$((INDEX + 1))
    done

    printf '%s\n' "$CURRENT_PATH"
}
# 解析并返回后续流程需要的目标信息。
resolve_dragged_path() {
    resolve_real_path "$1"
}
# 封装 read_project_path 对应的独立处理逻辑。
read_project_path() {
    if [[ -n "${JOBS_IOS_PROJECT_DIR:-}" && -d "$JOBS_IOS_PROJECT_DIR" ]]; then
        PROJECT_PATH="$JOBS_IOS_PROJECT_DIR"
        printf "Finder 目标：%s\n" "$PROJECT_PATH"
        return 0
    fi
    local RAW_PATH
    local NORMALIZED_PATH

    while true; do
        echo "请把 Xcode 工程目录拖到这里，然后按回车："
        read -r RAW_PATH

        NORMALIZED_PATH="$(normalize_dragged_path "$RAW_PATH")"
        NORMALIZED_PATH="$(resolve_dragged_path "$NORMALIZED_PATH")"

        if [ -d "$NORMALIZED_PATH" ]; then
            PROJECT_PATH="$NORMALIZED_PATH"
            printf "${GREEN}已解析目录：%s${NC}\n" "$PROJECT_PATH"
            break
        fi

        echo ""
        printf "${RED}错误：路径不存在，或者不是文件夹：${NC}\n"
        echo "$NORMALIZED_PATH"
        echo "请重新输入。"
        echo ""
    done
}
# 封装 create_output_dir 对应的独立处理逻辑。
create_output_dir() {
    local DESKTOP_DIR="$HOME/Desktop"
    local TIME_TEXT

    TIME_TEXT="$(date '+%Y%m%d_%H%M%S')"
    OUTPUT_DIR="$DESKTOP_DIR/PodspecFiles_$TIME_TEXT"

    mkdir -p "$OUTPUT_DIR"
}
# 封装 create_copied_source_list 对应的独立处理逻辑。
create_copied_source_list() {
    COPIED_SOURCE_LIST="$(mktemp "/tmp/podspec_real_sources.XXXXXX")"
}
# 执行对应的清理操作，并保留必要的安全检查。
cleanup_temp_files() {
    if [ -n "$COPIED_SOURCE_LIST" ] && [ -f "$COPIED_SOURCE_LIST" ]; then
        rm -f "$COPIED_SOURCE_LIST"
    fi
}
# 检查当前运行条件是否满足后续流程要求。
is_podspec_path() {
    local INPUT_PATH="$1"
    local LOWER_PATH

    LOWER_PATH="$(printf '%s' "$INPUT_PATH" | tr '[:upper:]' '[:lower:]')"
    [[ "$LOWER_PATH" == *.podspec ]]
}
# 检查当前运行条件是否满足后续流程要求。
has_copied_source() {
    local REAL_SOURCE_FILE="$1"

    if [ ! -f "$COPIED_SOURCE_LIST" ]; then
        return 1
    fi

    grep -F -x -q -- "$REAL_SOURCE_FILE" "$COPIED_SOURCE_LIST"
}
# 封装 record_copied_source 对应的独立处理逻辑。
record_copied_source() {
    local REAL_SOURCE_FILE="$1"

    printf '%s\n' "$REAL_SOURCE_FILE" >> "$COPIED_SOURCE_LIST"
}
# 封装 make_unique_target_file 对应的独立处理逻辑。
make_unique_target_file() {
    local SOURCE_FILE="$1"
    local FILE_NAME
    local TARGET_FILE
    local NAME
    local EXT
    local INDEX

    FILE_NAME="$(basename "$SOURCE_FILE")"
    TARGET_FILE="$OUTPUT_DIR/$FILE_NAME"

    if [ ! -e "$TARGET_FILE" ]; then
        echo "$TARGET_FILE"
        return
    fi

    if [[ "$FILE_NAME" == *.* ]]; then
        NAME="${FILE_NAME%.*}"
        EXT=".${FILE_NAME##*.}"
    else
        NAME="$FILE_NAME"
        EXT=""
    fi

    INDEX=1

    while [ -e "$OUTPUT_DIR/${NAME}_${INDEX}${EXT}" ]; do
        INDEX=$((INDEX + 1))
    done

    echo "$OUTPUT_DIR/${NAME}_${INDEX}${EXT}"
}
# 封装 make_unique_target_dir 对应的独立处理逻辑。
make_unique_target_dir() {
    local DIR_NAME="$1"
    local TARGET_DIR="$OUTPUT_DIR/$DIR_NAME"
    local INDEX

    if [ ! -e "$TARGET_DIR" ]; then
        echo "$TARGET_DIR"
        return
    fi

    INDEX=1

    while [ -e "$OUTPUT_DIR/${DIR_NAME}_${INDEX}" ]; do
        INDEX=$((INDEX + 1))
    done

    echo "$OUTPUT_DIR/${DIR_NAME}_${INDEX}"
}
# 解析并返回后续流程需要的目标信息。
get_jobs_podspec_kit_file() {
    local PODSPEC_FILE="$1"
    local PODSPEC_DIR
    local KIT_FILE

    PODSPEC_DIR="$(dirname "$PODSPEC_FILE")"
    KIT_FILE="$PODSPEC_DIR/JobsPodspecKit.rb"

    if [ -e "$KIT_FILE" ] || [ -L "$KIT_FILE" ]; then
        printf '%s\n' "$KIT_FILE"
    fi
}
# 封装 copy_jobs_podspec_kit_to_dir 对应的独立处理逻辑。
copy_jobs_podspec_kit_to_dir() {
    local KIT_FILE="$1"
    local TARGET_DIR="$2"
    local REAL_KIT_FILE
    local TARGET_FILE

    REAL_KIT_FILE="$(resolve_real_path "$KIT_FILE")"
    TARGET_FILE="$TARGET_DIR/JobsPodspecKit.rb"

    if [ ! -f "$REAL_KIT_FILE" ]; then
        printf "${RED}找到 JobsPodspecKit.rb，但目标不存在，或者目标不是文件：%s${NC}\n" "$KIT_FILE"
        if [ "$REAL_KIT_FILE" != "$KIT_FILE" ]; then
            printf "${RED}  指向：%s${NC}\n" "$REAL_KIT_FILE"
        fi
        return 1
    fi

    cp -p "$REAL_KIT_FILE" "$TARGET_FILE"

    if [ "$REAL_KIT_FILE" != "$KIT_FILE" ]; then
        echo "已复制：$KIT_FILE -> $REAL_KIT_FILE"
    else
        echo "已复制：$REAL_KIT_FILE"
    fi

    TOTAL_COUNT=$((TOTAL_COUNT + 1))
    return 0
}
# 封装 copy_podspec_to_output_dir 对应的独立处理逻辑。
copy_podspec_to_output_dir() {
    local SOURCE_FILE="$1"
    local REAL_SOURCE_FILE
    local TARGET_FILE
    local FILE_NAME
    local KIT_FILE
    local TARGET_DIR

    REAL_SOURCE_FILE="$(resolve_real_path "$SOURCE_FILE")"

    if [ ! -f "$REAL_SOURCE_FILE" ]; then
        printf "${RED}跳过：目标不存在，或者目标不是文件：%s${NC}\n" "$SOURCE_FILE"
        if [ "$REAL_SOURCE_FILE" != "$SOURCE_FILE" ]; then
            printf "${RED}  指向：%s${NC}\n" "$REAL_SOURCE_FILE"
        fi
        return 1
    fi

    if has_copied_source "$REAL_SOURCE_FILE"; then
        if [ "$REAL_SOURCE_FILE" != "$SOURCE_FILE" ]; then
            printf "${YELLOW}跳过重复目标：%s -> %s${NC}\n" "$SOURCE_FILE" "$REAL_SOURCE_FILE"
        else
            printf "${YELLOW}跳过重复目标：%s${NC}\n" "$REAL_SOURCE_FILE"
        fi
        return 1
    fi

    FILE_NAME="$(basename "$REAL_SOURCE_FILE")"
    KIT_FILE="$(get_jobs_podspec_kit_file "$REAL_SOURCE_FILE")"

    if [ -n "$KIT_FILE" ]; then
        TARGET_DIR="$(make_unique_target_dir "$FILE_NAME")"
        mkdir -p "$TARGET_DIR"
        TARGET_FILE="$TARGET_DIR/$FILE_NAME"
    else
        TARGET_FILE="$(make_unique_target_file "$REAL_SOURCE_FILE")"
    fi

    cp -p "$REAL_SOURCE_FILE" "$TARGET_FILE"
    record_copied_source "$REAL_SOURCE_FILE"

    if [ "$REAL_SOURCE_FILE" != "$SOURCE_FILE" ]; then
        echo "已复制：$SOURCE_FILE -> $REAL_SOURCE_FILE"
    else
        echo "已复制：$REAL_SOURCE_FILE"
    fi

    TOTAL_COUNT=$((TOTAL_COUNT + 1))

    if [ -n "$KIT_FILE" ]; then
        copy_jobs_podspec_kit_to_dir "$KIT_FILE" "$TARGET_DIR"
    fi

    return 0
}
# 封装 copy_to_output_dir 对应的独立处理逻辑。
copy_to_output_dir() {
    local SOURCE_FILE="$1"
    local REAL_SOURCE_FILE
    local TARGET_FILE

    REAL_SOURCE_FILE="$(resolve_real_path "$SOURCE_FILE")"

    if [ ! -f "$REAL_SOURCE_FILE" ]; then
        printf "${RED}跳过：目标不存在，或者目标不是文件：%s${NC}\n" "$SOURCE_FILE"
        if [ "$REAL_SOURCE_FILE" != "$SOURCE_FILE" ]; then
            printf "${RED}  指向：%s${NC}\n" "$REAL_SOURCE_FILE"
        fi
        return 1
    fi

    if has_copied_source "$REAL_SOURCE_FILE"; then
        if [ "$REAL_SOURCE_FILE" != "$SOURCE_FILE" ]; then
            printf "${YELLOW}跳过重复目标：%s -> %s${NC}\n" "$SOURCE_FILE" "$REAL_SOURCE_FILE"
        else
            printf "${YELLOW}跳过重复目标：%s${NC}\n" "$REAL_SOURCE_FILE"
        fi
        return 1
    fi

    TARGET_FILE="$(make_unique_target_file "$REAL_SOURCE_FILE")"

    cp -p "$REAL_SOURCE_FILE" "$TARGET_FILE"
    record_copied_source "$REAL_SOURCE_FILE"

    if [ "$REAL_SOURCE_FILE" != "$SOURCE_FILE" ]; then
        echo "已复制：$SOURCE_FILE -> $REAL_SOURCE_FILE"
    else
        echo "已复制：$REAL_SOURCE_FILE"
    fi

    TOTAL_COUNT=$((TOTAL_COUNT + 1))
    return 0
}
# 封装 copy_podspec_files 对应的独立处理逻辑。
copy_podspec_files() {
    local PODSPEC_FILE

    while IFS= read -r -d '' PODSPEC_FILE; do
        if copy_podspec_to_output_dir "$PODSPEC_FILE"; then
            PODSPEC_COUNT=$((PODSPEC_COUNT + 1))
        fi
    done < <(find "$PROJECT_PATH" \( -type f -o -type l \) -iname "*.podspec" -print0)
}
# 封装 copy_podspec_alias_target_files 对应的独立处理逻辑。
copy_podspec_alias_target_files() {
    local CANDIDATE_FILE
    local REAL_SOURCE_FILE

    # Finder 默认创建的替身通常会叫：xxx.podspec 替身 / xxx.podspec alias。
    # 这里补扫这些候选文件：只要它背后真正指向的是 .podspec，就复制真实目标文件。
    while IFS= read -r -d '' CANDIDATE_FILE; do
        REAL_SOURCE_FILE="$(resolve_real_path "$CANDIDATE_FILE")"

        if [ "$REAL_SOURCE_FILE" = "$CANDIDATE_FILE" ]; then
            continue
        fi

        if [ -f "$REAL_SOURCE_FILE" ] && is_podspec_path "$REAL_SOURCE_FILE"; then
            if copy_podspec_to_output_dir "$CANDIDATE_FILE"; then
                PODSPEC_COUNT=$((PODSPEC_COUNT + 1))
            fi
        fi
    done < <(find "$PROJECT_PATH" \( -type f -o -type l \) \( -iname "*podspec*" -o -iname "*alias*" -o -iname "*替身*" -o -iname "*别名*" \) ! -iname "*.podspec" -print0)
}
# 封装 copy_root_podfile_by_name 对应的独立处理逻辑。
copy_root_podfile_by_name() {
    local PODFILE_NAME="$1"
    local PODFILE_FILE="$PROJECT_PATH/$PODFILE_NAME"
    local REAL_PODFILE_FILE

    if [ -e "$PODFILE_FILE" ] || [ -L "$PODFILE_FILE" ]; then
        REAL_PODFILE_FILE="$(resolve_real_path "$PODFILE_FILE")"

        if [ -f "$REAL_PODFILE_FILE" ]; then
            if copy_to_output_dir "$PODFILE_FILE"; then
                PODFILE_COUNT=$((PODFILE_COUNT + 1))
            fi
        else
            printf "${RED}找到但目标不是文件：%s${NC}\n" "$PODFILE_NAME"
            printf "${RED}  指向：%s${NC}\n" "$REAL_PODFILE_FILE"
        fi
    else
        printf "${RED}未找到：%s${NC}\n" "$PODFILE_NAME"
    fi
}
# 封装 copy_root_podfiles 对应的独立处理逻辑。
copy_root_podfiles() {
    copy_root_podfile_by_name "Podfile.deps"
    copy_root_podfile_by_name "Podfile"
    copy_root_podfile_by_name "Podfile.lock"
}
# 执行对应的清理操作，并保留必要的安全检查。
remove_empty_output_dir_if_needed() {
    if [ "$TOTAL_COUNT" -eq 0 ]; then
        rmdir "$OUTPUT_DIR"
        printf "${RED}没有找到任何 .podspec、Podfile.deps、Podfile、Podfile.lock 文件。${NC}\n"
        exit 0
    fi
}
# 封装 print_result 对应的独立处理逻辑。
print_result() {
    echo ""
    printf "${GREEN}完成，共复制 %s 个文件。${NC}\n" "$TOTAL_COUNT"
    echo "其中 .podspec 文件：$PODSPEC_COUNT 个。"
    echo "其中 Podfile 相关文件：$PODFILE_COUNT 个。"
    echo "输出目录：$OUTPUT_DIR"
}
# 封装 open_output_dir 对应的独立处理逻辑。
open_output_dir() {
    open "$OUTPUT_DIR"
}
# 封装 make_unique_zip_file 对应的独立处理逻辑。
make_unique_zip_file() {
    local ZIP_FILE="$OUTPUT_DIR.zip"
    local ZIP_DIR
    local ZIP_BASE
    local ZIP_NAME
    local INDEX

    if [ ! -e "$ZIP_FILE" ]; then
        echo "$ZIP_FILE"
        return
    fi

    ZIP_DIR="$(dirname "$ZIP_FILE")"
    ZIP_BASE="$(basename "$ZIP_FILE")"
    ZIP_NAME="${ZIP_BASE%.zip}"
    INDEX=1

    while [ -e "$ZIP_DIR/${ZIP_NAME}_${INDEX}.zip" ]; do
        INDEX=$((INDEX + 1))
    done

    echo "$ZIP_DIR/${ZIP_NAME}_${INDEX}.zip"
}
# 收集并校验用户输入，决定后续执行路径。
ask_zip_output_dir() {
    local USER_INPUT
    local ZIP_FILE

    echo ""
    printf "${YELLOW}是否需要打包成 zip？直接回车 = 打包，输入任意字符 = 结束退出：${NC}"
    read -r USER_INPUT

    if [ -n "$USER_INPUT" ]; then
        printf "${YELLOW}已结束，未打包 zip。${NC}
"
        return 0
    fi

    ZIP_FILE="$(make_unique_zip_file)"

    if ditto -c -k --sequesterRsrc --keepParent "$OUTPUT_DIR" "$ZIP_FILE"; then
        printf "${GREEN}已打包 zip：%s${NC}
" "$ZIP_FILE"
    else
        printf "${RED}打包 zip 失败。${NC}
"
        return 1
    fi
}
# 打印脚本内置自述，并按运行入口决定是否等待用户确认。
show_script_intro_and_wait() {
  print -r -- '============================== 脚本内置自述 ==============================' | jobs_intro_style title
  print -r -- '脚本名称：【MacOS】⏳提取项目中所有的pod相关文件.command' | jobs_intro_style title
  print -r -- '核心用途：执行“⏳提取项目中所有的pod相关文件”对应的自动化任务。' | jobs_intro_style body
  print -r -- '影响范围：可能修改当前项目、用户环境或脚本指定的目标。' | jobs_intro_style body
  print -r -- '取消方式：确认前按 Ctrl+C 终止，不会继续执行后续业务。' | jobs_intro_style body
  print -r -- '============================================================================' | jobs_intro_style title
  if [[ ! -t 0 ]]; then
    print -u2 -r -- '当前没有可交互输入，请在终端中重新运行。'
    exit 1
  fi
  read -r "?👉 已了解脚本用途与影响，按回车继续；按 Ctrl+C 取消：" _ || exit 1
}
# 执行入口下沉后的完整业务流程和控制逻辑。
run_main_business_flow() {
    # 注册退出处理，确保异常中断时仍能执行必要收尾。
    trap cleanup_temp_files EXIT

    # 1. 打印脚本自述，并等待用户确认开始。
    print_intro

    # 2. 读取并校验用户拖入的 Xcode 工程目录。
    read_project_path

    # 3. 在桌面创建本次导出的目标文件夹。
    create_output_dir
    # 执行当前流程中的独立业务步骤：create_copied_source_list。
    create_copied_source_list

    # 4. 递归复制项目中的 .podspec 文件。
    copy_podspec_files

    # 5. 补充处理 Finder 默认命名的 podspec 替身文件。
    copy_podspec_alias_target_files

    # 6. 只从工程根目录复制 Podfile.deps、Podfile、Podfile.lock。
    copy_root_podfiles

    # 7. 如果什么都没复制到，则删除空目录并正常结束。
    remove_empty_output_dir_if_needed

    # 8. 打印统计结果，并打开输出目录。
    print_result
    # 执行当前流程中的独立业务步骤：open_output_dir。
    open_output_dir

    # 9. 执行完毕后询问是否需要将输出目录打包成 zip。
    ask_zip_output_dir
}
# 编排脚本的高层业务流程。
# 初始化脚本运行环境，并集中承载原有的顶层执行逻辑。
initialize_script_runtime() {
  setopt NO_NOMATCH TYPESET_SILENT
  set -u
}
# 编排脚本的高层业务流程。
main() {
  show_script_intro_and_wait # 展示脚本内置自述，并按运行入口完成防误触确认。
  initialize_script_runtime # 初始化 Shell 选项、日志、依赖和入口运行状态。
  run_main_business_flow "$@" # 执行入口下沉后的完整业务流程。
}

main "$@"
