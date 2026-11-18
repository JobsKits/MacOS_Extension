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

import json
import os
import pathlib
import subprocess
import tempfile
import unittest

import runpy
_layout = runpy.run_path(str(pathlib.Path(__file__).resolve().parents[3] / "Tests/SourceLayoutHelper.py/SourceLayoutHelper.py"))
source_script = _layout["source_script"]
shell_library = _layout["shell_library"]

ROOT = pathlib.Path(__file__).resolve().parents[3]
FEATURES = ['android_studio_opener', 'vscode_opener', 'xcode_opener', 'git-pull', 'git_remote', 'git_remote_copier', 'git-proxy-configure', 'git_empty_commit_push', 'git-rollback']
APPS = ['JobsAndroidStudioOpener', 'JobsVSCodeOpener', 'JobsXcodeOpener', 'JobsGitPuller', 'JobsGitRemoteOpener', 'JobsGitRemoteCopier']
GROUP_ID = 'com.jobs.JobsProjectTools.FinderSyncExtension'


class InstallerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='project-installer-')
        self.addCleanup(self.temp.cleanup)
        self.base = pathlib.Path(self.temp.name).resolve()
        self.config = self.base / 'config/EnabledFeatures.txt'
        self.state = self.base / 'state.json'
        self.state.write_text(json.dumps({**{f'com.jobs.{app}.FinderSyncExtension': '+' for app in APPS}, 'com.jobs.gitproxyconfigurator.findersync': '+', 'com.jobs.JobsTerminalOpener.FinderSyncExtension': '+', 'com.jobs.JobsGitRollback.FinderSyncExtension': '+'}))
        self.terminal = self.base / 'terminal/EnabledFinderMenuFeatures.txt'
        self.terminal.parent.mkdir()
        self.terminal.write_text('open,pod-install,git-empty-commit-push,unknown')
        self.log = self.base / 'calls.log'
        self.extension = self.base / 'work/DerivedData/Build/Products/Debug/JobsProjectTools.app/Contents/PlugIns/JobsProjectToolsFinderSync.appex'
        self.extension.mkdir(parents=True)
        deployment = self.base / 'Scripts/【MacOS】AppDeployment.zsh/【MacOS】AppDeployment.zsh'
        deployment.parent.mkdir(parents=True)
        # 只测试项目菜单事务；新部署系统边界由专门临时 App 夹具验证。
        deployment.write_text("""
jobs_deployment_app_path() { print -r -- "$1"; }
jobs_deployment_install() { return 0; }
jobs_deployment_retire_other_copies() { return 0; }
jobs_deployment_commit() { return 0; }
jobs_deployment_rollback() { return 0; }
jobs_deployment_has_other_enabled() { return 1; }
jobs_deployment_validate_app() { [[ "$1" == "$PROJECT_ROOT"/* && -d "$1" ]]; }
jobs_deployment_unregister_app() {
  "$PROJECT_ROOT/pluginkit" -r "$1/Contents/PlugIns/$2" || return $?
  "$LSREGISTER" -u "$1"
}
""")
        source = source_script(ROOT / 'JobsProjectTools/Scripts/ManageProjectTools.zsh').read_text()
        source = source.replace('CONFIG_DIR="${HOME}/Library/Application Support/JobsProjectTools"', f'CONFIG_DIR="{self.config.parent}"')
        source = source.replace('TERMINAL_CONFIG_PATH="${HOME}/Library/Application Support/JobsTerminalOpener/EnabledFinderMenuFeatures.txt"', f'TERMINAL_CONFIG_PATH="{self.terminal}"')
        shim = self.base / 'shim.py'
        shim.write_text(f'''#!/usr/bin/env python3
import json,pathlib,sys
base=pathlib.Path({str(self.base)!r})
name=pathlib.Path(sys.argv[0]).name
args=sys.argv[1:]
with (base/'calls.log').open('a') as f: f.write(name+' '+repr(args)+'\\n')
state_path=base/'state.json'
state=json.loads(state_path.read_text())
if name=='xcodebuild' and (base/'fail-build').exists(): sys.exit(9)
if name=='xcodebuild': pathlib.Path({str(self.extension)!r}).mkdir(parents=True,exist_ok=True)
if name=='pluginkit':
 if '-m' in args:
  identifier=args[args.index('-i')+1]
  if identifier in state:
   location={str(self.extension)!r} if identifier=={GROUP_ID!r} else '/old.app/Contents/PlugIns/old.appex'
   print(state[identifier]+' '+identifier+'(1.0) '+location)
 elif '-r' in args:
  state[{GROUP_ID!r}]='-'
  state_path.write_text(json.dumps(state))
 elif '-e' in args:
  if (base/'fail-register').exists(): sys.exit(8)
  state[args[args.index('-i')+1]]='+' if args[args.index('-e')+1]=='use' else '-'
  state_path.write_text(json.dumps(state))
''')
        shim.chmod(0o755)
        for name in ['xcodebuild', 'pluginkit', 'pkill', 'killall', 'lsregister']:
            path = self.base / name
            path.symlink_to(shim)
            if name == 'lsregister':
                start = source.index('LSREGISTER=')
                end = source.index('\n', start)
                source = source[:start] + f'LSREGISTER="{path}"' + source[end:]
            else:
                source = source.replace(f'/usr/bin/{name}', str(path))
        source = source.replace('  jobs_deployment_commit || return $?\n', '  [[ ! -e "$PROJECT_ROOT/fail-after-configuration" ]] || return 7\n  jobs_deployment_commit || return $?\n', 1)
        self.script = self.base / 'Scripts/【MacOS】ManageProjectTools.zsh/【MacOS】ManageProjectTools.zsh'
        self.script.parent.mkdir(parents=True)
        self.script.write_text(source)

    def run_script(self, operation, *features, success=True):
        result = subprocess.run(['zsh', str(self.script), operation, *features], capture_output=True, text=True, cwd='/', env=dict(os.environ, HOME=str(self.base), NO_COLOR='1'))
        self.assertEqual(result.returncode == 0, success, result.stdout + result.stderr)
        return result

    def configured(self):
        return set(filter(None, self.config.read_text().split(',')))

    def test_relocated_wrapped_and_flat_entries_resolve_their_own_resources(self):
        source = source_script(ROOT / 'JobsProjectTools/Scripts/ManageProjectTools.zsh').read_text()
        for layout in ['wrapped', 'flat']:
            with self.subTest(layout=layout):
                package = self.base / f'搬移 项目 {layout}'
                scripts = package / 'Scripts'
                entry = scripts / ('【MacOS】ManageProjectTools.zsh/【MacOS】ManageProjectTools.zsh' if layout == 'wrapped' else 'ManageProjectTools.zsh')
                entry.parent.mkdir(parents=True)
                entry.write_text(source)
                deployment = scripts / '【MacOS】AppDeployment.zsh/【MacOS】AppDeployment.zsh'
                deployment.parent.mkdir(parents=True)
                deployment.write_text('jobs_deployment_app_path() { print -r -- "$1"; }\n')
                home = package / 'private-home'
                home.mkdir()
                result = subprocess.run(['zsh', str(entry), 'uninstall', 'vscode_opener'], capture_output=True, text=True, cwd='/', env=dict(os.environ, HOME=str(home), NO_COLOR='1'))
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn(f'所选位置未安装，无需卸载：{package}/work/DerivedData/Build/Products/Debug/JobsProjectTools.app', result.stdout)
                self.assertFalse((home / 'Library').exists())

    def test_migration_partial_uninstall_reinstall_and_full_uninstall(self):
        self.run_script('install', 'vscode_opener')
        self.assertEqual(self.configured(), set(FEATURES))
        state = json.loads(self.state.read_text())
        self.assertEqual(state[GROUP_ID], '+')
        self.assertEqual(state['com.jobs.gitproxyconfigurator.findersync'], '-')
        self.assertEqual(self.terminal.read_text(), 'open,pod-install,unknown')
        self.assertTrue(all(state[f'com.jobs.{app}.FinderSyncExtension'] == '-' for app in APPS))
        self.run_script('uninstall', 'git_remote')
        self.assertEqual(self.configured(), set(FEATURES) - {'git_remote'})
        self.assertEqual(json.loads(self.state.read_text())[GROUP_ID], '+')
        self.run_script('install', 'git_remote')
        self.assertEqual(self.configured(), set(FEATURES))
        self.run_script('uninstall', *FEATURES)
        self.assertEqual(self.configured(), set())
        self.assertEqual(json.loads(self.state.read_text())[GROUP_ID], '-')
        self.run_script('install', 'vscode_opener')
        self.assertEqual(self.configured(), {'vscode_opener'})

    def test_failure_after_configuration_publication_restores_exact_prior_files(self):
        self.config.parent.mkdir(parents=True, exist_ok=True)
        self.config.write_text('git-pull')
        self.config.chmod(0o640)
        git_marker = self.config.parent / 'GitMenuMigrationVersion.txt'
        rollback_marker = self.config.parent / 'GitRollbackMigrationVersion.txt'
        git_marker.write_text('previous-git-marker')
        rollback_marker.write_text('previous-rollback-marker')
        before_terminal = self.terminal.read_bytes()
        (self.base / 'fail-after-configuration').touch()
        self.run_script('install', 'vscode_opener', success=False)
        self.assertEqual(self.config.read_text(), 'git-pull')
        self.assertEqual(self.config.stat().st_mode & 0o777, 0o640)
        self.assertEqual(git_marker.read_text(), 'previous-git-marker')
        self.assertEqual(rollback_marker.read_text(), 'previous-rollback-marker')
        self.assertEqual(self.terminal.read_bytes(), before_terminal)

    def test_retired_sourcetree_does_not_keep_an_uninstalled_package_alive(self):
        self.state.write_text('{}')
        self.run_script('install', *FEATURES)
        self.config.write_text(','.join([*FEATURES, 'git-sourcetree']))
        self.run_script('uninstall', *FEATURES)
        self.assertEqual(self.configured(), set())
        self.assertFalse(self.extension.parent.parent.exists())
        before = self.log.read_bytes()
        result = self.run_script('uninstall', *FEATURES)
        self.assertIn('未安装，无需卸载', result.stdout)
        self.assertEqual(self.log.read_bytes(), before)

    def test_unknown_configuration_is_preserved_and_never_treated_as_uninstalled(self):
        self.config.parent.mkdir(parents=True, exist_ok=True)
        self.config.write_text('vscode_opener,unknown-sibling')
        before = self.config.read_bytes()
        result = self.run_script('uninstall', 'vscode_opener', success=False)
        self.assertEqual(self.config.read_bytes(), before)
        self.assertTrue(self.extension.is_dir())
        self.assertNotIn('未安装，无需卸载', result.stdout)

    def test_build_and_registration_failures_keep_legacy_and_configuration(self):
        for marker in ['fail-build', 'fail-register']:
            with self.subTest(marker=marker):
                (self.base / marker).touch()
                self.run_script('install', 'vscode_opener', success=False)
                self.assertFalse(self.config.exists())
                state = json.loads(self.state.read_text())
                self.assertTrue(all(value == '+' for value in state.values()))
                (self.base / marker).unlink()

    def test_clean_install_does_not_enable_unselected_features(self):
        self.state.write_text('{}')
        self.run_script('install', 'xcode_opener', 'git-pull')
        self.assertEqual(self.configured(), {'xcode_opener', 'git-pull'})

    def test_retired_sourcetree_rejects_install_and_legacy_uninstall_preserves_siblings(self):
        self.state.write_text('{}')
        self.run_script('install', 'xcode_opener')
        self.config.write_text('xcode_opener,git-sourcetree')
        before = self.config.read_bytes()
        self.run_script('install', 'git-sourcetree', success=False)
        self.assertEqual(self.config.read_bytes(), before)
        self.run_script('uninstall', 'git-sourcetree')
        self.assertEqual(self.configured(), {'xcode_opener'})
        self.assertEqual(json.loads(self.state.read_text())[GROUP_ID], '+')

    def test_unknown_feature_has_no_side_effects(self):
        self.run_script('install', 'unknown', success=False)
        self.assertFalse(self.log.exists())
        self.assertFalse(self.config.exists())

    def test_legacy_uninstall_does_not_create_group_configuration(self):
        self.run_script('uninstall', 'git_remote')
        self.assertFalse(self.config.exists())
        state = json.loads(self.state.read_text())
        self.assertEqual(state['com.jobs.JobsGitRemoteOpener.FinderSyncExtension'], '-')
        self.assertEqual(state['com.jobs.JobsVSCodeOpener.FinderSyncExtension'], '+')

    def test_existing_group_migrates_once_and_preserves_other_terminal_entries(self):
        self.config.parent.mkdir()
        self.config.write_text('vscode_opener')
        self.run_script('install', 'git_remote')
        self.assertEqual(self.configured(), {'vscode_opener', 'git_remote', 'git-proxy-configure', 'git_empty_commit_push', 'git-rollback'})
        self.run_script('uninstall', 'git-proxy-configure', 'git_empty_commit_push')
        self.run_script('install', 'xcode_opener')
        self.assertEqual(self.configured(), {'vscode_opener', 'git_remote', 'xcode_opener', 'git-rollback'})
        self.assertEqual(self.terminal.read_text(), 'open,pod-install,unknown')

    def test_uninstalling_ide_before_migration_preserves_legacy_git_choice(self):
        self.config.parent.mkdir()
        self.config.write_text('vscode_opener')
        self.run_script('uninstall', 'vscode_opener')
        self.assertEqual(self.terminal.read_text(), 'open,pod-install,git-empty-commit-push,unknown')
        self.assertFalse((self.config.parent / 'GitMenuMigrationVersion.txt').exists())
        self.run_script('install', 'xcode_opener')
        self.assertIn('git_empty_commit_push', self.configured())

    def test_explicit_empty_commit_uninstall_only_removes_its_legacy_menu(self):
        self.run_script('uninstall', 'git_empty_commit_push')
        self.assertEqual(self.terminal.read_text(), 'open,pod-install,unknown')
        self.assertFalse(self.config.exists())

    def test_rollback_migrates_once_then_respects_uninstall(self):
        self.run_script('install', 'git-rollback')
        self.assertIn('git-rollback', self.configured())
        state = json.loads(self.state.read_text())
        self.assertEqual(state['com.jobs.JobsGitRollback.FinderSyncExtension'], '-')
        self.assertTrue((self.config.parent / 'GitRollbackMigrationVersion.txt').exists())
        self.run_script('uninstall', 'git-rollback')
        self.assertNotIn('git-rollback', self.configured())
        self.run_script('install', 'vscode_opener')
        self.assertNotIn('git-rollback', self.configured())

    def test_rollback_uninstall_preserves_unrelated_legacy_menus(self):
        self.run_script('uninstall', 'git-rollback')
        state = json.loads(self.state.read_text())
        self.assertEqual(state['com.jobs.JobsGitRollback.FinderSyncExtension'], '-')
        self.assertEqual(state['com.jobs.JobsVSCodeOpener.FinderSyncExtension'], '+')
        self.assertFalse(self.config.exists())

    def test_rollback_entries_and_bundle_use_the_shared_implementation(self):
        project = (ROOT / 'JobsProjectTools/JobsProjectTools.xcodeproj/project.pbxproj').read_text()
        self.assertIn('../' + str(source_script(ROOT / 'JobsGitRollback/Scripts/RollbackGitRepository.zsh').relative_to(ROOT)), project)
        # 显式复制阶段将新源码布局映射回既有 Bundle 资源名。
        parsed = json.loads(subprocess.run(['/usr/bin/plutil', '-convert', 'json', '-o', '-', str(ROOT / 'JobsProjectTools/JobsProjectTools.xcodeproj/project.pbxproj')], capture_output=True, text=True, check=True).stdout)
        phases = [obj for obj in parsed['objects'].values() if obj.get('isa') == 'PBXShellScriptBuildPhase']
        source = '$(SRCROOT)/../' + str(source_script(ROOT / 'JobsGitRollback/Scripts/RollbackGitRepository.zsh').relative_to(ROOT))
        destination = '$(TARGET_BUILD_DIR)/$(UNLOCALIZED_RESOURCES_FOLDER_PATH)/RollbackGitRepository.zsh'
        self.assertTrue(any(source in phase.get('inputPaths', []) and destination in phase.get('outputPaths', []) for phase in phases))
        manager = source_script(ROOT / 'JobsGitRollback/Scripts/ManageExtension.zsh').read_text()
        self.assertIn('MANAGER_UI_SCOPE="git-rollback"', manager)
        self.assertIn('JobsProjectTools/Scripts/ManageProjectTools.zsh', manager)
        self.assertIn('run_feature_operation install', manager)
        self.assertIn('run_feature_operation uninstall', manager)

    def test_all_entry_points_route_to_the_group(self):
        installer = source_script(ROOT / 'Scripts/ManageFinderExtensions.zsh').read_text()
        self.assertIn('ManageProjectTools.zsh")" install', installer)
        self.assertIn('ManageProjectTools.zsh")" uninstall', installer)
        for feature, app in zip(FEATURES, APPS):
            self.assertIn(f'SELECTABLE_FUNCTION_PROJECT_KEY[{feature}]="project-tools"', installer)
            manager = source_script(ROOT / app / 'Scripts/ManageExtension.zsh').read_text()
            self.assertIn(f'MANAGER_UI_SCOPE="{feature}"', manager)
            self.assertIn('JobsProjectTools/Scripts/ManageProjectTools.zsh', manager)
            self.assertIn('run_feature_operation install', manager)
            self.assertIn('run_feature_operation uninstall', manager)


if __name__ == '__main__':
    unittest.main()
