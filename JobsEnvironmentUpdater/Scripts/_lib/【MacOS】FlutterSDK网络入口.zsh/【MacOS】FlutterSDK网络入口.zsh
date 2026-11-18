#!/bin/zsh
# 脚本自述：只定义SDK子进程入口；source时不检测网络、不下载、不修改Shell环境。
typeset -g JOBS_FLUTTER_NETWORK_RESOURCE_ROOT="${${(%):-%x}:A:h:h}"
# 本任务缓存由网络模块创建，源与代理始终仅传给子进程。
jobs_flutter_sdk_command() {
  emulate -L zsh
  local module="$JOBS_FLUTTER_NETWORK_RESOURCE_ROOT/【MacOS】FlutterSDK网络选路.zsh/【MacOS】FlutterSDK网络选路.zsh"
  local adapter="$JOBS_FLUTTER_NETWORK_RESOURCE_ROOT/【MacOS】FlutterSDK命令适配.sh/【MacOS】FlutterSDK命令适配.sh"
  [[ -f "$module" && -f "$adapter" ]] || { print -u2 '✖ 缺少随包Flutter SDK网络资源，请重新部署完整_lib。'; return 1; }
  if [[ -z "${JOBS_FLUTTER_NETWORK_TASK_CACHE:-}" ]]; then
    local created_cache=""
    created_cache="$(/bin/zsh "$module" --cache-dir)" || return $?
    typeset -g JOBS_FLUTTER_NETWORK_TASK_CACHE="$created_cache"
  fi
  JOBS_FLUTTER_ROUTE_CACHE_DIR="$JOBS_FLUTTER_NETWORK_TASK_CACHE" \
  JOBS_FLUTTER_ROUTE_LOG="$JOBS_FLUTTER_NETWORK_TASK_CACHE/entry-network.log" \
    /bin/sh "$adapter" "$@"
}
# SDK版本清单只读远程原始URL，解析和项目配置写入留给调用者执行一次。
jobs_flutter_sdk_versions() {
  emulate -L zsh
  local module="$JOBS_FLUTTER_NETWORK_RESOURCE_ROOT/【MacOS】FlutterSDK网络选路.zsh/【MacOS】FlutterSDK网络选路.zsh"
  local url="${FLUTTER_STORAGE_BASE_URL-https://storage.googleapis.com}/flutter_infra_release/releases/releases_macos.json"
  if [[ -z "${JOBS_FLUTTER_NETWORK_TASK_CACHE:-}" ]]; then
    local created_cache=""
    created_cache="$(/bin/zsh "$module" --cache-dir)" || return $?
    typeset -g JOBS_FLUTTER_NETWORK_TASK_CACHE="$created_cache"
  fi
  JOBS_FLUTTER_ROUTE_CACHE_DIR="$JOBS_FLUTTER_NETWORK_TASK_CACHE" \
  JOBS_FLUTTER_ROUTE_MODE=source JOBS_FLUTTER_ROUTE_SOURCE_URL="$url" \
  JOBS_FLUTTER_ROUTE_EXPECTED_TEXT='"releases"' JOBS_FLUTTER_ROUTE_CAPTURE_OUTPUT=1 \
    /bin/zsh "$module" --run 'Flutter SDK发布清单' "$JOBS_FLUTTER_NETWORK_TASK_CACHE/releases.log" '' '' \
      /usr/bin/curl -fsSL --connect-timeout 10 --max-time 60 "$url"
}
