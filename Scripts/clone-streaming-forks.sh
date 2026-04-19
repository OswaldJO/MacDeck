#!/usr/bin/env bash
# Clone Apollo + moonlight-ios into Vendor/streaming-repos for local development.
# Fork the repos on GitHub first, then set APOLLO_GIT_URL / MOONLIGHT_GIT_URL to your forks.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${ROOT}/Vendor/streaming-repos"
APOLLO_GIT_URL="${APOLLO_GIT_URL:-https://github.com/ClassicOldSong/Apollo.git}"
MOONLIGHT_GIT_URL="${MOONLIGHT_GIT_URL:-https://github.com/moonlight-stream/moonlight-ios.git}"

mkdir -p "${DEST}"
cd "${DEST}"

clone_recursive() {
  local name="$1"
  local url="$2"
  if [[ -d "${name}/.git" ]]; then
    echo "Already cloned: ${name} (skip)"
    return 0
  fi
  echo "Cloning ${name} from ${url} …"
  git clone --recursive "${url}" "${name}"
}

clone_recursive "Apollo" "${APOLLO_GIT_URL}"
clone_recursive "moonlight-ios" "${MOONLIGHT_GIT_URL}"

echo "Done. Open Apollo and moonlight-ios Xcode projects from:"
echo "  ${DEST}/Apollo"
echo "  ${DEST}/moonlight-ios"
