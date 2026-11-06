#!/usr/bin/env python3
"""Summarise a LibreLane run (runs/wokwi/final/metrics.json) and append a row
to reports/sweep.md.

usage: metrics.py <run_dir> <label> [notes]      (prints the summary as JSON)
       metrics.py --summary <run_dir>             (prints JSON only)
"""
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def load_metrics(run_dir):
    p = os.path.join(run_dir, "final", "metrics.json")
    if not os.path.exists(p):
        return {}
    return json.load(open(p))


def first(m, *keys, default=None):
    for k in keys:
        if k in m and m[k] is not None:
            return m[k]
    return default


def worst(m, prefix):
    """Worst (minimum) value over all corners for e.g. timing__setup__ws."""
    vals = [v for k, v in m.items() if (k == prefix or k.startswith(prefix + "__corner:")) and isinstance(v, (int, float))]
    return min(vals) if vals else None


def total(m, prefix):
    vals = [v for k, v in m.items() if k == prefix and isinstance(v, (int, float))]
    return vals[0] if vals else None


def summarise(run_dir):
    m = load_metrics(run_dir)
    cfg = json.load(open(os.path.join(ROOT, "src", "config.json")))
    tiles = re.search(r'tiles:\s*"([^"]+)"', open(os.path.join(ROOT, "info.yaml")).read()).group(1)
    s = {
        "tiles": tiles,
        "clock_period_ns": cfg.get("CLOCK_PERIOD"),
        "pl_target_density_pct": cfg.get("PL_TARGET_DENSITY_PCT"),
        "synth_strategy": cfg.get("SYNTH_STRATEGY", "default"),
        "instances": first(m, "design__instance__count"),
        "stdcell_instances": first(m, "design__instance__count__stdcell"),
        "cell_area_um2": first(m, "design__instance__area__stdcell", "design__instance__area"),
        "core_area_um2": first(m, "design__core__area"),
        "utilization": first(m, "design__instance__utilization__stdcell", "design__instance__utilization"),
        "setup_ws_ns": worst(m, "timing__setup__ws"),
        "setup_tns_ns": worst(m, "timing__setup__tns"),
        "hold_ws_ns": worst(m, "timing__hold__ws"),
        "hold_tns_ns": worst(m, "timing__hold__tns"),
        "setup_violations": total(m, "timing__setup_vio__count"),
        "hold_violations": total(m, "timing__hold_vio__count"),
        "max_slew_violations": total(m, "design__max_slew_violation__count"),
        "max_cap_violations": total(m, "design__max_cap_violation__count"),
        "route_drc_errors": first(m, "route__drc_errors"),
        "magic_drc_errors": first(m, "magic__drc_error__count"),
        "klayout_drc_errors": first(m, "klayout__drc_error__count"),
        "lvs_errors": first(m, "design__lvs_error__count"),
        "antenna_violating_nets": first(m, "antenna__violating__nets"),
        "antenna_violating_pins": first(m, "antenna__violating__pins"),
        "wirelength_um": first(m, "route__wirelength"),
        "metrics_found": bool(m),
    }
    return s


def fmt(v, nd=3):
    if v is None:
        return "-"
    if isinstance(v, float):
        return f"{v:.{nd}f}"
    return str(v)


def append_sweep(s, label, notes):
    path = os.path.join(ROOT, "reports", "sweep.md")
    new = not os.path.exists(path)
    with open(path, "a") as f:
        if new:
            f.write("# Hardening sweep\n\n"
                    "Every hardening iteration of the Tiny Tapeout flow (LibreLane, sky130A). "
                    "WNS/TNS are the worst over all STA corners; DRC = Magic DRC, LVS = netgen.\n\n"
                    "| Iter | Tiles | Clock (ns) | Density % | Cells | Cell area um2 | Util | Setup WNS | Setup TNS | Hold WNS | DRC | LVS | Antenna nets | Notes |\n"
                    "|---|---|---|---|---|---|---|---|---|---|---|---|---|---|\n")
        util = s["utilization"]
        util_s = f"{util*100:.1f}%" if isinstance(util, (int, float)) else "-"
        f.write(f"| {label} | {s['tiles']} | {s['clock_period_ns']} | {s['pl_target_density_pct']} | "
                f"{fmt(s['stdcell_instances'] or s['instances'])} | {fmt(s['cell_area_um2'], 0)} | {util_s} | "
                f"{fmt(s['setup_ws_ns'])} | {fmt(s['setup_tns_ns'])} | {fmt(s['hold_ws_ns'])} | "
                f"{fmt(s['magic_drc_errors'])} | {fmt(s['lvs_errors'])} | {fmt(s['antenna_violating_nets'])} | {notes} |\n")


if __name__ == "__main__":
    if sys.argv[1] == "--summary":
        print(json.dumps(summarise(sys.argv[2]), indent=2))
        sys.exit(0)
    run_dir, label = sys.argv[1], sys.argv[2]
    notes = sys.argv[3] if len(sys.argv) > 3 else ""
    s = summarise(run_dir)
    if not s["metrics_found"]:
        notes = (notes + " (flow failed, no final metrics)").strip()
    append_sweep(s, label, notes)
    print(json.dumps(s, indent=2))
