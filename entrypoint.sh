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
elif [ "$(ls -A $AGENT_DIR/auth.json 2>/dev/null || true)" != "" ]; then
    echo "[Agent] Using existing auth.json"
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
# We use symlinks for versioned files to ensure they are parameterized from the workspace
if [ -f "$WORKSPACE/src/models.json" ]; then
    echo "[Agent] Linking models.json from workspace..."
    ln -sf "$WORKSPACE/src/models.json" "$AGENT_DIR/models.json"
fi
if [ -f "$WORKSPACE/src/models-store.json" ]; then
    echo "[Agent] Linking models-store.json from workspace..."
    ln -sf "$WORKSPACE/src/models-store.json" "$AGENT_DIR/models-store.json"
fi

if [ -n "$PI_SETTINGS_JSON" ]; then
    echo "[Agent] Injecting settings from environment..."
    echo "$PI_SETTINGS_JSON" > "$AGENT_DIR/settings.json"
elif [ -f "$WORKSPACE/src/settings.json" ]; then
    echo "[Agent] Linking settings.json from workspace..."
    ln -sf "$WORKSPACE/src/settings.json" "$AGENT_DIR/settings.json"
else
    echo "[Agent] Generating baseline info..."
    BASELINE_REV=$(git rev-parse HEAD~1 2>/dev/null || echo "none")
    node -e '
const fs = require("fs");
const path = require("path");
const agentDir = "/root/.pi/agent";
const baselineRev = process.env.BASELINE_REV;
let settings = {};
const settingsPath = path.join(agentDir, "settings.json");
if (fs.existsSync(settingsPath)) {
    settings = JSON.parse(fs.readFileSync(settingsPath, "utf8"));
}
settings.baseline_revision = baselineRev;
fs.writeFileSync(settingsPath, JSON.stringify(settings, null, 2));
console.log("[Agent] settings.json enriched with baseline: " + baselineRev);
'
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
