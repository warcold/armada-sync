#!/bin/bash
set -euo pipefail

MY_HOME=$(eval echo ~$(whoami))
REPO_DIR="$MY_HOME/armada-sync"

echo "=== Armada Sync — $(date) ==="

# 1. Pull latest from GitHub
echo "[1/4] Pulling latest from GitHub..."
cd "$REPO_DIR"
git pull origin master || echo "Warning: pull failed, continuing..."

# 2. Deploy to local opencode dirs
echo "[2/4] Deploying to opencode dirs..."

if [ -d "$REPO_DIR/agents" ]; then
    for f in "$REPO_DIR/agents"/*.md; do
        [ -f "$f" ] || continue
        name=$(basename "$f")
        dest="$MY_HOME/.config/opencode/agent/$name"
        [ -d "$MY_HOME/.config/opencode/agent" ] || mkdir -p "$MY_HOME/.config/opencode/agent"
        cp "$f" "$dest"
        echo "  → agent/$name"
    done
fi

if [ -d "$REPO_DIR/skills" ]; then
    for d in "$REPO_DIR/skills"/*/; do
        [ -d "$d" ] || continue
        name=$(basename "$d")
        dest="$MY_HOME/.config/opencode/skill/$name"
        mkdir -p "$dest"
        cp -r "$d"* "$dest/" 2>/dev/null || true
        echo "  → skill/$name"
    done
fi

if [ -d "$REPO_DIR/commands" ]; then
    for f in "$REPO_DIR/commands"/*.md; do
        [ -f "$f" ] || continue
        name=$(basename "$f")
        dest="$MY_HOME/.config/opencode/command/$name"
        [ -d "$MY_HOME/.config/opencode/command" ] || mkdir -p "$MY_HOME/.config/opencode/command"
        cp "$f" "$dest"
        echo "  → command/$name"
    done
fi

# 3. Collect local changes
echo "[3/4] Collecting local changes..."
cd "$REPO_DIR"

mkdir -p "$REPO_DIR/agents"
for f in "$MY_HOME/.config/opencode/agent"/*.md; do
    [ -f "$f" ] || continue
    name=$(basename "$f")
    cp -f "$f" "$REPO_DIR/agents/$name"
done

mkdir -p "$REPO_DIR/skills"
for d in "$MY_HOME/.config/opencode/skill"/*/; do
    [ -d "$d" ] || continue
    name=$(basename "$d")
    rm -rf "$REPO_DIR/skills/$name"
    mkdir -p "$REPO_DIR/skills/$name"
    cp -r "$d"* "$REPO_DIR/skills/$name/" 2>/dev/null || true
done

mkdir -p "$REPO_DIR/commands"
for f in "$MY_HOME/.config/opencode/command"/*.md; do
    [ -f "$f" ] || continue
    name=$(basename "$f")
    cp -f "$f" "$REPO_DIR/commands/$name"
done

# 4. Push to GitHub
echo "[4/4] Pushing to GitHub..."
git add -A
if git diff --cached --quiet; then
    echo "No changes to push."
else
    git commit -m "Sync $(date +%Y-%m-%d_%H:%M:%S) from $(hostname)"
    git push origin master
    echo "Pushed successfully."
fi

echo "=== Sync complete ==="
