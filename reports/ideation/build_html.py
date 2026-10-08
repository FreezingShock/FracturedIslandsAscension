#!/usr/bin/env python3
"""Render reports/ideation/<name>.md into a styled <name>.html. Usage: python3 reports/ideation/build_html.py reports/ideation/2026-10-08-3.md
The font-face (Minecraft, base64) is read from the artifact-styling skill's theme.css when present, else cached in reports/ideation/_font.css."""
import re, sys, html, glob, os
HERE = os.path.dirname(os.path.abspath(__file__))
src = sys.argv[1]; out = os.path.splitext(src)[0] + ".html"
md = open(src).read()
e = lambda t: html.escape(t, quote=False)

def font_face():
    cache = os.path.join(HERE, "_font.css")
    for p in glob.glob(os.path.expanduser("~/.claude/skills/synced/*/artifact-styling/theme.css")):
        m = re.search(r"@font-face\{[^}]*\}", open(p).read())
        if m: open(cache, "w").write(m.group(0)); return m.group(0)
    return open(cache).read() if os.path.exists(cache) else ""

def inl(t):
    t = e(t)
    t = re.sub(r"`([^`]+)`", r"<code>\1</code>", t)
    return re.sub(r"\*\*([^*]+)\*\*", r"<b>\1</b>", t)

fm, body = re.match(r"---\n(.*?)\n---\n(.*)", md, re.S).groups()
date = re.search(r"date: (.+)", fm).group(1); sha = re.search(r"based_on: (.+)", fm).group(1)
title = re.search(r"^# (.+)", body, re.M).group(1)
assump = (re.search(r"Assumptions: (.+)", body) or [0, ""])[1]
notes = re.findall(r"^- (.+)", re.search(r"## What I noticed\n(.*?)\n## ", body, re.S).group(1), re.M)
ideas_md = re.search(r"## Ideas\n(.*?)\n## Recommendation", body, re.S).group(1)
rec = re.search(r"## Recommendation\n(.*?)\n## ", body, re.S).group(1).strip()
prompt = re.search(r"## Paste-ready prompt\n```\n(.*?)\n```", body, re.S).group(1)

def field(spec, name, nxt):
    m = re.search(name + r"\s*(.*?)(?=" + nxt + r"|$)", spec, re.S); return m.group(1).strip() if m else ""
ideas = []
for blk in re.split(r"^### ", ideas_md, flags=re.M)[1:]:
    h = re.match(r"(\d+)\. (.+?) \((S|M|L)\)", blk)
    g = lambda lab: (re.search(r"- \*\*" + lab + r":\*\* (.*?)(?=\n- \*\*|\Z)", blk, re.S) or [0, ""])[1].strip()
    spec = g("Spec")
    lab = r"(?: Files:| Config:| \*\*Out of scope:\*\*| \*\*Verification:\*\*| \*\*Placeholders needed:\*\*)"
    goal = spec.split(" Files:")[0]
    files = field(spec, r" Files:", lab.replace(" Files:|", "")); cfg = field(spec, r" Config:", lab)
    ideas.append(dict(n=h.group(2), s=h.group(3), pitch=g("Pitch"), why=g("Why now"), goal=goal, files=files, cfg=cfg,
        oos=field(spec, r"\*\*Out of scope:\*\*", lab), ver=field(spec, r"\*\*Verification:\*\*", lab),
        ph=field(spec, r"\*\*Placeholders needed:\*\*", lab), key=g("Keybind"), risk=g("Risk")))

SIZE = {"S": ("Small", "green"), "M": ("Medium", "gold"), "L": ("Large", "purple")}
def li(items): return "<ul>" + "".join(f"<li>{inl(i)}</li>" for i in items if i.strip()) + "</ul>"
def split_files(t): return re.split(r",\s+(?=`)|\s+\+\s+(?=`)", t.rstrip("."))
def split_ver(t): return [x for x in re.split(r";\s+|:\s+(?=[a-z])", t.rstrip(".")) if x] if ";" in t else [t]

def block(cls, icon, label, content):
    return f'<section class="blk {cls}"><h4><span class="ic">{icon}</span>{label}</h4>{content}</section>'

cards = ""
for i, x in enumerate(ideas, 1):
    sz, col = SIZE[x["s"]]; top = i == 1
    keyline = f'<span class="pill key">⌨ {inl(x["key"])}</span>' if x["key"] and not x["key"].lower().startswith("none") else '<span class="pill">⌨ no key</span>'
    cards += f'''<article class="idea c-{col}{" top" if top else ""}" id="i{i}"><div class="inner">
<header><span class="rank">{i}</span><div class="ttl"><h3>{e(x["n"])}</h3><div class="meta"><span class="pill sz">{x["s"]} · {sz}</span>{keyline}{'<span class="pill topp">✪ TOP PICK</span>' if top else ''}</div></div></header>
<p class="pitch">{inl(x["pitch"])}</p>
<div class="grid2">
{block("aqua","☄","Why now",f"<p>{inl(x['why'])}</p>")}
{block("white","✎","Goal",f"<p>{inl(x['goal'])}</p>")}
</div>
{block("blue","⚒","Files",li(split_files(x["files"])))}
{block("gold","❁","Config",f"<p>{inl(x['cfg'])}</p>")}
<div class="grid2">
{block("gray","✖","Out of scope",f"<p>{inl(x['oos'])}</p>")}
{block("purple","ቾ","Placeholders",f"<p>{inl(x['ph'])}</p>")}
</div>
{block("green","✔","Verification",li(split_ver(x["ver"])))}
{block("red","☠","Risk",f"<p>{inl(x['risk'])}</p>")}
</div></article>
'''
glance = "".join(f'<a class="chip c-{SIZE[x["s"]][1]}{" top" if i==1 else ""}" href="#i{i}"><span class="badge">{x["s"]}</span><b>{e(x["n"])}</b>{"<em>✪ top</em>" if i==1 else ""}<p>{inl(x["pitch"].split(". ")[0].rstrip(".") + ".")}</p></a>' for i, x in enumerate(ideas, 1))
noticed = "".join(f"<li>{inl(n)}</li>" for n in notes)

css = open(os.path.join(HERE, "report.css")).read()
page = f'''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>FI:A ideation {date}</title>
<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Merriweather:ital,wght@0,300;0,400;0,700;1,400&display=swap" rel="stylesheet">
<style>{font_face()}
{css}</style></head><body><div class="glow g1"></div><div class="glow g2"></div>
<main>
<header class="hero"><div class="eyebrow">FRACTURED ISLANDS: ASCENSION · IDEATION</div>
<h1>{e(title.replace("FI:A ideation - ", ""))}</h1>
<p class="sub">based on <code>{sha}</code></p><p class="assump">{inl(assump)}</p></header>

<section class="sec"><h2><i>01</i>At a glance</h2><div class="strip">{glance}</div></section>
<section class="sec"><h2><i>02</i>What I noticed</h2><ol class="notice">{noticed}</ol></section>
<section class="sec"><h2><i>03</i>The ideas</h2>{cards}</section>
<section class="sec"><h2><i>04</i>Recommendation</h2><div class="rec"><p>{inl(rec)}</p></div></section>
<section class="sec"><h2><i>05</i>Paste-ready prompt</h2><div class="promptbox"><div class="bar"><span>/fia-feature</span><button onclick="navigator.clipboard.writeText(document.getElementById('p').textContent);this.textContent='✔ Copied'">Copy prompt</button></div><pre id="p">{e(prompt)}</pre></div></section>
</main></body></html>'''
open(out, "w").write(page); print("wrote", out, len(page))
