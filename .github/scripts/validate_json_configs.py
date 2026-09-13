#!/usr/bin/env python3
"""Validate JSON configuration files for schema and internal consistency.

Validates:
  1. installer/data/theme.json - required top-level keys, color references are valid,
     ANSI codes match expected pattern.
  2. installer/data/menu.json - valid menu tree, unique IDs, all action IDs are recognized,
     select options are non-empty, text defaults are strings.
"""

import json
import re
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]

RED = "\033[0;31m"
GREEN = "\033[0;32m"
YELLOW = "\033[0;33m"
BOLD = "\033[1m"
RESET = "\033[0m"

EXIT_CODE = 0


def error(msg: str) -> None:
    global EXIT_CODE
    print(f"{RED}[ERR]{RESET}  {msg}")
    EXIT_CODE = 1


def warn(msg: str) -> None:
    print(f"{YELLOW}[WARN]{RESET} {msg}")


def ok(msg: str) -> None:
    print(f"{GREEN}[OK]{RESET}   {msg}")


# theme.json

ANSI_SGR_RE = re.compile(r"^\d+(;\d+)*m$")
HEX_COLOR_RE = re.compile(r"^#[0-9a-fA-F]{6}$")

REQUIRED_THEME_SECTIONS = {
    "palette",
    "splash_screen",
    "glyphs",
}

KNOWN_GLYPHS = {
    "pending", "running", "ok", "warn", "failed", "skipped",
    "checkbox_on", "checkbox_off", "select_left", "select_right",
}

# Color names the TUI understands even when absent from the palette.
SPECIAL_COLORS = {"default", "dim", "bold", "reset"}


def validate_theme(filepath: Path) -> None:
    print(f"\n{BOLD}=== Validating {filepath.relative_to(ROOT)} ==={RESET}")

    try:
        data = json.loads(filepath.read_text(encoding="utf-8"))
    except json.JSONDecodeError as e:
        error(f"{filepath}: invalid JSON - {e}")
        return

    # Top-level sections
    for section in REQUIRED_THEME_SECTIONS:
        if section not in data:
            error(f"theme.json: missing required section '{section}'")

    # Palette: hex (#rrggbb) values, or legacy ANSI suffixes ("36m").
    palette = data.get("palette")
    colors = data.get("colors") if not isinstance(palette, dict) else None
    color_section = palette if isinstance(palette, dict) else (colors if isinstance(colors, dict) else {})
    for name, code in color_section.items():
        if not isinstance(code, str):
            error(f"theme.json: palette color '{name}' must be a string")
            continue
        if not (HEX_COLOR_RE.match(code) or ANSI_SGR_RE.match(code)):
            error(f"theme.json: palette color '{name}' has invalid value: {code!r}")

    defined_colors = set(color_section.keys()) | SPECIAL_COLORS

    def check_color_ref(value: Any, context: str) -> None:
        if not isinstance(value, str):
            return
        if value in SPECIAL_COLORS:
            return
        if value.startswith("bold_") and value[len("bold_"):] in defined_colors:
            return
        if value not in defined_colors:
            error(f"theme.json: {context} references undefined color '{value}'")

    # splash_screen
    splash = data.get("splash_screen", {})
    if isinstance(splash, dict):
        art = splash.get("art")
        if not isinstance(art, list) or len(art) == 0:
            error("theme.json: splash_screen.art must be a non-empty array of strings")
        elif not all(isinstance(line, str) for line in art):
            error("theme.json: all splash_screen.art elements must be strings")

        check_color_ref(splash.get("art_color"), "splash_screen.art_color")
        if "co_author" in splash and not isinstance(splash.get("co_author"), str):
            error("theme.json: splash_screen.co_author must be a string")

    # glyphs: every glyph is a non-empty string
    glyphs = data.get("glyphs", {})
    if isinstance(glyphs, dict):
        for name, value in glyphs.items():
            if name not in KNOWN_GLYPHS:
                warn(f"theme.json: unrecognized glyph key '{name}'")
            if not isinstance(value, str) or not value:
                error(f"theme.json: glyph '{name}' must be a non-empty string")

    ok("theme.json passed validation")


# menu.json

VALID_MENU_TYPES = {"submenu", "boolean", "select", "text", "action"}
VALID_ACTION_IDS = {"action_review", "action_proceed", "action_back"}


