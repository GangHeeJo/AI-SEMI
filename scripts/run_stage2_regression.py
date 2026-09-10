#!/usr/bin/env python3
"""Compile and run the reproducible Stage-2 RTL regression suite."""

from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys
import tempfile
import time
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class HDLTest:
    name: str
    top: str
    rtl: tuple[str, ...]
    tb: str
    marker: str
    compile_args: tuple[str, ...] = ()
    run_args: tuple[str, ...] = ()


@dataclass(frozen=True)
class Result:
    name: str
    passed: bool
    detail: str
    output: str
    seconds: float


def find_repo_root(start: Path) -> Path:
    for candidate in (start, *start.parents):
        if (candidate / "rtl").is_dir() and (candidate / "tb").is_dir():
            return candidate
    raise RuntimeError(f"cannot find repository root above {start}")


def run_process(args: list[str], cwd: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        args,
        cwd=cwd,
        text=True,
        encoding="utf-8",
        errors="replace",
        capture_output=True,
        check=False,
    )


def process_output(process: subprocess.CompletedProcess[str]) -> str:
    chunks = [process.stdout.strip(), process.stderr.strip()]
    return "\n".join(chunk for chunk in chunks if chunk)


def compile_test(
    test: HDLTest,
    root: Path,
    temp_root: Path,
    iverilog: str,
) -> tuple[subprocess.CompletedProcess[str], Path]:
    executable = temp_root / f"{test.name}.vvp"
    args = [
        iverilog,
        "-g2012",
        "-s",
        test.top,
        *test.compile_args,
        "-o",
        str(executable),
        *test.rtl,
        test.tb,
    ]
    return run_process(args, root), executable


def run_hdl_test(
    test: HDLTest,
    root: Path,
    temp_root: Path,
    iverilog: str,
    vvp: str,
    run_cwd: Path | None = None,
) -> Result:
    started = time.perf_counter()
    compile_run, executable = compile_test(test, root, temp_root, iverilog)
    if compile_run.returncode != 0:
        return Result(
            test.name,
            False,
            f"compile exited {compile_run.returncode}",
            process_output(compile_run),
            time.perf_counter() - started,
        )

    simulation = run_process(
        [vvp, str(executable), *test.run_args],
        run_cwd or root,
    )
    output = process_output(compile_run)
    simulation_output = process_output(simulation)
    if simulation_output:
        output = f"{output}\n{simulation_output}".strip()
    if simulation.returncode != 0:
        detail = f"simulation exited {simulation.returncode}"
        passed = False
    elif test.marker not in simulation.stdout:
        detail = f"missing stdout marker {test.marker!r}"
        passed = False
    else:
        detail = test.marker
        passed = True
    return Result(
        test.name,
        passed,
        detail,
        output,
        time.perf_counter() - started,
    )


def run_affine_vectors(
    root: Path,
    temp_root: Path,
    iverilog: str,
    vvp: str,
) -> Result:
    started = time.perf_counter()
    vector_path = temp_root / "tb" / "stage2_affine_vectors.tsv"
    vector_path.parent.mkdir(parents=True, exist_ok=True)
    generator = run_process(
        [
            sys.executable,
            "scripts/gen_stage2_affine_vectors.py",
            "--output",
            str(vector_path),
        ],
        root,
    )
    generator_output = process_output(generator)
    if generator.returncode != 0 or "SELF_CHECK_PASS" not in generator.stdout:
        reason = (
            f"generator exited {generator.returncode}"
            if generator.returncode != 0
            else "missing stdout marker 'SELF_CHECK_PASS'"
        )
        return Result(
            "affine_vectors",
            False,
            reason,
            generator_output,
            time.perf_counter() - started,
        )

    test = HDLTest(
        "affine_vectors_rtl",
        "tb_coord_transform_affine2d",
        ("rtl/coord_transform_affine2d.v",),
        "tb/tb_coord_transform_affine2d.v",
        "COORD_TRANSFORM_AFFINE2D_PASS",
    )
    rtl_result = run_hdl_test(
        test, root, temp_root, iverilog, vvp, run_cwd=temp_root
    )
    return Result(
        "affine_vectors",
        rtl_result.passed,
        rtl_result.detail,
        f"{generator_output}\n{rtl_result.output}".strip(),
        time.perf_counter() - started,
    )


