#!/usr/bin/env bash
set -euo pipefail

RAW_INSTALL_URL="https://raw.githubusercontent.com/uton88/dan-binary-releases/main/install.sh"
DEFAULT_INSTALL_DIR="${HOME}/dan-runtime"

# 安装阶段专用：只用来拉 domains，避免你自己的 CPA 因无 /v0/management/domains 而安装失败
DEFAULT_BOOTSTRAP_CPA_BASE_URL="https://gpt-up.icoa.pp.ua/"
DEFAULT_BOOTSTRAP_CPA_TOKEN="linuxdo"

# 运行阶段专用：真正写进 dan-web 配置，用于导入/同步你的 CPA
DEFAULT_RUNTIME_CPA_BASE_URL="http://8.220.143.189:8319"
DEFAULT_RUNTIME_CPA_TOKEN="114514"

DEFAULT_MAIL_API_URL="https://gpt-mail.icoa.pp.ua/"
DEFAULT_MAIL_API_KEY="linuxdo"
DEFAULT_THREADS="20"
DEFAULT_PORT="25666"

usage() {
  cat <<'EOF'
用法:
  install_dan_gptup_gptmail.sh install [threads] [port] [install_dir]
  install_dan_gptup_gptmail.sh stop [install_dir]
  install_dan_gptup_gptmail.sh status [install_dir]
  install_dan_gptup_gptmail.sh logs [install_dir] [lines]
  install_dan_gptup_gptmail.sh config [install_dir]

默认参数:
  bootstrap_cpa_base_url = https://gpt-up.icoa.pp.ua/
  bootstrap_cpa_token    = linuxdo
  runtime_cpa_base_url   = http://8.220.143.189:8319
  runtime_cpa_token      = 114514
  mail_api_url           = https://gpt-mail.icoa.pp.ua/
  mail_api_key           = linuxdo
  threads                = 20
  port                   = 25666
  install_dir            = $HOME/dan-runtime

可用环境变量覆盖:
  BOOTSTRAP_CPA_BASE_URL / BOOTSTRAP_CPA_TOKEN
  RUNTIME_CPA_BASE_URL   / RUNTIME_CPA_TOKEN
  MAIL_API_URL           / MAIL_API_KEY
  THREADS                / PORT / INSTALL_DIR
EOF
}

action="${1:-help}"
install_dir_default() {
  printf '%s' "${INSTALL_DIR:-$DEFAULT_INSTALL_DIR}"
}

install_cmd() {
  local threads="${1:-${THREADS:-$DEFAULT_THREADS}}"
  local port="${2:-${PORT:-$DEFAULT_PORT}}"
  local install_dir="${3:-$(install_dir_default)}"

  local bootstrap_cpa_base_url="${BOOTSTRAP_CPA_BASE_URL:-$DEFAULT_BOOTSTRAP_CPA_BASE_URL}"
  local bootstrap_cpa_token="${BOOTSTRAP_CPA_TOKEN:-$DEFAULT_BOOTSTRAP_CPA_TOKEN}"

  local runtime_cpa_base_url="${RUNTIME_CPA_BASE_URL:-$DEFAULT_RUNTIME_CPA_BASE_URL}"
  local runtime_cpa_token="${RUNTIME_CPA_TOKEN:-$DEFAULT_RUNTIME_CPA_TOKEN}"

  local mail_api_url="${MAIL_API_URL:-$DEFAULT_MAIL_API_URL}"
  local mail_api_key="${MAIL_API_KEY:-$DEFAULT_MAIL_API_KEY}"

  echo "[install] install_dir=$install_dir"
  echo "[install] threads=$threads port=$port"
  echo "[install] bootstrap_cpa_base_url=$bootstrap_cpa_base_url"
  echo "[install] runtime_cpa_base_url=$runtime_cpa_base_url"
  echo "[install] mail_api_url=$mail_api_url"

  # 第一步：仅借 bootstrap CPA 拉 domains，确保安装成功
  curl -fsSL "$RAW_INSTALL_URL" | bash -s -- \
    --install-dir "$install_dir" \
    --background \
    --cpa-base-url "$bootstrap_cpa_base_url" \
    --cpa-token "$bootstrap_cpa_token" \
    --mail-api-url "$mail_api_url" \
    --mail-api-key "$mail_api_key" \
    --threads "$threads" \
    --port "$port"

  # 第二步：把真正运行时需要的 CPA 改回你的 CPA
  python3 - <<PY
from pathlib import Path
import json
p = Path(${install_dir@Q}) / 'config' / 'web_config.json'
data = json.loads(p.read_text(encoding='utf-8'))
data['manual_default_threads'] = int(${threads@Q})
data['port'] = int(${port@Q})
data['mail_api_url'] = ${mail_api_url@Q}
data['mail_api_key'] = ${mail_api_key@Q}
data['cpa_base_url'] = ${runtime_cpa_base_url@Q}
data['cpa_token'] = ${runtime_cpa_token@Q}
p.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding='utf-8')
print('[patch] web_config.json 已切回你的 CPA')
PY
}

