#!/usr/bin/env python3
"""Jednoducha webova stranka "Naskenovat a poslat e-mailem".

Otevres http://<raspberry>.local:8080 z PC nebo z mobilu, zadas e-mail a zmacknes tlacitko.
Stranka jen spusti skript scan2email.sh - veskera logika skenovani je tam.
"""
import os
import re
import subprocess
import threading

from flask import Flask, render_template_string, request

SCRIPT = os.environ.get("SCAN2EMAIL_SCRIPT", "/usr/local/bin/scan2email.sh")
DEFAULT_TO = os.environ.get("MAIL_TO", "")
PORT = int(os.environ.get("PORT", "8080"))
EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[A-Za-z]{2,}$")

app = Flask(__name__)
scan_lock = threading.Lock()  # skener umi jen jedno skenovani najednou

PAGE = """<!doctype html>
<html lang="cs"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Skenovani</title>
<style>
 body{font-family:system-ui,sans-serif;max-width:420px;margin:2em auto;padding:0 16px;background:#f5f5f5}
 .card{background:#fff;border-radius:12px;padding:20px;box-shadow:0 1px 4px #0002}
 label{display:block;margin-top:12px;font-weight:600}
 input,select,button{width:100%;box-sizing:border-box;padding:10px;margin-top:4px;font-size:1em}
 button{margin-top:20px;background:#2563eb;color:#fff;border:0;border-radius:8px;cursor:pointer}
 .ok{color:#15803d}.err{color:#b91c1c;white-space:pre-wrap}
</style></head><body><div class="card">
<h1>Naskenovat do PDF</h1>
{% if msg %}<p class="{{ cls }}">{{ msg }}</p>{% endif %}
<form method="post" onsubmit="this.querySelector('button').disabled=true;this.querySelector('button').textContent='Skenuji…'">
 <label>E-mail prijemce<input type="email" name="to" value="{{ to }}" required></label>
 <label>Rozliseni<select name="dpi">
  {% for d in [150, 200, 300] %}<option {{ 'selected' if d == 200 }}>{{ d }}</option>{% endfor %}
 </select></label>
 <label><input type="checkbox" name="ocr" style="width:auto"> OCR (prohledavatelny text, pomalejsi)</label>
 <button type="submit">Skenovat a odeslat</button>
</form></div></body></html>"""


@app.route("/", methods=["GET", "POST"])
def index():
    to, msg, cls = DEFAULT_TO, "", "ok"
    if request.method == "POST":
        to = request.form.get("to", "").strip()
        dpi = request.form.get("dpi", "200")
        if not EMAIL_RE.match(to):
            return render_template_string(PAGE, to=to, msg="Neplatna e-mailova adresa.", cls="err")
        if dpi not in ("150", "200", "300"):
            dpi = "200"
        if not scan_lock.acquire(blocking=False):
            return render_template_string(PAGE, to=to, msg="Skener je prave obsazeny, zkus to za chvili.", cls="err")
        try:
            # Argumenty jako seznam (bez shellu) => uzivatel nemuze podstrcit prikaz.
            cmd = [SCRIPT, "-t", to, "-r", dpi]
            if request.form.get("ocr"):
                cmd.append("-O")
            r = subprocess.run(cmd, capture_output=True, text=True, timeout=600)
            if r.returncode == 0:
                msg = f"Hotovo, PDF odeslano na {to}."
            else:
                msg, cls = "Chyba:\n" + r.stderr[-1500:], "err"
        except subprocess.TimeoutExpired:
            msg, cls = "Skenovani trvalo prilis dlouho.", "err"
        finally:
            scan_lock.release()
    return render_template_string(PAGE, to=to, msg=msg, cls=cls)


if __name__ == "__main__":
    try:
        from waitress import serve  # produkcni WSGI server
        serve(app, host="0.0.0.0", port=PORT)
    except ImportError:
        app.run(host="0.0.0.0", port=PORT)
