#!/bin/bash
set -euo pipefail

MY_HOME=$(eval echo ~$(whoami))
REPO_DIR="$MY_HOME/armada-sync"

echo "=== Armada Sync — $(hostname) — $(date) ==="

# ── Arquitectura Hub/Follower ──────────────────────────────────────
# kalimete = HUB (único que push) → fuentes de verdad de todos los
# agentes/skills/commands. Victoria = FOLLOWER (solo pull+deploy).
#
# Flujo HUB:   pull → collect(→repo) → push
# Flujo FOL:   pull → deploy(→local)
#
# collect: local → repo dir (overwrite + delete)
# deploy:  repo dir → local (overwrite + delete)
#
# collect/deploy destructivos eliminan "agentes zombies" (archivos
# que existen en una máquina pero ya no en la fuente de verdad).

IS_HUB=false
[ "$(hostname)" = "kalimete" ] && IS_HUB=true
echo "Host=$(hostname) hub=$IS_HUB"

# ═══════════════════════════════════════════════════════════════════
# PASO 1: PULL DE TODOS (traer cambios del remoto al repo dir)
# ═══════════════════════════════════════════════════════════════════
echo "[1/3] Pulling latest from GitHub..."
cd "$REPO_DIR"
git pull origin master 2>&1 || echo "Warning: pull failed, continuing..."

# ═══════════════════════════════════════════════════════════════════
# PASO 2/3: SEGÚN ROL
# ═══════════════════════════════════════════════════════════════════
if $IS_HUB; then
    # ── HUB: COLLECT → PUSH ────────────────────────────────────────
    echo "[2/3] Collecting local → remote (hub)..."

    for d in agent skill command; do
        mkdir -p "$REPO_DIR/$d"
        local_dir="$MY_HOME/.config/opencode/$d"

        # a) Overwrite: copiar todo lo que existe en config local al repo dir
        for f in "$local_dir"/*.md 2>/dev/null; do
            [ -f "$f" ] || continue
            cp -f "$f" "$REPO_DIR/$d/$(basename "$f")"
            echo "  → repo/$d/$(basename "$f") (overwrite)"
        done
        for d2 in "$local_dir"/*/ 2>/dev/null; do
            [ -d "$d2" ] || continue
            nm=$(basename "$d2")
            rm -rf "$REPO_DIR/$d/$nm"
            mkdir -p "$REPO_DIR/$d/$nm"
            cp -r "$d2"* "$REPO_DIR/$d/$nm/" 2>/dev/null || true
            echo "  → repo/$d/$nm/ (overwrite)"
        done

        # b) Delete: borrar del repo dir lo que ya no existe en config local
        for f in "$REPO_DIR/$d"/*.md 2>/dev/null; do
            [ -f "$f" ] || continue
            local_name=$(basename "$f")
            [ ! -f "$local_dir/$local_name" ] && rm -f "$f" && echo "  ✗ repo/$d/$local_name (deleted — removed locally)"
        done
        for d2 in "$REPO_DIR/$d"/*/ 2>/dev/null; do
            [ -d "$d2" ] || continue
            local_name=$(basename "$d2")
            [ ! -d "$local_dir/$local_name" ] && rm -rf "$d2" && echo "  ✗ repo/$d/$local_name/ (deleted — removed locally)"
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
    echo "[2/3] Deploying from remote → local (follower)..."

    for d in agent skill command; do
        mkdir -p "$MY_HOME/.config/opencode/$d"
        local_dir="$MY_HOME/.config/opencode/$d"

        # a) Delete: borrar de config local lo que ya no existe en repo dir
        for f in "$local_dir"/*.md 2>/dev/null; do
            [ -f "$f" ] || continue
            local_name=$(basename "$f")
            if [ ! -f "$REPO_DIR/$d/$local_name" ]; then
                rm -f "$f"
                echo "  ✗ $d/$local_name (removed — not in remote)"
            fi
        done
        for d2 in "$local_dir"/*/ 2>/dev/null; do
            [ -d "$d2" ] || continue
            local_name=$(basename "$d2")
            if [ ! -d "$REPO_DIR/$d/$local_name" ]; then
                rm -rf "$d2"
                echo "  ✗ $d/$local_name/ (removed — not in remote)"
            fi
        done

        # b) Overwrite: copiar del repo dir a config local
        for f in "$REPO_DIR/$d"/*.md 2>/dev/null; do
            [ -f "$f" ] || continue
            name=$(basename "$f")
            [ "$f" = "$local_dir/$name" ] && continue
            cp -f "$f" "$local_dir/$name"
            echo "  → $d/$name"
        done
        for d2 in "$REPO_DIR/$d"/*/ 2>/dev/null; do
            [ -d "$d2" ] || continue
            name=$(basename "$d2")
            dest="$local_dir/$name"
            rm -rf "$dest" 2>/dev/null || true
            mkdir -p "$dest"
            cp -r "$d2"* "$dest/" 2>/dev/null || true
            echo "  → $d/$name/"
        done
    done

    echo "[3/3] Done (follower — read-only sync)"
fi

echo "=== Sync complete ==="
