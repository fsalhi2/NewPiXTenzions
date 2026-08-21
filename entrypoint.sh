#!/bin/bash
set -e

# --- Configuration & Workspace Setup ---
WORKSPACE="/app"
AGENT_DIR="/root/.pi/agent"
mkdir -p "$AGENT_DIR"

echo "[Agent] Initializing workspace at $WORKSPACE..."

# 1. Repository Management (Clone / Checkout)
# The agent works inside a clone of the repo located in /app
if [ ! -d "$WORKSPACE/.git" ]; then
    if [ -n "$REPO_URL" ]; then
        echo "[Agent] Cloning repository from $REPO_URL into $WORKSPACE..."
        git clone "$REPO_URL" "$WORKSPACE"
    else
        echo "[Agent] Error: No git repository found and no REPO_URL provided. Cannot initialize workspace."
        exit 1
    fi
fi

cd "$WORKSPACE"

# 2. Handle Branching (Agent Isolation)
TARGET_REVISION=${TARGET_REVISION:-"main"}
echo "[Agent] Target revision: $TARGET_REVISION"

# Ensure we are on the target revision
# We do a fetch to make sure we know about the new branches/tags
git fetch origin --quiet
git checkout "$TARGET_REVISION" --quiet || { echo "[Agent] Failed to checkout $TARGET_REVISION"; exit 1; }

# 3. Hydration of secrets & settings
# Injecting secrets into auth.json
if [ -n "$PI_AUTH_JSON" ]; then
    echo "[Agent] Injecting authentication tokens..."
    echo "$PI_AUTH_JSON" > "$AGENT_DIR/auth.json"
    chmod 600 "$AGENT_DIR/auth.json"
else
    echo "[Agent] Building auth.json from individual environment variables..."
    node -e '
const fs = require("fs");
const path = require("path");
const auth = {};
const prefix = "PI_AUTH_";
Object.keys(process.env).forEach(envVar => {
  if (envVar.startsWith(prefix)) {
    let provider = envVar.slice(prefix.length).toLowerCase().replace(/_/g, "-");
    auth[provider] = { type: "api_key", key: process.env[envVar] };
  }
});
if (Object.keys(auth).length > 0) {
    const dir = "/root/.pi/agent";
    if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(path.join(dir, "auth.json"), JSON.stringify(auth, null, 2));
    console.log("[Agent] auth.json created successfully.");
}
'
fi

# Injecting models and settings
echo "[Agent] Configuring models and settings..."

# 1. Models
if [ -f "$WORKSPACE/src/models.json" ]; then
    echo "[Agent] Copying models.json from workspace..."
    cp "$WORKSPACE/src/models.json" "$AGENT_DIR/models.json"
fi
if [ -f "$WORKSPACE/src/models-store.json" ]; then
    echo "[Agent] Copying models-store.json from workspace..."
    cp "$WORKSPACE/src/models-store.json" "$AGENT_DIR/models-store.json"
fi

# 2. Settings - Workspace priority as requested
if [ -f "$WORKSPACE/src/settings.json" ]; then
    echo "[Agent] Copying settings.json from workspace..."
    cp "$WORKSPACE/src/settings.json" "$AGENT_DIR/settings.json"
elif [ -n "$PI_SETTINGS_JSON" ]; then
    echo "[Agent] Injecting settings from environment variable..."
    echo "$PI_SETTINGS_JSON" > "$AGENT_DIR/settings.json"
else
    echo "[Agent] No settings found in workspace or env. Generating baseline..."
    BASELINE_REV=$(git rev-parse HEAD~1 2>/dev/null || echo "unknown")
    node -e '
const fs = require("fs");
const path = require("path");
const agentDir = "/root/.pi/agent";
const baselineRev = process.env.BASELINE_REV || "unknown";
let settings = { baseline_revision: baselineRev };
const settingsPath = path.join(agentDir, "settings.json");
fs.writeFileSync(settingsPath, JSON.stringify(settings, null, 2));
console.log("[Agent] baseline settings.json created with revision: " + baselineRev);
'
fi

# Linking assets for the agent (prompts, bins, extensions)
if [ -d "$WORKSPACE/src/prompts" ]; then
    echo "[Agent] Copying prompts from workspace..."
    rm -rf "$AGENT_DIR/prompts" && cp -r "$WORKSPACE/src/prompts" "$AGENT_DIR/prompts"
fi

if [ -d "$WORKSPACE/src/bin" ]; then
    echo "[Agent] Copying bins from workspace..."
    rm -rf "$AGENT_DIR/bin" && cp -r "$WORKSPACE/src/bin" "$AGENT_DIR/bin"
fi

if [ -d "$WORKSPACE/src/extensions" ]; then
    echo "[Agent] Copying extensions from workspace..."
    rm -rf "$AGENT_DIR/extensions" && cp -r "$WORKSPACE/src/extensions" "$AGENT_DIR/extensions"
fi

if [ -f "$WORKSPACE/src/APPEND_SYSTEM.md" ]; then
    echo "[Agent] Copying APPEND_SYSTEM.md from workspace..."
    cp "$WORKSPACE/src/APPEND_SYSTEM.md" "$AGENT_DIR/APPEND_SYSTEM.md"
fi

if [ -d "$WORKSPACE/src/.pi" ]; then
    echo "[Agent] Copying .pi configuration from workspace..."
    cp -r "$WORKSPACE/src/.pi/." "$AGENT_DIR/"
fi

# Injecting tests into the root for easy access
if [ -d "$WORKSPACE/tests" ]; then
    echo "[Agent] Injecting tests to /tests..."
    cp -r "$WORKSPACE/tests" /tests
fi

# 4. Git Authentication (Token injection)
if [ -n "$PI_GIT_TOKEN" ]; then
    echo "[Agent] Configuring Git authentication via token..."
    # We use the token to inject the auth into the URL for non-interactive pushes
    CURRENT_REMOTE=$(git remote get-url origin 2>/dev/null || echo "")
    if [ -n "$CURRENT_REMOTE" ]; then
        # Replace https:// with https://<TOKEN>@
        NEW_REMOTE=$(echo "$CURRENT_REMOTE" | sed "s|https://|https://${PI_GIT_TOKEN}@|")
        git remote set-url origin "$NEW_REMOTE"
        echo "[Agent] Git remote updated."
    fi
fi

# 5. Extension dependencies installation
if [ -d "$WORKSPACE/src/extensions" ]; then
    echo "[Agent] Installing extension dependencies..."
    find "$WORKSPACE/src/extensions" -name "package.json" -not -path "*/node_modules/*" | while read -r pkg_path; do
        pkg_dir=$(dirname "$pkg_path")
        echo "[Agent] Installing dependencies in $pkg_dir..."
        (cd "$pkg_dir" && npm install --quiet)
    done
fi

# 6. Lancement de la commande
echo "[Agent] Starting command: $@"
exec "$@"
