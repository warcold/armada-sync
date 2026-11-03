#!/usr/bin/env python3
"""victoria-video-server.py - Servicio de video de Victoria Armada.

Daemon HTTP persistente EN EL HOST (el sandbox no tiene egress a YouTube):
  GET  /health                      -> {"ok": true, "ytdlp": "...", "ffmpeg": true}
  POST /download                    -> JSON {"url": "..."} -> descarga con yt-dlp a
                                       /home/victoria/.victoria-custom/videos/<id>/
                                       devuelve {"video_path","title","duration",
                                       "resolution","webpage_url","id"}
  POST /frames                      -> JSON {"video": "<path|url>", "times": ["00:01:00","00:02:00"],
                                       "count": 5, "width": 640}
                                       extrae frames con ffmpeg (jpg/png)
                                       devuelve {"frames": ["/abs/path.jpg", ...]}
  POST /transcribe                  -> JSON {"video": "<path>", "lang": "es"} -> extrae audio
                                       con ffmpeg y lo manda al voice-server host (whisper /stt)
                                       devuelve {"text": "..."}
  POST /analyze                     -> JSON {"url": "...", "frames_times": [...], "lang": "es"}
                                       = download + frames + transcribe en un solo paso
                                       devuelve {"title","duration","frames":[...],"transcript":"..."}

El sandbox lo consume vía el bridge de UNIX socket (video-bridge.py) que hace
proxy a host.docker.internal:18811 (mismo patrón que el voice-server en 18810).
"""
import json
import os
import re
import subprocess
import sys
import tempfile
import time
import urllib.request

sys.path.insert(0, "/home/victoria")
import sense_auth

from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HOST = "0.0.0.0"
PORT = 18811
os.environ["PATH"] = "/home/victoria/.deno/bin:" + os.environ.get("PATH", "")
VIDEO_ROOT = "/home/victoria/.victoria-custom/videos"
YTDLP = "/home/victoria/video-venv/bin/yt-dlp"
FFMPEG = "/usr/bin/ffmpeg"
FFPROBE = "/usr/bin/ffprobe"
VOICE_SERVER = "http://127.0.0.1:18810"
LLM_GATEWAY = "http://127.0.0.1:8010/v1/chat/completions"
LLM_MODEL = "nvidia/Qwen3.6-35B-A3B-NVFP4"
_started = time.time()


def log(msg):
    print(f"[victoria-video-server] {msg}", flush=True)


def run(cmd, timeout=3600):
    p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    return p.returncode, p.stdout, p.stderr


def sanitize(name):
    name = re.sub(r"[^A-Za-z0-9._-]+", "-", name)
    return name.strip("-")[:80] or "video"


def get_yt_title(url):
    try:
        code, out, err = run([YTDLP, "--skip-download", "--print", "title",
                              url], timeout=120)
        title = (out or "").strip().splitlines()[0] if out.strip() else ""
        if title:
            return title[:200]
    except Exception:
        pass
    return os.path.basename(url)[:200]


def get_vlm_key():
    import sqlite3
    conn = sqlite3.connect("/home/victoria/.victoria-llm/llm-gateway.db")
    try:
        r = conn.execute("SELECT key_plaintext FROM api_keys WHERE name='servicios-alfredo-pro-llc'").fetchone()
        return r[0] if r else ""
    finally:
        conn.close()


