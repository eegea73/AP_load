#!/usr/bin/env python3
"""The generated files must match the reference tables they were generated from.

reference/ is the single source of truth. The SPSS syntax and the browser
calculator cannot read it at run time, so they carry copies of the numbers, and
a copy is only safe if something checks it. This test is that check: edit a
reference table without re-running the generators and it fails here rather than
in somebody's analysis.
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(ROOT, "build"))
import generate_spss
import generate_web

fails = []


def check(label: str, ok: bool, hint: str) -> None:
    print("  %-46s %s" % (label, "ok" if ok else "STALE"))
    if not ok:
        fails.append(hint)


with open(os.path.join(ROOT, "spss", "ap_load2026.sps"), encoding="utf-8") as fh:
    check(
        "spss/ap_load2026.sps",
        generate_spss.render() == fh.read(),
        "python3 build/generate_spss.py",
    )

with open(os.path.join(ROOT, "web", "apload.js"), encoding="utf-8") as fh:
    js = fh.read()
block = re.search(
    re.escape(generate_web.BEGIN) + r".*?" + re.escape(generate_web.END), js, re.S
)
check(
    "web/apload.js reference tables",
    block is not None and block.group(0).strip() == generate_web.build_block().strip(),
    "python3 build/generate_web.py",
)

with open(os.path.join(ROOT, "web", "apload-squarespace.html"), encoding="utf-8") as fh:
    sq = re.search(r"<script>\n(.*)\n</script>", fh.read(), re.S)
check(
    "web/apload-squarespace.html carries that same js",
    sq is not None and sq.group(1).strip() == js.strip(),
    "python3 build/generate_web.py",
)

print()
if fails:
    print("Regenerate and commit:")
    for hint in sorted(set(fails)):
        print("    %s" % hint)
    raise SystemExit(1)
print("Every generated file matches the reference tables.")
