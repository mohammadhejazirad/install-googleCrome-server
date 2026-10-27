# Chrome for Testing Mirror

Public mirror for Chrome for Testing binaries used by Puppeteer/Browsershot/Laravel on Linux servers.

## What it does

- Weekly GitHub Action, every Wednesday at 03:23 UTC (06:53 Iran time), with manual runs also available (`workflow_dispatch`).
- Mirrors only the latest **Stable** Chrome for Testing version from Google's official stable-channel catalog.
- Removes other version directories after all requested downloads succeed; older files remain in Git history.
- Supports `linux64` and `linux-arm64` (ARM64 is available from CfT v153+).
- Stores files under `chrome/<version>/<platform>/`.
- Files larger than 95,000,000 bytes are split into 90 MiB parts so each Git object stays below GitHub's 100 MB hard limit.
- Generates `manifest.json` with version, SHA-256, original size, source URL and part list.
- Server installer detects x86_64/ARM64, compares the installed version with the mirror, downloads/reassembles parts, verifies SHA-256, installs atomically, and rolls back if the new browser fails its headless smoke test.

## Run the mirror

The workflow runs automatically once it is on the repository's default branch and GitHub Actions is enabled with permission to push commits to that branch. No personal access token is needed; it uses `GITHUB_TOKEN` with `contents: write`. Branch protection must allow the workflow's push.

To run immediately, open **Actions → Mirror Chrome for Testing → Run workflow** and choose the platforms. Both scheduled and manual runs retain one stable version. If a requested platform is unavailable in the stable catalog, the workflow fails without publishing a new mirror.

GitHub may delay scheduled runs. In public repositories, scheduled workflows are disabled after 60 days without repository activity; re-enable the workflow from Actions if this happens.

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

The workflow intentionally commits binary parts to this public repository. Only one version is kept in the current tree, but Git history still grows with each update. The schedule updates the GitHub mirror; run the installer on your server when you want to install/update Chrome there.
