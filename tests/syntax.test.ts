/**
 * Fast, Docker-free syntax validation of generated sources:
 *  - Go is parsed with `gofmt` (errors on any syntax problem).
 *  - TypeScript is parsed with Bun's transpiler.
 *
 * This is a cheap gate; full compilation against the real Testcontainers
 * libraries and a live container start live in tests/integration.test.ts.
 */

import { describe, expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";
import { resolveServices } from "../src/generate-tests/devcontainer.js";
import { generateGo } from "../src/generate-tests/generators/go.js";
import { generateTypeScript } from "../src/generate-tests/generators/typescript.js";

const here = dirname(fileURLToPath(import.meta.url));
const multi = resolve(here, "fixtures", "multi", "devcontainer.json");
const { services } = resolveServices(multi);

const gofmtAvailable = spawnSync("gofmt", ["-h"]).error === undefined;

describe("generated Go is syntactically valid", () => {
  test.if(gofmtAvailable)("gofmt parses the generated file", () => {
    const go = generateGo(services, { packageName: "testsuite" });
    const res = spawnSync("gofmt", [], { input: go, encoding: "utf8" });
    expect(res.status, res.stderr).toBe(0);
  });

  if (!gofmtAvailable) {
    test.skip("gofmt not installed - skipping Go syntax check", () => {});
  }
});

describe("generated TypeScript is syntactically valid", () => {
  const transpiler = new Bun.Transpiler({ loader: "ts" });
  const ts = generateTypeScript(services, { baseName: "testcontainers" });

  test("setup module parses", () => {
    expect(() => transpiler.transformSync(ts.setup)).not.toThrow();
  });

  test("sample test parses", () => {
    expect(() => transpiler.transformSync(ts.test)).not.toThrow();
  });
});
