#!/usr/bin/env python3
"""Run and validate installer steps for CI dependency testing.

Executes non-interactive installer scripts and verifies both exit codes and build output
(CMake, Ninja, Make) while ignoring optional components like workspace-tracker.
"""

import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

INSTALLER_STEPS = [
    "scripts/00a-system-update.sh",
    "scripts/01-ensure-prereqs.sh",
    "scripts/02a-submodules.sh",
    "scripts/02-all-packages.sh",
    "scripts/08-build-shell.sh",
]


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

    failed: list[tuple[str, str]] = []

    for s in steps:
        print("\n=========================================")
        print(f"  RUNNING STEP: {s}")
        print("=========================================")

        proc = subprocess.Popen(
            ["bash", s],
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
            print(f"::error::Step {s} failed with exit code {rc}")
            failed.append((s, f"exit code {rc}"))
        elif build_errors:
            for ctx, err_msg in build_errors:
                print(f"::error::[{ctx}] Build error detected: {err_msg}")
            failed.append((s, f"Build error in [{current_info}]"))

    if failed:
        print(f"::error::{len(failed)} step(s) failed: {failed}")
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(run_steps())
