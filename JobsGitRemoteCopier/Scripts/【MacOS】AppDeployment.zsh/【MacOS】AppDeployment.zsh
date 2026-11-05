#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS】AppDeployment.zsh（Finder 扩展部署函数库）。
# - 核心用途：选择构建目录或应用程序目录，完整部署、回滚和精确卸载自有 App。
# - 影响范围：仅调用安装 / 卸载函数才改动所选 App；不会自动提权、重启 Finder 或结束进程。
# - 运行提示：由已确认操作的管理器 source；调用者在登记成功后 commit，失败时 rollback。
# shell: zsh

typeset -g JOBS_DEPLOYMENT_TRANSACTION_DIR="${JOBS_DEPLOYMENT_TRANSACTION_DIR:-}"
typeset -g JOBS_DEPLOYMENT_TRANSACTION_ROOT="${JOBS_DEPLOYMENT_TRANSACTION_ROOT:-}"
typeset -g JOBS_DEPLOYMENT_TRANSACTION_TARGET="${JOBS_DEPLOYMENT_TRANSACTION_TARGET:-}"
typeset -g JOBS_DEPLOYMENT_TRANSACTION_APP_ID="${JOBS_DEPLOYMENT_TRANSACTION_APP_ID:-}"
typeset -g JOBS_DEPLOYMENT_TRANSACTION_EXTENSION_NAME="${JOBS_DEPLOYMENT_TRANSACTION_EXTENSION_NAME:-}"
typeset -g JOBS_DEPLOYMENT_TRANSACTION_EXTENSION_ID="${JOBS_DEPLOYMENT_TRANSACTION_EXTENSION_ID:-}"
typeset -g JOBS_DEPLOYMENT_TRANSACTION_LOCK="${JOBS_DEPLOYMENT_TRANSACTION_LOCK:-}"
typeset -g JOBS_DEPLOYMENT_TRANSACTION_IDENTITY="${JOBS_DEPLOYMENT_TRANSACTION_IDENTITY:-}"
typeset -g JOBS_DEPLOYMENT_TARGET_IDENTITY="${JOBS_DEPLOYMENT_TARGET_IDENTITY:-}"
typeset -g JOBS_DEPLOYMENT_REGISTRATION_ONLY="${JOBS_DEPLOYMENT_REGISTRATION_ONLY:-0}"
typeset -g JOBS_DEPLOYMENT_MODULE_DIRECTORY="${${(%):-%x}:A:h}"
typeset -g JOBS_DEPLOYMENT_TRANSACTION_SOURCE="${JOBS_DEPLOYMENT_TRANSACTION_SOURCE:-}"
typeset -g JOBS_DEPLOYMENT_TRANSACTION_LEGACY_PATH="${JOBS_DEPLOYMENT_TRANSACTION_LEGACY_PATH:-}"
typeset -g JOBS_DEPLOYMENT_PREPARED_REGISTRATION="${JOBS_DEPLOYMENT_PREPARED_REGISTRATION:-0}"
typeset -ga JOBS_DEPLOYMENT_COMMITTED_RECEIPT
typeset -ga JOBS_DEPLOYMENT_PREVIOUS_APPS

