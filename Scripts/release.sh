#!/bin/bash
# Wrapper — delegates to app/Scripts/release.sh so you can run either:
#   ./Scripts/release.sh 0.3.0
#   ./app/Scripts/release.sh 0.3.0
set -euo pipefail
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
exec "$REPO_DIR/app/Scripts/release.sh" "$@"
