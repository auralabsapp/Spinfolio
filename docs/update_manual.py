#!/usr/bin/env python3
"""Régénère la section « Mini-manuel » de docs/index.html à partir du guide de l'app
(Spinlog/Features/Guide/GuideCatalog.swift), pour que la page et l'app disent la même chose.

Usage : python3 docs/update_manual.py
Le contenu entre les marqueurs MANUEL:DEBUT et MANUEL:FIN est remplacé. Aucune dépendance.
"""

import html
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
GUIDE = os.path.join(ROOT, "Spinlog", "Features", "Guide")
PAGE = os.path.join(HERE, "index.html")

BADGES = {
    "premium": '<span class="badge">Premium</span>',
    "requiresAccount": '<span class="badge acc">Compte Discogs</span>',
}


def clean(text):
    """Texte du catalogue → HTML : l'app s'appelait Spinlog dans certaines fiches."""
    return html.escape(text.replace("Spinlog", "Spinfolio").replace('\\"', '"'), quote=False)


def section_titles():
    source = open(os.path.join(GUIDE, "GuideEntry.swift"), encoding="utf-8").read()
    block = source.split("var title: LocalizedStringResource {", 1)[1].split("\n    }", 1)[0]
    return re.findall(r'case \.(\w+): "([^"]+)"', block)


def entries():
    source = open(os.path.join(GUIDE, "GuideCatalog.swift"), encoding="utf-8").read()
    pattern = re.compile(r'GuideEntry\(\s*id: "\w+",\s*section: \.(\w+),(.*?)\n        \)', re.S)
    for match in pattern.finditer(source):
        body = match.group(2)
        title = re.search(r'title: "(.*?)",\n', body)
        summary = re.search(r'summary: "(.*?)",\n', body)
        steps = re.search(r"steps: \[(.*?)\]", body, re.S)
        tip = re.search(r'tip: "(.*?)"(?:,|\n)', body)
        access = re.search(r"access: \.(\w+)", body)
        yield {
            "section": match.group(1),
            "title": title.group(1),
            "summary": summary.group(1),
            "steps": re.findall(r'"(.*?)"(?:,|\s*$)', steps.group(1).strip(), re.S) if steps else [],
            "tip": tip.group(1) if tip else None,
            "access": access.group(1) if access else None,
        }


def render():
    all_entries = list(entries())
    out = []
    for key, title in section_titles():
        group = [e for e in all_entries if e["section"] == key]
        if not group:
            continue
        out.append(f'    <div class="manual-group reveal"><h3>{clean(title)}</h3>')
        for e in group:
            badge = BADGES.get(e["access"], "")
            out.append(f'      <details><summary>{clean(e["title"])}{badge}</summary><div class="body">')
            out.append(f'        <p>{clean(e["summary"])}</p>')
            if e["steps"]:
                items = "".join(f"<li>{clean(s)}</li>" for s in e["steps"])
                out.append(f"        <ol>{items}</ol>")
            if e["tip"]:
                out.append(f'        <p class="tip"><strong>Astuce.</strong> {clean(e["tip"])}</p>')
            out.append("      </div></details>")
        out.append("    </div>")
    return "\n".join(out)


def main():
    page = open(PAGE, encoding="utf-8").read()
    start = page.index("<!-- MANUEL:DEBUT")
    start = page.index("-->", start) + 3
    end = page.index("<!-- MANUEL:FIN -->")
    page = page[:start] + "\n" + render() + "\n" + page[end:]
    open(PAGE, "w", encoding="utf-8").write(page)
    print("Mini-manuel mis à jour :", len(list(entries())), "fiches")


if __name__ == "__main__":
    main()
