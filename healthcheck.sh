#!/bin/sh
set -eu

CODE="$(curl -sS -o /dev/null -w '%{http_code}' "http://127.0.0.1:${GATEWAY_PORT:-8000}/health")"

[ "$CODE" -eq 200 ]
