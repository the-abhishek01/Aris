#!/usr/bin/env bash
# ==============================================================================
# Aris Gateway (9Router) - Obsidian Hyper-Router One-Line Installer
# Supports: macOS, Linux (Debian, Ubuntu, Arch, Fedora, Alpine, etc.), WSL
# GitHub: https://github.com/the-abhishek01/9router
# ==============================================================================

set -e

# ANSI Color Codes
BOLD="\033[1m"
GREEN="\033[38;2;16;185;129m"
CYAN="\033[38;2;6;182;212m"
YELLOW="\033[38;2;245;158;11m"
RED="\033[38;2;239;68;68m"
DIM="\033[2m"
RESET="\033[0m"

# Default Configuration
REPO_URL="https://github.com/the-abhishek01/9router.git"
DEFAULT_INSTALL_DIR="$HOME/.9router/gateway"
INSTALL_DIR="${ARIS_DIR:-$DEFAULT_INSTALL_DIR}"
PORT="${PORT:-20128}"
HOST="${HOST:-0.0.0.0}"
START_SERVER=1
BIN_DIR="$HOME/.local/bin"

# Parse CLI arguments
for arg in "$@"; do
  case "$arg" in
    --no-start|-n)
      START_SERVER=0
      ;;
    --port=*|-p=*)
      PORT="${arg#*=}"
      ;;
    --dir=*|-d=*)
      INSTALL_DIR="${arg#*=}"
      ;;
    --help|-h)
      echo -e "${BOLD}Aris Gateway (9Router) Installer${RESET}"
      echo ""
      echo "Usage: curl -fsSL https://raw.githubusercontent.com/the-abhishek01/9router/master/install.sh | bash [options]"
      echo ""
      echo "Options:"
      echo "  --no-start, -n         Install only, do not launch server"
      echo "  --port=<port>, -p=...  Specify gateway port (default: 20128)"
      echo "  --dir=<path>, -d=...   Specify installation directory (default: ~/.9router/gateway)"
      echo "  --help, -h             Show this help message"
      exit 0
      ;;
  esac
done

echo -e ""
echo -e "${GREEN}${BOLD}"
echo -e "   ___         _        ____       __eway "
echo -e "  / _ |  ____ (_)___   / __/____ _/ /____ "
echo -e " / __ | / __// // -_) _\\ \\ / _ \`/ __/ -_) "
echo -e "/_/ |_|/_/  /_/ \\__/ /___/ \\_,_/\\__/\\__/ "
echo -e "${RESET}"
echo -e "${BOLD}Aris Gateway (9Router)${RESET} — Obsidian Hyper-Router & Web2API Gateway"
echo -e "${DIM}Repository: https://github.com/the-abhishek01/9router${RESET}"
echo -e "------------------------------------------------------------------"

# Detect OS
OS_NAME="$(uname -s)"
case "$OS_NAME" in
  Darwin*) OS_TYPE="macOS" ;;
  Linux*)  OS_TYPE="Linux" ;;
  *)       OS_TYPE="Unknown ($OS_NAME)" ;;
esac

echo -e "${CYAN}→${RESET} Detected Platform: ${BOLD}${OS_TYPE} ($(uname -m))${RESET}"

# Check for Git
if ! command -v git >/dev/null 2>&1; then
  echo -e "${RED}✗ Error: 'git' is required but not installed.${RESET}"
  echo "Please install git for your operating system:"
  if [ "$OS_TYPE" = "macOS" ]; then
    echo "  xcode-select --install  (or: brew install git)"
  else
    echo "  sudo apt update && sudo apt install -y git  # Debian / Ubuntu"
    echo "  sudo dnf install -y git                     # Fedora / RHEL"
    echo "  sudo pacman -S git                          # Arch Linux"
  fi
  exit 1
fi

