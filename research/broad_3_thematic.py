#!/usr/bin/python3
# =============================================================================
# broad_3_thematic.py — BLAQUE BAUX BROAD #3 (thematic ETFs, inconclusive/weak).
#
# The thesis named thematic ETFs (IVES, GRNY). FINDING: the thematic wrapper adds vol,
# not alpha, and the histories are too short to conclude. IVES (AI theme, 2020+) has a
# much lower Sharpe than plain QQQ at high correlation — it lagged the broad index it
# tilts within. GRNY (2024+) is too short to test. Thematic rotation is not supported
# here; if anything, plain QQQ dominated the AI wrapper over this window.
#
# RESULTS AS TESTED:
#   IVES (2020-2026): Sharpe +0.32 vs QQQ +1.00, corr 0.60   (GRNY too short)
# Read-only.
# =============================================================================
import os, sys
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _broad_common import align, metrics

print("=" * 72, "\nBROAD #3 — thematic ETFs (IVES / GRNY)\n" + "=" * 72)
try:
    ds, P = align(["IVES", "QQQ"]); ri = P["IVES"][1:] / P["IVES"][:-1] - 1; rq = P["QQQ"][1:] / P["QQQ"][:-1] - 1
    print(f"  IVES span {ds[1]}..{ds[-1]} ({len(ri)}d): Sharpe {metrics(ri)['sh']:+.2f}  vs QQQ {metrics(rq)['sh']:+.2f}  "
          f"corr {np.corrcoef(ri, rq)[0, 1]:.2f}")
except Exception as e:
    print("  IVES fetch error:", e)
print("  GRNY: launched 2024-11 — too short to test.")
print("\nVERDICT: inconclusive/weak. The AI thematic wrapper (IVES) lagged plain QQQ at high")
print("correlation; the newer thematics lack history. Broad's edge is the leverage/exposure")
print("management (broad_1/broad_2), not thematic selection.")
