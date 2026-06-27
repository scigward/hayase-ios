#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

PNPM_VERSION="10.28.0"
ESBUILD_VERSION="0.25.12"
COBE_TARBALL="https://codeload.github.com/thaunknown/cobe/tar.gz/9687dd14ad06894e28781d170ef9c98aa5d03d9c"
GEOIP_VERSION="1.1.442"

BUILD_DIR="${PWD}/.build/torrent-client-globe"
ENTRY_FILE="${BUILD_DIR}/globe-entry.js"
RESOURCE_DIR="${PWD}/Hayase/Resources/TorrentClientGlobe"
GEOIP_DIR="${PWD}/Hayase/Resources/TorrentClientGeoIP"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "error: $1 is required to build the torrent client globe." >&2
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

require_command node
require_command corepack
require_command rsync

rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}" "${RESOURCE_DIR}" "${GEOIP_DIR}"

cat > "${BUILD_DIR}/package.json" <<EOF
{
  "private": true,
  "type": "module",
  "dependencies": {
    "cobe": "${COBE_TARBALL}",
    "doc999tor-fast-geoip": "${GEOIP_VERSION}"
  }
}
EOF

cat > "${ENTRY_FILE}" <<'EOF'
import createGlobe from 'cobe'

const canvas = document.getElementById('globe')

let globe = null
let markers = []
let size = 400

const scale = 1.5
const oneOverScale = 1 / scale

function offsetForSize () {
  return [size * 0.8 * oneOverScale, size * oneOverScale * 0.4]
}

function start () {
  if (!canvas || globe) return

  globe = createGlobe(canvas, {
    devicePixelRatio: window.devicePixelRatio,
    width: size,
    height: size,
    phi: 0,
    theta: 0.1,
    dark: 1,
    diffuse: 1.4,
    mapSamples: 19000,
    mapBrightness: 6,
    opacity: 0.8,
    baseColor: [0.23, 0.23, 0.23],
    markerColor: [1, 1, 1],
    glowColor: [0, 0, 0],
    markers: [],
    scale,
    offset: offsetForSize(),
    onRender: state => {
      state.phi = Date.now() * 0.0002 % (Math.PI * 2)
      state.width = size
      state.height = size
      state.offset = offsetForSize()
      state.markers = markers
    }
  })
}

window.HayaseGlobe = {
  setSize (nextSize) {
    size = Number(nextSize) >= 600 ? 600 : 400
    canvas.width = size
    canvas.height = size
  },
  setMarkers (nextMarkers) {
    markers = Array.isArray(nextMarkers) ? nextMarkers : []
  }
}

start()
EOF

corepack prepare "pnpm@${PNPM_VERSION}" --activate

(
  cd "${BUILD_DIR}"
  run_pnpm install --no-frozen-lockfile --ignore-scripts
  run_pnpm dlx "esbuild@${ESBUILD_VERSION}" "${ENTRY_FILE}" \
    --bundle \
    --platform=browser \
    --format=esm \
    --target=safari14 \
    --outfile="${RESOURCE_DIR}/globe.js"
)

rsync -a --delete "${BUILD_DIR}/node_modules/doc999tor-fast-geoip/data/" "${GEOIP_DIR}/"
node --input-type=module <<EOF
import params from '${BUILD_DIR}/node_modules/doc999tor-fast-geoip/build/params.js'
import { writeFileSync } from 'node:fs'
writeFileSync('${GEOIP_DIR}/params.json', JSON.stringify(params))
EOF

node --check "${RESOURCE_DIR}/globe.js"

if find "${RESOURCE_DIR}" "${GEOIP_DIR}" -name "node_modules" -print -quit | grep -q .; then
  echo "error: generated globe resources must not contain node_modules." >&2
  exit 1
fi

echo "Torrent client globe bundle generated at ${RESOURCE_DIR}/globe.js."
