#!/usr/bin/env python3
"""
Regenerates default.project.json from the folder layout under src/.

Why: scripts organised into system folders on disk (src/Server/Data/, src/Shared/Stats/ ...)
must still appear FLAT in Studio (ServerScriptService.X, ReplicatedStorage.Modules.X,
StarterPlayerScripts.X) because the game finds modules by name with WaitForChild.
Rojo cannot flatten folders itself, so every script is mapped individually.

Rules (per realm: src/Server, src/Shared, src/Client):
  * a .lua/.luau file                      -> one instance, named after the file
                                              (.client.lua = LocalScript, .server.lua = Script)
  * a folder with init.lua / init.luau /
    init.server.lua / init.client.lua /
    init.meta.json                          -> ONE instance (module with children, or a Folder),
                                              named after the folder
  * any other folder                        -> organisation only (system folder), recursed into

Usage:  python tools/gen_project.py          (rewrite default.project.json)
        python tools/gen_project.py --check  (exit 1 if the file is out of date)
"""
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "src")
PROJECT = os.path.join(ROOT, "default.project.json")

INSTANCE_MARKERS = {
    "init.lua", "init.luau", "init.server.lua", "init.client.lua",
    "init.server.luau", "init.client.luau", "init.meta.json",
}
SCRIPT_SUFFIXES = (".client.lua", ".server.lua", ".client.luau", ".server.luau", ".lua", ".luau")


def instance_name(filename):
    for suffix in SCRIPT_SUFFIXES:
        if filename.endswith(suffix):
            return filename[: -len(suffix)]
    return None


def collect(realm_dir):
    """Returns { instanceName: relative path with forward slashes }."""
    found = {}

    def add(name, path):
        if name in found:
            sys.exit(f"Duplicate instance name '{name}':\n  {found[name]}\n  {path}")
        found[name] = path

    def walk(directory):
        for entry in sorted(os.listdir(directory)):
            full = os.path.join(directory, entry)
            rel = os.path.relpath(full, ROOT).replace(os.sep, "/")
            if os.path.isdir(full):
                if INSTANCE_MARKERS & set(os.listdir(full)):
                    add(entry, rel)
                else:
                    walk(full)
            else:
                name = instance_name(entry)
                if name and not entry.startswith("init."):
                    add(name, rel)

    walk(realm_dir)
    return found


def build():
    def children(realm):
        return {name: {"$path": path} for name, path in sorted(collect(os.path.join(SRC, realm)).items())}

    return {
        "name": "FracturedIslandsAscension",
        "tree": {
            "$className": "DataModel",
            "ServerScriptService": {"$className": "ServerScriptService", **children("Server")},
            "ReplicatedStorage": {
                "$className": "ReplicatedStorage",
                "Modules": {"$className": "Folder", **children("Shared")},
            },
            "StarterPlayer": {
                "$className": "StarterPlayer",
                "StarterPlayerScripts": {"$className": "StarterPlayerScripts", **children("Client")},
            },
        },
    }


def main():
    text = json.dumps(build(), indent=2, ensure_ascii=False) + "\n"
    if "--check" in sys.argv:
        current = open(PROJECT, encoding="utf-8").read() if os.path.exists(PROJECT) else ""
        if current.replace("\r\n", "\n") != text:
            print("default.project.json is out of date - run: python tools/gen_project.py")
            sys.exit(1)
        print("default.project.json is up to date")
        return
    with open(PROJECT, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    print(f"Wrote {os.path.relpath(PROJECT, ROOT)}")


if __name__ == "__main__":
    main()
