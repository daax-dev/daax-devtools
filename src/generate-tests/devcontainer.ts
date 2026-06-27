/**
 * Read a `devcontainer.json` and resolve the backing services it declares.
 *
 * The devcontainer spec declares additional services through the standard
 * `dockerComposeFile` mechanism: the referenced compose file's `services:`
 * are the dependencies, and `service` names the devcontainer's own app
 * container (excluded from generation).
 */

import { readFileSync } from "node:fs";
import { dirname, isAbsolute, resolve } from "node:path";
import { parse as parseYaml } from "yaml";
import { extractEnv, servicesFromCompose, type SkipReporter } from "./compose.js";
import type { ServiceDef } from "./services.js";

export interface Devcontainer {
  dockerComposeFile?: string | string[];
  service?: string;
  [key: string]: unknown;
}

export interface ResolvedServices {
  services: ServiceDef[];
  /** Absolute paths of compose files that were read. */
  composeFiles: string[];
  /** The app service name, if declared. */
  appService?: string;
  /** Services that were skipped, each formatted as "name: reason". */
  skipped: string[];
}

/**
 * Strip comments and trailing commas from JSONC so it parses as JSON.
 * devcontainer.json permits `//` and block comments and trailing commas.
 */
export function parseJsonc(text: string): unknown {
  let out = "";
  let inString = false;
  let quote = "";
  let inLineComment = false;
  let inBlockComment = false;

  for (let i = 0; i < text.length; i++) {
    const ch = text[i];
    const next = text[i + 1];

    if (inLineComment) {
      if (ch === "\n") {
        inLineComment = false;
        out += ch;
      }
      continue;
    }
    if (inBlockComment) {
      if (ch === "*" && next === "/") {
        inBlockComment = false;
        i++;
      }
      continue;
    }
    if (inString) {
      out += ch;
      if (ch === "\\") {
        // Preserve escaped character verbatim.
        out += next ?? "";
        i++;
      } else if (ch === quote) {
        inString = false;
      }
      continue;
    }

    if (ch === '"' || ch === "'") {
      inString = true;
      quote = ch;
      out += ch;
      continue;
    }
    if (ch === "/" && next === "/") {
      inLineComment = true;
      i++;
      continue;
    }
    if (ch === "/" && next === "*") {
      inBlockComment = true;
      i++;
      continue;
    }
    out += ch;
  }

  // Remove trailing commas before } or ].
  const noTrailingCommas = out.replace(/,(\s*[}\]])/g, "$1");
  return JSON.parse(noTrailingCommas);
}

/** Parse devcontainer.json text into a `Devcontainer`. */
export function parseDevcontainer(text: string): Devcontainer {
  const parsed = parseJsonc(text);
  if (!parsed || typeof parsed !== "object") {
    throw new Error("devcontainer.json did not parse to an object");
  }
  return parsed as Devcontainer;
}

/**
 * Resolve all backing services declared by a devcontainer.json on disk.
 *
 * @param devcontainerPath Path to devcontainer.json.
 * @param composeOverride  Optional explicit compose file path, bypassing
 *                         `dockerComposeFile` resolution.
 */
export function resolveServices(
  devcontainerPath: string,
  composeOverride?: string,
): ResolvedServices {
  const dcDir = dirname(resolve(devcontainerPath));
  const dc = parseDevcontainer(readFileSync(devcontainerPath, "utf8"));

  const composeRefs = composeOverride
    ? [composeOverride]
    : normalizeComposeRefs(dc.dockerComposeFile);

  if (composeRefs.length === 0) {
    throw new Error(
      `No services found: ${devcontainerPath} does not reference a ` +
        `dockerComposeFile. Pass --compose <file> to point at one explicitly.`,
    );
  }

  const composeFiles: string[] = [];
  // Merge the `services` maps across all referenced compose files following
  // Docker Compose override semantics: later files override earlier ones,
  // merged per service. Only then do we classify into ServiceDefs.
  const mergedServices: Record<string, Record<string, unknown>> = {};

  for (const ref of composeRefs) {
    const composePath = isAbsolute(ref) ? ref : resolve(dcDir, ref);
    composeFiles.push(composePath);
    const doc = parseYaml(readFileSync(composePath, "utf8")) as
      | { services?: Record<string, Record<string, unknown>> }
      | null
      | undefined;
    const svcMap = doc && typeof doc === "object" ? doc.services : undefined;
    if (!svcMap || typeof svcMap !== "object") continue;
    for (const [name, raw] of Object.entries(svcMap)) {
      mergedServices[name] = mergeService(mergedServices[name], raw ?? {});
    }
  }

  const skipped: string[] = [];
  const onSkip: SkipReporter = (name, reason) =>
    skipped.push(`${name}: ${reason}`);
  const services = servicesFromCompose(
    { services: mergedServices },
    dc.service,
    onSkip,
  );

  return { services, composeFiles, appService: dc.service, skipped };
}

/**
 * Merge one compose service definition over another following Compose override
 * semantics: scalar/array keys (image, ports, depends_on) are replaced by the
 * later file, but `environment` maps are merged key-by-key so a later file that
 * overrides one variable does not drop the others.
 */
function mergeService(
  prev: Record<string, unknown> | undefined,
  next: Record<string, unknown>,
): Record<string, unknown> {
  const merged: Record<string, unknown> = { ...(prev ?? {}), ...next };
  if (prev && ("environment" in prev || "environment" in next)) {
    merged.environment = {
      ...extractEnv(prev.environment),
      ...extractEnv(next.environment),
    };
  }
  return merged;
}

function normalizeComposeRefs(ref: string | string[] | undefined): string[] {
  if (!ref) return [];
  return Array.isArray(ref) ? ref.filter((r) => typeof r === "string") : [ref];
}
