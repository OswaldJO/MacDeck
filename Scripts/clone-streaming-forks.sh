#!/usr/bin/env bash
# Clone Sunshine + Moonlight (iOS + Android) into Vendor/streaming-repos for local development.
# Fork the repos on GitHub first, then set SUNSHINE_GIT_URL / MOONLIGHT_*_GIT_URL to your forks.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${ROOT}/Vendor/streaming-repos"
SUNSHINE_GIT_URL="${SUNSHINE_GIT_URL:-${APOLLO_GIT_URL:-https://github.com/LizardByte/Sunshine.git}}"
MOONLIGHT_IOS_GIT_URL="${MOONLIGHT_IOS_GIT_URL:-${MOONLIGHT_GIT_URL:-https://github.com/moonlight-stream/moonlight-ios.git}}"
MOONLIGHT_ANDROID_GIT_URL="${MOONLIGHT_ANDROID_GIT_URL:-https://github.com/moonlight-stream/moonlight-android.git}"

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

clone_recursive "Sunshine" "${SUNSHINE_GIT_URL}"
clone_recursive "moonlight-ios" "${MOONLIGHT_IOS_GIT_URL}"
clone_recursive "moonlight-android" "${MOONLIGHT_ANDROID_GIT_URL}"

echo "Done. Open projects from:"
echo "  ${DEST}/Sunshine"
echo "  ${DEST}/moonlight-ios"
echo "  ${DEST}/moonlight-android"
echo ""
echo "Mac host: build/run Sunshine, then configure Playnite Mac → Streaming."
echo "Phones: companion_app/ (Flutter)"
