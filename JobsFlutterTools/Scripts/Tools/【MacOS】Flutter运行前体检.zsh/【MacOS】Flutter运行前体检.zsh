#!/bin/zsh
# Created by Jobs on 2026年11月10日，星期二.
# 内部只读模块：在设备选择前汇总工具链，运行前按目标平台阻止带病启动。
# 由运行器提供 PROJECT_PATH、FLUTTER_BIN、LOG_FILE、log 与 run_bounded；不单独执行。

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

typeset -gA JOBS_PREFLIGHT_STATE JOBS_PREFLIGHT_DETAIL
typeset -gA JOBS_PREFLIGHT_REPORTED_STATE JOBS_PREFLIGHT_REPORTED_DETAIL
JOBS_PREFLIGHT_REPORT_SCOPE=""
JOBS_PREFLIGHT_OUTPUT=""
JOBS_PREFLIGHT_SDK=""
JOBS_PREFLIGHT_DART=""
JOBS_PREFLIGHT_HELPER=""
JOBS_PREFLIGHT_DOCTOR_HELPER=""
JOBS_PREFLIGHT_DOCTOR=""
JOBS_PREFLIGHT_BUILD=""
JOBS_PREFLIGHT_READY=0
JOBS_PREFLIGHT_FINGERPRINT=""
JOBS_PREFLIGHT_HDC=""
JOBS_PREFLIGHT_HDC_DISCOVERY_DETAIL=""

jobs_fpf_fail() {
  local platform="$1" reason="$2"
  JOBS_PREFLIGHT_STATE[$platform]=failed
  if [[ -n "${JOBS_PREFLIGHT_DETAIL[$platform]:-}" ]]; then
    JOBS_PREFLIGHT_DETAIL[$platform]+=$'\n'
  fi
  JOBS_PREFLIGHT_DETAIL[$platform]+="$reason"
}
# 分行展示缺项，原始探针输出仍留在独立日志中供排查。
jobs_fpf_report() {
  local platform="$1" line="" detail="${JOBS_PREFLIGHT_DETAIL[$1]:-未完成检查}"
  if [[ "${JOBS_PREFLIGHT_STATE[$platform]:-failed}" == passed ]]; then
    log "✓ $platform：环境检查通过（仍需设备及实际构建验证）。"
    return 0
  fi
  log "✖ $platform：未就绪。"
  detail="${detail//；/$'\n'}"
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    if [[ "$line" == *'execution error: Error: Error: '* ]]; then
      line="${line#*execution error: Error: Error: }"
    fi
    line="${line% (-2700)}"
    log "✖   $line"
  done <<< "$detail"
}
# 展示快照只属于当前工程和SDK身份，工具路径变化不等同无关平台结果变化。
jobs_fpf_report_scope() {
  local item="" root="${JOBS_PREFLIGHT_SDK:-${FLUTTER_BIN:A:h:h}}"
  print -r -- "${PROJECT_PATH:A}" "${FLUTTER_BIN:A}" "${root:A}"
  for item in .fvmrc .fvm/fvm_config.json; do
    if [[ -f "$PROJECT_PATH/$item" ]]; then
      /usr/bin/cksum "$PROJECT_PATH/$item" || return 1
    else
      print -r -- "missing:$item"
    fi
  done
  for item in bin/cache/flutter_tools.snapshot bin/cache/dart-sdk/bin/dart bin/internal/engine.version; do
    if [[ -e "$root/$item" ]]; then
      /usr/bin/stat -f '%d:%i:%z:%m:%c' "$root/$item" || return 1
    else
      print -r -- "missing:$item"
    fi
  done
}
# 每轮仍真实复检；仅折叠同一工程/SDK下未变化的展示，不复用健康判断。
jobs_fpf_report_updates() {
  local platform="" scope="" changed=0
  scope="$(jobs_fpf_report_scope)" || return $?
  if [[ "$scope" != "$JOBS_PREFLIGHT_REPORT_SCOPE" ]]; then
    JOBS_PREFLIGHT_REPORTED_STATE=()
    JOBS_PREFLIGHT_REPORTED_DETAIL=()
    JOBS_PREFLIGHT_REPORT_SCOPE="$scope"
  fi
  for platform in ios android ohos; do
    if [[ "${JOBS_PREFLIGHT_REPORTED_STATE[$platform]:-}" == "${JOBS_PREFLIGHT_STATE[$platform]:-failed}" &&
          "${JOBS_PREFLIGHT_REPORTED_DETAIL[$platform]:-}" == "${JOBS_PREFLIGHT_DETAIL[$platform]:-}" ]]; then
      continue
    fi
    jobs_fpf_report "$platform"
    JOBS_PREFLIGHT_REPORTED_STATE[$platform]="${JOBS_PREFLIGHT_STATE[$platform]:-failed}"
    JOBS_PREFLIGHT_REPORTED_DETAIL[$platform]="${JOBS_PREFLIGHT_DETAIL[$platform]:-}"
    (( changed += 1 ))
  done
  (( changed > 0 )) || log 'ℹ 体检结果未变化，不重复展开；运行前仍会复核所选平台。'
  return 0
}
jobs_fpf_probe() {
  local name="$1" seconds="$2" result=0 output="$LOG_FILE.preflight.$1"
  shift 2
  run_bounded "$seconds" "$output" "$@" || result=$?
  JOBS_PREFLIGHT_OUTPUT="$(/bin/cat "$output" 2>/dev/null)"
  return "$result"
}

