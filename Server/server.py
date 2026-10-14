#!/usr/bin/env python3
"""Rebond — prototype server for the pitch demo (connected version of Rebond Pro).

FICTIONAL PATIENTS ONLY. Real health data must be hosted by an HDS-certified host (France).
Python standard library only; data kept in demo-data.json next to this file.

Run:  python3 server.py [port]      (default port 8080)
Then, in Rebond (development build): Espace kiné > Version connectée > address shown below.
"""
import json
import socket
import sys
import threading
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

DATA_FILE = Path(__file__).with_name("demo-data.json")
LOCK = threading.Lock()


def load():
    if DATA_FILE.exists():
        return json.loads(DATA_FILE.read_text())
    return {"kines": {}, "patients": {}}


DB = load()


def save():
    DATA_FILE.write_text(json.dumps(DB, ensure_ascii=False, indent=2))


def patient(pid):
    return DB["patients"].setdefault(pid, {"kineID": None, "name": "", "report": None, "program": None, "version": 0})


class Handler(BaseHTTPRequestHandler):
    def reply(self, status, payload):
        body = json.dumps(payload, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def body(self):
        length = int(self.headers.get("Content-Length") or 0)
        return json.loads(self.rfile.read(length) or b"{}")

    def parts(self):
        return [p for p in self.path.split("?")[0].split("/") if p]

    def do_GET(self):
        p = self.parts()
        with LOCK:
            if p == ["health"]:
                return self.reply(200, {"ok": True})
            # Physiotherapist: linked patients with their last report.
            if len(p) == 3 and p[0] == "kines" and p[2] == "patients":
                entries = [{"patientID": pid, "name": pt["name"], "report": pt["report"]}
                           for pid, pt in DB["patients"].items() if pt["kineID"] == p[1]]
                return self.reply(200, entries)
            # Patient: the program prescribed through the server, if any.
            if len(p) == 3 and p[0] == "patients" and p[2] == "program":
                pt = DB["patients"].get(p[1])
                if not pt or not pt["program"]:
                    return self.reply(404, {"error": "no program"})
                return self.reply(200, {"version": pt["version"], "program": pt["program"]})
        self.reply(404, {"error": "not found"})

    def do_POST(self):
        p = self.parts()
        data = self.body()
        with LOCK:
            if p == ["kines"]:
                kid = uuid.uuid4().hex[:12]
                DB["kines"][kid] = {"name": data.get("name", "")}
                save()
                print(f"Kiné inscrit : {data.get('name') or kid}")
                return self.reply(200, {"id": kid})
            if len(p) == 3 and p[0] == "patients" and p[2] == "link":
                pt = patient(p[1])
                pt["kineID"] = data.get("kineID")
                pt["name"] = data.get("name") or pt["name"]
                save()
                print(f"Patient lié : {pt['name'] or p[1]}")
                return self.reply(200, {"ok": True})
        self.reply(404, {"error": "not found"})

    def do_PUT(self):
        p = self.parts()
        data = self.body()
        with LOCK:
            if len(p) == 3 and p[0] == "patients" and p[2] == "report":
                pt = patient(p[1])
                pt["report"] = data
                pt["name"] = data.get("patientName") or pt["name"]
                save()
                print(f"Bilan reçu : {pt['name']}")
                return self.reply(200, {"ok": True})
            if len(p) == 3 and p[0] == "patients" and p[2] == "program":
                pt = patient(p[1])
                pt["program"] = data
                pt["version"] += 1
                save()
                print(f"Programme modifié pour {pt['name']} (version {pt['version']})")
                return self.reply(200, {"version": pt["version"]})
        self.reply(404, {"error": "not found"})

    def log_message(self, *args):
        pass


def addresses(port):
    host = socket.gethostname()
    if not host.endswith(".local"):
        host += ".local"
    yield f"http://{host}:{port}"
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
            s.connect(("192.0.2.1", 80))
            yield f"http://{s.getsockname()[0]}:{port}"
    except OSError:
        pass


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
    print("Serveur de démo Rebond — patients fictifs uniquement.")
    print("Adresse à saisir dans l'espace kiné :")
    for address in addresses(port):
        print("  " + address)
    ThreadingHTTPServer(("0.0.0.0", port), Handler).serve_forever()