# Check for Node.js
if ! command -v node >/dev/null 2>&1; then
  echo -e "${RED}✗ Error: 'node' (Node.js 18+) is required but not installed.${RESET}"
  echo "Please install Node.js (version 18 or higher):"
  if [ "$OS_TYPE" = "macOS" ]; then
    echo "  brew install node"
  else
    echo "  curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -"
    echo "  sudo apt install -y nodejs"
  fi
  echo "Or via nvm:"
  echo "  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash"
  echo "  nvm install 20"
  exit 1
fi

# Check Node version >= 18
NODE_VER=$(node -v | sed 's/v//')
NODE_MAJOR=$(echo "$NODE_VER" | cut -d. -f1)
if [ "$NODE_MAJOR" -lt 18 ]; then
  echo -e "${RED}✗ Error: Node.js version 18+ is required. Found: v${NODE_VER}${RESET}"
  echo "Please upgrade your Node.js runtime to version 18 or 20 LTS."
  exit 1
fi
echo -e "${GREEN}✓${RESET} Node.js Runtime: ${BOLD}v${NODE_VER}${RESET}"

# Check for npm
if ! command -v npm >/dev/null 2>&1; then
  echo -e "${RED}✗ Error: 'npm' is required but not found.${RESET}"
  exit 1
fi
echo -e "${GREEN}✓${RESET} Package Manager: ${BOLD}npm v$(npm -v)${RESET}"

# Check if current directory is already an Aris clone
if [ -f "package.json" ] && grep -q '"name": "aris-app"' package.json 2>/dev/null; then
  INSTALL_DIR="$(pwd)"
  echo -e "${CYAN}→${RESET} Running inside existing 9Router repository: ${BOLD}${INSTALL_DIR}${RESET}"
else
  # Clone or Update repository
  if [ -d "$INSTALL_DIR/.git" ]; then
    echo -e "${CYAN}→${RESET} Updating existing installation at: ${BOLD}${INSTALL_DIR}${RESET}"
    cd "$INSTALL_DIR"
    git fetch --depth=1 origin master >/dev/null 2>&1 || git fetch origin master >/dev/null 2>&1 || true
    git reset --hard origin/master >/dev/null 2>&1 || git pull origin master >/dev/null 2>&1 || true
  else
    echo -e "${CYAN}→${RESET} Cloning 9Router into: ${BOLD}${INSTALL_DIR}${RESET}"
    mkdir -p "$(dirname "$INSTALL_DIR")"
    git clone --depth=1 "$REPO_URL" "$INSTALL_DIR"
    cd "$INSTALL_DIR"
  fi
fi

# Install dependencies
echo -e "${CYAN}→${RESET} Installing project dependencies..."
npm install --no-audit --no-fund --loglevel=error

# Ensure CLI bundle exists
if [ ! -f "cli/app/custom-server.js" ] && [ ! -f "cli/app/server.js" ]; then
  echo -e "${CYAN}→${RESET} Compiling standalone Aris CLI distribution (this takes ~15s)..."
  node cli/scripts/build-cli.js
fi

# Ensure Next.js standalone runtime compatibility
node -e "try { require('./cli/hooks/nextRuntime').ensureNextRuntime(); } catch {}" 2>/dev/null || true

# Set up global CLI commands: aris and 9router
mkdir -p "$BIN_DIR"

cat << 'EOF' > "$BIN_DIR/aris"
#!/usr/bin/env bash
ARIS_ROOT="$(dirname "$(dirname "$0")")/.9router/gateway"
if [ ! -d "$ARIS_ROOT" ]; then
  # Fallback search
  if [ -f "$HOME/.9router/gateway/cli/cli.js" ]; then
    ARIS_ROOT="$HOME/.9router/gateway"
  fi
fi
if [ -f "$ARIS_ROOT/cli/cli.js" ]; then
  exec node "$ARIS_ROOT/cli/cli.js" "$@"
else
  exec node "$HOME/.9router/gateway/cli/cli.js" "$@"
fi
EOF

# Substitute actual install path into launcher
sed -i.bak "s|\$HOME/\.9router/gateway|$INSTALL_DIR|g" "$BIN_DIR/aris" 2>/dev/null || sed -i "" "s|\$HOME/\.9router/gateway|$INSTALL_DIR|g" "$BIN_DIR/aris" 2>/dev/null || true
rm -f "$BIN_DIR/aris.bak"
chmod +x "$BIN_DIR/aris"

