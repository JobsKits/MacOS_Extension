#!/bin/zsh
# Created by Jobs on 2026年11月12日，星期四.
# 仅供 source：先核对官方公开兼容 Release，再按需请求授权下载元数据；不安装工具或修改项目。
typeset -g JOBS_SIM_HARMONY_OFFICIAL_DIR="${${(%):-%x}:A:h}"

jobs_sim_harmony_official_data() {
  /usr/bin/osascript -l JavaScript "$JOBS_SIM_HARMONY_OFFICIAL_DIR/鸿蒙官方更新.jxa" "$@"
}

# 每次 HTTP 有界；仅传输中断和服务器暂时故障返回 75，认证及配置错误立即停止。
jobs_sim_harmony_official_request_once() {
  local name="$1" payload="$2" output="$3" endpoint="$4" result=0 http="" timestamp=""
  timestamp="$(/bin/date -u +%Y%m%dT%H%M%SZ)" || return 67
  : > "$output" || return 67
  run_bounded 40 "$output.http" /usr/bin/curl --silent --show-error --connect-timeout 10 --max-time 30 \
    --max-filesize 2097152 --proto '=https' --tlsv1.2 --request POST \
    --header 'Content-Type: application/json;charset=UTF-8' --header 'Origin: https://developer.huawei.com' \
    --header "X-HD-DATE: $timestamp" --header "X-HD-SERIALNO: ${RANDOM}${RANDOM}" \
    --data-binary "@$payload" --output "$output" --write-out '%{http_code}' "$endpoint" || result=$?
  (( result != 130 && result != 143 )) || return "$result"
  http="$(/usr/bin/tail -c 3 "$output.http" 2>/dev/null)"
  case "$result" in
    5|6|7|18|28|52|55|56|92|124) return 75 ;;
  esac
  if (( result == 0 )); then
    case "$http" in 408|425|429|5<->) return 75 ;; esac
  fi
  if (( result != 0 )) || [[ "$http" != 200 ]]; then
    log "✖ 鸿蒙官方 $name 更新核验未就绪（curl=$result，HTTP=${http:-未知}）；未下载旧 CLT。原始记录：$output.http"
    return 67
  fi
}

jobs_sim_harmony_official_backoff() {
  /bin/sleep "$1"
}

# 重试只重放元数据 HTTP；不会重放解压、创建、启动或业务工程准备。
jobs_sim_harmony_official_request() {
  local attempt=1 delay=1 result=0
  while true; do
    result=0
    jobs_sim_harmony_official_request_once "$@" || result=$?
    (( result == 75 )) || return "$result"
    /bin/cp "$3.http" "$3.last-network-failure.http" || return 67
    /bin/cp "$3" "$3.last-network-failure.json" || return 67
    log "⚠ 鸿蒙官方 $1 元数据网络/服务暂未就绪（第 $attempt 次），${delay} 秒后自动重试；Ctrl+C 可停止。失败记录：$3.last-network-failure.http"
    jobs_sim_harmony_official_backoff "$delay" || {
      result=$?
      (( result != 143 )) || return 143
      return 130
    }
    (( attempt += 1 ))
    (( delay >= 30 )) || delay=$(( delay * 2 ))
    (( delay <= 30 )) || delay=30
  done
}

