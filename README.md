# Chrome for Testing Mirror

Public mirror for Chrome for Testing binaries used by Puppeteer/Browsershot/Laravel on Linux servers.

## What it does

- Manual GitHub Action (`workflow_dispatch`).
- Mirrors the newest N Chrome for Testing versions from Google's official catalog.
- Supports `linux64` and `linux-arm64` (ARM64 is available from CfT v153+).
- Stores files under `chrome/<version>/<platform>/`.
- Files larger than 95,000,000 bytes are split into 90 MiB parts so each Git object stays below GitHub's 100 MB hard limit.
- Generates `manifest.json` with version, SHA-256, original size, source URL and part list.
- Server installer detects x86_64/ARM64, compares the installed version with the mirror, downloads/reassembles parts, verifies SHA-256, installs atomically, and rolls back if the new browser fails its headless smoke test.

## Run the mirror

Open **Actions → Mirror Chrome for Testing → Run workflow**.

Choose how many recent versions to retain/mirror (1, 3, 5 or 10) and the platforms.

## Install/update on a Linux server

```bash
curl -fsSL https://raw.githubusercontent.com/mohammadhejazirad/install-googleCrome-server/main/scripts/install-chrome.sh -o /tmp/install-chrome.sh
sudo bash /tmp/install-chrome.sh
```

For x86_64 the final path is:

```text
/opt/chrome-for-testing/chrome-linux64/chrome
```

Laravel/Puppeteer:

```env
PUPPETEER_EXECUTABLE_PATH=/opt/chrome-for-testing/chrome-linux64/chrome
```

On ARM64 the path is `/opt/chrome-for-testing/chrome-linux-arm64/chrome`.

## Notes

The workflow intentionally commits binary parts to this public repository. Keeping many versions will grow Git history quickly. The default is 5 versions.
