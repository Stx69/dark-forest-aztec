# Storage-style fee measurement

Compare gameplay transaction cost for two contract storage styles on a fresh local Aztec network.

- `9stx6/DevKit`: split planet roots, packed arrivals, and the `game_contract` macro.
- `9stx6/DevKitMain`: latest DevKit app and mprocs stack, with main's single `state_roots` hash, full `Arrival` slots, and `#[aztec]`.

Numbers from 27 Sep 2026 are in [storage-style-fees.json](storage-style-fees.json). On that sandbox the fee schedule charged L2 gas and zero DA gas, so the receipt fee follows L2 gas.

Billed L2 gas and receipt fee. The `devkit` column is the slice-write bytecode measured at 19:45 UTC on commit `aeb7278` plus the uncommitted slice-write sources. `devkit before` is the earlier DevKit run. `devkitMain` is the single-root style.

| Function | DevKit before | DevKit slice writes | DevKitMain | Slice-write fee |
| --- | ---: | ---: | ---: | ---: |
| initialize_player | 1,049,559 | 1,049,625 | 1,028,414 | 10,706,175,000,000 |
| give_spaceships | 1,965,690 | 1,965,972 | 2,655,419 | 20,052,914,400,000 |
| move | 2,305,197 | 1,972,488 | 3,782,976 | 20,119,377,600,000 |
| upgrade_planet | 1,328,072 | 1,331,241 | 1,949,767 | 13,578,658,200,000 |
| withdraw_silver | 1,382,314 | 1,314,571 | 2,008,785 | 13,408,624,200,000 |

`move` public L2 fell from 1,714,397 to 1,381,688, and billed L2 is about 14% below the previous DevKit run and about 48% below DevKitMain. `withdraw_silver` billed L2 is about 5% below the previous DevKit run. `upgrade_planet` is a few thousand L2 above the previous DevKit run. `initialize_player` and `give_spaceships` do not use slice writes and match the previous DevKit run. Teardown gas was 0 for every row.

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

The recorded player functions, in order:

1. `initialize_player` for user 1
2. `initialize_player` for user 2 (setup only, not recorded)
3. `give_spaceships` on user 1's home planet
4. `move` from user 2's home to an uninitialized planet
5. `upgrade_planet` for user 2
6. `withdraw_silver` for user 1

Reset the chain before measuring the other branch so both runs start from the same empty state and the same fee mode.

## Slice writes

`move`, `upgrade_planet`, and `withdraw_silver` now call `PlanetStorage.set_slices`. The private circuit compares the authenticated planet with the new one and sets a mask: static, dynamic, stats, modifiers. Public execution hashes and stores only the slices whose bit is set, and reuses the stored root for the rest. The full `PlanetUpdate` log and the full `state_roots` check stay in place. Empty arrival batches are skipped when the planet has no voyages. Other writers still call `set`, which marks every slice dirty.
