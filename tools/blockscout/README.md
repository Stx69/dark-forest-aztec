# Blockscout (local Anvil L1)

[Blockscout](https://github.com/blockscout/blockscout) explorer pointed at Anvil JSON-RPC (`http://127.0.0.1:8545`, chain id `31337`).

This stack is **host-native**: Hex.pm OTP/Elixir, Mix API, Next.js UI, prebuilt Postgres, Redis compiled with `make`. **No Docker. No Cargo.** Rust microservices (stats, visualizer, sig-provider) are disabled.

## URLs

| Surface | URL |
| --- | --- |
| Explorer UI | http://127.0.0.1:4000 |
| Backend API | http://127.0.0.1:4001 |

## Prerequisites

- `curl`, `git`, `tar`, `gcc`, `make`, `openssl`, `python3` (or `unzip`)
- Anvil on `127.0.0.1:8545` (`pnpm run dev:local`)

First run downloads OTP 27.3.4, Elixir 1.19.6, Postgres 18.6.0 binaries, and Redis 7.4.2 source. Backend and frontend are cloned at the commits in `tools/vendor-pins.json` (the Stx69 `devkit` branches). Mix security edits are applied on each start by `bin/apply-hex-security.sh`.

## Start

```bash
bash scripts/dev/mprocs-blockscout.sh
```

Or `pnpm run dev:local` (the `blockscout` pane).

Each start wipes Postgres and Redis when ports 5433 and 6380 are free, so the explorer matches a fresh Anvil chain. If those ports are already in use, the existing data is left in place.

## Layout

| Path | Role |
| --- | --- |
| `bin/` | Bootstrap scripts |
| `backend/` | Clone of blockscout (gitignored) |
| `frontend/` | Clone of blockscout/frontend (gitignored) |
| `.toolchain/` | OTP, Elixir, Postgres, Redis (gitignored) |
| `.data/` | Postgres/Redis data and secret (gitignored) |

## Hex security pins

The clone is patched on each start (`bin/apply-hex-security.sh`):

| Package | Upstream lock | Patched | Advisories |
| --- | --- | --- | --- |
| phoenix | 1.6.16 | 1.6.17 | CVE-2026-56811, CVE-2026-56812 |
| mint | 1.10.0 | 1.10.1 | CVE-2026-82672 |
| decimal | 2.4.1 | 3.1.x | CVE-2026-32686 |

Not bumped (would break this umbrella):

- **hackney 1.25.0** — vendor fix is 4.x; `httpoison` / `ethereum_jsonrpc` require 1.x. Proxies are unset so SOCKS/SSRF/cookie-CRLF paths are not used on local Anvil.
- **cowlib 2.20.0** — CVE-2026-43969 has no Hex release; Cowboy 2.19 already rejects CR/LF in response headers (CVE-2026-43966 server side).
