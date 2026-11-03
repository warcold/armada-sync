#!/usr/bin/env python3
# web-nav-server.py - Servicio de navegación web para Victoria
# Navega y examina URLs usando Chromium headless via Playwright

import json
import os
import signal
import sys
import time
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs

sys.path.insert(0, "/home/victoria")
import sense_auth

try:
    from playwright.sync_api import sync_playwright
    PLAYWRIGHT_AVAILABLE = True
except ImportError:
    PLAYWRIGHT_AVAILABLE = False

HOST = "0.0.0.0"
PORT = 18820
CHROMIUM_PATH = "/snap/bin/chromium"  # Chromium del host

start_time = time.time()
total_requests = 0

class WebNavHandler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        pass

    def do_GET(self):
        path = urlparse(self.path).path
        if path == "/health":
            self.send_json(200, {
                "status": "ok",
                "uptime_s": int(time.time() - start_time),
                "playwright": "OK" if PLAYWRIGHT_AVAILABLE else "MISSING",
                "chromium_path": CHROMIUM_PATH,
                "total_requests": total_requests
            })
        elif path == "/voice/config-guide":
            self.send_json(200, {
                "tool_name": "web_nav",
                "description": "Navigate and examine web URLs using headless Chromium",
                "available_tools": ["web_navigate", "web_scrape", "web_search"],
                "usage": "Send POST to /navigate with JSON body: {\"url\": \"https://...\"}"
            })
        else:
            self.send_json(404, {"error": "Not found"})

    def do_POST(self):
        global total_requests
        # SEGURIDAD 2026-09-17: localhost/docker (sandbox) sin llave;
        # LAN con llave gateway admin/services; resto denegado.
        ip = sense_auth.norm_ip(self.client_address[0] if self.client_address else "")
        if not sense_auth.is_trusted(ip):
            if not (sense_auth.is_lan(ip) and sense_auth.sense_role(self.headers)):
                self.send_json(401, {"error": "unauthorized",
                                     "detail": "Se requiere llave gateway admin/services (o red local/docker)"})
                return
        total_requests += 1
        path = urlparse(self.path).path

        content_length = int(self.headers.get('Content-Length', 0))
        post_data = json.loads(self.rfile.read(content_length))
        
        if path == "/navigate":
            url = post_data.get("url")
            if not url:
                self.send_json(400, {"error": "Missing 'url'"})
                return
            result = self.do_navigate(url)
            self.send_json(200, result)
        elif path == "/scrape":
            url = post_data.get("url")
            if not url:
                self.send_json(400, {"error": "Missing 'url'"})
                return
            result = self.do_scrape(url)
            self.send_json(200, result)
        else:
            self.send_json(404, {"error": "Not found"})

    def do_navigate(self, url):
        if not url.startswith(("http://", "https://")):
            url = "https://" + url
        
        try:
            with sync_playwright() as p:
                browser = p.chromium.launch(
                    headless=True,
                    args=["--no-sandbox", "--disable-gpu", "--disable-dev-shm-usage"]
                )
                context = browser.new_context(
                    viewport={"width": 1920, "height": 1080},
                    user_agent="Mozilla/5.0 (compatible; Victoria; +http://alfredo.pro)"
                )
                page = context.new_page()
                
                response = page.goto(url, wait_until="networkidle", timeout=30000)
                
                title = page.title().strip()
                text_content = page.inner_text("body").strip()
                
                # Extraer links
                links = []
                for a in page.query_selector_all("a")[:30]:
                    href = a.get_attribute("href")
                    text = a.text_content().strip()[:100]
                    if href and text:
                        links.append({"href": href, "text": text})
                
                browser.close()
                
                return {
                    "ok": True,
                    "url": page.url,
                    "title": title,
                    "content_preview": text_content[:2000],
                    "links": links[:20],
                    "message": f"Navegación exitosa: {title}"
                }
        except Exception as e:
            return {"ok": False, "error": str(e)[:500]}

    def do_scrape(self, url):
        if not url.startswith(("http://", "https://")):
            url = "https://" + url
        
        try:
            with sync_playwright() as p:
                browser = p.chromium.launch(headless=True)
                context = browser.new_context(
                    viewport={"width": 1920, "height": 1080},
                    user_agent="Mozilla/5.0 (compatible; Victoria; +http://alfredo.pro)"
                )
                page = context.new_page()
                
                page.goto(url, wait_until="networkidle", timeout=30000)
                
                title = page.title().strip()
                meta_desc = page.query_selector("meta[name='description']")
                description = meta_desc.get_attribute("content") if meta_desc else ""
                
                body_text = page.inner_text("body").strip()[:8000]
                
                # Extraer headings
                headings = []
                for h in page.query_selector_all("h1, h2, h3")[:20]:
                    headings.append(h.text_content().strip()[:200])
                
                # Extraer links
                links = []
                for a in page.query_selector_all("a")[:50]:
                    href = a.get_attribute("href")
                    text = a.text_content().strip()[:150]
                    if href and text:
                        links.append({"text": text, "href": href})
                
                browser.close()
                
                return {
                    "ok": True,
                    "url": url,
                    "title": title,
                    "description": description[:500],
                    "headings": headings,
                    "content": body_text[:5000],
                    "links_sample": links[:30]
                }
        except Exception as e:
            return {"ok": False, "error": str(e)[:500]}

    def send_json(self, status_code, data):
        self.send_response(status_code)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps(data, ensure_ascii=False).encode('utf-8'))

if __name__ == "__main__":
    server = HTTPServer((HOST, PORT), WebNavHandler)
    print(f"[web-nav] Ready on {HOST}:{PORT}")
    server.serve_forever()
