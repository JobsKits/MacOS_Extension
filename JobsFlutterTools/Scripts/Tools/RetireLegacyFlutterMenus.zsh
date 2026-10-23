#!/bin/zsh
# Run only after the unified extension is enabled. Retire known Flutter entries, preserve all other menus.
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
