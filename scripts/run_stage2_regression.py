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


def run_uzh_physical_vectors(
    root: Path,
    temp_root: Path,
    iverilog: str,
    vvp: str,
) -> Result:
    started = time.perf_counter()
    vector_path = temp_root / "tb" / "uzh_physical_affine_vectors.tsv"
    vector_path.parent.mkdir(parents=True, exist_ok=True)
    generator = run_process(
        [
            sys.executable,
            "scripts/gen_uzh_physical_affine_vectors.py",
            "--output",
            str(vector_path),
        ],
        root,
    )
    generator_output = process_output(generator)
    if (
        generator.returncode != 0
        or "UZH_PHYSICAL_ORACLE_PASS" not in generator.stdout
    ):
        reason = (
            f"generator exited {generator.returncode}"
            if generator.returncode != 0
            else "missing stdout marker 'UZH_PHYSICAL_ORACLE_PASS'"
        )
        return Result(
            "uzh_physical_affine",
            False,
            reason,
            generator_output,
            time.perf_counter() - started,
        )

    test = HDLTest(
        "uzh_physical_affine_rtl",
        "tb_coord_transform_affine2d_uzh_physical",
        ("rtl/coord_transform_affine2d.v",),
        "tb/tb_coord_transform_affine2d_uzh_physical.v",
        "UZH_PHYSICAL_AFFINE_RTL_PASS",
    )
    rtl_result = run_hdl_test(
        test, root, temp_root, iverilog, vvp, run_cwd=temp_root
    )
    return Result(
        "uzh_physical_affine",
        rtl_result.passed,
        rtl_result.detail,
        f"{generator_output}\n{rtl_result.output}".strip(),
        time.perf_counter() - started,
    )


def run_uzh_dual_region_vectors(
    root: Path,
    temp_root: Path,
    iverilog: str,
    vvp: str,
) -> Result:
    started = time.perf_counter()
    vector_path = temp_root / "tb" / "uzh_dual_region_vectors.tsv"
    vector_path.parent.mkdir(parents=True, exist_ok=True)
    generator = run_process(
        [
            sys.executable,
            "scripts/gen_uzh_dual_region_vectors.py",
            "--output",
            str(vector_path),
        ],
        root,
    )
    generator_output = process_output(generator)
    marker = "UZH_DUAL_REGION_ORACLE_PASS"
    if generator.returncode != 0 or marker not in generator.stdout:
        reason = (
            f"generator exited {generator.returncode}"
            if generator.returncode != 0
            else f"missing stdout marker '{marker}'"
        )
        return Result(
            "uzh_dual_region_affine",
            False,
            reason,
            generator_output,
            time.perf_counter() - started,
        )

    test = HDLTest(
        "uzh_dual_region_affine_rtl",
        "tb_aer_tx128_region_pose_affine2d_dual_uzh",
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
            "rtl/affine_region_pose_loader.v",
            "rtl/aer_tx128_region_pose_affine2d_dual.v",
        ),
        "tb/tb_aer_tx128_region_pose_affine2d_dual_uzh.v",
        "UZH_DUAL_REGION_RTL_PASS",
    )
    rtl_result = run_hdl_test(
        test, root, temp_root, iverilog, vvp, run_cwd=temp_root
    )
    return Result(
        "uzh_dual_region_affine",
        rtl_result.passed,
        rtl_result.detail,
        f"{generator_output}\n{rtl_result.output}".strip(),
        time.perf_counter() - started,
    )


