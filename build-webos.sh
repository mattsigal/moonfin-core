#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WEBOS_DIR="$REPO_ROOT/webos"
BUILD_DIR="$REPO_ROOT/build/web"
STAGE_DIR="$REPO_ROOT/build/webos-stage"
OUTPUT_DIR="$REPO_ROOT/build/webos"
WEBOS_KEY_DEBUG="${WEBOS_KEY_DEBUG:-0}"

# FORCE_TV is compile-time to avoid fragile runtime JS interop checks.
DART_DEFINES="--dart-define=FORCE_TV=true"
if [[ "$WEBOS_KEY_DEBUG" == "1" || "$WEBOS_KEY_DEBUG" == "true" ]]; then
  DART_DEFINES="$DART_DEFINES --dart-define=TV_KEY_DEBUG=true"
fi
flutter build web --release $DART_DEFINES

# Stage a copy for webOS packaging. Keep main.dart.js; remove CanvasKit
# to reduce size for low-resource TVs.
rm -rf "$STAGE_DIR"
cp -r "$BUILD_DIR" "$STAGE_DIR"
rm -rf "$STAGE_DIR/canvaskit"

# Use a relative base href for file:// loading on webOS.
sed -i 's|<base href="/">|<base href="./">|' "$STAGE_DIR/index.html"

# Force TV mode for all webOS package variants, regardless of user agent quirks.
sed -i '/<head>/a\  <script>window.__MOONFIN_WEBOS__ = true;<\/script>' "$STAGE_DIR/index.html"

# Optional: enable verbose key diagnostics in packaged builds.
if [[ "$WEBOS_KEY_DEBUG" == "1" || "$WEBOS_KEY_DEBUG" == "true" ]]; then
  sed -i '/<head>/a\  <script>window.__MOONFIN_KEY_DEBUG__ = true;<\/script>' "$STAGE_DIR/index.html"
fi

# Use a minimal ES5 bootstrap to avoid optional chaining in older webOS.
cat > "$STAGE_DIR/flutter_bootstrap.js" <<'EOF'
(function () {
  var script = document.createElement('script');
  script.type = 'application/javascript';
  script.src = 'main.dart.js';
  document.body.appendChild(script);
})();
EOF

cp "$WEBOS_DIR/appinfo.json" \
  "$WEBOS_DIR/icon-80.png" \
  "$WEBOS_DIR/icon-130.png" \
  "$WEBOS_DIR/splash.png" \
  "$STAGE_DIR/"

mkdir -p "$OUTPUT_DIR"

npx ares-package "$STAGE_DIR" -o "$OUTPUT_DIR" --no-minify

echo "webOS IPK created in: $OUTPUT_DIR"
