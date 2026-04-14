#!/bin/bash
# Usage: mmd-dashboard <folder> [port]
# Generates a dashboard page showing all .mmd files in a folder,
# each rendered as a clickable preview that opens in mermaid-live-editor.
# Uses local mermaid.js for fast rendering (~150ms vs ~10s CDN).

set -e

FOLDER="${1:-.}"
PORT="${2:-4000}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SERVE_PORT="${3:-8787}"

# Resolve to absolute path
FOLDER="$(cd "$FOLDER" && pwd)"

# Collect all .mmd files (skip hidden dirs like .Trash)
MMD_FILES=$(find "$FOLDER" -maxdepth 2 -not -path '*/.*' -name "*.mmd" -type f | sort)

if [ -z "$MMD_FILES" ]; then
  echo "No .mmd files found in: $FOLDER"
  exit 1
fi

COUNT=$(echo "$MMD_FILES" | wc -l | tr -d ' ')
echo "Found $COUNT .mmd files in $FOLDER"

# Prepare serve directory
SERVE_DIR=$(mktemp -d /tmp/mmd-serve-XXXX)
MERMAID_LOCAL="$SCRIPT_DIR/node_modules/.pnpm/mermaid@11.14.0/node_modules/mermaid/dist"
ln -s "$MERMAID_LOCAL" "$SERVE_DIR/mermaid-local"
ln -s "$SCRIPT_DIR/static/favicon.svg" "$SERVE_DIR/favicon.svg"

TMPHTML="$SERVE_DIR/index.html"

node -e "
const fs = require('fs');
const path = require('path');
const pako = require('$SCRIPT_DIR/node_modules/pako');
const { fromUint8Array } = require('$SCRIPT_DIR/node_modules/js-base64');

const files = process.argv.slice(1);
const port = '$PORT';

function makeEditUrl(code) {
  const state = JSON.stringify({
    code,
    mermaid: JSON.stringify({ theme: 'default' }),
    panZoom: true, rough: false, grid: true, updateDiagram: true
  });
  const data = new TextEncoder().encode(state);
  const compressed = pako.deflate(data, { level: 9 });
  const b64 = fromUint8Array(compressed, true);
  return 'http://localhost:' + port + '/edit#pako:' + b64;
}

