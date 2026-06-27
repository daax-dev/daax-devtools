/**
 * Service model and image classification for testcontainer code generation.
 *
 * A `ServiceDef` is the normalized, language-agnostic description of a single
 * backing service (postgres, redis, …) extracted from a devcontainer's
 * docker-compose definition. Generators consume `ServiceDef[]` to emit
 * idiomatic Testcontainers bootstrap code.
 */

export interface ServiceDef {
  /** Compose service name, e.g. "db". Used as the variable/identifier root. */
  name: string;
  /** Full image reference as declared, e.g. "postgres:15". */
  image: string;
  /** Image repository without tag, lowercased, e.g. "postgres". */
  repo: string;
  /** Image tag, e.g. "15". Defaults to "latest" when omitted. */
  tag: string;
  /** Classified kind (postgres, redis, …) or "generic" when unrecognized. */
  kind: ServiceKindId;
  /** Container port the service listens on. */
  port: number;
  /** Environment variables declared for the service. */
  env: Record<string, string>;
  /** Names of services this service depends on (must start first). */
  dependsOn: string[];
}

export type ServiceKindId =
  | "postgres"
  | "redis"
  | "mysql"
  | "mongodb"
  | "elasticsearch"
  | "rabbitmq"
  | "generic";

export interface ServiceKind {
  id: ServiceKindId;
  /** Image-repo substrings that identify this kind. */
  match: string[];
  /** Default listening port when compose does not declare one. */
  defaultPort: number;
  /**
   * TypeScript first-class Testcontainers module, when one exists and has been
   * compile-verified. `null` => fall back to GenericContainer.
   */
  ts: {
    module: string;
    className: string;
    /** Method on the started container returning a connection string. */
    connMethod: string;
  } | null;
}

/**
 * Registry of recognized services. TS first-class modules are only declared
 * for kinds whose generated output we compile-verify (postgres, redis,
 * elasticsearch). Everything else uses GenericContainer in both languages,
 * whose API surface is stable across Testcontainers releases.
 */
export const SERVICE_KINDS: ServiceKind[] = [
  {
    id: "postgres",
    match: ["postgres", "postgresql"],
    defaultPort: 5432,
    ts: {
      module: "@testcontainers/postgresql",
      className: "PostgreSqlContainer",
      connMethod: "getConnectionUri",
    },
  },
  {
    id: "redis",
    match: ["redis"],
    defaultPort: 6379,
    ts: {
      module: "@testcontainers/redis",
      className: "RedisContainer",
      connMethod: "getConnectionUrl",
    },
  },
  {
    id: "elasticsearch",
    match: ["elasticsearch"],
    defaultPort: 9200,
    ts: {
      module: "@testcontainers/elasticsearch",
      className: "ElasticsearchContainer",
      connMethod: "getHttpUrl",
    },
  },
  { id: "mysql", match: ["mysql", "mariadb"], defaultPort: 3306, ts: null },
  { id: "mongodb", match: ["mongo"], defaultPort: 27017, ts: null },
  { id: "rabbitmq", match: ["rabbitmq"], defaultPort: 5672, ts: null },
];

const GENERIC_KIND: ServiceKind = {
  id: "generic",
  match: [],
  defaultPort: 0,
  ts: null,
};

/** Resolve the `ServiceKind` for an image repository. */
export function classifyImage(repo: string): ServiceKind {
  const lower = repo.toLowerCase();
  // Use the last path segment so registry-qualified images still classify,
  // e.g. "docker.io/library/postgres" -> "postgres".
  const segment = lower.split("/").pop() ?? lower;
  for (const kind of SERVICE_KINDS) {
    if (kind.match.some((m) => segment === m || segment.includes(m))) {
      return kind;
    }
  }
  return GENERIC_KIND;
}

/** Split an image reference into `{ repo, tag }`. */
export function splitImage(image: string): { repo: string; tag: string } {
  // Strip a digest (`@sha256:...`) first so it is not mistaken for a `:tag`.
  const atIdx = image.indexOf("@");
  const ref = atIdx === -1 ? image : image.slice(0, atIdx);
  const digest = atIdx === -1 ? "" : image.slice(atIdx + 1);

  // Tag is the part after the LAST colon, but only if that segment has no "/"
  // (otherwise the colon belongs to a registry:port host).
  const lastColon = ref.lastIndexOf(":");
  if (lastColon === -1) return { repo: ref, tag: digest || "latest" };
  const maybeTag = ref.slice(lastColon + 1);
  if (maybeTag.includes("/")) return { repo: ref, tag: digest || "latest" };
  return { repo: ref.slice(0, lastColon), tag: maybeTag };
}

/**
 * Topologically sort services so that every service appears after all of its
 * `dependsOn` targets. Throws on a dependency cycle. Ordering among
 * independent services is stable (declaration order preserved).
 */
export function topoSort(services: ServiceDef[]): ServiceDef[] {
  const byName = new Map(services.map((s) => [s.name, s]));
  const sorted: ServiceDef[] = [];
  const state = new Map<string, "visiting" | "done">();

  const visit = (svc: ServiceDef, trail: string[]): void => {
    const status = state.get(svc.name);
    if (status === "done") return;
    if (status === "visiting") {
      throw new Error(
        `Dependency cycle detected: ${[...trail, svc.name].join(" -> ")}`,
      );
    }
    state.set(svc.name, "visiting");
    for (const dep of svc.dependsOn) {
      const target = byName.get(dep);
      // Unknown deps (e.g. the app service itself) are ignored: they are not
      // services we generate containers for.
      if (target) visit(target, [...trail, svc.name]);
    }
    state.set(svc.name, "done");
    sorted.push(svc);
  };

  for (const svc of services) visit(svc, []);
  return sorted;
}
