#!/usr/bin/env bash
# Compile Aztec Noir contracts with progress heartbeats.
#
# Aztec 6.0 `aztec compile` runs `nargo test --list-tests` after nargo and can hang
# for a long time when oracle tests are generated into contract crates. Use
# `aztec-nargo compile` + `bb aztec_process` instead, then stamp aztec_version.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT}"

export RAYON_NUM_THREADS="${RAYON_NUM_THREADS:-10}"

package_count="$(
  awk '/^members/{f=1;next} f && /^\]/{exit} f && /"/{c++} END{print c+0}' Nargo.toml
)"

echo "[aztec-compile] ${package_count} workspace packages, RAYON_NUM_THREADS=${RAYON_NUM_THREADS}"
echo "[aztec-compile] nargo stays silent until a package finishes; heartbeat every 20s"

aztec-nargo compile "$@" &
pid=$!
started=$(date +%s)

while kill -0 "${pid}" 2>/dev/null; do
  sleep 20
  if ! kill -0 "${pid}" 2>/dev/null; then
    break
  fi
  elapsed=$(( $(date +%s) - started ))
  json_count="$(find target -maxdepth 1 -name '*.json' 2>/dev/null | wc -l | tr -d ' ')"
  latest="$(
    find target -maxdepth 1 -name '*.json' -printf '%T@ %f\n' 2>/dev/null \
      | sort -n | tail -1 | cut -d' ' -f2-
  )"
  echo "[aztec-compile] ${elapsed}s still running, json artifacts=${json_count}, latest=${latest:-none}"
done

wait "${pid}"
echo "[aztec-compile] nargo finished in $(( $(date +%s) - started ))s"

mapfile -t unprocessed < <(
  python3 - <<'PY'
import json, glob
from pathlib import Path
for path in sorted(glob.glob("target/*.json")):
    try:
        data = json.loads(Path(path).read_text())
    except Exception:
        continue
    if isinstance(data.get("functions"), list) and data.get("transpiled") is not True:
        print(path)
PY
)

if ((${#unprocessed[@]} > 0)); then
  echo "[aztec-compile] postprocessing ${#unprocessed[@]} artifact(s) with bb aztec_process"
  bb_args=()
  for artifact in "${unprocessed[@]}"; do
    bb_args+=(-i "${artifact}")
  done
  bb aztec_process "${bb_args[@]}"
  python3 - <<'PY'
import json, glob
from pathlib import Path
version = "6.0.0"
for path in glob.glob("target/*.json"):
    data = json.loads(Path(path).read_text())
    if isinstance(data.get("functions"), list):
        data["aztec_version"] = version
        Path(path).write_text(json.dumps(data, indent=2) + "\n")
print("[aztec-compile] stamped aztec_version=6.0.0")
PY
else
  echo "[aztec-compile] no untranspiled artifacts to postprocess"
fi

echo "[aztec-compile] finished in $(( $(date +%s) - started ))s"