# 设备发现不要求整套编译工具已就绪；显式工具目录优先且不悄悄换成另一套 SDK。
jobs_fpf_find_harmony_hdc() {
  local candidate="" root="" sdk="" configured="${DEVECO_STUDIO_HOME:-${TOOL_HOME:-}}" scope='自动范围：PATH 及标准 DevEco/CLT 目录'
  local -a roots=() sdk_roots=() candidates=() matches=()
  REPLY=""
  JOBS_PREFLIGHT_HDC_DISCOVERY_DETAIL=""
  if [[ -n "$JOBS_PREFLIGHT_HDC" && -x "$JOBS_PREFLIGHT_HDC" && ! -d "$JOBS_PREFLIGHT_HDC" ]]; then
    REPLY="${JOBS_PREFLIGHT_HDC:A}"
    return 0
  fi
  if [[ -n "${OHOS_SDK_HOME:-}" ]]; then
    sdk_roots=("$OHOS_SDK_HOME")
    scope="指定范围：OHOS_SDK_HOME=$OHOS_SDK_HOME"
  elif [[ -n "${DEVECO_SDK_HOME:-}" ]]; then
    sdk_roots=("$DEVECO_SDK_HOME")
    scope="指定范围：DEVECO_SDK_HOME=$DEVECO_SDK_HOME"
  elif [[ -n "$configured" ]]; then
    [[ "$configured" != *.app ]] || configured+='/Contents'
    roots=("$configured")
    scope="指定范围：DevEco/CLT=$configured"
  elif [[ -n "${commands[hdc]:-}" && -x "${commands[hdc]}" && ! -d "${commands[hdc]}" ]]; then
    REPLY="${commands[hdc]:A}"
    return 0
  else
    roots=(/Applications/DevEco*.app/Contents(N/) "$HOME"/Applications/DevEco*.app/Contents(N/)
      "$HOME"/Library/Application\ Support/JobsHarmonySimulator/clt-*(N/))
  fi
  for root in "${roots[@]}"; do
    candidates+=("$root/bin/hdc" "$root/tools/hdc")
    sdk_roots+=("$root/sdk")
  done
  for sdk in "${sdk_roots[@]}"; do
    candidates+=("$sdk/toolchains/hdc" "$sdk/default/openharmony/toolchains/hdc" "$sdk/openharmony/toolchains/hdc"
      "$sdk/default/harmonyos/toolchains/hdc" "$sdk/harmonyos/toolchains/hdc"
      "$sdk"/[0-9]*/toolchains/hdc(N) "$sdk"/[0-9]*/openharmony/toolchains/hdc(N))
  done
  for candidate in "${candidates[@]}"; do
    [[ -x "$candidate" && ! -d "$candidate" ]] || continue
    matches+=("${candidate:A}")
  done
  matches=("${(@u)matches}")
  if (( ${#matches} == 1 )); then
    REPLY="$matches[1]"
    return 0
  fi
  if (( ${#matches} > 1 )); then
    JOBS_PREFLIGHT_HDC_DISCOVERY_DETAIL="发现多个 HDC，未猜测工具版本；请通过 OHOS_SDK_HOME 或 DEVECO_SDK_HOME 指定本轮 SDK。$scope；候选：${(j:；:)matches}"
  else
    JOBS_PREFLIGHT_HDC_DISCOVERY_DETAIL="未找到可执行 HDC；$scope；继续读取 USB 调试节点。"
  fi
  return 1
}

# Flutter 未支持的平台仍显示原生连接证据；两条取证链独立，失败原文保留在本轮日志。
jobs_flutter_harmony_discovery_rows() {
  local usb="$LOG_FILE.harmony-usb.plist" visible="$LOG_FILE.harmony-visible.ids" targets="$LOG_FILE.harmony-hdc.targets"
  local evidence="$LOG_FILE.harmony-discovery" hdc="" row="" rows="" summary="" usable_usb="" usable_targets=""
  local helper="$JOBS_PREFLIGHT_HELPER"
  local hdc_result=0 usb_result=0 parse_result=0
  local -a diagnostic_rows=()
  [[ -n "$helper" ]] || helper="$(jobs_layout_file "${${(%):-%x}:A:h}/Flutter运行前体检.jxa")"
  [[ -s "$helper" && ! -L "$helper" ]] || { log "✖ 缺少鸿蒙连接取证模块：$helper" >&2; return 1; }
  : > "$evidence" || return 1
  : > "$visible" || return 1
  for row in "$@"; do
    print -r -- "${row%%$'\t'*}" >> "$visible" || return 1
  done
  : > "$targets" || return 1
  if jobs_fpf_find_harmony_hdc; then
    hdc="$REPLY"
    print -r -- "HDC 路径：$hdc" >> "$evidence"
    run_bounded 8 "$targets" "$hdc" list targets >> "$LOG_FILE" 2>&1 || hdc_result=$?
    print -r -- "HDC list targets 退出码：$hdc_result；原始输出：$targets" >> "$evidence"
    (( hdc_result != 130 && hdc_result != 143 )) || return "$hdc_result"
    if (( hdc_result == 0 )); then
      usable_targets="$targets"
      summary="$(/usr/bin/osascript -l JavaScript "$helper" hdc-status "$targets" 2>> "$LOG_FILE")" || return $?
      print -r -- "$summary" >> "$evidence"
      [[ "$summary" != *'⚠'* ]] || log "$summary" >&2
    else
      log "⚠ HDC 目标查询失败（退出码 $hdc_result），未将错误输出当作设备；继续读取 USB。原始输出：$targets" >&2
    fi
  else
    print -r -- "$JOBS_PREFLIGHT_HDC_DISCOVERY_DETAIL" >> "$evidence"
    log "ℹ $JOBS_PREFLIGHT_HDC_DISCOVERY_DETAIL" >&2
  fi
  # USB 身份与调试授权分别识别；HDC 未安装时仍能显示已连接的物理设备。
  run_bounded 8 "$usb" /usr/sbin/ioreg -p IOUSB -a -l >> "$LOG_FILE" 2>&1 || usb_result=$?
  print -r -- "USB ioreg 退出码：$usb_result；原始输出：$usb" >> "$evidence"
  (( usb_result != 130 && usb_result != 143 )) || return "$usb_result"
  if (( usb_result == 0 )); then
    usable_usb="$usb"
  else
    log "⚠ USB 调试节点读取失败（退出码 $usb_result），仍保留已确认 HDC 目标；未据此判断手机未连接。详情：$evidence" >&2
  fi
  rows="$(/usr/bin/osascript -l JavaScript "$helper" usb-harmony "$usable_usb" "$visible" "$usable_targets" 2>> "$LOG_FILE")" || parse_result=$?
  if (( parse_result != 0 )) && [[ -n "$usable_usb" ]]; then
    print -r -- "USB/设备清单解析退出码：$parse_result；解析错误：$LOG_FILE" >> "$evidence"
    log "⚠ USB/设备清单解析失败，尝试保留已确认 HDC 目标；详情：$evidence" >&2
    rows="$(/usr/bin/osascript -l JavaScript "$helper" usb-harmony '' "$visible" "$usable_targets" 2>> "$LOG_FILE")" || return $?
  elif (( parse_result != 0 )); then
    return "$parse_result"
  fi
  if [[ -z "$rows" ]]; then
    print -r -- '未发现尚未列出的明确 HDC 连接证据；仅品牌 USB 节点不认作鸿蒙，开发者模式不等于 USB 调试授权。' >> "$evidence"
  else
    diagnostic_rows=("${(@f)rows}")
    print -r -- "诊断行数：${#diagnostic_rows}；诊断标识不能作为 Flutter 设备 ID。" >> "$evidence"
    print -r -- "$rows"
  fi
  print -r -- "鸿蒙连接取证：$evidence" >> "$LOG_FILE"
  return 0
}

# 菜单停留期间可能切换 SDK 或修改工程；只保存摘要，不记录配置正文。
jobs_fpf_fingerprint() {
  local item=""
  {
    print -r -- "$PROJECT_PATH" "${FLUTTER_BIN:A}" "${DEVECO_STUDIO_HOME:-}" "${TOOL_HOME:-}" "${DEVECO_SDK_HOME:-}" "${OHOS_SDK_HOME:-}" "${JAVA_HOME:-}" "$PATH"
    for item in pubspec.yaml .fvmrc .fvm/fvm_config.json .dart_tool/package_config.json; do
      if [[ -f "$PROJECT_PATH/$item" ]]; then
        /usr/bin/cksum "$PROJECT_PATH/$item" || return 1
      else
        print -r -- "missing:$item"
      fi
    done
    for item in bin/cache/flutter_tools.snapshot bin/cache/flutter.version.json bin/cache/dart-sdk/bin/dart packages/flutter_tools/.dart_tool/package_config.json; do
      /usr/bin/stat -f '%d:%i:%z:%m:%c' "$JOBS_PREFLIGHT_SDK/$item" || return 1
    done
  } | /usr/bin/shasum -a 256
}

# 直接执行已就绪的同源工具快照，避免 Flutter Shell shim 在体检中下载 SDK。
jobs_fpf_flutter() {
  FLUTTER_ROOT="$JOBS_PREFLIGHT_SDK" PATH="$JOBS_PREFLIGHT_SDK/bin:$PATH" "$JOBS_PREFLIGHT_DART" --disable-dart-dev \
    "--packages=$JOBS_PREFLIGHT_SDK/packages/flutter_tools/.dart_tool/package_config.json" \
    "$JOBS_PREFLIGHT_SDK/bin/cache/flutter_tools.snapshot" --suppress-analytics --no-version-check "$@"
}

# 只调用同源 SDK 的本地官方验证器，完整 JSON 才是结论；公网连通性不混入运行环境门禁。
jobs_fpf_doctor() {
  local scope="${1:-all}" output="$2" result=0
  run_bounded 45 "$output" /usr/bin/env "FLUTTER_ROOT=$JOBS_PREFLIGHT_SDK" "PATH=$JOBS_PREFLIGHT_SDK/bin:$PATH" \
    "$JOBS_PREFLIGHT_DART" --disable-dart-dev \
    "--packages=$JOBS_PREFLIGHT_SDK/packages/flutter_tools/.dart_tool/package_config.json" "$JOBS_PREFLIGHT_DOCTOR_HELPER" "$scope" || result=$?
  (( result == 0 || result == 1 )) || return "$result"
  JOBS_PREFLIGHT_DOCTOR="$(/usr/bin/osascript -l JavaScript "$JOBS_PREFLIGHT_HELPER" doctor "$output")" || return 2
  return "$result"
}

jobs_fpf_section() {
  local title="$1"
  print -r -- "$JOBS_PREFLIGHT_DOCTOR" | /usr/bin/awk -v title="$title" '
    /^\[[^]]+\]/ { active = index($0, "] " title) > 0 }
    active { print }
  '
}

jobs_fpf_doctor_platform() {
  local platform="$1" title="$2" section="" first=""
  section="$(jobs_fpf_section "$title")"
  first="${section%%$'\n'*}"
  if [[ "$first" != '[✓]'* && "$first" != '[√]'* ]]; then
    jobs_fpf_fail "$platform" "${section:-doctor 未返回 $title 检查结果}"
  fi
}

jobs_fpf_build_capability() {
  local platform="$1" target="$2"
  print -r -- "$JOBS_PREFLIGHT_BUILD" | /usr/bin/grep -Eq "^[[:space:]]*${target}[[:space:]]" ||
    jobs_fpf_fail "$platform" "当前工程 SDK 没有 flutter build $target 能力"
}

jobs_fpf_find_harmony_root() {
  local candidate="" configured="${DEVECO_STUDIO_HOME:-${TOOL_HOME:-}}"
  local -a candidates=()
  REPLY=""
  if [[ -n "$configured" ]]; then
    [[ "$configured" == *.app ]] && configured+='/Contents'
    candidates=("$configured")
  else
    candidates=(/Applications/DevEco*.app/Contents(N/) "$HOME"/Applications/DevEco*.app/Contents(N/)
      "$HOME"/Library/Application\ Support/JobsHarmonySimulator/clt-*(N/))
  fi
  for candidate in "${candidates[@]}"; do
    [[ -d "$candidate/sdk" ]] || continue
    [[ -z "$REPLY" ]] || { jobs_fpf_fail ohos '存在多个 DevEco/CLT，请通过 DEVECO_STUDIO_HOME 指定本次工具链'; REPLY=""; return 1; }
    REPLY="${candidate:A}"
  done
  [[ -n "$REPLY" ]] || { jobs_fpf_fail ohos '未找到 DevEco/CLT 及配套 SDK；选中有连接证据的鸿蒙设备后，在当前运行流程准备环境'; return 1; }
}

jobs_fpf_find_harmony_tool() {
  local name="$1" root="$2" sdk="$3" candidate="" directory=""
  REPLY=""
  local -a candidates=()
  if [[ "$name" == hvigorw && -f "$PROJECT_PATH/ohos/hvigorw" && ! -L "$PROJECT_PATH/ohos/hvigorw" ]]; then
    REPLY="$PROJECT_PATH/ohos/hvigorw"
    return 0
  fi
  [[ "$name" != java || -z "${JAVA_HOME:-}" ]] || candidates+=("$JAVA_HOME/bin/java")
  for directory in node/bin node tools/node/bin tools/node ohpm/bin tools/ohpm/bin hvigor/bin tools/hvigor/bin jbr/Contents/Home/bin jbr/bin bin ''; do
    candidates+=("$root/${directory:+$directory/}$name")
  done
  candidates+=("$sdk/toolchains/$name" "${commands[$name]:-}")
  for candidate in "${candidates[@]}"; do
    [[ -n "$candidate" && -x "$candidate" && ! -d "$candidate" ]] || continue
    REPLY="${candidate:A}"
    return 0
  done
  return 1
}

jobs_fpf_harmony() {
  local root="" sdk="" part="" name="" argument="" executable="" node="" result=0
  jobs_fpf_build_capability ohos hap
  for part in build-profile.json5 oh-package.json5 AppScope/app.json5; do
    [[ -f "$PROJECT_PATH/ohos/$part" ]] || jobs_fpf_fail ohos "缺少 ohos/$part"
  done
  [[ -f "$PROJECT_PATH/ohos/hvigorfile.ts" || -f "$PROJECT_PATH/ohos/hvigorfile.js" ]] || jobs_fpf_fail ohos '缺少 ohos/hvigorfile'
  if jobs_fpf_find_harmony_root; then
    root="$REPLY"
    sdk="${OHOS_SDK_HOME:-${DEVECO_SDK_HOME:-$root/sdk}/default/openharmony}"
    for part in ets native toolchains; do
      [[ -d "$sdk/$part" ]] || jobs_fpf_fail ohos "Harmony SDK 缺少 $part：$sdk"
    done
    for name in node ohpm hvigorw hdc java; do
      if ! jobs_fpf_find_harmony_tool "$name" "$root" "$sdk"; then
        jobs_fpf_fail ohos "缺少 $name"
        continue
      fi
      executable="$REPLY"
      argument=--version
      [[ "$name" != hdc ]] || argument=-v
      [[ "$name" != java ]] || argument=-version
      [[ "$name" != node ]] || node="$executable"
      [[ "$name" != hdc ]] || JOBS_PREFLIGHT_HDC="$executable"
      result=0
      if [[ "$name" == hvigorw && "$executable" == "$PROJECT_PATH/ohos/hvigorw" ]]; then
        jobs_fpf_probe "ohos-$name" 20 /usr/bin/env "PATH=${node:+${node:h}:}${PATH}" /bin/sh -c \
          'cd -- "$1" && exec /bin/sh "$2" "$3"' sh "$PROJECT_PATH/ohos" "$executable" "$argument" || result=$?
      else
        jobs_fpf_probe "ohos-$name" 20 /usr/bin/env \
          "PATH=${node:+${node:h}:}${PATH}" "$executable" "$argument" || result=$?
      fi
      if (( result != 0 )) || [[ -z "$JOBS_PREFLIGHT_OUTPUT" ]]; then
        jobs_fpf_fail ohos "$name 版本检查失败（退出码 $result），详情：$LOG_FILE.preflight.ohos-$name"
      elif [[ "$name" == java ]] && ! print -r -- "$JOBS_PREFLIGHT_OUTPUT" | /usr/bin/grep -Eq 'version "(17|2[1-9]|[3-9][0-9])([.\"]|$)'; then
        jobs_fpf_fail ohos 'Harmony Java 版本无法确认兼容，至少需要配套 JDK 17'
      fi
    done
  fi
  result=0
  jobs_fpf_probe ohos-plugins 20 /usr/bin/osascript -l JavaScript "$JOBS_PREFLIGHT_HELPER" ohos "$PROJECT_PATH" "$JOBS_PREFLIGHT_SDK" || result=$?
  (( result == 0 )) || jobs_fpf_fail ohos "${JOBS_PREFLIGHT_OUTPUT:-无法核验依赖与原生插件的 OpenHarmony 支持}"
}

jobs_flutter_preflight_overview() {
  local doctor_result=0 build_result=0 common_result=0 platform="" reason="" section=""
  JOBS_PREFLIGHT_READY=0
  JOBS_PREFLIGHT_HDC=""
  JOBS_PREFLIGHT_STATE=()
  JOBS_PREFLIGHT_DETAIL=()
  for platform in ios android ohos macos web; do
    JOBS_PREFLIGHT_STATE[$platform]=passed
    JOBS_PREFLIGHT_DETAIL[$platform]=""
  done
  JOBS_PREFLIGHT_SDK="${FLUTTER_BIN:A:h:h}"
  JOBS_PREFLIGHT_DART="$JOBS_PREFLIGHT_SDK/bin/cache/dart-sdk/bin/dart"
  JOBS_PREFLIGHT_HELPER="$(jobs_layout_file "${${(%):-%x}:A:h}/Flutter运行前体检.jxa")"
  JOBS_PREFLIGHT_DOCTOR_HELPER="$(jobs_layout_directory "$JOBS_PREFLIGHT_HELPER")/DoctorScope.dart"
  log '▶ 运行前环境健康体检：iOS / Android / OpenHarmony；不下载、切换 SDK 或改写工程。'
  if [[ ! -x "$JOBS_PREFLIGHT_DART" || ! -s "$JOBS_PREFLIGHT_SDK/bin/cache/flutter_tools.snapshot" ||
        ! -s "$JOBS_PREFLIGHT_SDK/packages/flutter_tools/.dart_tool/package_config.json" || ! -s "$JOBS_PREFLIGHT_HELPER" || ! -s "$JOBS_PREFLIGHT_DOCTOR_HELPER" ]]; then
    for platform in ios android ohos macos web; do jobs_fpf_fail "$platform" '同源 Dart、Flutter 工具快照或体检资源未就绪'; done
  else
    JOBS_PREFLIGHT_DOCTOR=""
    jobs_fpf_doctor all "$LOG_FILE.preflight.doctor" || doctor_result=$?
    log "  Flutter 本地官方验证器退出码：$doctor_result；完整结果：$LOG_FILE.preflight.doctor"
    jobs_fpf_probe build 30 jobs_fpf_flutter build -h || build_result=$?
    JOBS_PREFLIGHT_BUILD="$JOBS_PREFLIGHT_OUTPUT"
    # warning=1 表示某些平台有缺项，按已完整返回的结果判断；其它失败不得使用半成品。
    section="$(jobs_fpf_section Flutter)"
    if (( doctor_result != 0 && doctor_result != 1 )) || [[ "$section" != '[✓]'* && "$section" != '[√]'* ]] || (( build_result != 0 )); then
      for platform in ios android ohos macos web; do jobs_fpf_fail "$platform" "Flutter 基础检查失败（doctor=$doctor_result，build=$build_result），请查看体检日志"; done
    fi
    jobs_fpf_probe packages 20 /usr/bin/osascript -l JavaScript "$JOBS_PREFLIGHT_HELPER" packages "$PROJECT_PATH" "$JOBS_PREFLIGHT_SDK" || common_result=$?
    if (( common_result != 0 )); then
      reason="${JOBS_PREFLIGHT_OUTPUT:-依赖解析记录缺失或无法读取，请先拉取依赖}"
      for platform in ios android ohos macos web; do jobs_fpf_fail "$platform" "$reason"; done
    fi
    for platform in ios android macos web; do
      [[ -d "$PROJECT_PATH/$platform" ]] || jobs_fpf_fail "$platform" "项目未配置 $platform/ 平台目录"
    done
    jobs_fpf_doctor_platform ios Xcode
    jobs_fpf_doctor_platform macos Xcode
    jobs_fpf_doctor_platform android 'Android toolchain'
    jobs_fpf_doctor_platform web Chrome
    jobs_fpf_build_capability ios ios
    jobs_fpf_build_capability android apk
    jobs_fpf_build_capability macos macos
    jobs_fpf_build_capability web web
    jobs_fpf_harmony
  fi
  jobs_fpf_report_updates || return $?
  JOBS_PREFLIGHT_READY=1
  JOBS_PREFLIGHT_FINGERPRINT="$(jobs_fpf_fingerprint)" || { JOBS_PREFLIGHT_READY=0; log '✖ 无法保存本轮 SDK 与工程检查摘要，停止运行。'; return 1; }
  return 0
}

jobs_flutter_preflight_require() {
  local platform="$1" device="${2:-}" result=0 current="" title="" section=""
  [[ "$platform" != darwin ]] || platform=macos
  [[ "$platform" != openharmony && "$platform" != harmony ]] || platform=ohos
  if [[ "$JOBS_PREFLIGHT_READY" != 1 ]]; then
    log '✖ 本轮环境体检未完成，停止运行。'
    return 1
  fi
  if [[ "${JOBS_PREFLIGHT_STATE[$platform]:-failed}" != passed ]]; then
    log "✖ $platform 环境未就绪，未启动设备 $device。${JOBS_PREFLIGHT_DETAIL[$platform]:-未识别或未完成此平台的健康检查}"
    return 1
  fi
  current="$(jobs_fpf_fingerprint)" || { log '✖ 无法复核 SDK 与工程状态，停止运行。'; return 1; }
  [[ "$current" == "$JOBS_PREFLIGHT_FINGERPRINT" ]] || { log '✖ 体检后 SDK、工程声明、依赖索引或工具链环境已变化，请重新进入运行入口完成体检。'; return 1; }
  [[ -d "$PROJECT_PATH/$platform" ]] || { log "✖ $platform/ 平台目录已移除，停止运行。"; return 1; }
  jobs_fpf_probe selected-packages 20 /usr/bin/osascript -l JavaScript "$JOBS_PREFLIGHT_HELPER" packages "$PROJECT_PATH" "$JOBS_PREFLIGHT_SDK" || result=$?
  (( result == 0 )) || { log "✖ 运行前依赖复核失败：$JOBS_PREFLIGHT_OUTPUT"; return 1; }
  case "$platform" in
    ios|macos) title=Xcode ;;
    android) title='Android toolchain' ;;
    web) title=Chrome ;;
  esac
  if [[ -n "$title" ]]; then
    log "▶ 运行前复核 $platform 工具链；详情：$LOG_FILE.preflight.selected-doctor"
    result=0
    JOBS_PREFLIGHT_DOCTOR=""
    jobs_fpf_doctor "$platform" "$LOG_FILE.preflight.selected-doctor" || result=$?
    section="$(jobs_fpf_section Flutter)"
    if (( result != 0 && result != 1 )) || [[ "$section" != '[✓]'* && "$section" != '[√]'* ]]; then
      log "✖ 运行前 Flutter 工具链复核失败（退出码 $result），停止运行。"
      return 1
    fi
    jobs_fpf_doctor_platform "$platform" "$title"
    [[ "${JOBS_PREFLIGHT_STATE[$platform]}" == passed ]] || { log "✖ $platform 运行前工具链复核失败：${JOBS_PREFLIGHT_DETAIL[$platform]}"; return 1; }
  fi
  if [[ "$platform" == ohos ]]; then
    jobs_fpf_harmony
    [[ "${JOBS_PREFLIGHT_STATE[ohos]}" == passed ]] || { log "✖ OpenHarmony 运行前复核失败：${JOBS_PREFLIGHT_DETAIL[ohos]}"; return 1; }
    result=0
    jobs_fpf_probe selected-hdc 15 "$JOBS_PREFLIGHT_HDC" list targets || result=$?
    (( result == 0 )) && [[ -n "$device" ]] && print -r -- "$JOBS_PREFLIGHT_OUTPUT" | /usr/bin/grep -Fxq -- "$device" || {
      log '✖ 所选鸿蒙设备未在 HDC 授权连接列表中，请在手机确认 USB 调试授权并重新加载设备。'
      return 1
    }
  fi
  log "✓ $platform 运行前体检通过；继续核验设备与运行。"
}
