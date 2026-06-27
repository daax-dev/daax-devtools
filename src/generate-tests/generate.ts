/**
 * High-level orchestration: turn resolved services into a set of output files.
 * Kept free of filesystem side effects so it is trivially unit-testable.
 */

import { generateGo } from "./generators/go.js";
import { generateTypeScript } from "./generators/typescript.js";
import type { ServiceDef } from "./services.js";

export type Lang = "go" | "ts" | "both";

export interface GenerateOptions {
  lang?: Lang;
  /** Output directory the relative file paths are resolved against. */
  outDir?: string;
  /** Go package name. */
  goPackage?: string;
  /** Base name for the TypeScript files. */
  baseName?: string;
}

export interface GeneratedFile {
  /** Path relative to `outDir`. */
  path: string;
  content: string;
  language: "go" | "typescript";
}

/** Produce the list of files that would be written for the given services. */
export function generate(
  services: ServiceDef[],
  options: GenerateOptions = {},
): GeneratedFile[] {
  const lang = options.lang ?? "both";
  const base = options.baseName ?? "testcontainers";
  const files: GeneratedFile[] = [];

  if (lang === "go" || lang === "both") {
    files.push({
      path: `${base}_setup_test.go`,
      content: generateGo(services, { packageName: options.goPackage }),
      language: "go",
    });
  }

  if (lang === "ts" || lang === "both") {
    const ts = generateTypeScript(services, { baseName: base });
    files.push(
      { path: `${base}.setup.ts`, content: ts.setup, language: "typescript" },
      { path: `${base}.test.ts`, content: ts.test, language: "typescript" },
    );
  }

  return files;
}
