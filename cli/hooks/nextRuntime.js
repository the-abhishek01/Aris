const fs = require("fs");
const path = require("path");

/**
 * Next.js 16 standalone issue: config-schema.js imports SUPPORTED_TEST_RUNNERS_LIST
 * from ../cli/next-test. In Next.js >=16.3.6 / 16.4+, next-test.js top-level requires
 * ../lib/warn-missing-react-dependencies and other dev tools that are excluded from
 * standalone output traces. This causes the server to crash on startup with:
 * "Cannot find module '../lib/warn-missing-react-dependencies'".
 *
 * This hook safely stubs next-test.js and ensures warn-missing-react-dependencies.js
 * is present across all potential app directories before server launch.
 */
function ensureNextRuntime({ silent = false } = {}) {
  try {
    const candidates = [
      path.join(__dirname, "..", "app"),
      process.env.NINEROUTER_CLI_APP_DIR,
      path.join(process.cwd(), "cli", "app"),
      path.join(process.cwd(), "app"),
      path.join(process.cwd(), ".next", "standalone"),
      path.join(process.cwd(), ".next-cli-build", "standalone"),
    ].filter(Boolean);

    for (const baseDir of candidates) {
      // Find candidate next/dist directory directly or under node_modules
      const distCandidates = [
        path.join(baseDir, "node_modules", "next", "dist"),
        path.join(baseDir, "next", "dist"),
      ];

      for (const nextDistDir of distCandidates) {
        if (!fs.existsSync(nextDistDir)) continue;

        const nextLibDir = path.join(nextDistDir, "lib");
        const warnDepPath = path.join(nextLibDir, "warn-missing-react-dependencies.js");

        // 1. Ensure warn-missing-react-dependencies.js stub exists in next/dist/lib
        if (!fs.existsSync(warnDepPath)) {
          if (!fs.existsSync(nextLibDir)) {
            fs.mkdirSync(nextLibDir, { recursive: true });
          }
          fs.writeFileSync(
            warnDepPath,
            `"use strict";\nObject.defineProperty(exports, "__esModule", { value: true });\nexports.warnMissingReactDependencies = function () {};\n`,
            "utf8"
          );
        }

        // 2. Ensure next-test.js doesn't crash on untraced dev dependencies
        const nextCliDir = path.join(nextDistDir, "cli");
        const nextTestPath = path.join(nextCliDir, "next-test.js");
        let needsStub = !fs.existsSync(nextTestPath);

        if (!needsStub) {
          try {
            const content = fs.readFileSync(nextTestPath, "utf8");
            if (content.includes("warn-missing-react-dependencies") || content.includes("get-project-dir")) {
              needsStub = true;
            }
          } catch {
            needsStub = true;
          }
        }

        if (needsStub) {
          if (!fs.existsSync(nextCliDir)) {
            fs.mkdirSync(nextCliDir, { recursive: true });
          }
          fs.writeFileSync(
            nextTestPath,
            `"use strict";\nObject.defineProperty(exports, "__esModule", { value: true });\nexports.SUPPORTED_TEST_RUNNERS_LIST = ["playwright"];\nexports.nextTest = async function () {};\n`,
            "utf8"
          );
        }
      }
    }
  } catch (err) {
    if (!silent) {
      console.warn("⚠️  Failed to patch Next.js standalone runtime:", err.message);
    }
  }
}

if (require.main === module) {
  ensureNextRuntime({ silent: false });
}

module.exports = { ensureNextRuntime };
