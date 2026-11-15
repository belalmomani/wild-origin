#!/usr/bin/env python3
"""Builds hero_viewer.html: the template + assets/hero/hero.glb embedded as base64. Run: python3 tools/build_hero_html.py"""
import base64, os
root = os.path.join(os.path.dirname(__file__), "..")
glb = open(os.path.join(root, "assets", "hero", "hero.glb"), "rb").read()
tpl = open(os.path.join(os.path.dirname(__file__), "hero_viewer_template.html"), encoding="utf-8").read()
out = os.path.join(root, "hero_viewer.html")
open(out, "w", encoding="utf-8").write(tpl.replace("__GLB_BASE64__", base64.b64encode(glb).decode()))
print("wrote", os.path.abspath(out), os.path.getsize(out) // 1024, "KB")
