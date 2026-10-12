const http = require("http");
const path = require("path");
const fs = require("fs");
const crypto = require("crypto");
const { pathToFileURL } = require("url");

const origCreate = http.createServer.bind(http);

// Per-process secret proving x-9r-real-ip was stamped below rather than sent by the client.
// A bare `next start` / `next dev` never loads this file, so it cannot produce a matching
// header even though the env var is inherited by child processes. Named like x-9r-cli-token
// so the request-detail header sanitizer redacts it too.
const PEER_TOKEN = crypto.randomBytes(24).toString("hex");
process.env.NINEROUTER_PEER_TOKEN = PEER_TOKEN;

let backgroundRefreshStarted = false;

function startBackgroundTokenRefreshFromCustomServer() {
  if (backgroundRefreshStarted) return;
  backgroundRefreshStarted = true;
  // Prefer source path (repo / standalone that still has src). Fail-open if missing
  // — initializeApp also starts the same scheduler when the Next app boots.
  const modPath = path.join(__dirname, "src", "sse", "services", "backgroundTokenRefresh.js");
  import(pathToFileURL(modPath).href)
    .then((m) => {
      try {
        m.startBackgroundTokenRefresh();
      } catch (e) {
        console.error("[BackgroundTokenRefresh] start failed:", e && e.message ? e.message : e);
      }
      const stop = () => {
        try {
          m.stopBackgroundTokenRefresh();
        } catch {
          /* ignore */
        }
      };
      process.once("SIGINT", stop);
      process.once("SIGTERM", stop);
    })
    .catch((e) => {
      // Expected in published CLI standalone (src/ not on disk). App bootstrap covers it.
      if (process.env.DEBUG_BACKGROUND_TOKEN_REFRESH) {
        console.error("[BackgroundTokenRefresh] import failed:", e && e.message ? e.message : e);
      }
    });
}

// Configure global high-performance undici Agent with connection pooling & TCP_NODELAY
try {
  const { Agent, setGlobalDispatcher } = require("undici");
  const globalAgent = new Agent({
    keepAliveTimeout: 60_000,
    keepAliveMaxTimeout: 180_000,
    connections: 128,
    pipelining: 1,
    connect: {
      noDelay: true,
      keepAlive: true,
      keepAliveInitialDelay: 1000,
    },
  });
  setGlobalDispatcher(globalAgent);
} catch {
  /* undici optional fallback */
}

