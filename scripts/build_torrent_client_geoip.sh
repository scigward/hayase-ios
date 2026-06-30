#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

PNPM_VERSION="10.28.0"
GEOIP_VERSION="1.1.442"

BUILD_DIR="${PWD}/.build/torrent-client-geoip"
GEOIP_DIR="${PWD}/Hayase/Resources/TorrentClientGeoIP"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "error: $1 is required to build the torrent client GeoIP resources." >&2
    exit 1
  fi
}

run_pnpm() {
  if command -v corepack >/dev/null 2>&1; then
    COREPACK_ENABLE_PROJECT_SPEC=0 corepack "pnpm@${PNPM_VERSION}" "$@"
  else
    npm exec --yes "pnpm@${PNPM_VERSION}" -- "$@"
  fi
}

require_command node
if ! command -v corepack >/dev/null 2>&1; then
  require_command npm
fi
require_command rsync

rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}" "${GEOIP_DIR}"

cat > "${BUILD_DIR}/package.json" <<EOF_PACKAGE
{
  "private": true,
  "type": "module",
  "dependencies": {
    "doc999tor-fast-geoip": "${GEOIP_VERSION}"
  }
}
EOF_PACKAGE

export COREPACK_ENABLE_PROJECT_SPEC=0

(
  cd "${BUILD_DIR}"
  run_pnpm install --no-frozen-lockfile --ignore-scripts
)

rsync -a --delete "${BUILD_DIR}/node_modules/doc999tor-fast-geoip/data/" "${GEOIP_DIR}/"
node --input-type=module <<EOF_NODE
import params from '${BUILD_DIR}/node_modules/doc999tor-fast-geoip/build/params.js'
import { writeFileSync } from 'node:fs'
writeFileSync('${GEOIP_DIR}/params.json', JSON.stringify(params))
EOF_NODE

if find "${GEOIP_DIR}" -name "node_modules" -print -quit | grep -q .; then
  echo "error: generated GeoIP resources must not contain node_modules." >&2
  exit 1
fi

echo "Torrent client GeoIP resources generated at ${GEOIP_DIR}."
