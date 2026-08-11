#!/bin/bash
# run_broad_daily.sh — broad standalone sleeve (Blaque Baux). DRY-RUN by default (logs the target,
# places nothing) using the shared read-only data keys; graduates to PAPER once ~/.config/blaquebaux/alpaca_broad.env
# exists (that account's own keys). One-time: julia --project=engine -e 'using Pkg; Pkg.instantiate()'.
# Manual dry test:  BB_DRYRUN=1 bash live/run_broad_daily.sh
set -uo pipefail
REPO="/Users/malcolmx/blaquebaux-broad"; ENGINE="$REPO/engine"; JULIA="/Users/malcolmx/.juliaup/bin/julia"
DATAENV="$HOME/.config/blaquebaux/alpaca.env"; SLEEVEENV="$HOME/.config/blaquebaux/alpaca_broad.env"
LOGDIR="$REPO/logs"; mkdir -p "$LOGDIR"; LOG="$LOGDIR/broad_$(TZ=America/New_York date +%Y%m%d).log"
exec >> "$LOG" 2>&1
echo "======== $(TZ=America/New_York date '+%F %T %Z') broad daily run ========"
export BB_LEDGER_PATH="$REPO/alpaca_ledger_broad.sqlite" BB_AUDIT_PATH="$REPO/alpaca_audit_broad.jsonl"
export BB_HWM_PATH="$HOME/.config/blaquebaux/equity_hwm_broad.txt" BB_EQUITY_PATH="$HOME/.config/blaquebaux/equity_last_broad.txt"
if [ -f "$SLEEVEENV" ]; then set -a; source "$SLEEVEENV"; set +a
else [ -f "$DATAENV" ] && { set -a; source "$DATAENV"; set +a; }; export BB_DRYRUN=1; fi
if [ -z "${ALPACA_KEY_ID:-}" ] || [ -z "${ALPACA_SECRET_KEY:-}" ]; then echo "no ALPACA keys — skipping"; exit 0; fi
MODE=$([ "${BB_DRYRUN:-}" = "1" ] && echo dryrun || echo paper); echo "mode=$MODE"
if [ "$MODE" = "paper" ]; then
  CLOCK=$(curl -s --max-time 15 -H "APCA-API-KEY-ID: $ALPACA_KEY_ID" -H "APCA-API-SECRET-KEY: $ALPACA_SECRET_KEY" https://paper-api.alpaca.markets/v2/clock)
  IS_OPEN=$(echo "$CLOCK" | grep -Eo '"is_open":(true|false)' | grep -Eo 'true|false' | head -1)
  NEXT_OPEN=$(echo "$CLOCK" | grep -o '"next_open":"[^"]*"' | grep -Eo '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1)
  ET_TODAY=$(TZ=America/New_York date +%F)
  if { [ -n "$IS_OPEN" ] || [ -n "$NEXT_OPEN" ]; } && [ "$IS_OPEN" != "true" ] && [ "$NEXT_OPEN" != "$ET_TODAY" ]; then echo "not a trading day — skipping"; exit 0; fi
  ORDERS_TODAY=$(curl -s --max-time 15 -H "APCA-API-KEY-ID: $ALPACA_KEY_ID" -H "APCA-API-SECRET-KEY: $ALPACA_SECRET_KEY" "https://paper-api.alpaca.markets/v2/orders?status=all&limit=10&after=${ET_TODAY}T00:00:00Z" | grep -o '"id"' | wc -l | tr -d ' ')
  [ "${ORDERS_TODAY:-0}" -gt 0 ] && { echo "already placed today — skipping (catch-up no-op)"; exit 0; }
fi
cd "$REPO" || exit 1
"$JULIA" --project="$ENGINE" "$REPO/live/broad_live.jl"; RC=$?
echo "======== done rc=$RC $(TZ=America/New_York date '+%T %Z') ========"; exit $RC
