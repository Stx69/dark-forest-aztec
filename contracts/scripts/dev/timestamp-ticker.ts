/**
 * Sends a no-op transaction periodically to keep the local Aztec chain producing blocks,
 * so you can get correct timestamps when testing.
 *
 * Usage: node --experimental-transform-types scripts/dev/timestamp-ticker.ts [intervalSeconds]
 *   intervalSeconds: interval in seconds (default 12)
 *
 * Prerequisites: deploy + configure done, .env has ACCOUNT_* and ADMIN_CONTRACT_ADDRESS
 */
import { SponsoredFeePaymentMethod } from '@aztec/aztec.js/fee';
import { SponsoredFPCContractArtifact } from '@aztec/noir-contracts.js/SponsoredFPC';

import {
    createTolerantAztecNodeClient,
    getAztecNodeUrl,
    getContractInstances,
    getOptionalEnv,
    getProverEnabled,
    getSponsoredPFCContract,
    loadContractsEnv,
    resolveDeployerAccount,
    setupWallet,
} from '../utils/index.ts';

loadContractsEnv();

const AZTEC_NODE_URL = getAztecNodeUrl();
const PROVER_ENABLED = getProverEnabled();
const INTERVAL_SEC = parseInt(process.argv[2] || '12', 10) || 12;
const SEND_TIMEOUT_MS = 20_000;

const CONTRACT_SPECS = [
    {
        name: 'Admin',
        modulePath: './artifacts/Admin.ts',
        exportName: 'AdminContract',
    },
];
async function main() {
    const adminAddr = getOptionalEnv('ADMIN_CONTRACT_ADDRESS');
    if (!adminAddr) {
        throw new Error(
            'Missing ADMIN_CONTRACT_ADDRESS in .env. Run deploy + configure first.'
        );
    }

    console.log(
        `🕐 Timestamp ticker — sending no-op tx every ${INTERVAL_SEC}s`
    );
    console.log(`   Node: ${AZTEC_NODE_URL}\n`);

    const aztecNode = createTolerantAztecNodeClient(AZTEC_NODE_URL);
    const wallet = await setupWallet(aztecNode, {
        clearStore: false,
        proverEnabled: PROVER_ENABLED,
    });

    const sponsoredFPC = await getSponsoredPFCContract();
    await wallet.registerContract(sponsoredFPC, SponsoredFPCContractArtifact);

    const admin = await resolveDeployerAccount(wallet, aztecNode, {
        mode: 'loadOnly',
        deployTimeoutMs: 120_000,
    });
    const contracts = await getContractInstances(
        wallet,
        { Admin: adminAddr },
        CONTRACT_SPECS
    );
    const Admin = contracts['Admin'];
    if (!Admin) throw new Error('Admin contract not loaded.');

    const sendOpts = () => ({
        from: admin,
        fee: {
            paymentMethod: new SponsoredFeePaymentMethod(sponsoredFPC.address),
        },
    });

    let count = 0;
    let inFlight = false;
    const sleep = (ms: number) =>
        new Promise((resolve) => setTimeout(resolve, ms));

    while (true) {
        const started = Date.now();
        count++;
        if (inFlight) {
            console.log(
                `[${new Date().toISOString()}] #${count} skipped — previous tick still sending`
            );
        } else {
            inFlight = true;
            const tick = count;
            void (async () => {
                const ts = new Date().toISOString();
                console.log(`[${ts}] #${tick} sending admin no-op`);
                try {
                    const blockBefore = await aztecNode.getBlockNumber();
                    const sent = Admin.methods
                        .transfer_admin(admin)
                        .send(sendOpts());
                    await Promise.race([
                        sent,
                        sleep(SEND_TIMEOUT_MS).then(() => {
                            throw new Error(
                                `send still waiting after ${SEND_TIMEOUT_MS / 1000}s`
                            );
                        }),
                    ]);
                    const blockAfter = await aztecNode.getBlockNumber();
                    console.log(
                        `[${new Date().toISOString()}] #${tick} tx sent — block ${blockBefore} → ${blockAfter}`
                    );
                } catch (e) {
                    console.error(
                        `[${new Date().toISOString()}] #${tick} failed:`,
                        e instanceof Error ? e.message : e
                    );
                } finally {
                    inFlight = false;
                }
            })();
        }

        const elapsed = Date.now() - started;
        await sleep(Math.max(0, INTERVAL_SEC * 1000 - elapsed));
    }
}

main().catch((e) => {
    console.error(e);
    process.exit(1);
});
