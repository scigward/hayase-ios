#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

TORRENT_CLIENT_REPO="https://github.com/hayase-app/torrent-client.git"
TORRENT_CLIENT_COMMIT="f953c72d851073d00a1d4c665bad531ce6d7170e"
PNPM_VERSION="10.28.0"
ESBUILD_VERSION="0.25.12"

BUILD_DIR="${PWD}/.build/webtorrent-backend"
SOURCE_DIR="${BUILD_DIR}/torrent-client"
RESOURCE_DIR="${PWD}/Hayase/Resources/WebTorrentBackend"
OUTPUT_DIR="${RESOURCE_DIR}/torrent-client"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "error: $1 is required to build the WebTorrent backend." >&2
    exit 1
  fi
}

run_pnpm() {
  if command -v pnpm >/dev/null 2>&1; then
    pnpm "$@"
  else
    corepack pnpm "$@"
  fi
}

require_command git
require_command node
require_command corepack
require_command rsync

rm -rf "${SOURCE_DIR}"
mkdir -p "${BUILD_DIR}"

git init --initial-branch=hayase-build "${SOURCE_DIR}"
git -C "${SOURCE_DIR}" remote add origin "${TORRENT_CLIENT_REPO}"
git -C "${SOURCE_DIR}" fetch --depth 1 origin "${TORRENT_CLIENT_COMMIT}"
git -C "${SOURCE_DIR}" checkout --detach FETCH_HEAD

ACTUAL_COMMIT="$(git -C "${SOURCE_DIR}" rev-parse HEAD)"
if [ "${ACTUAL_COMMIT}" != "${TORRENT_CLIENT_COMMIT}" ]; then
  echo "error: expected torrent-client ${TORRENT_CLIENT_COMMIT}, got ${ACTUAL_COMMIT}." >&2
  exit 1
fi

corepack prepare "pnpm@${PNPM_VERSION}" --activate

rm -rf "${OUTPUT_DIR}"
mkdir -p "${OUTPUT_DIR}"

(
  cd "${SOURCE_DIR}"

  run_pnpm dlx "esbuild@${ESBUILD_VERSION}" index.ts \
    --bundle \
    --platform=node \
    --format=esm \
    --target=node24 \
    --packages=external \
    --outfile="${OUTPUT_DIR}/index.js"

  run_pnpm install \
    --prod \
    --no-frozen-lockfile \
    --ignore-scripts \
    --config.node-linker=hoisted \
    --config.shamefully-hoist=true
)

rsync -aL --delete \
  --exclude=".cache/" \
  --exclude="*.node" \
  --exclude="*.tsbuildinfo" \
  "${SOURCE_DIR}/node_modules/" \
  "${OUTPUT_DIR}/node_modules/"

NATIVE_ADDON="$(find "${OUTPUT_DIR}" -name "*.node" -print -quit)"
if [ -n "${NATIVE_ADDON}" ]; then
  echo "error: WebTorrent backend generated a native Node addon, which cannot be bundled in the iOS app: ${NATIVE_ADDON}" >&2
  exit 1
fi

BROKEN_SYMLINK="$(find "${OUTPUT_DIR}" -type l -print -quit)"
if [ -n "${BROKEN_SYMLINK}" ]; then
  echo "error: WebTorrent backend output still contains a symlink after resource staging: ${BROKEN_SYMLINK}" >&2
  exit 1
fi

node --check "${RESOURCE_DIR}/webtorrent-bridge.js"
node --check "${OUTPUT_DIR}/index.js"

echo "WebTorrent backend bundle generated at ${OUTPUT_DIR}."
