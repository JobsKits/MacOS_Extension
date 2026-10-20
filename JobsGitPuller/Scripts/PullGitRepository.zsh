#!/bin/zsh
# 脚本自述：
# - 脚本名称：PullGitRepository.zsh
# - 核心用途：拉取当前工作树分支的上游，冲突时提供还原、放弃改动或提交后重试。
# - 影响范围：仅当前 Git 工作树；不递归更新子模块，不推送，恢复快照保存在 Git 元数据中。
# - 运行提示：先阅读内置自述并回车；未提交内容再次回车确认，丢弃必须输入 YES。

typeset REPO='' PULL_GIT_DIR='' BRANCH='' REMOTE='' MERGE_REF='' ORIGINAL_HEAD=''
typeset SESSION='' REF_BASE='' SNAPSHOT='' INITIAL_SNAPSHOT='' ATTEMPT_HEAD='' TARGET='' LOG_FILE='' LOCK_DIR='' CONFIRMED_TOKEN=''
typeset LOCK_OWNED=0 TRANSACTION_ACTIVE=0 APPLY_ATTEMPTED=0
typeset -a UNTRACKED_PATHS=()

# 将可能含凭据的命令输出脱敏，日志与终端使用同一展示副本。
redact_stream() {
    /usr/bin/perl -pe 's{([a-zA-Z][a-zA-Z0-9+.-]*://)[^/\s]*\@}{$1***\@}g; s{([a-zA-Z][a-zA-Z0-9+.-]*://[^\s?#]+)[?#][^\s]*}{$1?[redacted]}g; s/\e\[[0-9;]*[A-Za-z]//g'
}
# 同步显示并保存纯文本业务日志。
log() {
    if [[ -n "$LOG_FILE" ]]; then
        print -r -- "$*" | redact_stream | /usr/bin/tee -a "$LOG_FILE"
    else
        print -r -- "$*" | redact_stream
    fi
}
# 执行 Git 并保留真实退出码，禁用隐式递归与自动 stash。
run_git() {
    local result
    LC_ALL=C git -C "$REPO" -c submodule.recurse=false -c merge.autoStash=false "$@" 2>&1 | redact_stream | /usr/bin/tee "$SESSION/last-git-output" | /usr/bin/tee -a "$LOG_FILE"
    result=${pipestatus[1]}
    return "$result"
}
# 读取一行；空格不是空输入，EOF 不构成确认。
read_answer() {
    print -n -r -- "$1"
    IFS= read -r REPLY
}
# 先只读判断 Git 归属，非 Git 目录静默退出且不创建日志。
show_script_intro_and_wait() {
    local selected="${1:-$PWD}" answer=''
    [[ -d "$selected" ]] || exit 0
    if [[ -n "${GIT_DIR+x}${GIT_WORK_TREE+x}${GIT_INDEX_FILE+x}${GIT_COMMON_DIR+x}${GIT_NAMESPACE+x}" ]]; then
        print -u2 '✖ 检测到改变仓库或索引归属的 GIT_* 环境变量，请在普通终端中运行。'
        exit 1
    fi
    command -v git >/dev/null 2>&1 || { print -u2 '✖ 未找到 Git，请先安装命令行工具。'; exit 1; }
    [[ "$(git -C "$selected" rev-parse --is-inside-work-tree 2>/dev/null)" == true ]] || exit 0
    REPO="$(git -C "$selected" rev-parse --show-toplevel)" || exit 1
    local title='JobsGitPuller｜拉取 Git 到最新'
    if [[ -t 1 && -n "${TERM:-}" && "$TERM" != dumb && -z "${NO_COLOR+x}" ]]; then
        print -r -- $'\033[1;31m'"$title"$'\033[0m'
        print -r -- $'\033[0;34m1、拉取当前分支上游；保护未提交内容，冲突时三选一。\033[0m'
    else
        print -r -- "$title"
        print -r -- '1、拉取当前分支上游；保护未提交内容，冲突时三选一。'
    fi
    print -r -- "2、作用目录：$REPO"
    print -r -- '3、不递归子模块、不推送；放弃改动需要 YES。请先停止其它 Git 操作和文件编辑。'
    print -r -- '4、日志与恢复锚点保存在当前工作树 Git 元数据的 jobs-git-pull/ 中。Ctrl+C 取消；事务中断保留现场。'
    [[ -t 0 ]] || { print -u2 '✖ 请在可交互终端中运行。'; exit 1; }
    read_answer '已了解用途，直接回车继续；任意字符取消：' || exit 0
    [[ -z "$REPLY" ]] || exit 0
}
# 初始化本工作树互斥锁、私有日志和中断清理。
initialize_runtime() {
    setopt NO_NOMATCH PIPE_FAIL
    umask 077
    PULL_GIT_DIR="$(git -C "$REPO" rev-parse --absolute-git-dir)" || exit 1
    local common_dir="$(git -C "$REPO" rev-parse --git-common-dir)"
    [[ "$common_dir" == /* ]] || common_dir="$REPO/$common_dir"
    LOCK_DIR="${common_dir:A}/jobs-git-pull.lock"
    /bin/mkdir "$LOCK_DIR" 2>/dev/null || { print -u2 "✖ 已有拉取会话或遗留锁：$LOCK_DIR；确认旧进程结束后再处理。"; exit 1; }
    LOCK_OWNED=1
    SESSION="$PULL_GIT_DIR/jobs-git-pull/$(/bin/date +%Y%m%d-%H%M%S)-$$-$RANDOM"
    /bin/mkdir -p "$SESSION" || exit 1
    LOG_FILE="$SESSION/run.log"
    : > "$LOG_FILE" || exit 1
    REF_BASE="refs/jobs-git-pull/${SESSION:t}"
    log "ℹ 日志：$LOG_FILE"
}
# 退出时仅清理本会话锁，不自动 reset 现场；终端载体由外层负责清理。
finish_runtime() {
    if (( TRANSACTION_ACTIVE )); then
        log "⚠ 尚未完成，原 HEAD：$REF_BASE/head；原改动：${SNAPSHOT:-无}"
        log "⚠ 恢复说明：$SESSION/recovery.txt；请勿删除快照。"
    fi
    if (( LOCK_OWNED )); then
        /bin/rmdir "$LOCK_DIR" 2>/dev/null
    fi
}
# 命名退出陷阱保持脚本级生命周期，避免在初始化函数返回时提前释放锁。
TRAPEXIT() {
    local result=$?
    finish_runtime
    return "$result"
}
# 中断只保留现场，不自动重置可能已由外部编辑的文件。
TRAPINT() {
    log '⚠ 已中断，保留当前现场与恢复锚点。'
    exit 130
}
# 终端关闭沿用中断保护，保留可识别的退出码。
TRAPHUP() {
    exit 129
}
# 外部终止沿用脚本级退出清理。
TRAPTERM() {
    exit 143
}
# 拒绝既存事务、稀疏或特殊索引，避免脚本无法完整还原的状态。
validate_repository() {
    local marker entry folder top state_all state_without flags
    for marker in MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD rebase-merge rebase-apply sequencer BISECT_START; do
        [[ ! -e "$PULL_GIT_DIR/$marker" ]] || { log "✖ 已有 Git 操作进行中：$marker，请先完成或中止。"; exit 1; }
    done
    BRANCH="$(git -C "$REPO" symbolic-ref --quiet --short HEAD)" || { log '✖ 游离 HEAD 不拉取。'; exit 1; }
    ORIGINAL_HEAD="$(git -C "$REPO" rev-parse --verify HEAD)" || { log '✖ 当前分支尚无提交。'; exit 1; }
    ATTEMPT_HEAD="$ORIGINAL_HEAD"
    [[ "$(git -C "$REPO" config --bool core.sparseCheckout)" != true ]] || { log '✖ 稀疏检出请在 Git 客户端手动处理。'; exit 1; }
    while IFS= read -r -d '' entry; do
        flags="${entry[1]}"
        [[ "$flags" == H ]] || { log '✖ 存在 skip-worktree、assume-unchanged 或冲突索引，请先恢复普通索引。'; exit 1; }
    done < <(git -C "$REPO" ls-files -v -z)
    state_all="$(git -C "$REPO" status --porcelain=v1 --ignore-submodules=none --untracked-files=all)" || exit 1
    state_without="$(git -C "$REPO" status --porcelain=v1 --ignore-submodules=all --untracked-files=all)" || exit 1
    [[ "$state_all" == "$state_without" ]] || { log '✖ 子模块有未提交内容或检出变化，请先单独处理子模块。'; exit 1; }
    while IFS= read -r -d '' entry; do
        folder="$REPO/${entry%/}"
        [[ -d "$folder" && ! -L "$folder" ]] || continue
        top="$(git -C "$folder" rev-parse --show-toplevel 2>/dev/null)"
        [[ -z "$top" || "$top" == "$REPO" ]] || { log "✖ 未跟踪目录包含独立 Git 仓库：$entry，请先移出或忽略。"; exit 1; }
    done < <(git -C "$REPO" ls-files --others --exclude-standard --directory -z)
    REMOTE="$(git -C "$REPO" config --get "branch.$BRANCH.remote")" || { log '✖ 当前分支未配置 upstream。'; exit 1; }
    MERGE_REF="$(git -C "$REPO" config --get-all "branch.$BRANCH.merge")" || exit 1
    [[ "$REMOTE" != . && "$REMOTE" != -* && "$MERGE_REF" == refs/heads/* && "$MERGE_REF" != *$'\n'* ]] || { log '✖ 只支持一个明确的远端 upstream 分支。'; exit 1; }
    git check-ref-format "$MERGE_REF" || exit 1
    if [[ -n "$state_all" ]]; then
        log '⚠ 当前有未提交内容（含暂存、未暂存及未跟踪文件）：'
        log "$state_all"
        read_answer '直接回车确认保护这些内容后继续；任意字符取消：' || exit 0
        [[ -z "$REPLY" ]] || exit 0
    fi
    CONFIRMED_TOKEN="$(worktree_token)" || exit 1
}
# 展示实际生效来源并只获取明确的上游分支，失败时工作区尚未移动。
fetch_upstream() {
    local configured actual
    configured="$(git -C "$REPO" config --get "remote.$REMOTE.url")" || exit 1
    actual="$(git -C "$REPO" remote get-url "$REMOTE")" || exit 1
    log '━━━━━━━━━━ 来源｜Git 拉取 ━━━━━━━━━━'
    log "📦 工作树：$REPO"
    log "🌐 远端：$REMOTE ｜ 分支：$MERGE_REF"
    log "📥 配置地址：$configured"
    log "📥 拉取地址（本地规则展开）：$actual"
    log '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
    run_git fetch --no-tags --no-recurse-submodules -- "$REMOTE" "+$MERGE_REF:$REF_BASE/upstream" || { log '✖ 获取上游失败，工作区未修改。'; exit 1; }
    TARGET="$(git -C "$REPO" rev-parse "$REF_BASE/upstream^{commit}")" || exit 1
    [[ "$(git -C "$REPO" rev-parse HEAD)" == "$ORIGINAL_HEAD" ]] || { log '✖ 获取期间 HEAD 已改变，停止。'; exit 1; }
    assert_branch || exit 1
    assert_worktree_token "$CONFIRMED_TOKEN" || exit 1
}
# 防止其它 Git 客户端切换分支后，后续命令作用到错误分支。
assert_branch() {
    [[ "$(git -C "$REPO" symbolic-ref --quiet --short HEAD)" == "$BRANCH" ]] || { log '✖ 当前分支已被其它进程切换，停止并保留快照。'; return 1; }
}
# 只有成功计算且一致的状态摘要才能继续，探测失败同样停止。
assert_worktree_token() {
    local current
    current="$(worktree_token)" || { log '✖ 无法读取完整工作区状态，停止并保留现场。'; return 1; }
    [[ "$current" == "$1" ]] || { log '✖ 工作区、索引或分支已被其它进程改动，停止并保留现场。'; return 1; }
}
# 建立持久恢复锚点，将未提交内容移入本会话 stash。
snapshot_worktree() {
    local before after entry
    assert_branch || exit 1
    verify_protected_state || exit 1
    run_git update-ref "$REF_BASE/head" "$ORIGINAL_HEAD" || exit 1
    print -r -- "仓库：$REPO
原 HEAD：$REF_BASE/head
上游：$REF_BASE/upstream
本次 stash 若存在位于 $REF_BASE/snapshot（包含 index 和非忽略的 untracked）。
中断后先检查 git status。已有 merge 用 git merge --abort；再按 head 锚点恢复。
reset --hard 会丢弃中断后编辑，必须人工确认；未跟踪文件先另存，不要直接 clean。
恢复原 HEAD 且工作区干净后：git stash apply --index $REF_BASE/snapshot
快照与日志保留，不自动删除任何既存 stash。" > "$SESSION/recovery.txt"
    if [[ -n "$(git -C "$REPO" status --porcelain=v1 --untracked-files=all)" ]]; then
        before="$(git -C "$REPO" rev-parse -q --verify refs/stash 2>/dev/null)"
        TRANSACTION_ACTIVE=1
        run_git stash push --include-untracked --message "JobsGitPuller ${SESSION:t}" || { log '✖ 快照失败，保留当前状态，请按日志检查。'; exit 1; }
        after="$(git -C "$REPO" rev-parse -q --verify refs/stash)" || exit 1
        [[ "$after" != "$before" ]] || { log '✖ 未得到新的快照，停止。'; exit 1; }
        [[ "$(git -C "$REPO" rev-parse "$after^1")" == "$ORIGINAL_HEAD" && "$(git -C "$REPO" show -s --format=%s "$after")" == *"JobsGitPuller ${SESSION:t}"* ]] || { log '✖ stash 被其它进程改变，无法确认本会话快照，停止并保留现场。'; exit 1; }
        SNAPSHOT="$after"
        INITIAL_SNAPSHOT="$after"
        run_git update-ref "$REF_BASE/snapshot" "$SNAPSHOT" || exit 1
        if git -C "$REPO" rev-parse --verify "$SNAPSHOT^3" >/dev/null 2>&1; then
            while IFS= read -r -d '' entry; do
                UNTRACKED_PATHS+=("$entry")
            done < <(git -C "$REPO" ls-tree -r --name-only -z "$SNAPSHOT^3")
        fi
    fi
    [[ -z "$(git -C "$REPO" status --porcelain=v1 --ignore-submodules=all --untracked-files=all)" ]] || { log '✖ 快照后工作区仍非干净，停止并保留快照。'; exit 1; }
    TRANSACTION_ACTIVE=1
    log "ℹ 恢复锚点：$REF_BASE/head；改动快照：${SNAPSHOT:-无}"
}
# 快照前再次检查隐藏索引和子模块，防止获取远端期间的状态变化被漏掉。
verify_protected_state() {
    local entry state_all state_without marker
    for marker in MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD rebase-merge rebase-apply sequencer BISECT_START; do
        [[ ! -e "$PULL_GIT_DIR/$marker" ]] || { log "✖ 新出现的 Git 操作：$marker，停止。"; return 1; }
    done
    git -C "$REPO" ls-files -v -z > "$SESSION/index-flags" || return 1
    while IFS= read -r -d '' entry; do
        [[ "${entry[1]}" == H ]] || { log '✖ 索引出现隐藏或冲突条目，停止。'; return 1; }
    done < "$SESSION/index-flags"
    state_all="$(git -C "$REPO" status --porcelain=v1 --ignore-submodules=none --untracked-files=all)" || return 1
    state_without="$(git -C "$REPO" status --porcelain=v1 --ignore-submodules=all --untracked-files=all)" || return 1
    [[ "$state_all" == "$state_without" ]] || { log '✖ 子模块状态已变化，停止。'; return 1; }
}
# 从本次合并现场恢复指定检查点，清理仅限本会话恢复过的未跟踪路径。
restore_checkpoint() {
    local checkpoint_head="$1" checkpoint_snapshot="$2" entry
    assert_branch || return 1
    if [[ -f "$PULL_GIT_DIR/MERGE_HEAD" ]]; then
        run_git merge --abort || return 1
    fi
    run_git -c core.hooksPath=/dev/null reset --hard "$checkpoint_head" || return 1
    if (( APPLY_ATTEMPTED )); then
        for entry in "${UNTRACKED_PATHS[@]}"; do
            verify_untracked_before_cleanup "$entry" || return 1
            run_git --literal-pathspecs clean -f -- "$entry" || return 1
        done
    fi
    if [[ -n "$checkpoint_snapshot" ]]; then
        run_git stash apply --index "$checkpoint_snapshot" || { log '✖ 快照恢复失败；保留现场与快照，停止。'; return 1; }
    fi
    APPLY_ATTEMPTED=0
    return 0
}
# 只允许清理快照原样恢复的未跟踪文件，外部编辑或类型变化必须停止。
verify_untracked_before_cleanup() {
    local entry="$1" expected actual
    [[ -e "$REPO/$entry" || -L "$REPO/$entry" ]] || return 0
    git -C "$REPO" --literal-pathspecs ls-files --error-unmatch -- "$entry" >/dev/null 2>&1 && return 0
    expected="$(git -C "$REPO" rev-parse "$INITIAL_SNAPSHOT^3:$entry")" || return 1
    if [[ -L "$REPO/$entry" ]]; then
        actual="$(/usr/bin/readlink "$REPO/$entry" | /usr/bin/perl -pe 'chomp if eof' | git -C "$REPO" hash-object --stdin)" || return 1
    elif [[ -f "$REPO/$entry" ]]; then
        actual="$(git -C "$REPO" hash-object --path="$entry" -- "$REPO/$entry")" || return 1
    else
        log "✖ 快照路径类型已变化，保留并停止：$entry"
        return 1
    fi
    [[ "$actual" == "$expected" ]] || { log "✖ 未跟踪文件已被外部修改，保留并停止：$entry"; return 1; }
}
# 仅明确确认后舍弃快照内容，保留原有本地提交并重新合并上游。
discard_original() {
    local token answer read_result
    token="$(worktree_token)" || return 1
    read_answer '⚠ 将放弃拉取前全部未提交内容（不含 ignored / 子仓），输入 YES 确认：'
    read_result=$?
    answer="$REPLY"
    assert_worktree_token "$token" || return 1
    (( read_result == 0 )) && [[ "$answer" == YES ]] || return 2
    restore_checkpoint "$ATTEMPT_HEAD" "$SNAPSHOT" || return 1
    if [[ -n "$SNAPSHOT" ]]; then
        run_git stash push --include-untracked --message "JobsGitPuller discarded ${SESSION:t}" || return 1
    fi
    SNAPSHOT=''
    APPLY_ATTEMPTED=0
    return 0
}
# 提交最初的改动，空行作为合法空提交信息，保留既有本地提交。
commit_original() {
    local message token
    if [[ "$ATTEMPT_HEAD" != "$ORIGINAL_HEAD" ]]; then
        restore_checkpoint "$ATTEMPT_HEAD" '' || return 1
        log '⚠ 本轮改动已经提交；已提交历史间的冲突需要手动解决，提交已保留。'
        return 1
    fi
    restore_checkpoint "$ATTEMPT_HEAD" "$SNAPSHOT" || return 1
    if [[ -z "$(git -C "$REPO" status --porcelain=v1 --ignore-submodules=all --untracked-files=all)" ]]; then
        log '⚠ 原始状态没有可提交改动；已还原。请手动解决已提交历史间的冲突。'
        return 1
    fi
    token="$(worktree_token)" || return 1
    read_answer '输入 commit 信息（直接回车也立即提交，允许空信息）：' || return 1
    message="$REPLY"
    assert_worktree_token "$token" || return 1
    run_git add --all || return 1
    if ! run_git commit --allow-empty-message --message "$message"; then
        log '✖ 提交失败（身份、签名或 hook 等），保留原 HEAD、工作区和快照；不继续拉取。'
        return 1
    fi
    ATTEMPT_HEAD="$(git -C "$REPO" rev-parse HEAD)" || return 1
    run_git update-ref "$REF_BASE/committed" "$ATTEMPT_HEAD" || return 1
    SNAPSHOT=''
    APPLY_ATTEMPTED=0
    return 0
}
# 汇总 HEAD、分支、索引、工作区及未跟踪内容，识别等待输入期间的外部改动。
worktree_token() {
    local directory token result
    directory="$(/usr/bin/mktemp -d "$SESSION/token.XXXXXX")" || return 1
    write_worktree_token "$directory"
    result=$?
    if (( result == 0 )); then
        token="$(git -C "$REPO" hash-object --no-filters -- "$directory/input")"
        result=$?
    fi
    /bin/rm -f -- "$directory/input" "$directory/paths"
    /bin/rmdir "$directory" 2>/dev/null
    (( result == 0 )) || return 1
    print -r -- "$token"
}
# 逐项读取状态并检查退出码，不能把失败的 Git 探测当作空工作区。
write_worktree_token() {
    local directory="$1" entry
    git -C "$REPO" rev-parse HEAD > "$directory/input" || return 1
    git -C "$REPO" symbolic-ref --quiet HEAD >> "$directory/input" || return 1
    git -C "$REPO" status --porcelain=v1 -z --untracked-files=all >> "$directory/input" || return 1
    git -C "$REPO" ls-files -v -z >> "$directory/input" || return 1
    git -C "$REPO" diff --binary --no-ext-diff >> "$directory/input" || return 1
    git -C "$REPO" diff --cached --binary --no-ext-diff >> "$directory/input" || return 1
    git -C "$REPO" ls-files --others --exclude-standard -z > "$directory/paths" || return 1
    while IFS= read -r -d '' entry; do
        print -rn -- "$entry"$'\0' >> "$directory/input" || return 1
        if [[ -L "$REPO/$entry" ]]; then
            /usr/bin/readlink "$REPO/$entry" >> "$directory/input" || return 1
        elif [[ -f "$REPO/$entry" ]]; then
            /bin/cat -- "$REPO/$entry" >> "$directory/input" || return 1
        else
            return 1
        fi
    done < "$directory/paths"
}
# 冲突菜单只接受三个明确选项，EOF 按还原处理。
resolve_conflict() {
    local token choice_result
    log '⚠ 合并或恢复本地改动发生冲突：'
    log '1、回滚到当前这轮拉取之前（HEAD、暂存区和工作区；已确认的新提交保留）。'
    log '2、放弃拉取前未提交内容，再拉取最新（保留本地已提交历史）。'
    log '3、先恢复并提交拉取前的改动，再拉取最新。'
    while true; do
        token="$(worktree_token)" || return 1
        if ! read_answer '输入 1 / 2 / 3（回车默认 1）：'; then
            REPLY=1
        fi
        assert_worktree_token "$token" || return 1
        case "$REPLY" in
            ''|1)
                restore_checkpoint "$ATTEMPT_HEAD" "$SNAPSHOT" || exit 1
                TRANSACTION_ACTIVE=0
                log '✔ 已回滚到拉取前状态，恢复快照保留。'
                return 2
                ;;
            2)
                discard_original
                choice_result=$?
                if (( choice_result == 2 )); then
                    restore_checkpoint "$ATTEMPT_HEAD" "$SNAPSHOT" || return 1
                    TRANSACTION_ACTIVE=0
                    return 1
                fi
                (( choice_result == 0 )) || return 1
                return 0
                ;;
            3)
                commit_original || return 1
                return 0
                ;;
            *) log '⚠ 只支持 1 / 2 / 3。' ;;
        esac
    done
}
# 合并固定的本次远端提交，再还原本地改动；失败时严格区分冲突和其它错误。
merge_and_restore() {
    local merge_result conflict_result apply_output
    while true; do
        assert_branch || return 1
        run_git -c rerere.enabled=false merge --commit --no-squash --no-edit --no-autostash --no-overwrite-ignore "$TARGET"
        merge_result=$?
        if (( merge_result == 0 )); then
            if [[ -f "$PULL_GIT_DIR/MERGE_HEAD" ]] || ! git -C "$REPO" merge-base --is-ancestor "$TARGET" HEAD; then
                log '✖ 合并命令结束但远端历史尚未整合，保留现场与快照。'
                return 1
            fi
            if [[ -n "$SNAPSHOT" ]]; then
                APPLY_ATTEMPTED=1
                if ! run_git stash apply --index "$SNAPSHOT"; then
                    apply_output="$(/bin/cat "$SESSION/last-git-output")"
                    if [[ -z "$(git -C "$REPO" ls-files --unmerged)" && "$apply_output" != *'patch failed'* && "$apply_output" != *'already exists'* && "$apply_output" != *'CONFLICT'* && "$apply_output" != *'conflicts in index'* ]]; then
                        log '✖ 恢复快照失败但未确认文件冲突，保留现场和快照，请人工检查。'
                        return 1
                    fi
                    resolve_conflict
                    conflict_result=$?
                    (( conflict_result == 2 )) && return 0
                    (( conflict_result == 0 )) || return 1
                    refresh_upstream_for_retry || return 1
                    continue
                fi
            fi
            TRANSACTION_ACTIVE=0
            log "✔ 已整合上游 $REMOTE/$MERGE_REF（$TARGET），未提交内容已保留。"
            log "ℹ 当前 HEAD：$(git -C "$REPO" rev-parse HEAD)；来源：$(git -C "$REPO" remote get-url "$REMOTE")"
            return 0
        fi
        if [[ -n "$(git -C "$REPO" ls-files --unmerged)" ]]; then
            resolve_conflict
            conflict_result=$?
            (( conflict_result == 2 )) && return 0
            (( conflict_result == 0 )) || return 1
            refresh_upstream_for_retry || return 1
            continue
        fi
        log '✖ 合并失败但没有文件冲突；正在还原，不进入冲突选项。'
        restore_checkpoint "$ATTEMPT_HEAD" "$SNAPSHOT" || exit 1
        TRANSACTION_ACTIVE=0
        return 1
    done
}
# 提交或放弃后重新获取最新上游，避免用户输入期间远端推进导致使用旧目标。
refresh_upstream_for_retry() {
    local token
    assert_branch || return 1
    [[ "$(git -C "$REPO" config --get "branch.$BRANCH.remote")" == "$REMOTE" && "$(git -C "$REPO" config --get-all "branch.$BRANCH.merge")" == "$MERGE_REF" ]] || { log '✖ upstream 配置已变化，保留当前基线并停止。'; return 1; }
    token="$(worktree_token)" || return 1
    log "ℹ 已确认的新基线：$ATTEMPT_HEAD；重新获取 $REMOTE/$MERGE_REF。"
    log "📥 拉取地址：$(git -C "$REPO" remote get-url "$REMOTE")"
    if ! run_git fetch --no-tags --no-recurse-submodules -- "$REMOTE" "+$MERGE_REF:$REF_BASE/upstream"; then
        TRANSACTION_ACTIVE=0
        log '✖ 再次获取失败，已确认的提交或放弃结果保留；未开始新一轮合并。'
        return 1
    fi
    assert_worktree_token "$token" || return 1
    TARGET="$(git -C "$REPO" rev-parse "$REF_BASE/upstream^{commit}")" || return 1
}
# 编排只读门禁、确认、远端获取、快照与合并。
main() {
    show_script_intro_and_wait "$@" # 非 Git 静默退出，展示影响范围并等待确认。
    initialize_runtime # 为本工作树建立独立锁、日志和退出清理。
    validate_repository # 检查上游和仓库状态，未提交内容再次确认。
    fetch_upstream # 工作区未移动前先获取准确上游提交。
    snapshot_worktree # 为 HEAD、暂存区与工作区建立可恢复锚点。
    merge_and_restore # 合并上游并处理冲突三选项。
}

main "$@"
