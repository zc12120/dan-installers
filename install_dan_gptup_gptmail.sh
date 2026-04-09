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
DEFAULT_BRIDGE_PORT="18319"
DEFAULT_UPLOAD_API_URL="${DEFAULT_RUNTIME_CPA_BASE_URL}/v0/management/auth-files"
DEFAULT_UPLOAD_API_TOKEN="${DEFAULT_RUNTIME_CPA_TOKEN}"

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
  bridge_port            = 18319
  upload_api_url         = http://8.220.143.189:8319/v0/management/auth-files
  upload_api_token       = 114514
  mail_api_url           = https://gpt-mail.icoa.pp.ua/
  mail_api_key           = linuxdo
  threads                = 20
  port                   = 25666
  install_dir            = $HOME/dan-runtime

可用环境变量覆盖:
  BOOTSTRAP_CPA_BASE_URL / BOOTSTRAP_CPA_TOKEN
  RUNTIME_CPA_BASE_URL   / RUNTIME_CPA_TOKEN
  BRIDGE_PORT
  UPLOAD_API_URL         / UPLOAD_API_TOKEN
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
  local bridge_port="${BRIDGE_PORT:-$DEFAULT_BRIDGE_PORT}"
  local upload_api_url="${UPLOAD_API_URL:-${runtime_cpa_base_url%/}/v0/management/auth-files}"
  local upload_api_token="${UPLOAD_API_TOKEN:-$runtime_cpa_token}"

  local mail_api_url="${MAIL_API_URL:-$DEFAULT_MAIL_API_URL}"
  local mail_api_key="${MAIL_API_KEY:-$DEFAULT_MAIL_API_KEY}"

  echo "[install] install_dir=$install_dir"
  echo "[install] threads=$threads port=$port"
  echo "[install] bootstrap_cpa_base_url=$bootstrap_cpa_base_url"
  echo "[install] runtime_cpa_base_url=$runtime_cpa_base_url"
  echo "[install] bridge_port=$bridge_port"
  echo "[install] upload_api_url=$upload_api_url"
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

  # 第二步：创建本地 CPA bridge，domains 继续走 bootstrap，其他请求走你的 CPA
  cat > "$install_dir/cpa-bridge.py" <<'PY'
#!/usr/bin/env python3
import gzip
import json
import os
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.error import HTTPError, URLError
from urllib.parse import urlsplit
from urllib.request import Request, urlopen

LISTEN_HOST = os.environ.get('CPA_BRIDGE_HOST', '127.0.0.1')
LISTEN_PORT = int(os.environ.get('CPA_BRIDGE_PORT', '18319'))
DOMAINS_UPSTREAM = os.environ.get('CPA_DOMAINS_UPSTREAM', 'https://gpt-up.icoa.pp.ua').rstrip('/')
DOMAINS_TOKEN = os.environ.get('CPA_DOMAINS_TOKEN', 'linuxdo')
RUNTIME_UPSTREAM = os.environ.get('CPA_RUNTIME_UPSTREAM', 'http://8.220.143.189:8319').rstrip('/')
RUNTIME_TOKEN = os.environ.get('CPA_RUNTIME_TOKEN', '114514')

def join_url(base, path, query):
    if not path.startswith('/'):
        path = '/' + path
    return f"{base}{path}" + (("?" + query) if query else "")

def maybe_decompress(body, headers):
    enc = (headers.get('Content-Encoding') or headers.get('content-encoding') or '').lower()
    if enc == 'gzip' or body[:2] == b'\x1f\x8b':
        try:
            body = gzip.decompress(body)
            headers = dict(headers)
            headers.pop('Content-Encoding', None)
            headers.pop('content-encoding', None)
        except Exception:
            pass
    return body, headers

