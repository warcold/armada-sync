#!/bin/bash
set -euo pipefail

# nullglob: si no hay *.md, el for no se ejecuta (en vez de usar literal "*.md")
shopt -s nullglob

MY_HOME=$(eval echo ~$(whoami))
REPO_DIR="$MY_HOME/armada-sync"

echo "=== Armada Sync — $(hostname) — $(date) ==="

# ── Arquitectura Hub/Follower ──────────────────────────────────────
# kalimete = HUB (único push) → fuente de verdad
# Victoria = FOLLOWER (solo pull+deploy, read-only)
#
# collect: local opencode → repo dir (overwrite + delete)
# deploy:  repo dir → local opencode (overwrite + delete)
# Ambos DESTRUCTIVOS (eliminan "agentes zombies")
#
# Convención:
#   Repo (armada-sync/):  agents/, skills/, commands/  (plural)
#   Config (opencode/):   agent/, skills/, command/    (skills PLURAL — opencode
#                         lee ~/.config/opencode/skills/; el singular skill/
#                         fue eliminado 2026-08-14)

IS_HUB=false
[ "$(hostname)" = "kalimete" ] && IS_HUB=true
echo "Host=$(hostname) hub=$IS_HUB"

# ═══════════════════════════════════════════════════════════════════
# PASO 1: PULL (todos reciben cambios del remoto)
# ═══════════════════════════════════════════════════════════════════
echo "[1/3] Pulling latest from GitHub..."
cd "$REPO_DIR"
git config pull.rebase true 2>/dev/null || true
git pull origin master 2>&1 || echo "Warning: pull failed, continuing..."

if $IS_HUB; then
    # ── HUB: COLLECT → PUSH ────────────────────────────────────────
    echo "[2/3] Collecting local → repo dir (hub)..."

    for dir_pair in "agent:agents" "skills:skills" "command:commands"; do
        local_part="${dir_pair%%:*}"
        repo_part="${dir_pair##*:}"

        mkdir -p "$REPO_DIR/$repo_part"
        local_dir="$MY_HOME/.config/opencode/$local_part"

        # a) Overwrite: config → repo dir
        for f in "$local_dir"/*.md; do
            cp -f "$f" "$REPO_DIR/$repo_part/$(basename "$f")"
            echo "  → repo/$repo_part/$(basename "$f") (overwrite)"
        done
        for d2 in "$local_dir"/*/; do
            nm=$(basename "$d2")
            rm -rf "$REPO_DIR/$repo_part/$nm"
            mkdir -p "$REPO_DIR/$repo_part/$nm"
            cp -r "$d2"* "$REPO_DIR/$repo_part/$nm/" 2>/dev/null || true
            echo "  → repo/$repo_part/$nm/ (overwrite)"
        done

        # b) Delete: lo que ya no existe en config → borrar del repo dir
        for f in "$REPO_DIR/$repo_part"/*.md; do
            local_name=$(basename "$f")
            [ ! -f "$local_dir/$local_name" ] && rm -f "$f" && echo "  ✗ repo/$repo_part/$local_name (deleted)"
        done
        for d2 in "$REPO_DIR/$repo_part"/*/; do
            local_name=$(basename "$d2")
            [ ! -d "$local_dir/$local_name" ] && rm -rf "$d2" && echo "  ✗ repo/$repo_part/$local_name/ (deleted)"
        done
    done

    # Commit + push si hay cambios
    echo "[3/3] Pushing to GitHub (hub)..."
    git add -A
    if git diff --cached --quiet; then
        echo "No local changes."
    else
        git commit -m "hub: sync $(date +%H:%M)"
        git push origin master 2>&1 && echo "Pushed OK." || echo "Push FAILED!"
    fi
else
    # ── FOLLOWER: DEPLOY (destructivo) ─────────────────────────────
    echo "[2/3] Deploying from repo dir → local (follower)..."

    for dir_pair in "agent:agents" "skills:skills" "command:commands"; do
        local_part="${dir_pair%%:*}"
        repo_part="${dir_pair##*:}"

        mkdir -p "$MY_HOME/.config/opencode/$local_part"
        local_dir="$MY_HOME/.config/opencode/$local_part"

        # a) Delete: lo que no está en repo dir → borrar de config
        for f in "$local_dir"/*.md; do
            local_name=$(basename "$f")
            [ ! -f "$REPO_DIR/$repo_part/$local_name" ] && rm -f "$f" && echo "  ✗ $local_part/$local_name (removed)"
        done
        for d2 in "$local_dir"/*/; do
            local_name=$(basename "$d2")
            [ ! -d "$REPO_DIR/$repo_part/$local_name" ] && rm -rf "$d2" && echo "  ✗ $local_part/$local_name/ (removed)"
        done

        # b) Overwrite: repo dir → config
        for f in "$REPO_DIR/$repo_part"/*.md; do
            name=$(basename "$f")
            dest="$local_dir/$name"
            [ "$f" = "$dest" ] && continue
            cp -f "$f" "$dest"
            echo "  → $local_part/$name"
        done
        for d2 in "$REPO_DIR/$repo_part"/*/; do
            name=$(basename "$d2")
            dest="$local_dir/$name"
            rm -rf "$dest" 2>/dev/null || true
            mkdir -p "$dest"
            cp -r "$d2"* "$dest/" 2>/dev/null || true
            echo "  → $local_part/$name/"
        done
    done

    echo "[3/3] Done (follower — read-only sync)"
fi

echo "=== Sync complete ==="