def validate_menu_items(items: list[Any], path: str = "menu", seen_ids: set[str] | None = None) -> None:
    if seen_ids is None:
        seen_ids = set()

    if not isinstance(items, list):
        error(f"menu.json: {path} must be an array")
        return

    for i, item in enumerate(items):
        item_path = f"{path}[{i}]"
        if not isinstance(item, dict):
            error(f"menu.json: {item_path} must be an object")
            continue

        item_type = item.get("type")
        if item_type not in VALID_MENU_TYPES:
            error(f"menu.json: {item_path} has invalid type: {item_type!r}")

        title = item.get("title")
        if not isinstance(title, str) or not title.strip():
            error(f"menu.json: {item_path} is missing a non-empty 'title'")

        help_text = item.get("help")
        if help_text is not None and not isinstance(help_text, str):
            error(f"menu.json: {item_path} 'help' must be a string")

        item_id = item.get("id")

        if item_type == "submenu":
            if not isinstance(item_id, str):
                error(f"menu.json: {item_path} submenu must have a string 'id'")
            elif item_id in seen_ids:
                error(f"menu.json: {item_path} duplicate id '{item_id}'")
            else:
                seen_ids.add(item_id)
            sub_items = item.get("items")
            if not isinstance(sub_items, list) or len(sub_items) == 0:
                error(f"menu.json: {item_path} submenu 'items' must be a non-empty array")
            else:
                validate_menu_items(sub_items, f"{item_path}.items", seen_ids)

        elif item_type == "boolean":
            if not isinstance(item_id, str):
                error(f"menu.json: {item_path} boolean must have a string 'id'")
            default = item.get("default")
            if default is not None and not isinstance(default, bool):
                error(f"menu.json: {item_path} boolean 'default' must be a boolean")

        elif item_type == "select":
            if not isinstance(item_id, str):
                error(f"menu.json: {item_path} select must have a string 'id'")
            options = item.get("options")
            if not isinstance(options, list) or len(options) == 0:
                error(f"menu.json: {item_path} select 'options' must be a non-empty array")
            default = item.get("default")
            if default is not None and options and default not in options:
                warn(f"menu.json: {item_path} default '{default}' not in options {options}")

        elif item_type == "text":
            if not isinstance(item_id, str):
                error(f"menu.json: {item_path} text must have a string 'id'")
            default = item.get("default")
            if default is not None and not isinstance(default, str):
                error(f"menu.json: {item_path} text 'default' must be a string")

        elif item_type == "action":
            if item_id not in VALID_ACTION_IDS:
                error(f"menu.json: {item_path} action id must be one of {VALID_ACTION_IDS}, got: {item_id!r}")


def validate_menu(filepath: Path) -> None:
    print(f"\n{BOLD}=== Validating {filepath.relative_to(ROOT)} ==={RESET}")

    try:
        data = json.loads(filepath.read_text(encoding="utf-8"))
    except json.JSONDecodeError as e:
        error(f"menu.json: invalid JSON - {e}")
        return

    if not isinstance(data, dict):
        error("menu.json: root must be an object")
        return

    menu_items = data.get("menu")
    if not isinstance(menu_items, list):
        error("menu.json: missing 'menu' array")
        return

    if len(menu_items) == 0:
        error("menu.json: 'menu' array is empty")
        return

    # Check that the root menu has at least one proceed action
    has_proceed = any(
        isinstance(item, dict) and item.get("id") in ("action_review", "action_proceed")
        for item in menu_items
    )
    if not has_proceed:
        error("menu.json: root menu must include an 'action_review' item")

    validate_menu_items(menu_items)

    if EXIT_CODE == 0:
        ok("menu.json passed validation")


def main() -> int:
    theme_path = ROOT / "installer" / "data" / "theme.json"
    menu_path = ROOT / "installer" / "data" / "menu.json"

    if theme_path.is_file():
        validate_theme(theme_path)
    else:
        error(f"{theme_path.relative_to(ROOT)} not found")

    if menu_path.is_file():
        validate_menu(menu_path)
    else:
        error(f"{menu_path.relative_to(ROOT)} not found")

    print()
    if EXIT_CODE == 0:
        print(f"{BOLD}{GREEN}All JSON config validations passed.{RESET}")
    else:
        print(f"{BOLD}{RED}Some JSON config validations failed.{RESET}")

    return EXIT_CODE


if __name__ == "__main__":
    sys.exit(main())
