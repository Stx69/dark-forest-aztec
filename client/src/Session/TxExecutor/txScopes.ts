import { AztecAddress } from "@aztec/aztec.js/addresses";
import type { Wallet } from "@aztec/aztec.js/wallet";
import {
  ADMIN_CONTRACT_ADDRESS,
  ARRIVAL_STORAGE_CONTRACT_ADDRESS,
  ARTIFACT_ACTION_SYSTEM_CONTRACT_ADDRESS,
  ARTIFACT_FIND_SYSTEM_CONTRACT_ADDRESS,
  ARTIFACT_LOCATION_STORAGE_CONTRACT_ADDRESS,
  ARTIFACT_PROSPECT_SYSTEM_CONTRACT_ADDRESS,
  ARTIFACT_STORAGE_CONTRACT_ADDRESS,
  ARTIFACT_VAULT_SYSTEM_CONTRACT_ADDRESS,
  CONFIG_CONTRACT_ADDRESS,
  CORE_CONTRACT_ADDRESS,
  MOVE_CONTRACT_ADDRESS,
  PLANET_ARTIFACTS_STORAGE_CONTRACT_ADDRESS,
  PLANET_EVENTS_STORAGE_CONTRACT_ADDRESS,
  PLANET_REVEALED_COORDS_STORAGE_CONTRACT_ADDRESS,
  PLANET_STORAGE_CONTRACT_ADDRESS,
  PLAYER_STORAGE_CONTRACT_ADDRESS,
  WORLD_STORAGE_CONTRACT_ADDRESS,
} from "@dfpunk/contracts";

/** Aztec 5.2 canonical contracts the account entrypoint reads while proving. */
const AZTEC_STANDARD_SCOPES = [
  "0x1e8e7e73c592a1b1c9199b4b655ddc7a16fa8a8488df595610b71d3dc1cc666c",
  "0x246d60af8b79a5dceece7d2388921203401c0df02ce674c5781c6c2162922986",
  "0x031b75e2c220f6a6f27da5d61f7b2a12756a127fd25b95fad5da1c5520994b18",
  "0x06127814dca78709650de6629637194f7381d2e05b35eb9d53a4746636c9aa9d",
  "0x086c3c67589e1141c70ed0ed8ae324c51d3bf7c5637043fd84c424ffb625831d",
];

const GAME_SCOPES = [
  ADMIN_CONTRACT_ADDRESS,
  ARRIVAL_STORAGE_CONTRACT_ADDRESS,
  ARTIFACT_ACTION_SYSTEM_CONTRACT_ADDRESS,
  ARTIFACT_FIND_SYSTEM_CONTRACT_ADDRESS,
  ARTIFACT_LOCATION_STORAGE_CONTRACT_ADDRESS,
  ARTIFACT_PROSPECT_SYSTEM_CONTRACT_ADDRESS,
  ARTIFACT_STORAGE_CONTRACT_ADDRESS,
  ARTIFACT_VAULT_SYSTEM_CONTRACT_ADDRESS,
  CONFIG_CONTRACT_ADDRESS,
  CORE_CONTRACT_ADDRESS,
  MOVE_CONTRACT_ADDRESS,
  PLANET_ARTIFACTS_STORAGE_CONTRACT_ADDRESS,
  PLANET_EVENTS_STORAGE_CONTRACT_ADDRESS,
  PLANET_REVEALED_COORDS_STORAGE_CONTRACT_ADDRESS,
  PLANET_STORAGE_CONTRACT_ADDRESS,
  PLAYER_STORAGE_CONTRACT_ADDRESS,
  WORLD_STORAGE_CONTRACT_ADDRESS,
];

/** Scopes for every client simulate/send, including utility preflight reads. */
export function staticTxScopes(): AztecAddress[] {
  return [...AZTEC_STANDARD_SCOPES, ...GAME_SCOPES]
    .filter((addr) => addr && addr.length >= 10)
    .map((addr) => AztecAddress.fromStringUnsafe(addr));
}

/** Static scopes plus the fee sponsor and every account the wallet already knows. */
export async function collectTxScopes(
  wallet: Wallet,
  sponsoredFpcAddress?: AztecAddress
): Promise<AztecAddress[]> {
  const scopes = staticTxScopes();
  if (sponsoredFpcAddress) scopes.push(sponsoredFpcAddress);
  const aliased = [
    ...(await wallet.getAccounts().catch(() => [])),
    ...(await wallet.getAddressBook().catch(() => [])),
  ];
  for (const row of aliased) {
    if (row?.item) scopes.push(row.item);
  }
  return scopes;
}