def run_full50(
    root: Path,
    temp_root: Path,
    iverilog: str,
    vvp: str,
) -> Result:
    started = time.perf_counter()
    test = HDLTest(
        "full50_compile",
        "tb_steal_buf_common_trace",
        (
            "rtl/arbiter2.v",
            "rtl/arbiter4_tree.v",
            "rtl/aer_tx16_trad_rowcol_fovea_cluster2_steal_buf.v",
        ),
        "tb/tb_steal_buf_common_trace.v",
        "STEAL_BUF_TRACE_CONSISTENT",
    )
    compile_run, executable = compile_test(test, root, temp_root, iverilog)
    if compile_run.returncode != 0:
        return Result(
            "full50_trace_totals",
            False,
            f"compile exited {compile_run.returncode}",
            process_output(compile_run),
            time.perf_counter() - started,
        )

    traces = sorted((root / "common_traces_full50").glob("*.cyclemask.txt"))
    totals = [0, 0, 0, 0]  # generated, overrun, accepted, delivered
    failures: list[str] = []
    count_pattern = re.compile(
        r"generated=(\d+) overrun=(\d+) accepted=(\d+) delivered=(\d+)"
    )
    for trace in traces:
        relative_trace = trace.relative_to(root).as_posix()
        simulation = run_process(
            [vvp, str(executable), f"+TRACE_FILE={relative_trace}"],
            root,
        )
        match = count_pattern.search(simulation.stdout)
        if simulation.returncode != 0:
            failures.append(f"{trace.name}: exit {simulation.returncode}")
        elif test.marker not in simulation.stdout:
            failures.append(f"{trace.name}: missing {test.marker}")
        elif match is None:
            failures.append(f"{trace.name}: missing count summary")
        if match is not None:
            for index, value in enumerate(match.groups()):
                totals[index] += int(value)

    expected = (106416, 502, 105914, 105914)
    if len(traces) != 50:
        failures.append(f"expected 50 traces, found {len(traces)}")
    if tuple(totals) != expected:
        failures.append(f"totals {tuple(totals)} != expected {expected}")
    detail = (
        f"traces={len(traces)} generated={totals[0]} overrun={totals[1]} "
        f"accepted={totals[2]} delivered={totals[3]}"
    )
    return Result(
        "full50_trace_totals",
        not failures,
        detail if not failures else "; ".join(failures),
        process_output(compile_run),
        time.perf_counter() - started,
    )