def run_uzh_200mhz_memory_sweep(
    root: Path,
    temp_root: Path,
    iverilog: str,
    vvp: str,
) -> Result:
    started = time.perf_counter()
    trace_path = temp_root / "tb" / "uzh_200mhz.addrpol.txt"
    trace_path.parent.mkdir(parents=True, exist_ok=True)
    generator = run_process(
        [
            sys.executable,
            "scripts/gen_uzh_200mhz_trace.py",
            "--output",
            str(trace_path),
        ],
        root,
    )
    generator_output = process_output(generator)
    marker = "UZH_200MHZ_TRACE_PASS"
    if generator.returncode != 0 or marker not in generator.stdout:
        reason = (
            f"generator exited {generator.returncode}"
            if generator.returncode != 0
            else f"missing stdout marker {marker!r}"
        )
        return Result(
            "uzh_200mhz_memory_sweep",
            False,
            reason,
            generator_output,
            time.perf_counter() - started,
        )

    dependencies = (
        "rtl/arbiter2.v",
        "rtl/arbiter4_tree.v",
        "rtl/aer_tx16_trad_rowcol_fovea_cluster2_steal_buf_polarity_pose.v",
        "rtl/aer_bitmap_to_event8_pose.v",
        "rtl/event_batch_fifo.v",
        "rtl/pose_inflight_guard8.v",
        "rtl/pose_history_affine8.v",
        "rtl/coord_transform_affine2d.v",
        "rtl/aer_tx16_pose_affine2d_banked.v",
        "rtl/rr_stream_arbiter4.v",
        "rtl/world_time_surface_sram_writer.v",
        "rtl/world_time_surface_sram_banked4.v",
        "rtl/aer_tx16_pose_affine2d_k4_sram_surface.v",
    )
    outputs = [generator_output]
    summaries: list[str] = []
    failures: list[str] = []
    for delay in (0, 2, 8, 32):
        test = HDLTest(
            f"uzh_200mhz_memory_d{delay}",
            "tb_aer_tx16_pose_affine2d_k4_sram_surface_uzh_200mhz",
            dependencies,
            "tb/tb_aer_tx16_pose_affine2d_k4_sram_surface_uzh_200mhz.v",
            "STAGE2_K4_SRAM_UZH_200MHZ_PASS",
            (
                "-Ptb_aer_tx16_pose_affine2d_k4_sram_surface_uzh_200mhz."
                f"MEM_RESPONSE_DELAY={delay}",
            ),
            (f"+TRACE_FILE={trace_path}",),
        )
        result = run_hdl_test(
            test, root, temp_root, iverilog, vvp, run_cwd=temp_root
        )
        outputs.append(f"MEM_RESPONSE_DELAY={delay}\n{result.output}")
        if not result.passed:
            failures.append(f"d{delay}: {result.detail}")
            continue
        counts = re.search(
            r"UZH_200MHZ_MEMORY_COUNTS .*aer_overrun=(\d+) "
            r"fifo_overflow=(\d+)",
            result.output,
        )
        latency = re.search(
            r"UZH_200MHZ_MEMORY_LATENCY population=\d+ mean=(\d+) "
            r"p50=(\d+) p99=(\d+) max=(\d+)",
            result.output,
        )
        if counts is None or latency is None:
            failures.append(f"d{delay}: missing counts/latency receipt")
        else:
            summaries.append(
                f"d{delay}:loss={counts.group(1)}/{counts.group(2)},"
                f"lat={latency.group(1)}/{latency.group(2)}/"
                f"{latency.group(3)}/{latency.group(4)}"
            )

    passed = not failures
    detail = ", ".join(summaries) if passed else "; ".join(failures)
    return Result(
        "uzh_200mhz_memory_sweep",
        passed,
        detail,
        "\n".join(outputs),
        time.perf_counter() - started,
    )


def run_full_sensor_affine_sweep(root: Path) -> Result:
    started = time.perf_counter()
    marker = "UZH_FULL_SENSOR_SAMPLED_REGION_SWEEP_PASS"
    outputs: list[str] = []
    passed_sides: list[int] = []
    failed_detail = ""
    for region_side in (4, 8):
        sweep = run_process(
            [
                sys.executable,
                "scripts/sweep_uzh_full_sensor_affine.py",
                "--tile-side",
                str(region_side),
                *(["--skip-global-baseline"] if region_side == 8 else []),
            ],
            root,
        )
        outputs.append(process_output(sweep))
        if sweep.returncode != 0:
            failed_detail = (
                f"{region_side}x{region_side} sweep exited "
                f"{sweep.returncode}"
            )
            break
        if (
            marker not in sweep.stdout
            or f"tile={region_side} " not in sweep.stdout
        ):
            failed_detail = (
                f"{region_side}x{region_side} sweep missing identity/PASS marker"
            )
            break
        passed_sides.append(region_side)
    passed = passed_sides == [4, 8]
    detail = (
        "4x4 and 8x8 sampled region sweeps passed"
        if passed else failed_detail
    )
    return Result(
        "uzh_full_sensor_region_affine_sweep",
        passed,
        detail,
        "\n".join(output for output in outputs if output),
        time.perf_counter() - started,
    )


