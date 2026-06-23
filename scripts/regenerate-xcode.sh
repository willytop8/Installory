#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v xcodegen >/dev/null 2>&1; then
  cat >&2 <<'EOF'
✗ xcodegen not found on PATH.

Install it with Homebrew:

    brew install xcodegen

XcodeGen reads project.yml and regenerates Installory.xcodeproj. The project
itself is gitignored; project.yml is the source of truth.
EOF
  exit 1
fi

if [ ! -f project.yml ]; then
  echo "✗ project.yml not found in $(pwd) — are you in the repo root?" >&2
  exit 1
fi

xcodegen generate
echo "✓ Installory.xcodeproj regenerated"
