# Storage-style fee measurement

Compare gameplay transaction cost for two contract storage styles on a fresh local Aztec network.

- `9stx6/DevKit`: split planet roots, packed arrivals, and the `game_contract` macro.
- `9stx6/DevKitMain`: latest DevKit app and mprocs stack, with main's single `state_roots` hash, full `Arrival` slots, and `#[aztec]`.

Numbers from 27 Sep 2026 are in [storage-style-fees.json](storage-style-fees.json). On that sandbox the fee schedule charged L2 gas and zero DA gas, so the receipt fee follows L2 gas. DevKit was cheaper on `give_spaceships`, `move`, `upgrade_planet`, and `withdraw_silver`. `move` billed about 64% less L2 gas than DevKitMain. `initialize_player` was slightly cheaper on DevKitMain.

## What is recorded

Each included transaction prints one `FEE_MEASURE` line from `contracts/scripts/test/feeMeasureLog.ts`:

- `total`, `public`, `billed`, and `teardown` DA and L2 gas from wallet simulation
- `fee` from the receipt `transactionFee` when the node provides it

Missing fields stay empty. They are never written as zero.

## How to run

Start a fresh Anvil and Aztec local network, then deploy and configure the branch under test. From `contracts/`:

```sh
FEE_MEASURE_COMMIT="$(git rev-parse HEAD)" pnpm exec tsx scripts/test/measure-storage-fees.ts devkit
```

Use `devkitMain` as the section name on `9stx6/DevKitMain`. The runner writes `docs/benchmarks/storage-style-fees.json` and keeps the other section.

The scenario, in order:

1. `initialize_player` for user 1
2. `initialize_player` for user 2 (setup only, not recorded)
3. `give_spaceships` on user 1's home planet
4. `move` from user 2's home to an uninitialized planet
5. `upgrade_planet` for user 2
6. `withdraw_silver` for user 1

Reset the chain before measuring the other branch so both runs start from the same empty state and the same fee mode.
