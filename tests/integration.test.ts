/**
 * Integration test: runs the real verification harness (compile generated Go
 * against testcontainers-go, typecheck generated TS against the testcontainers
 * packages, and — if Docker is available — start live containers).
 *
 * Skipped by default because it is slow and requires the Go toolchain and a
 * Docker daemon. Enable with:
 *
 *   DAAX_TC_INTEGRATION=1 bun test tests/integration.test.ts
 *   # or: bun run test:integration
 */

import { describe, expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

const here = dirname(fileURLToPath(import.meta.url));
const script = resolve(here, "..", "scripts", "verify-generated.sh");
const enabled = process.env.DAAX_TC_INTEGRATION === "1";

describe("generated code compiles and runs (integration)", () => {
  test.if(enabled)(
    "verify-generated.sh passes",
    () => {
      const res = spawnSync("bash", [script], {
        encoding: "utf8",
        stdio: "inherit",
      });
      expect(res.status).toBe(0);
    },
    600_000,
  );

  if (!enabled) {
    test.skip("set DAAX_TC_INTEGRATION=1 to run the integration harness", () => {});
  }
});
