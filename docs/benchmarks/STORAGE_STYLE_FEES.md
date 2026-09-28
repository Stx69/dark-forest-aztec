# Storage-style fee measurement

Compare gameplay transaction cost for two contract storage styles on a fresh local Aztec network.

- `9stx6/DevKit`: packed arrivals, the `game_contract` macro, and a planet write that stores only the full `state_roots` hash plus the `PlanetUpdate` log.
- `9stx6/DevKitMain`: latest DevKit app and mprocs stack, with main's single `state_roots` hash, full `Arrival` slots, and `#[aztec]`.

Numbers from 27 Sep 2026 are in [storage-style-fees.json](storage-style-fees.json). On that sandbox the fee schedule charged L2 gas and zero DA gas, so the receipt fee follows L2 gas.

Billed L2 gas. `devkit` is the 28 Sep 2026 run: unchanged side rows are skipped, empty arrival batches are omitted, and `move` skips artifact checks when the id is zero. Earlier columns stay in the JSON. `devkitMain` is the single-root style with full arrival slots.

| Function | Skip unchanged rows | Latest | DevKitMain | Fee |
| --- | ---: | ---: | ---: | ---: |
| initialize_player | 831,158 | 831,158 | 1,028,414 | 8,477,811,600,000 |
| give_spaceships | 1,531,122 | 1,531,122 | 2,655,419 | 15,617,444,400,000 |
| move | 1,362,427 | 1,300,942 | 3,782,976 | 13,269,608,400,000 |
| upgrade_planet | 1,123,533 | 1,123,533 | 1,949,767 | 11,460,036,600,000 |
| withdraw_silver | 1,177,559 | 1,177,559 | 2,008,785 | 12,011,101,800,000 |

`move` public L2 is 710,142. The other four functions match the previous DevKit run. Teardown gas was 0 for every row.

Aztec 5.2.0 on the same five calls is the `aztec520` section, measured 28 Sep 2026. Billed L2 matches the latest 5.0.1 DevKit column: initialize_player 831,158, give_spaceships 1,531,122, move 1,300,942, upgrade_planet 1,123,533, withdraw_silver 1,177,559.

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

## Planet writes

`PlanetStorage.set` stores the full planet hash in `state_roots` and emits the full `PlanetUpdate` log. It does not hash or store split roots, and it does not emit `PlanetSplitRootsUpdate`. Gameplay checks the full `state_roots` hash. The indexer reconstructs the planet from `PlanetUpdate`. A planet-events or planet-artifacts row is written only when a field other than `last_updated` changed. An empty arrival batch is not passed into the public call. `move` checks a moved or activated artifact only when its id is not zero. The voyage log still includes the empty event slots, because a shorter log is dropped by the indexer.
