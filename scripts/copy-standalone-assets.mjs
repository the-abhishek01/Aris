import { cpSync, existsSync, writeFileSync, mkdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

export function copyStandaloneAssets({ projectRoot = process.cwd(), distDir = process.env.NEXT_DIST_DIR || ".next" } = {}) {
  if (process.env.NEXT_TRACING_ROOT_MODE === "workspace") {
    console.log("[standalone-assets] Skipping workspace-traced CLI build; CLI packaging handles assets");
    return;
  }

  const buildDir = resolve(projectRoot, distDir);
  const standaloneDir = resolve(buildDir, "standalone");

  if (!existsSync(standaloneDir)) {
    console.log(`[standalone-assets] No standalone build found at ${standaloneDir}`);
    return;
  }

  const staticSource = resolve(buildDir, "static");
  const staticDestination = resolve(standaloneDir, distDir, "static");
  if (existsSync(staticSource)) {
    cpSync(staticSource, staticDestination, { recursive: true, force: true });
    console.log(`[standalone-assets] Copied static assets to ${staticDestination}`);
  }

  const publicSource = resolve(projectRoot, "public");
  const publicDestination = resolve(standaloneDir, "public");
  if (existsSync(publicSource)) {
    cpSync(publicSource, publicDestination, { recursive: true, force: true });
    console.log(`[standalone-assets] Copied public assets to ${publicDestination}`);
  }

  // Without it beside server.js the standalone build serves requests unsanitized.
  const serverWrapperSource = resolve(projectRoot, "custom-server.js");
  const serverWrapperDestination = resolve(standaloneDir, "custom-server.js");
  if (existsSync(serverWrapperSource)) {
    cpSync(serverWrapperSource, serverWrapperDestination, { force: true });
    console.log(`[standalone-assets] Copied custom-server.js to ${serverWrapperDestination}`);
  }

  // Ensure Next.js standalone compatibility (stubs next-test and warn-missing-react-dependencies)
  const nextDistDir = resolve(standaloneDir, "node_modules", "next", "dist");
  if (existsSync(nextDistDir)) {
    const nextCliDir = resolve(nextDistDir, "cli");
    const nextLibDir = resolve(nextDistDir, "lib");
    const rootNextCli = resolve(projectRoot, "node_modules", "next", "dist", "cli");
    if (!existsSync(nextCliDir) && existsSync(rootNextCli)) {
      cpSync(rootNextCli, nextCliDir, { recursive: true });
    }
    if (!existsSync(nextCliDir)) mkdirSync(nextCliDir, { recursive: true });
    writeFileSync(resolve(nextCliDir, "next-test.js"), `"use strict";\nObject.defineProperty(exports, "__esModule", { value: true });\nexports.SUPPORTED_TEST_RUNNERS_LIST = ["playwright"];\nexports.nextTest = async function () {};\n`, "utf8");
    if (!existsSync(nextLibDir)) mkdirSync(nextLibDir, { recursive: true });
    const warnDep = resolve(nextLibDir, "warn-missing-react-dependencies.js");
    if (!existsSync(warnDep)) {
      writeFileSync(warnDep, `"use strict";\nObject.defineProperty(exports, "__esModule", { value: true });\nexports.warnMissingReactDependencies = function () {};\n`, "utf8");
    }
    console.log(`[standalone-assets] Applied Next.js standalone compatibility patches`);
  }
}

if (process.argv[1] && resolve(process.argv[1]) === resolve(dirname(fileURLToPath(import.meta.url)), "copy-standalone-assets.mjs")) {
  copyStandaloneAssets();
}
