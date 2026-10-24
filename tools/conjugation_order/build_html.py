#!/usr/bin/env python3
"""conj.json を template.html に埋めて確認表(Artifact 用 HTML)を作る。
使い方: build_html.py conj.json out.html   (Artifact 公開時は capabilities {db: {}}、collection "decisions")
"""
import os
import sys

t = open(os.path.join(os.path.dirname(__file__), "template.html"), encoding="utf-8").read()
d = open(sys.argv[1], encoding="utf-8").read().replace("</", "<\\/")
open(sys.argv[2], "w", encoding="utf-8").write(t.replace("__DATA__", d))
