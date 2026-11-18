#!/bin/zsh
# Run only after the unified extension is enabled. Retire known Flutter entries, preserve all other menus.
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

setopt ERR_EXIT PIPE_FAIL
unified='com.jobs.JobsFlutterTools.FinderSyncExtension'
registration="$(/usr/bin/pluginkit -m -i "$unified" -v)"
print -r -- "$registration" | /usr/bin/grep -Eq '^\+.*com\.jobs\.JobsFlutterTools\.FinderSyncExtension' || { print -u2 '统一 Flutter 扩展尚未启用；未停用旧菜单。'; exit 1; }
for identifier in com.jobs.JobsFlutterVersionMgr.FinderSyncExtension com.jobs.JobsFlutterSdkInspector.FinderSyncExtension com.jobs.JobsFlutterDependencyExtractor.FinderSync com.jobs.JobsFlutterRunner.FinderSyncExtension com.jobs.JobsFlutterPackager.findersync com.jobs.JobsFlutterDoctor.FinderSyncExtension com.jobs.JobsFlutterCodegen.FinderSyncExtension; do
  /usr/bin/pluginkit -e ignore -i "$identifier" || exit 1
done
config="$HOME/Library/Application Support/JobsTerminalOpener/EnabledFinderMenuFeatures.txt"
[[ ! -L "$config" && ! -L "${config:h}" ]] || { print -u2 'Terminal 菜单配置是链接，未改写。'; exit 1; }
if [[ -f "$config" ]]; then
  value="$(<"$config")"
  [[ ",$value," == *flutter-pub-get* ]] || exit 0
else
  value='open,pod-install,clean-build-artifacts,codegraph-bootstrap,git-empty-commit-push'
fi
/bin/mkdir -p "${config:h}"
backup="$(/usr/bin/mktemp -d "${config:h}/FlutterMenuMigration.XXXXXX")"
[[ ! -f "$config" ]] || /bin/cp -p "$config" "$backup/EnabledFinderMenuFeatures.txt"
print -r -- "$value" | /usr/bin/tr ',' '\n' | /usr/bin/awk '{$1=$1} $0 != "flutter-pub-get" && length {if (count++) printf ","; printf "%s", $0} END {print ""}' > "$backup/next"
/bin/mv "$backup/next" "$config"
print -r -- '✔ 已停用旧 Flutter 独立菜单；Terminal 其他功能保持原有选择。'
