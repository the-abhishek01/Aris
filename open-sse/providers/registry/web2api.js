// Web2API Gateway Provider
// Connects to local or remote Web2API services (e.g. FastAPI / Node web2api instances,
// reverse web-to-API bridges, cookie session proxies, and api.web2api.com).
export default {
  id: "web2api",
  priority: 23,
  alias: "web2api",
  aliases: [
    "w2a",
    "web-to-api",
    "webapi",
  ],
  uiAlias: "w2a",
  display: {
    name: "Web2API Gateway",
    icon: "hub",
    color: "#10B981",
    textIcon: "W2A",
    website: "https://github.com/the-abhishek01/9router",
    notice: {
      text: "Universal Web2API reverse gateway bridge. Connects to standard Web2API proxy endpoints, local Python/Go Web2API daemons (e.g., http://localhost:8000/v1 or custom endpoints), or cloud Web2API instances. Supports zero-auth or session-cookie auth.",
      apiKeyUrl: "http://localhost:8000",
    },
  },
  category: "webCookie",
  authType: "apikey",
  authModes: [
    "apikey",
    "cookie",
  ],
  hasFree: true,
  passthroughModels: true,
  serviceKinds: ["llm", "image"],
  authHint: "Enter your Web2API API key, session bearer token, or Cookie header value (leave blank if your local Web2API daemon runs without auth)",
  transport: {
    baseUrl: "http://localhost:8000/v1/chat/completions",
    validateUrl: "http://localhost:8000/v1/models",
    format: "openai",
    forceStream: true,
  },
  models: [
    { id: "gpt-5-6-web", name: "GPT-5.6 Sol (Web2API)", contextLength: 200000 },
    { id: "gpt-5.6-luna-free", name: "GPT-5.6 Luna Free (Web2API)", contextLength: 128000 },
    { id: "claude-3-7-sonnet-web", name: "Claude 3.7 Sonnet (Web2API)", contextLength: 200000, supportsReasoning: true },
    { id: "gemini-2.5-pro-web", name: "Gemini 2.5 Pro (Web2API)", contextLength: 1000000 },
    { id: "gemini-2.5-flash-web", name: "Gemini 2.5 Flash (Web2API)", contextLength: 1000000 },
    { id: "deepseek-chat-web", name: "DeepSeek V3 (Web2API)", contextLength: 128000 },
    { id: "deepseek-reasoner-web", name: "DeepSeek R1 (Web2API)", contextLength: 128000, supportsReasoning: true },
    { id: "grok-3-web", name: "xAI Grok 3 (Web2API)", contextLength: 131072 },
    { id: "custom", name: "Custom Web2API Model", contextLength: 131072 },
  ],
};
