#!/usr/bin/env bash
set -Eeuo pipefail

REPO="mohammadhejazirad/install-googleCrome-server"
BRANCH="${BRANCH:-main}"
INSTALL_ROOT="${INSTALL_ROOT:-/opt/chrome-for-testing}"
FORCE="${FORCE:-0}"
RAW="https://raw.githubusercontent.com/$REPO/$BRANCH"

[[ "$EUID" -eq 0 ]] || { echo "Run with sudo/root."; exit 1; }

case "$(uname -m)" in
  x86_64|amd64) PLATFORM="linux64"; CHROME_DIR="chrome-linux64" ;;
  aarch64|arm64) PLATFORM="linux-arm64"; CHROME_DIR="chrome-linux-arm64" ;;
  *) echo "Unsupported architecture: $(uname -m)"; exit 1 ;;
esac

if [[ -r /etc/os-release ]]; then . /etc/os-release; echo "Detected OS: ${PRETTY_NAME:-${ID:-Linux}}"; fi

need_pkg() {
  command -v "$1" >/dev/null 2>&1 && return 0
  command -v apt-get >/dev/null 2>&1 || { echo "Missing command $1 and apt-get is unavailable."; exit 1; }
  apt-get update -y
  apt-get install -y "$2"
}
need_pkg curl curl
need_pkg jq jq
need_pkg unzip unzip

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Reading mirror manifest..."
curl -fL --retry 5 --retry-all-errors "$RAW/manifest.json" -o "$TMP/manifest.json"
LATEST="$(jq -r '.latest_stable // empty' "$TMP/manifest.json")"
[[ "$LATEST" =~ ^[0-9]+(\.[0-9]+){3}$ ]] || { echo "Invalid mirror version."; exit 1; }

ENTRY="$(jq -c --arg v "$LATEST" --arg p "$PLATFORM" '.builds[] | select(.version==$v and .platform==$p)' "$TMP/manifest.json" | head -n1)"
[[ -n "$ENTRY" ]] || { echo "Mirror has no $LATEST / $PLATFORM build."; exit 1; }

CHROME_BIN="$INSTALL_ROOT/$CHROME_DIR/chrome"
INSTALLED=""
[[ -x "$CHROME_BIN" ]] && INSTALLED="$("$CHROME_BIN" --version 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+){3}' | head -n1 || true)"
echo "Installed: ${INSTALLED:-none}"
echo "Mirror latest: $LATEST"
if [[ "$FORCE" != "1" && "$INSTALLED" == "$LATEST" ]]; then
  echo "Chrome is already up to date."
  echo "PUPPETEER_EXECUTABLE_PATH=$CHROME_BIN"
  exit 0
fi

if command -v apt-get >/dev/null 2>&1; then
  apt-get update -y
  PKGS=(ca-certificates fonts-liberation fonts-noto-color-emoji libatk-bridge2.0-0 libcairo2 libcups2 libdbus-1-3 libexpat1 libfontconfig1 libgbm1 libglib2.0-0 libgtk-3-0 libnspr4 libnss3 libpango-1.0-0 libx11-6 libx11-xcb1 libxcb1 libxcomposite1 libxdamage1 libxext6 libxfixes3 libxrandr2 xdg-utils)
  for p in "${PKGS[@]}"; do apt-cache show "$p" >/dev/null 2>&1 && apt-get install -y "$p" || true; done
  if apt-cache show libasound2t64 >/dev/null 2>&1; then apt-get install -y libasound2t64 || true
  elif apt-cache show libasound2 >/dev/null 2>&1; then apt-get install -y libasound2 || true; fi
fi

BASE="chrome/$LATEST/$PLATFORM"
ZIP="$TMP/chrome.zip"
EXPECTED="$(jq -r '.sha256' <<<"$ENTRY")"

if [[ "$(jq -r '.split' <<<"$ENTRY")" == "true" ]]; then
  : > "$ZIP"
  while IFS= read -r part; do
    [[ "$part" =~ ^chrome\.zip\.part-[0-9]{3}$ ]] || { echo "Unsafe part name: $part"; exit 1; }
    echo "Downloading $part"
    curl -fL --retry 5 --retry-all-errors "$RAW/$BASE/$part" >> "$ZIP"
  done < <(jq -r '.parts[]' <<<"$ENTRY")
else
  curl -fL --retry 5 --retry-all-errors "$RAW/$BASE/chrome.zip" -o "$ZIP"
fi

ACTUAL="$(sha256sum "$ZIP" | awk '{print $1}')"
[[ "$ACTUAL" == "$EXPECTED" ]] || { echo "SHA256 verification failed."; exit 1; }
unzip -t "$ZIP" >/dev/null

mkdir "$TMP/extract"
unzip -q "$ZIP" -d "$TMP/extract"
SOURCE="$TMP/extract/$CHROME_DIR"
[[ -f "$SOURCE/chrome" ]] || { echo "Chrome binary missing."; exit 1; }
chmod 0755 "$SOURCE/chrome"

mkdir -p "$INSTALL_ROOT"
TARGET="$INSTALL_ROOT/$CHROME_DIR"
BACKUP="$INSTALL_ROOT/$CHROME_DIR.backup.$$"
case "$TARGET" in
  /opt/chrome-for-testing/chrome-linux64|/opt/chrome-for-testing/chrome-linux-arm64) ;;
  *) [[ "$INSTALL_ROOT" != "/opt/chrome-for-testing" ]] || { echo "Safety path check failed."; exit 1; } ;;
esac

[[ -e "$TARGET" ]] && mv "$TARGET" "$BACKUP"
if ! mv "$SOURCE" "$TARGET"; then
  [[ -e "$BACKUP" ]] && mv "$BACKUP" "$TARGET" || true
  exit 1
fi

TEST="$TMP/test.txt"
if ! "$CHROME_BIN" --version ||
   ! timeout 30 "$CHROME_BIN" --headless=new --no-sandbox --disable-setuid-sandbox --disable-dev-shm-usage --disable-gpu       --dump-dom 'data:text/html,<html><body>CHROME_OK</body></html>' >"$TEST" 2>&1 ||
   ! grep -q CHROME_OK "$TEST"; then
  cat "$TEST" >&2 || true
  rm -rf -- "$TARGET"
  [[ -e "$BACKUP" ]] && mv "$BACKUP" "$TARGET" || true
  echo "New Chrome failed; previous installation restored."
  exit 1
fi

rm -rf -- "$BACKUP" 2>/dev/null || true
ln -sfn "$CHROME_BIN" /usr/local/bin/chrome-for-testing
echo "Chrome installed/updated successfully."
"$CHROME_BIN" --version
echo "PUPPETEER_EXECUTABLE_PATH=$CHROME_BIN"
