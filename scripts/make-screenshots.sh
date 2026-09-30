#!/bin/bash
# Regenerates docs/statusbar.png and docs/settings.png.
#
# The app renders its own views to PNG (see Capture.swift), so no Screen
# Recording permission is needed. The settings come in through the UserDefaults
# argument domain ("-key value"), which is read-only for this process — your
# real saved API key is never touched.
#
# Requires: python3, ImageMagick (brew install imagemagick)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/DeepSeekBalanceIndicator.app"
PORT="${PORT:-8765}"
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"; kill "${STUB:-}" 2>/dev/null || true' EXIT

cd "$ROOT"
./scripts/build-app.sh >/dev/null

# Stub of the balance endpoint so the screenshots show a real-looking amount.
cat > "$OUT/stub.py" <<'PY'
import json, sys
from http.server import BaseHTTPRequestHandler, HTTPServer

BODY = json.dumps({
    "is_available": True,
    "balance_infos": [{
        "currency": "CNY",
        "total_balance": "110.00",
        "granted_balance": "10.00",
        "topped_up_balance": "100.00",
    }],
}).encode()

class H(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(BODY)))
        self.end_headers()
        self.wfile.write(BODY)
    def log_message(self, *a):
        pass

HTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
PY
python3 "$OUT/stub.py" "$PORT" &
STUB=$!
sleep 1.5

mkdir -p "$ROOT/docs"
"$APP/Contents/MacOS/DeepSeekBalanceIndicator" --capture "$OUT" \
  "-deepseek.apiKey" "screenshot-stub-value" \
  "--endpoint" "http://127.0.0.1:$PORT/user/balance" >/dev/null

# The status item is captured white-on-transparent (it is a template image), so
# lay it on a menu bar strip to make it legible on a white README.
magick "$OUT/menubar.png" -bordercolor none -border 22x9 \
  -background '#1c1c1e' -flatten "$ROOT/docs/statusbar.png"
cp "$OUT/settings.png" "$ROOT/docs/settings.png"

echo "==> wrote:"
magick identify "$ROOT/docs/statusbar.png" "$ROOT/docs/settings.png"