# Create 9router alias
ln -sf "$BIN_DIR/aris" "$BIN_DIR/9router"

echo -e "${GREEN}✓${RESET} Installed CLI shortcuts: ${BOLD}$BIN_DIR/aris${RESET} and ${BOLD}$BIN_DIR/9router${RESET}"

# Configure PATH in user shells if needed
SHELL_CONFIGS=("$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.profile")
PATH_LINE='export PATH="$HOME/.local/bin:$PATH"'
PATH_FOUND=0

case ":$PATH:" in
  *":$BIN_DIR:"*) PATH_FOUND=1 ;;
esac

if [ "$PATH_FOUND" -eq 0 ]; then
  for conf in "${SHELL_CONFIGS[@]}"; do
    if [ -f "$conf" ]; then
      if ! grep -q '\.local/bin' "$conf" 2>/dev/null; then
        echo -e "\n# Added by Aris Gateway installer\n$PATH_LINE" >> "$conf"
      fi
    fi
  done
  export PATH="$BIN_DIR:$PATH"
fi

echo ""
echo -e "${GREEN}${BOLD}==================================================================${RESET}"
echo -e "${GREEN}${BOLD}   ⚡ Aris Gateway (9Router) is Ready!${RESET}"
echo -e "${GREEN}${BOLD}==================================================================${RESET}"
echo ""
echo -e "  ${BOLD}Dashboard URL:${RESET}      ${CYAN}http://localhost:${PORT}/dashboard${RESET}"
echo -e "  ${BOLD}OpenAI Endpoint:${RESET}    ${CYAN}http://localhost:${PORT}/v1${RESET}"
echo -e "  ${BOLD}Installed To:${RESET}       ${DIM}${INSTALL_DIR}${RESET}"
echo -e "  ${BOLD}Global Command:${RESET}     ${GREEN}aris${RESET} ${DIM}or${RESET} ${GREEN}9router${RESET}"
echo ""

if [ "$START_SERVER" -eq 1 ]; then
  # Check if port is already running
  if curl -s "http://127.0.0.1:${PORT}/api/health" >/dev/null 2>&1; then
    echo -e "${YELLOW}ℹ Aris Gateway is already actively running on port ${PORT}!${RESET}"
    echo -e "Opening dashboard at: ${CYAN}http://localhost:${PORT}/dashboard${RESET}"
  else
    echo -e "${CYAN}→${RESET} Launching Aris Gateway on port ${PORT}..."
    if [ -t 0 ]; then
      # Terminal is interactive - start CLI menu
      exec node "$INSTALL_DIR/cli/cli.js" --port "$PORT"
    else
      # Running in curl | bash pipe: launch in background with PID tracking
      PID_DIR="$HOME/.9router"
      mkdir -p "$PID_DIR"
      nohup env PORT="$PORT" HOSTNAME="$HOST" node "$INSTALL_DIR/cli/app/custom-server.js" > "$PID_DIR/server.log" 2>&1 &
      SERVER_PID=$!
      echo "$SERVER_PID" > "$PID_DIR/server.pid"
      
      # Wait up to 5s for health check
      READY=0
      for i in {1..20}; do
        if curl -s "http://127.0.0.1:${PORT}/api/health" | grep -q '"ok":true' 2>/dev/null; then
          READY=1
          break
        fi
        sleep 0.3
      done

      if [ "$READY" -eq 1 ]; then
        echo -e "${GREEN}✓ Gateway started in background (PID: ${SERVER_PID})!${RESET}"
      else
        echo -e "${YELLOW}ℹ Server initializing in background (PID: ${SERVER_PID}).${RESET}"
      fi
      echo -e "${BOLD}Logs available at:${RESET} ${DIM}$PID_DIR/server.log${RESET}"
      echo ""
      echo -e "Run ${GREEN}aris${RESET} anytime in your terminal to open the interactive manager."
    fi
  fi
fi

echo ""
