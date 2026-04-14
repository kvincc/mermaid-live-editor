#!/bin/bash
# Usage: mmd-pako <url-or-pako-string> [output.mmd]
# Extracts the pako-encoded mermaid state from a live-editor URL (or bare
# pako:... string) and writes the diagram source to a .mmd file.
#
# Input forms accepted:
#   https://mermaid.live/edit#pako:eNp...
#   http://localhost:4000/edit#pako:eNp...
#   pako:eNp...
#   eNp...                  (bare base64url payload)
# If no argument is given, reads from stdin (or `pbpaste` on macOS).

set -e

INPUT="${1:-}"
OUT="${2:-}"

if [ -z "$INPUT" ]; then
  if [ ! -t 0 ]; then
    INPUT="$(cat)"
  elif command -v pbpaste >/dev/null 2>&1; then
    INPUT="$(pbpaste)"
  fi
fi

if [ -z "$INPUT" ]; then
  echo "Usage: mmd-pako <url-or-pako-string> [output.mmd]"
  echo "  (or pipe the URL via stdin / leave it on the macOS clipboard)"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Decode + write file via Node (uses repo-local pako)
node -e "
const fs = require('fs');
const path = require('path');
const pako = require('${SCRIPT_DIR}/node_modules/pako');

const raw = process.argv[1].trim();
// Pull out the pako payload regardless of URL shape.
let payload = raw;
const m = raw.match(/pako:([A-Za-z0-9_\-]+)/);
if (m) {
  payload = m[1];
} else {
  // Strip a leading 'pako:' if present, otherwise assume the whole string is the payload.
  payload = payload.replace(/^pako:/, '');
  // If it still looks like a URL, give up.
  if (/^https?:\/\//i.test(payload) || payload.includes('/')) {
    console.error('Error: no pako:... segment found in input.');
    process.exit(1);
  }
}

// base64url -> base64
let b64 = payload.replace(/-/g, '+').replace(/_/g, '/');
while (b64.length % 4) b64 += '=';

let json;
try {
  const compressed = Buffer.from(b64, 'base64');
  const inflated = pako.inflate(compressed);
  json = new TextDecoder().decode(inflated);
} catch (e) {
  console.error('Error: failed to decode pako payload:', e.message);
  process.exit(1);
}

let state;
try {
  state = JSON.parse(json);
} catch (e) {
  console.error('Error: decoded payload is not valid JSON.');
  process.exit(1);
}

const code = state.code;
if (typeof code !== 'string') {
  console.error('Error: decoded state has no .code field.');
  process.exit(1);
}

let out = process.argv[2];
if (!out) {
  const ts = new Date().toISOString().replace(/[:.]/g, '-').replace(/T/, '_').slice(0, 19);
  out = \`diagram-\${ts}.mmd\`;
}
fs.writeFileSync(out, code.endsWith('\n') ? code : code + '\n');
console.log(path.resolve(out));
" "$INPUT" "$OUT"
