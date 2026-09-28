#!/usr/bin/env bash
# Assert pnpm supply-chain posture. No network and no install.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok() { echo "OK: $*"; }

[[ -f pnpm-lock.yaml ]] || fail "missing pnpm-lock.yaml"
[[ -f .npmrc ]] || fail "missing .npmrc"
[[ -f tooling/TOOLCHAIN.pins ]] || fail "missing tooling/TOOLCHAIN.pins"
[[ -f scripts/enforce-pnpm.mjs ]] || fail "missing scripts/enforce-pnpm.mjs"

# shellcheck disable=SC1091
source tooling/TOOLCHAIN.pins

PM="$(node -p "require('./package.json').packageManager||''")"
ENG_PNPM="$(node -p "require('./package.json').engines?.pnpm||''")"
ENG_NODE="$(node -p "require('./package.json').engines?.node||''")"

if [[ ! "$PM" =~ ^pnpm@[0-9]+\.[0-9]+\.[0-9]+\+sha512\.[a-f0-9]{128}$ ]]; then
  fail "packageManager must be pnpm@<ver>+sha512.<128-hex> (got: ${PM:-empty})"
fi
[[ "$PM" == "$PNPM_PACKAGE_MANAGER" ]] || fail "packageManager != TOOLCHAIN.pins"
ok "packageManager pinned"

[[ "$ENG_PNPM" == "$PNPM_VERSION" ]] || fail "engines.pnpm=$ENG_PNPM want $PNPM_VERSION"
[[ "$ENG_NODE" == "$NODE_VERSION" ]] || fail "engines.node=$ENG_NODE want $NODE_VERSION"
ok "engines.node=$ENG_NODE engines.pnpm=$ENG_PNPM"

DERIVED_HEX="$(node -e "const i=process.argv[1]; if(!i.startsWith('sha512-')) process.exit(2); process.stdout.write(Buffer.from(i.slice(7),'base64').toString('hex'));" "$PNPM_NPM_INTEGRITY")"
EXPECTED_HEX="${PNPM_PACKAGE_MANAGER#*+sha512.}"
[[ "$DERIVED_HEX" == "$EXPECTED_HEX" ]] || fail "pnpm sha512 hex does not match npm integrity"
ok "pnpm sha512 hex matches npm integrity"

rg -qF 'registry=https://registry.npmjs.org/' .npmrc || fail ".npmrc missing HTTPS registry"
ok ".npmrc registry is HTTPS"

node <<'EOF' || fail "pnpm-workspace.yaml hardening incomplete"
const fs = require("fs");
const text = fs.readFileSync("pnpm-workspace.yaml", "utf8");
const need = [
  "preferFrozenLockfile: true",
  "lockfile: true",
  "pmOnFail: error",
  "strictDepBuilds: true",
  "minimumReleaseAge: 1440",
  "blockExoticSubdeps: true",
  "trustPolicy: no-downgrade",
  "trustLockfile: true",
  "verifyDepsBeforeRun: error",
  "engineStrict: true",
  "saveExact: true",
  "allowBuilds:",
  "better-sqlite3: true",
  "esbuild: true",
  "leveldown: true",
  "lmdb: true",
  "netlify-cli: true",
  "overrides:",
];
for (const k of need) {
  if (!text.includes(k)) {
    console.error("pnpm-workspace.yaml missing: " + k);
    process.exit(2);
  }
}
const p = require("./package.json");
if (p.pnpm) {
  console.error("package.json#pnpm must be empty on pnpm 11");
  process.exit(4);
}
if (!String(p.scripts?.preinstall || "").includes("enforce-pnpm")) process.exit(5);
const aztec = { ...p.dependencies };
for (const [name, ver] of Object.entries(aztec)) {
  if (name.startsWith("@aztec/") && ver !== "5.2.0") {
    console.error(name + " must be exact 5.2.0");
    process.exit(6);
  }
}
EOF
ok "workspace hardening and Aztec 5.2.0 pins"

if rg -n 'tag\s*=\s*"v5\.0\.1"' contracts --glob 'Nargo.toml' >/dev/null; then
  fail "a Nargo.toml is still on aztec.nr v5.0.1"
fi
ok "aztec.nr tags are not v5.0.1"
