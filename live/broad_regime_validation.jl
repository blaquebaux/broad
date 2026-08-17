#!/usr/bin/env julia
# ============================================================================
# broad_regime_validation.jl — does the BONDS regime overlay improve BROAD?
#
# BROAD is a net-long managed-QQQ trend sleeve. The claim: de-risking its gross when the
# stock-bond correlation is POSITIVE (bond hedge dead — no diversification cushion) improves
# BROAD's RISK-ADJUSTED outcome vs running its managed gross always.
#
# Fully causal daily walk-forward reusing broad_target (the real book) on QQQ, and the SAME
# 63d SPY-IEF correlation regime the bonds driver publishes. Compares:
#   FULL    — broad at its managed (vol-targeted) gross, always
#   OVERLAY — broad gross x REGIME_DERISK whenever the bond hedge is dead (pos-corr)
# Net of cost. Reuses broad_target + REGIME_DERISK from broad_live.jl.
#   Run:  julia --project=engine live/broad_regime_validation.jl
# ============================================================================
include(joinpath(@__DIR__, "broad_live.jl"))
using Dates, Printf, Statistics

_sh(r; ann = 252) = (x = r[isfinite.(r)]; s = std(x); s > 0 ? mean(x) / s * sqrt(ann) : NaN)
_dd(r) = (lvl = cumprod(1 .+ r); minimum(lvl ./ accumulate(max, lvl) .- 1))
_cagr(r) = (lvl = cumprod(1 .+ r); lvl[end]^(252 / length(r)) - 1)

function fetch_panel(U, lb = 2600)
    try
        return panel_at(AlpacaPanelProvider(U; lookback = lb, calendar_days = 4300, feed = "sip"), Dates.today() - Day(30))
    catch e
        m = match(r"only (\d+) common", sprint(showerror, e)); m === nothing && rethrow(e)
        n = parse(Int, m.captures[1]) - 20; (n < 200 || n >= lb) && rethrow(e)
        return fetch_panel(U, n)
    end
end

function main_validate(; warmup = 160, corr_win = 63,
                       cost_bps = parse(Float64, get(ENV, "BB_COST_BPS", "5")), derisk = REGIME_DERISK)
    panel = fetch_panel([SYM, "SPY", "IEF"])
    R = panel.returns; syms = panel.symbols; T = size(R, 1); cost = cost_bps / 1e4
    qi = findfirst(==(SYM), syms); q = R[:, qi]
    spy = R[:, findfirst(==("SPY"), syms)]; ief = R[:, findfirst(==("IEF"), syms)]
    subpanel(t) = (returns = R[1:t, :], symbols = syms, prices = panel.prices)

    full = Float64[]; over = Float64[]; wF = 0.0; wO = 0.0; npos = 0; nderisk = 0
    for t0 in warmup:(T-1)                          # daily walk-forward (broad is a daily sleeve)
        wf = broad_target(subpanel(t0), 1.0; gross_scale = 1.0).net[SYM]
        corr = cor(spy[t0-corr_win+1:t0], ief[t0-corr_win+1:t0])
        hedge_on = corr < 0; scale = hedge_on ? 1.0 : derisk
        wo = wf * scale
        npos += 1; hedge_on || (nderisk += 1)
        rf = wf * q[t0+1] - abs(wf - wF) * cost
        ro = wo * q[t0+1] - abs(wo - wO) * cost
        push!(full, rf); push!(over, ro); wF = wf; wO = wo
    end

    println("="^78, "\nBROAD + bonds-regime overlay — does de-risking in pos-corr help?\n", "="^78)
    @printf("\n  OOS days %d   de-risked %d (%.0f%%)   derisk x%.2f, net %d bps/side\n",
            length(full), nderisk, 100nderisk/npos, derisk, round(Int, cost*1e4))
    @printf("  %-28s %8s %8s %7s %8s\n", "book", "Sharpe", "CAGR", "vol", "maxDD")
    for (lbl, r) in [("FULL (managed gross)", full), ("OVERLAY (regime de-risk)", over)]
        @printf("  %-28s %+8.2f %7.1f%% %6.1f%% %7.0f%%\n", lbl, _sh(r), _cagr(r)*100, std(r)*sqrt(252)*100, _dd(r)*100)
    end

    shF, shO = _sh(full), _sh(over); ddF, ddO = _dd(full), _dd(over)
    dd_cut = 1 - abs(ddO) / abs(ddF); ret_keep = _cagr(over) / _cagr(full)
    println("\n  THE BAR (overlay must earn its place):")
    checks = [
        ("Sharpe not worse (>= FULL - 0.03)", shO >= shF - 0.03, @sprintf("%.2f vs %.2f", shO, shF)),
        ("reduces max drawdown",              ddO > ddF,          @sprintf("%.0f%% -> %.0f%% (%.0f%% cut)", ddF*100, ddO*100, dd_cut*100)),
        ("retains >= 80% of return",          ret_keep >= 0.80,   @sprintf("%.0f%% kept", ret_keep*100)),
    ]
    for (n, ok, v) in checks; @printf("    [%s] %-36s %s\n", ok ? "PASS" : "FAIL", n, v); end
    allpass = all(c -> c[2], checks)
    println("\n  VERDICT: ", allpass ?
        "PASS — the bonds-regime overlay improves BROAD's risk-adjusted profile. On by default (BB_BONDS_OVERLAY=1)." :
        "MIXED — the overlay does not clearly earn its place on this sample; ships OFF-by-default until it does.")
    return (; pass = allpass, shF, shO, ddF, ddO, dd_cut, ret_keep)
end

if abspath(PROGRAM_FILE) == @__FILE__
    main_validate()
end
