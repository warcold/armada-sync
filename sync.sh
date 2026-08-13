#!/bin/bash
set -euo pipefail

MY_HOME=$(eval echo ~$(whoami))
REPO_DIR="$MY_HOME/armada-sync"

echo "=== Armada Sync — $(date) ==="
HOSTNAME_LOCAL=$(hostname)

# ── Modo unidireccional ──────────────────────────────────────
# Solo kalimete (hub) puede push al repo. Los demás (victoria,
# rootsource, jonas) solo hacen pull+deploy — nunca collect ni push.
# Esto evita que agentes locales de victoria/otros contaminen
# el repositorio central (fuente única de verdad = kalimete).
IS_HUB=false
[ "$HOSTNAME_LOCAL" = "kalimete" ] && IS_HUB=true

echo "[0/4] Host=$HOSTNAME_LOCAL hub=$IS_HUB"

# 1. Pull latest from GitHub
echo "[1/4] Pulling latest from GitHub..."
cd "$REPO_DIR"
git pull origin master || echo "Warning: pull failed, continuing..."

# 2. Deploy to local opencode dirs (DESTRUCTIVO — borra archivos
#    que ya no existen en el repo para mantener consistencia)
echo "[2/4] Deploying to opencode dirs (destructive)..."

for dir in agents skills commands; do
    [ -d "$REPO_DIR/$dir" ] || continue

    for d in "$REPO_DIR/$dir"/*/; do
        [ -d "$d" ] || continue
        name=$(basename "$d")
        dest="$MY_HOME/.config/opencode/${dir}/${name}"
        # Destructivo: borrar lo que ya no está en el repo
        if [ -d "$dest" ]; then
            rm -rf "$dest"
        fi
        mkdir -p "$dest"
        cp -r "$d"* "$dest/" 2>/dev/null || true
        echo "  → ${dir}/${name}"
    done

    for f in "$REPO_DIR/$dir"/*.md; do
        [ -f "$f" ] || continue
        name=$(basename "$f")
        dest="$MY_HOME/.config/opencode/${dir}/${name}"
        # Destructivo: borrar archivos que ya no están en el repo
        if [ -f "$dest" ]; then
            current_md5=$(md5sum "$dest" | cut -d' ' -f1)
            repo_md5=$(md5sum "$f" | cut -d' ' -f1)
            [ "$current_md5" != "$repo_md5" ] && rm -f "$dest"
        fi
        cp "$f" "$dest" 2>/dev/null || echo "  → ${dir}/${name} (skip)"
    done
done

if $IS_HUB; then
    # 3. Collect local changes (solo kalimete puede cambiar agentes)
    echo "[3/4] Collecting local changes (hub only)..."
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

    # 4. Push to GitHub (solo kalimete)
    echo "[4/4] Pushing to GitHub (hub)..."
    git add -A
    if git diff --cached --quiet; then
        echo "No changes to push."
    else
        git commit -m "Sync $(date +%Y-%m-%d_%H:%M:%S) from $(hostname)"
        git push origin master
        echo "Pushed successfully."
    fi
else
    echo "[3/4] Skip collect+push (not hub — read-only sync)"
    # Solo loguear sin git add para evitar conflictos de cron.log
fi

echo "=== Sync complete ==="
