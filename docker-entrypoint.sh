#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-/opt/dan-runtime}"
CONFIG_FILE="$INSTALL_DIR/config/web_config.json"
PORT_VALUE="${PORT:-${DAN_PORT:-25666}}"
THREADS_VALUE="${THREADS:-30}"
BRIDGE_PORT_VALUE="${BRIDGE_PORT:-18319}"
MAIL_API_URL_VALUE="${MAIL_API_URL:-https://gpt-mail.icoa.pp.ua/}"
MAIL_API_KEY_VALUE="${MAIL_API_KEY:-linuxdo}"
BOOTSTRAP_CPA_BASE_URL_VALUE="${BOOTSTRAP_CPA_BASE_URL:-https://gpt-up.icoa.pp.ua/}"
BOOTSTRAP_CPA_TOKEN_VALUE="${BOOTSTRAP_CPA_TOKEN:-linuxdo}"
RUNTIME_CPA_BASE_URL_VALUE="${RUNTIME_CPA_BASE_URL:-http://8.220.143.189:8319}"
RUNTIME_CPA_TOKEN_VALUE="${RUNTIME_CPA_TOKEN:-114514}"
UPLOAD_API_URL_VALUE="${UPLOAD_API_URL:-${RUNTIME_CPA_BASE_URL_VALUE%/}/v0/management/auth-files}"
UPLOAD_API_TOKEN_VALUE="${UPLOAD_API_TOKEN:-${RUNTIME_CPA_TOKEN_VALUE}}"

CPA_BRIDGE_PORT="$BRIDGE_PORT_VALUE" \
CPA_DOMAINS_UPSTREAM="$BOOTSTRAP_CPA_BASE_URL_VALUE" \
CPA_DOMAINS_TOKEN="$BOOTSTRAP_CPA_TOKEN_VALUE" \
CPA_RUNTIME_UPSTREAM="$RUNTIME_CPA_BASE_URL_VALUE" \
CPA_RUNTIME_TOKEN="$RUNTIME_CPA_TOKEN_VALUE" \
python3 /usr/local/bin/cpa-bridge.py &

python3 - <<PY
from pathlib import Path
import json
p = Path(${CONFIG_FILE@Q})
data = json.loads(p.read_text(encoding='utf-8'))
bridge_port = int(${BRIDGE_PORT_VALUE@Q})
data['manual_default_threads'] = int(${THREADS_VALUE@Q})
data['mail_api_url'] = ${MAIL_API_URL_VALUE@Q}
data['mail_api_key'] = ${MAIL_API_KEY_VALUE@Q}
data['cpa_base_url'] = f'http://127.0.0.1:{bridge_port}'
data['cpa_token'] = ${RUNTIME_CPA_TOKEN_VALUE@Q}
data['port'] = int(${PORT_VALUE@Q})
p.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding='utf-8')
print('[entrypoint] web_config patched')
print('[entrypoint] port=', data['port'])
print('[entrypoint] threads=', data['manual_default_threads'])
print('[entrypoint] cpa_base_url=', data['cpa_base_url'])
print('[entrypoint] mail_api_url=', data['mail_api_url'])
print('[entrypoint] runtime_cpa_upstream=', ${RUNTIME_CPA_BASE_URL_VALUE@Q})
PY

python3 - <<PY
from pathlib import Path
import json
p = Path(${INSTALL_DIR@Q}) / 'config.json'
data = json.loads(p.read_text(encoding='utf-8'))
data['upload_api_url'] = ${UPLOAD_API_URL_VALUE@Q}
data['upload_api_token'] = ${UPLOAD_API_TOKEN_VALUE@Q}
p.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding='utf-8')
print('[entrypoint] upload_api_url=', data['upload_api_url'])
PY

exec "$INSTALL_DIR/dan-web"

