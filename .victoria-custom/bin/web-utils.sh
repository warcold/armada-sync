#!/usr/bin/env bash
# web-utils.sh - Wrappers del sandbox para web-nav service (puerto 18820)
# Acceso: sandbox → host.docker.internal:18820

WEB_NAV_URL="http://host.docker.internal:18820"

web_navigate() {
    # Navegar una URL y retornar contenido/título
    local url="$1"
    local max_chars="${2:-2000}"
    
    local response
    response=$(curl -s -X POST "${WEB_NAV_URL}/navigate" \
        -H "Content-Type: application/json" \
        -d "{\"url\": \"${url}\"}" 2>/dev/null)
    
    echo "$response" | python3 -c "
import json, sys
try:
    d = json.loads(sys.stdin.read())
    if d.get('ok'):
        print(f'# Title: {d.get(\"title\", \"Unknown\")}')
        print(f'# URL: {d.get(\"url\", \"Unknown\")}')
        print()
        content = d.get('content_preview', '')[:${max_chars}]
        print(f'{content}')
        links = d.get('links', [])
        if links:
            print()
            print('## Links de interés:')
            for link in links[:10]:
                print(f'- [{link[\"text\"]}]({link[\"href\"]})')
    else:
        print(f'ERROR: {d.get(\"error\", \"Unknown error\")}')
except:
    print(f'ERROR: Failed to parse response')
" 2>/dev/null
}

web_scrape() {
    # Scraping completo de una página (título, descripciones, headings, contenido, links)
    local url="$1"
    local max_content="${2:-5000}"
    local max_links="${3:-30}"
    
    local response
    response=$(curl -s -X POST "${WEB_NAV_URL}/scrape" \
        -H "Content-Type: application/json" \
        -d "{\"url\": \"${url}\"}" 2>/dev/null)
    
    echo "$response" | python3 -c "
import json, sys
try:
    d = json.loads(sys.stdin.read())
    if d.get('ok'):
        print(f'# Página: {d.get(\"title\", \"No title\")}')
        print(f'# URL: {d.get(\"url\", \"Unknown\")}')
        desc = d.get('description', '')[:200]
        if desc:
            print(f'# Descripción: {desc}')
        print()
        # Headings
        headings = d.get('headings', [])
        if headings:
            print('## Estructura de la página:')
            for h in headings[:15]:
                print(f'- {h}')
            print()
        print(f'# Contenido principal:')
        print(d.get('content', '')[:${max_content}])
        # Links
        links = d.get('links_sample', [])
        if links:
            print()
            print(f'## Links ({len(links)} encontrados, mostrando {min(len(links), ${max_links})}):')
            for link in links[:${max_links}]:
                print(f'- [{link[\"text\"]}]({link[\"href\"]})')
    else:
        print(f'ERROR: scraping fallido - {d.get(\"error\", \"Unknown\")}')
except:
    print(f'ERROR: Failed to parse scrape response')
" 2>/dev/null
}

case "${1:-help}" in
    navigate)
        web_navigate "${2:-}" "${3:-2000}"
        ;;
    scrape)
        web_scrape "${2:-}" "${3:-5000}" "${4:-30}"
        ;;
    help|*)
        echo "Usage:"
        echo "  web-utils navigate <URL> [max_chars]    # Navegar y obtener contenido"
        echo "  web-utils scrape <URL> [max_content] [max_links]  # Scraping completo"
        ;;
esac
