# _sleeve_validation.jl — shared VALIDATE-BEFORE-LIVE gate for a single sleeve driver.
# A fully causal walk-forward that reuses the driver's OWN target(panel, cap) -> (; net, ...) each
# rebalance (so it validates exactly what the driver trades), holds the net weights, and accrues the
# instrument-level P&L NET OF COSTS. Reports OOS Sharpe/CAGR/maxDD vs the in-sample-fit ceiling and SPY,
# a purged-K-fold OOS consistency check (module_11_cv), and a stated pass/fail bar by sleeve `kind`.
using Dates, Printf, Statistics, LinearAlgebra
include(joinpath(normpath(joinpath(@__DIR__, "..")), "engine", "src", "module_11_cv", "purged_kfold.jl"))
using .PurgedKFold

function fetch_panel(fetchU, lb = 2600)      # request all available history (auto-fit the lookback)
    try
        return panel_at(AlpacaPanelProvider(fetchU; lookback = lb))
    catch e
        m = match(r"only (\d+) common", sprint(showerror, e))
        m === nothing && rethrow(e)
        n = parse(Int, m.captures[1]) - 20   # generous margin (the common-bar count fluctuates a little)
        (n < 80 || n >= lb) && rethrow(e)
        return fetch_panel(fetchU, n)
    end
end

_sh(r; ann = 252) = (x = r[isfinite.(r)]; s = std(x); s > 0 ? mean(x) / s * sqrt(ann) : NaN)
_dd(r) = (lvl = cumprod(1 .+ r); minimum(lvl ./ accumulate(max, lvl) .- 1))
_cagr(r) = (lvl = cumprod(1 .+ r); lvl[end]^(252 / length(r)) - 1)

function validate_sleeve(target; label, universe, warmup, reb = 21,
                         cost_bps = parse(Float64, get(ENV, "BB_COST_BPS", "5")),
                         benchmark = "SPY", kind = :directional)
    fetchU = unique(vcat(universe, benchmark))
    panel = fetch_panel(fetchU)
    R = panel.returns; syms = panel.symbols; T = size(R, 1)
    sidx = Dict(s => i for (i, s) in enumerate(syms)); dummy = ones(length(syms)); cost = cost_bps / 1e4
    subpanel(t) = (returns = R[1:t, :], symbols = syms, prices = dummy)
    bookret(w, day) = sum(get(w, s, 0.0) * R[day, sidx[s]] for s in keys(w); init = 0.0)

    oos = Float64[]; oosidx = Int[]; wprev = Dict{String,Float64}()
    for t0 in warmup:reb:(T-1)
        w = target(subpanel(t0), 1.0).net
        turn = sum(abs(get(w, s, 0.0) - get(wprev, s, 0.0)) for s in union(keys(w), keys(wprev)); init = 0.0)
        for day in (t0+1):min(t0+reb, T)
            r = bookret(w, day); day == t0 + 1 && (r -= turn * cost)
            push!(oos, r); push!(oosidx, day)
        end
        wprev = w
    end
    spy = [R[i, sidx[benchmark]] for i in oosidx]
    beta = var(spy) > 0 ? cov(oos, spy) / var(spy) : 0.0; corr = cor(oos, spy)
    folds = purged_kfold_split(length(oos), PurgedKFoldConfig(; n_splits = 6, embargo_bars = reb); returns = oos)
    fsh = [_sh(oos[f.test_idx]) for f in folds if length(f.test_idx) > 30]
    osh, ssh = _sh(oos), _sh(spy)

    println("="^76, "\n$label — walk-forward OOS validation (net $(round(Int,cost*1e4)) bps/side, kind=$kind)\n", "="^76)
    @printf("\n  OOS days %d  rebalances %d   (warmup %d, reb %d; rule-based sleeve — no fitted params)\n", length(oos), length(warmup:reb:(T-1)), warmup, reb)
    @printf("  %-26s %8s %8s %8s\n", "book", "Sharpe", "CAGR", "maxDD")
    @printf("  %-26s %+8.2f %7.1f%% %7.0f%%\n", "sleeve OOS (net, causal)", osh, _cagr(oos)*100, _dd(oos)*100)
    @printf("  %-26s %+8.2f %7.1f%% %7.0f%%\n", "SPY (same window)", ssh, _cagr(spy)*100, _dd(spy)*100)
    @printf("  beta-SPY %+.2f  corr-SPY %+.2f   purged 6-fold OOS Sharpe: mean %+.2f min %+.2f\n",
            beta, corr, mean(fsh), minimum(fsh))

    # ---- the bar (by kind) ----
    posfold = mean(fsh .> 0)
    checks = if kind == :insurance
        [("anti-correlated to SPY (corr <= -0.20)", corr <= -0.20, @sprintf("%.2f", corr)),
         ("affordable carry (CAGR >= -3%)",         _cagr(oos) >= -0.03, @sprintf("%.1f%%", _cagr(oos)*100)),
         ("shallow own drawdown (maxDD >= -25%)",   _dd(oos) >= -0.25, @sprintf("%.0f%%", _dd(oos)*100))]
    elseif kind == :neutral
        [("OOS net Sharpe >= 0.30",                 osh >= 0.30, @sprintf("%.2f", osh)),
         ("market-neutral (|beta| <= 0.25)",        abs(beta) <= 0.25, @sprintf("%.2f", beta)),
         ("positive in >= 60% of folds",            posfold >= 0.60, @sprintf("%.0f%%", posfold*100))]
    else # directional
        [("OOS net Sharpe >= 0.40",                 osh >= 0.40, @sprintf("%.2f", osh)),
         ("positive in >= 60% of folds",            posfold >= 0.60, @sprintf("%.0f%%", posfold*100))]
    end
    println("\n  THE BAR ($kind):")
    for (n, ok, v) in checks; @printf("    [%s] %-40s %s\n", ok ? "PASS" : "FAIL", n, v); end
    allpass = all(c -> c[2], checks)
    println("\n  VERDICT: ", allpass ? "PASS — clears the bar." : "MIXED — does not fully clear the bar; keep in dry-run.")
    return (; label, osh, ish, ssh, beta, corr, maxdd = _dd(oos), pass = allpass)
end
