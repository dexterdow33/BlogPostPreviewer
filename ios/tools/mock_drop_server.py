#!/usr/bin/env python3
"""A local stand-in for the GSR Drop Box REST API, for testing the app's real HTTP code.

It answers start / add / chunk / remove / finish the way ios/reference/gsr-dropbox-1.0.0.js
expects the WordPress plugin to, and keeps everything in memory. It is not the plugin and
says nothing about how the plugin stores files; it only checks the requests the app makes.

  python3 ios/tools/mock_drop_server.py --port 8787
  GSR_MOCK_DROP_URL=http://127.0.0.1:8787/wp-json/gsr-drop/v1/ swift test   # in ios/GSRKit

GET /_state returns what was received, for the tests to check.
No third-party dependencies.
"""
import argparse
import json
import secrets
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

PREFIX = "/wp-json/gsr-drop/v1/"
FORMS = {"tips", "story", "inside", "nothing"}
LIMITS = {"chunk": 65536, "maxFile": 10 * 1024 * 1024, "maxFiles": 50, "maxTotal": 50 * 1024 * 1024}

lock = threading.Lock()
sessions = {}  # token -> {"form", "files": {id: {...}}, "finished": None}
next_id = [1]


class Handler(BaseHTTPRequestHandler):
    server_version = "GSRMockDrop/1.0"

    def log_message(self, fmt, *args):  # quiet
        pass

    def reply(self, status, obj):
        body = json.dumps(obj).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=UTF-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def error(self, status, code, message):
        self.reply(status, {"code": code, "message": message, "data": {"status": status}})

    def body(self):
        n = int(self.headers.get("Content-Length") or 0)
        return self.rfile.read(n) if n else b""

    def json_body(self):
        if not (self.headers.get("Content-Type") or "").startswith("application/json"):
            return None
        try:
            return json.loads(self.body() or b"{}")
        except ValueError:
            return None

    def do_GET(self):
        if self.path == "/_state":
            with lock:
                out = {}
                for t, s in sessions.items():
                    out[t] = {
                        "form": s["form"],
                        "finished": s["finished"],
                        "files": {str(i): {"name": f["name"], "size": f["size"], "type": f["type"],
                                           "received": len(f["data"]), "removed": f["removed"],
                                           "sha": __import__("hashlib").sha256(bytes(f["data"])).hexdigest()}
                                  for i, f in s["files"].items()},
                    }
            return self.reply(200, out)
        self.error(404, "rest_no_route", "No route was found matching the URL and request method.")

    def do_POST(self):
        url = urlparse(self.path)
        if not url.path.startswith(PREFIX):
            return self.error(404, "rest_no_route", "No route was found matching the URL and request method.")
        route = url.path[len(PREFIX):]
        q = {k: v[0] for k, v in parse_qs(url.query, keep_blank_values=True).items()}
        with lock:
            if route == "start":
                b = self.json_body()
                if b is None:
                    return self.error(400, "gsrdb_json", "Send JSON.")
                if b.get("form") not in FORMS:
                    return self.error(400, "gsrdb_form", "Unknown form.")
                if b.get("website"):
                    return self.error(400, "gsrdb_spam", "No.")
                # Tokens with characters that must be escaped in a query string.
                token = secrets.token_urlsafe(12) + "+/="
                sessions[token] = {"form": b["form"], "files": {}, "finished": None}
                return self.reply(200, dict(token=token, **LIMITS))
            if route == "add":
                b = self.json_body()
                s = sessions.get((b or {}).get("token"))
                if not s or s["finished"]:
                    return self.error(410, "gsrdb_gone", "That upload session has ended.")
                if not isinstance(b.get("size"), int) or b["size"] < 0 or b["size"] > LIMITS["maxFile"]:
                    return self.error(400, "gsrdb_size", "Bad size.")
                fid = next_id[0]
                next_id[0] += 1
                s["files"][fid] = {"name": b.get("name", ""), "size": b["size"], "type": b.get("type", ""),
                                   "data": bytearray(), "removed": False}
                return self.reply(200, {"id": fid})
            if route == "chunk":
                s = sessions.get(q.get("token"))
                if not s or s["finished"]:
                    return self.error(410, "gsrdb_gone", "That upload session has ended.")
                try:
                    f = s["files"][int(q.get("file", ""))]
                    offset = int(q.get("offset", ""))
                except (KeyError, ValueError):
                    return self.error(404, "gsrdb_file", "No such file.")
                if self.headers.get("Content-Type") != "application/octet-stream":
                    return self.error(415, "gsrdb_type", "Send bytes.")
                data = self.body()
                if offset != len(f["data"]):
                    return self.reply(409, {"code": "gsrdb_offset", "received": len(f["data"])})
                if len(data) > LIMITS["chunk"] or len(f["data"]) + len(data) > f["size"]:
                    return self.error(400, "gsrdb_size", "Too many bytes.")
                f["data"].extend(data)
                return self.reply(200, {"received": len(f["data"])})
            if route == "remove":
                b = self.json_body() or {}
                s = sessions.get(b.get("token"))
                if not s:
                    return self.error(410, "gsrdb_gone", "That upload session has ended.")
                f = s["files"].get(b.get("file"))
                if f:
                    f["removed"] = True
                return self.reply(200, {"ok": True})
            if route == "finish":
                b = self.json_body()
                s = sessions.get((b or {}).get("token"))
                if not s or s["finished"]:
                    return self.error(410, "gsrdb_gone", "That upload session has ended.")
                for f in s["files"].values():
                    if not f["removed"] and len(f["data"]) != f["size"]:
                        return self.error(400, "gsrdb_incomplete", "A file is incomplete.")
                s["finished"] = {"main": b.get("main", ""), "fields": b.get("fields", {})}
                return self.reply(200, {"ok": True})
        self.error(404, "rest_no_route", "No route was found matching the URL and request method.")


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--port", type=int, default=8787)
    args = ap.parse_args()
    httpd = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    print(f"Mock GSR Drop Box on http://127.0.0.1:{args.port}{PREFIX}", flush=True)
    httpd.serve_forever()


if __name__ == "__main__":
    main()
