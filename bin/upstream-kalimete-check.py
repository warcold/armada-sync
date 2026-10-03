#!/usr/bin/env python3
"""upstream-kalimete-check.py — versiones Kalimete (locales + vps-preprod) vs upstream.
Guarda 24h (lazy), KEYLESS. Estado: ~/armada-sync/upstream/state.json (hub lo publica).
Checker LEIDO por el subagente eco-victoria de Victoria desde /srv/armada-upstream/.
Uso: sin args (corre solo si guarda expirada) | --force | --report"""
import json, os, re, subprocess, sys, time, urllib.request

HOME = os.path.expanduser("~")
STATE_DIR = os.path.join(HOME, "armada-sync", "upstream")
STATE = os.path.join(STATE_DIR, "state.json")
TTL_F = os.path.join(STATE_DIR, ".last_check")
TTL = 86400
LOG = os.path.join(STATE_DIR, "check.log")
VPS = "vps-preprod"
MIRROR_PARENT = "/srv/armada-upstream"
MIRROR = MIRROR_PARENT + "/kalimete-state.json"
UA = {"User-Agent": "armada-kalimete/1.0"}
TIMEOUT = 15

def log(msg):
    line = "{} {}".format(time.strftime("[%Y-%m-%d %H:%M]"), msg)
    print(line)
    try:
        with open(LOG, "a") as f:
            f.write(line + "\n")
    except OSError:
        pass

def sh(c, timeout=20):
    try:
        return subprocess.run(c, shell=True, capture_output=True, text=True, timeout=timeout).stdout.strip()
    except Exception:
        return ""

def fetch(url, json_mode=True):
    try:
        req = urllib.request.Request(url, headers=UA)
        with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
            txt = r.read().decode("utf-8", "replace")
            return json.loads(txt) if json_mode else txt
    except Exception as e:
        return {"_err": str(e)[:100]} if json_mode else ""

def gh_latest(repo):
    d = fetch("https://api.github.com/repos/" + repo + "/releases/latest")
    if not isinstance(d, dict) or "_err" in d:
        return ""
    return d.get("tag_name", "") or d.get("name", "") or ""

def gh_tag(repo, match=None):
    d = fetch("https://api.github.com/repos/" + repo + "/tags?per_page=60")
    if not isinstance(d, list):
        return ""
    for t in d:
        n = t.get("name", "")
        if match and not re.search(match, n):
            continue
        return n
    return ""

def pypi(pkg):
    d = fetch("https://pypi.org/pypi/" + pkg + "/json")
    return ((d or {}).get("info") or {}).get("version", "")

def hub_latest(repo):
    d = fetch("https://hub.docker.com/v2/repositories/" + repo + "/tags/latest")
    return (d or {}).get("name", "")

def hub_tag_named(repo, name):
    d = fetch("https://hub.docker.com/v2/repositories/" + repo + "/tags/" + name)
    return (d or {}).get("name", "")

def hub_wp_latest():
    # hub.docker.com/library/wordpress/latest tag -> date pushed as 'latest' rows
    d = fetch("https://hub.docker.com/v2/repositories/library/wordpress/tags/latest")
    return (d or {}).get("last_updated", "")[:10]  # solo fecha, comparación por date

def hub_wp_local_date(kalimete_docker=True):
    # fecha del tag 6.7-php8.3-apache (el que corre), para comparar mejor con latest
    d = fetch("https://hub.docker.com/v2/repositories/library/wordpress/tags/6.7-php8.3-apache")
    return (d or {}).get("last_updated", "")[:10]

def ssh_vps(cmd):
    return sh("ssh -o ConnectTimeout=8 -o BatchMode=yes " + VPS + " " + sh_quote(cmd), timeout=30)

def ssh_victoria(cmd):
    return sh("ssh -o ConnectTimeout=8 -o BatchMode=yes victoria " + sh_quote(cmd), timeout=20)

def sh_quote(s):
    return "'" + s.replace("'", "'\\''") + "'"

def git_head(path):
    return sh("git -C " + path + " rev-parse HEAD 2>/dev/null")[:12]

def git_up(path):
    sh("git -C " + path + " fetch --quiet --depth=1 origin HEAD 2>/dev/null")
    return sh("git -C " + path + " rev-parse @{u} 2>/dev/null" + "").strip()[:12]

def vps_ps(fmt):
    return ssh_vps("docker ps --format " + sh_quote(fmt))

def vps_img(pat):
    out = vps_ps("{{.Image}}")
    for line in out.splitlines():
        if re.search(pat, line):
            return line.strip()
    return ""

def kali_img(pat):
    out = sh("docker ps --format '{{.Image}}'")
    for line in out.splitlines():
        if re.search(pat, line):
            return line.strip()
    return ""

def norm(v):
    v = (v or "").strip()
    v = re.sub(r"^(version|release|v|V)+", "", v)
    v = re.sub(r"[.x-]+$" , "", v.replace(".x", ""))
    return v.lower()

def eq(a, b):
    if not a or not b:
        return None
    na, nb = norm(a), norm(b)
    if na == nb:
        return False
    return True