// Wrap Next standalone HTTP server: derive client IP from the TCP socket
// (unspoofable) and strip client-supplied forwarding headers so downstream
// rate-limiting keys on the real peer address instead of attacker-controlled XFF.
http.createServer = (...args) => {
  const handler = args.find((a) => typeof a === "function");
  const rest = args.filter((a) => typeof a !== "function");
  if (!handler) return origCreate(...args);
  const wrapped = (req, res) => {
    // Immediate TCP_NODELAY for sub-millisecond SSE token flushing
    if (req.socket && typeof req.socket.setNoDelay === "function") {
      req.socket.setNoDelay(true);
    }
    const socketIp = req.socket && req.socket.remoteAddress ? req.socket.remoteAddress : "";
    const xff = req.headers["x-forwarded-for"];
    const xRealIp = req.headers["x-real-ip"];
    const viaProxy = !!(xff || xRealIp);
    const isLoopbackProxy = socketIp === "127.0.0.1" || socketIp === "::1" || socketIp === "::ffff:127.0.0.1";
    // Trust forwarding headers only when the TCP peer is a local reverse proxy.
    // Direct/public sockets remain keyed by the unspoofable peer address.
    const proxyIp = xRealIp || (xff ? String(xff).split(",")[0].trim() : "");
    const ip = isLoopbackProxy && proxyIp ? proxyIp : socketIp;
    delete req.headers["x-9r-real-ip"];
    delete req.headers["x-forwarded-for"];
    delete req.headers["x-9r-via-proxy"];
    delete req.headers["x-9r-peer-token"];
    req.headers["x-9r-real-ip"] = ip;
    req.headers["x-9r-peer-token"] = PEER_TOKEN;
    if (viaProxy) req.headers["x-9r-via-proxy"] = "1";
    return handler(req, res);
  };
  const server = origCreate(...rest, wrapped);
  server.keepAliveTimeout = 65000;
  server.headersTimeout = 66000;
  server.requestTimeout = 0; // Don't terminate long LLM generations
  server.once("listening", () => {
    startBackgroundTokenRefreshFromCustomServer();
  });
  const origEmit = server.emit;
  // JBR 25 sends h2c upgrades that the HTTP/1.1 server would otherwise close.
  server.emit = function (event, ...eventArgs) {
    const [req, socket, head] = eventArgs;
    if (event !== "upgrade" || String(req.headers.upgrade || "").toLowerCase() !== "h2c") {
      return origEmit.call(this, event, ...eventArgs);
    }

    const contentLength = Number(req.headers["content-length"] || 0);
    if (!Number.isSafeInteger(contentLength) || contentLength < 0) {
      socket.destroy();
      return true;
    }
    const chunks = [head];
    let received = head.length;
    const serve = () => {
      // Replay the upgraded request through the existing HTTP/1.1 handler.
      const replay = new http.IncomingMessage(socket);
      Object.assign(replay, { method: req.method, url: req.url, headers: req.headers, complete: true });
      if (received) replay.push(Buffer.concat(chunks, received).subarray(0, contentLength));
      replay.push(null);
      const res = new http.ServerResponse(replay);
      res.shouldKeepAlive = false;
      res.assignSocket(socket);
      res.once("finish", () => socket.end());
      Promise.resolve().then(() => wrapped(replay, res)).catch((error) => {
        console.error("Failed to downgrade h2c request", error);
        socket.destroy();
      });
    };
    if (received >= contentLength) serve();
    else {
      socket.on("data", function readBody(chunk) {
        chunks.push(chunk);
        received += chunk.length;
        if (received < contentLength) return;
        socket.off("data", readBody);
        serve();
      });
      socket.resume();
    }
    delete req.headers.upgrade;
    delete req.headers["http2-settings"];
    req.headers.connection = "close";
    return true;
  };
  return server;
};

// Self-heal Next.js 16 standalone bug: config-schema.js imports SUPPORTED_TEST_RUNNERS_LIST
// from ../cli/next-test. In Next.js >=16.3.6 / 16.4+, next-test.js requires
// ../lib/warn-missing-react-dependencies and other dev tools that are excluded from
// standalone output traces. If missing or broken, patch them before server.js boots.
function ensureNextStandaloneCompatibility() {
  try {
    const nextDistDirs = [
      path.join(__dirname, "node_modules", "next", "dist"),
      path.join(__dirname, ".next", "standalone", "node_modules", "next", "dist"),
      path.join(__dirname, ".next-cli-build", "standalone", "node_modules", "next", "dist"),
    ];

    for (const nextDistDir of nextDistDirs) {
      if (!fs.existsSync(nextDistDir)) continue;

      const nextLibDir = path.join(nextDistDir, "lib");
      const warnDepPath = path.join(nextLibDir, "warn-missing-react-dependencies.js");
      if (!fs.existsSync(warnDepPath)) {
        if (!fs.existsSync(nextLibDir)) fs.mkdirSync(nextLibDir, { recursive: true });
        fs.writeFileSync(
          warnDepPath,
          `"use strict";\nObject.defineProperty(exports, "__esModule", { value: true });\nexports.warnMissingReactDependencies = function () {};\n`,
          "utf8"
        );
      }

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
        if (!fs.existsSync(nextCliDir)) fs.mkdirSync(nextCliDir, { recursive: true });
        fs.writeFileSync(
          nextTestPath,
          `"use strict";\nObject.defineProperty(exports, "__esModule", { value: true });\nexports.SUPPORTED_TEST_RUNNERS_LIST = ["playwright"];\nexports.nextTest = async function () {};\n`,
          "utf8"
        );
      }
    }
  } catch {
    /* best effort */
  }
}

if (require.main === module) {
  ensureNextStandaloneCompatibility();
  const standalone = path.join(__dirname, "server.js");
  if (fs.existsSync(standalone)) {
    require(standalone);
  } else {
    // Repo checkout has no standalone build next to us. `next start` builds its HTTP
    // server in-process, so the wrapper above still sanitizes every request.
    const nextBin = require.resolve("next/dist/bin/next");
    process.argv = [process.argv[0], nextBin, "start", ...process.argv.slice(2)];
    require(nextBin);
  }
}
