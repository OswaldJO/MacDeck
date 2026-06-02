#!/usr/bin/env bash
# Copy a Sunshine binary into the Mac app bundle resources (optional; Playnite also finds Homebrew installs).
#
# Usage:
#   ./Scripts/stage-sunshine-for-mac-app.sh           # copy existing binary
#   ./Scripts/stage-sunshine-for-mac-app.sh --install # tap + brew install, then copy
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${ROOT}/MacGameLibraryApp/Resources/Sunshine"
SUNSHINE_TAP="LizardByte/homebrew"
SUNSHINE_FORMULA="lizardbyte/homebrew/sunshine"
mkdir -p "${DEST}"

install_sunshine() {
  if ! command -v brew >/dev/null 2>&1; then
    echo "Homebrew is required. Install from https://brew.sh" >&2
    exit 1
  fi
  echo "Adding tap ${SUNSHINE_TAP} …"
  brew tap "${SUNSHINE_TAP}"
  echo "Installing Sunshine (this may take a few minutes) …"
  brew install "${SUNSHINE_FORMULA}"
}

pick_binary() {
  if [[ -n "${SUNSHINE_BINARY:-}" && -x "${SUNSHINE_BINARY}" ]]; then
    echo "${SUNSHINE_BINARY}"
    return 0
  fi

  local candidate
  for candidate in \
    /opt/homebrew/bin/sunshine \
    /usr/local/bin/sunshine \
    /opt/homebrew/opt/sunshine/bin/sunshine \
    /usr/local/opt/sunshine/bin/sunshine \
    /Applications/Sunshine.app/Contents/MacOS/sunshine; do
    if [[ -x "${candidate}" ]]; then
      echo "${candidate}"
      return 0
    fi
  done

  if command -v brew >/dev/null 2>&1; then
    local prefix
    prefix="$(brew --prefix sunshine 2>/dev/null || true)"
    if [[ -n "${prefix}" && -x "${prefix}/bin/sunshine" ]]; then
      echo "${prefix}/bin/sunshine"
      return 0
    fi
  fi

  local built
  built="$(find "${ROOT}/Vendor/streaming-repos/Sunshine/build" -name sunshine -type f 2>/dev/null | head -1)"
  if [[ -n "${built}" && -x "${built}" ]]; then
    echo "${built}"
    return 0
  fi
  return 1
}

if [[ "${1:-}" == "--install" ]]; then
  if ! pick_binary >/dev/null 2>&1; then
    install_sunshine
  else
    echo "Sunshine is already installed; skipping brew install."
  fi
fi

if ! SRC="$(pick_binary)"; then
  echo "No Sunshine binary found." >&2
  echo "" >&2
  echo "Sunshine is not in default Homebrew. Use either:" >&2
  echo "  ./Scripts/stage-sunshine-for-mac-app.sh --install" >&2
  echo "  brew tap LizardByte/homebrew && brew install lizardbyte/homebrew/sunshine" >&2
  echo "Or build Vendor/streaming-repos/Sunshine and re-run." >&2
  exit 1
fi

echo "Staging ${SRC} → ${DEST}/sunshine"
cp -f "${SRC}" "${DEST}/sunshine"
chmod +x "${DEST}/sunshine"
echo "Done. Rebuild MacGameLibrary in Xcode so Resources/Sunshine is copied into the app."
