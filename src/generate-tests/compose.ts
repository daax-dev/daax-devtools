/**
 * Parse a docker-compose file into normalized `ServiceDef`s.
 *
 * Only the subset of the compose schema relevant to Testcontainers generation
 * is interpreted: `image`, `ports`, `expose`, `environment`, and `depends_on`.
 */

import { parse as parseYaml } from "yaml";
import {
  classifyImage,
  splitImage,
  type ServiceDef,
} from "./services.js";

interface RawService {
  image?: unknown;
  ports?: unknown;
  expose?: unknown;
  environment?: unknown;
  depends_on?: unknown;
}

/**
 * Resolve Docker Compose variable interpolation in a string against the current
 * process environment, matching Compose's `${VAR}`, `${VAR:-default}`,
 * `${VAR-default}`, and `$VAR` forms. Unset variables with no default resolve
 * to an empty string (as Compose does).
 */
export function interpolate(value: string): string {
  return value
    .replace(
      /\$\{([A-Za-z_][A-Za-z0-9_]*)(:?-)?([^}]*)\}/g,
      (_m, name: string, op: string | undefined, def: string) => {
        const v = process.env[name];
        if (op === ":-") return v != null && v !== "" ? v : def;
        if (op === "-") return v != null ? v : def;
        return v ?? "";
      },
    )
    .replace(/\$([A-Za-z_][A-Za-z0-9_]*)/g, (_m, name: string) =>
      process.env[name] != null ? (process.env[name] as string) : "",
    );
}

interface RawCompose {
  services?: Record<string, RawService>;
}

/**
 * Convert a parsed compose document into `ServiceDef[]`.
 *
 * @param doc        Parsed compose document.
 * @param appService Name of the devcontainer's own service, which is excluded
 *                   from the result (we generate containers for *dependencies*,
 *                   not the app under test).
 */
/** Optional callback invoked when a service is skipped, with the reason. */
export type SkipReporter = (name: string, reason: string) => void;

export function servicesFromCompose(
  doc: unknown,
  appService?: string,
  onSkip?: SkipReporter,
): ServiceDef[] {
  if (!doc || typeof doc !== "object") {
    throw new Error("compose file is empty or not an object");
  }
  const services = (doc as RawCompose).services;
  if (!services || typeof services !== "object") {
    return [];
  }

  const result: ServiceDef[] = [];
  for (const [name, rawUnknown] of Object.entries(services)) {
    if (name === appService) continue;
    const raw = (rawUnknown ?? {}) as RawService;

    const image =
      typeof raw.image === "string" ? interpolate(raw.image.trim()) : "";
    if (!image) {
      // A service without an image (build-only) cannot be a Testcontainer.
      onSkip?.(name, "no image declared (build-only service)");
      continue;
    }

    const { repo, tag } = splitImage(image);
    const kind = classifyImage(repo);
    const declaredPorts = extractPorts(raw);
    let port = declaredPorts[0] ?? (kind.defaultPort > 0 ? kind.defaultPort : 0);
    if (kind.defaultPort > 0 && declaredPorts.includes(kind.defaultPort)) {
      port = kind.defaultPort;
    }

    if (port === 0) {
      // An unrecognized image with no ports/expose has no port to map; emitting
      // a container for it would produce invalid `0/tcp` setup. Skip it loudly
      // rather than generate code that cannot run.
      onSkip?.(
        name,
        `image "${image}" has no recognized default port and declares no ` +
          "ports/expose; add a ports or expose entry to include it",
      );
      continue;
    }

    result.push({
      name,
      image,
      repo,
      tag,
      kind: kind.id,
      port,
      env: extractEnv(raw.environment),
      dependsOn: extractDependsOn(raw.depends_on),
    });
  }
  return result;
}

/** Parse YAML/JSON compose text into `ServiceDef[]`. */
export function servicesFromComposeText(
  text: string,
  appService?: string,
  onSkip?: SkipReporter,
): ServiceDef[] {
  return servicesFromCompose(parseYaml(text), appService, onSkip);
}

/** Container ports from `expose:` (preferred) or `ports:` mappings. */
function extractPorts(raw: RawService): number[] {
  const ports: number[] = [];

  // `expose` lists container ports directly.
  if (Array.isArray(raw.expose)) {
    for (const e of raw.expose) {
      const n = parsePort(String(e));
      if (n !== null) ports.push(n);
    }
  }

  // `ports` maps host:container; the container port is what we need.
  if (Array.isArray(raw.ports)) {
    for (const p of raw.ports) {
      const containerPort = parseContainerPort(p);
      if (containerPort !== null) ports.push(containerPort);
    }
  }

  // De-duplicate while preserving order.
  return [...new Set(ports)];
}

/** Extract the container-side port from a compose `ports` entry. */
function parseContainerPort(entry: unknown): number | null {
  // Validate numeric entries the same way as strings so out-of-range values
  // like `ports: [0]` or `ports: [70000]` are rejected, not propagated.
  if (typeof entry === "number") return parsePort(String(entry));
  if (entry && typeof entry === "object") {
    // Long syntax: { target: 5432, published: 5432 }
    const target = (entry as { target?: unknown }).target;
    return parsePort(String(target));
  }
  if (typeof entry !== "string") return null;
  // Short syntax variants: "5432", "5432:5432", "127.0.0.1:5432:5432",
  // "5432:5432/tcp". The container port is the segment before any "/proto",
  // after the last ":".
  const noProto = entry.split("/")[0];
  const segments = noProto.split(":");
  return parsePort(segments[segments.length - 1]);
}

function parsePort(value: string): number | null {
  const s = interpolate(value.trim());
  // Reject anything that is not purely a port number — e.g. Compose port
  // ranges like "5432-5433" must not be silently truncated to 5432.
  if (!/^\d+$/.test(s)) return null;
  const n = Number.parseInt(s, 10);
  return n > 0 && n < 65536 ? n : null;
}

/** Normalize compose `environment` (list or map form) into a string map. */
export function extractEnv(environment: unknown): Record<string, string> {
  const env: Record<string, string> = {};
  if (Array.isArray(environment)) {
    for (const item of environment) {
      if (typeof item !== "string") continue;
      const eq = item.indexOf("=");
      if (eq === -1) env[item] = interpolate(process.env[item] ?? "");
      else env[item.slice(0, eq)] = interpolate(item.slice(eq + 1));
    }
  } else if (environment && typeof environment === "object") {
    for (const [k, v] of Object.entries(environment as Record<string, unknown>)) {
      env[k] = v == null ? "" : interpolate(String(v));
    }
  }
  return env;
}

/** Normalize compose `depends_on` (list or map form) into a name array. */
function extractDependsOn(dependsOn: unknown): string[] {
  if (Array.isArray(dependsOn)) {
    return dependsOn.filter((d): d is string => typeof d === "string");
  }
  if (dependsOn && typeof dependsOn === "object") {
    return Object.keys(dependsOn as Record<string, unknown>);
  }
  return [];
}
