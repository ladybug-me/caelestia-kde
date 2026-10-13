#!/usr/bin/env python3
"""Validate that a PR description is meaningful - not just placeholder text.

Reads the PR body from the GitHub event payload and checks:
  1. The description is not completely empty
  2. The "What does this change?" section has been filled in
"""

import json
import os
import re
import sys

RED = "\033[0;31m"
GREEN = "\033[0;32m"
YELLOW = "\033[0;33m"
BOLD = "\033[1m"
RESET = "\033[0m"

EXIT_CODE = 0
WARNINGS: list[str] = []


def error(msg: str) -> None:
    global EXIT_CODE
    print(f"{RED}[ERR]{RESET}  {msg}")
    EXIT_CODE = 1


def warn(msg: str) -> None:
    print(f"{YELLOW}[WARN]{RESET} {msg}")
    WARNINGS.append(msg)


def ok(msg: str) -> None:
    print(f"{GREEN}[OK]{RESET}   {msg}")


def load_pr_body() -> str | None:
    """Load PR body from the GitHub event file."""
    event_path = os.environ.get("GITHUB_EVENT_PATH")
    if not event_path:
        print("Warning: GITHUB_EVENT_PATH not set - running locally?")
        return None

    try:
        with open(event_path, encoding="utf-8") as f:
            event = json.load(f)
    except (json.JSONDecodeError, FileNotFoundError):
        print("Warning: Could not read GitHub event file")
        return None

    pull_request = event.get("pull_request", {})
    return pull_request.get("body", "")


def check_section_filled(body: str, section_header: str) -> bool:
    """Verify that a section has real content, not just placeholder text."""
    header_pattern = re.escape(section_header)
    section_match = re.search(
        rf"#{1,3}\s+{header_pattern}.*?\n(.*?)(?=\n#{1,3}\s+|\Z)",  # noqa: E231
        body,
        re.DOTALL | re.IGNORECASE,
    )
    if not section_match:
        return True  # Section not present - the new template is lightweight

    section_text = section_match.group(1).strip()

    placeholder_texts = [
        "A sentence or two about what this PR does",
        "Briefly describe what this PR changes",
        "Describe how you tested these changes",
        "Add screenshots if they are relevant",
        "Add any other context here",
    ]

    for placeholder in placeholder_texts:
        if placeholder.lower() in section_text.lower() and len(section_text) < len(placeholder) + 30:
            warn(f"'{section_header}' still contains placeholder text - fill it in?")
            return False

    cleaned = re.sub(r"[#\-\*\s]", "", section_text)
    if len(cleaned) < 10:
        warn(f"'{section_header}' section is empty - a sentence or two helps reviewers")
        return False

    return True


def main() -> int:
    body = load_pr_body()

    if body is None:
        print(f"{YELLOW}Skipping PR template validation - not running in CI context.{RESET}")
        return 0

    print(f"{BOLD}=== PR Description Check ==={RESET}")

    check_section_filled(body, "What does this change?")

    if not body or len(body.strip()) < 20:
        error("PR description is empty - please add a sentence about what this changes")

    print()
    if EXIT_CODE == 0:
        print(f"{BOLD}{GREEN}PR description looks good!{RESET}")
        if WARNINGS:
            print(f"{YELLOW}({len(WARNINGS)} gentle suggestion(s) above){RESET}")
    else:
        print(f"{BOLD}{RED}Please add a description before submitting.{RESET}")

    return EXIT_CODE


if __name__ == "__main__":
    sys.exit(main())
