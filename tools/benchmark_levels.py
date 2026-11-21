#!/usr/bin/env python3
"""Time level loads and frames in a real window, through autoloads/perf_monitor.gd.

Each level runs in its own Godot process with vsync off and no frame cap, so a frame's time
is what it cost rather than the display's refresh. Needs a display; this is a measurement
tool, not a check, and run_checks.py does not call it.

    python3 tools/benchmark_levels.py --levels 1 8 19 --storm --restart --out before.json
    python3 tools/benchmark_levels.py --levels 1 8 19 --compare before.json
"""

import argparse
import json
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from godot_binary import find_godot_binary  # noqa: E402


ROOT = Path(__file__).resolve().parents[1]
START_SCENE = "res://scenes/screens/main_menu.tscn"
RESOLUTION = "1067x600"
LOAD_SECTIONS = ("scene.change", "floor.bake", "world.rebuild", "world.compose", "world.image", "world.publish")


def run_level(binary: str, level: int, args) -> dict:
    command = [
        binary, "--path", str(ROOT), "--disable-vsync", "--max-fps", "0",
        "--resolution", RESOLUTION, START_SCENE, "--",
        f"--perf-bench={level}", f"--perf-seconds={args.seconds}", f"--perf-mode={args.mode}",
    ]
    if args.storm:
        command.append("--perf-storm")
    if args.restart:
        command.append("--perf-restart")
    if args.preload:
        command.append(f"--perf-preload={args.preload}")
    completed = subprocess.run(command, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=600)
    for line in completed.stdout.splitlines():
        if line.startswith("PERF_RESULT "):
            return json.loads(line[len("PERF_RESULT "):])
    tail = "\n".join(completed.stdout.splitlines()[-30:])
    raise RuntimeError(f"level {level} printed no PERF_RESULT (exit {completed.returncode}):\n{tail}")


def section_ms(load: dict, name: str) -> float:
    entry = load.get("sections", {}).get(name)
    return float(entry[0]) if entry else 0.0


def table(results: list, previous: dict) -> str:
    header = "| Level | Load ms | scene | floor | world | compose | images | publish | Restart ms | p50 | p95 | p99 | max | >=20 ms |"
    rows = [header, "| " + " | ".join(["---"] * (header.count("|") - 1)) + " |"]
    for result in results:
        load = result["load"]
        frames = result.get("frames", {})
        restart = result.get("restart", {}).get("total_ms", "")
        old = previous.get(str(result["level"]))

        def cell(value, key=None, source=None):
            if old is None or key is None:
                return f"{value}"
            before = source(old)
            return f"{value} ({before})" if before not in ("", None) else f"{value}"

        rows.append("| " + " | ".join([
            str(result["level"]),
            cell(load["total_ms"], "load", lambda o: o["load"]["total_ms"]),
            *[f"{section_ms(load, name):.0f}" for name in LOAD_SECTIONS[:-1]],
            f"{section_ms(load, 'world.publish'):.0f}",
            cell(restart, "restart", lambda o: o.get("restart", {}).get("total_ms", "")),
            f"{frames.get('p50_ms', '')}",
            f"{frames.get('p95_ms', '')}",
            cell(frames.get("p99_ms", ""), "p99", lambda o: o.get("frames", {}).get("p99_ms", "")),
            cell(frames.get("max_ms", ""), "max", lambda o: o.get("frames", {}).get("max_ms", "")),
            cell(frames.get("over_20ms", ""), "over", lambda o: o.get("frames", {}).get("over_20ms", "")),
        ]) + " |")
    return "\n".join(rows)


def spikes(results: list) -> str:
    lines = []
    for result in results:
        for spike in result.get("spikes", [])[:5]:
            sections = sorted(spike["sections"].items(), key=lambda item: -item[1][0])[:5]
            named = ", ".join(f"{name} {value[0]} ms x{value[1]}" for name, value in sections)
            render = f", render cpu {spike.get('render_cpu_ms', '?')} / gpu {spike.get('render_gpu_ms', '?')} ms"
            lines.append(f"level {result['level']}: {spike['ms']} ms, {spike['resources']:+d} resources, previous frame's process {spike['process_ms']} ms{render}; {named or 'no section'}")
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--levels", nargs="+", type=int, default=[1, 8, 19])
    parser.add_argument("--seconds", type=float, default=8.0)
    parser.add_argument("--mode", choices=("time", "points"), default="time")
    parser.add_argument("--storm", action="store_true", help="swap one object's state a second")
    parser.add_argument("--restart", action="store_true", help="also time one restart_level()")
    parser.add_argument("--preload", type=float, default=0.0, help="preload the level this many seconds before starting it, as the description screen does")
    parser.add_argument("--runs", type=int, default=1, help="repeat each level and keep every run")
    parser.add_argument("--out", type=Path, help="write the raw results as JSON")
    parser.add_argument("--compare", type=Path, help="show a previous --out file's numbers in brackets")
    args = parser.parse_args()

    binary = find_godot_binary(ROOT)
    results = []
    for level in args.levels:
        for _ in range(args.runs):
            results.append(run_level(binary, level, args))
            print(f"level {level}: load {results[-1]['load']['total_ms']} ms", file=sys.stderr)
    previous = {}
    if args.compare:
        for result in json.loads(args.compare.read_text()):
            previous.setdefault(str(result["level"]), result)
    print(table(results, previous))
    print()
    print(spikes(results))
    if args.out:
        args.out.write_text(json.dumps(results, indent=1) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