def run_synthesis_elaboration(
    root: Path,
    temp_root: Path,
    iverilog: str,
) -> Result:
    started = time.perf_counter()
    common_rtl = (
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
        "rtl/aer_tx16_pose_affine2d_banked.v",
        "rtl/rr_stream_arbiter4.v",
        "rtl/aer_tx16_pose_affine2d_k4_serial.v",
        "rtl/aer_tx64_pose_affine2d_serial.v",
        "rtl/world_time_surface_sram_writer.v",
        "rtl/world_time_surface_sram_banked4.v",
        "rtl/aer_tx16_pose_affine2d_k4_sram_surface.v",
        "rtl/affine_region_pose_loader.v",
        "rtl/aer_tx128_region_pose_affine2d_dual.v",
        "rtl/pose_epoch_count_guard2.v",
        "rtl/affine_region_coeff_table2.v",
        "rtl/region_affine_shared_lane.v",
        "rtl/serialized_sensor_region_affine2d.v",
        "rtl/aer_region8x8_event_stream.v",
        "rtl/rr_stream_merge16.v",
        "rtl/aer_tx256_region_shared_affine.v",
    )
    configurations = (
        ("k8", "aer_tx16_pose_affine2d", ()),
        ("k1_d32", "aer_tx16_pose_affine2d_serial", ()),
        ("k1_d128", "aer_tx16_pose_affine2d_serial",
         ("-Paer_tx16_pose_affine2d_serial.FIFO_DEPTH=128",)),
        ("k2_d32", "aer_tx16_pose_affine2d_banked", (
            "-Paer_tx16_pose_affine2d_banked.K=2",
            "-Paer_tx16_pose_affine2d_banked.FIFO_DEPTH=32",
        )),
        ("k4_d8", "aer_tx16_pose_affine2d_banked", (
            "-Paer_tx16_pose_affine2d_banked.K=4",
            "-Paer_tx16_pose_affine2d_banked.FIFO_DEPTH=8",
        )),
        ("k4_serial_d32", "aer_tx16_pose_affine2d_k4_serial", (
            "-Paer_tx16_pose_affine2d_k4_serial.FIFO_DEPTH=32",
        )),
        ("k4_banked_surface", "aer_tx16_pose_affine2d_k4_sram_surface", ()),
        ("tx64_k1", "aer_tx64_pose_affine2d_serial", ()),
        ("region_loader_690", "affine_region_pose_loader", ()),
        ("tx128_dual_region", "aer_tx128_region_pose_affine2d_dual", ()),
        ("pose_epoch_count_guard2", "pose_epoch_count_guard2", ()),
        ("region_coeff_table_690", "affine_region_coeff_table2", ()),
        ("region_shared_lane", "region_affine_shared_lane", ()),
        ("serialized_sensor_region", "serialized_sensor_region_affine2d", ()),
        ("aer_region8x8_stream", "aer_region8x8_event_stream", ()),
        ("rr_stream_merge16", "rr_stream_merge16", ()),
        ("tx256_region_shared", "aer_tx256_region_shared_affine", ()),
    )
    failures: list[str] = []
    outputs: list[str] = []
    for name, top, parameters in configurations:
        executable = temp_root / f"synthesis_{name}.vvp"
        compile_run = run_process(
            [
                iverilog,
                "-g2005",
                "-s",
                top,
                *parameters,
                "-o",
                str(executable),
                *common_rtl,
            ],
            root,
        )
        output = process_output(compile_run)
        if output:
            outputs.append(f"[{name}]\n{output}")
        if compile_run.returncode != 0:
            failures.append(f"{name}: compile exited {compile_run.returncode}")

    return Result(
        "synthesis_elaboration",
        not failures,
        "17/17 Verilog-2005 tops elaborated" if not failures
        else "; ".join(failures),
        "\n".join(outputs),
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
            "region_pose_loader_small",
            "tb_affine_region_pose_loader",
            ("rtl/affine_region_pose_loader.v",),
            "tb/tb_affine_region_pose_loader.v",
            "AFFINE_REGION_POSE_LOADER_PASS",
        ),
        HDLTest(
            "region_pose_loader_690",
            "tb_affine_region_pose_loader",
            ("rtl/affine_region_pose_loader.v",),
            "tb/tb_affine_region_pose_loader.v",
            "AFFINE_REGION_POSE_LOADER_PASS",
            (
                "-Ptb_affine_region_pose_loader.REGION_COLS=30",
                "-Ptb_affine_region_pose_loader.REGION_ROWS=23",
            ),
        ),
        HDLTest(
            "pose_epoch_count_guard2",
            "tb_pose_epoch_count_guard2",
            ("rtl/pose_epoch_count_guard2.v",),
            "tb/tb_pose_epoch_count_guard2.v",
            "POSE_EPOCH_COUNT_GUARD2_PASS",
        ),
        HDLTest(
            "affine_region_coeff_table2",
            "tb_affine_region_coeff_table2",
            (
                "rtl/affine_region_pose_loader.v",
                "rtl/affine_region_coeff_table2.v",
            ),
            "tb/tb_affine_region_coeff_table2.v",
            "AFFINE_REGION_COEFF_TABLE2_PASS",
        ),
        HDLTest(
            "region_affine_shared_lane",
            "tb_region_affine_shared_lane",
            (
                "rtl/affine_region_pose_loader.v",
                "rtl/affine_region_coeff_table2.v",
                "rtl/pose_epoch_count_guard2.v",
                "rtl/coord_transform_affine2d.v",
                "rtl/region_affine_shared_lane.v",
            ),
            "tb/tb_region_affine_shared_lane.v",
            "REGION_AFFINE_SHARED_LANE_PASS",
        ),
        HDLTest(
            "serialized_sensor_region_affine",
            "tb_serialized_sensor_region_affine2d",
            (
                "rtl/affine_region_pose_loader.v",
                "rtl/affine_region_coeff_table2.v",
                "rtl/pose_epoch_count_guard2.v",
                "rtl/coord_transform_affine2d.v",
                "rtl/region_affine_shared_lane.v",
                "rtl/serialized_sensor_region_affine2d.v",
            ),
            "tb/tb_serialized_sensor_region_affine2d.v",
            "SERIALIZED_SENSOR_REGION_AFFINE2D_PASS",
        ),
        HDLTest(
            "aer_region8x8_event_stream",
            "tb_aer_region8x8_event_stream",
            (
                "rtl/arbiter2.v",
                "rtl/arbiter4_tree.v",
                "rtl/aer_tx16_trad_rowcol_fovea_cluster2_steal_buf_polarity_pose.v",
                "rtl/aer_bitmap_to_event8_pose.v",
                "rtl/event_batch_fifo.v",
                "rtl/rr_stream_arbiter4.v",
                "rtl/aer_region8x8_event_stream.v",
            ),
            "tb/tb_aer_region8x8_event_stream.v",
            "AER_REGION8X8_EVENT_STREAM_PASS",
        ),
        HDLTest(
            "aer_region8x8_event_stream_edge",
            "tb_aer_region8x8_event_stream_edge",
            (
                "rtl/arbiter2.v",
                "rtl/arbiter4_tree.v",
                "rtl/aer_tx16_trad_rowcol_fovea_cluster2_steal_buf_polarity_pose.v",
                "rtl/aer_bitmap_to_event8_pose.v",
                "rtl/event_batch_fifo.v",
                "rtl/rr_stream_arbiter4.v",
                "rtl/aer_region8x8_event_stream.v",
            ),
            "tb/tb_aer_region8x8_event_stream_edge.v",
            "AER_REGION8X8_EDGE_PASS",
        ),
        HDLTest(
            "rr_stream_merge16",
            "tb_rr_stream_merge16",
            (
                "rtl/rr_stream_arbiter4.v",
                "rtl/rr_stream_merge16.v",
            ),
            "tb/tb_rr_stream_merge16.v",
            "RR_STREAM_MERGE16_PASS",
        ),
        HDLTest(
            "aer_tx256_region_shared_affine",
            "tb_aer_tx256_region_shared_affine",
            (
                "rtl/arbiter2.v",
                "rtl/arbiter4_tree.v",
                "rtl/aer_tx16_trad_rowcol_fovea_cluster2_steal_buf_polarity_pose.v",
                "rtl/aer_bitmap_to_event8_pose.v",
                "rtl/event_batch_fifo.v",
                "rtl/rr_stream_arbiter4.v",
                "rtl/aer_region8x8_event_stream.v",
                "rtl/affine_region_pose_loader.v",
                "rtl/affine_region_coeff_table2.v",
                "rtl/pose_epoch_count_guard2.v",
                "rtl/coord_transform_affine2d.v",
                "rtl/region_affine_shared_lane.v",
                "rtl/aer_tx256_region_shared_affine.v",
            ),
            "tb/tb_aer_tx256_region_shared_affine.v",
            "AER_TX256_REGION_SHARED_AFFINE_PASS",
        ),
        HDLTest(
            "aer_tx128_dual_region_e2e",
            "tb_aer_tx128_region_pose_affine2d_dual",
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
                "rtl/affine_region_pose_loader.v",
                "rtl/aer_tx128_region_pose_affine2d_dual.v",
            ),
            "tb/tb_aer_tx128_region_pose_affine2d_dual.v",
            "AER_TX128_REGION_POSE_AFFINE2D_DUAL_PASS",
        ),
        HDLTest(
            "pose_guard_accept5",
            "tb_pose_inflight_guard8",
            ("rtl/pose_inflight_guard8.v",),
            "tb/tb_pose_inflight_guard8.v",
            "POSE_INFLIGHT_GUARD8_PASS",
            ("-DPOSE_GUARD_ACCEPT_SOURCES=5",),
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
            "banked_k2_backpressure",
            "tb_aer_tx16_pose_affine2d_banked_backpressure",
            (
                "rtl/arbiter2.v",
                "rtl/arbiter4_tree.v",
                "rtl/aer_tx16_trad_rowcol_fovea_cluster2_steal_buf_polarity_pose.v",
                "rtl/aer_bitmap_to_event8_pose.v",
                "rtl/event_batch_fifo.v",
                "rtl/pose_inflight_guard8.v",
                "rtl/pose_history_affine8.v",
                "rtl/coord_transform_affine2d.v",
                "rtl/aer_tx16_pose_affine2d_banked.v",
            ),
            "tb/tb_aer_tx16_pose_affine2d_banked_backpressure.v",
            "AER_TX16_POSE_AFFINE2D_BANKED_BACKPRESSURE_PASS",
            ("-Ptb_aer_tx16_pose_affine2d_banked_backpressure.K=2",),
        ),
        HDLTest(
            "banked_k4_backpressure",
            "tb_aer_tx16_pose_affine2d_banked_backpressure",
            (
                "rtl/arbiter2.v",
                "rtl/arbiter4_tree.v",
                "rtl/aer_tx16_trad_rowcol_fovea_cluster2_steal_buf_polarity_pose.v",
                "rtl/aer_bitmap_to_event8_pose.v",
                "rtl/event_batch_fifo.v",
                "rtl/pose_inflight_guard8.v",
                "rtl/pose_history_affine8.v",
                "rtl/coord_transform_affine2d.v",
                "rtl/aer_tx16_pose_affine2d_banked.v",
            ),
            "tb/tb_aer_tx16_pose_affine2d_banked_backpressure.v",
            "AER_TX16_POSE_AFFINE2D_BANKED_BACKPRESSURE_PASS",
            ("-Ptb_aer_tx16_pose_affine2d_banked_backpressure.K=4",),
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
            "world_time_surface_sram_writer",
            "tb_world_time_surface_sram_writer",
            ("rtl/world_time_surface_sram_writer.v",),
            "tb/tb_world_time_surface_sram_writer.v",
            "WORLD_TIME_SURFACE_SRAM_WRITER_PASS",
        ),
        HDLTest(
            "world_time_surface_sram_banked4",
            "tb_world_time_surface_sram_banked4",
            (
                "rtl/rr_stream_arbiter4.v",
                "rtl/world_time_surface_sram_writer.v",
                "rtl/world_time_surface_sram_banked4.v",
            ),
            "tb/tb_world_time_surface_sram_banked4.v",
            "WORLD_TIME_SURFACE_SRAM_BANKED4_PASS",
        ),
        HDLTest(
            "aer_4x4_k4_sram_surface_e2e",
            "tb_aer_tx16_pose_affine2d_k4_sram_surface",
            (
                "rtl/arbiter2.v",
                "rtl/arbiter4_tree.v",
                "rtl/aer_tx16_trad_rowcol_fovea_cluster2_steal_buf_polarity_pose.v",
                "rtl/aer_bitmap_to_event8_pose.v",
                "rtl/event_batch_fifo.v",
                "rtl/pose_inflight_guard8.v",
                "rtl/pose_history_affine8.v",
                "rtl/coord_transform_affine2d.v",
                "rtl/aer_tx16_pose_affine2d_banked.v",
                "rtl/rr_stream_arbiter4.v",
                "rtl/world_time_surface_sram_writer.v",
                "rtl/world_time_surface_sram_banked4.v",
                "rtl/aer_tx16_pose_affine2d_k4_sram_surface.v",
            ),
            "tb/tb_aer_tx16_pose_affine2d_k4_sram_surface.v",
            "AER_TX16_POSE_AFFINE2D_K4_SRAM_SURFACE_PASS",
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
        HDLTest(
            "aer_8x8_pose_sram_surface",
            "tb_aer_tx64_pose_sram_surface",
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
                "rtl/world_time_surface_sram_writer.v",
                "rtl/aer_tx64_pose_sram_surface.v",
            ),
            "tb/tb_aer_tx64_pose_sram_surface.v",
            "AER_TX64_POSE_SRAM_SURFACE_PASS",
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


def trace_sweep_tests() -> tuple[HDLTest, ...]:
    trace = "common_traces_uzh/uzh_shapes_rotation_patch.addrpol.txt"
    dependencies = (
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
    )
    return tuple(
        HDLTest(
            f"uzh_k1_k8_depth_{depth}",
            "tb_stage2_k1_k8_uzh_trace",
            dependencies,
            "tb/tb_stage2_k1_k8_uzh_trace.v",
            "STAGE2_K1_K8_UZH_TRACE_PASS",
            (f"-Ptb_stage2_k1_k8_uzh_trace.FIFO_DEPTH={depth}",),
            (f"+TRACE_FILE={trace}",),
        )
        for depth in (8, 16, 32, 64, 128)
    )


def lane_sweep_tests() -> tuple[HDLTest, ...]:
    trace = "common_traces_uzh/uzh_shapes_rotation_patch.addrpol.txt"
    dependencies = (
        "rtl/arbiter2.v",
        "rtl/arbiter4_tree.v",
        "rtl/aer_tx16_trad_rowcol_fovea_cluster2_steal_buf_polarity_pose.v",
        "rtl/aer_bitmap_to_event8_pose.v",
        "rtl/event_batch_fifo.v",
        "rtl/pose_inflight_guard8.v",
        "rtl/pose_history_affine8.v",
        "rtl/coord_transform_affine2d.v",
        "rtl/aer_tx16_pose_affine2d_banked.v",
    )
    configurations = (
        (2, 1), (2, 2), (2, 4), (2, 8), (2, 16), (2, 32),
        (4, 1), (4, 2), (4, 4), (4, 8),
    )
    return tuple(
        HDLTest(
            f"uzh_k{k}_depth_{depth}",
            "tb_stage2_k2_k4_uzh_trace",
            dependencies,
            "tb/tb_stage2_k2_k4_uzh_trace.v",
            "STAGE2_BANKED_UZH_TRACE_PASS",
            (
                f"-Ptb_stage2_k2_k4_uzh_trace.K={k}",
                f"-Ptb_stage2_k2_k4_uzh_trace.FIFO_DEPTH={depth}",
            ),
            (f"+TRACE_FILE={trace}",),
        )
        for k, depth in configurations
    )


def serialized_k4_sweep_tests() -> tuple[HDLTest, ...]:
    trace = "common_traces_uzh/uzh_shapes_rotation_patch.addrpol.txt"
    dependencies = (
        "rtl/arbiter2.v",
        "rtl/arbiter4_tree.v",
        "rtl/aer_tx16_trad_rowcol_fovea_cluster2_steal_buf_polarity_pose.v",
        "rtl/aer_bitmap_to_event8_pose.v",
        "rtl/event_batch_fifo.v",
        "rtl/pose_inflight_guard8.v",
        "rtl/pose_history_affine8.v",
        "rtl/coord_transform_affine2d.v",
        "rtl/aer_tx16_pose_affine2d_banked.v",
        "rtl/rr_stream_arbiter4.v",
        "rtl/aer_tx16_pose_affine2d_k4_serial.v",
    )
    always_ready = tuple(
        HDLTest(
            f"uzh_k4_serial_depth_{depth}",
            "tb_stage2_k2_k4_uzh_trace",
            dependencies,
            "tb/tb_stage2_k2_k4_uzh_trace.v",
            "STAGE2_BANKED_UZH_TRACE_PASS",
            (
                "-Ptb_stage2_k2_k4_uzh_trace.K=4",
                f"-Ptb_stage2_k2_k4_uzh_trace.FIFO_DEPTH={depth}",
                "-Ptb_stage2_k2_k4_uzh_trace.SERIALIZE_OUTPUT=1",
            ),
            (f"+TRACE_FILE={trace}",),
        )
        for depth in (8, 16, 32, 64)
    )
    stalled = HDLTest(
        "uzh_k4_serial_stall_depth_32",
        "tb_stage2_k2_k4_uzh_trace",
        dependencies,
        "tb/tb_stage2_k2_k4_uzh_trace.v",
        "STAGE2_BANKED_UZH_TRACE_PASS",
        (
            "-Ptb_stage2_k2_k4_uzh_trace.K=4",
            "-Ptb_stage2_k2_k4_uzh_trace.FIFO_DEPTH=32",
            "-Ptb_stage2_k2_k4_uzh_trace.SERIALIZE_OUTPUT=1",
            "-Ptb_stage2_k2_k4_uzh_trace.SERIAL_STALL_OUTPUT=1",
        ),
        (f"+TRACE_FILE={trace}",),
    )
    return always_ready + (stalled,)


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
    parser.add_argument(
        "--trace-sweep",
        action="store_true",
        help=("also compare K=1 FIFO depths 8..128 against K=8 on the "
              "1 ms-bin UZH burst stress"),
    )
    parser.add_argument(
        "--lane-sweep",
        action="store_true",
        help=("also sweep K=2/K=4 bank depths and the fair single-output "
              "K=4 endpoint on the 1 ms-bin UZH burst stress"),
    )
    parser.add_argument(
        "--physical",
        action="store_true",
        help=("also regenerate measured-pose/calibration UZH vectors, compare "
              "all 8,503 patch events, and probe two adjacent 8x8 regions"),
    )
    parser.add_argument(
        "--full-sensor-sweep",
        action="store_true",
        help=("also fit every 4x4 and 8x8 region over the 240x180 sensor "
              "at uniform plus trajectory-risk poses and enforce sampled "
              "geometry/error gates"),
    )
    parser.add_argument(
        "--memory-sweep",
        action="store_true",
        help=("also replay eventmeta nanosecond timestamps at 200 MHz "
              "through the four-bank SRAM surface across read latencies"),
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

        result = run_synthesis_elaboration(root, temp_root, iverilog)
        results.append(result)
        print_result(result)

        for test in tests[4:]:
            result = run_hdl_test(test, root, temp_root, iverilog, vvp)
            results.append(result)
            print_result(result)

        if args.physical:
            result = run_uzh_physical_vectors(
                root, temp_root, iverilog, vvp
            )
            results.append(result)
            print_result(result)
            result = run_uzh_dual_region_vectors(
                root, temp_root, iverilog, vvp
            )
            results.append(result)
            print_result(result)

        if args.full_sensor_sweep:
            result = run_full_sensor_affine_sweep(root)
            results.append(result)
            print_result(result)

        if args.memory_sweep:
            result = run_uzh_200mhz_memory_sweep(
                root, temp_root, iverilog, vvp
            )
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

        if args.trace_sweep:
            for test in trace_sweep_tests():
                result = run_hdl_test(test, root, temp_root, iverilog, vvp)
                results.append(result)
                print_result(result)

        if args.lane_sweep:
            for test in lane_sweep_tests():
                result = run_hdl_test(test, root, temp_root, iverilog, vvp)
                results.append(result)
                print_result(result)
            for test in serialized_k4_sweep_tests():
                result = run_hdl_test(test, root, temp_root, iverilog, vvp)
                results.append(result)
                print_result(result)

    passed = sum(result.passed for result in results)
    print(f"\nStage-2 regression: {passed}/{len(results)} tests passed")
    return 0 if passed == len(results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
