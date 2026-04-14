#!/bin/bash
# Usage: mmd-open <file.mmd> [port]
# Opens a local mermaid file in mermaid-live-editor running on localhost.

set -e

if [ -z "$1" ]; then
  echo "Usage: mmd-open <file.mmd> [port]"
  echo "  port defaults to 4000"
  exit 1
fi

FILE="$1"
PORT="${2:-4000}"

if [ ! -f "$FILE" ]; then
  echo "Error: File not found: $FILE"
  exit 1
fi

# Read file, build state JSON, pako-deflate + base64url encode
HASH=$(node -e "
const fs = require('fs');
const pako = require('$(dirname "$0")/node_modules/pako');
const code = fs.readFileSync('$FILE', 'utf8');
const state = JSON.stringify({
  code,
  mermaid: JSON.stringify({ theme: 'default' }),
  panZoom: true,
  rough: false,
  grid: true,
  updateDiagram: true
});
const compressed = pako.deflate(new TextEncoder().encode(state), { level: 9 });
// base64url encoding (no padding)
const b64 = Buffer.from(compressed).toString('base64')
  .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
console.log('pako:' + b64);
")

open "http://localhost:${PORT}/edit#${HASH}"
