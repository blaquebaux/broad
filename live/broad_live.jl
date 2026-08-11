#!/usr/bin/env julia
# ============================================================================
# broad_live.jl — BLAQUE BAUX BROAD live driver (managed equity-beta exposure).
#
# Runs on the engine (engine/ submodule) — same governed order path + Layer-3 safety gate as the
# spine. Standalone single-sleeve driver.  data(QQQ) -> managed exposure -> [ GATE ] -> order.
#
# SIGNAL (research: the leverage law — never buy-and-hold the daily-reset wrapper; manage exposure on
# the UNLEVERED index). Multi-horizon trend (30/60/120-day sign, long-only fraction) times a vol-target
# on QQQ, capped at 1x (no leverage). Sharpe ~+0.95 / maxDD -16% (vs -35% buy&hold). A managed-beta
# sleeve, not a diversifier; the edge is getting out in downtrends.
#
# MODES: dry-run by default via the wrapper (BB_DRYRUN=1 -> compute + log, NO venue). Paper: unset
# BB_DRYRUN with paper keys. Real money requires BB_LIVE_CONFIRM=I_UNDERSTAND_THIS_IS_REAL_MONEY.
# Kill switch: ~/.config/blaquebaux/HALT.  Run:  julia --project=engine live/broad_live.jl
# NOT validated to the spine's bar — a paper-path graduation of the research.
# ============================================================================
using Dates, Printf, Statistics

const REPO   = normpath(joinpath(@__DIR__, ".."))
const ENGINE = joinpath(REPO, "engine")
include(joinpath(ENGINE, "src/module_7_execution/module_7_execution.jl"))
include(joinpath(ENGINE, "src/module_10_feedback/module_10_feedback.jl"))
include(joinpath(ENGINE, "src/module_13_portfolio/module_13_portfolio.jl"))
include(joinpath(ENGINE, "src/module_1_data/equity_panel.jl"))
include(joinpath(ENGINE, "src/module_1_data/alpaca_panel.jl"))
include(joinpath(ENGINE, "src/module_8_governance/safety_gate.jl"))
using .ExecutionLayer, .FeedbackLayer, .PortfolioOptModule, .EquityPanel, .AlpacaPanel, .SafetyGate
include(joinpath(ENGINE, "scripts/live_execution.jl"))

const SYM = "QQQ"
const UNIVERSE = [SYM]
const LIVE_SENTINEL = "I_UNDERSTAND_THIS_IS_REAL_MONEY"
const VOL_TARGET = 0.15

_readf(p) = isfile(p) ? (v = tryparse(Float64, strip(read(p, String))); v === nothing ? NaN : v) : NaN
_writef(p, x) = (mkpath(dirname(p)); write(p, string(x)))
function ewma_vol_ann(r; hl = 20)
    isempty(r) && return NaN; lam = 0.5^(1/hl); v = float(r[1])^2
    for t in eachindex(r); v = t == 1 ? float(r[t])^2 : lam*v + (1-lam)*float(r[t])^2; end
    sqrt(max(v, 1e-12)) * sqrt(252)
end

function broad_target(panel, cap)
    syms = panel.symbols; R = panel.returns; T = size(R, 1)
    ci = findfirst(==(SYM), syms); q = R[:, ci]; px = panel.prices[ci]
    frac = mean([(prod(1 .+ q[T-h+1:T]) - 1) > 0 ? 1.0 : 0.0 for h in (30, 60, 120)])   # long-only trend fraction
    vol = ewma_vol_ann(q; hl = 20)
    w = clamp(frac * (VOL_TARGET / max(vol, 1e-6)), 0.0, 1.0)                             # no leverage
    (targets = Dict(SYM => round(Float64, w * cap / px)), prices = Dict(SYM => px),
     net = Dict(SYM => w), frac = frac, vol = vol)
end

