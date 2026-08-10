#!/usr/bin/python3
# =============================================================================
# broad_1_leverage_decay.py — BLAQUE BAUX BROAD #1 (the flagship: is the wrapper worth it?).
#
# Extends the base's leverage_decision to a daily-reset product (TQQQ = 3x QQQ).
# THREE findings:
#   (a) DECAY IS REGIME-DEPENDENT. Over a bull-heavy sample, daily-reset leverage
#       COMPOUNDS: TQQQ actually beat naive 3x(QQQ) in total dollars. But annualized it
#       delivered <3x, at LOWER Sharpe and ~2.3x the drawdown.
#   (b) BUY&HOLD LEVERAGE triples the RUIN, not the Sharpe (UPRO/TQQQ Sharpe < SPY/QQQ).
#   (c) THE DECISIVE TEST — at EQUAL VOL, the wrapper is strictly worse: vol-target QQQ vs
#       TQQQ to the same 20% and TQQQ delivers ~3% less CAGR / 0.12 less Sharpe. TQQQ is
#       NOT free leverage — the daily reset + financing cost money.
#
# RESULTS AS TESTED (2016-2026):
#   $1 -> QQQ $6.79 | naive 3x $18.38 | TQQQ actual $30.41 ; TQQQ CAGR 1.92x QQQ, Sharpe 0.82 vs 0.93
#   buy&hold: SPY 0.88/-34 | QQQ 0.93/-35 | UPRO 0.75/-77 | TQQQ 0.82/-82
#   equal-vol (20%): QQQ 0.91/+18.6%/-29 | TQQQ 0.79/+15.5%/-31
# Read-only.
# =============================================================================
import os, sys
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _broad_common import align, metrics, voltarget

ds, P = align(["QQQ", "TQQQ", "SPY", "UPRO"]); r = {s: P[s][1:] / P[s][:-1] - 1 for s in P}
print("=" * 72, "\nBROAD #1 — leverage decay: is the TQQQ wrapper worth it?\n" + "=" * 72)
q = np.prod(1 + r["QQQ"]); t = np.prod(1 + r["TQQQ"])
print("(a) decay is regime-dependent:")
print(f"    $1 -> QQQ ${q:.2f} | naive 3x(QQQ) ${1+3*(q-1):.2f} | TQQQ actual ${t:.2f}")
print(f"    TQQQ CAGR {metrics(r['TQQQ'])['cagr']*100:+.1f}% = {metrics(r['TQQQ'])['cagr']/metrics(r['QQQ'])['cagr']:.2f}x QQQ (not 3x); "
      f"Sharpe {metrics(r['TQQQ'])['sh']:+.2f} vs QQQ {metrics(r['QQQ'])['sh']:+.2f}")
print("\n(b) buy&hold — leverage triples the ruin, not the Sharpe:")
for s in ["SPY", "QQQ", "UPRO", "TQQQ"]:
    x = metrics(r[s]); print(f"    {s:<5} Sharpe {x['sh']:+.2f}  CAGR {x['cagr']*100:+.1f}%  vol {x['vol']*100:.0f}%  maxDD {x['dd']*100:.0f}%")
print("\n(c) equal-vol (20%) — the decisive test: the wrapper costs money at matched risk:")
for s in ["QQQ", "TQQQ"]:
    x = metrics(voltarget(r[s])); print(f"    {s:<5} vol-targeted 20%: Sharpe {x['sh']:+.2f}  CAGR {x['cagr']*100:+.1f}%  maxDD {x['dd']*100:.0f}%")
print("\nVERDICT: TQQQ is not free leverage. Buy&hold it and you take 3x the drawdown for a")
print("LOWER Sharpe; match its risk to the index and it delivers ~3% less CAGR. For any risk")
print("target, use the unlevered index (managed), not the daily-reset wrapper. See broad_2.")
