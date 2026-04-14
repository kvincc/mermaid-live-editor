#!/bin/bash
# Usage: mmd-serve [port]
# Wrapper around `pnpm dev` that passes --port to vite, so we don't need to
# patch upstream vite.config.js (default port 3000 there) and can keep a clean
# merge path from mermaid-js/mermaid-live-editor.

set -e

PORT="${1:-4000}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

cd "$SCRIPT_DIR"
exec pnpm dev -- --port "$PORT"