# current 仅来自真实 CLT version.txt；收据 JSON 不含可执行 Shell，也不接受浏览器 Cookie。
jobs_sim_harmony_official_update() {
  local current="${1:-}" receipt="$2" version_file="${3:-}" prefix="$LOG_FILE.harmony-official" state="" latest="" platform="" result=0
  [[ "$receipt" == /* && -f "$receipt" && ! -L "$receipt" && ! -s "$receipt" ]] || { log '✖ 官方更新收据必须是本轮预建的空普通文件。'; return 67; }
  if [[ -n "$current" && ( ! -f "$version_file" || -L "$version_file" || "${version_file:t}" != version.txt ) ]]; then
    log '✖ 未能核验本机 CLT 的 version.txt；Emulator、IDE 或 SDK 版本不能代替，未报告最新。'
    return 67
  fi
  case "$(/usr/bin/uname -m)" in arm64) platform=3 ;; x86_64) platform=2 ;; *) log '✖ 官方 CLT 更新不支持本机架构。'; return 67 ;; esac
  print -r -- '{"centerPrefix":"doccenter","language":"en","level2NodeAlias":"release-notes","isApi":0,"fileName":"deveco-studio-new-features-611"}' > "$prefix.release.request" || return 67
  log '▶ 核验华为官方公开 6.1 兼容 Release 说明与实际 CLT 版本；仅缺失/落后时请求归档授权。'
  jobs_sim_harmony_official_request release "$prefix.release.request" "$prefix.release.json" \
    'https://svc-drcn.developer.huawei.com/community/servlet/consumer/cn/documentPortal/getCenterDocument' || return $?
  run_bounded 20 "$prefix.public.json" jobs_sim_harmony_official_data release "$prefix.release.json" "$current" "$version_file" || result=$?
  (( result != 130 && result != 143 )) || return "$result"
  if (( result != 0 )); then log "✖ 官方公开 Release 说明无法核验，未把未知状态当作最新；详情：$prefix.public.json"; return 67; fi
  state="$(jobs_sim_harmony_official_data field "$prefix.public.json" state)" || return 67
  latest="$(jobs_sim_harmony_official_data field "$prefix.public.json" version)" || return 67
  if [[ "$state" == ready ]]; then
    /bin/cp "$prefix.public.json" "$receipt" || return 67
    log "✓ 本机 CLT $current 已达到官方公开兼容 Release $latest；继续实际工具能力复检。"
    return 0
  fi
  log "▶ 本机 CLT ${current:-尚未核验/缺失} 需准备官方兼容 Release $latest 或更新；先核验归档权限、大小与 SHA-256。"
  jobs_sim_harmony_official_data request catalog > "$prefix.catalog.request" || return 67
  jobs_sim_harmony_official_request catalog "$prefix.catalog.request" "$prefix.catalog.json" \
    'https://svc-drcn.developer.huawei.com/svc/community/common/v1/delegate' || return $?
  result=0
  run_bounded 20 "$prefix.candidate.json" jobs_sim_harmony_official_data catalog "$prefix.catalog.json" "$platform" "$latest" || result=$?
  (( result != 130 && result != 143 )) || return "$result"
  if (( result != 0 )); then
    log "✖ 官方下载目录要求登录/授权，或正式元数据未完整返回（未就绪 67）；未下载固定旧版。原响应：$prefix.catalog.json；解析：$prefix.candidate.json"
    log '请通过官方渠道取得所需 Release 及其来源/摘要；仅在浏览器登录不会给匿名探针增加认证，原样重试不保证成功。'
    return 67
  fi
  jobs_sim_harmony_official_data request download "$prefix.candidate.json" > "$prefix.download.request" || return 67
  jobs_sim_harmony_official_request download "$prefix.download.request" "$prefix.download.json" \
    'https://svc-drcn.developer.huawei.com/svc/community/common/v1/delegate' || return $?
  result=0
  run_bounded 20 "$prefix.verified.json" jobs_sim_harmony_official_data download "$prefix.download.json" "$prefix.candidate.json" || result=$?
  (( result != 130 && result != 143 )) || return "$result"
  if (( result != 0 )); then log "✖ 官方归档 URL/权限/协议未就绪，未下载安装；详情：$prefix.verified.json"; return 67; fi
  /bin/cp "$prefix.verified.json" "$receipt" || return 67
  log "✓ 已验证官方归档元数据；下载与解压后仍须核对归档大小、SHA-256、实际 CLT version.txt 和工具能力。"
}
