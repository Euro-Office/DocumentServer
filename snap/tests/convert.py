# SPDX-FileCopyrightText: 2026 Euro-Office contributors
# SPDX-License-Identifier: AGPL-3.0-only
"""Converts a file with a running document server: convert.py <url> <jwt secret>"""

import base64
import hashlib
import hmac
import http.server
import json
import sys
import threading
import time
import urllib.request

URL, SECRET = sys.argv[1:]
SIGNATURES = {"docx": b"PK", "odt": b"PK", "pdf": b"%PDF"}


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"Smoke test\n")

    def log_message(self, *args):
        pass


def b64(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=")


def sign(payload):
    data = b64(b'{"alg":"HS256","typ":"JWT"}') + b"." + b64(json.dumps(payload).encode())
    return (data + b"." + b64(hmac.new(SECRET.encode(), data, hashlib.sha256).digest())).decode()


def convert(output, token=True):
    payload = {
        "async": False,
        "filetype": "txt",
        "outputtype": output,
        "key": f"{output}{time.time_ns()}",
        "url": f"http://127.0.0.1:{server.server_port}/test.txt",
    }
    if token:
        payload["token"] = sign(payload)
    headers = {"Content-Type": "application/json", "Accept": "application/json"}
    request = urllib.request.Request(f"{URL}/converter", json.dumps(payload).encode(), headers)
    return json.load(urllib.request.urlopen(request, timeout=120))


server = http.server.HTTPServer(("127.0.0.1", 0), Handler)
threading.Thread(target=server.serve_forever, daemon=True).start()

if "fileUrl" in convert("docx", token=False):
    sys.exit("converted without a token")
for output, signature in SIGNATURES.items():
    result = convert(output)
    if "fileUrl" not in result:
        sys.exit(f"{output}: {result}")
    if not urllib.request.urlopen(result["fileUrl"], timeout=60).read().startswith(signature):
        sys.exit(f"{output}: not a valid file")
    print(f"ok: converted to {output}")