def val_inspircd():
    out = ssh_vps("inspircd --version 2>/dev/null | head -1")
    m = re.search(r"([0-9][0-9.x]*)", out)
    return m.group(1).replace("x","") if m else ""

def val_squid():
    out = ssh_vps("squid -v 2>/dev/null")
    m = re.search(r"[Vv]ersion[ /]+([0-9]+(?:\.[0-9]+)+)", out)
    return m.group(1) if m else ""

def val_godot():
    out = sh("command -v godot >/dev/null 2>&1 && godot --version 2>/dev/null")
    m = re.search(r"([0-9]+(?:\.[0-9]+)+)", out)
    return m.group(1) if m else ""

def val_prowler():
    out = sh("command -v prowler-cli >/dev/null 2>&1 && prowler-cli --version 2>/dev/null | head -1")
    m = re.search(r"([0-9]+(?:\.[0-9]+)+)", out)
    return m.group(1) if m else ""

CHECKS = [
 {"id":"eco-vps", "label":"25/25 contenedores (infra)", "kind":"labels", "href":"https://docs.docker.com", "docs":"https://docs.docker.com",
  "local": lambda: ( "labels " + str(len(vps_ps("{{.Names}}").split())) ) , "upstream": ""},
 {"id":"eco-victoria", "label":"LEIDO (otra maquina)", "kind":"goto", "href":"", "docs":"", "local":lambda:"", "upstream":""},
 {"id":"eco-cloudflare", "label":"cloudflared (hub)", "kind":"fetched", "href":"github.com/cloudflare/cloudflared/releases", "docs":"https://developers.cloudflare.com/changelog/",
  "local": lambda: gh_latest("cloudflare/cloudflared") and re.sub(r"^[A-Za-z-]*", "", sh("cloudflared --version 2>/dev/null | grep -oE [0-9]+[.][0-9]+[.][0-9]+ | head -1")),
  "upstream": lambda: gh_latest("cloudflare/cloudflared")},
 {"id":"eco-irc", "label":"inspircd native (vps)", "kind":"fetched", "href":"github.com/inspircd/inspircd/releases", "docs":"https://docs.inspircd.org/4/",
  "local": val_inspircd, "upstream": lambda: gh_latest("inspircd/inspircd")},
 {"id":"eco-proxy", "label":"squid native (vps)", "kind":"fetched", "href":"github.com/squid-cache/squid/tags", "docs":"https://www.squid-cache.org",
  "local": val_squid, "upstream": lambda: gh_tag("squid-cache/squid", match=r"SQUID_6")},
 {"id":"eco-petsuite", "label":"petsuite:v2 (local)", "kind":"local", "href":"", "docs":"", "local": lambda: vps_img(r"petsuite"), "upstream": ""},
 {"id":"eco-woodly", "label":"woodly-woodly (kalimete)", "kind":"local", "href":"", "docs":"", "local": lambda: kali_img(r"woodly"), "upstream": ""},
 {"id":"eco-alfredo-ecomm", "label":"backend-api (kalimete)", "kind":"local", "href":"", "docs":"", "local": lambda: kali_img(r"backend-api"), "upstream": ""},
 {"id":"eco-taohemps", "label":"taohemps-frontend/backend (vps)", "kind":"local", "href":"", "docs":"", "local": lambda: vps_img(r"taohemps"), "upstream": ""},
 {"id":"eco-ragnarok", "label":"git /srv/ragnarok (vps)", "kind":"git", "href":"https://rathena.org/board/", "docs":"https://rathena.org/board/",
  "local": lambda: ssh_vps("git -C /srv/ragnarok rev-parse HEAD 2>/dev/null")[:12], "upstream": lambda: ssh_vps("git -C /srv/ragnarok fetch --quiet --depth=1 origin HEAD ./svn && echo $(git -C /srv/ragnarok rev-parse @{u} 2>/dev/null | cut -c1-12)") or ""},
 {"id":"eco-nextcloud", "label":"nextcloud:fpm (vps)", "kind":"named", "href":"github.com/Nextcloud/server/releases", "docs":"https://docs.nextcloud.com/",
  "local": lambda: vps_img(r"nextcloud-stack-nextcloud") or "nextcloud:fpm", "upstream": "", "extra": lambda: gh_latest("Nextcloud/server")},
 {"id":"eco-authentik", "label":"ghcr.io/goauthentik/server (vps)", "kind":"named", "href":"github.com/goauthentik/authentik/releases", "docs":"https://docs.goauthentik.io/",
  "local": lambda: vps_img(r"authentik-server") or "ghcr.io/goauthentik/server", "upstream": "", "extra": lambda: gh_latest("goauthentik/authentik")},
 {"id":"eco-docuseal", "label":"docuseal/docuseal:latest (vps)", "kind":"named", "href":"github.com/docusealco/docuseal/releases", "docs":"https://www.docuseal.com/guides",
  "local": lambda: vps_img(r"docuseal") or "docuseal/docuseal:latest", "upstream": "", "extra": lambda: gh_latest("docusealco/docuseal")},
 {"id":"eco-scriberr", "label":"scriberr-custom (vendor)", "kind":"local", "href":"", "docs":"", "local": lambda: vps_img(r"scriberr"), "upstream": ""},
 {"id":"wordpress-dev", "label":"wordpress:6.7-php8.3-apache (kalimete)", "kind":"fetched", "href":"hub.docker.com/_/wordpress", "docs":"https://wordpress.org/documentation/",
  "local": hub_wp_local_date, "upstream": hub_wp_latest, "extra": lambda: hub_tag_named("library/wordpress", "6.7-php8.3-apache")},
 {"id":"erp-dev", "label":"git erpipo preprod (:8100)", "kind":"git", "href":"github.com/warcold/erpipo-preprod", "docs":"", "local": lambda: git_head(HOME + "/erpipo-preprod") or "?", "upstream": lambda: git_up(HOME + "/erpipo-preprod")},
 {"id":"godot-dev", "label":"godot: 4.7.2 (kalimete)", "kind":"fetched", "href":"github.com/godotengine/godot/releases", "docs":"https://docs.godotengine.org/", "local": val_godot, "upstream": lambda: gh_latest("godotengine/godot") and re.sub(r"^[A-Za-z-]*", "", gh_latest("godotengine/godot").replace("stable","").replace(".stable",""))},
 {"id":"proxmark", "label":"prowler-cli 5.36.0 (kalimete)", "kind":"fetched", "href":"pypi.org/pypi/prowler", "docs":"https://docs.prowler.com/", "local": val_prowler, "upstream": lambda: pypi("prowler")},
]