def regular_tests() -> tuple[HDLTest, ...]:
    return (
        HDLTest(
            "m0_latency",
            "tb_stage2_m0_latency_skew",
            (
                "rtl/arbiter2.v",
                "rtl/arbiter4_tree.v",
                "rtl/aer_tx16_trad_rowcol_fovea_cluster2_steal_buf_polarity.v",
            ),
            "tb/tb_stage2_m0_latency_skew.v",
            "STAGE2_M0_PASS",
        ),
        HDLTest(
            "pose_timestamp_aer",
            "tb_steal_buf_polarity_pose_correctness",
            (
                "rtl/arbiter2.v",
                "rtl/arbiter4_tree.v",
                "rtl/aer_tx16_trad_rowcol_fovea_cluster2_steal_buf_polarity.v",
                "rtl/aer_tx16_trad_rowcol_fovea_cluster2_steal_buf_polarity_pose.v",
            ),
            "tb/tb_steal_buf_polarity_pose_correctness.v",
            "STEAL_BUF_POLARITY_POSE_TIMESTAMP_PASS",
        ),
        HDLTest(
            "pose_history",
            "tb_pose_history_affine8",
            ("rtl/pose_history_affine8.v",),
            "tb/tb_pose_history_affine8.v",
            "POSE_HISTORY_AFFINE8_PASS",
        ),
        HDLTest(
            "pose_guard",
            "tb_pose_inflight_guard8",
            ("rtl/pose_inflight_guard8.v",),
            "tb/tb_pose_inflight_guard8.v",
            "POSE_INFLIGHT_GUARD8_PASS",
        ),
        HDLTest(
            "affine_backpressure",
            "tb_coord_transform_affine2d_backpressure",
            ("rtl/coord_transform_affine2d.v",),
            "tb/tb_coord_transform_affine2d_backpressure.v",
            "COORD_TRANSFORM_AFFINE2D_BACKPRESSURE_PASS",
        ),
        HDLTest(
            "aer_4x4_e2e",
            "tb_aer_tx16_pose_affine2d_e2e",
            (
                "rtl/arbiter2.v",
                "rtl/arbiter4_tree.v",
                "rtl/aer_tx16_trad_rowcol_fovea_cluster2_steal_buf_polarity_pose.v",
                "rtl/aer_bitmap_to_event8_pose.v",
                "rtl/pose_inflight_guard8.v",
                "rtl/pose_history_affine8.v",
                "rtl/coord_transform_affine2d.v",
                "rtl/aer_tx16_pose_affine2d.v",
            ),
            "tb/tb_aer_tx16_pose_affine2d_e2e.v",
            "AER_TX16_POSE_AFFINE2D_E2E_PASS",
        ),
        HDLTest(
            "aer_4x4_serial_e2e",
            "tb_aer_tx16_pose_affine2d_serial",
            (
                "rtl/arbiter2.v",
                "rtl/arbiter4_tree.v",
                "rtl/aer_tx16_trad_rowcol_fovea_cluster2_steal_buf_polarity_pose.v",
                "rtl/aer_bitmap_to_event8_pose.v",
                "rtl/event_batch_fifo.v",
                "rtl/pose_inflight_guard8.v",
                "rtl/pose_history_affine8.v",
                "rtl/coord_transform_affine2d.v",
                "rtl/aer_tx16_pose_affine2d_serial.v",
            ),
            "tb/tb_aer_tx16_pose_affine2d_serial.v",
            "AER_TX16_POSE_AFFINE2D_SERIAL_PASS",
        ),
        HDLTest(
            "k1_k8_comparison",
            "tb_stage2_k1_k8_comparison",
            (
                "rtl/arbiter2.v",
                "rtl/arbiter4_tree.v",
                "rtl/aer_tx16_trad_rowcol_fovea_cluster2_steal_buf_polarity_pose.v",
                "rtl/aer_bitmap_to_event8_pose.v",
                "rtl/event_batch_fifo.v",
                "rtl/pose_inflight_guard8.v",
                "rtl/pose_history_affine8.v",
                "rtl/coord_transform_affine2d.v",
                "rtl/aer_tx16_pose_affine2d.v",
                "rtl/aer_tx16_pose_affine2d_serial.v",
            ),
            "tb/tb_stage2_k1_k8_comparison.v",
            "STAGE2_K1_K8_COMPARISON_PASS",
        ),
        HDLTest(
            "event_batch_fifo",
            "tb_event_batch_fifo",
            ("rtl/event_batch_fifo.v",),
            "tb/tb_event_batch_fifo.v",
            "EVENT_BATCH_FIFO_PASS",
            ("-Ptb_event_batch_fifo.DEPTH=32",),
        ),
        HDLTest(
            "rr_stream_arbiter4",
            "tb_rr_stream_arbiter4",
            ("rtl/rr_stream_arbiter4.v",),
            "tb/tb_rr_stream_arbiter4.v",
            "RR_STREAM_ARBITER4_PASS",
            ("-Ptb_rr_stream_arbiter4.DATA_W=32",),
        ),
        HDLTest(
            "aer_8x8_serial_e2e",
            "tb_aer_tx64_pose_affine2d_serial",
            (
                "rtl/arbiter2.v",
                "rtl/arbiter4_tree.v",
                "rtl/aer_tx16_trad_rowcol_fovea_cluster2_steal_buf_polarity_pose.v",
                "rtl/aer_bitmap_to_event8_pose.v",
                "rtl/event_batch_fifo.v",
                "rtl/rr_stream_arbiter4.v",
                "rtl/pose_inflight_guard8.v",
                "rtl/pose_history_affine8.v",
                "rtl/coord_transform_affine2d.v",
                "rtl/aer_tx64_pose_affine2d_serial.v",
            ),
            "tb/tb_aer_tx64_pose_affine2d_serial.v",
            "AER_TX64_POSE_AFFINE2D_SERIAL_PASS",
        ),
        HDLTest(
            "world_time_surface",
            "tb_world_time_surface",
            ("rtl/world_time_surface.v",),
            "tb/tb_world_time_surface.v",
            "WORLD_TIME_SURFACE_PASS",
        ),
        HDLTest(
            "world_time_surface_random",
            "tb_world_time_surface_random",
            ("rtl/world_time_surface.v",),
            "tb/tb_world_time_surface_random.v",
            "WORLD_TIME_SURFACE_RANDOM_PASS",
        ),
        HDLTest(
            "aer_8x8_pose_time_surface",
            "tb_aer_tx64_pose_time_surface",
            (
                "rtl/arbiter2.v",
                "rtl/arbiter4_tree.v",
                "rtl/aer_tx16_trad_rowcol_fovea_cluster2_steal_buf_polarity_pose.v",
                "rtl/aer_bitmap_to_event8_pose.v",
                "rtl/event_batch_fifo.v",
                "rtl/rr_stream_arbiter4.v",
                "rtl/pose_inflight_guard8.v",
                "rtl/pose_history_affine8.v",
                "rtl/coord_transform_affine2d.v",
                "rtl/aer_tx64_pose_affine2d_serial.v",
                "rtl/world_time_surface.v",
                "rtl/aer_tx64_pose_time_surface.v",
            ),
            "tb/tb_aer_tx64_pose_time_surface.v",
            "AER_TX64_POSE_TIME_SURFACE_PASS",
        ),
    )


