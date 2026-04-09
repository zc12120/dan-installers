#!/usr/bin/env python3
import gzip
import json
import os
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.error import HTTPError, URLError
from urllib.parse import urlsplit
from urllib.request import Request, urlopen

LISTEN_HOST = os.environ.get("CPA_BRIDGE_HOST", "127.0.0.1")
LISTEN_PORT = int(os.environ.get("CPA_BRIDGE_PORT", "18319"))
DOMAINS_UPSTREAM = os.environ.get("CPA_DOMAINS_UPSTREAM", "https://gpt-up.icoa.pp.ua").rstrip("/")
DOMAINS_TOKEN = os.environ.get("CPA_DOMAINS_TOKEN", "linuxdo")
RUNTIME_UPSTREAM = os.environ.get("CPA_RUNTIME_UPSTREAM", "http://8.220.143.189:8319").rstrip("/")
RUNTIME_TOKEN = os.environ.get("CPA_RUNTIME_TOKEN", "114514")


def join_url(base: str, path: str, query: str) -> str:
    if not path.startswith("/"):
        path = "/" + path
    return f"{base}{path}" + (("?" + query) if query else "")


def maybe_decompress(body: bytes, headers: dict) -> tuple[bytes, dict]:
    enc = (headers.get("Content-Encoding") or headers.get("content-encoding") or "").lower()
    if enc == "gzip" or body[:2] == b"\x1f\x8b":
        try:
            body = gzip.decompress(body)
            headers = dict(headers)
            headers.pop("Content-Encoding", None)
            headers.pop("content-encoding", None)
        except Exception:
            pass
    return body, headers


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def _read_body(self) -> bytes:
        length = self.headers.get("Content-Length")
        if not length:
            return b""
        try:
            return self.rfile.read(int(length))
        except Exception:
            return b""

    def _send(self, status: int, body: bytes = b"", headers: dict | None = None) -> None:
        self.send_response(status)
        sent_len = False
        if headers:
            for k, v in headers.items():
                lk = k.lower()
                if lk in ("transfer-encoding", "connection", "content-encoding"):
                    continue
                if lk == "content-length":
                    sent_len = True
                self.send_header(k, v)
        if not sent_len:
            self.send_header("Content-Length", str(len(body)))
        self.send_header("Connection", "close")
        self.end_headers()
        if body:
            self.wfile.write(body)

    def _proxy(self) -> None:
        parsed = urlsplit(self.path)
        path = parsed.path or "/"
        query = parsed.query
        incoming_body = self._read_body()

        if path == "/healthz":
            payload = json.dumps(
                {
                    "ok": True,
                    "domains_upstream": DOMAINS_UPSTREAM,
                    "runtime_upstream": RUNTIME_UPSTREAM,
                }
            ).encode()
            return self._send(200, payload, {"Content-Type": "application/json"})

        if path.startswith("/v0/management/domains"):
            upstream = DOMAINS_UPSTREAM
            token = DOMAINS_TOKEN
        else:
            upstream = RUNTIME_UPSTREAM
            token = RUNTIME_TOKEN

        url = join_url(upstream, path, query)
        headers = {}
        for k, v in self.headers.items():
            lk = k.lower()
            if lk in ("host", "content-length", "connection"):
                continue
            headers[k] = v
        headers["Accept-Encoding"] = "identity"
        if token:
            headers["Authorization"] = f"Bearer {token}"
            headers["X-API-Key"] = token

        method = self.command
        req = Request(
            url,
            data=incoming_body if method not in ("GET", "HEAD") else None,
            headers=headers,
            method=method,
        )
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
            payload = json.dumps({"error": "upstream_unreachable", "url": url, "reason": str(e.reason)}).encode()
            return self._send(502, payload, {"Content-Type": "application/json"})
        except Exception as e:
            payload = json.dumps({"error": "bridge_failure", "url": url, "reason": str(e)}).encode()
            return self._send(500, payload, {"Content-Type": "application/json"})

    do_GET = do_POST = do_PUT = do_DELETE = do_PATCH = do_HEAD = do_OPTIONS = _proxy

    def log_message(self, fmt, *args):
        sys.stdout.write("%s - - [%s] %s\n" % (self.client_address[0], self.log_date_time_string(), fmt % args))
        sys.stdout.flush()


if __name__ == "__main__":
    srv = ThreadingHTTPServer((LISTEN_HOST, LISTEN_PORT), Handler)
    print(f"CPA bridge listening on http://{LISTEN_HOST}:{LISTEN_PORT}", flush=True)
    srv.serve_forever()
