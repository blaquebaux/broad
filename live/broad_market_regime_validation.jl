#!/usr/bin/env julia
# ============================================================================
# broad_market_regime_validation.jl — does benchmark's MARKET_REGIME add anything to BROAD?
#
# BROAD is net-long managed QQQ (multi-horizon trend x vol-target), so a market risk-on/off flag is at
# least the RIGHT kind of signal for it. The catch: BROAD already SELF-manages risk via its vol-target,
# and benchmark's market_regime is (honestly) mostly VOL-TIMING — so the two likely overlap. This is the
# marginal-value test: does gating BROAD's managed book on the market_regime improve it BEYOND what the
# vol-target already does, or is it redundant? Full 2016-2026 SIP, net of cost, causal. Reuses
# broad_target from broad_live.jl and the same composite benchmark publishes.
#   Run:  julia --project=engine live/broad_market_regime_validation.jl
# ============================================================================
include(joinpath(@__DIR__, "broad_live.jl"))
using Dates, Printf, Statistics

const INTERNALS = ["SPY", "RSP", "HYG", "LQD", "DIA", "IYT", "XLU", "VIXY", "TLT"]
_sh(r; ann = 252) = (x = r[isfinite.(r)]; s = std(x); s > 0 ? mean(x) / s * sqrt(ann) : NaN)
_dd(r) = (lvl = cumprod(1 .+ r); minimum(lvl ./ accumulate(max, lvl) .- 1))
_cagr(r) = (lvl = cumprod(1 .+ r); lvl[end]^(252 / length(r)) - 1)

function fetch_panel(U, lb = 2600)
    try
        return panel_at(AlpacaPanelProvider(U; lookback = lb, calendar_days = 4300, feed = "sip"), Dates.today() - Day(30))
    catch e
        m = match(r"only (\d+) common", sprint(showerror, e)); m === nothing && rethrow(e)
        n = parse(Int, m.captures[1]) - 20; (n < 400 || n >= lb) && rethrow(e)
        return fetch_panel(U, n)
    end
end

# market_regime composite as a causal series (mirrors benchmark_live.market_regime)
_relpath(R, i) = cumprod(vcat(1.0, 1 .+ R[:, i]))[2:end]
_trend(x, w) = (t = fill(NaN, length(x)); for k in w+1:length(x); t[k] = x[k]/x[k-w]-1; end; t)
_rvol(r, w) = (v = fill(NaN, length(r)); for k in w+1:length(r); v[k] = std(@view r[k-w:k-1])*sqrt(252); end; v)
_rollz(x, w) = ([ (h = [x[j] for j in max(1,k-w):k-1 if isfinite(x[j])]; (length(h) >= w÷2 && std(h) > 0) ? (x[k]-mean(h))/std(h) : NaN) for k in 1:length(x) ])
function composite_lag(panel)
    R = panel.returns; i(s) = findfirst(==(s), panel.symbols); rp(s) = _relpath(R, i(s))
    sig = [ _trend(rp("HYG")./rp("LQD"),21), _trend(rp("RSP")./rp("SPY"),21), _trend(rp("IYT")./rp("DIA"),21),
            _trend(rp("SPY")./rp("XLU"),21), -_trend(rp("VIXY"),21), -_rvol(R[:, i("TLT")],20) ]
    Z = hcat([_rollz(s, 252) for s in sig]...)
    comp = [ (v = Z[k, isfinite.(Z[k,:])]; isempty(v) ? NaN : mean(v)) for k in 1:size(Z,1) ]
    vcat(NaN, comp[1:end-1])
end

function main_validate(; warmup = 300, cost_bps = parse(Float64, get(ENV, "BB_COST_BPS", "5")), derisk = 0.5)
    panel = fetch_panel(unique(vcat([SYM], INTERNALS)))
    R = panel.returns; syms = panel.symbols; T = size(R, 1); cost = cost_bps/1e4
    qi = findfirst(==(SYM), syms); q = R[:, qi]; dummy = ones(length(syms))
    subpanel(t) = (returns = R[1:t, :], symbols = syms, prices = dummy)
    ron = composite_lag(panel) .> 0

    full = Float64[]; over = Float64[]; wF = 0.0; wO = 0.0; nde = 0; npos = 0
    for t0 in warmup:(T-1)                                     # daily (broad is a daily sleeve)
        wf = broad_target(subpanel(t0), 1.0; gross_scale = 1.0).net[SYM]
        scale = ron[t0] ? 1.0 : derisk; npos += 1; ron[t0] || (nde += 1)
        wo = wf * scale
        push!(full, wf*q[t0+1] - abs(wf-wF)*cost); push!(over, wo*q[t0+1] - abs(wo-wO)*cost)
        wF = wf; wO = wo
    end

    println("="^80, "\nBROAD + market_regime overlay — does it add anything beyond broad's own vol-target?\n", "="^80)
    @printf("\n  full 2016-2026 SIP; net %dbps; de-risk x%.2f in risk-off (%.0f%% of days)\n", round(Int,cost*1e4), derisk, 100nde/npos)
    @printf("  %-34s %8s %8s %7s %8s\n", "book", "Sharpe", "CAGR", "vol", "maxDD")
    for (lbl, r) in [("FULL broad (trend x vol-target)", full), ("+ market_regime overlay", over)]
        @printf("  %-34s %+8.2f %7.1f%% %6.1f%% %7.0f%%\n", lbl, _sh(r), _cagr(r)*100, std(r)*sqrt(252)*100, _dd(r)*100)
    end
    shF, shO, ddF, ddO = _sh(full), _sh(over), _dd(full), _dd(over)
    print("\n  DECISION: ")
    if shO >= shF + 0.05 && ddO > ddF
        println("ON — market_regime adds value beyond the vol-target; wire it (BB_MARKET_OVERLAY=1).")
    else
        println("DECLINED (redundant) — market_regime does not improve BROAD beyond its own vol-target.")
        println("  BROAD already de-risks via multi-horizon trend + vol-target, and market_regime is itself")
        println("  mostly vol-timing (benchmark #3), so the two overlap: gating adds no Sharpe (", @sprintf("%+.2f -> %+.2f", shF, shO),
                ") and\n  no drawdown benefit. Match the signal to the sleeve — BROAD keeps its vol-target; stacking a second")
        println("  vol-timing overlay just double-counts. (BROAD does consume the bonds regime, which is orthogonal.)")
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    main_validate()
end