def extended_tests(root: Path) -> tuple[HDLTest, ...]:
    trace = "common_traces_uzh/uzh_shapes_rotation_patch.addrpol.txt"
    return (
        HDLTest(
            "uzh_polarity_trace",
            "tb_steal_buf_polarity_uzh_trace",
            (
                "rtl/arbiter2.v",
                "rtl/arbiter4_tree.v",
                "rtl/aer_tx16_trad_rowcol_fovea_cluster2_steal_buf_polarity.v",
            ),
            "tb/tb_steal_buf_polarity_uzh_trace.v",
            "STEAL_BUF_POLARITY_UZH_PASS",
            run_args=(f"+TRACE_FILE={trace}",),
        ),
        HDLTest(
            "aer_8x8_serial_random_stress",
            "tb_aer_tx64_pose_affine2d_serial_random",
            (
                "rtl/arbiter2.v",
                "rtl/arbiter4_tree.v",
                "rtl/aer_tx16_trad_rowcol_fovea_cluster2_steal_buf_polarity_pose.v",
                "rtl/aer_bitmap_to_event8_pose.v",
                "rtl/event_batch_fifo.v",
                "rtl/rr_stream_arbiter4.v",
                "rtl/pose_inflight_guard8.v",
                "rtl/pose_history_affine8.v",
                "rtl/coord_transform_affine2d.v",
                "rtl/aer_tx64_pose_affine2d_serial.v",
            ),
            "tb/tb_aer_tx64_pose_affine2d_serial_random.v",
            "AER_TX64_POSE_AFFINE2D_SERIAL_RANDOM_PASS",
        ),
    )


def print_result(result: Result) -> None:
    label = "PASS" if result.passed else "FAIL"
    print(f"[{label}] {result.name} ({result.seconds:.2f}s) - {result.detail}")
    if not result.passed and result.output:
        lines = result.output.splitlines()
        for line in lines[-40:]:
            print(f"       {line}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--extended",
        action="store_true",
        help="also run the slower UZH and 50-trace suites",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        root = find_repo_root(Path(__file__).resolve().parent)
    except RuntimeError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1

    iverilog = shutil.which("iverilog")
    vvp = shutil.which("vvp")
    missing = [
        name
        for name, executable in (("iverilog", iverilog), ("vvp", vvp))
        if executable is None
    ]
    if missing:
        print(
            f"ERROR: missing required executable(s): {', '.join(missing)}",
            file=sys.stderr,
        )
        return 1

    results: list[Result] = []
    with tempfile.TemporaryDirectory(prefix="ai-semi-stage2-") as temp_name:
        temp_root = Path(temp_name)
        tests = regular_tests()
        for test in tests[:4]:
            result = run_hdl_test(test, root, temp_root, iverilog, vvp)
            results.append(result)
            print_result(result)

        result = run_affine_vectors(root, temp_root, iverilog, vvp)
        results.append(result)
        print_result(result)

        for test in tests[4:]:
            result = run_hdl_test(test, root, temp_root, iverilog, vvp)
            results.append(result)
            print_result(result)

        if args.extended:
            for test in extended_tests(root):
                result = run_hdl_test(test, root, temp_root, iverilog, vvp)
                results.append(result)
                print_result(result)
            result = run_full50(root, temp_root, iverilog, vvp)
            results.append(result)
            print_result(result)

    passed = sum(result.passed for result in results)
    print(f"\nStage-2 regression: {passed}/{len(results)} tests passed")
    return 0 if passed == len(results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
