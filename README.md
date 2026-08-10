# Blaque Baux Broad

**Broad-market and thematic ETF exposure — including leverage — steered by rule, bounded by governance.**

Broad is a member of the Blaque Baux family. The [core repo](https://github.com/Carter-Warrens/blaquebaux)
is the **engine and blueprint**. Broad points that engine at index and thematic ETFs —
`IVES` (AI), `GRNY` (Granny Shots), `QQQ` (Nasdaq-100), and `TQQQ` (3x Nasdaq-100) — trading
broad exposures and the occasional leveraged wrapper, with the engine's governance on the
order path. Leverage here is a sizing choice the safety gate bounds, never a bypass.

> **Not investment advice.** Educational/research software. Leveraged/decay products (e.g.
> TQQQ) can lose value even in a flat market and compound losses in chop. Nothing here is
> validated. See [LICENSE](LICENSE).

```bash
git clone --recursive https://github.com/Carter-Warrens/blaquebaux-broad.git
julia --project=engine -e 'using Pkg; Pkg.instantiate()'   # one-time engine setup
```

## The thesis

Broad ETFs are the cleanest place to express a trend/vol-target rule (deep liquidity, tight
spreads). The catch is leverage: the base's leverage work is explicit that levering a book
past its Kelly point *lowers* growth while deepening drawdown, and daily-reset products like
TQQQ add volatility drag on top. So Broad's job is to hold broad/thematic exposure with a
vol-target that treats a 3x product as 3x risk, not 3x free return.

## Research plan (Path A — not yet built)

- **Trend / vol-target on broad ETFs** — QQQ/broad indices, each vol-targeted; the honest baseline.
- **Leverage decay, measured** — quantify TQQQ's path-dependence vs 3× QQQ (the base's
  `leverage_decision` analysis applied to a daily-reset product); when is the wrapper worth it?
- **Thematic rotation** — IVES / GRNY and peers: cross-thematic momentum, tested beta-neutral
  so it is real rotation and not just market beta (and mindful of their short live histories).

Nothing above is implemented or validated. This is the map, not the territory.

## Status
**Scaffold.** Engine wired as a submodule; strategy research not yet conducted.

## The Blaque Baux family
This repo is one sleeve of the **Blaque Baux** family — a single governed engine steered in
many directions. The [core repo](https://github.com/Carter-Warrens/blaquebaux) is the
base/blueprint and holds the [full family roster](https://github.com/Carter-Warrens/blaquebaux#the-blaque-baux-family).

## Layout
```
engine/     the Blaque Baux platform (git submodule → Carter-Warrens/blaquebaux)
research/   Path-A strategy sketches (to come)
live/       governed live drivers (once a sleeve graduates to paper A/B)
```

## License
[MIT](LICENSE). © 2026 Carter Warrens.
