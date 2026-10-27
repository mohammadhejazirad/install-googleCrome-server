#!/usr/bin/env bash
set -Eeuo pipefail

PLATFORMS_CSV="${PLATFORMS:-linux64,linux-arm64}"
PART_THRESHOLD=95000000
PART_SIZE="90M"
ROOT="chrome"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

API="https://googlechromelabs.github.io/chrome-for-testing/last-known-good-versions-with-downloads.json"

echo "::group::Fetch official Chrome for Testing catalog"
curl -fL --retry 5 --retry-all-errors --connect-timeout 20 "$API" -o "$TMP/catalog.json"
jq -e '.channels.Stable | .version and (.downloads.chrome | length > 0)' "$TMP/catalog.json" >/dev/null
LATEST="$(jq -r '.channels.Stable.version' "$TMP/catalog.json")"
[[ "$LATEST" =~ ^[0-9]+(\.[0-9]+){3}$ ]] || { echo "Invalid stable Chrome version"; exit 1; }
echo "::endgroup::"

IFS=',' read -r -a PLATFORMS <<< "$PLATFORMS_CSV"

mkdir -p "$ROOT"
ITEMS="$TMP/items.jsonl"
: > "$ITEMS"

VERSION="$LATEST"
for PLATFORM_RAW in "${PLATFORMS[@]}"; do
  PLATFORM="$(xargs <<<"$PLATFORM_RAW")"
  case "$PLATFORM" in
    linux64|linux-arm64) ;;
    *) echo "Unsupported platform: $PLATFORM"; exit 1 ;;
  esac
  URL="$(jq -r --arg v "$VERSION" --arg p "$PLATFORM" '
    .channels.Stable | select(.version==$v) |
    .downloads.chrome[]? | select(.platform==$p) | .url
  ' "$TMP/catalog.json" | head -n1)"

  if [[ -z "$URL" || "$URL" == "null" ]]; then
    echo "ERROR: Stable Chrome $VERSION has no $PLATFORM asset"
    exit 1
  fi

  DIR="$ROOT/$VERSION/$PLATFORM"
  ZIP="$TMP/chrome-$VERSION-$PLATFORM.zip"
  mkdir -p "$DIR"

  echo "::group::Download Chrome $VERSION / $PLATFORM"
  curl -fL --retry 5 --retry-all-errors --connect-timeout 20 "$URL" -o "$ZIP"
  unzip -t "$ZIP" >/dev/null
  echo "::endgroup::"

  SHA256="$(sha256sum "$ZIP" | awk '{print $1}')"
  SIZE="$(stat -c%s "$ZIP")"

  rm -f "$DIR"/chrome.zip "$DIR"/chrome.zip.part-* "$DIR"/SHA256SUMS "$DIR"/metadata.json

  if (( SIZE > PART_THRESHOLD )); then
    split -b "$PART_SIZE" -d -a 3 "$ZIP" "$DIR/chrome.zip.part-"
    SPLIT=true
    PARTS="$(find "$DIR" -maxdepth 1 -type f -name 'chrome.zip.part-*' -printf '%f\n' | sort | jq -R . | jq -s .)"
  else
    cp "$ZIP" "$DIR/chrome.zip"
    SPLIT=false
    PARTS='["chrome.zip"]'
  fi

  printf '%s  chrome.zip\n' "$SHA256" > "$DIR/SHA256SUMS"
  jq -n --arg version "$VERSION" --arg platform "$PLATFORM" --arg source_url "$URL"       --arg sha256 "$SHA256" --argjson original_size "$SIZE"       --argjson split "$SPLIT" --argjson parts "$PARTS"       '{version:$version,platform:$platform,source_url:$source_url,sha256:$sha256,original_size:$original_size,split:$split,parts:$parts}'       > "$DIR/metadata.json"
  cat "$DIR/metadata.json" >> "$ITEMS"
done

printf '%s\n' "$LATEST" > "$ROOT/LATEST_STABLE"

# Remove other versions only after every requested download succeeds.
while IFS= read -r OLD; do
  if [[ "$OLD" != "$LATEST" && "$OLD" =~ ^[0-9]+(\.[0-9]+){3}$ ]]; then
    rm -rf -- "$ROOT/$OLD"
  fi
done < <(find "$ROOT" -mindepth 1 -maxdepth 1 -type d -printf '%f\n')

# Manifest must describe only files still present.
: > "$ITEMS"
while IFS= read -r meta; do cat "$meta" >> "$ITEMS"; done < <(find "$ROOT" -mindepth 3 -maxdepth 3 -name metadata.json -type f | sort -V)

jq -s --arg latest "$LATEST"   '{schema:1,latest_stable:$latest,generated_at:(now|todate),builds:.}' "$ITEMS" > manifest.json

echo "Latest stable: $LATEST"
find "$ROOT" -maxdepth 3 -type f -printf '%p %s bytes\n' | sort
