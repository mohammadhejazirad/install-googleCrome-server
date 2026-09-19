#!/usr/bin/env bash
set -Eeuo pipefail

COUNT="${VERSIONS_COUNT:-5}"
PLATFORMS_CSV="${PLATFORMS:-linux64,linux-arm64}"
PART_THRESHOLD=95000000
PART_SIZE="90M"
KEEP_VERSIONS="${KEEP_VERSIONS:-$COUNT}"
ROOT="chrome"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

API="https://googlechromelabs.github.io/chrome-for-testing/known-good-versions-with-downloads.json"

echo "::group::Fetch official Chrome for Testing catalog"
curl -fL --retry 5 --retry-all-errors --connect-timeout 20 "$API" -o "$TMP/catalog.json"
jq -e '.versions | length > 0' "$TMP/catalog.json" >/dev/null
echo "::endgroup::"

IFS=',' read -r -a PLATFORMS <<< "$PLATFORMS_CSV"
mapfile -t VERSIONS < <(
  jq -r '.versions[] | select(.downloads.chrome != null) | .version' "$TMP/catalog.json" |
  sort -V | tail -n "$COUNT" | tac
)
(("${#VERSIONS[@]}" > 0)) || { echo "No Chrome versions found"; exit 1; }

mkdir -p "$ROOT"
ITEMS="$TMP/items.jsonl"
: > "$ITEMS"

for VERSION in "${VERSIONS[@]}"; do
  for PLATFORM_RAW in "${PLATFORMS[@]}"; do
    PLATFORM="$(xargs <<<"$PLATFORM_RAW")"
    URL="$(jq -r --arg v "$VERSION" --arg p "$PLATFORM" '
      .versions[] | select(.version==$v) |
      .downloads.chrome[]? | select(.platform==$p) | .url
    ' "$TMP/catalog.json" | head -n1)"

    if [[ -z "$URL" || "$URL" == "null" ]]; then
      echo "SKIP: $VERSION has no $PLATFORM Chrome asset"
      continue
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
done

LATEST="${VERSIONS[0]}"
printf '%s\n' "$LATEST" > "$ROOT/LATEST_STABLE"

# Retain only the newest requested version directories in the working tree.
mapfile -t EXISTING < <(find "$ROOT" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort -V -r)
if (("${#EXISTING[@]}" > KEEP_VERSIONS)); then
  for OLD in "${EXISTING[@]:$KEEP_VERSIONS}"; do
    [[ "$OLD" =~ ^[0-9]+(\.[0-9]+){3}$ ]] && rm -rf -- "$ROOT/$OLD"
  done
fi

# Manifest must describe only files still present.
: > "$ITEMS"
while IFS= read -r meta; do cat "$meta" >> "$ITEMS"; done < <(find "$ROOT" -mindepth 3 -maxdepth 3 -name metadata.json -type f | sort -V)

jq -s --arg latest "$LATEST"   '{schema:1,latest_stable:$latest,generated_at:(now|todate),builds:.}' "$ITEMS" > manifest.json

echo "Latest stable: $LATEST"
find "$ROOT" -maxdepth 3 -type f -printf '%p %s bytes\n' | sort
