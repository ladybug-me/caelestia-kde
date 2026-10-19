#!/usr/bin/env python3
"""Run and validate installer steps for CI dependency testing.

Executes non-interactive installer scripts and verifies both exit codes and build output
(CMake, Ninja, Make) while ignoring optional components like workspace-tracker.
"""

import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

INSTALLER_STEPS = [
    "00a-system-update",
    "01-ensure-prereqs",
    "02a-submodules",
    "02-all-packages",
    "08-build-shell",
]


def installer_binary() -> Path:
    """The step table lives in the installer crate, so the steps run through it."""
    if "CAELESTIA_INSTALL_BIN" in os.environ:
        return Path(os.environ["CAELESTIA_INSTALL_BIN"])

    for candidate in (
        ROOT / "installer" / "target" / "release" / "caelestia-install",
        ROOT / "installer" / "target" / "debug" / "caelestia-install",
        ROOT / "caelestia-install",
    ):
        if candidate.is_file():
            return candidate

    raise SystemExit(
        "::error::the installer binary is missing; build it with "
        "`cargo build --release --manifest-path installer/Cargo.toml`"
    )


def step_command(step: str, binary: Path) -> list[str]:
    """A step that still has a script runs it; a ported step runs inside the installer."""
    script = ROOT / "scripts" / f"{step}.sh"
    if script.is_file():
        return ["bash", str(script)]
    return [str(binary), "step", step, "--bundle", str(ROOT)]


def detect_base_distro() -> str:
    """Detect base distro family (arch, fedora, debian)."""
    if "BASE_DISTRO" in os.environ:
        return os.environ["BASE_DISTRO"]

    os_release = Path("/etc/os-release")
    if os_release.exists():
        content = os_release.read_text(encoding="utf-8")
        info = {}
        for line in content.splitlines():
            if "=" in line:
                k, v = line.split("=", 1)
                info[k.strip()] = v.strip().strip('"')

        distro_id = info.get("ID", "").lower()
        id_like = info.get("ID_LIKE", "").lower()

        if distro_id in {"arch", "cachyos", "endeavouros", "manjaro", "artix"} or "arch" in id_like:
            return "arch"
        if distro_id in {"fedora", "nobara", "bazzite", "rhel", "centos", "almalinux", "rocky"} or "fedora" in id_like:
            return "fedora"
        if distro_id in {"debian", "ubuntu", "pop", "mint", "kali", "raspbian", "elementary", "zorin", "deepin", "devuan"} or any(d in id_like for d in ("debian", "ubuntu")):
            return "debian"

    if shutil.which("pacman"):
        return "arch"
    if shutil.which("dnf"):
        return "fedora"
    if shutil.which("apt-get"):
        return "debian"

    return "unknown"


def get_ci_environment() -> dict[str, str]:
    """Build environment dictionary with required defaults and distro configurations."""
    env = dict(os.environ)
    distro = detect_base_distro()

    env["BASE_DISTRO"] = distro
    env["BUNDLE_DIR"] = str(ROOT)
    env["NONINTERACTIVE"] = "1"
    env["CI"] = "1"
    env["CAELESTIA_SETUP_RUNNING"] = "1"
    env["CAELESTIA_FORCE_BUILD_SHELL"] = "true"
    env["INSTALL_DARKLY"] = "true"

    if distro == "arch":
        env.setdefault("CONFIRM_ARG", "--noconfirm")
    elif distro == "fedora":
        env.setdefault("CONFIRM_ARG", "-y")
    elif distro == "debian":
        env.setdefault("CONFIRM_ARG", "-y")
        env["DEBIAN_FRONTEND"] = "noninteractive"

    return env


def is_workspace_tracker_error(ctx: str, line: str) -> bool:
    target = f"{ctx} {line}".lower()
    return "workspace-tracker" in target or "workspace_tracker" in target


def is_build_error(line: str) -> bool:
    line_lower = line.lower()
    return (
        "cmake error" in line_lower
        or "ninja: build stopped" in line_lower
        or line.startswith("FAILED:")
        or "make: ***" in line
        or ("make[" in line and "Error" in line)
    )


