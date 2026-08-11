#!/usr/bin/env julia
# broad_validation.jl — validate-before-live gate for the BROAD sleeve (walk-forward / OOS / net-of-cost).
# Reuses broad_target from broad_live.jl. Run:  julia --project=engine live/broad_validation.jl
include(joinpath(@__DIR__, "broad_live.jl"))
include(joinpath(@__DIR__, "_sleeve_validation.jl"))
validate_sleeve(broad_target; label = "BROAD", universe = UNIVERSE, warmup = 180, kind = :directional)
