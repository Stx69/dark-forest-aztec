#!/usr/bin/env bash
# aztec/nargo compile prints nothing until it exits. Poll artifact files so
# mprocs shows that the compiler is still working and which output moved last.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT}"

export RAYON_NUM_THREADS="${RAYON_NUM_THREADS:-10}"

package_count="$(
  awk '/^members/{f=1;next} f && /^\]/{exit} f && /"/{c++} END{print c+0}' Nargo.toml
)"

echo "[aztec-compile] ${package_count} workspace packages, RAYON_NUM_THREADS=${RAYON_NUM_THREADS}"
echo "[aztec-compile] nargo stays silent until a package finishes; heartbeat every 20s"

aztec compile "$@" &
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
echo "[aztec-compile] finished in $(( $(date +%s) - started ))s"
