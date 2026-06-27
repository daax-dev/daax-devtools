/**
 * Unit + structural tests for the testcontainer code generator.
 * These run without Docker and validate the DoD acceptance criteria at the
 * level of generated source structure. Real compilation / container start is
 * covered by tests/integration.test.ts.
 */

import { describe, expect, test } from "bun:test";
import { fileURLToPath } from "node:url";
import { tmpdir } from "node:os";
import { mkdtempSync, rmSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { servicesFromComposeText } from "../src/generate-tests/compose.js";
import { resolveServices } from "../src/generate-tests/devcontainer.js";
import {
  classifyImage,
  splitImage,
  topoSort,
  type ServiceDef,
} from "../src/generate-tests/services.js";
import { generate } from "../src/generate-tests/generate.js";
import { generateGo } from "../src/generate-tests/generators/go.js";
import { generateTypeScript } from "../src/generate-tests/generators/typescript.js";
import { run } from "../src/generate-tests/cli.js";

const here = dirname(fileURLToPath(import.meta.url));
const fixture = (...p: string[]) => resolve(here, "fixtures", ...p);

describe("image classification", () => {
  test("recognizes first-class kinds", () => {
    expect(classifyImage("postgres").id).toBe("postgres");
    expect(classifyImage("postgresql").id).toBe("postgres");
    expect(classifyImage("redis").id).toBe("redis");
    expect(classifyImage("elasticsearch").id).toBe("elasticsearch");
    expect(classifyImage("docker.io/library/postgres").id).toBe("postgres");
  });

  test("unknown images fall back to generic", () => {
    expect(classifyImage("rabbitmq").id).toBe("rabbitmq");
    expect(classifyImage("ghcr.io/acme/widget").id).toBe("generic");
  });

  test("splitImage separates repo and tag, handling registry ports", () => {
    expect(splitImage("postgres:15")).toEqual({ repo: "postgres", tag: "15" });
    expect(splitImage("redis")).toEqual({ repo: "redis", tag: "latest" });
    expect(splitImage("registry:5000/team/img")).toEqual({
      repo: "registry:5000/team/img",
      tag: "latest",
    });
    expect(splitImage("registry:5000/team/img:1.2")).toEqual({
      repo: "registry:5000/team/img",
      tag: "1.2",
    });
  });
});

describe("compose parsing", () => {
  test("excludes the app service and parses ports/env/depends_on", () => {
    const text = `
services:
  app:
    build: .
  db:
    image: postgres:15
    environment:
      POSTGRES_PASSWORD: secret
    ports:
      - "5432:5432"
  cache:
    image: redis:7
    depends_on: [db]
    expose: ["6379"]
`;
    const services = servicesFromComposeText(text, "app");
    expect(services.map((s) => s.name).sort()).toEqual(["cache", "db"]);
    const db = services.find((s) => s.name === "db")!;
    expect(db.kind).toBe("postgres");
    expect(db.port).toBe(5432);
    expect(db.env.POSTGRES_PASSWORD).toBe("secret");
    const cache = services.find((s) => s.name === "cache")!;
    expect(cache.kind).toBe("redis");
    expect(cache.port).toBe(6379);
    expect(cache.dependsOn).toEqual(["db"]);
  });

  test("resolves ${VAR} / ${VAR:-default} interpolation from the environment", () => {
    process.env.DAAX_TEST_PG_TAG = "16";
    try {
      const services = servicesFromComposeText(
        "services:\n  db:\n    image: postgres:${DAAX_TEST_PG_TAG:-15}\n    ports: [\"5432:5432\"]\n  cache:\n    image: redis:${DAAX_UNSET_TAG:-7}\n    ports: [\"6379:6379\"]",
      );
      expect(services.find((s) => s.name === "db")!.image).toBe("postgres:16");
      // Unset var falls back to the default.
      expect(services.find((s) => s.name === "cache")!.image).toBe("redis:7");
    } finally {
      delete process.env.DAAX_TEST_PG_TAG;
    }
  });

  test("uses default port when none declared", () => {
    const services = servicesFromComposeText(
      "services:\n  db:\n    image: postgres:15\n",
    );
    expect(services[0].port).toBe(5432);
  });

  test("ignores build-only services without an image", () => {
    const services = servicesFromComposeText(
      "services:\n  worker:\n    build: ./worker\n",
    );
    expect(services).toEqual([]);
  });
});

describe("topological ordering (depends_on)", () => {
  const mk = (name: string, dependsOn: string[] = []): ServiceDef => ({
    name,
    image: `${name}:latest`,
    repo: name,
    tag: "latest",
    kind: "generic",
    port: 1234,
    env: {},
    dependsOn,
  });

  test("dependencies come before dependents", () => {
    const order = topoSort([mk("b", ["a"]), mk("a"), mk("c", ["b"])]).map(
      (s) => s.name,
    );
    expect(order.indexOf("a")).toBeLessThan(order.indexOf("b"));
    expect(order.indexOf("b")).toBeLessThan(order.indexOf("c"));
  });

  test("ignores deps that are not generated services (e.g. the app)", () => {
    const order = topoSort([mk("db", ["app"])]).map((s) => s.name);
    expect(order).toEqual(["db"]);
  });

  test("throws on a dependency cycle", () => {
    expect(() => topoSort([mk("a", ["b"]), mk("b", ["a"])])).toThrow(/cycle/i);
  });
});

describe("Go generation", () => {
  const services = servicesFromComposeText(
    `services:
  db:
    image: postgres:15
    environment:
      POSTGRES_USER: app
      POSTGRES_PASSWORD: secret
      POSTGRES_DB: appdb
    ports: ["5432:5432"]`,
  );
  const go = generateGo(services, { packageName: "testsuite" });

  test("uses GenericContainer (not first-class module) per the spec", () => {
    expect(go).toContain("testcontainers.GenericContainer(ctx");
    expect(go).not.toContain("modules/postgres");
  });

  test("returns a connection string assembled from Host + MappedPort", () => {
    expect(go).toContain(".Host(ctx)");
    expect(go).toContain('.MappedPort(ctx, "5432/tcp")');
    // Credentials are passed as %s args (not interpolated into the format
    // string) so values containing % or " are safe.
    expect(go).toContain(
      'fmt.Sprintf("postgres://%s:%s@%s:%s/%s?sslmode=disable", "app", "secret", dbHost, dbPort.Port(), "appdb")',
    );
    expect(go).toContain("dbConnString string");
  });

  test("escapes and URL-encodes special characters in credentials", () => {
    const svc = servicesFromComposeText(
      'services:\n  db:\n    image: postgres:15\n    environment:\n      POSTGRES_PASSWORD: "p@s%s"\n    ports: ["5432:5432"]',
    );
    const out = generateGo(svc);
    // Password passed as an arg (no fmt corruption) AND URL-encoded so @ and %
    // don't break clients parsing the DSN: p@s%s -> p%40s%25s.
    expect(out).toContain(', "postgres", "p%40s%25s", dbHost, dbPort.Port(), "postgres")');
  });

  test("shares containers across the suite via TestMain", () => {
    expect(go).toContain("func TestMain(m *testing.M)");
    expect(go).toContain("code := m.Run()");
    expect(go).toContain("Terminate(ctx)");
  });
});

describe("TypeScript generation", () => {
  const services = servicesFromComposeText(
    `services:
  cache:
    image: redis:7
    ports: ["6379:6379"]
  queue:
    image: rabbitmq:3
    ports: ["5672:5672"]`,
  );
  const ts = generateTypeScript(services, { baseName: "testcontainers" });

  test("redis uses the first-class RedisContainer module", () => {
    expect(ts.setup).toContain(
      'import { RedisContainer, StartedRedisContainer } from "@testcontainers/redis";',
    );
    expect(ts.setup).toContain("new RedisContainer(\"redis:7\").start()");
    expect(ts.setup).toContain(".getConnectionUrl()");
  });

  test("forwards extra (non-setter) env to first-class containers", () => {
    const svc = servicesFromComposeText(
      "services:\n  db:\n    image: postgres:15\n    environment:\n      POSTGRES_USER: app\n      POSTGRES_INITDB_ARGS: --data-checksums\n    ports: [\"5432:5432\"]",
    );
    const out = generateTypeScript(svc).setup;
    expect(out).toContain('.withUsername("app")');
    // The non-setter var is preserved via withEnvironment.
    expect(out).toContain('.withEnvironment({ "POSTGRES_INITDB_ARGS": "--data-checksums" })');
  });

  test("unknown service falls back to GenericContainer", () => {
    expect(ts.setup).toContain(
      'import { GenericContainer, StartedTestContainer } from "testcontainers";',
    );
    expect(ts.setup).toContain("new GenericContainer(\"rabbitmq:3\")");
    expect(ts.setup).toContain(".withExposedPorts(5672)");
  });

  test("sample suite shares containers via beforeAll/afterAll", () => {
    expect(ts.test).toContain('import { afterAll, beforeAll, describe, expect, it } from "vitest";');
    expect(ts.test).toContain("beforeAll(async () => {");
    expect(ts.test).toContain("await startTestServices()");
    expect(ts.test).toContain("afterAll(async () => {");
    expect(ts.test).not.toContain("beforeEach");
  });
});

describe("end-to-end resolution from fixtures", () => {
  test("postgres fixture yields one postgres service", () => {
    const { services, appService } = resolveServices(
      fixture("postgres", "devcontainer.json"),
    );
    expect(appService).toBe("app");
    expect(services).toHaveLength(1);
    expect(services[0].kind).toBe("postgres");
    expect(services[0].image).toBe("postgres:15");
  });

  test("array dockerComposeFile applies later-file overrides", () => {
    const { services, composeFiles } = resolveServices(
      fixture("override", "devcontainer.json"),
    );
    expect(composeFiles).toHaveLength(2);
    expect(services).toHaveLength(1);
    // docker-compose.override.yml bumps postgres:14 -> postgres:16.
    expect(services[0].image).toBe("postgres:16");
    // Non-overridden fields (ports) survive the merge.
    expect(services[0].port).toBe(5432);
    // environment is merged per-key: the later file adds POSTGRES_USER without
    // dropping the base POSTGRES_PASSWORD / POSTGRES_DB.
    expect(services[0].env).toEqual({
      POSTGRES_PASSWORD: "basepass",
      POSTGRES_DB: "basedb",
      POSTGRES_USER: "overuser",
    });
  });

  test("skips a service with no resolvable port and reports it", () => {
    const skipped: string[] = [];
    const services = servicesFromComposeText(
      "services:\n  widget:\n    image: ghcr.io/acme/widget:1\n",
      undefined,
      (name, reason) => skipped.push(`${name}:${reason}`),
    );
    expect(services).toEqual([]);
    expect(skipped[0]).toContain("widget:");
    expect(skipped[0]).toContain("no recognized default port");
  });

  test("postgres TS uses module setters to preserve declared credentials", () => {
    const { services } = resolveServices(fixture("multi", "devcontainer.json"));
    const ts = generateTypeScript(services);
    // db declares POSTGRES_USER=app, POSTGRES_PASSWORD=secret, POSTGRES_DB=appdb.
    expect(ts.setup).toContain(
      'new PostgreSqlContainer("postgres:15").withUsername("app").withPassword("secret").withDatabase("appdb").start()',
    );
    // elasticsearch env is preserved via withEnvironment.
    expect(ts.setup).toContain('.withEnvironment({ "discovery.type": "single-node"');
  });

  test("multi fixture orders cache after db (depends_on)", () => {
    const { services } = resolveServices(fixture("multi", "devcontainer.json"));
    const go = generateGo(services);
    // db must be initialized before cache in TestMain.
    expect(go.indexOf("db (postgres:15)")).toBeLessThan(
      go.indexOf("cache (redis:7)"),
    );
    const kinds = services.map((s) => s.kind).sort();
    expect(kinds).toEqual(["elasticsearch", "postgres", "rabbitmq", "redis"]);
    // rabbitmq has no first-class TS module -> GenericContainer fallback.
    const ts = generateTypeScript(services);
    expect(ts.setup).toContain('new GenericContainer("rabbitmq:3")');
  });
});

describe("CLI behavior", () => {
  test("--dry-run prints generated content and writes nothing", () => {
    const result = run([
      "--devcontainer",
      fixture("postgres", "devcontainer.json"),
      "--dry-run",
    ]);
    expect(result.exitCode).toBe(0);
    expect(result.written).toEqual([]);
    const out = result.stdout.join("\n");
    expect(out).toContain("DRY RUN");
    expect(out).toContain("func TestMain"); // actual Go content, not just a filename
    expect(out).toContain("startTestServices"); // actual TS content
  });

  test("rejects an unsupported --target", () => {
    const result = run([
      "--devcontainer",
      fixture("postgres", "devcontainer.json"),
      "--target",
      "junit",
    ]);
    expect(result.exitCode).toBe(2);
    expect(result.stderr.join("\n")).toContain("unsupported --target");
  });

  test("errors clearly when no compose file is referenced", () => {
    const result = run(["--devcontainer", fixture("nope.json")]);
    expect(result.exitCode).toBe(1);
  });

  test("writes files when not a dry run", () => {
    const outDir = mkdtempSync(join(tmpdir(), "daax-tc-"));
    try {
      const result = run([
        "--devcontainer",
        fixture("postgres", "devcontainer.json"),
        "--lang",
        "go",
        "--out",
        outDir,
      ]);
      expect(result.exitCode).toBe(0);
      expect(result.written).toHaveLength(1);
      expect(result.written[0]).toContain("testcontainers_setup_test.go");
    } finally {
      rmSync(outDir, { recursive: true, force: true });
    }
  });
});

describe("generate() file set", () => {
  const services = servicesFromComposeText(
    "services:\n  db:\n    image: postgres:15\n",
  );

  test("both languages produce three files", () => {
    const files = generate(services, { lang: "both" });
    expect(files.map((f) => f.path).sort()).toEqual([
      "testcontainers.setup.ts",
      "testcontainers.test.ts",
      "testcontainers_setup_test.go",
    ]);
  });

  test("lang filter narrows output", () => {
    expect(generate(services, { lang: "go" })).toHaveLength(1);
    expect(generate(services, { lang: "ts" })).toHaveLength(2);
  });
});