function main(; capital = nothing, pool = "us", limits::SafetyLimits = SafetyLimits(),
              db_path     = get(ENV, "BB_LEDGER_PATH", joinpath(REPO, "alpaca_ledger_broad.sqlite")),
              audit_path  = get(ENV, "BB_AUDIT_PATH",  joinpath(REPO, "alpaca_audit_broad.jsonl")),
              hwm_path    = get(ENV, "BB_HWM_PATH",    joinpath(homedir(), ".config", "blaquebaux", "equity_hwm_broad.txt")),
              equity_path = get(ENV, "BB_EQUITY_PATH", joinpath(homedir(), ".config", "blaquebaux", "equity_last_broad.txt")))
    (get(ENV, "ALPACA_KEY_ID", "") == "" || get(ENV, "ALPACA_SECRET_KEY", "") == "") &&
        error("Set ALPACA_KEY_ID and ALPACA_SECRET_KEY (read-only bars are needed even in dry-run).")
    dryrun = get(ENV, "BB_DRYRUN", "") in ("1", "true", "yes")
    if dryrun
        panel = panel_at(AlpacaPanelProvider(UNIVERSE; lookback = 200))
        bk = broad_target(panel, capital === nothing ? 100_000.0 : capital)
        @info "BROAD dry run" asof=panel.asof trend_frac=@sprintf("%.0f%%", 100bk.frac) qqq_vol=@sprintf("%.0f%%", 100bk.vol)
        println("\n  BROAD managed QQQ exposure: ", @sprintf("%.0f%%", 100*get(bk.net, SYM, 0.0)),
                " -> ", Int(get(bk.targets, SYM, 0.0)), " sh @ \$", @sprintf("%.2f", get(bk.prices, SYM, NaN)))
        ok, reasons = preflight(; account_status = "ACTIVE", equity = 100_000.0, hwm = 100_000.0, last_equity = 100_000.0,
            buying_power = 100_000.0, data_fresh = (Dates.today() - panel.asof) <= Day(5), targets = bk.targets, prices = bk.prices, limits = limits)
        println("  DRY RUN — no venue, no orders. Gate: ", ok ? "PASS" : "ABORT: " * join(reasons, "; ")); return ok ? :dryrun_ok : :dryrun_gate_abort
    end
    live = get(ENV, "BB_LIVE_CONFIRM", "") == LIVE_SENTINEL; paper = !live; mode = live ? "*** LIVE REAL MONEY ***" : "paper"
    @info "broad_live starting" mode; live && alert("BROAD LIVE REAL-MONEY mode engaged"; level = :critical)
    venue = AlpacaVenue(AlpacaConfig(; paper = paper))
    built = build_live_controller(; venue = venue, ledger_config = LedgerConfig(; db_path = db_path), audit_path = audit_path)
    ctrl, ledger = built.ctrl, built.ledger
    try
        connect!(venue) || (alert("ABORT [$mode]: connect failed (broad)"; level = :critical); return :connect_failed)
        acct = account_info(venue); acct === nothing && (alert("ABORT [$mode]: no account (broad)"; level = :critical); return :no_account)
        cap = capital === nothing ? acct.equity : capital; hwm = max(load_hwm(hwm_path), acct.equity); last_eq = _readf(equity_path)
        panel = panel_at(AlpacaPanelProvider(UNIVERSE; lookback = 200)); fresh = (Dates.today() - panel.asof) <= Day(5)
        bk = broad_target(panel, cap)
        ok, reasons = preflight(; account_status = acct.status, trading_blocked = acct.trading_blocked, account_blocked = acct.account_blocked,
            equity = acct.equity, hwm = hwm, last_equity = last_eq, buying_power = acct.buying_power, data_fresh = fresh, targets = bk.targets, prices = bk.prices, limits = limits)
        save_hwm(hwm, hwm_path); _writef(equity_path, acct.equity)
        !ok && (msg = "SAFETY ABORT [$mode] (broad): " * join(reasons, "; "); @error msg; halt!(ctrl, "safety gate"); alert(msg; level = :critical); return :aborted)
        reset_daily!(ctrl); set_pool_budget!(ctrl, pool, limits.max_gross_leverage * acct.equity); set_pool_loss_limit!(ctrl, pool, limits.max_daily_loss)
        set_pool_staleness!(ctrl, pool, Day(5)); feed_staleness!(ctrl, pool; stale = !fresh); isfinite(last_eq) && update_pnl!(ctrl, pool, acct.equity - last_eq)
        ncanc = cancel_all_open!(venue); ncanc > 0 && sleep(2)
        for (sym, qty) in positions(venue, ctrl.account); apply_fill!(ctrl, sym, qty); end
        res = execute_rebalance!(ctrl, ledger; targets = bk.targets, prices = bk.prices, signal_id = "broad",
            regime = "managed-beta", solve_id = Dates.format(panel.asof, "yyyymmdd"), pool_id = pool, settle_secs = 20)
        !res.reconciled && (alert("RECONCILE FAILED [$mode] (broad)"; level = :critical); halt!(ctrl, "reconcile mismatch"))
        summary = "[$mode] broad; orders=$(length(res.acks)) fills=$(length(res.fills)) reconciled=$(res.reconciled) equity=$(round(Int, acct.equity))"
        @info "broad_live complete" summary; alert(summary; level = :info); return res.reconciled ? :ok : :reconcile_failed
    finally
        disconnect!(venue); close_ledger(ledger)
    end
end
if abspath(PROGRAM_FILE) == @__FILE__; main(); end