def run(write=True):
    state, drifts = {}, []
    for c in CHECKS:
        if c.get("kind") == "goto":
            state[c["id"]] = {"id": c["id"], "label": c["label"], "href": c["href"], "docs": c["docs"], "kind": "goto", "ts": int(time.time())}
            continue
        try:
            local = (c["local"]() or "").strip()
        except Exception:
            local = ""
        try:
            up = (c["upstream"]() or "").strip()
        except Exception:
            up = ""
        extra = ""
        if c.get("extra"):
            try:
                extra = (c["extra"]() or "").strip()
            except Exception:
                extra = ""
        drift = eq(local, up) if up else None
        if not local and not up:
            drift = None
        state[c["id"]] = {"id": c["id"], "label": c.get("label",""), "href": c["href"], "docs": c.get("docs",""),
                          "local": local or "?", "upstream": up or "?", "latest": extra, "drift": drift,
                          "kind": c.get("kind","fetched"), "ts": int(time.time())}
        if drift is True:
            drifts.append(c["id"])
    if write:
        os.makedirs(STATE_DIR, exist_ok=True)
        json.dump(state, open(STATE, "w"), indent=1)
        open(TTL_F, "w").write(str(int(time.time())))
        sh("ssh -o ConnectTimeout=10 -o BatchMode=yes " + VPS + " mkdir -p " + MIRROR_PARENT + " 2>/dev/null")
        sh("scp -q -o ConnectTimeout=10 " + STATE + " " + VPS + ":" + MIRROR + " 2>/dev/null")
    return state, drifts

def stale():
    try:
        return (time.time() - os.path.getmtime(TTL_F)) >= TTL
    except OSError:
        return True

def report():
    try:
        st = json.load(open(STATE))
    except (OSError, ValueError):
        print("sin estado aun")
        return 0
    age = -1
    if os.path.exists(TTL_F):
        age = time.time() - os.path.getmtime(TTL_F)
    print("chequeo:", (str(age/3600) + "h" if age >= 0 else "nunca"))
    print("{}{:<22}{:<34}{:<34}EST".format("", "SISTEMA", "LOCAL", "UPSTREAM"))
    for k in ["eco-vps","eco-victoria","eco-cloudflare","eco-irc","eco-proxy","eco-petsuite","eco-woodly","eco-alfredo-ecomm","eco-taohemps","eco-ragnarok","eco-nextcloud","eco-authentik","eco-docuseal","eco-scriberr","wordpress-dev","erp-dev","godot-dev","proxmark"]:
        s = st.get(k)
        if not s:
            print("{}{:<36}{}{}".format(k, "[sin datos]", "", "?")); continue
        if s.get("kind") == "goto":
            print("{}{:<22}{}{}".format(k, "(ajeno victoria)", "", "→")); continue
        est = "drift" if s.get("drift") is True else ("?" if s.get("drift") is None else "ok")
        print("{}{:<22}{:<34}{:<34}{}".format("", k, str(s.get("local","?"))[:30], str(s.get("upstream","?"))[:30], est))
    return 0

if __name__ == "__main__":
    force = "--force" in sys.argv
    if "--report" in sys.argv:
        sys.exit(report())
    if force or stale():
        st, drifts = run(True)
        ok = sum(1 for v in st.values() if v.get("drift") is False)
        log("chequeo: query={} sistemas, {} ok, {} derivas".format(len(st), ok, len(drifts)))
        for d in drifts:
            log("DERIVA: " + d)
    else:
        print("al-dia (guarda 24h); reporte: --report")