stop_cmd() {
  local install_dir="${1:-$(install_dir_default)}"
  local pid_file="$install_dir/dan-web.pid"
  if [[ ! -f "$pid_file" ]]; then
    echo "[stop] 未找到 PID 文件: $pid_file"
    return 0
  fi
  local pid
  pid="$(cat "$pid_file" 2>/dev/null || true)"
  if [[ -z "$pid" ]]; then
    echo "[stop] PID 文件为空: $pid_file"
    return 0
  fi
  if kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
    sleep 2
  fi
  if kill -0 "$pid" 2>/dev/null; then
    kill -9 "$pid" 2>/dev/null || true
  fi
  echo "[stop] 已停止 PID=$pid"
}

status_cmd() {
  local install_dir="${1:-$(install_dir_default)}"
  local pid_file="$install_dir/dan-web.pid"
  local log_file="$install_dir/dan-web.log"
  local config_file="$install_dir/config/web_config.json"
  echo "install_dir=$install_dir"
  echo "pid_file=$pid_file"
  echo "log_file=$log_file"
  echo "config_file=$config_file"
  if [[ -f "$pid_file" ]]; then
    local pid
    pid="$(cat "$pid_file" 2>/dev/null || true)"
    echo "pid=$pid"
    ps -p "$pid" -o pid=,stat=,etime=,cmd= 2>/dev/null || true
  else
    echo "pid=not_found"
  fi
  if [[ -f "$config_file" ]]; then
    echo "===== web_config.json ====="
    sed -n '1,220p' "$config_file"
  else
    echo "[status] 未找到配置文件"
  fi
  if [[ -f "$log_file" ]]; then
    echo "===== log tail ====="
    tail -n 40 "$log_file"
  else
    echo "[status] 未找到日志文件"
  fi
}

logs_cmd() {
  local install_dir="${1:-$(install_dir_default)}"
  local lines="${2:-120}"
  local log_file="$install_dir/dan-web.log"
  if [[ ! -f "$log_file" ]]; then
    echo "[logs] 未找到日志文件: $log_file"
    exit 1
  fi
  tail -n "$lines" "$log_file"
}

config_cmd() {
  local install_dir="${1:-$(install_dir_default)}"
  local config_file="$install_dir/config/web_config.json"
  if [[ ! -f "$config_file" ]]; then
    echo "[config] 未找到配置文件: $config_file"
    exit 1
  fi
  sed -n '1,220p' "$config_file"
}

case "$action" in
  install)
    install_cmd "${2:-}" "${3:-}" "${4:-}"
    ;;
  stop)
    stop_cmd "${2:-}"
    ;;
  status)
    status_cmd "${2:-}"
    ;;
  logs)
    logs_cmd "${2:-}" "${3:-}"
    ;;
  config)
    config_cmd "${2:-}"
    ;;
  help|-h|--help|"")
    usage
    ;;
  *)
    echo "未知动作: $action" >&2
    usage >&2
    exit 1
    ;;
esac
