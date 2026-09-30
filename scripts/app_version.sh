#!/bin/bash
# Prints the app version in the interface family's format: 6.4.<patch>, where the
# patch counts every commit since the app became Hayase (09fbce0), the way the
# interface and its capacitor shell bump their patch on every commit.
set -euo pipefail

cd "$(dirname "$0")/.."

if [ "$(git rev-parse --is-shallow-repository)" = "true" ]; then
  git fetch --quiet --unshallow
fi

echo "6.4.$(git rev-list --count 09fbce0..HEAD)"