def describe_frame(frame_path, lang="es"):
    """Envía un frame al VLM local (gateway 8010) y devuelve la descripción."""
    if not os.path.isfile(frame_path):
        return "(frame no disponible)"
    import base64
    b64 = base64.b64encode(open(frame_path, "rb").read()).decode()
    prompt = ("Describe brevemente en {} qué se ve en este frame de un video "
              "(escena, objetos, texto, personas, acción). Máx 200 caracteres.")
    lang_name = "español" if lang == "es" else "inglés"
    payload = {
        "model": LLM_MODEL,
        "chat_template_kwargs": {"enable_thinking": False},
        "messages": [{"role": "user", "content": [
            {"type": "text", "text": prompt.format(lang_name)},
            {"type": "image_url", "image_url": {"url": f"data:image/jpeg;base64,{b64}"}},
        ]}],
        "max_tokens": 200,
    }
    req = urllib.request.Request(LLM_GATEWAY,
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json", "Authorization": "Bearer " + get_vlm_key()})
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            d = json.loads(resp.read().decode())
            msg = d["choices"][0]["message"]
            content = (msg.get("content") or "").strip()
            reasoning = (msg.get("reasoning") or "").strip()
            return (content or reasoning or "(sin descripción)")[:400]
    except Exception as e:
        return f"(error VLM: {e})"


def ffprobe_info(video_path):
    code, out, err = run([FFPROBE, "-v", "error", "-show_entries",
                          "format=duration:stream=width,height,codec_name",
                          "-of", "json", video_path])
    if code != 0:
        return {}
    try:
        d = json.loads(out)
        fmt = d.get("format", {})
        streams = d.get("streams", [])
        duration = float(fmt.get("duration", 0) or 0)
        res = ""
        for s in streams:
            if s.get("width") and s.get("height"):
                res = f"{s['width']}x{s['height']}"
                break
        return {"duration": round(duration, 1), "resolution": res}
    except Exception:
        return {}


def get_audio_wav(video_path, workdir):
    wav = os.path.join(workdir, "audio.wav")
    code, out, err = run([FFMPEG, "-y", "-v", "error", "-i", video_path,
                          "-vn", "-ac", "1", "-ar", "16000", wav])
    if code != 0 or not os.path.isfile(wav):
        raise RuntimeError(f"ffmpeg audio extracción falló: {err[:300]}")
    return wav


def voice_stt(wav_path, lang):
    with open(wav_path, "rb") as f:
        data = f.read()
    url = VOICE_SERVER + "/stt"
    if lang:
        url += f"?lang={lang}"
    req = urllib.request.Request(url, data=data,
                                 headers={"Content-Type": "application/octet-stream"},
                                 method="POST")
    with urllib.request.urlopen(req, timeout=600) as resp:
        body = resp.read().decode("utf-8", "replace")
    try:
        return json.loads(body).get("text", "")
    except Exception:
        return body.strip()


def download(url):
    vids_dir = os.path.join(VIDEO_ROOT, "downloads")
    os.makedirs(vids_dir, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        code, out, err = run([YTDLP, "-f", "18/22/mp4/best[height<=720]/best",
                              "-o", os.path.join(tmp, "video.%(ext)s"),
                              "--print", "after_move:filepath",
                              url], timeout=1800)
        if code != 0:
            raise RuntimeError(f"yt-dlp falló: {err[-500:]}")
        moved = (out or "").strip().splitlines()[-1] if out.strip() else ""
        if not moved or not os.path.isfile(moved):
            raise RuntimeError(f"yt-dlp no devolvió archivo (out={out[-300:]})")
        vid_id = "video-" + str(int(time.time()) % 100000)
        dest_dir = os.path.join(vids_dir, vid_id)
        os.makedirs(dest_dir, exist_ok=True)
        dest = os.path.join(dest_dir, "video.mp4")
        os.replace(moved, dest)
    info = ffprobe_info(dest)
    title = get_yt_title(url)
    return {
        "video_path": dest,
        "title": title,
        "duration": info.get("duration", 0),
        "resolution": info.get("resolution", ""),
        "id": vid_id,
        "webpage_url": url,
    }


def extract_frames(video, times, count, width):
    if not os.path.isfile(video):
        raise RuntimeError(f"video no existe: {video}")
    workdir = os.path.dirname(video)
    frames = []
    if times:
        for t in times:
            out = os.path.join(workdir, f"frame-{sanitize(t)}.jpg")
            code, o, e = run([FFMPEG, "-y", "-v", "error", "-ss", t, "-i", video,
                              "-frames:v", "1", "-vf",
                              (f"scale={width}:-2" if width else "scale='min(640,iw)':-2"),
                              out])
            if code == 0 and os.path.isfile(out):
                frames.append(out)
    else:
        info = ffprobe_info(video)
        duration = info.get("duration", 0)
        count = count or 5
        if duration <= 0:
            raise RuntimeError("no se pudo obtener duración del video")
        step = duration / count
        for i in range(count):
            t = i * step
            out = os.path.join(workdir, f"frame-{i:02d}.jpg")
            code, o, e = run([FFMPEG, "-y", "-v", "error", "-ss", str(t), "-i", video,
                              "-frames:v", "1", "-vf",
                              (f"scale={width}:-2" if width else "scale='min(640,iw)':-2"),
                              out])
            if code == 0 and os.path.isfile(out):
                frames.append(out)
    if not frames:
        raise RuntimeError("no se extrajeron frames")
    return frames


def analyze(url, times, lang, describe_frames=False):
    d = download(url)
    frames = extract_frames(d["video_path"], times or None, 5, 640)
    wav = get_audio_wav(d["video_path"], os.path.dirname(d["video_path"]))
    transcript = voice_stt(wav, lang)
    d["frames"] = frames
    d["transcript"] = transcript
    if describe_frames:
        d["frame_descriptions"] = [describe_frame(f, lang) for f in frames]
    return d


def analyze_local_file(video_path, lang="es", describe_frames=True, count=5):
    """Analiza un archivo de video ya presente en el host (NO descarga nada).

    Recibe la ruta absoluta de un archivo mp4/avi/mov/etc ya copiado al host.
    Extrae frames con ffmpeg, transcribe el audio con whisper (voice-server)
    y describe los frames con el VLM local. Devuelve el mismo JSON que
    `analyze` pero sin los campos de descarga (title/webpage_url/id).
    """
    if not os.path.isfile(video_path):
        raise RuntimeError(f"video no existe: {video_path}")
    info = ffprobe_info(video_path)
    frames = extract_frames(video_path, None, count, 640)
    wav = get_audio_wav(video_path, os.path.dirname(video_path))
    transcript = voice_stt(wav, lang)
    d = {
        "title": os.path.basename(video_path),
        "duration": info.get("duration", 0),
        "resolution": info.get("resolution", ""),
        "video_path": video_path,
        "frames": frames,
        "transcript": transcript,
    }
    if describe_frames:
        d["frame_descriptions"] = [describe_frame(f, lang) for f in frames]
    return d


class Handler(BaseHTTPRequestHandler):
    def _send(self, status, obj, ctype="application/json"):
        body = json.dumps(obj).encode("utf-8") if not isinstance(obj, bytes) else obj
        self.send_response(status)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _read_json(self):
        length = int(self.headers.get("Content-Length", 0))
        if length <= 0:
            return {}
        return json.loads(self.rfile.read(length).decode("utf-8", "replace"))

    def log_message(self, *a):
        pass

    def do_GET(self):
        if self.path.startswith("/health"):
            code, out, err = run([YTDLP, "--version"])
            self._send(200, {"ok": True, "uptime_s": int(time.time() - _started),
                             "ytdlp": (out or "").strip() or "?", "ffmpeg": True})
        else:
            self._send(404, {"error": "not found"})

    def _parse_qs(self):
        """Parse query string del path (e.g. /analyze-upload?count=5&lang=es)."""
        qs = {}
        if "?" in self.path:
            query = self.path.split("?", 1)[1]
            for pair in query.split("&"):
                if "=" in pair:
                    k, v = pair.split("=", 1)
                    qs[k] = v
                elif pair:
                    qs[pair] = ""
        return qs

    def _gate(self):
        """SEGURIDAD 2026-09-17: localhost/docker (bridge sandbox) sin llave;
        LAN con llave gateway admin/services; resto denegado. /health abierto."""
        ip = sense_auth.norm_ip(self.client_address[0] if self.client_address else "")
        if sense_auth.is_trusted(ip):
            return True
        if sense_auth.is_lan(ip) and sense_auth.sense_role(self.headers):
            return True
        return False

    def do_POST(self):
        if not self._gate():
            self._send(401, {"error": "unauthorized",
                             "detail": "Se requiere llave gateway admin/services (o red local/docker)"})
            return
        try:
            if self.path.startswith("/analyze-upload"):
                # Recibe el archivo binario (raw body) + X-Filename header
                qs = self._parse_qs()
                length = int(self.headers.get("Content-Length", 0))
                raw = self.rfile.read(length) if length > 0 else b""
                if not raw:
                    self._send(400, {"error": "body vacío"})
                    return
                filename = self.headers.get("X-Filename", "video.mp4")
                filename = sanitize(filename)
                ext = os.path.splitext(filename)[1] or ".mp4"
                upload_dir = os.path.join(VIDEO_ROOT, "uploads",
                                          str(int(time.time()) % 100000))
                os.makedirs(upload_dir, exist_ok=True)
                video_path = os.path.join(upload_dir, "video" + ext)
                with open(video_path, "wb") as f:
                    f.write(raw)
                lang = qs.get("lang", "es") or "es"
                count = int(qs.get("count", "5") or "5")
                describe = qs.get("describe_frames", "true") in ("true", "1", "yes")
                self._send(200, analyze_local_file(video_path, lang, describe, count))
            elif self.path.startswith("/download"):
                body = self._read_json()
                self._send(200, download(body.get("url", "")))
            elif self.path.startswith("/frames"):
                body = self._read_json()
                frames = extract_frames(body.get("video", ""), body.get("times"),
                                        body.get("count", 5), body.get("width"))
                self._send(200, {"frames": frames})
            elif self.path.startswith("/transcribe"):
                body = self._read_json()
                wav = get_audio_wav(body.get("video", ""), os.path.dirname(body.get("video", "")))
                text = voice_stt(wav, body.get("lang"))
                self._send(200, {"text": text})
            elif self.path.startswith("/analyze"):
                body = self._read_json()
                self._send(200, analyze(body.get("url", ""), body.get("frames_times"),
                                        body.get("lang", "es"), body.get("describe_frames", False)))
            else:
                self._send(404, {"error": "not found"})
        except Exception as e:
            self._send(500, {"error": str(e)})


if __name__ == "__main__":
    os.makedirs(VIDEO_ROOT, exist_ok=True)
    log(f"arrancando en {HOST}:{PORT} (yt-dlp+ffmpeg; STT vía voice-server {VOICE_SERVER})")
    ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()