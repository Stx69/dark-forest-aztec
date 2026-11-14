import { readFileSync, realpathSync } from "node:fs";
import { createRequire } from "node:module";
import path from "node:path";

import react from "@vitejs/plugin-react";
import { defineConfig, type Plugin } from "vite";
import { nodePolyfills } from "vite-plugin-node-polyfills";

const require = createRequire(import.meta.url);

// pnpm does not hoist this transitive package to node_modules/@aztec, so Vite
// cannot resolve the bare import left in prebundled @aztec-labs/stdlib.
// stdlib exports omit "./package.json", so locate the package from an exported file.
const stdlibDir = realpathSync(
  path.join(path.dirname(require.resolve("@aztec-labs/stdlib/tx")), "../..")
);
// Aztec 6 publishes these under @aztec-foundation (not exported as package.json).
const stdlibRequire = createRequire(require.resolve("@aztec-labs/stdlib/tx"));
const noirAbiDir = realpathSync(
  path.join(
    path.dirname(stdlibRequire.resolve("@aztec-foundation/noir-noirc_abi")),
    ".."
  )
);
const noirAcvmDir = realpathSync(
  path.join(
    path.dirname(stdlibRequire.resolve("@aztec-foundation/noir-acvm_js")),
    ".."
  )
);
// Keep simulator resolvable for the client graph (same as Aztec 5 Vite setup).
const aztecJsRequire = createRequire(
  require.resolve("@aztec-labs/aztec.js/fields")
);
void aztecJsRequire.resolve("@aztec-labs/simulator/client");

// pnpm keeps a second @aztec-labs/stdlib (different peer graph). AztecAddress.equals
// then fails even when the hex is already in the allowed scopes list.
function forceSinglePackage(packageName: string, packageDir: string): Plugin {
  const prefix = `${packageName}/`;
  return {
    name: `force-single-${packageName}`,
    enforce: "pre",
    async resolveId(id, _importer, options) {
      if (id !== packageName && !id.startsWith(prefix)) return null;
      return this.resolve(id, path.join(packageDir, "package.json"), {
        ...options,
        skipSelf: true,
      });
    },
  };
}

/**
 * sqlite3mc's loader resolves `sqlite3.wasm` and `sqlite3-opfs-async-proxy.js`
 * via dynamic paths relative to the emitted worker chunk. Vite hashes the wasm
 * and never emits the proxy script, so production requests 404 → SPA HTML.
 * Emit both under the fixed names the runtime expects.
 */
function emitSqliteRuntimeAssets(): Plugin {
  const opfsProxySource = readFileSync(
    require.resolve("@aztec-labs/sqlite3mc-wasm/vendor/jswasm/sqlite3-opfs-async-proxy.js"),
    "utf8"
  );

  return {
    name: "emit-sqlite-runtime-assets",
    generateBundle(_options, bundle) {
      const sqliteWasm = Object.values(bundle).find(
        (output) =>
          output.type === "asset" &&
          /^assets\/sqlite3-.*\.wasm$/.test(output.fileName)
      );

      if (sqliteWasm?.type === "asset") {
        this.emitFile({
          type: "asset",
          fileName: "assets/sqlite3.wasm",
          source: sqliteWasm.source,
        });
      }

      this.emitFile({
        type: "asset",
        fileName: "assets/sqlite3-opfs-async-proxy.js",
        source: opfsProxySource,
      });
    },
  };
}

export default defineConfig({
  worker: {
    format: "es",
  },
  plugins: [
    forceSinglePackage("@aztec-labs/stdlib", stdlibDir),
    emitSqliteRuntimeAssets(),
    react(),
    nodePolyfills({
      include: [
        "buffer",
        "crypto",
        "util",
        "stream",
        "process",
        "events",
        "path",
        "string_decoder",
        "tty",
        "vm",
      ],
      globals: {
        Buffer: true,
        global: true,
        process: true,
      },
    }),
  ],
  server: {
    headers: {
      "Cross-Origin-Opener-Policy": "same-origin",
      "Cross-Origin-Embedder-Policy": "credentialless",
    },
  },
  resolve: {
    alias: {
      "@aztec-foundation/noir-noirc_abi": noirAbiDir,
      "@aztec-foundation/noir-acvm_js": noirAcvmDir,
    },
    // pnpm installs two @aztec-labs/foundation copies (different peer graphs).
    // BaseField rejects a field from the other copy, which breaks getPublicEvents.
    dedupe: [
      "@aztec-labs/foundation",
      "@aztec-labs/stdlib",
      "@aztec-labs/aztec.js",
    ],
  },
  build: {
    target: "esnext",
  },
  optimizeDeps: {
    esbuildOptions: {
      target: "esnext",
    },
    include: [
      "@aztec-labs/aztec.js/fields",
      "@aztec-labs/aztec.js/addresses",
      "@aztec-labs/aztec.js/abi",
      "@aztec-labs/aztec.js/contracts",
      "@aztec-labs/aztec.js/wallet",
      "@aztec-labs/foundation/crypto/poseidon",
      "@aztec-labs/accounts/schnorr/lazy",
      "@aztec-labs/accounts/schnorr/stub/lazy",
      "@aztec-labs/standard-contracts/multi-call-entrypoint/lazy",
      "msgpackr/index-no-eval",
      "pino",
    ],
    exclude: [
      "@aztec-foundation/bb.js",
      "@aztec-foundation/noir-acvm_js",
      "@aztec-foundation/noir-noirc_abi",
      "@aztec-labs/kv-store/sqlite-opfs",
    ],
  },
});