const cards = files.map((f, i) => {
  const code = fs.readFileSync(f, 'utf8').trim();
  const name = path.basename(f, '.mmd');
  const relPath = path.relative('$FOLDER', f);
  const editUrl = makeEditUrl(code);

  // Strip frontmatter ---...--- block for dashboard preview rendering
  let displayCode = code;
  const fmMatch = displayCode.match(/^---[\\s\\S]*?---\\n?/);
  if (fmMatch) {
    displayCode = displayCode.slice(fmMatch[0].length);
  }
  const escaped = displayCode.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');

  // Extract %% comments from the file (after frontmatter if present, before diagram code)
  const lines = code.split('\\n');
  const commentLines = [];
  let k = 0;
  // Skip frontmatter ---...--- block if present
  if (lines[k] && lines[k].trim() === '---') {
    k++;
    while (k < lines.length && lines[k].trim() !== '---') k++;
    k++; // skip closing ---
  }
  // Collect %% comment lines
  for (; k < lines.length; k++) {
    const trimmed = lines[k].trim();
    if (trimmed.startsWith('%%')) {
      commentLines.push(trimmed.replace(/^%%\\s*/, ''));
    } else if (trimmed === '') {
      continue;
    } else {
      break;
    }
  }
  const description = commentLines.join('<br>').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/&lt;br&gt;/g,'<br>');
  const descHtml = description
    ? \`<div class=\"card-desc\">\${description}</div>\`
    : '';

  return \`
    <a href=\"\${editUrl}\" target=\"_blank\" class=\"card\" title=\"\${relPath}\">
      <div class=\"diagram-container\">
        <pre class=\"mermaid\" id=\"diagram-\${i}\">\${escaped}</pre>
      </div>
      <div class=\"card-footer\">
        <span class=\"card-name\">\${name}</span>
        <span class=\"card-path\">\${relPath}</span>
      </div>\${descHtml}
    </a>\`;
}).join('\\n');

const html = \`<!DOCTYPE html>
<html lang=\"en\">
<head>
<meta charset=\"UTF-8\">
<link rel=\"icon\" type=\"image/svg+xml\" href=\"/favicon.svg\">
<title>Mermaid Dashboard - \${files.length} diagrams</title>
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body {
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
    background: #0f0f0f; color: #e0e0e0; padding: 24px;
  }
  h1 { font-size: 20px; font-weight: 500; margin-bottom: 8px; color: #fff; }
  .subtitle { font-size: 13px; color: #888; margin-bottom: 4px; }
  .timing { font-size: 13px; color: #4a9eff; margin-bottom: 24px; }
  .grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(420px, 1fr));
    gap: 20px;
  }
  .card {
    display: flex; flex-direction: column;
    background: #1a1a1a; border: 1px solid #2a2a2a; border-radius: 12px;
    overflow: hidden; text-decoration: none; color: inherit;
    transition: border-color 0.2s, box-shadow 0.2s;
  }
  .card:hover {
    border-color: #4a9eff; box-shadow: 0 0 0 1px #4a9eff;
  }
  .diagram-container {
    padding: 20px; min-height: 180px; max-height: 360px; overflow: hidden;
    display: flex; align-items: center; justify-content: center;
    background: #fff; position: relative;
  }
  .diagram-container::after {
    content: ''; position: absolute; bottom: 0; left: 0; right: 0;
    height: 40px; background: linear-gradient(transparent, #fff);
    pointer-events: none;
  }
  .diagram-container svg { max-width: 100%; max-height: 320px; }
  .card-footer {
    padding: 12px 16px; display: flex; justify-content: space-between;
    align-items: center; border-top: 1px solid #2a2a2a;
  }
  .card-name { font-size: 14px; font-weight: 600; color: #fff; }
  .card-path { font-size: 11px; color: #666; font-family: monospace; }
  .card-desc {
    padding: 10px 16px 14px; font-size: 12px; color: #aaa;
    line-height: 1.5; border-top: 1px solid #222;
  }
</style>
</head>
<body>
  <h1>Mermaid Dashboard</h1>
  <p class=\"subtitle\">\${files.length} diagrams from $FOLDER</p>
  <p class=\"timing\" id=\"timing\">Rendering...</p>
  <div class=\"grid\">\${cards}</div>
  <script>window.__t0 = performance.now();<\/script>
  <script type=\"module\">
    import mermaid from '/mermaid-local/mermaid.esm.min.mjs';
    mermaid.initialize({ startOnLoad: false, theme: 'default', securityLevel: 'loose' });
    await mermaid.run();
    document.getElementById('timing').textContent =
      'Rendered in ' + (performance.now() - window.__t0).toFixed(0) + ' ms';
  <\/script>
</body>
</html>\`;

fs.writeFileSync('$TMPHTML', html);
" $MMD_FILES

# Auto-start live editor dev server on $PORT if not running
DEV_STARTED_BY_US=0
if lsof -ti:"$PORT" >/dev/null 2>&1; then
  echo "Live editor already running on :$PORT"
else
  echo "Starting live editor dev server on :$PORT ..."
  ("$SCRIPT_DIR/mmd-serve.sh" "$PORT" > /tmp/mmd-dev.log 2>&1) &
  DEV_STARTED_BY_US=1
  # Wait up to ~10s for port to open
  for _ in $(seq 1 40); do
    if lsof -ti:"$PORT" >/dev/null 2>&1; then break; fi
    sleep 0.25
  done
  if lsof -ti:"$PORT" >/dev/null 2>&1; then
    echo "Live editor ready on http://localhost:$PORT/"
  else
    echo "Warning: dev server did not open :$PORT in time (see /tmp/mmd-dev.log)"
  fi
fi

# Cleanup: kill dashboard server, ask about dev server if we started it
cleanup() {
  # Stop dashboard http server
  if [ -n "${SERVER_PID:-}" ]; then
    kill "$SERVER_PID" 2>/dev/null || true
  fi
  # Ask before killing the dev server — only if we started it
  if [ "$DEV_STARTED_BY_US" = "1" ]; then
    echo ""
    printf "关闭由 mmd-dashboard 启动的 dev server (port %s)? [y/N] " "$PORT"
    read -r ans < /dev/tty || ans=""
    case "$ans" in
      y|Y|yes|YES)
        lsof -ti:"$PORT" | xargs kill 2>/dev/null || true
        echo "Dev server stopped."
        ;;
      *)
        echo "Dev server left running on :$PORT."
        ;;
    esac
  fi
}
trap cleanup EXIT

# Kill any old dashboard server on the same port
lsof -ti:"$SERVE_PORT" | xargs kill 2>/dev/null || true

# Start HTTP server and open browser
echo "Starting dashboard server on http://localhost:$SERVE_PORT ..."
cd "$SERVE_DIR"
python3 -m http.server "$SERVE_PORT" --bind 127.0.0.1 &
SERVER_PID=$!
sleep 1

open "http://localhost:${SERVE_PORT}/"

echo "Dashboard: http://localhost:${SERVE_PORT}/"
echo "Press Ctrl+C to stop."
wait $SERVER_PID
