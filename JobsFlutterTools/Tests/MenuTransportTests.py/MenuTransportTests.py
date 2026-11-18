# JOBS_TERMINAL_STYLE_GUARD_V1_BEGIN
# 保存与恢复由监督进程负责；导入本模块时不接管终端。
def _jobs_terminal_style_bootstrap_v1():
    import os as _os
    import base64 as _base64
    import json as _json
    import shutil as _shutil
    import subprocess as _subprocess
    import sys as _sys
    import tempfile as _tempfile

    _entry = _os.path.abspath(__file__)
    if _os.environ.get("JOBS_TERMINAL_STYLE_REEXEC") == _entry:
        _os.environ.pop("JOBS_TERMINAL_STYLE_REEXEC", None)
        return
    if (getattr(_sys, "frozen", False) or not _sys.stdin or not _sys.stdout
            or not _sys.stdin.isatty() or not _sys.stdout.isatty()
            or "NO_COLOR" in _os.environ
            or _os.environ.get("PLAIN_OUTPUT") == "1"
            or _os.environ.get("IS_SOURCETREE_RUNTIME") == "1"
            or any(_key.upper().startswith(("SOURCETREE", "SOURCE_TREE"))
                   for _key in _os.environ)):
        return
    if _os.name != "nt" and (_os.environ.get("TERM", "") in ("", "dumb")
                             or _os.environ.get("TMUX") or _os.environ.get("STY")):
        return
    _original = getattr(_sys, "orig_argv", None)
    _module_start = False
    for _argument in list(_original[1:]) if _original else []:
        if _argument == "--" or _os.path.abspath(_argument) == _entry:
            break
        if _argument in ("-c", "-m"):
            _module_start = True
            break
    if _module_start:
        _os.environ.update(NO_COLOR="1", PLAIN_OUTPUT="1", FORCE_COLOR="0", CLICOLOR="0")
        return
    _command = [_sys.executable] + (list(_original[1:]) if _original else list(_sys.argv))
    _environment = _os.environ.copy()
    _environment["JOBS_TERMINAL_STYLE_REEXEC"] = _entry
    _shell_core = r"""# 临时保护当前终端配色，业务进程自行管理原有退出清理。
jobs_terminal_style_run() {
    # 无法可靠保存原色时，沿用脚本已有的纯文本约定。
    jobs_terminal_style_plain() {
        PLAIN_OUTPUT=1
        NO_COLOR=1
        FORCE_COLOR=0
        CLICOLOR=0
        ANSI_COLORS_DISABLED=1
        npm_config_color=false
        export PLAIN_OUTPUT NO_COLOR FORCE_COLOR CLICOLOR ANSI_COLORS_DISABLED npm_config_color
        if "$@"; then
            jobs_style_exit_status=0
        else
            jobs_style_exit_status=$?
        fi
        exit "$jobs_style_exit_status"
    }
    if [ ! -t 0 ] || [ ! -t 1 ] || [ -z "${TERM:-}" ] ||
       [ "${TERM:-}" = dumb ] || [ "${NO_COLOR+x}" = x ] ||
       [ "${PLAIN_OUTPUT:-0}" = 1 ] || [ "${IS_SOURCETREE_RUNTIME:-0}" = 1 ] ||
       env | LC_ALL=C grep -qiE '^(SOURCETREE|SOURCE_TREE)'; then
        if "$@"; then
            jobs_style_exit_status=0
        else
            jobs_style_exit_status=$?
        fi
        exit "$jobs_style_exit_status"
    fi
    if [ -n "${TMUX:-}${STY:-}" ]; then
        jobs_terminal_style_plain "$@"
    fi
    jobs_style_tty=$(tty 2>/dev/null) || jobs_terminal_style_plain "$@"
    if ! ps -o pgid= -o tpgid= -p "$$" 2>/dev/null |
         LC_ALL=C awk 'NF == 2 && $1 == $2 && $1 > 0 { foreground = 1 } END { exit !foreground }'; then
        jobs_terminal_style_plain "$@"
    fi
    case ${JOBS_TERMINAL_STYLE_OWNER:-} in
        ''|*[!0-9]*) ;;
        *)
            if [ "${JOBS_TERMINAL_STYLE_TTY:-}" = "$jobs_style_tty" ] &&
               kill -0 "$JOBS_TERMINAL_STYLE_OWNER" 2>/dev/null; then
                if "$@"; then
                    jobs_style_exit_status=0
                else
                    jobs_style_exit_status=$?
                fi
                exit "$jobs_style_exit_status"
            fi
            ;;
    esac
    jobs_style_stty=$(stty -g 2>/dev/null < /dev/tty) || jobs_terminal_style_plain "$@"
    jobs_style_saved=''
    jobs_style_saved_rows=''
    jobs_style_applied_rows=''
    jobs_style_changed=0
    jobs_style_applied_complete=0
    jobs_style_query_active=0
    jobs_style_recovery=''
    jobs_style_exit_status=0
    jobs_style_esc=$(printf '\033')
    jobs_style_bel=$(printf '\007')
    # 只接受本次请求对应的 RGB 响应；非协议输入使本次探测失败。
    jobs_terminal_style_query() {
        jobs_style_query_key=$1
        printf '\033]%s;?\007' "$jobs_style_query_key" > /dev/tty || return 1
        jobs_style_reply=''
        for jobs_style_attempt in 1 2 3; do
            jobs_style_piece=$(dd bs=256 count=1 2>/dev/null < /dev/tty)
            jobs_style_reply=$jobs_style_reply$jobs_style_piece
            case $jobs_style_reply in
                *"$jobs_style_bel"|*"$jobs_style_esc\\") break ;;
                '') ;;
                "$jobs_style_esc"*) ;;
                *) break ;;
            esac
        done
        case $jobs_style_reply in
            "$jobs_style_esc]$jobs_style_query_key;rgb:"*"$jobs_style_bel")
                jobs_style_rgb=${jobs_style_reply#"$jobs_style_esc]$jobs_style_query_key;rgb:"}
                jobs_style_rgb=${jobs_style_rgb%"$jobs_style_bel"}
                ;;
            "$jobs_style_esc]$jobs_style_query_key;rgb:"*"$jobs_style_esc\\")
                jobs_style_rgb=${jobs_style_reply#"$jobs_style_esc]$jobs_style_query_key;rgb:"}
                jobs_style_rgb=${jobs_style_rgb%"$jobs_style_esc\\"}
                ;;
            *) return 1 ;;
        esac
        jobs_style_normalized=$(printf '%s\n' "$jobs_style_rgb" | LC_ALL=C awk -F/ '
            NF != 3 { exit 1 }
            {
                for (i = 1; i <= 3; i++) {
                    h = tolower($i)
                    if (length(h) < 1 || length(h) > 4 || h ~ /[^0-9a-f]/) exit 1
                    n = 0
                    for (j = 1; j <= length(h); j++) n = n * 16 + index("0123456789abcdef", substr(h, j, 1)) - 1
                    value[i] = int(n * 65535 / (16 ^ length(h) - 1) + 0.5)
                }
                printf "%d/%d/%d", value[1], value[2], value[3]
            }
        ') || return 1
        [ -n "$jobs_style_normalized" ]
    }
    # 查询可用不代表终端允许改色，按目标值核对实际生效结果。
    jobs_terminal_style_accepts_target() {
        jobs_style_requested_hex=''
        case $1 in
            10|12) jobs_style_requested_hex=ffffff ;;
            11) jobs_style_requested_hex=000000 ;;
            '4;'*)
                jobs_style_requested_index=0
                for jobs_style_requested_color in 000000 ff5f56 5fd787 ffd75f 5fafff d787ff 5fd7ff eeeeee 9e9e9e ff8787 87ffaf ffff87 87bfff ffafff afffff ffffff; do
                    if [ "4;$jobs_style_requested_index" = "$1" ]; then
                        jobs_style_requested_hex=$jobs_style_requested_color
                        break
                    fi
                    jobs_style_requested_index=$((jobs_style_requested_index + 1))
                done
                ;;
        esac
        [ -n "$jobs_style_requested_hex" ] || return 1
        printf '%s|%s\n' "$jobs_style_normalized" "$jobs_style_requested_hex" | LC_ALL=C awk -F'|' '
            function hexbyte(h) {
                return (index("0123456789abcdef", substr(h, 1, 1)) - 1) * 16 + index("0123456789abcdef", substr(h, 2, 1)) - 1
            }
            {
                if (split($1, actual, "/") != 3 || length($2) != 6) exit 1
                for (i = 1; i <= 3; i++) {
                    difference = actual[i] - hexbyte(substr($2, i * 2 - 1, 2)) * 257
                    if (difference < -255 || difference > 255) exit 1
                }
            }
        '
    }
    # 检测到后续改色时只恢复仍由本次保护持有的项，保留独立恢复入口。
    jobs_terminal_style_cleanup() {
        jobs_style_result=$1
        trap '' HUP INT TERM
        if [ "$jobs_style_query_active" = 1 ]; then
            stty "$jobs_style_stty" 2>/dev/null < /dev/tty || :
            jobs_style_query_active=0
        fi
        if [ "$jobs_style_changed" = 1 ]; then
            jobs_style_cleanup_ok=0
            jobs_style_conflicts=''
            jobs_style_restore_safe=''
            if [ "$jobs_style_applied_complete" = 1 ]; then
                jobs_style_stty=$(stty -g 2>/dev/null < /dev/tty) || jobs_style_stty=''
                if [ -n "$jobs_style_stty" ] && stty -echo -icanon min 0 time 1 2>/dev/null < /dev/tty; then
                    jobs_style_query_active=1
                    jobs_style_cleanup_ok=1
                    while IFS='|' read -r jobs_style_key jobs_style_expected jobs_style_original; do
                        [ -n "$jobs_style_key" ] || continue
                        if ! jobs_terminal_style_query "$jobs_style_key"; then
                            jobs_style_cleanup_ok=0
                            break
                        fi
                        if [ "$jobs_style_normalized" = "$jobs_style_expected" ]; then
                            jobs_style_restore_safe=$jobs_style_restore_safe$jobs_style_original
                        else
                            jobs_style_conflicts="$jobs_style_conflicts $jobs_style_key"
                        fi
                    done <<JOBS_STYLE_APPLIED
$jobs_style_applied_rows
JOBS_STYLE_APPLIED
                    stty "$jobs_style_stty" 2>/dev/null < /dev/tty || jobs_style_cleanup_ok=0
                    jobs_style_query_active=0
                fi
            fi
            if [ "$jobs_style_cleanup_ok" = 1 ] && printf '%s\033[0m' "$jobs_style_restore_safe" > /dev/tty; then
                if [ -z "$jobs_style_conflicts" ]; then
                    rm -f "$jobs_style_recovery"
                    rmdir "${jobs_style_recovery%/*}" 2>/dev/null || :
                else
                    printf '检测到运行期间的配色变更，已保留这些项：%s\n' "$jobs_style_conflicts" >&2
                    printf '确认要覆盖后续改色时才使用恢复入口：sh "%s"\n' "$jobs_style_recovery" >&2
                    [ "$jobs_style_result" -ne 0 ] || jobs_style_result=1
                fi
            else
                printf '终端配色未能安全自动恢复；确认覆盖当前配色后可运行：sh "%s"\n' "$jobs_style_recovery" >&2
                [ "$jobs_style_result" -ne 0 ] || jobs_style_result=1
            fi
        fi
        if [ "${2:-}" = continue ]; then
            jobs_style_cleanup_status=$jobs_style_result
            return 0
        fi
        exit "$jobs_style_result"
    }
    trap 'jobs_terminal_style_cleanup "$jobs_style_exit_status"' 0
    trap 'jobs_style_exit_status=129; exit 129' HUP
    trap 'jobs_style_exit_status=130; exit 130' INT
    trap 'jobs_style_exit_status=143; exit 143' TERM
    if ! stty -echo -icanon min 0 time 1 2>/dev/null < /dev/tty; then
        jobs_terminal_style_plain "$@"
    fi
    jobs_style_query_active=1
    jobs_style_probe_ok=1
    for jobs_style_key in 10 11 12 '4;0' '4;1' '4;2' '4;3' '4;4' '4;5' '4;6' '4;7' '4;8' '4;9' '4;10' '4;11' '4;12' '4;13' '4;14' '4;15'; do
        if ! jobs_terminal_style_query "$jobs_style_key"; then
            jobs_style_probe_ok=0
            break
        fi
        jobs_style_saved=$jobs_style_saved$jobs_style_reply
        jobs_style_saved_rows="$jobs_style_saved_rows$jobs_style_key|$jobs_style_reply
"
    done
    stty "$jobs_style_stty" 2>/dev/null < /dev/tty || { jobs_style_exit_status=1; exit 1; }
    jobs_style_query_active=0
    if [ "$jobs_style_probe_ok" != 1 ]; then
        printf '%s\n' '终端不支持完整配色保存，或启动时收到其它输入；保留原配色并使用纯文本。' >&2
        jobs_terminal_style_plain "$@"
    fi
    jobs_style_recovery_dir=$(umask 077; mktemp -d "${TMPDIR:-/tmp}/jobs-terminal-style.XXXXXX") || jobs_terminal_style_plain "$@"
    jobs_style_recovery=$jobs_style_recovery_dir/restore.sh
    if ! (umask 077; {
        printf '#!/bin/sh\n'
        printf '[ -t 0 ] && [ "$(tty)" = '\''%s'\'' ] || { printf '\''请在原终端运行恢复入口。\\n'\'' >&2; exit 1; }\n' "$jobs_style_tty"
        printf 'printf '\''本操作会覆盖此终端当前配色。确认恢复脚本启动前的配色，请输入 YES：'\'' >&2\n'
        printf 'IFS= read -r jobs_restore_choice\n[ "$jobs_restore_choice" = YES ] || exit 1\n'
        printf 'printf '\''%%s\\033[0m'\'' '\''%s'\'' > /dev/tty\n' "$jobs_style_saved"
    } > "$jobs_style_recovery"); then
        printf '%s\n' '无法保存终端配色恢复入口；保留原配色并使用纯文本。' >&2
        jobs_terminal_style_plain "$@"
    fi
    printf '正在准备本次终端临时配色；强退后恢复入口：sh "%s"\n' "$jobs_style_recovery" >&2
    jobs_style_changed=1
    printf '\033]10;#ffffff\007\033]11;#000000\007\033]12;#ffffff\007' > /dev/tty
    jobs_style_index=0
    for jobs_style_color in 000000 ff5f56 5fd787 ffd75f 5fafff d787ff 5fd7ff eeeeee 9e9e9e ff8787 87ffaf ffff87 87bfff ffafff afffff ffffff; do
        printf '\033]4;%s;#%s\007' "$jobs_style_index" "$jobs_style_color" > /dev/tty
        jobs_style_index=$((jobs_style_index + 1))
    done
    printf '\033[0m' > /dev/tty
    jobs_style_stty=$(stty -g 2>/dev/null < /dev/tty) || { jobs_style_exit_status=1; exit 1; }
    stty -echo -icanon min 0 time 1 2>/dev/null < /dev/tty || { jobs_style_exit_status=1; exit 1; }
    jobs_style_query_active=1
    jobs_style_probe_ok=1
    jobs_style_targets_ok=1
    while IFS='|' read -r jobs_style_key jobs_style_original; do
        [ -n "$jobs_style_key" ] || continue
        if ! jobs_terminal_style_query "$jobs_style_key"; then
            jobs_style_probe_ok=0
            break
        fi
        jobs_style_applied_rows="$jobs_style_applied_rows$jobs_style_key|$jobs_style_normalized|$jobs_style_original
"
        if ! jobs_terminal_style_accepts_target "$jobs_style_key"; then
            jobs_style_targets_ok=0
        fi
    done <<JOBS_STYLE_ORIGINAL
$jobs_style_saved_rows
JOBS_STYLE_ORIGINAL
    stty "$jobs_style_stty" 2>/dev/null < /dev/tty || { jobs_style_exit_status=1; exit 1; }
    jobs_style_query_active=0
    if [ "$jobs_style_probe_ok" != 1 ]; then
        printf '%s\n' '无法核实本次临时配色，已停止启动业务。' >&2
        jobs_style_exit_status=1
        exit 1
    fi
    jobs_style_applied_complete=1
    if [ "$jobs_style_targets_ok" != 1 ]; then
        jobs_terminal_style_cleanup 0 continue
        jobs_style_changed=0
        if [ "$jobs_style_cleanup_status" != 0 ]; then
            jobs_style_exit_status=1
            exit 1
        fi
        trap 'jobs_style_exit_status=129; exit 129' HUP
        trap 'jobs_style_exit_status=130; exit 130' INT
        trap 'jobs_style_exit_status=143; exit 143' TERM
        printf '%s\n' '终端未接受本次配色，已恢复原配色并使用纯文本。' >&2
        jobs_terminal_style_plain "$@"
    fi
    printf '%s\n' '本次终端已临时使用黑底白字。' >&2
    JOBS_TERMINAL_STYLE_TTY=$jobs_style_tty
    JOBS_TERMINAL_STYLE_OWNER=$$
    export JOBS_TERMINAL_STYLE_TTY JOBS_TERMINAL_STYLE_OWNER
    if "$@"; then
        jobs_style_exit_status=0
    else
        jobs_style_exit_status=$?
    fi
    exit "$jobs_style_exit_status"
}
"""
    _powershell_core = r"""$__jobsTerminalCommand = @($args)
# BEGIN JOBS_TERMINAL_STYLE_V1 - session-only colors; no profile or registry changes.
function New-JobsTerminalStyleState {
    if ($PSVersionTable.PSVersion.Major -lt 5) { return @{ JobsTerminalPlainFallback = $true; Before = @{} } }
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or $Host.Name -ne 'ConsoleHost') { return $null }
    if ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected -or [Console]::IsErrorRedirected) { return $null }
    if ((Test-Path Env:NO_COLOR) -or $env:TERM -ieq 'dumb' -or $env:PLAIN_OUTPUT -eq '1') { return $null }
    foreach ($key in [Environment]::GetEnvironmentVariables().Keys) {
        if ([string]$key -match '^(?i:SOURCE_?TREE)') { return $null }
    }
    if (-not ('Jobs.TerminalStyleV1.Native' -as [type])) {
        try {
        Add-Type -ErrorAction Stop -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
namespace Jobs.TerminalStyleV1 {
    public static class Native {
        [StructLayout(LayoutKind.Explicit, Size=20, CharSet=CharSet.Unicode)]
        public struct InputRecord {
            [FieldOffset(0)] public ushort Kind;
            [FieldOffset(4)] public int Down;
            [FieldOffset(8)] public ushort Repeat;
            [FieldOffset(10)] public ushort Key;
            [FieldOffset(12)] public ushort Scan;
            [FieldOffset(14)] public char Character;
            [FieldOffset(16)] public uint Modifiers;
        }
        [DllImport("kernel32.dll")] static extern IntPtr GetStdHandle(int n);
        [DllImport("kernel32.dll")] static extern IntPtr GetConsoleWindow();
        [DllImport("kernel32.dll")] static extern bool GetConsoleMode(IntPtr h, out uint mode);
        [DllImport("kernel32.dll")] static extern bool SetConsoleMode(IntPtr h, uint mode);
        [DllImport("kernel32.dll")] static extern uint WaitForSingleObject(IntPtr h, uint milliseconds);
        [DllImport("kernel32.dll")] static extern bool GetNumberOfConsoleInputEvents(IntPtr h, out uint count);
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, ExactSpelling=true)] static extern bool ReadConsoleInputW(IntPtr h, [Out] InputRecord[] records, uint count, out uint read);
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, ExactSpelling=true)] static extern bool WriteConsoleInputW(IntPtr h, InputRecord[] records, uint count, out uint written);
        const string OwnerName = "JOBS_TERMINAL_STYLE_WINDOWS_OWNER";
        static readonly string[] Keys = { "10", "11", "4;0", "4;1", "4;2", "4;3", "4;4", "4;5", "4;6", "4;7", "4;8", "4;9", "4;10", "4;11", "4;12", "4;13", "4;14", "4;15" };
        static readonly string[] Hex = { "000000", "ff5f56", "5fd787", "ffd75f", "5fafff", "d787ff", "5fd7ff", "eeeeee", "9e9e9e", "ff8787", "87ffaf", "ffff87", "87bfff", "ffafff", "afffff", "ffffff" };
        static readonly Regex Reply = new Regex("\\x1b\\](?<key>10|11|4;[0-9]{1,2});(?<rgb>rgb:[0-9a-f]{1,4}/[0-9a-f]{1,4}/[0-9a-f]{1,4})(?:\\x07|\\x1b\\\\)", RegexOptions.IgnoreCase);
        public sealed class State {
            public IntPtr Input, Output;
            public uint OutputMode;
            public ConsoleColor Foreground, Background;
            public Dictionary<string,string> Original, Applied;
            public string Owner, PreviousOwner, Recovery;
            public bool Active, ModeChanged, Fallback;
            public Dictionary<string,string> EnvironmentBefore = new Dictionary<string,string>();
        }
        static string Escape(string key, string value) { return "\x1b]" + key + ";" + value + "\x07"; }
        static string Rgb(string hex) { return "rgb:" + hex.Substring(0,2) + "/" + hex.Substring(2,2) + "/" + hex.Substring(4,2); }
        static string Normal(string rgb) {
            string[] parts = rgb.Substring(4).Split('/');
            for (int n=0; n<3; n++) {
                int maximum = (1 << (4 * parts[n].Length)) - 1;
                int value = Convert.ToInt32(parts[n],16);
                parts[n] = ((value * 65535L + maximum/2) / maximum).ToString("x4");
            }
            return String.Join("/",parts);
        }
        // Preserve unrelated key/window records instead of consuming user input during color queries.
        static Dictionary<string,string> Query(State state) {
            uint pending;
            if (!GetNumberOfConsoleInputEvents(state.Input,out pending) || pending != 0) { return null; }
            StringBuilder commands = new StringBuilder();
            foreach (string key in Keys) { commands.Append(Escape(key,"?")); }
            Console.Write(commands.ToString());
            List<InputRecord> records = new List<InputRecord>();
            List<int> characterIndices = new List<int>();
            StringBuilder text = new StringBuilder();
            Dictionary<string,string> result = new Dictionary<string,string>();
            Stopwatch timer = Stopwatch.StartNew();
            try {
                while (timer.ElapsedMilliseconds < 600) {
                    if (result.Count == Keys.Length && GetNumberOfConsoleInputEvents(state.Input,out pending) && pending == 0) { break; }
                    if (WaitForSingleObject(state.Input,20) != 0) { continue; }
                    InputRecord[] item = new InputRecord[1]; uint read;
                    if (!ReadConsoleInputW(state.Input,item,1,out read) || read != 1) { break; }
                    int index = -1;
                    if (item[0].Kind == 1 && item[0].Character != '\0') {
                        if (item[0].Down != 0) { index = text.Length; text.Append(item[0].Character); }
                        else if (text.Length != 0 && text[text.Length-1] == item[0].Character) { index = text.Length-1; }
                    }
                    records.Add(item[0]); characterIndices.Add(index);
                    foreach (Match match in Reply.Matches(text.ToString())) {
                        string key = match.Groups["key"].Value;
                        if (Array.IndexOf(Keys,key) >= 0) { result[key] = match.Groups["rgb"].Value; }
                    }
                }
            } finally {
                bool[] used = new bool[text.Length];
                foreach (Match match in Reply.Matches(text.ToString())) {
                    for (int n=match.Index; n<match.Index+match.Length; n++) { used[n] = true; }
                }
                List<InputRecord> replay = new List<InputRecord>();
                for (int n=0; n<records.Count; n++) {
                    int index = characterIndices[n];
                    if (index < 0 || !used[index]) { replay.Add(records[n]); }
                }
                if (replay.Count != 0) {
                    uint written;
                    if (!WriteConsoleInputW(state.Input,replay.ToArray(),(uint)replay.Count,out written) || written != replay.Count) {
                        Console.Error.WriteLine("[Jobs] Could not replay terminal input; color protection is unavailable.");
                        result.Clear();
                    }
                }
            }
            return result.Count == Keys.Length ? result : null;
        }
        static void Plain(State state) {
            foreach (string key in new string[] { "NO_COLOR", "PLAIN_OUTPUT", "FORCE_COLOR", "CLICOLOR", "ANSI_COLORS_DISABLED" }) {
                state.EnvironmentBefore[key] = Environment.GetEnvironmentVariable(key);
                Environment.SetEnvironmentVariable(key, key == "FORCE_COLOR" || key == "CLICOLOR" ? "0" : "1");
            }
            state.Fallback = true;
        }
        public static void Enter(State state) {
            try {
                state.Input = GetStdHandle(-10); state.Output = GetStdHandle(-11);
                uint inputMode;
                if (!GetConsoleMode(state.Input,out inputMode) || !GetConsoleMode(state.Output,out state.OutputMode)) { Plain(state); return; }
                IntPtr window = GetConsoleWindow();
                if (window == IntPtr.Zero) { Plain(state); return; }
                string identity = window.ToInt64().ToString("x");
                state.PreviousOwner = Environment.GetEnvironmentVariable(OwnerName);
                if (!String.IsNullOrEmpty(state.PreviousOwner)) {
                    string[] owner = state.PreviousOwner.Split(':');
                    int pid; long started;
                    if (owner.Length == 3 && owner[0] == identity && Int32.TryParse(owner[1],out pid) && Int64.TryParse(owner[2],out started)) {
                        try { if (Process.GetProcessById(pid).StartTime.ToUniversalTime().Ticks == started) { return; } } catch {}
                    }
                }
                state.Foreground = Console.ForegroundColor; state.Background = Console.BackgroundColor;
                if ((state.OutputMode & 4) == 0) {
                    if (!SetConsoleMode(state.Output,state.OutputMode | 4)) { Plain(state); return; }
                    state.ModeChanged = true;
                }
                state.Original = Query(state);
                if (state.Original == null) { Restore(state); Plain(state); return; }
                state.Applied = new Dictionary<string,string>();
                state.Applied["10"] = "rgb:ff/ff/ff"; state.Applied["11"] = "rgb:00/00/00";
                for (int n=0; n<16; n++) { state.Applied["4;"+n] = Rgb(Hex[n]); }
                StringBuilder restore = new StringBuilder();
                foreach (string key in Keys) { restore.Append(Escape(key,state.Original[key])); }
                string encoded = Convert.ToBase64String(Encoding.UTF8.GetBytes(restore.ToString()));
                state.Recovery = Path.Combine(Path.GetTempPath(),"JobsTerminalStyle-"+Process.GetCurrentProcess().Id+"-"+Guid.NewGuid().ToString("N")+".ps1");
                string manual = "# Restore only the session colors saved by this Jobs script.\r\n"+
                    "if ([Console]::IsOutputRedirected) { throw 'Run in the original console.' }\r\n"+
                    "Add-Type -Namespace Jobs -Name RecoveryConsole -MemberDefinition '[System.Runtime.InteropServices.DllImport(\"kernel32.dll\")] public static extern System.IntPtr GetStdHandle(int n); [System.Runtime.InteropServices.DllImport(\"kernel32.dll\")] public static extern bool GetConsoleMode(System.IntPtr h, out uint m); [System.Runtime.InteropServices.DllImport(\"kernel32.dll\")] public static extern bool SetConsoleMode(System.IntPtr h, uint m);'\r\n"+
                    "$h = [Jobs.RecoveryConsole]::GetStdHandle(-11); [uint32]$m = 0\r\n"+
                    "if (-not [Jobs.RecoveryConsole]::GetConsoleMode($h, [ref]$m)) { throw 'Run in the original console.' }\r\n"+
                    "try {\r\nif (-not [Jobs.RecoveryConsole]::SetConsoleMode($h, ($m -bor 4))) { throw 'Cannot enable terminal recovery.' }\r\n"+
                    "[Console]::Write([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('"+encoded+"')))\r\n"+
                    "[Console]::ForegroundColor = [ConsoleColor]"+((int)state.Foreground)+"\r\n"+
                    "[Console]::BackgroundColor = [ConsoleColor]"+((int)state.Background)+"\r\n"+
                    "[Console]::Write([string][char]27 + '[39;49m')\r\n"+
                    "} finally { [void][Jobs.RecoveryConsole]::SetConsoleMode($h, $m) }\r\n";
                File.WriteAllText(state.Recovery,manual,new UTF8Encoding(false));
                state.Owner = identity+":"+Process.GetCurrentProcess().Id+":"+Process.GetCurrentProcess().StartTime.ToUniversalTime().Ticks;
                Environment.SetEnvironmentVariable(OwnerName,state.Owner);
                state.Active = true;
                foreach (string key in Keys) { Console.Write(Escape(key,state.Applied[key])); }
                Console.ForegroundColor = ConsoleColor.White; Console.BackgroundColor = ConsoleColor.Black;
                Dictionary<string,string> check = Query(state);
                foreach (string key in Keys) {
                    if (check == null || Normal(check[key]) != Normal(state.Applied[key])) { Restore(state); Plain(state); return; }
                }
            } catch (Exception error) {
                Restore(state); Plain(state);
                Console.Error.WriteLine("[Jobs] Terminal style unavailable: " + error.Message);
            }
        }
        public static void Restore(State state) {
            if (state == null) { return; }
            try {
                if (state.Active) {
                    Dictionary<string,string> current = Query(state);
                    bool complete = current != null;
                    if (current != null) {
                        bool restoreForeground = Console.ForegroundColor == ConsoleColor.White && Normal(current["10"]) == Normal(state.Applied["10"]) && Normal(current["4;15"]) == Normal(state.Applied["4;15"]);
                        bool restoreBackground = Console.BackgroundColor == ConsoleColor.Black && Normal(current["11"]) == Normal(state.Applied["11"]) && Normal(current["4;0"]) == Normal(state.Applied["4;0"]);
                        foreach (string key in Keys) {
                            if (Normal(current[key]) == Normal(state.Applied[key])) { Console.Write(Escape(key,state.Original[key])); }
                            else if (Normal(current[key]) != Normal(state.Original[key])) {
                                complete = false; Console.Error.WriteLine("[Jobs] Kept a concurrent color change: " + key);
                            }
                        }
                        if (restoreForeground) { Console.ForegroundColor = state.Foreground; Console.Write("\x1b[39m"); }
                        if (restoreBackground) { Console.BackgroundColor = state.Background; Console.Write("\x1b[49m"); }
                    }
                    if (complete) {
                        Dictionary<string,string> check = Query(state);
                        foreach (string key in Keys) { if (check == null || Normal(check[key]) != Normal(state.Original[key])) { complete = false; } }
                    }
                    if (complete) { File.Delete(state.Recovery); }
                    else { Console.Error.WriteLine("[Jobs] Color restore needs review. Manual recovery: powershell -NoProfile -File \""+state.Recovery+"\""); }
                }
            } catch (Exception error) {
                Console.Error.WriteLine("[Jobs] Color restore failed: "+error.Message+"; recovery: "+state.Recovery);
            } finally {
                if (state.Owner != null && Environment.GetEnvironmentVariable(OwnerName) == state.Owner) { Environment.SetEnvironmentVariable(OwnerName,state.PreviousOwner); }
                state.Active = false;
                uint currentMode;
                if (state.ModeChanged && GetConsoleMode(state.Output,out currentMode) && currentMode == (state.OutputMode | 4)) { SetConsoleMode(state.Output,state.OutputMode); }
                state.ModeChanged = false;
                if (state.Fallback) {
                    foreach (KeyValuePair<string,string> pair in state.EnvironmentBefore) {
                        string applied = pair.Key == "FORCE_COLOR" || pair.Key == "CLICOLOR" ? "0" : "1";
                        if (Environment.GetEnvironmentVariable(pair.Key) == applied) { Environment.SetEnvironmentVariable(pair.Key,pair.Value); }
                    }
                    state.Fallback = false;
                }
            }
        }
    }
}
'@
        } catch {
            [Console]::Error.WriteLine('[Jobs] Terminal style setup failed; using plain output: ' + $_.Exception.Message)
            return @{ JobsTerminalPlainFallback = $true; Before = @{} }
        }
    }
    return New-Object Jobs.TerminalStyleV1.Native+State
}
# Guard setup is optional; failure keeps business behavior and the user's original terminal settings.
function Start-JobsTerminalStyle {
    param($State)
    if ($State -is [Collections.IDictionary] -and $State.Contains('JobsTerminalPlainFallback')) {
        foreach ($key in @('NO_COLOR', 'PLAIN_OUTPUT', 'FORCE_COLOR', 'CLICOLOR', 'ANSI_COLORS_DISABLED')) {
            $State.Before[$key] = [Environment]::GetEnvironmentVariable($key)
            [Environment]::SetEnvironmentVariable($key, $(if (@('FORCE_COLOR', 'CLICOLOR') -contains $key) { '0' } else { '1' }))
        }
        return
    }
    if ($null -ne $State) { [Jobs.TerminalStyleV1.Native]::Enter($State) }
}
# A finally block also runs for script exit and Ctrl+C; direct .NET calls avoid stopped pipelines.
function Stop-JobsTerminalStyle {
    param($State)
    if ($State -is [Collections.IDictionary] -and $State.Contains('JobsTerminalPlainFallback')) {
        foreach ($key in $State.Before.Keys) {
            $applied = if (@('FORCE_COLOR', 'CLICOLOR') -contains $key) { '0' } else { '1' }
            if ([Environment]::GetEnvironmentVariable($key) -ceq $applied) { [Environment]::SetEnvironmentVariable($key, $State.Before[$key]) }
        }
        return
    }
    if ($null -ne $State) { [Jobs.TerminalStyleV1.Native]::Restore($State) }
}
# END JOBS_TERMINAL_STYLE_V1

$__jobsTerminalStyleState = $null
$__jobsTerminalExitCode = 0
try {
    $__jobsTerminalStyleState = New-JobsTerminalStyleState
    Start-JobsTerminalStyle $__jobsTerminalStyleState
    if ($null -eq $__jobsTerminalCommand -or $__jobsTerminalCommand.Count -eq 0) { throw 'A program is required.' }
    $__jobsTerminalProgram = $__jobsTerminalCommand[0]
    $__jobsTerminalArguments = @()
    if ($__jobsTerminalCommand.Count -gt 1) { $__jobsTerminalArguments = @($__jobsTerminalCommand[1..($__jobsTerminalCommand.Count-1)]) }
    $LASTEXITCODE = 0
    & $__jobsTerminalProgram @__jobsTerminalArguments
    $__jobsTerminalCommandSucceeded = $?
    $__jobsTerminalExitCode = $LASTEXITCODE
    if (-not $__jobsTerminalCommandSucceeded -and $__jobsTerminalExitCode -eq 0) { $__jobsTerminalExitCode = 1 }
} finally {
    Stop-JobsTerminalStyle $__jobsTerminalStyleState
}
exit $__jobsTerminalExitCode
"""
    _interrupted = False
    # 等监督进程完成恢复后再退出，避免 Ctrl+C 提前关闭控制终端。
    def _wait(_arguments):
        nonlocal _interrupted
        _process = _subprocess.Popen(_arguments, env=_environment)
        while True:
            try:
                return _process.wait()
            except KeyboardInterrupt:
                _interrupted = True
                continue
    try:
        if _os.name == "nt":
            _powershell = _shutil.which("powershell.exe") or _shutil.which("pwsh.exe")
            if not _powershell:
                _os.environ.update(NO_COLOR="1", PLAIN_OUTPUT="1", FORCE_COLOR="0", CLICOLOR="0")
                return
            with _tempfile.TemporaryDirectory(prefix="jobs-terminal-style-") as _directory:
                _wrapper = _os.path.join(_directory, "guard.ps1")
                with open(_wrapper, "w", encoding="utf-8-sig", newline="\n") as _file:
                    _file.write(_powershell_core)
                # 原参数经 JSON 交给原生 Python 数组，避开旧 Windows PowerShell 的参数重解析。
                _environment["JOBS_TERMINAL_STYLE_PYTHON_COMMAND"] = _json.dumps(_command, ensure_ascii=False)
                _receipt = _os.path.join(_directory, "started")
                _environment["JOBS_TERMINAL_STYLE_PYTHON_RECEIPT"] = _receipt
                _bridge_source = """import json, os, subprocess, sys
command = json.loads(os.environ.pop('JOBS_TERMINAL_STYLE_PYTHON_COMMAND'))
with open(os.environ.pop('JOBS_TERMINAL_STYLE_PYTHON_RECEIPT'), 'wb') as receipt:
    receipt.write(b'started')
process = subprocess.Popen(command)
while True:
    try:
        result = process.wait()
        break
    except KeyboardInterrupt:
        continue
sys.exit(result if result >= 0 else 128 - result)
"""
                _bridge = "exec(__import__('base64').b64decode('" + _base64.b64encode(_bridge_source.encode()).decode() + "'))"
                _result = _wait([_powershell, "-NoProfile", "-ExecutionPolicy", "Bypass",
                                 "-File", _wrapper, _sys.executable, "-c", _bridge])
                if not _os.path.exists(_receipt) and not _interrupted and _result not in (129, 130, 143, -1073741510, 0xC000013A):
                    _os.environ.update(NO_COLOR="1", PLAIN_OUTPUT="1", FORCE_COLOR="0", CLICOLOR="0")
                    print("终端配色保护未能启动，保持原配色并使用纯文本。", file=_sys.stderr)
                    return
        else:
            _result = _wait(["/bin/sh", "-c", _shell_core + '\njobs_terminal_style_run "$@"\n',
                             "jobs-terminal-style", *_command])
    except KeyboardInterrupt:
        raise SystemExit(130) from None
    except OSError:
        _os.environ.update(NO_COLOR="1", PLAIN_OUTPUT="1", FORCE_COLOR="0", CLICOLOR="0")
        print("终端配色保护未能启动，保持原配色并使用纯文本。", file=_sys.stderr)
        return
    if _result in (-1073741510, 0xC000013A):
        raise SystemExit(130)
    raise SystemExit(_result if _result >= 0 else 128 - _result)