# 只写调用者预建的私有控制旗标；nofollow 和句柄身份复核避免路径替换误写其它文件。
jobs_deployment_mark_app_management_blocked() (
  local control_file="${JOBS_FINDER_BLOCKED_FILE:-}" control_dir="" control_fd="" result=0
  local -A directory_stat opened_directory_stat file_stat descriptor_stat
  [[ -n "$control_file" && "$control_file" == /* && "$control_file" == "${control_file:a}" &&
     "${control_file:t}" == app-management.blocked && -f "$control_file" && ! -L "$control_file" ]] || return 1
  control_dir="${control_file:h}"
  [[ "${control_dir:t}" == JobsFinderControl.?* && -d "$control_dir" && ! -L "$control_dir" ]] || return 1
  zmodload -F zsh/stat b:zstat || return 1
  zmodload zsh/system || return 1
  zstat -H directory_stat "$control_dir" && zstat -H file_stat "$control_file" || return 1
  (( directory_stat[uid] == EUID && (directory_stat[mode] & 8#7777) == 8#700 &&
     file_stat[uid] == EUID && (file_stat[mode] & 8#7777) == 8#600 && file_stat[nlink] == 1 )) || return 1
  builtin cd -- "$control_dir" || return 1
  zstat -H opened_directory_stat . || return 1
  (( opened_directory_stat[device] == directory_stat[device] && opened_directory_stat[inode] == directory_stat[inode] )) || return 1
  sysopen -w -o nofollow,cloexec -u control_fd app-management.blocked || return 1
  zstat -H descriptor_stat -f "$control_fd" || result=1
  if (( ! result )); then
    (( descriptor_stat[device] == file_stat[device] && descriptor_stat[inode] == file_stat[inode] &&
       descriptor_stat[uid] == EUID && (descriptor_stat[mode] & 8#170000) == 8#100000 &&
       (descriptor_stat[mode] & 8#7777) == 8#600 && descriptor_stat[nlink] == 1 )) || result=1
  fi
  if (( ! result && descriptor_stat[size] == 0 )); then
    print -r -- app-management >&"$control_fd" || result=1
  fi
  exec {control_fd}>&-
  return "$result"
)
# 用错误流保留诊断，路径查询函数的标准输出只包含路径。
jobs_deployment_error() {
  print -u2 -r -- "✖ App 部署：$*"
  if [[ "$*" == *'Operation not permitted'* || "$*" == *EPERM* ]] && [[ "$*" == *.app* || "$*" == *_CodeSignature* ]]; then
    local responsible_app="${JOBS_FINDER_RESPONSIBLE_APP:-}" parent_id="$PPID" parent_command="" attempt=0
    while [[ -z "$responsible_app" && -n "$parent_id" && "$parent_id" != 0 ]] && (( attempt < 8 )); do
      parent_command="$(/bin/ps -o comm= -p "$parent_id" 2>/dev/null)"
      case "$parent_command" in
        *SelectFinderExtensionFeatures*|*ManagementPanel*|*.app/Contents/MacOS/*) responsible_app="$parent_command" ;;
      esac
      parent_id="$(/bin/ps -o ppid= -p "$parent_id" 2>/dev/null)"
      parent_id="${parent_id//[[:space:]]/}"
      (( attempt += 1 ))
    done
    jobs_deployment_mark_app_management_blocked || true
    print -u2 -r -- $'JOBS_MANAGER_BLOCKED\tapp-management\t77'
    print -u2 -r -- "⚠ macOS App 管理阻止修改应用；负责应用 / 面板：${responsible_app:-当前启动管理面板的应用}。"
    print -u2 -r -- '请检查“系统设置 → 隐私与安全性 → App 管理”中的对应授权；不以 root 运行整个安装器，不修改系统目录权限或 TCC 数据库。'
    return 77
  fi
}
# 校验显式模式，不把拼错的值静默回退为构建目录。
jobs_deployment_location() {
  case "${JOBS_FINDER_INSTALL_LOCATION:-build}" in
    build|applications) print -r -- "${JOBS_FINDER_INSTALL_LOCATION:-build}" ;;
    *) jobs_deployment_error '安装位置必须是 build 或 applications。'; return 2 ;;
  esac
}
# 应用程序根目录必须真实存在且没有符号链接父级，拒绝系统根与常见危险根目录。
jobs_deployment_applications_root() {
  local applications_dir="${JOBS_FINDER_APPLICATIONS_DIR:-/Applications}"
  applications_dir="${applications_dir%/}"
  [[ -n "$applications_dir" && "$applications_dir" == /* && "$applications_dir" == "${applications_dir:a}" ]] || {
    jobs_deployment_error '应用程序目录必须是规范化的绝对路径。'; return 2
  }
  case "$applications_dir" in
    /|/System|/System/*|/Library|/usr|/usr/*|/bin|/sbin|/private|/private/var|/Users|/Volumes|"${HOME:-/nonexistent}")
      jobs_deployment_error "拒绝危险的应用程序根目录：$applications_dir"; return 2 ;;
  esac
  [[ -d "$applications_dir" && ! -L "$applications_dir" && "${applications_dir:A}" == "$applications_dir" ]] || {
    jobs_deployment_error "应用程序目录不存在，或其自身 / 父级含符号链接：$applications_dir"; return 2
  }
  print -r -- "$applications_dir"
}
# 外层只保留一个自有管理 App；固定身份防止覆盖用户的同名第三方应用。
jobs_deployment_validate_container() {
  local container_app="$1"
  [[ -d "$container_app" && ! -L "$container_app" &&
     "${container_app:t}" == Jobs自定义右键菜单.app &&
     ! -L "$container_app/Contents" && ! -L "$container_app/Contents/Info.plist" &&
     -f "$container_app/Contents/Info.plist" &&
     ! -L "$container_app/Contents/MacOS" &&
     -x "$container_app/Contents/MacOS/JobsFinderExtensions" &&
     ! -L "$container_app/Contents/MacOS/JobsFinderExtensions" &&
     -d "$container_app/Contents/Applications" && ! -L "$container_app/Contents/Applications" &&
     "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$container_app/Contents/Info.plist" 2>/dev/null)" == com.jobs.finderextensions.manager ]] || {
    jobs_deployment_error "联合 App 缺失、为链接或身份不匹配：$container_app"; return 1
  }
}
# 计算固定联合 App 路径；已有同名未知文件立即拒绝。
jobs_deployment_container_path() {
  local applications_dir="" container_app=""
  applications_dir="$(jobs_deployment_applications_root)" || return $?
  container_app="$applications_dir/Jobs自定义右键菜单.app"
  if [[ -e "$container_app" || -L "$container_app" ]]; then
    jobs_deployment_validate_container "$container_app" || return 1
  fi
  print -r -- "$container_app"
}
# 同包管理器资源使用自有相对位置，独立功能包无需保留源码仓绝对路径。
jobs_deployment_prepare_container_resources() {
  local container_app="$1" resource_library="$JOBS_DEPLOYMENT_MODULE_DIRECTORY/../【MacOS】联合App管理.zsh/【MacOS】联合App管理.zsh"
  if (( ! $+functions[jobs_prepare_combined_manager_resources] )) && [[ -f "$resource_library" ]]; then
    source "$resource_library" || return $?
  fi
  if (( $+functions[jobs_prepare_combined_manager_resources] )); then
    jobs_prepare_combined_manager_resources "$container_app" || return $?
  fi
}
# 缺失时原子创建联合 App 基座，然后交由随包函数补齐管理界面资源。
jobs_deployment_prepare_container() {
  local container_app="" temporary_dir="" staged_app="" result=0
  container_app="$(jobs_deployment_container_path)" || return $?
  if [[ ! -d "$container_app" ]]; then
    temporary_dir="$(/usr/bin/mktemp -d "${container_app:h}/.JobsFinderContainer.XXXXXX")" || return $?
    staged_app="$temporary_dir/Jobs自定义右键菜单.app"
    /bin/mkdir -p "$staged_app/Contents/MacOS" "$staged_app/Contents/Applications" "$staged_app/Contents/Resources" || result=$?
    if (( ! result )); then
      /bin/cat > "$staged_app/Contents/Info.plist" <<'JOBS_CONTAINER_PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>com.jobs.finderextensions.manager</string><key>CFBundleExecutable</key><string>JobsFinderExtensions</string><key>CFBundleName</key><string>Jobs自定义右键菜单</string><key>CFBundleDisplayName</key><string>Jobs自定义右键菜单</string><key>CFBundlePackageType</key><string>APPL</string><key>CFBundleVersion</key><string>1</string><key>LSUIElement</key><true/></dict></plist>
JOBS_CONTAINER_PLIST
      /bin/cat > "$staged_app/Contents/MacOS/JobsFinderExtensions" <<'JOBS_CONTAINER_LAUNCHER'
#!/bin/zsh
manager="${0:A:h:h}/Resources/ManageInstalledExtensions.zsh"
if [[ -f "$manager" && -r "$manager" ]]; then
  exec /bin/zsh "$manager" "$@"
fi
/usr/bin/osascript -e 'display alert "Jobs自定义右键菜单" message "管理资源不完整，请从安装面板更新联合 App。"'
exit 1
JOBS_CONTAINER_LAUNCHER
      /bin/chmod 755 "$staged_app/Contents/MacOS/JobsFinderExtensions" || result=$?
    fi
    if (( ! result )); then
      [[ ! -e "$container_app" && ! -L "$container_app" ]] && /bin/mv "$staged_app" "$container_app" || result=1
    fi
    /bin/rm -r -- "$temporary_dir" || result=1
    (( ! result )) || return "$result"
  fi
  jobs_deployment_validate_container "$container_app" || return 1
  jobs_deployment_prepare_container_resources "$container_app"
}
# 每次宿主集合变化仅重签外层，验证可递归检查，但绝不深度重签子宿主。
jobs_deployment_sign_container() {
  local container_app="$1" signing_output="" result=0 error_result=0
  jobs_deployment_validate_container "$container_app" || return 1
  signing_output="$(jobs_deployment_codesign_container "$container_app" 2>&1)" || result=$?
  [[ -z "$signing_output" ]] || print -u2 -r -- "$signing_output"
  if (( result )); then
    jobs_deployment_error "外层签名写入失败：$container_app；$signing_output" || error_result=$?
    (( error_result != 77 )) || return 77
    return "$result"
  fi
  jobs_deployment_verify_signature "$container_app"
}
# 签名写操作单独封装，验证不带重签名动作，便于精确复现策略拒绝。
jobs_deployment_codesign_container() {
  /usr/bin/codesign --force --sign - "$1"
}
# 在任何新子扩展登记前完成外层签名；登记后的提交只读核验，不再创建签名封套。
jobs_deployment_prepare_registration() {
  [[ "$(jobs_deployment_location)" == applications ]] || return 0
  local container_app=""
  container_app="$(jobs_deployment_container_path)" || return $?
  if [[ "$JOBS_DEPLOYMENT_PREPARED_REGISTRATION" == 1 ]]; then
    jobs_deployment_verify_signature "$container_app"
    return $?
  fi
  jobs_deployment_sign_container "$container_app" || return $?
  JOBS_DEPLOYMENT_PREPARED_REGISTRATION=1
}
# 最后一个宿主和事务移除后才删除联合 App；任何未知内部项都使容器保留。
jobs_deployment_remove_empty_container() {
  local container_app="" entries=""
  container_app="$(jobs_deployment_container_path)" || return $?
  [[ -d "$container_app" ]] || return 0
  entries="$(/usr/bin/find "$container_app/Contents/Applications" -mindepth 1 -maxdepth 1 -print -quit)" || return $?
  [[ -z "$entries" ]] || return 0
  /bin/rm -r -- "$container_app"
}
# 根据构建产物名计算目标；卸载也可调用，不要求源码或构建产物仍存在。
jobs_deployment_app_path() {
  local built_app="$1" location="" applications_dir=""
  location="$(jobs_deployment_location)" || return $?
  [[ "$built_app" == /* && "${built_app:t}" == Jobs*.app && "$built_app" == "${built_app:a}" ]] || {
    jobs_deployment_error "无效的自有 App 路径：$built_app"; return 2
  }
  if [[ "$location" == build ]]; then
    print -r -- "$built_app"
    return 0
  fi
  applications_dir="$(jobs_deployment_container_path)" || return $?
  print -r -- "$applications_dir/Contents/Applications/${built_app:t}"
}
# 精确匹配所选位置的宿主或直接内嵌 appex；不会把另一位置或同前缀副本混入卸载。
jobs_deployment_matches_path() {
  local candidate="$1" built_app="$2" selected_app=""
  selected_app="$(jobs_deployment_app_path "$built_app")" || return $?
  [[ "$candidate" == "$selected_app" ]] && return 0
  [[ "${candidate:h}" == "$selected_app/Contents/PlugIns" && "${candidate:t}" == *.appex ]]
}
# 只读判断所选位置确有普通 App；不把符号链接视为可卸载的安装。
jobs_deployment_selected_exists() {
  [[ -d "$1" && ! -L "$1" ]]
}
# 精确读取启用记录，避免对同 ID 的其它位置误作全局禁用或改写共同配置。
jobs_deployment_has_other_enabled() {
  local selected_app="$1" extension_id="$2" metadata="" candidate=""
  metadata="$(jobs_deployment_enabled_extension_paths "$extension_id")" || return 2
  while IFS= read -r candidate; do
    [[ -n "$candidate" ]] || continue
    [[ "${candidate:h}" == "$selected_app/Contents/PlugIns" && "${candidate:t}" == *.appex ]] || return 0
  done <<< "$metadata"
  return 1
}
# 只接受固定 Jobs 身份和单个扩展文件名，阻断字段中的路径穿越。
jobs_deployment_validate_arguments() {
  local app_id="$1" extension_name="$2" extension_id="$3"
  [[ "$app_id" == com.jobs.* && "$extension_id" == com.jobs.* &&
     -n "${app_id#com.jobs.}" && -n "${extension_id#com.jobs.}" &&
     "$extension_name" == *.appex && "$extension_name" != */* &&
     "$extension_name" != .* && "$extension_name" != *$'\n'* ]] || {
    jobs_deployment_error '宿主 / 扩展身份或扩展文件名无效。'; return 2
  }
}
# 核对 Bundle 身份及可执行文件，拒绝外部链接资源与不完整 Bundle。
jobs_deployment_validate_app() {
  local candidate_app="$1" app_id="$2" extension_name="$3" extension_id="$4"
  local extension_bundle="$candidate_app/Contents/PlugIns/$extension_name"
  local bundle="" expected_id="" executable_name="" link_item="" link_value=""
  jobs_deployment_validate_arguments "$app_id" "$extension_name" "$extension_id" || return $?
  [[ -d "$candidate_app" && ! -L "$candidate_app" && "${candidate_app:t}" == *.app ]] || {
    jobs_deployment_error "App 缺失或为符号链接：$candidate_app"; return 1
  }
  for bundle expected_id in "$candidate_app" "$app_id" "$extension_bundle" "$extension_id"; do
    [[ -d "$bundle" && ! -L "$bundle" && -f "$bundle/Contents/Info.plist" && ! -L "$bundle/Contents/Info.plist" ]] || {
      jobs_deployment_error "Bundle 配置缺失或为符号链接：$bundle"; return 1
    }
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$bundle/Contents/Info.plist" 2>/dev/null)" == "$expected_id" ]] || {
      jobs_deployment_error "拒绝操作身份不匹配的 Bundle：$bundle"; return 1
    }
    executable_name="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$bundle/Contents/Info.plist" 2>/dev/null)" || return 1
    [[ -n "$executable_name" && "$executable_name" != */* && "$executable_name" != .* && -x "$bundle/Contents/MacOS/$executable_name" ]] || {
      jobs_deployment_error "Bundle 执行程序不完整：$bundle"; return 1
    }
  done
  while IFS= read -r -d '' link_item; do
    link_value="$(/usr/bin/readlink "$link_item")" || return 1
    [[ "$link_value" != /* && -e "$link_item" && "${link_item:A}" == "${candidate_app:A}"/* ]] || {
      jobs_deployment_error "拒绝指向 App 外部或失效的链接：$link_item"; return 1
    }
  done < <(/usr/bin/find "$candidate_app" -type l -print0)
}
# 深度签名验证与复制分别封装，隔离测试可精确替换而不触碰真实系统登记。
jobs_deployment_verify_signature() {
  /usr/bin/codesign --verify --deep --strict "$1"
}
# ditto 保留整个 App、内嵌扩展、资源、扩展属性和权限。
jobs_deployment_copy_app() {
  /usr/bin/ditto --rsrc --extattr --acl "$1" "$2"
}
# 获取已启用的精确扩展路径，供跨安装位置切换失败时恢复。
jobs_deployment_enabled_extension_paths() {
  local metadata=""
  metadata="$(/usr/bin/pluginkit -m -A -D -vv -i "$1" 2>/dev/null)" || return $?
  print -r -- "$metadata" | /usr/bin/awk '
    /^[[:space:]]*[+!-]/ { enabled=($1 == "+") }
    /Path = / { if (enabled) { sub(/^.*Path = /, ""); print } }
  '
}
# 注销只针对当前精确路径，不使用会影响同 ID 其它位置的全局 ignore。
jobs_deployment_unregister_app() {
  local selected_app="$1" extension_name="$2" extension_bundle="$1/Contents/PlugIns/$2"
  local remove_result=0 metadata="" candidate=""
  jobs_deployment_remove_extension_path "$extension_bundle" || remove_result=$?
  if (( remove_result )); then
    metadata="$(jobs_deployment_registered_extension_paths_for_bundle "$extension_bundle")" || {
      jobs_deployment_error "注销失败且无法复核登记：$extension_bundle"; return "$remove_result"
    }
    while IFS= read -r candidate; do
      [[ "$candidate" != "$extension_bundle" ]] || {
        jobs_deployment_error "注销失败且精确路径仍登记：$extension_bundle"; return "$remove_result"
      }
    done <<< "$metadata"
    print -u2 -r -- "ℹ 精确扩展已无登记，无需重复移除：$extension_bundle"
  fi
  jobs_deployment_unregister_host_path "$selected_app"
}
# 宿主注销只处理精确路径，和扩展注销分开保留错误码。
jobs_deployment_unregister_host_path() {
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$1"
}
# 单独封装系统注销，隔离测试可模拟“已被系统先行移除”的真实分支。
jobs_deployment_remove_extension_path() {
  /usr/bin/pluginkit -r "$1"
}
# 复核失败注销时仅查询该 Bundle ID 的记录，不把查询失败当成已移除。
jobs_deployment_registered_extension_paths_for_bundle() {
  local extension_id=""
  extension_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$1/Contents/Info.plist" 2>/dev/null)" || return 1
  [[ "$extension_id" == com.jobs.* ]] || return 1
  jobs_deployment_registered_extension_paths "$extension_id"
}
# 恢复事务开始前已启用的自有 Bundle，包含原先位于构建目录的副本。
jobs_deployment_register_restored_app() {
  local selected_app="$1" extension_name="$2" extension_id="$3"
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$selected_app" || return $?
  /usr/bin/pluginkit -a "$selected_app/Contents/PlugIns/$extension_name" || return $?
  /usr/bin/pluginkit -e use -i "$extension_id"
}
# 记录恢复所需身份，只采纳当前 ID 且 Bundle 身份完整匹配的启用项。
jobs_deployment_capture_previous_apps() {
  local app_id="$1" extension_name="$2" extension_id="$3" metadata="" candidate="" owner_app=""
  JOBS_DEPLOYMENT_PREVIOUS_APPS=()
  metadata="$(jobs_deployment_enabled_extension_paths "$extension_id")" || {
    jobs_deployment_error '无法读取旧扩展启用状态，未开始替换。'; return 1
  }
  while IFS= read -r candidate; do
    [[ -n "$candidate" ]] || continue
    [[ "$candidate" == /*/Contents/PlugIns/"$extension_name" ]] || return 1
    owner_app="${candidate%/Contents/PlugIns/$extension_name}"
    jobs_deployment_validate_app "$owner_app" "$app_id" "$extension_name" "$extension_id" || return 1
    JOBS_DEPLOYMENT_PREVIOUS_APPS+=("$owner_app")
  done <<< "$metadata"
}
# 清空内存事务状态，避免后续安装误用上一项的路径。
jobs_deployment_reset_transaction() {
  JOBS_DEPLOYMENT_TRANSACTION_DIR=""
  JOBS_DEPLOYMENT_TRANSACTION_ROOT=""
  JOBS_DEPLOYMENT_TRANSACTION_TARGET=""
  JOBS_DEPLOYMENT_TRANSACTION_APP_ID=""
  JOBS_DEPLOYMENT_TRANSACTION_EXTENSION_NAME=""
  JOBS_DEPLOYMENT_TRANSACTION_EXTENSION_ID=""
  JOBS_DEPLOYMENT_TRANSACTION_LOCK=""
  JOBS_DEPLOYMENT_TRANSACTION_IDENTITY=""
  JOBS_DEPLOYMENT_TARGET_IDENTITY=""
  JOBS_DEPLOYMENT_TRANSACTION_SOURCE=""
  JOBS_DEPLOYMENT_TRANSACTION_LEGACY_PATH=""
  JOBS_DEPLOYMENT_PREPARED_REGISTRATION=0
  JOBS_DEPLOYMENT_REGISTRATION_ONLY=0
  JOBS_DEPLOYMENT_PREVIOUS_APPS=()
}
# 事务目录身份不变才可清理；失败时保留备份并报告位置。
jobs_deployment_validate_transaction() {
  local transaction_dir="$JOBS_DEPLOYMENT_TRANSACTION_DIR" transaction_root="$JOBS_DEPLOYMENT_TRANSACTION_ROOT"
  [[ -n "$transaction_dir" && -d "$transaction_dir" && ! -L "$transaction_dir" &&
     "${transaction_dir:h}" == "$transaction_root" && "${transaction_dir:t}" == .JobsFinderDeployment.* &&
     "${transaction_root:A}" == "$transaction_root" &&
     "$(/usr/bin/stat -f '%d:%i' "$transaction_dir")" == "$JOBS_DEPLOYMENT_TRANSACTION_IDENTITY" ]] || {
    jobs_deployment_error "事务目录已变化，保留现状请人工核对：$transaction_dir"; return 1
  }
}
# 释放事务目录和互斥锁；只清理由本模块创建且身份未变化的目录。
jobs_deployment_release_transaction() {
  jobs_deployment_validate_transaction || return 1
  /bin/rm -r -- "$JOBS_DEPLOYMENT_TRANSACTION_DIR" || return $?
  /bin/rmdir -- "$JOBS_DEPLOYMENT_TRANSACTION_LOCK" || return $?
  jobs_deployment_reset_transaction
}
# 只收拢本次已由嵌套宿主替代的旧顶层副本；未知应用和未选中的功能保留。
jobs_deployment_backup_legacy_top_level_app() {
  local applications_dir="" legacy_app=""
  applications_dir="$(jobs_deployment_applications_root)" || return $?
  legacy_app="$applications_dir/${JOBS_DEPLOYMENT_TRANSACTION_SOURCE:t}"
  [[ -e "$legacy_app" || -L "$legacy_app" ]] || return 0
  if ! jobs_deployment_validate_app "$legacy_app" "$JOBS_DEPLOYMENT_TRANSACTION_APP_ID" "$JOBS_DEPLOYMENT_TRANSACTION_EXTENSION_NAME" "$JOBS_DEPLOYMENT_TRANSACTION_EXTENSION_ID"; then
    print -u2 -r -- "⚠ 未迁移身份无法核验或为链接的旧顶层对象：$legacy_app"
    return 0
  fi
  jobs_deployment_verify_signature "$legacy_app" || return $?
  jobs_deployment_unregister_app "$legacy_app" "$JOBS_DEPLOYMENT_TRANSACTION_EXTENSION_NAME" || return $?
  JOBS_DEPLOYMENT_TRANSACTION_LEGACY_PATH="$legacy_app"
  /bin/mv -- "$legacy_app" "$JOBS_DEPLOYMENT_TRANSACTION_DIR/legacy.app" || return $?
  print -u2 -r -- "ℹ 已将本次旧顶层宿主收拢到联合 App，提交前保留备份：$legacy_app"
}
# 所有登记与配置保存成功后丢弃旧 App 备份。
jobs_deployment_commit() {
  local receipt=("$JOBS_DEPLOYMENT_TRANSACTION_SOURCE" "$JOBS_DEPLOYMENT_TRANSACTION_TARGET" "$JOBS_DEPLOYMENT_TRANSACTION_APP_ID" "$JOBS_DEPLOYMENT_TRANSACTION_EXTENSION_NAME" "$JOBS_DEPLOYMENT_TRANSACTION_EXTENSION_ID" "$JOBS_DEPLOYMENT_TARGET_IDENTITY")
  if [[ "$JOBS_DEPLOYMENT_REGISTRATION_ONLY" == 1 ]]; then
    JOBS_DEPLOYMENT_COMMITTED_RECEIPT=()
    jobs_deployment_reset_transaction
    return 0
  fi
  [[ -n "$JOBS_DEPLOYMENT_TRANSACTION_DIR" ]] || return 0
  [[ -n "$JOBS_DEPLOYMENT_TARGET_IDENTITY" && -d "$JOBS_DEPLOYMENT_TRANSACTION_TARGET" &&
     ! -L "$JOBS_DEPLOYMENT_TRANSACTION_TARGET" &&
     "$(/usr/bin/stat -f '%d:%i' "$JOBS_DEPLOYMENT_TRANSACTION_TARGET")" == "$JOBS_DEPLOYMENT_TARGET_IDENTITY" ]] || {
    jobs_deployment_error "提交前目标已被替换，保留备份：$JOBS_DEPLOYMENT_TRANSACTION_DIR"; return 1
  }
  [[ "$JOBS_DEPLOYMENT_PREPARED_REGISTRATION" == 1 ]] || { jobs_deployment_error '尚未在扩展登记前准备联合 App 签名，拒绝提交。'; return 1; }
  jobs_deployment_verify_signature "${JOBS_DEPLOYMENT_TRANSACTION_TARGET:h:h:h}" || return $?
  jobs_deployment_backup_legacy_top_level_app || return $?
  jobs_deployment_release_transaction || return $?
  JOBS_DEPLOYMENT_COMMITTED_RECEIPT=("${receipt[@]}")
}
# 恢复原文件与原启用位置；失败保留事务目录，绝不删除并发替换的新文件。
jobs_deployment_rollback() {
  local selected_app="$JOBS_DEPLOYMENT_TRANSACTION_TARGET" previous_app="" result=0
  local backup_app="$JOBS_DEPLOYMENT_TRANSACTION_DIR/previous.app"
  if [[ "$JOBS_DEPLOYMENT_REGISTRATION_ONLY" == 1 ]]; then
    if [[ -d "$selected_app" && ! -L "$selected_app" ]]; then
      jobs_deployment_validate_app "$selected_app" "$JOBS_DEPLOYMENT_TRANSACTION_APP_ID" "$JOBS_DEPLOYMENT_TRANSACTION_EXTENSION_NAME" "$JOBS_DEPLOYMENT_TRANSACTION_EXTENSION_ID" || return 1
      jobs_deployment_unregister_app "$selected_app" "$JOBS_DEPLOYMENT_TRANSACTION_EXTENSION_NAME" || result=1
    fi
    for previous_app in "${JOBS_DEPLOYMENT_PREVIOUS_APPS[@]}"; do
      jobs_deployment_validate_app "$previous_app" "$JOBS_DEPLOYMENT_TRANSACTION_APP_ID" "$JOBS_DEPLOYMENT_TRANSACTION_EXTENSION_NAME" "$JOBS_DEPLOYMENT_TRANSACTION_EXTENSION_ID" || return 1
      jobs_deployment_register_restored_app "$previous_app" "$JOBS_DEPLOYMENT_TRANSACTION_EXTENSION_NAME" "$JOBS_DEPLOYMENT_TRANSACTION_EXTENSION_ID" || result=1
    done
    (( ! result )) || return 1
    jobs_deployment_reset_transaction
    return 0
  fi
  [[ -n "$JOBS_DEPLOYMENT_TRANSACTION_DIR" ]] || return 0
  jobs_deployment_validate_transaction || return 1
  if [[ -n "$JOBS_DEPLOYMENT_TARGET_IDENTITY" ]]; then
    [[ -d "$selected_app" && ! -L "$selected_app" &&
       "$(/usr/bin/stat -f '%d:%i' "$selected_app")" == "$JOBS_DEPLOYMENT_TARGET_IDENTITY" ]] || {
      jobs_deployment_error "目标已被其它操作替换，保留备份：$JOBS_DEPLOYMENT_TRANSACTION_DIR"; return 1
    }
    jobs_deployment_validate_app "$selected_app" "$JOBS_DEPLOYMENT_TRANSACTION_APP_ID" "$JOBS_DEPLOYMENT_TRANSACTION_EXTENSION_NAME" "$JOBS_DEPLOYMENT_TRANSACTION_EXTENSION_ID" || return 1
    jobs_deployment_unregister_app "$selected_app" "$JOBS_DEPLOYMENT_TRANSACTION_EXTENSION_NAME" || result=1
    /bin/rm -r -- "$selected_app" || return $?
    JOBS_DEPLOYMENT_TARGET_IDENTITY=""
  fi
  if [[ -d "$backup_app" ]]; then
    [[ ! -e "$selected_app" && ! -L "$selected_app" ]] || return 1
    /bin/mv -- "$backup_app" "$selected_app" || return $?
  fi
  if [[ -d "$JOBS_DEPLOYMENT_TRANSACTION_DIR/legacy.app" ]]; then
    [[ -n "$JOBS_DEPLOYMENT_TRANSACTION_LEGACY_PATH" && ! -e "$JOBS_DEPLOYMENT_TRANSACTION_LEGACY_PATH" && ! -L "$JOBS_DEPLOYMENT_TRANSACTION_LEGACY_PATH" ]] || {
      jobs_deployment_error "旧顶层位置已有新文件，保留迁移备份：$JOBS_DEPLOYMENT_TRANSACTION_DIR"; return 1
    }
    /bin/mv -- "$JOBS_DEPLOYMENT_TRANSACTION_DIR/legacy.app" "$JOBS_DEPLOYMENT_TRANSACTION_LEGACY_PATH" || return $?
    JOBS_DEPLOYMENT_TRANSACTION_LEGACY_PATH=""
  fi
  for previous_app in "${JOBS_DEPLOYMENT_PREVIOUS_APPS[@]}"; do
    jobs_deployment_validate_app "$previous_app" "$JOBS_DEPLOYMENT_TRANSACTION_APP_ID" "$JOBS_DEPLOYMENT_TRANSACTION_EXTENSION_NAME" "$JOBS_DEPLOYMENT_TRANSACTION_EXTENSION_ID" || return 1
    jobs_deployment_register_restored_app "$previous_app" "$JOBS_DEPLOYMENT_TRANSACTION_EXTENSION_NAME" "$JOBS_DEPLOYMENT_TRANSACTION_EXTENSION_ID" || result=1
  done
  if (( result )); then
    jobs_deployment_error "原文件已恢复，但登记恢复未全部成功；保留事务：$JOBS_DEPLOYMENT_TRANSACTION_DIR"
    return 1
  fi
  jobs_deployment_remove_empty_container || return $?
  local remaining_container="$(jobs_deployment_container_path)" || return $?
  if [[ -d "$remaining_container" ]]; then
    jobs_deployment_sign_container "$remaining_container" || return $?
  fi
  jobs_deployment_release_transaction
}
# 在相同文件系统先复制校验，再发布完整 App；旧 App 留在事务内直到 commit。
jobs_deployment_publish_app() {
  local built_app="$1" app_id="$2" extension_name="$3" extension_id="$4"
  local selected_app="$JOBS_DEPLOYMENT_TRANSACTION_TARGET" staging_app="$JOBS_DEPLOYMENT_TRANSACTION_DIR/staging.app"
  print -u2 -r -- "━━━━━━━━━━ 来源｜App 部署 ━━━━━━━━━━"
  print -u2 -r -- "📦 对象：${built_app:t}；来源：$built_app"
  print -u2 -r -- "📂 目标：$selected_app"
  jobs_deployment_copy_app "$built_app" "$staging_app" || return $?
  jobs_deployment_validate_app "$staging_app" "$app_id" "$extension_name" "$extension_id" || return 1
  jobs_deployment_verify_signature "$staging_app" || return $?
  if [[ -e "$selected_app" || -L "$selected_app" ]]; then
    jobs_deployment_validate_app "$selected_app" "$app_id" "$extension_name" "$extension_id" || return 1
    /bin/mv -- "$selected_app" "$JOBS_DEPLOYMENT_TRANSACTION_DIR/previous.app" || return $?
  fi
  /bin/mv -- "$staging_app" "$selected_app" || return $?
  JOBS_DEPLOYMENT_TARGET_IDENTITY="$(/usr/bin/stat -f '%d:%i' "$selected_app")" || return 1
}
# 应用程序模式创建文件事务；构建模式只保存原登记，保留原构建和文件处理流程。
jobs_deployment_install() {
  local built_app="$1" app_id="$2" extension_name="$3" extension_id="$4"
  local location="" selected_app="" applications_dir="" transaction_dir="" lock_dir="" result=0
  location="$(jobs_deployment_location)" || return $?
  JOBS_DEPLOYMENT_COMMITTED_RECEIPT=()
  [[ -z "$JOBS_DEPLOYMENT_TRANSACTION_DIR" && "$JOBS_DEPLOYMENT_REGISTRATION_ONLY" != 1 ]] || { jobs_deployment_error '上一项部署尚未提交或回滚。'; return 1; }
  if [[ "$location" == build ]]; then
    # 原管理器仍核验缺失产物；不要求旧隔离构建替身额外制造真实 App。
    [[ -d "$built_app" && ! -L "$built_app" ]] || return 0
    jobs_deployment_capture_previous_apps "$app_id" "$extension_name" "$extension_id" || return 1
    JOBS_DEPLOYMENT_TRANSACTION_TARGET="$built_app"
    JOBS_DEPLOYMENT_TRANSACTION_SOURCE="$built_app"
    JOBS_DEPLOYMENT_TRANSACTION_APP_ID="$app_id"
    JOBS_DEPLOYMENT_TRANSACTION_EXTENSION_NAME="$extension_name"
    JOBS_DEPLOYMENT_TRANSACTION_EXTENSION_ID="$extension_id"
    JOBS_DEPLOYMENT_REGISTRATION_ONLY=1
    return 0
  fi
  selected_app="$(jobs_deployment_app_path "$built_app")" || return $?
  [[ "${built_app:A}" != "$selected_app" ]] || { jobs_deployment_error '构建来源与部署目标不能是同一 App。'; return 1; }
  jobs_deployment_validate_app "$built_app" "$app_id" "$extension_name" "$extension_id" || return 1
  jobs_deployment_verify_signature "$built_app" || return $?
  if [[ -e "$selected_app" || -L "$selected_app" ]]; then
    jobs_deployment_validate_app "$selected_app" "$app_id" "$extension_name" "$extension_id" || return 1
  fi
  jobs_deployment_capture_previous_apps "$app_id" "$extension_name" "$extension_id" || return 1
  applications_dir="$(jobs_deployment_applications_root)" || return $?
  [[ -w "$applications_dir" ]] || { jobs_deployment_error "应用程序目录不可写，请使用有写权限的账户：$applications_dir"; return 1; }
  lock_dir="$applications_dir/.JobsFinderDeployment.Jobs自定义右键菜单.lock"
  /bin/mkdir -- "$lock_dir" || { jobs_deployment_error "此 App 已有部署事务或残留锁：$lock_dir"; return 1; }
  jobs_deployment_prepare_container || {
    result=$?
    jobs_deployment_remove_empty_container || jobs_deployment_error '准备失败后的空容器清理未完成。'
    local existing_container="$(jobs_deployment_container_path)"
    if [[ -n "$existing_container" && -d "$existing_container" ]]; then
      jobs_deployment_sign_container "$existing_container" || jobs_deployment_error '资源准备失败，联合 App 签名复核未通过。'
    fi
    /bin/rmdir -- "$lock_dir"
    return "$result"
  }
  transaction_dir="$(/usr/bin/mktemp -d "$applications_dir/.JobsFinderDeployment.${built_app:t}.XXXXXX")" || {
    /bin/rmdir -- "$lock_dir"; return 1
  }
  JOBS_DEPLOYMENT_TRANSACTION_DIR="$transaction_dir"
  JOBS_DEPLOYMENT_TRANSACTION_ROOT="$applications_dir"
  JOBS_DEPLOYMENT_TRANSACTION_TARGET="$selected_app"
  JOBS_DEPLOYMENT_TRANSACTION_SOURCE="$built_app"
  JOBS_DEPLOYMENT_TRANSACTION_APP_ID="$app_id"
  JOBS_DEPLOYMENT_TRANSACTION_EXTENSION_NAME="$extension_name"
  JOBS_DEPLOYMENT_TRANSACTION_EXTENSION_ID="$extension_id"
  JOBS_DEPLOYMENT_TRANSACTION_LOCK="$lock_dir"
  JOBS_DEPLOYMENT_TRANSACTION_IDENTITY="$(/usr/bin/stat -f '%d:%i' "$transaction_dir")"
  JOBS_DEPLOYMENT_TARGET_IDENTITY=""
  jobs_deployment_publish_app "$built_app" "$app_id" "$extension_name" "$extension_id" || result=$?
  (( result )) || jobs_deployment_prepare_registration || result=$?
  if (( result )); then
    jobs_deployment_rollback || jobs_deployment_error "自动回滚未完成，请检查：$transaction_dir"
    return "$result"
  fi
}
# 单活切换只撤销其它启用路径的登记，保留其文件；失败可用 rollback 恢复原启用位置。
jobs_deployment_retire_other_copies() {
  local selected_app="$1" app_id="$2" extension_name="$3" extension_id="$4" previous_app=""
  jobs_deployment_prepare_registration || return $?
  if [[ -z "$JOBS_DEPLOYMENT_TRANSACTION_DIR" && "$JOBS_DEPLOYMENT_REGISTRATION_ONLY" != 1 ]]; then
    jobs_deployment_capture_previous_apps "$app_id" "$extension_name" "$extension_id" || return 1
    JOBS_DEPLOYMENT_TRANSACTION_TARGET="$selected_app"
    JOBS_DEPLOYMENT_TRANSACTION_APP_ID="$app_id"
    JOBS_DEPLOYMENT_TRANSACTION_EXTENSION_NAME="$extension_name"
    JOBS_DEPLOYMENT_TRANSACTION_EXTENSION_ID="$extension_id"
    JOBS_DEPLOYMENT_REGISTRATION_ONLY=1
  fi
  [[ "$JOBS_DEPLOYMENT_TRANSACTION_TARGET" == "$selected_app" && "$JOBS_DEPLOYMENT_TRANSACTION_EXTENSION_ID" == "$extension_id" ]] || {
    jobs_deployment_error '其它副本注销请求与当前事务不一致。'; return 1
  }
  for previous_app in "${JOBS_DEPLOYMENT_PREVIOUS_APPS[@]}"; do
    [[ "$previous_app" != "$selected_app" ]] || continue
    jobs_deployment_validate_app "$previous_app" "$app_id" "$extension_name" "$extension_id" || return 1
    print -u2 -r -- "ℹ 保留其它位置 App 文件，仅注销登记：$previous_app"
    jobs_deployment_unregister_app "$previous_app" "$extension_name" || return $?
  done
}
# 只卸载所选应用程序目录中的完整自有 App；构建模式保留原管理器的卸载语义。
jobs_deployment_uninstall() {
  local selected_app="$1" app_id="$2" extension_name="$3" extension_id="$4"
  local location="" applications_dir="" container_app="" lock_dir="" result=0
  location="$(jobs_deployment_location)" || return $?
  [[ "$location" == applications ]] || return 0
  JOBS_DEPLOYMENT_COMMITTED_RECEIPT=()
  [[ -z "$JOBS_DEPLOYMENT_TRANSACTION_DIR" && "$JOBS_DEPLOYMENT_REGISTRATION_ONLY" != 1 ]] || { jobs_deployment_error '部署事务未完成，不能卸载。'; return 1; }
  applications_dir="$(jobs_deployment_applications_root)" || return $?
  container_app="$(jobs_deployment_container_path)" || return $?
  [[ "${selected_app:h}" == "$container_app/Contents/Applications" && "${selected_app:t}" == Jobs*.app && "$selected_app" == "${selected_app:a}" ]] || {
    jobs_deployment_error "拒绝卸载所选应用程序目录之外的 App：$selected_app"; return 1
  }
  [[ -e "$selected_app" || -L "$selected_app" ]] || { print -u2 -r -- "ℹ 所选应用程序目录未安装：$selected_app"; return 0; }
  jobs_deployment_validate_app "$selected_app" "$app_id" "$extension_name" "$extension_id" || return 1
  print -u2 -r -- "📦 卸载对象：$selected_app；宿主：$app_id；扩展：$extension_id"
  lock_dir="$applications_dir/.JobsFinderDeployment.Jobs自定义右键菜单.lock"
  /bin/mkdir -- "$lock_dir" || return $?
  jobs_deployment_unregister_app "$selected_app" "$extension_name" || result=$?
  (( result )) || /bin/rm -r -- "$selected_app" || result=$?
  (( result )) || jobs_deployment_remove_empty_container || result=$?
  if (( ! result )) && [[ -d "$container_app" ]]; then
    jobs_deployment_sign_container "$container_app" || result=$?
  fi
  /bin/rmdir -- "$lock_dir" || result=1
  return "$result"
}
# 查询所有登记来源，清理不能仅凭某个副本已启用就忽略仍引用构建目录的记录。
jobs_deployment_registered_extension_paths() {
  local metadata=""
  metadata="$(/usr/bin/pluginkit -m -A -D -vv -i "$1" 2>/dev/null)" || return $?
  print -r -- "$metadata" | /usr/bin/awk '/Path = / { sub(/^.*Path = /, ""); print }'
}
# 保守核对可执行路径和命令行；来源仍被进程引用时拒绝清理，不结束任何进程。
jobs_deployment_source_is_running() {
  local source_root="$1" processes="" process_line=""
  processes="$(/bin/ps -wwaxo pid=,comm=,args=)" || return 2
  while IFS= read -r process_line; do
    [[ "$process_line" == *"$source_root/"* ]] && return 0
  done <<< "$processes"
  return 1
}
# 只有精确目标已启用且构建来源不再有登记时，才能清理来源；查询失败一律停止。
jobs_deployment_cleanup_registration_ready() {
  local selected_app="$1" source_root="$2" extension_name="$3" extension_id="$4" moved_root="${5:-}"
  local metadata="" candidate="" matched=0
  metadata="$(jobs_deployment_enabled_extension_paths "$extension_id")" || return 1
  while IFS= read -r candidate; do
    [[ -n "$candidate" ]] || continue
    [[ "$candidate" == "$selected_app/Contents/PlugIns/$extension_name" ]] || {
      jobs_deployment_error "其它位置仍在启用，保留构建产物：$candidate"; return 1
    }
    matched=1
  done <<< "$metadata"
  (( matched )) || { jobs_deployment_error '未确认联合 App 内的精确扩展已启用，保留构建产物。'; return 1; }
  metadata="$(jobs_deployment_registered_extension_paths "$extension_id")" || return 1
  while IFS= read -r candidate; do
    [[ -n "$candidate" ]] || continue
    if [[ "$candidate" == "$source_root"/* || ( -n "$moved_root" && "$candidate" == "$moved_root"/* ) ]]; then
      jobs_deployment_error "构建来源仍有扩展登记，保留产物：$candidate"
      return 1
    fi
  done <<< "$metadata"
}
# 安全清理本轮已提交部署的唯一 DerivedData；失败仅返回错误，不回滚应用程序安装。
jobs_deployment_cleanup_build_products() {
  local built_app="$1" derived_root="$2" app_id="$3" extension_name="$4" extension_id="$5"
  local selected_app="" source_identity="" quarantine="" moved_root="" protected="" applications_dir="" result=0 process_result=0
  [[ "$(jobs_deployment_location)" == applications && -z "$JOBS_DEPLOYMENT_TRANSACTION_DIR" && "$JOBS_DEPLOYMENT_REGISTRATION_ONLY" != 1 ]] || {
    jobs_deployment_error '构建清理只允许在应用程序安装提交成功之后执行。'; return 2
  }
  selected_app="$(jobs_deployment_app_path "$built_app")" || return $?
  applications_dir="$(jobs_deployment_applications_root)" || return $?
  (( ${#JOBS_DEPLOYMENT_COMMITTED_RECEIPT[@]} == 6 )) &&
    [[ "${JOBS_DEPLOYMENT_COMMITTED_RECEIPT[1]}" == "$built_app" &&
       "${JOBS_DEPLOYMENT_COMMITTED_RECEIPT[2]}" == "$selected_app" &&
       "${JOBS_DEPLOYMENT_COMMITTED_RECEIPT[3]}" == "$app_id" &&
       "${JOBS_DEPLOYMENT_COMMITTED_RECEIPT[4]}" == "$extension_name" &&
       "${JOBS_DEPLOYMENT_COMMITTED_RECEIPT[5]}" == "$extension_id" &&
       "${JOBS_DEPLOYMENT_COMMITTED_RECEIPT[6]}" == "$(/usr/bin/stat -f '%d:%i' "$selected_app" 2>/dev/null)" ]] || {
    jobs_deployment_error '缺少本轮相同来源和目标的成功部署凭据，保留构建产物。'; return 2
  }
  [[ -d "$derived_root" && ! -L "$derived_root" && "$derived_root" == /* &&
     "$derived_root" == "${derived_root:a}" && "$derived_root" == "${derived_root:A}" &&
     "${derived_root:h:t}" == work &&
     ( "${derived_root:t}" == DerivedData || "${derived_root:t}" == "${built_app:t:r}DerivedData" ) &&
     "${built_app:h:h}" == "$derived_root/Build/Products" &&
     ( "${built_app:h:t}" == Debug || "${built_app:h:t}" == Release ) &&
     "$selected_app" != "$derived_root"/* && "$built_app" != "$selected_app" && "$derived_root" != "$applications_dir"/* ]] || {
    jobs_deployment_error "拒绝未经验证的本轮构建根目录：$derived_root"; return 2
  }
  jobs_deployment_validate_app "$built_app" "$app_id" "$extension_name" "$extension_id" || return 1
  jobs_deployment_validate_app "$selected_app" "$app_id" "$extension_name" "$extension_id" || return 1
  jobs_deployment_verify_signature "$selected_app" || return $?
  jobs_deployment_verify_signature "${selected_app:h:h:h}" || return $?
  protected="$(/usr/bin/find "$derived_root" \( -name .git -o -name .hg -o -name .svn \) -print -quit)" || return $?
  [[ -z "$protected" ]] || { jobs_deployment_error "构建根包含版本元数据，保留产物：$protected"; return 1; }
  jobs_deployment_cleanup_registration_ready "$selected_app" "$derived_root" "$extension_name" "$extension_id" || return 1
  jobs_deployment_source_is_running "$derived_root" || process_result=$?
  (( process_result == 1 )) || { jobs_deployment_error '构建来源仍被进程引用或进程查询失败，保留产物。'; return 1; }
  source_identity="$(/usr/bin/stat -f '%d:%i' "$derived_root")" || return $?
  quarantine="$(/usr/bin/mktemp -d "${derived_root:h}/.JobsFinderCleanup.XXXXXX")" || return $?
  moved_root="$quarantine/DerivedData"
  /bin/mv -- "$derived_root" "$moved_root" || { /bin/rmdir -- "$quarantine"; return 1; }
  [[ ! -L "$moved_root" && "$(/usr/bin/stat -f '%d:%i' "$moved_root")" == "$source_identity" && "${quarantine:A}" == "$quarantine" ]] || result=1
  if (( ! result )); then
    jobs_deployment_cleanup_registration_ready "$selected_app" "$derived_root" "$extension_name" "$extension_id" "$moved_root" || result=1
    process_result=0
    jobs_deployment_source_is_running "$derived_root" || process_result=$?
    (( process_result == 1 )) || result=1
    process_result=0
    jobs_deployment_source_is_running "$moved_root" || process_result=$?
    (( process_result == 1 )) || result=1
  fi
  if (( result )); then
    if [[ ! -e "$derived_root" && ! -L "$derived_root" && "${derived_root:h:A}" == "${derived_root:h}" ]]; then
      /bin/mv -- "$moved_root" "$derived_root" && /bin/rmdir -- "$quarantine"
    fi
    jobs_deployment_error "清理前状态发生变化，已保留构建产物；原位置：$derived_root；暂存位置：$quarantine"
    return 1
  fi
  print -u2 -r -- "🧹 本轮构建产物：$derived_root；已安装联合 App：$selected_app"
  /bin/rm -r -- "$moved_root" || { jobs_deployment_error "清理未完整完成，剩余产物：$quarantine"; return 1; }
  /bin/rmdir -- "$quarantine" || return $?
  JOBS_DEPLOYMENT_COMMITTED_RECEIPT=()
  print -u2 -r -- "✔ 本轮构建产物清理完成：$derived_root"
}
# 独立清理已安装联合 App 对应的历史构建根；强校验目标后才临时复用同一删除内核。
jobs_deployment_cleanup_existing_build_products() {
  local built_app="$1" derived_root="$2" app_id="$3" extension_name="$4" extension_id="$5"
  local selected_app="" entries="" result=0 previous_receipt=("${JOBS_DEPLOYMENT_COMMITTED_RECEIPT[@]}")
  [[ "$(jobs_deployment_location)" == applications && -z "$JOBS_DEPLOYMENT_TRANSACTION_DIR" && "$JOBS_DEPLOYMENT_REGISTRATION_ONLY" != 1 ]] || {
    jobs_deployment_error '独立清理只允许针对已安装的联合 App，且不能与部署事务并行。'; return 2
  }
  [[ "$derived_root" == /* && "$derived_root" == "${derived_root:a}" && ! -L "$derived_root" &&
     "${derived_root:h:t}" == work &&
     ( "${derived_root:t}" == DerivedData || "${derived_root:t}" == "${built_app:t:r}DerivedData" ) &&
     "${built_app:h:h}" == "$derived_root/Build/Products" &&
     ( "${built_app:h:t}" == Debug || "${built_app:h:t}" == Release ) ]] || {
    jobs_deployment_error "拒绝独立清理未经验证的构建根：$derived_root"; return 2
  }
  if [[ ! -e "$derived_root" ]]; then
    print -u2 -r -- "ℹ 构建目录不存在，无需清理：$derived_root"
    return 0
  fi
  [[ -d "$derived_root" && "$derived_root" == "${derived_root:A}" ]] || {
    jobs_deployment_error "构建根或其父级包含链接，保留目录：$derived_root"; return 2
  }
  entries="$(/usr/bin/find "$derived_root" -mindepth 1 -maxdepth 1 -print -quit)" || return $?
  [[ -n "$entries" ]] || { print -u2 -r -- "ℹ 构建目录为空，无需清理：$derived_root"; return 0; }
  selected_app="$(jobs_deployment_app_path "$built_app")" || return $?
  jobs_deployment_validate_app "$selected_app" "$app_id" "$extension_name" "$extension_id" || return 1
  jobs_deployment_verify_signature "$selected_app" || return $?
  jobs_deployment_verify_signature "${selected_app:h:h:h}" || return $?
  jobs_deployment_cleanup_registration_ready "$selected_app" "$derived_root" "$extension_name" "$extension_id" || return 1
  JOBS_DEPLOYMENT_COMMITTED_RECEIPT=("$built_app" "$selected_app" "$app_id" "$extension_name" "$extension_id" "$(/usr/bin/stat -f '%d:%i' "$selected_app")")
  jobs_deployment_cleanup_build_products "$built_app" "$derived_root" "$app_id" "$extension_name" "$extension_id" || result=$?
  JOBS_DEPLOYMENT_COMMITTED_RECEIPT=("${previous_receipt[@]}")
  return "$result"
}
