#!/usr/bin/env python3
"""Restart `rojo serve` after scripts were added, moved or removed.

  python tools/restart_rojo.py            regenerate-check, stop old rojo, start a new one, wait for the port
  python tools/restart_rojo.py --stop     only stop it

Steps: (1) `gen_project.py --check` (warns if default.project.json is stale), (2) kill every running rojo process by
PID (never other programs), (3) start `rojo serve` detached with its output in the temp folder, (4) wait until the
port accepts connections. Afterwards press Connect in the Studio Rojo plugin. Removed scripts must still be deleted
by hand in Studio: Rojo does not delete them.
"""

import json
import os
import shutil
import socket
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LOG = Path(tempfile.gettempdir()) / "rojo_serve.log"
DEFAULT_PORT = 34872
WIN = os.name == "nt"


def rojo_pids() -> list[int]:
    if WIN:
        out = subprocess.run(["tasklist", "/FI", "IMAGENAME eq rojo.exe", "/FO", "CSV", "/NH"],
                             capture_output=True, text=True).stdout
        pids = []
        for line in out.splitlines():
            parts = [p.strip('"') for p in line.split('","')]
            if len(parts) > 1 and parts[0].lower().strip('"') == "rojo.exe":
                pids.append(int(parts[1]))
        return pids
    out = subprocess.run(["pgrep", "-x", "rojo"], capture_output=True, text=True).stdout
    return [int(p) for p in out.split()]


def stop() -> None:
    for pid in rojo_pids():
        if WIN:
            subprocess.run(["taskkill", "/PID", str(pid), "/F"], capture_output=True)
        else:
            os.kill(pid, 9)
        print(f"stopped rojo PID {pid}")
    deadline = time.time() + 5
    while rojo_pids() and time.time() < deadline:
        time.sleep(0.2)


def port() -> int:
    try:
        return int(json.loads((ROOT / "default.project.json").read_text(encoding="utf-8")).get("servePort", DEFAULT_PORT))
    except (OSError, ValueError):
        return DEFAULT_PORT


def listening(p: int) -> bool:
    with socket.socket() as s:
        s.settimeout(0.3)
        return s.connect_ex(("127.0.0.1", p)) == 0


def main() -> int:
    check = subprocess.run([sys.executable, str(ROOT / "tools" / "gen_project.py"), "--check"],
                           capture_output=True, text=True, cwd=ROOT)
    if check.returncode != 0:
        print("WARNING: default.project.json is stale:", (check.stdout + check.stderr).strip())
        print("run: python tools/gen_project.py")

    stop()
    if "--stop" in sys.argv:
        return 0

    rojo = shutil.which("rojo")  # on Windows this is often an npm shim (rojo.cmd), which CreateProcess cannot find by bare name
    if not rojo:
        print("rojo is not on PATH")
        return 1
    log = open(LOG, "wb")
    kwargs = {}
    if WIN:
        kwargs["creationflags"] = 0x00000008 | 0x00000200  # DETACHED_PROCESS | CREATE_NEW_PROCESS_GROUP
    else:
        kwargs["start_new_session"] = True
    proc = subprocess.Popen([rojo, "serve"], cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL, **kwargs)

    p = port()
    deadline = time.time() + 20
    while time.time() < deadline:
        if proc.poll() is not None:
            print("rojo exited early:", LOG.read_text(errors="replace")[-400:])
            return 1
        if listening(p):
            print(f"rojo serve is up on port {p} (PID {proc.pid}, log {LOG}). Press Connect in the Studio Rojo plugin.")
            return 0
        time.sleep(0.3)
    print(f"rojo did not open port {p} within 20s; see {LOG}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