if __name__ == "__main__":
    _jobs_terminal_style_bootstrap_v1()
# JOBS_TERMINAL_STYLE_GUARD_V1_END

import pathlib,subprocess,tempfile
import runpy
_layout = runpy.run_path(str(pathlib.Path(__file__).resolve().parents[3] / "Tests/SourceLayoutHelper.py/SourceLayoutHelper.py"))
source_script = _layout["source_script"]
shell_library = _layout["shell_library"]

root=pathlib.Path(__file__).resolve().parents[2]
shared=root/'JobsFlutterToolsShared'
sources=[(shared/'FlutterFeatureConfiguration/FlutterFeatureConfiguration.swift').read_text(),(shared/'FlutterToolsRequest/FlutterToolsRequest.swift').read_text(),(shared/'FlutterProjectValidator/FlutterProjectValidator.swift').read_text(),(root/'JobsFlutterTools/FlutterToolsLauncher/FlutterToolsLauncher.swift').read_text()]
menu=(root/'JobsFlutterToolsFinderSync/FinderSync.swift').read_text().replace('import FinderSync','').replace('NSWorkspace.shared.open(requestURL)','TestWorkspace.open(requestURL)').replace('let alert = NSAlert()', 'let alert = TestAlert()')
menu = menu.replace('var directories = FileManager.default.urls', 'var directories = [URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("Desktop")] + FileManager.default.urls')
stub='''import AppKit
import Foundation
import Darwin
enum FIMenuKind: UInt { case contextualMenuForItems, contextualMenuForContainer, contextualMenuForSidebar, toolbarItemMenu }
class FIFinderSync: NSObject { func menu(for kind: FIMenuKind) -> NSMenu? { nil } }
final class FIFinderSyncController {
 static let shared = FIFinderSyncController()
 static func `default`() -> FIFinderSyncController { shared }
 var directoryURLs: Set<URL> = []
 var selected: [URL]?; var targeted: URL?
 func selectedItemURLs() -> [URL]? { selected }
 func targetedURL() -> URL? { targeted }
}
enum TestWorkspace {
 static var requests: [URL] = []
 static var failures = 0
 static var failureMessages: [String] = []
 static func open(_ url: URL) -> Bool { requests.append(url); return true }
}
final class TestAlert {
 var alertStyle: NSAlert.Style = .warning
 var messageText = ""
 var informativeText = ""
 func addButton(withTitle title: String) {}
 func runModal() { TestWorkspace.failures += 1; TestWorkspace.failureMessages.append(informativeText) }
}
'''
# Override only the compiled fixture, so no real user configuration is read or changed.
config_call='FlutterFeatureConfiguration.enabledFeatures(configurationURL: URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("features.conf"))'
sources=[source.replace('FlutterFeatureConfiguration.enabledFeatures()',config_call) for source in sources]
menu=menu.replace('FlutterFeatureConfiguration.enabledFeatures()',config_call)
checks=r'''
var assertions = 0
func expect(_ condition: @autoclosure () -> Bool, _ message: String) { assertions += 1; if !condition() { fatalError(message) } }
let base = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let project = base.appendingPathComponent("工程 ' $(touch NEVER) ; space")
try FileManager.default.createDirectory(at: project.appendingPathComponent("lib"), withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: project.appendingPathComponent("ohos"), withIntermediateDirectories: true)
for name in ["build-profile.json5", "oh-package.json5"] {
 try "{}".write(to: project.appendingPathComponent("ohos").appendingPathComponent(name), atomically: true, encoding: .utf8)
}
try "name: fixture\ndependencies:\n  flutter:\n    sdk: flutter\n".write(to: project.appendingPathComponent("pubspec.yaml"), atomically: true, encoding: .utf8)
let controller = FIFinderSyncController.default()
let ordinary = base.appendingPathComponent("ordinary", isDirectory: true)
try FileManager.default.createDirectory(at: ordinary, withIntermediateDirectories: true)
let singleFile = project.appendingPathComponent("lib/main.dart")
try "void main() {}\n".write(to: singleFile, atomically: true, encoding: .utf8)
let projectLink = base.appendingPathComponent("project-link", isDirectory: true)
try FileManager.default.createSymbolicLink(at: projectLink, withDestinationURL: project)
controller.selected = [project]
let provider = FinderSync()
func setContext(_ url: URL?, for kind: FIMenuKind) {
 controller.selected = kind == .contextualMenuForItems ? url.map { [$0] } : [ordinary, base]
 controller.targeted = kind != .contextualMenuForItems ? url : nil
}
func leafItems(_ menu: NSMenu) -> [NSMenuItem] {
 menu.items.flatMap { item in item.submenu.map(leafItems) ?? [item] }
}
expect(FlutterToolsAction.dependencyFetch.map(\.rawValue) == ["pub-get", "android-dependencies", "pods-dependencies", "spm-dependencies", "ohos-dependencies", "web-dependencies"], "network fetch excludes native combo and platform resources")
expect(FlutterToolsAction.dependencyExports.map(\.rawValue) == ["export-all-dependencies", "extract", "export-private-dependencies", "export-gradle-dependencies", "export-pods-dependencies", "export-spm-dependencies", "export-ohos-dependencies", "export-native-dependencies", "export-precache-dependencies", "export-web-dependencies"], "export group preserves every raw action")
expect(FlutterToolsAction.dependencyImports.map(\.rawValue) == ["import-all-dependencies", "import-dependencies", "import-private-dependencies", "import-gradle-dependencies", "import-pods-dependencies", "import-spm-dependencies", "import-ohos-dependencies", "import-native-dependencies", "import-precache-dependencies", "import-web-dependencies"], "import group preserves every raw action")
expect(FlutterToolsAction.environments.map(\.rawValue) == ["sdk-manage", "ohos-sdk-manage", "java-manage"], "runtime environment children")
expect(FlutterToolsAction.resources.map(\.rawValue) == ["gradle-download", "flutter-precache", "native-dependencies"], "resource and build dependency children")
expect(FlutterToolsAction.doctors.map(\.rawValue) == ["sdk-version", "native-doctor", "harmony-doctor"], "SDK inspection belongs to project inspection")
let actions: [FlutterToolsAction] = [.projectSetup,.run] + FlutterToolsAction.dependencyFetch + FlutterToolsAction.dependencyExports + FlutterToolsAction.dependencyImports + FlutterToolsAction.environments + FlutterToolsAction.resources + FlutterToolsAction.packaging + [.codegen] + FlutterToolsAction.doctors + FlutterToolsAction.repairs + FlutterToolsAction.cleaning
expect(actions.count == 47 && Set(actions) == FlutterFeatureConfiguration.leafActions, "regrouping covers the same 47 unique leaves")
for kind in [FIMenuKind.contextualMenuForItems, .contextualMenuForContainer, .contextualMenuForSidebar] {
 controller.selected = kind == .contextualMenuForItems ? [project] : [ordinary, base]
 controller.targeted = kind != .contextualMenuForItems ? project : nil
 let menu = provider.menu(for: kind)!
 expect(menu.items.map(\.title) == ["🦋 Flutter开发相关辅助工具"], "one root menu")
 let development = menu.items[0].submenu!
 expect(development.items.map(\.title) == ["🚀 一键配置 Flutter 项目","▶️ 从终端运行 Flutter 项目","📥 拉取Flutter项目工程相关依赖","🧩 提取Flutter项目工程依赖","📤 导入Flutter项目工程依赖","🔀 安装/切换Flutter运行环境","🧱 Flutter 资源与构建依赖","📦 Flutter打包","⚙️ Flutter自动化生产代码","🏥 Flutter项目体检","🔧 Flutter项目修复","🧹 Flutter清理维护工具"], "development direct groups follow the requested wording and order")
 expect(development.items[2].submenu!.items.map(\.title) == ["📥 拉取 Flutter Pub 依赖","🤖 拉取 Android 原生依赖","🥥 拉取 CocoaPods 依赖","🧬 拉取 Swift Package 依赖","🕊️ 拉取 OpenHarmony 依赖","🌐 拉取 Web 工程依赖"], "network fetch group has only network package operations")
 expect(development.items[3].submenu!.items.map(\.title) == FlutterToolsAction.dependencyExports.map(\.title), "extract group contains Pub and every export action")
 expect(development.items[4].submenu!.items.map(\.title) == FlutterToolsAction.dependencyImports.map(\.title), "import group contains Pub and every import action")
 expect(development.items[5].submenu!.items.map(\.title) == ["🔀 安装/切换Flutter SDK","🕊️ 安装/切换Flutter@OpenHarmony SDK","☕ 安装/切换Java SDK"], "environment names match the request")
 expect(development.items[6].submenu!.items.map(\.title) == ["📚 下载Gradled分发与构建插件","🗃️ 下载Flutter平台资源","🧱 准备原生库与构建依赖（组合操作）"], "resources include the native build preparation combo")
 expect(development.items[7].submenu!.items.map(\.title) == ["🍏 iOS", "🤖 Android", "📦 打包鸿蒙（HAP + APP）"], "packaging platforms")
 expect(development.items[9].submenu!.items.map(\.title) == ["🔎 查看当前Flutter项目工程的SDK版本","🧑‍⚕️ 原生Flutter项目体检", "💓 OpenHarmony Flutter 环境体检"], "SDK version is nested in inspection")
 expect(development.items[10].submenu!.items.map(\.title) == ["🩹 修复 Android SDK / platforms 缺失","🈶 修复 Flutter 项目中文路径","🏷️ 修复 Flutter 插件 namespace","🔤 修复 Dart 相对 import 为 package 引用"], "nested repairs")
 expect(development.items[11].submenu!.items.map(\.title) == ["🗑️ 清理当前 Flutter 项目构建产物", "♻️ 依赖与缓存维护"], "nested cleaning")
 for index in [2,3,4,5,6,7,9,10,11] {
  expect(development.items[index].submenu != nil && !(development.items[index].target is FinderSync), "group parent expands its submenu without a Finder business target")
 }
 func checkEmoji(_ menu: NSMenu) {
  for item in menu.items {
   let first = item.title.unicodeScalars.first!
   expect(first.properties.isEmoji, "every custom menu caption starts with emoji")
   if let submenu = item.submenu { checkEmoji(submenu) }
  }
 }
 checkEmoji(menu)
 let leaves = leafItems(menu)
 expect(leaves.count == actions.count, "all actions remain available")
 for (index,item) in leaves.enumerated() {
  _ = (item.target as! NSObject).perform(item.action!, with: item)
  let request = TestWorkspace.requests.last!
  expect(FlutterToolsRequest.action(from: request) == actions[index], "action transport")
  expect(FlutterToolsRequest.projectURL(from: request)?.path == project.path, "path transport")
 }
 for guardedItem in [development.items[4].submenu!.items[0], development.items[10].submenu!.items.last!] {
  let requestCount = TestWorkspace.requests.count
  let failureCount = TestWorkspace.failures
  setContext(ordinary, for: kind)
  _ = (guardedItem.target as! NSObject).perform(guardedItem.action!, with: guardedItem)
  expect(TestWorkspace.requests.count == requestCount, "changed non-Flutter context must not dispatch \(guardedItem.title)")
  expect(TestWorkspace.failures == failureCount + 1, "changed context reports failure")
  setContext(project, for: kind)
  try "name: fixture\ndependencies: {}\n".write(to: project.appendingPathComponent("pubspec.yaml"), atomically: true, encoding: .utf8)
  _ = (guardedItem.target as! NSObject).perform(guardedItem.action!, with: guardedItem)
  expect(TestWorkspace.requests.count == requestCount, "project losing Flutter declaration must not dispatch \(guardedItem.title)")
  expect(TestWorkspace.failures == failureCount + 2, "changed manifest reports failure")
  try "name: fixture\ndependencies:\n  flutter:\n    sdk: flutter\n".write(to: project.appendingPathComponent("pubspec.yaml"), atomically: true, encoding: .utf8)
 }
}
for kind in [FIMenuKind.contextualMenuForItems, .contextualMenuForContainer, .contextualMenuForSidebar] {
 for (url, reason) in [(ordinary, "ordinary directory"), (project.appendingPathComponent("lib"), "lib child directory"), (projectLink, "symbolic link")] {
  setContext(url, for: kind)
  expect(provider.menu(for: kind) == nil, "hide all Flutter actions for \(reason)")
 }
}
// 单 Dart 菜单只保留运行，并把实际文件运输到宿主和终端载体。
controller.selected = [singleFile]
controller.targeted = project
let demoMenu = provider.menu(for: .contextualMenuForItems)!
let demoItems = leafItems(demoMenu)
expect(demoItems.count == 1 && demoItems[0].title == FlutterProjectValidator.demoMenuTitle(), "Dart only exposes localized run")
expect(demoMenu.items.count == 1 && demoMenu.items[0] === demoItems[0] && demoMenu.items[0].submenu == nil, "Dart run is a direct Finder action without a redundant Flutter group")
_ = (demoItems[0].target as! NSObject).perform(demoItems[0].action!, with: demoItems[0])
expect(FlutterToolsRequest.action(from: TestWorkspace.requests.last!) == .run, "Demo dispatch remains run action")
expect(FlutterToolsRequest.projectURL(from: TestWorkspace.requests.last!)?.path == singleFile.path, "Demo URL preserves target file")
let dartLink = project.appendingPathComponent("lib/shortcut.dart")
try FileManager.default.createSymbolicLink(at: dartLink, withDestinationURL: singleFile)
controller.selected = [dartLink]
expect(provider.menu(for: .contextualMenuForItems) == nil, "linked Dart is rejected")
let nested = project.appendingPathComponent("nested")
try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
try "dependencies: {}".write(to: nested.appendingPathComponent("pubspec.yaml"), atomically: true, encoding: .utf8)
let nestedDart = nested.appendingPathComponent("main.dart")
try "void main() {}".write(to: nestedDart, atomically: true, encoding: .utf8)
controller.selected = [nestedDart]
expect(provider.menu(for: .contextualMenuForItems) == nil, "nearest non-Flutter package stops ancestor lookup")
for language in ["zh-Hans", "zh-Hant", "bo", "en", "ja", "fr", "es", "de", "ru", "ko"] {
 expect(FlutterProjectValidator.demoMenuTitle(language: language).hasPrefix("▶️ "), "all ten Demo languages have titles")
}
controller.selected = [project,base]
expect(provider.menu(for: .contextualMenuForItems) == nil, "multiple selection")
controller.selected = nil
controller.targeted=URL(fileURLWithPath:String(cString:getpwuid(getuid())!.pointee.pw_dir)).appendingPathComponent("Desktop")
expect(provider.menu(for: .contextualMenuForContainer) == nil,"desktop excluded")
controller.targeted = project
let sidebarItems = leafItems(provider.menu(for: .contextualMenuForSidebar)!)
controller.selected = [project]
_ = provider.menu(for: .contextualMenuForItems)
controller.selected = [ordinary, base]
for original in sidebarItems {
 let item = original.copy() as! NSMenuItem
 _ = (item.target as! NSObject).perform(item.action!, with: item)
 expect(FlutterToolsRequest.projectURL(from: TestWorkspace.requests.last!)?.path == project.path, "copied sidebar action survives interleaved item menu")
}
var remoteSidebar = URLComponents(url: project, resolvingAgainstBaseURL: false)!
remoteSidebar.host = "remote-host"
for target in [nil, URL(string: "x-apple-finder:Recents"), URL(string: "https://example.com"), remoteSidebar.url,
               base.appendingPathComponent("missing"), singleFile] as [URL?] {
 controller.targeted = target
 expect(provider.menu(for: .contextualMenuForSidebar) == nil, "invalid sidebar target never borrows selected project")
 let oldCount = TestWorkspace.requests.count
 let item = sidebarItems[0]
 _ = (item.target as! NSObject).perform(item.action!, with: item)
 expect(TestWorkspace.requests.count == oldCount, "invalidated sidebar item does not dispatch")
}
let desktop = base.appendingPathComponent("Desktop")
try FileManager.default.createDirectory(at: desktop.appendingPathComponent("lib"), withIntermediateDirectories: true)
try "dependencies:\n  flutter:\n    sdk: flutter\n".write(to: desktop.appendingPathComponent("pubspec.yaml"), atomically: true, encoding: .utf8)
controller.targeted = desktop
expect(provider.menu(for: .contextualMenuForContainer) == nil, "Desktop background remains excluded")
let desktopRun = leafItems(provider.menu(for: .contextualMenuForSidebar)!).first { $0.title == FlutterToolsAction.run.title }!
_ = (desktopRun.target as! NSObject).perform(desktopRun.action!, with: desktopRun)
expect(FlutterToolsRequest.projectURL(from: TestWorkspace.requests.last!)?.path == desktop.path, "Desktop sidebar action keeps sidebar context")
expect(FlutterToolsRequest.action(from:URL(string:"jobsfluttertools://import-dependencies?path=/project")!) == .importDependencies,"dependency import URL")
expect(FlutterToolsRequest.action(from:URL(string:"jobsfluttertools://maintenance?path=/legacy")!) == .maintenance,"legacy maintenance URL stays valid")
expect(FlutterToolsRequest.action(from:URL(string:"jobsfluttertools://repair-package-imports?path=/project")!) == .repairPackageImports,"package import repair URL")
for value in ["jobsfluttertools://unknown?path=/a","jobsfluttertools://package-macos?path=/a","jobsfluttertools://run?path=/a&path=/b","jobsfluttertools://run?path=relative","jobsfluttertools://run?path=/a%00b","jobsfluttertools://user@run?path=/a","jobsfluttertools://run:12?path=/a","jobsfluttertools://run/extra?path=/a","jobsfluttertools://run?path=/a#fragment"] {
 expect(FlutterToolsRequest.action(from:URL(string:value)!) == nil,"reject ambiguous request")
}
let tools=base.appendingPathComponent("stub-tools")
try FileManager.default.createDirectory(at:tools,withIntermediateDirectories:true)
try "#!/bin/zsh\n/usr/bin/printf '%s\\0' \"$@\" > \"$JOBS_TEST_ARGS\"\nexit 19\n".write(to:tools.appendingPathComponent("DispatchFlutterTools.zsh"),atomically:true,encoding:.utf8)
for action in [FlutterToolsAction.projectSetup, .gradleDownload, .importDependencies, .repairNamespace, .repairPackageImports, .cleanBuildArtifacts, .maintenance, .harmonySdkManage, .javaManage] + FlutterToolsAction.dependencyPreparation + FlutterToolsAction.dependencyArchives + FlutterToolsAction.packaging {
let request=try FlutterToolsLauncher().prepare(projectURL:project,action:action,toolsURL:tools)
let attributes=try FileManager.default.attributesOfItem(atPath:request.directoryURL.path)
expect((attributes[.posixPermissions] as! NSNumber).intValue == 0o700,"private carrier")
let argsFile=base.appendingPathComponent("args")
let process=Process();process.executableURL=URL(fileURLWithPath:"/bin/zsh");process.arguments=["-f","-c",request.commandLine.replacingOccurrences(of:"/bin/zsh -l ",with:"/bin/zsh -f ")];process.environment=ProcessInfo.processInfo.environment.merging(["JOBS_TEST_ARGS":argsFile.path]){_,new in new}
try process.run();process.waitUntilExit()
expect(process.terminationStatus == 19,"preserve worker error")
let args=String(decoding:try Data(contentsOf:argsFile),as:UTF8.self).split(separator:"\0").map(String.init)
expect(args == [action.rawValue,project.path],"shell metacharacters remain data")
expect(!FileManager.default.fileExists(atPath:request.directoryURL.path),"private carrier cleanup")
expect(!FileManager.default.fileExists(atPath:base.appendingPathComponent("NEVER").path),"no command substitution")
}
let demoRequest = try FlutterToolsLauncher().prepare(projectURL: singleFile, action: .run, toolsURL: tools)
let demoArgs = base.appendingPathComponent("demo-args")
let demoProcess = Process()
demoProcess.executableURL = URL(fileURLWithPath: "/bin/zsh")
demoProcess.arguments = ["-f", "-c", demoRequest.commandLine.replacingOccurrences(of: "/bin/zsh -l ", with: "/bin/zsh -f ")]
demoProcess.environment = ProcessInfo.processInfo.environment.merging(["JOBS_TEST_ARGS": demoArgs.path]) { _, new in new }
try demoProcess.run()
demoProcess.waitUntilExit()
expect(demoProcess.terminationStatus == 19, "Demo carrier keeps worker failure")
let demoTransport = String(decoding: try Data(contentsOf: demoArgs), as: UTF8.self).split(separator: "\0").map(String.init)
expect(demoTransport == ["run", singleFile.path], "Demo carrier keeps actual source target: \(demoTransport) expected \(singleFile.path)")
do {
 _ = try FlutterToolsLauncher().prepare(projectURL: singleFile, action: .maintenance, toolsURL: tools)
 fatalError("file accepted for maintenance")
} catch { expect(true, "files cannot enter project maintenance") }
let harmonyValidator = FlutterProjectValidator()
expect(harmonyValidator.isHarmonyFlutterProject(at: project), "recognize adapted Harmony Flutter root")
func expectUnadaptedHarmonyAction() {
 for kind in [FIMenuKind.contextualMenuForItems, .contextualMenuForContainer, .contextualMenuForSidebar] {
  setContext(project, for: kind)
  let harmony = leafItems(provider.menu(for: kind)!).first { $0.title == FlutterToolsAction.packageHarmony.title }
  expect(harmony != nil, "unadapted Flutter project keeps configured Harmony packaging visible")
  let oldCount = TestWorkspace.requests.count
  let oldFailures = TestWorkspace.failures
  _ = (harmony!.target as! NSObject).perform(harmony!.action!, with: harmony!)
  expect(TestWorkspace.requests.count == oldCount, "unadapted Harmony click does not dispatch to host")
  expect(TestWorkspace.failures == oldFailures + 1, "unadapted Harmony click shows a warning")
  let message = TestWorkspace.failureMessages.last ?? ""
  expect(message.contains("ohos/build-profile.json5") && message.contains("ohos/oh-package.json5") && message.contains("请先完成鸿蒙适配"), "warning explains the missing Harmony adaptation")
 }
}
for name in ["build-profile.json5", "oh-package.json5"] {
 let manifest = project.appendingPathComponent("ohos").appendingPathComponent(name)
 let saved = try Data(contentsOf: manifest)
 setContext(project, for: .contextualMenuForItems)
 let stale = leafItems(provider.menu(for: .contextualMenuForItems)!).first { $0.title == FlutterToolsAction.packageHarmony.title }!
 try FileManager.default.removeItem(at: manifest)
 expect(!harmonyValidator.isHarmonyFlutterProject(at: project), "missing Harmony manifest rejects package")
 expectUnadaptedHarmonyAction()
 setContext(project, for: .contextualMenuForItems)
 let oldCount = TestWorkspace.requests.count
 _ = (stale.target as! NSObject).perform(stale.action!, with: stale)
 expect(TestWorkspace.requests.count == oldCount, "stale Harmony action is rejected after manifest removal")
 do {
  let request = try FlutterToolsLauncher().prepare(projectURL: project, action: .packageHarmony, toolsURL: tools)
  try FileManager.default.removeItem(at: request.directoryURL)
  fatalError("host accepted missing Harmony manifest")
 } catch { expect(true, "host rechecks Harmony project") }
 try FileManager.default.createSymbolicLink(at: manifest, withDestinationURL: singleFile)
 expect(!harmonyValidator.isHarmonyFlutterProject(at: project), "symlink Harmony manifest is rejected")
 try FileManager.default.removeItem(at: manifest)
 try saved.write(to: manifest)
}
let ohosDirectory = project.appendingPathComponent("ohos")
let savedOhos = project.appendingPathComponent("ohos-backup")
try FileManager.default.moveItem(at: ohosDirectory, to: savedOhos)
expect(!harmonyValidator.isHarmonyFlutterProject(at: project), "missing ohos directory rejects package")
expectUnadaptedHarmonyAction()
try FileManager.default.createSymbolicLink(at: ohosDirectory, withDestinationURL: savedOhos)
expect(!harmonyValidator.isHarmonyFlutterProject(at: project), "linked ohos directory rejected")
try FileManager.default.removeItem(at: ohosDirectory)
try FileManager.default.moveItem(at: savedOhos, to: ohosDirectory)
let config = base.appendingPathComponent("features.conf")
expect(FlutterFeatureConfiguration.enabledFeatures(configurationURL: config).count == 47, "missing config keeps legacy actions")
setContext(project, for: .contextualMenuForItems)
let staleMenu = provider.menu(for: .contextualMenuForItems)!
let staleRun = leafItems(staleMenu).first!
let staleImport = leafItems(staleMenu).first { $0.title == FlutterToolsAction.importDependencies.title }!
try "package-android,repair-package-imports".write(to: config, atomically: true, encoding: .utf8)
let partial = provider.menu(for: .contextualMenuForItems)!.items[0].submenu!
expect(partial.items.map(\.title) == ["📦 Flutter打包", "🔧 Flutter项目修复"], "empty action groups are hidden")
expect(leafItems(partial).map(\.title) == ["🤖 Android", "🔤 修复 Dart 相对 import 为 package 引用"], "selected leaves only")
let previousRequestCount = TestWorkspace.requests.count
_ = (staleRun.target as! NSObject).perform(staleRun.action!, with: staleRun)
expect(TestWorkspace.requests.count == previousRequestCount, "stale menu cannot launch disabled action")
_ = (staleImport.target as! NSObject).perform(staleImport.action!, with: staleImport)
expect(TestWorkspace.requests.count == previousRequestCount, "stale dependency import cannot launch a disabled action")
for action in [FlutterToolsAction.projectSetup, .gradleDownload, .run, .importDependencies, .package, .packageIOS, .packageHarmony] {
 do {
  let request = try FlutterToolsLauncher().prepare(projectURL: project, action: action, toolsURL: tools)
  try FileManager.default.removeItem(at: request.directoryURL)
  fatalError("disabled host action accepted")
 } catch {
  expect(true, "host rejects disabled or aggregate platform action")
 }
}
let groupExpectations: [(String, [FlutterToolsAction])] = [
 ("📥 拉取Flutter项目工程相关依赖", FlutterToolsAction.dependencyFetch),
 ("🧩 提取Flutter项目工程依赖", FlutterToolsAction.dependencyExports),
 ("📤 导入Flutter项目工程依赖", FlutterToolsAction.dependencyImports),
 ("🔀 安装/切换Flutter运行环境", FlutterToolsAction.environments),
 ("🧱 Flutter 资源与构建依赖", FlutterToolsAction.resources),
 ("📦 Flutter打包", FlutterToolsAction.packaging),
 ("🏥 Flutter项目体检", FlutterToolsAction.doctors),
 ("🔧 Flutter项目修复", FlutterToolsAction.repairs),
 ("🧹 Flutter清理维护工具", FlutterToolsAction.cleaning)
]
for action in actions {
 try action.rawValue.write(to: config, atomically: true, encoding: .utf8)
 let oneMenu = provider.menu(for: .contextualMenuForItems)!
 let one = leafItems(oneMenu)
 expect(one.count == 1 && one[0].title == action.title, "each individual selection survives its parent group")
 expect(oneMenu.items.count == 1 && oneMenu.items[0] === one[0] && oneMenu.items[0].submenu == nil, "one enabled action is a direct leaf, including nested groups")
 expect(one[0].target is FinderSync && one[0].action != nil, "flattened leaf preserves its original business target")
}
try "package-android,repair-package-imports".write(to: config, atomically: true, encoding: .utf8)
let enabledRequest = try FlutterToolsLauncher().prepare(projectURL: project, action: .packageAndroid, toolsURL: tools)
try FileManager.default.removeItem(at: enabledRequest.directoryURL)
expect(FlutterFeatureConfiguration.permits(.package, enabled: Set(FlutterToolsAction.packaging)), "legacy package only when every platform is enabled")
for invalid in ["", "unknown", "run,unknown", "run,run", "run,", "package", "run\u{0000}", String(repeating: "r", count: 8193)] {
 try invalid.write(to: config, atomically: true, encoding: .utf8)
 expect(FlutterFeatureConfiguration.enabledFeatures(configurationURL: config).isEmpty, "empty or invalid configuration disables all actions")
 expect(provider.menu(for: .contextualMenuForItems) == nil, "all disabled hides Flutter root")
}
try Data([0xff, 0xfe]).write(to: config)
expect(FlutterFeatureConfiguration.enabledFeatures(configurationURL: config).isEmpty, "invalid UTF-8 rejected")
try FileManager.default.removeItem(at: config)
let other = base.appendingPathComponent("other-features.conf")
try "run".write(to: other, atomically: true, encoding: .utf8)
try FileManager.default.createSymbolicLink(at: config, withDestinationURL: other)
expect(FlutterFeatureConfiguration.enabledFeatures(configurationURL: config).isEmpty, "symlink configuration rejected")
try FileManager.default.removeItem(at: config)
try FileManager.default.createDirectory(at: config, withIntermediateDirectories: false)
expect(FlutterFeatureConfiguration.enabledFeatures(configurationURL: config).isEmpty, "directory configuration rejected")
let diagnosticURL = FileManager.default.temporaryDirectory.appendingPathComponent("JobsFlutterToolsFinderMenu-\(getpid()).jsonl")
let diagnosticData = try Data(contentsOf: diagnosticURL)
let records = try String(decoding: diagnosticData, as: UTF8.self).split(separator: "\n").map {
 try JSONSerialization.jsonObject(with: Data($0.utf8)) as! [String: Any]
}
expect(records.first?["event"] as? String == "initialized", "diagnostic records extension initialization")
expect(records.contains { $0["reason"] as? String == "returned" && $0["returnedLeafCount"] as? Int == 47 && $0["validator"] as? Bool == true }, "diagnostic confirms valid project and returned leaves")
expect(records.contains { $0["reason"] as? String == "non-flutter" && $0["validator"] as? Bool == false }, "diagnostic identifies validator refusal")
expect(records.contains { $0["reason"] as? String == "no-candidate" }, "diagnostic identifies missing selection")
expect(records.contains { $0["reason"] as? String == "no-enabled-actions" && $0["enabledCount"] as? Int == 0 }, "diagnostic identifies disabled features")
expect(records.allSatisfy { Set($0.keys).isSubset(of: ["event", "observedRoot", "time", "pid", "kind", "candidate", "validator", "enabledCount", "availableCount", "returnedLeafCount", "reason"]) }, "diagnostic contains only local menu metadata")
let diagnosticAttributes = try FileManager.default.attributesOfItem(atPath: diagnosticURL.path)
expect((diagnosticAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o600, "diagnostic is private")
try Data(repeating: 65, count: 131_072).write(to: diagnosticURL)
_ = provider.menu(for: .contextualMenuForItems)
let rotatedDiagnostic = try Data(contentsOf: diagnosticURL)
expect(rotatedDiagnostic.count < 4096, "diagnostic rotates before its bound")
try FileManager.default.removeItem(at: diagnosticURL)
try FileManager.default.createSymbolicLink(at: diagnosticURL, withDestinationURL: other)
_ = provider.menu(for: .contextualMenuForItems)
let symlinkTarget = try String(contentsOf: other, encoding: .utf8)
expect(symlinkTarget == "run", "diagnostic refuses symlink destination")
try FileManager.default.removeItem(at: diagnosticURL)
print("PASS: \(assertions) menu and transport assertions")
'''
with tempfile.TemporaryDirectory(prefix='jobs-flutter-menu-') as temp:
 p=pathlib.Path(temp);(p/'main.swift').write_text(stub+'\n'+'\n'.join(sources)+'\n'+menu+'\n'+checks)
 subprocess.run(['/usr/bin/xcrun','swiftc',str(p/'main.swift'),'-o',str(p/'check')],check=True)
 subprocess.run([str(p/'check'),str(p)],check=True)

# Exercise only the isolated config writer, never the real install/registration entry.
with tempfile.TemporaryDirectory(prefix='jobs-flutter-feature-install-') as temp:
 p=pathlib.Path(temp)
 installer=source_script(root/'Scripts/ManageExtension.zsh').read_text()
 (p/'library.zsh').write_text(shell_library(installer))
 config=p/'Library/Application Support/JobsFinderExtensions/flutter-tools-features.conf'
 config.parent.mkdir(parents=True)
 config.write_text('run')
 result=subprocess.run(['/bin/zsh','-f','-c','source "$1"; LOG_FILE="$2"; manager_persist_flutter_selection','fixture',str(p/'library.zsh'),str(p/'install.log')],env={'HOME':temp,'PATH':'/usr/bin:/bin'},capture_output=True,text=True)
 assert result.returncode == 0,result.stdout+result.stderr
 selected=config.read_text().split(',')
 assert len(selected) == len(set(selected)) == 47,selected
 assert config.stat().st_mode & 0o777 == 0o600
 assert len(list(config.parent.iterdir())) == 1
 print('PASS: isolated independent installer enables all 47 actions atomically')
