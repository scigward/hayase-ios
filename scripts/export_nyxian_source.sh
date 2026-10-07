#!/bin/bash
# Build once with Xcode, then export a relocatable Nyxian project, not an Xcode dump.
set -euo pipefail
cd "$(dirname "$0")/.."

if [ "$(uname -s)" != Darwin ]; then
  echo "error: the Nyxian export requires macOS and the iOS Xcode toolchain." >&2
  exit 1
fi
for tool in xcodebuild xcrun xcodegen node python3 git; do
  command -v "$tool" >/dev/null || { echo "error: missing $tool" >&2; exit 1; }
done

EXPORT_OUTPUT="$PWD/build/nyxian-export"
EXPORT_DERIVED_DATA="$PWD/build/nyxian-derived-data"
EXPORT_PACKAGES="${NYXIAN_PACKAGES_DIR:-$HOME/.hayase-spm}"
mkdir -p "$EXPORT_OUTPUT"
# A rerun must never publish an older successful archive after a failed build.
python3 - "$EXPORT_OUTPUT" <<'PY'
from pathlib import Path
import sys
output = Path(sys.argv[1])
for name in ('Hayase-Nyxian-Source.zip', 'Hayase-Nyxian-Source.zip.sha256', 'export-report.json'):
    (output / name).unlink(missing_ok=True)
PY

# Hayase's bridge is currently empty. Library evolution must not silently drop
# future ObjC imports: the exporter refuses that change until it is supported.
python3 - <<'PY'
from pathlib import Path
import re
header = Path('Hayase/Hayase-Bridging-Header.h').read_text()
header = re.sub(r'/\*.*?\*/|//[^\n]*', '', header, flags=re.S).strip()
if header:
    raise SystemExit('error: nonempty Hayase bridging header; update the Nyxian distribution build before exporting')
PY

bash ./scripts/build_webtorrent_backend.sh
bash ./scripts/build_torrent_client_geoip.sh
bash ./scripts/generate_project.sh
EXPORT_VERSION="$(bash ./scripts/app_version.sh)"

EXPORT_RESOLVED=false
for attempt in 1 2 3; do
  echo "Resolve attempt $attempt/3"
  if perl -e 'alarm(300); exec(@ARGV)' -- xcodebuild \
    -workspace Hayase.xcworkspace -scheme Hayase \
    -resolvePackageDependencies \
    -clonedSourcePackagesDirPath "$EXPORT_PACKAGES" \
    -derivedDataPath "$EXPORT_DERIVED_DATA"; then
    EXPORT_RESOLVED=true
    break
  fi
  if [ "$attempt" -lt 3 ]; then sleep 10; fi
done
if [ "$EXPORT_RESOLVED" != true ]; then
  echo "error: Swift package resolution failed" >&2
  exit 1
fi

# Interfaces let Nyxian import Swift dependencies without relying on Xcode's
# compiler-specific serialized .swiftmodule files. Only arm64 device inputs.
EXPORT_BUILD_ARGS=(
  -workspace Hayase.xcworkspace -scheme Hayase -configuration Release
  -sdk iphoneos -destination generic/platform=iOS
  -skipPackageUpdates -clonedSourcePackagesDirPath "$EXPORT_PACKAGES"
  -derivedDataPath "$EXPORT_DERIVED_DATA"
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES
  CODE_SIGN_IDENTITY= CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
  BUILD_LIBRARY_FOR_DISTRIBUTION=YES SWIFT_EMIT_MODULE_INTERFACE=YES
  SWIFT_OBJC_BRIDGING_HEADER=
  "MARKETING_VERSION=$EXPORT_VERSION" "CURRENT_PROJECT_VERSION=${EXPORT_VERSION##*.}"
)
xcodebuild "${EXPORT_BUILD_ARGS[@]}" clean build 2>&1 | tee "$EXPORT_OUTPUT/xcode-build.log"
xcodebuild "${EXPORT_BUILD_ARGS[@]}" -showBuildSettings -json > "$EXPORT_OUTPUT/build-settings.json"

python3 ./scripts/nyxian_export.py \
  --repo "$PWD" --derived-data "$EXPORT_DERIVED_DATA" \
  --packages "$EXPORT_PACKAGES" --build-log "$EXPORT_OUTPUT/xcode-build.log" \
  --settings "$EXPORT_OUTPUT/build-settings.json" --output "$EXPORT_OUTPUT"
