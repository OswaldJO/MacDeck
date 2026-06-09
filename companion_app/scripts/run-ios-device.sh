#!/usr/bin/env bash
# Physical iPhone/iPad on iOS 18.4+ cannot run Flutter *debug* (JIT) — use profile mode.
set -euo pipefail
cd "$(dirname "$0")/.."
flutter run --profile "$@"
