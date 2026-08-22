#!/usr/bin/env julia
# ============================================================================
# broad_rate_regime_validation.jl — does balanced's RATE regime improve BROAD?
#
# BROAD is a net-long, vol-targeted QQQ TREND book — pure long-duration GROWTH. balanced publishes a rate
# regime (rate_regime.txt: rising/falling rates from IEF's 100d trend) with the validated fact that value
# beats growth +12.3%/yr when rates RISE and lags when they fall. The hypothesis worth testing: rising
# rates are a GROWTH headwind, and rate direction may LEAD the growth selloff — a signal BROAD's *reactive*
# trend-following lags. So: de-risk BROAD's gross when rates are rising, and see if it earns its place.
#
# Fully causal daily walk-forward reusing broad_target (the real book) on QQQ, with the SAME IEF-100d-trend
# regime balanced publishes. Compares FULL (managed gross, always) vs OVERLAY (gross × derisk when rates
# rising). Net of cost. Verdict on the family overlay bar + the corrected fat-tail toolkit (JB/Jensen/M²).
#   Run:  julia --project=engine live/broad_rate_regime_validation.jl
# ============================================================================
include(joinpath(@__DIR__, "broad_live.jl"))
using Dates, Printf, Statistics

_sh(r; ann = 252) = (x = r[isfinite.(r)]; s = std(x); s > 0 ? mean(x) / s * sqrt(ann) : NaN)
_dd(r) = (lvl = cumprod(1 .+ r); minimum(lvl ./ accumulate(max, lvl) .- 1))
_cagr(r) = (lvl = cumprod(1 .+ r); lvl[end]^(252 / length(r)) - 1)
function _jb(r); r = r[isfinite.(r)]; n = length(r); m = mean(r); s = std(r); s == 0 && return (p=1.0, skew=0.0, exkurt=0.0, normal=true)
    z = (r .- m)./s; sk = mean(z.^3); ku = mean(z.^4)-3; jb = n/6*(sk^2+ku^2/4); (p=exp(-jb/2), skew=sk, exkurt=ku, normal=(exp(-jb/2)>=0.05)); end
_jensen(r, rb; rf=0.0) = (b = cov(r,rb)/var(rb); (alpha_ann=((mean(r)-rf/252)-b*(mean(rb)-rf/252))*252, beta=b))
_m2(r, rb; rf=0.0) = (shp=(mean(r)-rf/252)/std(r)*sqrt(252); shb=(mean(rb)-rf/252)/std(rb)*sqrt(252); (m2_excess=(shp-shb)*std(rb)*sqrt(252),))  # bench vs itself = 0

function fetch_panel(U, lb = 2600)
    try
        return panel_at(AlpacaPanelProvider(U; lookback = lb, calendar_days = 4300, feed = "sip"), Dates.today() - Day(30))
    catch e
        m = match(r"only (\d+) common", sprint(showerror, e)); m === nothing && rethrow(e)
        n = parse(Int, m.captures[1]) - 20; (n < 400 || n >= lb) && rethrow(e)
        return fetch_panel(U, n)
    end
end

function main_validate(; warmup = 160, ma = 100,
                       cost_bps = parse(Float64, get(ENV, "BB_COST_BPS", "5")),
                       derisk = parse(Float64, get(ENV, "BB_RATE_DERISK", "0.5")))
    panel = fetch_panel([SYM, "IEF", "SPY"])
    R = panel.returns; syms = panel.symbols; T = size(R, 1); cost = cost_bps/1e4
    q = R[:, findfirst(==(SYM), syms)]; spy = R[:, findfirst(==("SPY"), syms)]
    ieflvl = cumprod(vcat(1.0, 1 .+ R[:, findfirst(==("IEF"), syms)]))[2:end]   # IEF relative level (scale-free for the MA cross)
    subpanel(t) = (returns = R[1:t, :], symbols = syms, prices = panel.prices)

    full = Float64[]; over = Float64[]; oosidx = Int[]; wF = 0.0; wO = 0.0; npos = 0; nde = 0
    for t0 in warmup:(T-1)
        wf = broad_target(subpanel(t0), 1.0; gross_scale = 1.0).net[SYM]
        rising = t0 > ma && ieflvl[t0] < mean(@view ieflvl[t0-ma+1:t0])         # IEF below 100d MA → rates rising (growth headwind)
        scale = rising ? derisk : 1.0; npos += 1; rising && (nde += 1)
        wo = wf * scale
        rf = wf * q[t0+1] - abs(wf - wF) * cost
        ro = wo * q[t0+1] - abs(wo - wO) * cost
        push!(full, rf); push!(over, ro); push!(oosidx, t0+1); wF = wf; wO = wo
    end
    spyO = spy[oosidx]

    println("="^80, "\nBROAD + balanced's RATE regime — does de-risking growth when rates rise help?\n", "="^80)
    @printf("\n  full 2016-2026 SIP; net %dbps; de-risk x%.2f when rates RISING (%.0f%% of days)\n", round(Int,cost*1e4), derisk, 100nde/npos)
    @printf("  %-30s %8s %8s %7s %8s\n", "book", "Sharpe", "CAGR", "vol", "maxDD")
    for (lbl, r) in [("FULL (managed gross, always)", full), ("OVERLAY (rate de-risk)", over), ("SPY (reference)", spyO)]
        @printf("  %-30s %+8.2f %7.1f%% %6.1f%% %7.0f%%\n", lbl, _sh(r), _cagr(r)*100, std(r)*sqrt(252)*100, _dd(r)*100)
    end
    println("\n  Fat-tail toolkit (does the overlay improve tail quality Sharpe can't see? — vs SPY):")
    @printf("  %-30s %8s %7s %9s %8s\n", "book", "JB p", "skew", "Jensen α", "M² exc")
    for (lbl, r) in [("FULL", full), ("OVERLAY", over)]
        j = _jb(r); je = _jensen(r, spyO); m = _m2(r, spyO)
        @printf("  %-30s %8.3f %+7.2f %+8.1f%% %+7.1f%%   (%s)\n", lbl, j.p, j.skew, je.alpha_ann*100, m.m2_excess*100, j.normal ? "normal" : "NON-normal")
    end

    shF, shO, ddF, ddO = _sh(full), _sh(over), _dd(full), _dd(over)
    dd_cut = 1 - abs(ddO)/abs(ddF); ret_keep = _cagr(over)/_cagr(full)
    println("\n  THE BAR (overlay must earn its place — family standard):")
    checks = [ ("Sharpe not worse (>= FULL - 0.03)", shO >= shF-0.03, @sprintf("%.2f vs %.2f", shO, shF)),
               ("reduces max drawdown",              ddO > ddF,       @sprintf("%.0f%% -> %.0f%% (%.0f%% cut)", ddF*100, ddO*100, dd_cut*100)),
               ("retains >= 80% of return",          ret_keep >= 0.80, @sprintf("%.0f%% kept", ret_keep*100)) ]
    for (n, ok, v) in checks; @printf("    [%s] %-36s %s\n", ok ? "PASS" : "FAIL", n, v); end
    allpass = all(c -> c[2], checks)
    println("\n  VERDICT: ", allpass ?
        "PASS — the rate regime earns its place on BROAD's growth book; wire it on (BB_RATE_OVERLAY=1)." :
        "MIXED — the rate overlay does not clearly earn its place; BROAD's own trend+vol-target already\n     handles the growth-selloff risk (cf. its declined market_regime). Ships OFF; signal stays published.")
end

if abspath(PROGRAM_FILE) == @__FILE__
    main_validate()
end
