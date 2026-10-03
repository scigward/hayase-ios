#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v xcodegen &> /dev/null; then
    echo "xcodegen not found, installing via Homebrew..."
    brew install xcodegen
fi

xcodegen generate

# Create the workspace the CI builds from
WORKSPACE="Hayase.xcworkspace"
mkdir -p "$WORKSPACE"

cat > "$WORKSPACE/contents.xcworkspacedata" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<Workspace
   version = "1.0">
   <FileRef
      location = "group:Hayase.xcodeproj">
   </FileRef>
</Workspace>
EOF

echo "Project generated successfully."
