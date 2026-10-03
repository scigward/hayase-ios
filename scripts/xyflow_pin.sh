#!/bin/bash
# Xyflow-Swift follows `main` (project.yml), and nothing in the repository pins it: Package.resolved is
# ignored and the workspace is generated on every run. The only pin there is lives in the cached
# SourcePackages directory, as the revision that whichever run filled the cache resolved, and the build
# uses it as it is (-skipPackageUpdates). So `main` never moved on in CI.
#
#   xyflow_pin.sh drop [dir]   forget the cached pin and clone, so the next resolve takes `main` as it is
#   xyflow_pin.sh show [dir]   print the revision that was resolved next to the one `main` is at
set -euo pipefail

mode="${1:-drop}"
dir="${2:-$HOME/.hayase-spm}"
remote="https://github.com/scigward/Xyflow-Swift.git"

case "$mode" in
  drop)
    state="$dir/workspace-state.json"
    if [ -f "$state" ]; then
      python3 - "$state" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path) as file:
    data = json.load(file)

dependencies = data.get("object", {}).get("dependencies", [])
kept = [d for d in dependencies if "xyflow-swift" not in json.dumps(d.get("packageRef", {})).lower()]

if len(kept) != len(dependencies):
    data["object"]["dependencies"] = kept
    with open(path, "w") as file:
        json.dump(data, file, indent=2)
    print("Dropped the cached pin of Xyflow-Swift")
else:
    print("No cached pin of Xyflow-Swift")
PY
    fi
    rm -rf "$dir/checkouts/Xyflow-Swift" "$dir"/repositories/Xyflow-Swift-*
    ;;
  show)
    resolved="$(git -C "$dir/checkouts/Xyflow-Swift" rev-parse HEAD 2>/dev/null || echo "none")"
    latest="$(git ls-remote "$remote" refs/heads/main | cut -f1)"
    echo "Xyflow-Swift resolved at $resolved, main is at $latest"
    ;;
  *)
    echo "usage: xyflow_pin.sh drop|show [dir]" >&2
    exit 2
    ;;
esac
