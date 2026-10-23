#!/bin/zsh
# shell: zsh
# 脚本自述：通用 iOS 开发 / Ad Hoc IPA 免编译重签工具。
# - 使用本机证书私钥与有效描述文件，分别重签主 App、Widget 和嵌套动态代码。
# - 不登录 Apple、不刷新描述文件、不编译；新包验证后替换原 IPA，回车确认后安装到已选设备。
# - 双击后先确认；过期、设备未授权、权限不匹配或缺少私钥时停止。

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
typeset -g SCRIPT_DIR SCRIPT_PATH SCRIPT_BASENAME LOG_FILE WORK_ROOT REPLACEMENT_DIR IPA_PATH TARGET_UDID
typeset -g OTOOL_PATH FZF_PATH PROJECT_FOLDER IPA_BUNDLE_ID
typeset -g IPA_REPLACED=0 FINISH_WAIT=1
# 终端按语义着色；重定向、NO_COLOR 或简陋终端使用纯文本。
display_line() {
  local message="$1" style='' label
  if [[ ! -t 1 || "${TERM:-dumb}" == dumb || -n "${NO_COLOR+x}" ]]; then
    print -r -- "$message"
    return
  fi
  case "$message" in
    '✖'*) style='1;31' ;;
    '⚠'*) style='1;33' ;;
    *'UDID：'*|*'目标设备：'*) style='1;36' ;;
    '✔'*) style='1;32' ;;
    'ℹ'*) style='36' ;;
    '➤'*) style='1;35' ;;
    'Jobs ·'*|'── '*) style='1' ;;
  esac
  if [[ -n "$style" ]]; then
    printf '\033[%sm%s\033[0m\n' "$style" "$message"
  elif [[ "$message" == *：* ]]; then
    label="${message%%：*}"
    printf '\033[1m%s：\033[0m%s\n' "$label" "${message#*：}"
  else
    print -r -- "$message"
  fi
}
# 打印内置说明，确认前不写文件或修改环境。
show_script_intro_and_wait() {
  display_line 'Jobs · 通用 IPA 免编译重签' | jobs_intro_style title
  display_line '用途：对已有 IPA 重新签名；不重新编译源码。' | jobs_intro_style body
  display_line '需要：有效描述文件、对应证书私钥，以及描述文件已授权的设备。' | jobs_intro_style body
  display_line '免费 Personal Team 的描述文件通常只有 7 天；本工具不能续期。' | jobs_intro_style body
  display_line '支持：自有未加密 iOS IPA，保持原团队与 Bundle ID，主 App 和扩展分别签名。' | jobs_intro_style body
  display_line '不支持：App Store 加密包、跨团队迁移、Watch App、macOS / tvOS 包。' | jobs_intro_style body
  display_line '工程目录：回车从 IPA 向上寻找工程根目录并校验；也可手动拖入。再次回车会重新查找。' | jobs_intro_style body
  display_line '材料不足时强提示打开 Xcode，人工刷新后在本窗口复检，最多复检三轮。' | jobs_intro_style body
  display_line '范围：在临时副本中重签，完整验证成功后替换原 IPA；失败保留原包，不生成桌面报告或结果目录。' | jobs_intro_style body
  display_line '安装：替换成功后，直接回车安装到已选设备；输入任意字符（包括空格）结束脚本。不自动卸载旧 App。' | jobs_intro_style body
  display_line '日志：系统临时目录/IPA免编译重签.时间戳.进程号.log；结束时显示完整路径。' | jobs_intro_style body
  display_line '可选参数：第一个参数为 IPA 绝对路径，第二个参数为设备 UDID。' | jobs_intro_style body
  display_line '未指定 UDID 时自动检测：单台自动选中，多台使用 fzf 选择；无设备可重扫或手动输入。' | jobs_intro_style body
  display_line '遇到钥匙串授权提示，只授权本次 codesign 使用所选证书。Ctrl+C 可取消。' | jobs_intro_style body
  [[ -t 0 ]] || { print -u2 -- '请双击或在交互式终端运行。'; exit 2; }
  read -r '?按回车继续，Ctrl+C 取消：' || exit 2
}
# 同步终端与纯文本日志。
log() {
  print -r -- "$*" >> "$LOG_FILE"
  display_line "$*"
}
# 输出明确错误并停止下游业务。
fail() {
  log "✖ $*"
  exit 1
}
# 回收本次临时副本，保留日志与成功结果。
finish() {
  local result=$?
  trap - EXIT
  if [[ -n "$REPLACEMENT_DIR" && "$REPLACEMENT_DIR" == "${IPA_PATH:h}/.jobs-ipa-replace."* && -d "$REPLACEMENT_DIR" ]]; then
    /bin/rm -f -- "$REPLACEMENT_DIR/replacement.ipa"
    /bin/rmdir -- "$REPLACEMENT_DIR"
  fi
  if [[ -n "$WORK_ROOT" && "$WORK_ROOT" == "${TMPDIR:-/tmp/}"jobs-ipa-resign.* && -d "$WORK_ROOT" ]]; then
    /bin/rm -rf -- "$WORK_ROOT"
  fi
  print -r -- "日志：$LOG_FILE"
  if (( result != 0 )); then
    if (( IPA_REPLACED )); then
      display_line "⚠ 后续流程未完成；已重签的 IPA 保留在：$IPA_PATH"
    else
      display_line '未生成可交付 IPA；原文件未修改。'
    fi
  fi
  if [[ -t 0 && "$FINISH_WAIT" == 1 ]]; then
    read -r '?按回车关闭：'
  fi
  exit "$result"
}
# 在整个脚本结束时执行回收，避免 zsh 的函数级 EXIT trap 提前触发。
TRAPEXIT() {
  finish
}
# 初始化运行参数、私有临时目录和失败回收。
initialize_runtime() {
  setopt NO_NOMATCH PIPE_FAIL
  umask 077
  SCRIPT_PATH="${0:A}"
  SCRIPT_DIR="${SCRIPT_PATH:h}"
  SCRIPT_BASENAME="${SCRIPT_PATH:t:r}"
  LOG_FILE="${TMPDIR:-/tmp/}IPA免编译重签.$(/bin/date +%Y%m%d-%H%M%S).$$.log"
  : > "$LOG_FILE" || exit 1
  trap 'exit 130' INT
  trap 'exit 143' TERM
  WORK_ROOT=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp/}jobs-ipa-resign.XXXXXX") || fail '无法创建临时目录。'
  IPA_PATH="${1:-}"
  TARGET_UDID="${2:-}"
}
# 解析 Finder 拖入的转义路径，不使用 eval 或执行用户输入。
normalize_file_path() {
  local raw="$1"
  local kind="${2:-file}"
  local -a parts
  raw="${raw%$'\r'}"
  [[ "$raw" == q ]] && exit 0
  if [[ "$kind" == directory && -d "$raw" || "$kind" == file && -f "$raw" ]]; then
    REPLY="${raw:A}"
    return
  fi
  parts=( ${(z)raw} )
  (( ${#parts} == 1 )) || { log '⚠ 每次只接受一个文件，请重新拖入。'; return 1; }
  REPLY="${(Q)parts[1]}"
  [[ "$kind" == directory && -d "$REPLY" || "$kind" == file && -f "$REPLY" ]] || { log "⚠ 路径不存在或类型不正确：$REPLY"; return 1; }
  REPLY="${REPLY:A}"
}
# 读取 IPA 主 App 标识，供工程归属校验使用，不执行包内代码。
read_ipa_identity() {
  local LC_ALL=C
  local entry
  local -a entries
  while IFS= read -r entry; do
    [[ "$entry" =~ '^Payload/[^/]+\.app/Info\.plist$' ]] && entries+=("$entry")
  done < <(/usr/bin/unzip -Z1 "$IPA_PATH")
  (( ${#entries} == 1 )) || fail '无法唯一确定 IPA 主 App 的 Info.plist。'
  /usr/bin/unzip -p "$IPA_PATH" "${entries[1]}" > "$WORK_ROOT/ipa-info.plist" || fail '无法读取 IPA 信息。'
  IPA_BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$WORK_ROOT/ipa-info.plist") || fail 'IPA 缺少 Bundle ID。'
}
# 检查真实 iOS 应用 Target 与 IPA 标识，过滤只有同名目录的误匹配。
validate_ios_projects() {
  /usr/bin/osascript -l JavaScript - "$1" "$IPA_BUNDLE_ID" <<'IOSPROJECT'
ObjC.import('Foundation');
function run(args) {
  const text=ObjC.unwrap($.NSString.stringWithContentsOfFileEncodingError(args[0],$.NSUTF8StringEncoding,null));
  const found=[];
  for(const path of text.trim().split('\n').filter(Boolean)) {
    try {
      const native=$.NSPropertyListSerialization.propertyListWithDataOptionsFormatError($.NSData.dataWithContentsOfFile(path),0,null,null);
      if(!native) continue;
      const p=ObjC.deepUnwrap(native), objects=p.objects, project=objects[p.rootObject];
      if(!project || project.isa!=='PBXProject') continue;
      const root=path.replace(/\/[^/]+\.xcodeproj\/project\.pbxproj$/,'');
      const defaults=((objects[project.buildConfigurationList]||{}).buildConfigurations||[]).map(id=>objects[id]);
      for(const id of project.targets||[]) {
        const t=objects[id];
        if(t.isa!=='PBXNativeTarget' || t.productType!=='com.apple.product-type.application') continue;
        for(const configID of (objects[t.buildConfigurationList]||{}).buildConfigurations||[]) {
          const c=objects[configID], base=defaults.find(b=>b.name===c.name);
          const s=Object.assign({},(base||{}).buildSettings||{},c.buildSettings||{},{SRCROOT:root,PROJECT_DIR:root,TARGET_NAME:t.name,CONFIGURATION:c.name});
          const expand=v=>{let value=String(v||'');for(let i=0;i<10;i++){const next=value.replace(/\$\(([^)]+)\)|\$\{([^}]+)\}/g,(all,a,b)=>typeof s[a||b]==='string'?s[a||b]:all);if(next===value)break;value=next;}return value;};
          const ios=/^iphoneos/.test(expand(s.SDKROOT)) || /\biphoneos\b/.test(expand(s.SUPPORTED_PLATFORMS));
          if(ios && expand(s.PRODUCT_BUNDLE_IDENTIFIER)===args[1]) {found.push(path);break;}
        }
      }
    } catch(e) { /* 无法解析的工程不作为匹配依据。 */ }
  }
  const unique=Array.from(new Set(found));
  if(unique.length!==1) throw Error('未找到唯一匹配 IPA Bundle ID 的 iOS 应用工程（或配置依赖未解析的 xcconfig）。');
  return unique[0];
}
IOSPROJECT
}
# 向上逐层检查工程，识别仓库根目录作为顶层边界，不扫描其它仓库。
discover_project_folder() {
  local cursor="${IPA_PATH:h}" boundary='' candidate project matched=''
  local -a projects
  boundary=$(/usr/bin/git -C "$cursor" rev-parse --show-toplevel 2>/dev/null) || boundary=''
  [[ -n "$boundary" ]] && boundary="${boundary:A}"
  : > "$WORK_ROOT/ancestor-projects.txt"
  while true; do
    projects=("$cursor/"*.xcodeproj/project.pbxproj(N))
    for project in "${projects[@]}"; do
      print -r -- "$project" >> "$WORK_ROOT/ancestor-projects.txt"
    done
    [[ "$cursor" == / || "$cursor" == "$boundary" ]] && break
    cursor="${cursor:h}"
  done
  matched=$(validate_ios_projects "$WORK_ROOT/ancestor-projects.txt" 2>> "$LOG_FILE") || return 1
  candidate="${matched:h:h}"
  [[ -n "$boundary" && "$candidate/" == "$boundary/"* ]] && candidate="$boundary"
  PROJECT_FOLDER="$candidate"
  print -r -- "$matched" > "$WORK_ROOT/projects.txt"
}
# 关联工程根目录；回车每次重新自动查找，失败后保持输入循环。
select_project_folder() {
  local input matched
  read_ipa_identity
  log '── 关联 IPA 对应工程 ──'
  while true; do
    read -r 'input?拖入对应工程文件夹；直接回车从 IPA 向上查找（q 退出）：' < /dev/tty || fail '输入已取消。'
    if [[ -z "${input//[[:space:]]/}" ]]; then
      log "ℹ 从 IPA 所在目录向上查找并验证：${IPA_PATH:h}"
      discover_project_folder || { log '✖ 未找到可验证的对应 iOS 工程根目录。请手动拖入；再次回车将重新查找。'; continue; }
    else
      normalize_file_path "$input" directory || continue
      PROJECT_FOLDER="$REPLY"
      /usr/bin/find "$PROJECT_FOLDER" \( -type d \( -name .git -o -name Pods -o -name node_modules -o -name build -o -name DerivedData -o -name .dart_tool \) -prune \) -o \( -type f -name project.pbxproj -print \) > "$WORK_ROOT/projects.txt"
      matched=$(validate_ios_projects "$WORK_ROOT/projects.txt" 2>> "$LOG_FILE") || { log '✖ 目录未通过对应 iOS 工程校验，请重新拖入；回车可重新自动查找。'; continue; }
      print -r -- "$matched" > "$WORK_ROOT/projects.txt"
    fi
    log "✔ 对应工程：$PROJECT_FOLDER"
    return 0
  done
}
# 静态读取工程配置，不调用构建；只有全部配置一致时才自动使用权限文件。
resolve_project_entitlements() {
  /usr/bin/osascript -l JavaScript - "$WORK_ROOT/projects.txt" "$1" <<'PROJECT'
ObjC.import('Foundation');
function run(args) {
  const read=p=>ObjC.unwrap($.NSString.stringWithContentsOfFileEncodingError(p,$.NSUTF8StringEncoding,null));
  const matches=[];
  for (const path of read(args[0]).trim().split('\n')) {
    const data=$.NSData.dataWithContentsOfFile(path);
    const plist=$.NSPropertyListSerialization.propertyListWithDataOptionsFormatError(data,0,null,null);
    if (!plist) continue;
    const p=ObjC.deepUnwrap(plist), objects=p.objects, project=objects[p.rootObject];
    const root=path.replace(/\/[^/]+\.xcodeproj\/project\.pbxproj$/,'');
    const projectConfigs=(objects[project.buildConfigurationList]||{}).buildConfigurations||[];
    for (const targetID of project.targets||[]) {
      const target=objects[targetID];
      if (target.isa!=='PBXNativeTarget') continue;
      const configs=(objects[target.buildConfigurationList]||{}).buildConfigurations||[];
      const paths=[]; let hit=false, uncertain=false;
      for (const configID of configs) {
        const config=objects[configID], own=config.buildSettings||{};
        const inherited=projectConfigs.map(id=>objects[id]).find(c=>c.name===config.name);
        const settings=Object.assign({},(inherited||{}).buildSettings||{},own);
        Object.assign(settings,{SRCROOT:root,PROJECT_DIR:root,SOURCE_ROOT:root,TARGET_NAME:target.name,CONFIGURATION:config.name});
        const expand=value=>{
          let text=String(value||'');
          for(let i=0;i<10 && /\$[({]/.test(text);i++) {
            const next=text.replace(/\$\(([^)]+)\)|\$\{([^}]+)\}/g,(all,a,b)=> typeof settings[a||b]==='string'?settings[a||b]:all);
            if(next===text) break; text=next;
          }
          return text;
        };
        const id=expand(settings.PRODUCT_BUNDLE_IDENTIFIER);
        if(id===args[1]) hit=true;
        // 依赖 xcconfig、条件覆盖或不同配置的匹配无法静态确定时，保持人工兜底。
        if(id!==args[1] || !own.PRODUCT_BUNDLE_IDENTIFIER || !own.CODE_SIGN_ENTITLEMENTS || Object.keys(settings).some(k=>/^(PRODUCT_BUNDLE_IDENTIFIER|CODE_SIGN_ENTITLEMENTS)\[/.test(k))) {uncertain=true;continue;}
        const entitlement=expand(settings.CODE_SIGN_ENTITLEMENTS);
        if(!entitlement || /\$[({]/.test(entitlement)) {uncertain=true;continue;}
        const resolved=ObjC.unwrap($(entitlement.startsWith('/')?entitlement:root+'/'+entitlement).stringByStandardizingPath);
        if(!$.NSFileManager.defaultManager.fileExistsAtPath(resolved)) {uncertain=true;continue;}
        paths.push(resolved);
      }
      if(hit) matches.push({uncertain,paths:Array.from(new Set(paths))});
    }
  }
  if(matches.length!==1 || matches[0].uncertain || matches[0].paths.length!==1) throw Error('无法唯一确定该 Bundle ID 的权限配置，请手动提供对应 .entitlements / .xcent。');
  return matches[0].paths[0];
}
PROJECT
}
# 从终端读取文件，避免嵌套文件遍历占用标准输入。
read_file_path() {
  local input
  while true; do
    read -r "input?$1：" < /dev/tty || fail '输入已取消。'
    if [[ -z "${input//[[:space:]]/}" ]]; then
      log 'ℹ 尚未输入文件，请拖入文件或输入路径；q 退出。'
      continue
    fi
    normalize_file_path "$input" && return 0
  done
}
# 接收 IPA 和实际目标设备，避免沿用固定项目或固定手机。
select_input() {
  log '── 选择 IPA 与目标设备 ──'
  if [[ -z "$IPA_PATH" ]]; then
    read_file_path '请拖入目标 IPA 或输入路径（q 退出）'
    IPA_PATH="$REPLY"
  fi
  [[ -f "$IPA_PATH" && "${IPA_PATH:e:l}" == ipa ]] || fail "不是有效 IPA 文件路径：$IPA_PATH"
  IPA_PATH="${IPA_PATH:A}"
  select_project_folder
  if [[ -z "$TARGET_UDID" ]]; then
    detect_target_device
  fi
  if [[ -z "$TARGET_UDID" ]]; then
    log 'ℹ 请从爱思设备信息复制 UDID；不要填写序列号、IMEI 或 devicectl 的内部 UUID。'
    read -r 'TARGET_UDID?目标 iPhone / iPad 的 UDID（q 退出）：' || fail '输入已取消。'
    [[ "$TARGET_UDID" == q ]] && exit 0
  fi
  [[ "$TARGET_UDID" =~ '^[A-Fa-f0-9-]{16,64}$' ]] || fail '设备 UDID 格式不正确。'
  log "ℹ 输入：$IPA_PATH"
  log "ℹ 目标设备：$TARGET_UDID"
}
# 从结构化设备数据提取硬件 UDID，排除离线记录和模拟器。
parse_connected_devices() {
  /usr/bin/osascript -l JavaScript - "$1" <<'DEVICES'
ObjC.import('Foundation');
function run(args) {
  const data=JSON.parse(ObjC.unwrap($.NSString.stringWithContentsOfFileEncodingError(args[0],$.NSUTF8StringEncoding,null)));
  if (data.info && data.info.outcome !== 'success') throw Error('设备枚举失败');
  const seen=new Set();
  return ((data.result||{}).devices||[]).map(d=>{
    const p=d.properties||{}, h=p.hardware||d.hardwareProperties||{}, c=p.connection||d.connectionProperties||{}, s=p.state||d.deviceProperties||{};
    const state=c.state||c.tunnelState;
    if (!['connected','available'].includes(state) || !['iPhone','iPad'].includes(h.deviceType) || h.reality!=='physical') return '';
    const udid=h.udid;
    if (!/^(?:[A-Fa-f0-9]{8}-[A-Fa-f0-9]{16}|[A-Fa-f0-9]{40})$/.test(udid||'') || seen.has(udid.toUpperCase())) return '';
    seen.add(udid.toUpperCase());
    const label=[s.name||h.deviceType,h.marketingName||'',c.transportType||''].join(' · ').replace(/[\r\n\t]/g,' ');
    return udid+'\t'+label;
  }).filter(Boolean).join('\n');
}
DEVICES
}
# 检查 PATH 与两种 Homebrew 路径中的 fzf，并保存实际可用入口。
find_healthy_fzf() {
  local candidate version
  local -a candidates
  candidates=("$(command -v fzf 2>/dev/null)" /opt/homebrew/bin/fzf /usr/local/bin/fzf)
  for candidate in "${candidates[@]}"; do
    [[ -n "$candidate" && -x "$candidate" ]] || continue
    if version=$("$candidate" --version 2>/dev/null); then
      FZF_PATH="${candidate:A}"
      log "ℹ fzf：$FZF_PATH，版本：$version"
      return 0
    fi
  done
  return 1
}
# 缺失或损坏时提供一次安装修复机会，完成后重新发现并验证。
ensure_fzf() {
  find_healthy_fzf && return 0
  local candidate brew_path='' answer action=install
  local -a candidates
  candidates=("$(command -v brew 2>/dev/null)" /opt/homebrew/bin/brew /usr/local/bin/brew)
  for candidate in "${candidates[@]}"; do
    [[ -n "$candidate" && -x "$candidate" ]] || continue
    if "$candidate" --version >> "$LOG_FILE" 2>&1 && "$candidate" --prefix >> "$LOG_FILE" 2>&1; then
      brew_path="$candidate"
      break
    fi
  done
  [[ -n "$brew_path" ]] || fail 'fzf 不可用，且未找到健康的 Homebrew。请先安装或修复 Homebrew，再执行 brew install fzf 后重试。'
  "$brew_path" list --versions fzf >/dev/null 2>&1 && action=reinstall
  log "⚠ 多设备选择需要 fzf。将使用 $brew_path $action fzf；不会升级其它软件。"
  read -r 'answer?直接回车跳过并退出；输入任意字符安装或修复 fzf：' < /dev/tty || fail '输入已取消。'
  [[ -n "$answer" ]] || exit 0
  HOMEBREW_NO_AUTO_UPDATE=1 "$brew_path" "$action" fzf 2>&1 | /usr/bin/tee -a "$LOG_FILE" || fail 'fzf 安装或修复失败。'
  rehash
  find_healthy_fzf || fail 'fzf 安装后复检失败，停止设备选择。'
}
# 使用 fzf 单选真实设备行，取消或异常时不自动选取首项。
select_device_with_fzf() {
  ensure_fzf
  local selected result row
  local palette='header:bold,prompt:cyan:bold,pointer:green,hl:yellow,hl+:yellow:bold,info:cyan'
  [[ -n "${NO_COLOR+x}" || "${TERM:-dumb}" == dumb ]] && palette=bw
  selected=$(printf '%s\n' "$@" | FZF_DEFAULT_OPTS='' FZF_DEFAULT_OPTS_FILE=/dev/null "$FZF_PATH" --no-multi --height=60% --layout=reverse --border --color="$palette" --delimiter=$'\t' --with-nth=2,1 --prompt='目标设备 > ' --header='选择安装目标：名称 · 型号 · 连接方式 | UDID；回车确认，Esc 取消')
  result=$?
  if (( result == 130 || result == 1 )); then
    log 'ℹ 已取消设备选择。'
    exit 0
  fi
  (( result == 0 )) && [[ -n "$selected" ]] || fail 'fzf 设备选择失败。'
  for row in "$@"; do
    if [[ "$selected" == "$row" ]]; then
      TARGET_UDID="${selected%%$'\t'*}"
      log "✔ 已选择：${selected#*$'\t'}，UDID：$TARGET_UDID"
      return 0
    fi
  done
  fail '选择结果不在本轮检测到的设备列表中。'
}
# 单设备自动使用，多设备通过 fzf 选择，检测失败时保留手动输入兜底。
detect_target_device() {
  local answer row
  local -a devices
  while true; do
    log 'ℹ 正在检测已连接的 iPhone / iPad…'
    devices=()
    if /usr/bin/xcrun devicectl --timeout 15 list devices --json-output "$WORK_ROOT/devices.json" >> "$LOG_FILE" 2>&1; then
      if parse_connected_devices "$WORK_ROOT/devices.json" > "$WORK_ROOT/devices.tsv" 2>> "$LOG_FILE"; then
        while IFS= read -r row; do
          [[ -n "$row" ]] && devices+=("$row")
        done < "$WORK_ROOT/devices.tsv"
      fi
    fi
    if (( ${#devices} == 1 )); then
      TARGET_UDID="${devices[1]%%$'\t'*}"
      log "✔ 自动选中：${devices[1]#*$'\t'}，UDID：$TARGET_UDID"
      return 0
    fi
    if (( ${#devices} > 1 )); then
      select_device_with_fzf "${devices[@]}"
      return 0
    else
      log '⚠ 未检测到可用设备。请用数据线连接、解锁并信任此 Mac；检查 Xcode 工具链是否可用。'
      read -r 'answer?连接后输入 r 重扫；回车或 m 手动输入；q 退出：' < /dev/tty || fail '输入已取消。'
    fi
    case "$answer" in
      q|Q) exit 0 ;;
      m|M|'') return 0 ;;
      r|R) continue ;;
      *) log '⚠ 选项无效，请重新选择。' ;;
    esac
  done
}
# 强提示用户打开 Xcode；打开后仍须人工完成签名刷新。
wait_for_xcode() {
  local answer
  while ! /usr/bin/pgrep -x Xcode >/dev/null; do
    log '⚠⚠ 请打开 Xcode。当前未检测到 Xcode 运行，本步骤暂停。'
    read -r 'answer?输入 o 打开 Xcode；手动打开后按回车复检；q 退出：' || fail '输入已取消。'
    case "$answer" in
      q|Q) exit 0 ;;
      o|O) /usr/bin/open -b com.apple.dt.Xcode >> "$LOG_FILE" 2>&1 || log '⚠ 无法启动 Xcode，请先安装或手动打开。' ;;
    esac
  done
  log 'ℹ 已检测到 Xcode；这仅证明应用已打开，不代表签名材料已更新。'
}
# 验证完整原生依赖链，缺失时不自动安装工具。
check_environment() {
  local command_path
  for command_path in /usr/bin/codesign /usr/bin/security /usr/bin/plutil /usr/bin/osascript /usr/bin/ditto /usr/bin/unzip /usr/bin/shasum /usr/bin/base64 /usr/bin/find /usr/libexec/PlistBuddy /usr/bin/file; do
    [[ -x "$command_path" ]] || fail "缺少系统工具：$command_path"
  done
  /usr/bin/security find-identity -v -p codesigning > "$WORK_ROOT/identities.txt" 2>> "$LOG_FILE" || fail '钥匙串不可用。'
  /usr/bin/osascript -l JavaScript -e 'ObjC.import("Foundation"); "ok"' >> "$LOG_FILE" 2>&1 || fail '系统 JavaScript/Foundation 不可用。'
  /usr/bin/plutil -help > /dev/null || fail 'plutil 不可用。'
  if ! OTOOL_PATH=$(/usr/bin/xcrun --find otool 2>> "$LOG_FILE"); then
    wait_for_xcode
    fail 'otool 不可用；请完成 Xcode 首次启动组件安装，并在 Settings → Locations 配置 Command Line Tools 后重试。'
  fi
  "$OTOOL_PATH" -h /usr/bin/true >> "$LOG_FILE" 2>&1 || fail 'otool 无法工作，请检查 Xcode 工具链。'
}
# 解包并检查路径边界，仅接受一个主 App。
unpack_ipa() {
  /usr/bin/unzip -t "$IPA_PATH" >> "$LOG_FILE" 2>&1 || fail 'IPA 压缩数据损坏。'
  /usr/bin/unzip -Z1 "$IPA_PATH" > "$WORK_ROOT/entries.txt" || fail '无法读取 ZIP 目录。'
  local entry target
  while IFS= read -r entry; do
    [[ "$entry" != /* && "/$entry/" != */../* ]] || fail 'ZIP 包含越界路径。'
  done < "$WORK_ROOT/entries.txt"
  /usr/bin/ditto -x -k "$IPA_PATH" "$WORK_ROOT/unpacked" >> "$LOG_FILE" 2>&1 || fail '解压失败。'
  while IFS= read -r -d '' entry; do
    target="${entry:A}"
    [[ "$target" == "${WORK_ROOT:A}/unpacked/"* ]] || fail "符号链接越界：$entry"
  done < <(/usr/bin/find "$WORK_ROOT/unpacked" -type l -print0)
  local -a main_apps
  main_apps=("$WORK_ROOT/unpacked/Payload/"*.app(N/))
  (( ${#main_apps} == 1 )) || fail '只支持 Payload 下一个主 App 的 IPA。'
  /bin/mkdir -p "$WORK_ROOT/bundles" "$WORK_ROOT/profiles" || fail '无法建立检查目录。'
  local bundle index=0 bundle_id executable fallback
  while IFS= read -r -d '' bundle; do
    (( ++index ))
    [[ "$bundle" != *$'\n'* && "$bundle" != *$'\t'* ]] || fail '不支持路径中的换行或制表符。'
    /bin/mkdir "$WORK_ROOT/bundles/$index" || fail '无法建立 bundle 检查目录。'
    print -r -- "$bundle" > "$WORK_ROOT/bundles/$index/path.txt"
    /bin/cp "$bundle/Info.plist" "$WORK_ROOT/bundles/$index/info.plist" || fail '缺少 Info.plist。'
    bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$bundle/Info.plist") || fail '缺少 Bundle ID。'
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleSupportedPlatforms:0' "$bundle/Info.plist" 2>/dev/null)" == iPhoneOS ]] || fail "仅支持 iOS App / 扩展：$bundle_id"
    if ! /usr/bin/security cms -D -i "$bundle/embedded.mobileprovision" > "$WORK_ROOT/bundles/$index/old.plist" 2>> "$LOG_FILE"; then
      log "⚠ $bundle_id 没有可用的原始描述文件。为保持团队与 App ID 前缀，请提供该 target 的原始描述文件。"
      read_file_path '拖入该 target 的 .mobileprovision（可过期，仅用于确认原身份；q 退出）'
      /usr/bin/security cms -D -i "$REPLY" > "$WORK_ROOT/bundles/$index/old.plist" 2>> "$LOG_FILE" || fail '描述文件不可解析。'
    fi
    /usr/bin/codesign -d --xml --entitlements - "$bundle" > "$WORK_ROOT/bundles/$index/requested.plist" 2>> "$LOG_FILE"
    if [[ ! -s "$WORK_ROOT/bundles/$index/requested.plist" ]]; then
      bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$bundle/Info.plist")
      log "⚠ $bundle_id 的原签名没有权限数据，正在匹配工程 Target。"
      if fallback=$(resolve_project_entitlements "$bundle_id" 2>> "$LOG_FILE"); then
        log "✔ 自动定位权限文件：$fallback"
      else
        log '⚠ 工程配置无法唯一解析；请提供对应 target 的 .entitlements 或构建生成的 .xcent。'
        read_file_path '拖入对应权限文件（q 退出）'
        fallback="$REPLY"
      fi
      /bin/cp "$fallback" "$WORK_ROOT/bundles/$index/requested.plist" || fail '权限恢复失败。'
      log "⚠ $bundle_id 缺少签名权限，将根据项目 entitlements 和新描述文件恢复。"
    fi
    /usr/bin/plutil -lint "$WORK_ROOT/bundles/$index/requested.plist" >> "$LOG_FILE" 2>&1 || fail '权限文件不可解析。'
  done < <(/usr/bin/find "${main_apps[1]}" -depth -type d \( -name '*.app' -o -name '*.appex' \) -print0)
  (( index > 0 )) || fail '未找到可签名 App。'
}
# 检查加密负载和暂不支持的嵌套代码；不执行 IPA 中的程序。
inspect_payload() {
  local item format
  while IFS= read -r -d '' item; do
    [[ "$item" != *.xpc ]] || fail '暂不支持嵌套 XPC 服务。'
  done < <(/usr/bin/find "$WORK_ROOT/unpacked/Payload" -type d -name '*.xpc' -print0)
  while IFS= read -r -d '' item; do
    format=$(/usr/bin/file -b "$item") || fail '无法检测文件类型。'
    [[ "$format" == *Mach-O* ]] || continue
    "$OTOOL_PATH" -l "$item" > "$WORK_ROOT/load-commands.txt" 2>> "$LOG_FILE" || fail "无法检查 Mach-O：$item"
    if /usr/bin/awk '$1 == "cryptid" && $2 != "0" {found=1} END {exit !found}' "$WORK_ROOT/load-commands.txt"; then
      fail "检测到加密二进制，不能通过重新签名安装：$item"
    fi
  done < <(/usr/bin/find "$WORK_ROOT/unpacked/Payload" -type f -print0)
}
# 收集 Xcode 缓存中的描述文件及其允许的证书指纹。
collect_profiles() {
  local source decoded cert_index fingerprint index=0
  local -a roots
  /bin/rm -f -- "$WORK_ROOT/profiles/"*(N)
  /usr/bin/security find-identity -v -p codesigning > "$WORK_ROOT/identities.txt" 2>> "$LOG_FILE" || fail '钥匙串读取失败。'
  roots=("$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles" "$HOME/Library/MobileDevice/Provisioning Profiles" "$SCRIPT_DIR/描述文件")
  : > "$WORK_ROOT/certificates.tsv"
  for source in "${roots[@]}"; do
    [[ -d "$source" ]] || continue
    local profile
    while IFS= read -r -d '' profile; do
      (( ++index ))
      decoded="$WORK_ROOT/profiles/$index.plist"
      /usr/bin/security cms -D -i "$profile" > "$decoded" 2>> "$LOG_FILE" || { /bin/rm -f "$decoded"; log "⚠ 跳过无法解析的描述文件：${profile:t}"; continue; }
      /bin/cp "$profile" "$WORK_ROOT/profiles/$index.mobileprovision" || fail '无法暂存描述文件。'
      cert_index=0
      while /usr/bin/plutil -extract "DeveloperCertificates.$cert_index" raw -o "$WORK_ROOT/cert.base64" "$decoded" 2>/dev/null; do
        fingerprint=$(/usr/bin/base64 -D -i "$WORK_ROOT/cert.base64" | /usr/bin/shasum -a 1) || fail '证书指纹计算失败。'
        fingerprint="${fingerprint%% *}"
        printf '%s\t%s\n' "$index" "${(U)fingerprint}" >> "$WORK_ROOT/certificates.tsv"
        (( ++cert_index ))
      done
    done < <(/usr/bin/find "$source" -type f -name '*.mobileprovision' -print0)
  done
}
# 写入内嵌的原生 plist 匹配器；不依赖 Python、Node 或第三方包。
write_planner() {
  /bin/cat > "$WORK_ROOT/plan.js" <<'JXA'
ObjC.import('Foundation');
// 读取原生 plist，同时保留布尔、数组和日期类型。
function plist(p) {
  const data = $.NSData.dataWithContentsOfFile(p);
  if (!data) throw Error('无法读取 ' + p);
  return ObjC.deepUnwrap($.NSPropertyListSerialization.propertyListWithDataOptionsFormatError(data, 0, null, null));
}
// 读取文本清单。
function text(p) { return ObjC.unwrap($.NSString.stringWithContentsOfFileEncodingError(p, $.NSUTF8StringEncoding, null)); }
// 安全落盘计划与 JSON 权限文件。
function write(p, s) { if (!$(s).writeToFileAtomicallyEncodingError(p, true, $.NSUTF8StringEncoding, null)) throw Error('写入失败 ' + p); }
// 列举当前目录，避免执行拼接的 shell 命令。
function names(p) { return ObjC.deepUnwrap($.NSFileManager.defaultManager.contentsOfDirectoryAtPathError(p, null)); }
// 描述文件只允许相等值或自身声明的通配范围。
function allowed(value, permit) {
  if (Array.isArray(value)) return Array.isArray(permit) && value.every(v => permit.some(p => allowed(v, p)));
  if (typeof value === 'string' && typeof permit === 'string') {
    const re = '^' + permit.split('*').map(s => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')).join('.*') + '$';
    return new RegExp(re).test(value);
  }
  if (value && typeof value === 'object') return permit && Object.keys(value).every(k => allowed(value[k], permit[k]));
  return value === permit;
}
// 为每个 bundle 保留请求的权限，仅补签名必需标识。
function entitlements(requested, profile, bundleID) {
  const permit = profile.Entitlements;
  const appID = profile.ApplicationIdentifierPrefix[0] + '.' + bundleID;
  // 仅展开标准 Xcode 标识变量，未知构建变量交给用户提供 .xcent。
  function expand(v) {
    if (Array.isArray(v)) return v.map(expand);
    if (v && typeof v==='object') { const o={}; Object.keys(v).forEach(k=>o[k]=expand(v[k])); return o; }
    if (typeof v!=='string') return v;
    const values={AppIdentifierPrefix:profile.ApplicationIdentifierPrefix[0]+'.',TeamIdentifierPrefix:profile.TeamIdentifier[0]+'.',CFBundleIdentifier:bundleID,PRODUCT_BUNDLE_IDENTIFIER:bundleID};
    const result=v.replace(/\$\(([^)]+)\)|\$\{([^}]+)\}/g,(_,a,b)=>{
      if (!Object.prototype.hasOwnProperty.call(values,a||b)) throw Error('未知构建变量，请提供 .xcent：'+(a||b));
      return values[a||b];
    });
    return result;
  }
  const ent = expand(requested);
  ent['application-identifier'] = appID;
  ent['com.apple.developer.team-identifier'] = profile.TeamIdentifier[0];
  ent['get-task-allow'] = permit['get-task-allow'];
  if (!ent['keychain-access-groups']) ent['keychain-access-groups'] = [appID];
  for (const key of Object.keys(ent)) {
    if (!allowed(ent[key], permit[key])) throw Error('描述文件未授权权限：' + key);
  }
  return ent;
}
// 从同团队、同前缀、同证书且包含目标设备的描述文件中选择最晚到期者。
function run(args) {
  const root = args[0], udid = args[1];
  const identities = text(root + '/identities.txt').match(/[A-F0-9]{40}/g) || [];
  const certs = {};
  text(root + '/certificates.tsv').trim().split('\n').filter(Boolean).forEach(l => {
    const v=l.split('\t'); (certs[v[0]] || (certs[v[0]]=[])).push(v[1]);
  });
  const profiles = names(root + '/profiles').filter(n => n.endsWith('.plist')).map(n => ({index:n.slice(0,-6), p:plist(root+'/profiles/'+n)}));
  const bundles = names(root + '/bundles').sort((a,b)=>Number(a)-Number(b)).map(n => {
    const dir=root+'/bundles/'+n;
    return {index:n, path:text(dir+'/path.txt').trimEnd(), info:plist(dir+'/info.plist'), old:plist(dir+'/old.plist'), requested:plist(dir+'/requested.plist')};
  });
  let report = ['IPA 重签预检', '目标 UDID：'+udid, '生成时间：'+new Date().toISOString()];
  const matches = bundles.map(b => {
    const id=b.info.CFBundleIdentifier;
    if (!b.old.TeamIdentifier || !b.old.ApplicationIdentifierPrefix || !b.old.Entitlements || !allowed(b.old.ApplicationIdentifierPrefix[0]+'.'+id,b.old.Entitlements['application-identifier'])) throw Error('提供的原始描述文件与 Bundle ID 不匹配：'+id);
    const compatible = profiles.filter(x => x.p.TeamIdentifier && x.p.ApplicationIdentifierPrefix && x.p.Entitlements && x.p.TeamIdentifier[0]===b.old.TeamIdentifier[0] && x.p.ApplicationIdentifierPrefix[0]===b.old.ApplicationIdentifierPrefix[0] && allowed(x.p.ApplicationIdentifierPrefix[0]+'.'+id,x.p.Entitlements['application-identifier']));
    const candidates=[];
    for (const x of compatible) {
      const p=x.p, reason=[];
      if (!(new Date(p.ExpirationDate).getTime()>Date.now())) reason.push('描述文件已过期 '+new Date(p.ExpirationDate).toISOString());
      if (!(p.ProvisionedDevices || []).some(d=>d.toUpperCase()===udid.toUpperCase())) reason.push('未授权目标设备（仅支持 Development / Ad Hoc）');
      if (typeof p.Entitlements['get-task-allow']!=='boolean') reason.push('缺少有效的 get-task-allow');
      if (!(certs[x.index]||[]).some(c=>identities.includes(c))) reason.push('缺少匹配的有效证书私钥');
      let ent;
      try { ent=entitlements(b.requested,p,id); } catch(e) { reason.push(e.message); }
      report.push(id+' / '+p.Name+' / '+(reason.length?reason.join('；'):'可用'));
      if (!reason.length) candidates.push({x,ent});
    }
    if (!compatible.length) report.push(id+'：未找到同团队、同 App ID 的描述文件');
    return {b,candidates};
  });
  let choice=null;
  for (const identity of identities) {
    const selected=matches.map(m=>m.candidates.filter(c=>(certs[c.x.index]||[]).includes(identity)).sort((a,b)=>new Date(b.x.p.ExpirationDate)-new Date(a.x.p.ExpirationDate))[0]);
    if (selected.every(Boolean)) { choice={identity,selected}; break; }
  }
  write(root+'/report.txt',report.join('\n')+'\n');
  if (!choice) throw Error('预检失败：没有可同时签署全部 App/扩展的有效材料。请在 Xcode 更新对应团队、全部 target 的描述文件及证书。');
  const plan=[];
  matches.forEach((m,i)=>{
    const c=choice.selected[i];
    write(root+'/bundles/'+m.b.index+'/entitlements.json',JSON.stringify(c.ent));
    plan.push([m.b.index,c.x.index,choice.identity].join('\t'));
    report.push('采用：'+m.b.info.CFBundleIdentifier+'；有效至 '+new Date(c.x.p.ExpirationDate).toISOString());
  });
  write(root+'/plan.tsv',plan.join('\n')+'\n');
  write(root+'/identity.txt',choice.identity);
  write(root+'/report.txt',report.join('\n')+'\n');
  return '主 App 与扩展的描述文件、设备、证书及权限均已匹配。';
}
JXA
}
# 在任何实际签名前完成全部 bundle 的检查。
prepare_signing_plan() {
  log '── 签名材料检查 ──'
  local attempt answer
  for attempt in 0 1 2 3; do
    collect_profiles
    /bin/rm -f "$WORK_ROOT/plan.tsv" "$WORK_ROOT/report.txt"
    if /usr/bin/osascript -l JavaScript "$WORK_ROOT/plan.js" "$WORK_ROOT" "$TARGET_UDID" > "$WORK_ROOT/planner.log" 2>&1; then
      /bin/cat "$WORK_ROOT/report.txt" | /usr/bin/tee -a "$LOG_FILE"
      log 'ℹ 本机材料已齐备，无需启动 Xcode 或编译。'
      return 0
    fi
    [[ -f "$WORK_ROOT/report.txt" ]] && /bin/cat "$WORK_ROOT/report.txt" | /usr/bin/tee -a "$LOG_FILE"
    /bin/cat "$WORK_ROOT/planner.log" | /usr/bin/tee -a "$LOG_FILE"
    (( attempt < 3 )) || fail '三轮复检仍未通过；已停止。请按报告解决签名材料问题后重新运行。'
    log '⚠⚠ 签名材料不齐，暂停重签。打开 Xcode 只是第一步。'
    wait_for_xcode
    log '➤ 打开目标 IPA 对应工程；Settings → Accounts 登录原团队账号。'
    log '➤ 主 App 和每个扩展的 Signing & Capabilities 选择原 Team；免费账号使用 Automatically manage signing。'
    log '➤ 连接目标设备，确认其 UDID 已授权；等待签名刷新，必要时 Try Again 或 Run 一次，无需 Clean。'
    log '➤ 也可把有效 .mobileprovision 放入本脚本旁的“描述文件”目录；私钥仍必须在钥匙串。'
    read -r 'answer?完成刷新后输入 r 复检；直接回车或 q 退出：' || fail '输入已取消。'
    [[ "$answer" == r || "$answer" == R ]] || exit 0
  done
}
# 将全部嵌套动态代码从内到外签名，再分别签署扩展和主 App。
sign_payload() {
  log '── 重签 App 与扩展 ──'
  local identity="$(<"$WORK_ROOT/identity.txt")" item bundle_index profile_index planned_identity bundle
  log 'ℹ 预检通过，开始签署临时副本。'
  while IFS= read -r -d '' item; do
    if [[ -f "$item" ]]; then
      [[ "$(/usr/bin/file -b "$item")" == *Mach-O* ]] || continue
    elif [[ "$item" == *.bundle ]]; then
      [[ -f "$item/Info.plist" ]] || continue
      /usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$item/Info.plist" >/dev/null 2>&1 || continue
    elif [[ "$item" != *.framework ]]; then
      continue
    fi
    /usr/bin/codesign --force --sign "$identity" --generate-entitlement-der "$item" >> "$LOG_FILE" 2>&1 || fail "嵌套代码签名失败：$item"
  done < <(/usr/bin/find "$WORK_ROOT/unpacked/Payload" -depth \( -type f -o -type d -name '*.framework' -o -type d -name '*.bundle' \) -print0)
  while IFS=$'\t' read -r bundle_index profile_index planned_identity; do
    bundle="$(<"$WORK_ROOT/bundles/$bundle_index/path.txt")"
    /usr/bin/plutil -convert xml1 -o "$WORK_ROOT/bundles/$bundle_index/entitlements.plist" "$WORK_ROOT/bundles/$bundle_index/entitlements.json" || fail '权限转换失败。'
    /bin/cp "$WORK_ROOT/profiles/$profile_index.mobileprovision" "$bundle/embedded.mobileprovision" || fail '无法替换副本描述文件。'
    /usr/bin/codesign --force --sign "$planned_identity" --entitlements "$WORK_ROOT/bundles/$bundle_index/entitlements.plist" --generate-entitlement-der "$bundle" >> "$LOG_FILE" 2>&1 || fail "App/扩展签名失败：$bundle"
    /usr/bin/codesign --verify --deep --strict "$bundle" >> "$LOG_FILE" 2>&1 || fail "签名完整性失败：$bundle"
    # codesign 的文件输出会追加；标准输出重定向覆盖，并按 Target 隔离回读文件。
    /usr/bin/codesign -d --xml --entitlements - "$bundle" > "$WORK_ROOT/bundles/$bundle_index/actual.plist" 2>> "$LOG_FILE" || fail '无法回读签名权限。'
    /usr/bin/plutil -convert json -o "$WORK_ROOT/bundles/$bundle_index/actual.json" "$WORK_ROOT/bundles/$bundle_index/actual.plist" || fail '回读的签名权限无效。'
    /usr/bin/osascript -l JavaScript -e 'ObjC.import("Foundation"); function run(a){function read(p){return JSON.parse(ObjC.unwrap($.NSString.stringWithContentsOfFileEncodingError(p,$.NSUTF8StringEncoding,null)));} function norm(v){if(Array.isArray(v))return v.map(norm);if(v&&typeof v==="object"){let o={};Object.keys(v).sort().forEach(k=>o[k]=norm(v[k]));return o;}return v;}const actual=read(a[0]), expected=read(a[1]); const keys=Array.from(new Set(Object.keys(actual).concat(Object.keys(expected)))); const diff=keys.filter(k=>JSON.stringify(norm(actual[k]))!==JSON.stringify(norm(expected[k]))); if(diff.length)throw Error("签名权限差异键："+diff.join(", "));}' "$WORK_ROOT/bundles/$bundle_index/actual.json" "$WORK_ROOT/bundles/$bundle_index/entitlements.json" >> "$LOG_FILE" 2>&1 || fail "写入与回读的签名权限不一致：$bundle（差异键见日志）。"
    log "✔ 签名与权限回读一致：${bundle:t}"
  done < "$WORK_ROOT/plan.tsv"
}
# 同目录暂存并原子替换，复制或校验失败时不触碰原 IPA。
replace_verified_ipa() {
  REPLACEMENT_DIR=$(/usr/bin/mktemp -d "${IPA_PATH:h}/.jobs-ipa-replace.XXXXXX") || fail '原 IPA 目录不可写，无法替换。'
  /bin/cp "$1" "$REPLACEMENT_DIR/replacement.ipa" || fail '新 IPA 暂存失败，原包保留。'
  /usr/bin/cmp -s "$1" "$REPLACEMENT_DIR/replacement.ipa" || fail '新 IPA 复制校验失败，原包保留。'
  /bin/mv -f "$REPLACEMENT_DIR/replacement.ipa" "$IPA_PATH" || fail '原 IPA 替换失败。'
  IPA_REPLACED=1
  /bin/rmdir "$REPLACEMENT_DIR"
  REPLACEMENT_DIR=''
  log "✔ 已用重签后的 IPA 替换原文件：$IPA_PATH"
}
# 压缩后再次解包验证，成功后才替换原文件。
package_and_verify() {
  log '── 打包与最终验证 ──'
  /usr/bin/ditto -c -k --norsrc --keepParent "$WORK_ROOT/unpacked/Payload" "$WORK_ROOT/resigned.ipa" >> "$LOG_FILE" 2>&1 || fail '压缩 IPA 失败。'
  /usr/bin/unzip -t "$WORK_ROOT/resigned.ipa" >> "$LOG_FILE" 2>&1 || fail '最终 ZIP 校验失败。'
  /usr/bin/ditto -x -k "$WORK_ROOT/resigned.ipa" "$WORK_ROOT/verify" >> "$LOG_FILE" 2>&1 || fail '最终解包复验失败。'
  local app
  for app in "$WORK_ROOT/verify/Payload/"*.app(N/); do
    /usr/bin/codesign --verify --deep --strict "$app" >> "$LOG_FILE" 2>&1 || fail '最终 IPA 签名复验失败。'
  done
  replace_verified_ipa "$WORK_ROOT/resigned.ipa"
  log 'ℹ 本地签名与压缩校验已通过；尚未安装到手机，最终以 iOS 安装验证为准。'
  log 'ℹ 即将询问是否直接安装；开发签名在适用系统上需要开启开发者模式。'
}
# 调用 Xcode 设备安装工具，保留原始错误与结构化安装结果。
run_device_install() {
  /usr/bin/xcrun devicectl device install app --device "$TARGET_UDID" "$1" --timeout 180 --json-output "$WORK_ROOT/install-result.json"
}
# 回车才安装；任意字符均结束，不再追加关闭窗口确认。
confirm_and_install() {
  local answer app
  local -a apps
  log '── 安装到手机 ──'
  log "ℹ 安装目标设备：$TARGET_UDID"
  log "ℹ 已重签 IPA：$IPA_PATH"
  IFS= read -r 'answer?直接回车确认安装；输入任意字符结束脚本：' < /dev/tty || { FINISH_WAIT=0; exit 0; }
  if [[ -n "$answer" ]]; then
    log 'ℹ 已跳过安装，重签后的 IPA 已保留。'
    FINISH_WAIT=0
    exit 0
  fi
  apps=("$WORK_ROOT/verify/Payload/"*.app(N/))
  (( ${#apps} == 1 )) || fail '无法唯一定位最终 IPA 中已验证的 App。'
  app="${apps[1]}"
  log 'ℹ 开始安装，请保持手机连接并解锁；如果设备询问信任，请在设备上确认。'
  if ! run_device_install "$app" 2>&1 | /usr/bin/tee -a "$LOG_FILE"; then
    fail '设备安装未成功或超时，具体原因见上方工具输出；重签 IPA 保留，不自动卸载旧 App。'
  fi
  /usr/bin/osascript -l JavaScript -e 'ObjC.import("Foundation"); function run(a){const s=ObjC.unwrap($.NSString.stringWithContentsOfFileEncodingError(a[0],$.NSUTF8StringEncoding,null));const result=JSON.parse(s);if(!result.info || result.info.outcome!=="success")throw Error("未获得明确的安装成功结果");}' "$WORK_ROOT/install-result.json" >> "$LOG_FILE" 2>&1 || fail '无法确认安装成功，请检查设备；重签 IPA 保留。'
  log "✔ 安装成功，目标设备：$TARGET_UDID"
}
# 编排交互、完整预检、重签与最终交付。
main() {
  show_script_intro_and_wait # 先展示范围并等待确认。
  initialize_runtime "$@" # 建立日志与临时副本上下文。
  select_input # 接收拖入的 IPA 与目标设备 UDID。
  check_environment # 检查系统工具和可用证书私钥。
  unpack_ipa # 解包并恢复每个 App 的权限请求。
  inspect_payload # 拦截加密包与不支持的嵌套代码。
  write_planner # 准备原生 plist 权限与授权检查器。
  prepare_signing_plan # 材料全部合格后才允许签名。
  sign_payload # 按嵌套顺序分别签名并回读验证。
  package_and_verify # 对最终 IPA 复验并替换原文件。
  confirm_and_install # 回车确认后安装到已选设备，任意字符结束。
}

main "$@"
