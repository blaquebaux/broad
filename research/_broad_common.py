#!/usr/bin/python3
# =============================================================================
# _broad_common.py — shared helpers for the Blaque Baux Broad (broad/thematic ETF) sketches.
# Alpaca SIP daily bars; reads ALPACA_KEY_ID / ALPACA_SECRET_KEY from env. Read-only.
# =============================================================================
import os, json, urllib.request, math
import numpy as np

H = {"APCA-API-KEY-ID": os.environ["ALPACA_KEY_ID"], "APCA-API-SECRET-KEY": os.environ["ALPACA_SECRET_KEY"]}
START, END = "2016-01-01", "2026-08-01"
_cache = {}

def closes(s):
    if s in _cache: return _cache[s]
    u = (f"https://data.alpaca.markets/v2/stocks/bars?symbols={s}&timeframe=1Day"
         f"&start={START}&end={END}&adjustment=all&feed=sip&limit=10000")
    b = json.load(urllib.request.urlopen(urllib.request.Request(u, headers=H), timeout=40)).get("bars", {}).get(s, [])
    _cache[s] = {x["t"][:10]: x["c"] for x in b}
    return _cache[s]

def align(syms):
    D = {s: closes(s) for s in syms}; D = {s: v for s, v in D.items() if len(v) > 300}
    ds = sorted(set.intersection(*[set(v) for v in D.values()]))
    return ds, {s: np.array([D[s][d] for d in ds]) for s in D}

def metrics(r, ppy=252):
    r = np.asarray(r, float); r = r[np.isfinite(r)]
    if len(r) < 30 or r.std() == 0: return dict(sh=float('nan'), cagr=float('nan'), dd=float('nan'), vol=float('nan'))
    cum = np.cumprod(1 + r)
    return dict(sh=r.mean() / r.std() * math.sqrt(ppy), cagr=cum[-1] ** (ppy / len(r)) - 1,
                dd=(cum / np.maximum.accumulate(cum) - 1).min(), vol=r.std() * math.sqrt(ppy))

def ewma_vol(r, hl=30):
    lam = 0.5 ** (1 / hl); v = r[0] ** 2; o = np.empty(len(r))
    for t in range(len(r)):
        v = r[t] ** 2 if t == 0 else lam * v + (1 - lam) * r[t] ** 2
        o[t] = math.sqrt(max(v, 1e-12)) * math.sqrt(252)
    return o

def voltarget(r, tgt=0.20, cap=3.0):
    sc = np.clip(tgt / np.maximum(ewma_vol(r), 1e-6), 0, cap); return sc[:-1] * r[1:]

def trend_vt(base_r, trade_r, tgt=0.20, cap=3.0):
    """Long-only multi-horizon trend on base_r, vol-targeted, traded via trade_r."""
    lvl = np.cumprod(1 + base_r); sig = np.full(len(base_r), np.nan)
    for t in range(120, len(base_r)):
        sig[t] = max(0.0, np.mean([np.sign(lvl[t] / lvl[t - h] - 1) for h in (30, 60, 120)]))
    sc = np.clip(tgt / np.maximum(ewma_vol(trade_r), 1e-6), 0, cap)
    return (sig * sc)[:-1] * trade_r[1:]