def check_plan(binary: Path, env: dict[str, str]) -> bool:
    """What the installer says it would do on this distribution.

    Cheap, side-effect free, and the only place the plan is exercised somewhere other than Arch:
    a step that resolves a different package list per distro is exactly what this catches.
    """
    proc = subprocess.run(
        [str(binary), "--plan", "--json", str(ROOT)],
        cwd=ROOT,
        env=env,
        capture_output=True,
        text=True,
    )
    distro = env.get("BASE_DISTRO", "unknown")
    if proc.returncode != 0:
        print(f"::error::--plan failed on {distro} with exit code {proc.returncode}")
        print(proc.stderr)
        return False

    try:
        plan = json.loads(proc.stdout)
    except json.JSONDecodeError as problem:
        print(f"::error::--plan --json printed something that is not JSON: {problem}")
        print(proc.stdout[:400])
        return False

    rows = {row["id"]: row["runs"] for row in plan.get("steps", [])}
    missing = [step for step in INSTALLER_STEPS if step not in rows]
    switched_off = [step for step in INSTALLER_STEPS if step in rows and not rows[step]]

    print(
        f"  plan on {distro}: {plan.get('steps_that_run')} of "
        f"{plan.get('steps_total')} steps would run"
    )
    print(f"  journal would be {plan.get('journal')}")

    if missing:
        print(f"::error::{distro}: the plan does not mention {missing}")
        return False
    if switched_off:
        print(f"::error::{distro}: the environment switches off {switched_off}")
        return False
    return True


def run_pass(label: str, env: dict[str, str], binary: Path) -> list[tuple[str, str]]:
    """Run every step once and collect what went wrong."""
    failed: list[tuple[str, str]] = []

    for s in INSTALLER_STEPS:
        command = step_command(s, binary)
        print("\n=========================================")
        print(f"  {label}: STEP {s} ({command[0]})")
        print("=========================================")

        proc = subprocess.Popen(
            command,
            cwd=ROOT,
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
        )

        current_info = s
        build_errors: list[tuple[str, str]] = []

        if proc.stdout:
            for line in proc.stdout:
                print(line, end="")
                info_match = re.search(r"\[INFO\]\s*(.*)", line)
                if info_match:
                    current_info = info_match.group(1).strip()

                if not is_workspace_tracker_error(current_info, line) and is_build_error(line):
                    build_errors.append((current_info, line.strip()))

        proc.wait()
        rc = proc.returncode

        build_errors = [
            (ctx, msg)
            for ctx, msg in build_errors
            if not is_workspace_tracker_error(ctx, msg)
        ]

        if rc != 0:
            print(f"::error::{label}: step {s} failed with exit code {rc}")
            failed.append((s, f"{label}: exit code {rc}"))
        elif build_errors:
            for ctx, err_msg in build_errors:
                print(f"::error::[{ctx}] Build error detected: {err_msg}")
            failed.append((s, f"{label}: build error in [{current_info}]"))

    return failed


def run_steps() -> int:
    env = get_ci_environment()
    steps = INSTALLER_STEPS

    print("=========================================")
    print("  CI Dependency Test Runner")
    print(f"  Base Distro : {env.get('BASE_DISTRO')}")
    print(f"  Bundle Dir  : {env.get('BUNDLE_DIR')}")
    print(f"  Total Steps : {len(steps)}")
    print("=========================================")
    for s in steps:
        print(f"  - {s}")

    binary = installer_binary()

    print("\n=========================================")
    print("  PLAN")
    print("=========================================")
    if not check_plan(binary, env):
        return 1

    failed = run_pass("pass 1", env, binary)
    if failed:
        print(f"::error::{len(failed)} step(s) failed: {failed}")
        return 1

    print("\n=========================================")
    print("  PASS 2 - the same steps on the machine pass 1 built")
    print("=========================================")
    failed = run_pass("pass 2", env, binary)
    if failed:
        print(f"::error::not idempotent: {failed}")
        return 1

    print("\nBoth passes finished cleanly on " + env.get("BASE_DISTRO", "unknown"))
    return 0


if __name__ == "__main__":
    sys.exit(run_steps())