class Handler(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'

    def _read_body(self):
        length = self.headers.get('Content-Length')
        if not length:
            return b''
        try:
            return self.rfile.read(int(length))
        except Exception:
            return b''

    def _send(self, status, body=b'', headers=None):
        self.send_response(status)
        sent_len = False
        if headers:
            for k, v in headers.items():
                lk = k.lower()
                if lk in ('transfer-encoding', 'connection', 'content-encoding'):
                    continue
                if lk == 'content-length':
                    sent_len = True
                self.send_header(k, v)
        if not sent_len:
            self.send_header('Content-Length', str(len(body)))
        self.send_header('Connection', 'close')
        self.end_headers()
        if body:
            self.wfile.write(body)

    def _proxy(self):
        parsed = urlsplit(self.path)
        path = parsed.path or '/'
        query = parsed.query
        incoming_body = self._read_body()

        if path == '/healthz':
            payload = json.dumps({
                'ok': True,
                'domains_upstream': DOMAINS_UPSTREAM,
                'runtime_upstream': RUNTIME_UPSTREAM,
            }).encode()
            return self._send(200, payload, {'Content-Type': 'application/json'})

        if path.startswith('/v0/management/domains'):
            upstream = DOMAINS_UPSTREAM
            token = DOMAINS_TOKEN
        else:
            upstream = RUNTIME_UPSTREAM
            token = RUNTIME_TOKEN

        url = join_url(upstream, path, query)
        headers = {}
        for k, v in self.headers.items():
            lk = k.lower()
            if lk in ('host', 'content-length', 'connection'):
                continue
            headers[k] = v
        headers['Accept-Encoding'] = 'identity'
        if token:
            headers['Authorization'] = f'Bearer {token}'
            headers['X-API-Key'] = token

        method = self.command
        req = Request(url, data=incoming_body if method not in ('GET', 'HEAD') else None, headers=headers, method=method)
        try:
            with urlopen(req, timeout=30) as resp:
                body = resp.read()
                resp_headers = {k: v for k, v in resp.headers.items()}
                body, resp_headers = maybe_decompress(body, resp_headers)
                return self._send(resp.status, body, resp_headers)
        except HTTPError as e:
            body = e.read()
            resp_headers = {k: v for k, v in e.headers.items()} if e.headers else {}
            body, resp_headers = maybe_decompress(body, resp_headers)
            return self._send(e.code, body, resp_headers)
        except URLError as e:
            payload = json.dumps({'error': 'upstream_unreachable', 'url': url, 'reason': str(e.reason)}).encode()
            return self._send(502, payload, {'Content-Type': 'application/json'})
        except Exception as e:
            payload = json.dumps({'error': 'bridge_failure', 'url': url, 'reason': str(e)}).encode()
            return self._send(500, payload, {'Content-Type': 'application/json'})

    do_GET = do_POST = do_PUT = do_DELETE = do_PATCH = do_HEAD = do_OPTIONS = _proxy

    def log_message(self, fmt, *args):
        sys.stdout.write("%s - - [%s] %s\n" % (self.client_address[0], self.log_date_time_string(), fmt % args))
        sys.stdout.flush()

if __name__ == '__main__':
    srv = ThreadingHTTPServer((LISTEN_HOST, LISTEN_PORT), Handler)
    print(f'CPA bridge listening on http://{LISTEN_HOST}:{LISTEN_PORT}', flush=True)
    srv.serve_forever()
PY
  chmod +x "$install_dir/cpa-bridge.py"

  local bridge_pid_file="$install_dir/cpa-bridge.pid"
  local bridge_log_file="$install_dir/cpa-bridge.log"
  if [[ -f "$bridge_pid_file" ]]; then
    local old_bridge_pid
    old_bridge_pid="$(cat "$bridge_pid_file" 2>/dev/null || true)"
    if [[ -n "$old_bridge_pid" ]] && kill -0 "$old_bridge_pid" 2>/dev/null; then
      kill "$old_bridge_pid" 2>/dev/null || true
      sleep 1
    fi
  fi

  (
    cd "$install_dir"
    CPA_BRIDGE_PORT="$bridge_port" \
    CPA_DOMAINS_UPSTREAM="$bootstrap_cpa_base_url" \
    CPA_DOMAINS_TOKEN="$bootstrap_cpa_token" \
    CPA_RUNTIME_UPSTREAM="$runtime_cpa_base_url" \
    CPA_RUNTIME_TOKEN="$runtime_cpa_token" \
    nohup python3 ./cpa-bridge.py >> "$bridge_log_file" 2>&1 &
    echo $! > "$bridge_pid_file"
  )
  sleep 1

  # 第三步：把 dan-web 配置切到本地 bridge
  python3 - <<PY
from pathlib import Path
import json
p = Path(${install_dir@Q}) / 'config' / 'web_config.json'
data = json.loads(p.read_text(encoding='utf-8'))
data['manual_default_threads'] = int(${threads@Q})
data['port'] = int(${port@Q})
data['mail_api_url'] = ${mail_api_url@Q}
data['mail_api_key'] = ${mail_api_key@Q}
data['cpa_base_url'] = f'http://127.0.0.1:{int(${bridge_port@Q})}'
data['cpa_token'] = ${runtime_cpa_token@Q}
p.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding='utf-8')
print('[patch] web_config.json 已改为本地 CPA bridge')
PY

  python3 - <<PY
