#!/usr/bin/env bun
/**
 * `daax dev generate-tests` — auto-generate Testcontainers bootstrap code from
 * a devcontainer's docker-compose service definitions.
 *
 * Usage:
 *   daax-generate-tests [options]
 *
 * Options:
 *   --target <name>        Generation target. Only "testcontainers" (default).
 *   --devcontainer <path>  Path to devcontainer.json
 *                          (default: auto-detected).
 *   --compose <path>       Explicit docker-compose file, overriding the
 *                          devcontainer's dockerComposeFile.
 *   --lang <go|ts|both>    Languages to emit (default: both).
 *   --out <dir>            Output directory (default: ./testcontainers).
 *   --go-package <name>    Go package name (default: testsuite).
 *   --base-name <name>     Base name for generated files (default:
 *                          testcontainers).
 *   --dry-run              Print generated content to stdout; write nothing.
 *   -h, --help             Show this help.
 */

import { parseArgs } from "node:util";
import { existsSync, mkdirSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { resolveServices } from "./devcontainer.js";
import { generate, type Lang } from "./generate.js";

const HELP = `daax dev generate-tests — generate Testcontainers setup from devcontainer services

Usage: daax-generate-tests [options]

Options:
  --target <name>        Generation target. Only "testcontainers" (default).
  --devcontainer <path>  Path to devcontainer.json (default: auto-detected).
  --compose <path>       Explicit docker-compose file (overrides dockerComposeFile).
  --lang <go|ts|both>    Languages to emit (default: both).
  --out <dir>            Output directory (default: ./testcontainers).
  --go-package <name>    Go package name (default: testsuite).
  --base-name <name>     Base name for generated files (default: testcontainers).
  --dry-run              Print what would be generated without writing files.
  -h, --help             Show this help.
`;

const DEFAULT_DEVCONTAINER_PATHS = [
  ".devcontainer/devcontainer.json",
  ".devcontainer.json",
  "devcontainer.json",
  "devcontainer/devcontainer.json",
];

export interface CliResult {
  exitCode: number;
  /** Lines written to stdout (captured for testing). */
  stdout: string[];
  /** Lines written to stderr (captured for testing). */
  stderr: string[];
  /** Files written to disk (empty on --dry-run). */
  written: string[];
}

export function run(argv: string[]): CliResult {
  const stdout: string[] = [];
  const stderr: string[] = [];
  const written: string[] = [];

  let parsed;
  try {
    parsed = parseArgs({
      args: argv,
      options: {
        target: { type: "string", default: "testcontainers" },
        devcontainer: { type: "string" },
        compose: { type: "string" },
        lang: { type: "string", default: "both" },
        out: { type: "string", default: "testcontainers" },
        "go-package": { type: "string", default: "testsuite" },
        "base-name": { type: "string", default: "testcontainers" },
        "dry-run": { type: "boolean", default: false },
        help: { type: "boolean", short: "h", default: false },
      },
      allowPositionals: false,
    });
  } catch (err) {
    stderr.push(`error: ${(err as Error).message}`);
    stderr.push(HELP);
    return { exitCode: 2, stdout, stderr, written };
  }

  const opts = parsed.values;

  if (opts.help) {
    stdout.push(HELP);
    return { exitCode: 0, stdout, stderr, written };
  }

  // Validate --target.
  if (opts.target !== "testcontainers") {
    stderr.push(
      `error: unsupported --target "${opts.target}". Only "testcontainers" is supported.`,
    );
    return { exitCode: 2, stdout, stderr, written };
  }

  // Validate --lang.
  const lang = opts.lang as string;
  if (!["go", "ts", "both"].includes(lang)) {
    stderr.push(`error: invalid --lang "${lang}". Use go, ts, or both.`);
    return { exitCode: 2, stdout, stderr, written };
  }

  // Resolve devcontainer path.
  const devcontainerPath = opts.devcontainer
    ? resolve(opts.devcontainer)
    : autoDetectDevcontainer();
  if (!devcontainerPath) {
    stderr.push(
      "error: could not find a devcontainer.json. Pass --devcontainer <path>.",
    );
    return { exitCode: 1, stdout, stderr, written };
  }
  if (!existsSync(devcontainerPath)) {
    stderr.push(`error: devcontainer not found: ${devcontainerPath}`);
    return { exitCode: 1, stdout, stderr, written };
  }

  // Resolve services.
  let resolved;
  try {
    resolved = resolveServices(
      devcontainerPath,
      opts.compose ? resolve(opts.compose) : undefined,
    );
  } catch (err) {
    stderr.push(`error: ${(err as Error).message}`);
    return { exitCode: 1, stdout, stderr, written };
  }

  for (const skipped of resolved.skipped) {
    stderr.push(`warning: skipped ${skipped}`);
  }

  if (resolved.services.length === 0) {
    stderr.push(
      "warning: no backing services were found in the devcontainer's compose " +
        "definition; nothing meaningful to generate.",
    );
  }

  const outDir = resolve(opts.out as string);
  const files = generate(resolved.services, {
    lang: lang as Lang,
    goPackage: opts["go-package"] as string,
    baseName: opts["base-name"] as string,
  });

  const serviceSummary = resolved.services
    .map((s) => `${s.name} (${s.image} -> ${s.kind})`)
    .join(", ");
  stdout.push(
    `Found ${resolved.services.length} service(s): ${serviceSummary || "(none)"}`,
  );

  if (opts["dry-run"]) {
    stdout.push("");
    stdout.push("=== DRY RUN: the following files would be generated ===");
    for (const file of files) {
      const target = resolve(outDir, file.path);
      stdout.push("");
      stdout.push(`----- ${target} (${file.language}) -----`);
      stdout.push(file.content);
    }
    return { exitCode: 0, stdout, stderr, written };
  }

  // Write files.
  for (const file of files) {
    const target = resolve(outDir, file.path);
    mkdirSync(dirname(target), { recursive: true });
    writeFileSync(target, file.content);
    written.push(target);
    stdout.push(`wrote ${target}`);
  }

  return { exitCode: 0, stdout, stderr, written };
}

function autoDetectDevcontainer(): string | undefined {
  for (const candidate of DEFAULT_DEVCONTAINER_PATHS) {
    const p = resolve(candidate);
    if (existsSync(p)) return p;
  }
  return undefined;
}

/** Entry point: run, flush captured output, and exit. */
export function main(argv = process.argv.slice(2)): void {
  const result = run(argv);
  for (const line of result.stdout) console.log(line);
  for (const line of result.stderr) console.error(line);
  process.exit(result.exitCode);
}

// Execute when invoked directly (works under both node and bun).
const invokedPath = process.argv[1] ? resolve(process.argv[1]) : "";
const thisPath = resolve(new URL(import.meta.url).pathname);
if (invokedPath && invokedPath === thisPath) {
  main();
}