from pathlib import Path
import json
p = Path(${install_dir@Q}) / 'config.json'
data = json.loads(p.read_text(encoding='utf-8'))
data['upload_api_url'] = ${upload_api_url@Q}
data['upload_api_token'] = ${upload_api_token@Q}
p.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding='utf-8')
print('[patch] config.json 已改为上传凭证到你的 CPA')
PY

  local pid_file="$install_dir/dan-web.pid"
  if [[ -f "$pid_file" ]]; then
    local old_pid
    old_pid="$(cat "$pid_file" 2>/dev/null || true)"
    if [[ -n "$old_pid" ]] && kill -0 "$old_pid" 2>/dev/null; then
      kill "$old_pid" 2>/dev/null || true
      sleep 1
    fi
  fi

  (
    cd "$install_dir"
    nohup "./dan-web" >> "$install_dir/dan-web.log" 2>&1 &
    echo $! > "$install_dir/dan-web.pid"
  )
}

stop_cmd() {
  local install_dir="${1:-$(install_dir_default)}"
  local pid_file="$install_dir/dan-web.pid"
  local bridge_pid_file="$install_dir/cpa-bridge.pid"

  if [[ -f "$pid_file" ]]; then
    local pid
    pid="$(cat "$pid_file" 2>/dev/null || true)"
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
      sleep 2
    fi
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
      kill -9 "$pid" 2>/dev/null || true
    fi
    echo "[stop] 已停止 dan-web PID=$pid"
  else
    echo "[stop] 未找到 PID 文件: $pid_file"
  fi

  if [[ -f "$bridge_pid_file" ]]; then
    local bridge_pid
    bridge_pid="$(cat "$bridge_pid_file" 2>/dev/null || true)"
    if [[ -n "$bridge_pid" ]] && kill -0 "$bridge_pid" 2>/dev/null; then
      kill "$bridge_pid" 2>/dev/null || true
      sleep 1
    fi
    if [[ -n "$bridge_pid" ]] && kill -0 "$bridge_pid" 2>/dev/null; then
      kill -9 "$bridge_pid" 2>/dev/null || true
    fi
    echo "[stop] 已停止 cpa-bridge PID=$bridge_pid"
  else
    echo "[stop] 未找到 bridge PID 文件: $bridge_pid_file"
  fi
}

status_cmd() {
  local install_dir="${1:-$(install_dir_default)}"
  local pid_file="$install_dir/dan-web.pid"
  local log_file="$install_dir/dan-web.log"
  local bridge_pid_file="$install_dir/cpa-bridge.pid"
  local bridge_log_file="$install_dir/cpa-bridge.log"
  local config_file="$install_dir/config/web_config.json"
  echo "install_dir=$install_dir"
  echo "pid_file=$pid_file"
  echo "log_file=$log_file"
  echo "bridge_pid_file=$bridge_pid_file"
  echo "bridge_log_file=$bridge_log_file"
  echo "config_file=$config_file"
  if [[ -f "$pid_file" ]]; then
    local pid
    pid="$(cat "$pid_file" 2>/dev/null || true)"
    echo "pid=$pid"
    ps -p "$pid" -o pid=,stat=,etime=,cmd= 2>/dev/null || true
  else
    echo "pid=not_found"
  fi
  if [[ -f "$bridge_pid_file" ]]; then
    local bridge_pid
    bridge_pid="$(cat "$bridge_pid_file" 2>/dev/null || true)"
    echo "bridge_pid=$bridge_pid"
    ps -p "$bridge_pid" -o pid=,stat=,etime=,cmd= 2>/dev/null || true
  else
    echo "bridge_pid=not_found"
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
  if [[ -f "$bridge_log_file" ]]; then
    echo "===== bridge log tail ====="
    tail -n 20 "$bridge_log_file"
  else
    echo "[status] 未找到 bridge 日志文件"
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
