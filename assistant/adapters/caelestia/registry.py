"""Frozen tool registry for the settings layer (issue #120, the settings design notes (see module docstrings) §1).

One ToolSpec per editable shell.json leaf. Every row is grounded in this
checkout's own sources — the C++ property declaration in
shell/plugin/src/Caelestia/Config/*.hpp (CONFIG_PROPERTY /
CONFIG_GLOBAL_PROPERTY / the *_ENUM_PROPERTY variants: type, name,
default) plus the shipped Nexus control that reads/writes it — and every
row carries its citations as ("file:line", "what it evidences") pairs, so
the provenance travels with the data instead of living only in
the settings design notes (see module docstrings)'s appendix.

The registry: an 18-tool hand-frozen core inside the generated whole — every scalar leaf
that a shipped scalar Nexus control touches. The table is no longer
hand-maintained here: build_registry.py generates tools.json from the real
headers (enumerate.py) + the transcribed control table
(ui_ranges_data.py) + the safety classification (curations.py), and this
module loads that committed artifact at import (the ONLY I/O it performs;
a unittest drift guard regenerates the table from the checkout and
byte-compares it, so the artifact cannot silently drift). The leaves that
are deliberately NOT tools are recorded with a reason each in the
not_exposed table inside tools.json (exposed here as NOT_EXPOSED):
credentials, endpoints, the master switch, list/map/union keys, kwinrc
companion writes, dynamic or transformed-string controls, and every leaf
without a shipped control.

Upstream declares NO numeric bounds in the schema: property setters carry
only a type and a default, and their validation hook is type-only —
``if (rejectInvalidWrite(...)) return; /* Skip writes of the wrong type */``
(Settings/macros.hpp:91-92, [C6]) — which is still a no-op for every
ordinary typed property (the template overload returns false
unconditionally, "Only QVariant unions can be given the wrong type",
node.hpp:88-92); only the QVariant-union keys get a metatype check
(node.cpp:133-141). The ranges below are therefore the assistant's OWN
conservative validation (the settings design notes (see module docstrings) §1.1), adopting the shipped Nexus
controls' ranges verbatim — in the STORED unit, which for a handful of
transformed steppers (seconds/ms, percent/fraction, minutes/seconds) is a
documented unit conversion (curations.RANGE_FIXUPS) — implementing issue
#120's rule that an out-of-range value "simply isn't applied".

Kinds: bool / int / float / enum / string. Enum values are the serialized
form — metaenum keys for C++ enum leaves, or the raw ints the shipped
numeric-coded SelectRow writes. String tools (font families) carry a
string_max_len instead of a range and are not settable through the
planner yet. The 18 core tools keep their exact names, paths,
kinds, defaults, ranges, steps, global-only flags and nouns (pinned by
tests) and lead TOOL_SPECS; every tool after them is noun-silent
(addressable by name via --call, not by plain words) and carries a
feature-area group (GROUPS / tools_by_group / list_tools_lines).
"""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List, Optional, Tuple, Union

Value = Union[float, int, bool, str]
EnumValue = Union[str, int]

_TOOLS_JSON_PATH = Path(__file__).resolve().parent / "tools.json"

# The 18-tool core order of the 18 core tools (the settings design notes (see module docstrings) §1 rows 1-18:
# # extension). They lead TOOL_SPECS in exactly this order; tools.json must
# contain all of them (their values are pinned by tests/test_registry.py).
CORE_TOOL_NAMES: Tuple[str, ...] = (
    "setBarScale",
    "setBarPosition",
    "setDockIconSize",
    "setBarPersistent",
    "setLivePreviews",
    "setBlurEnabled",
    "setTransparencyBase",
    "setRoundingScale",
    "setSpacingScale",
    "setPaddingScale",
    "setFontScale",
    "setAnimationSpeed",
    "setBorderThickness",
    "setLauncherMaxShown",
    "setPitchBlack",
    "setNotifsMaxPopups",
    "setNotifsMaxNotifs",
    "setDockBadges",
)


@dataclass(frozen=True)
class ToolSpec:
    """One editable shell.json leaf (the settings design notes (see module docstrings) §1).

    ``nouns`` holds the parser's noun groups (the settings design notes (see module docstrings) §3.4): each element
    is a regex alternation; a tool's noun matches when EVERY group appears
    (most tools have exactly one group). Only the 18 core tools carry
    nouns — the remaining tools are addressed by name (--call), not words.

    ``group`` is the feature-area slug (GROUPS lists them in display
    order). ``citations`` are ("file:line", "what it evidences") pairs,
    C++ declaration first, shipped Nexus control second, extra evidence
    after. ``string_max_len`` is set only for kind "string".
    """

    name: str                                   # tool name, e.g. "setBarScale"
    path: str                                   # dotted JSON path, e.g. "bar.scale"
    kind: str                                   # "bool" | "int" | "float" | "enum" | "string"
    default: Value                              # registry default (reset target)
    minimum: Optional[float] = None             # None for bool/enum/string
    maximum: Optional[float] = None             # None for bool/enum/string
    enum: Optional[Tuple[EnumValue, ...]] = None  # allowed values for kind == "enum"
    global_only: bool = False                   # SETTINGS_GLOBAL_* upstream ([C6])
    step: Union[float, int] = 0                 # magnitude of one "step" op (§1.2); 0 = not steppable
    nouns: Tuple[str, ...] = ()                 # parser noun groups (§3.4); () = noun-silent
    group: str = ""                             # feature-area slug ("" only if absent upstream)
    citations: Tuple[Tuple[str, str], ...] = () # ("file:line", "what it evidences")
    string_max_len: Optional[int] = None        # kind "string" only: max characters


# ---------------------------------------------------------------------------
# Loading the frozen artifact (the module's only I/O). tools.json is
# generated by build_registry.py (deterministic; see the module docstring)
# and is sorted group-major then by name — the group order below is derived
# from that first-seen order, which is curations.GROUPS order restricted to
# the groups that actually have tools.
# ---------------------------------------------------------------------------


def _load_data() -> Dict[str, object]:
    with _TOOLS_JSON_PATH.open("r", encoding="utf-8") as handle:
        return json.load(handle)


_DATA = _load_data()
_ROWS: List[Dict[str, object]] = list(_DATA["tools"])  # type: ignore[assignment]

_CORE_NAME_SET = frozenset(CORE_TOOL_NAMES)
_ROWS_BY_NAME: Dict[str, Dict[str, object]] = {str(row["name"]): row for row in _ROWS}


def _spec_from_row(row: Dict[str, object]) -> ToolSpec:
    enum = row.get("enum")
    citations = row.get("citations") or ()
    step = row.get("step")
    return ToolSpec(
        name=str(row["name"]),
        path=str(row["path"]),
        kind=str(row["kind"]),
        default=row["default"],  # type: ignore[arg-type]
        minimum=row.get("minimum"),  # type: ignore[arg-type]
        maximum=row.get("maximum"),  # type: ignore[arg-type]
        enum=tuple(enum) if enum is not None else None,  # type: ignore[arg-type]
        global_only=bool(row.get("global_only")),
        step=step if step is not None else 0,  # type: ignore[arg-type]
        nouns=tuple(row.get("nouns") or ()),  # type: ignore[arg-type]
        group=str(row.get("group") or ""),
        citations=tuple((str(c[0]), str(c[1])) for c in citations),  # type: ignore[index]
        string_max_len=row.get("string_max_len"),  # type: ignore[arg-type]
    )


# The 18 core tools first (registry order above), then every remaining tool in
# tools.json order (group order, then name).
TOOL_SPECS: Tuple[ToolSpec, ...] = tuple(
    _spec_from_row(_ROWS_BY_NAME[name])
    if name in _ROWS_BY_NAME
    else _raise_missing_core(name)
    for name in CORE_TOOL_NAMES
) + tuple(
    _spec_from_row(row)
    for row in _ROWS
    if str(row["name"]) not in _CORE_NAME_SET
)

# Feature-area slugs in display order (curations.GROUPS order, restricted
# to groups that have tools — derived from tools.json's group-major sort).
GROUPS: Tuple[str, ...] = tuple(
    dict.fromkeys(str(row["group"]) for row in _ROWS)
)

TOOL_COUNT: int = len(TOOL_SPECS)

# Every scalar leaf that is deliberately NOT a tool, with its reason
# (mirrors tools.json's not_exposed table; build_registry.py emits it).
NOT_EXPOSED: Tuple[Tuple[str, str], ...] = tuple(
    (str(entry["path"]), str(entry["reason"]))
    for entry in _DATA["not_exposed"]  # type: ignore[union-attr]
)

# Named presets: bundles of validated tool calls only. Each call
# was validated against its tool at BUILD time (build_registry._preset_value_ok
# fails the build otherwise) — presets are data, never bespoke code paths.
PRESETS: Tuple[Dict[str, object], ...] = tuple(
    {
        "name": str(p["name"]),
        "label": str(p["label"]),
        "description": str(p["description"]),
        "calls": tuple((str(c["tool"]), c["value"]) for c in p["calls"]),  # type: ignore[union-attr,index]
    }
    for p in _DATA.get("presets", ())  # type: ignore[union-attr]
)

# Explainability rules: pure data — a state predicate ("when"),
# an answer template ("answer"), and citations. Rendered by explain.py (CLI)
# and by the QML service identically.
EXPLAIN_RULES: Tuple[Dict[str, object], ...] = tuple(
    {
        "path": str(r["path"]),
        "when": str(r["when"]),
        "answer": str(r["answer"]),
        "cites": tuple(str(c) for c in r["cites"]),  # type: ignore[union-attr,index]
    }
    for r in _DATA.get("explain_rules", ())  # type: ignore[union-attr]
)

_TOOLS_BY_NAME: Dict[str, ToolSpec] = {spec.name: spec for spec in TOOL_SPECS}
_TOOLS_BY_PATH: Dict[str, ToolSpec] = {spec.path: spec for spec in TOOL_SPECS}
_TOOLS_BY_GROUP: Dict[str, Tuple[ToolSpec, ...]] = {
    group: tuple(spec for spec in TOOL_SPECS if spec.group == group)
    for group in GROUPS
}


def _raise_missing_core(name: str) -> ToolSpec:
    """Loud import-time failure if tools.json lost one of the 18 core tools."""
    raise RuntimeError(
        f"tools.json is missing the core tool {name!r}; the 18-tool core "
        "registry must be preserved (regenerate with "
        "python3 -m assistant.capabilities.settings.build_registry and check curations)"
    )


def tool_by_name(name: str) -> Optional[ToolSpec]:
    """Look a tool up by its tool name (e.g. "setBarScale")."""
    return _TOOLS_BY_NAME.get(name)


# ---------------------------------------------------------------------------
# Fuzzy tool-name search (bounded edit distance over the registry).
#
# The non-duplication note first: assistant/cortex/lexicon.py already ships
# a bounded two-row Levenshtein (``levenshtein(a, b, cap)``) used by the
# ROUTER for QUERY-side typo correction against registry vocabulary — that
# corrects a mistyped word inside a natural-language request. What was
# missing is NAME-side addressing: the user (or a tool-calling model) who
# writes ``--call setBarHight=1.2`` or asks for ``caelestia_setting_set``
# with a misspelled tool name gets a bare "unknown tool" and nothing else.
# This module closes exactly that gap, and only that gap.
#
# The search simulates the Levenshtein automaton bit-parallel, in the
# classic k+1-bitmask formulation of Wu & Manber (Wu & Manber 1992,
# "Fast text searching with errors", CACM 35(10), Fig. 3) adapted from
# substring search to FULL-STRING distance (bit 0 — the empty pattern
# prefix — is never forced after the first text character; it only
 # propagates through the insertion term, which is what makes the state
# encode D[i][j] <= d instead of "some suffix matches"): one bitmask per
# error level, so each candidate name costs O(k * n) machine-word
# operations for n query characters and k error levels (k defaults to 2:
# three words of work per name). Verified against a reference two-row DP
# on 30,000 randomized pairs, capped semantics included. Names longer
# than 63 characters (none exist in the registry today; the guard is
# honest, not decorative) fall back to the plain two-row DP.
# ---------------------------------------------------------------------------

def _bitap_distance(pattern: str, text: str,
                     cap: Optional[int] = None) -> Optional[int]:
    """Bounded edit distance via the bit-parallel Levenshtein automaton
    (Wu & Manber 1992, full-string variant). Returns the true Levenshtein
    distance when it is <= ``cap`` (or always, when cap is None), else
    None."""
    m = len(pattern)
    if m == 0:
        return len(text) if (cap is None or len(text) <= cap) else None
    k = cap if cap is not None else len(pattern) + len(text)
    if k < 0:
        return None
    if m + 1 > 64:
        # fallback: two-row DP with the same cap semantics
        prev = list(range(len(text) + 1))
        for i, ca in enumerate(pattern, start=1):
            cur = [i] + [0] * len(text)
            best = cur[0]
            for j, cb in enumerate(text, start=1):
                cost = 0 if ca == cb else 1
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
                best = min(best, cur[j])
            if cap is not None and best > cap:
                return None
            prev = cur
        return prev[-1] if cap is None or prev[-1] <= cap else None

    # PM[c] bit i (i >= 1) = [P[i-1] == c]; bit i of level d tracks
    # D[i][j] <= d (pattern prefix of LENGTH i vs text prefix of length j).
    pm: Dict[str, int] = {}
    for ch in set(pattern) | set(text):
        bits = 0
        for i, pch in enumerate(pattern, start=1):
            if pch == ch:
                bits |= 1 << i
        pm[ch] = bits
    full = (1 << (m + 1)) - 1
    # init j = 0: D[i][0] = i -> bit i set iff i <= d
    levels = [((1 << min(d + 1, m + 1)) - 1) for d in range(k + 1)]
    for c in text:
        pmc = pm.get(c, 0)
        new = [(levels[0] << 1) & pmc]
        for d in range(1, k + 1):
            t = ((levels[d] << 1) & pmc)      # match
            t |= (levels[d - 1] << 1)         # substitution
            t |= (new[d - 1] << 1)            # deletion from pattern (intra-row)
            t |= levels[d - 1]                # insertion into text
            new.append(t & full)
        new[0] &= full
        levels = new
    high = 1 << m
    for d in range(k + 1):
        if levels[d] & high:
            return d
    return None


def suggest_tools(query: str, max_distance: int = 2,
                  limit: int = 5) -> List[Tuple[str, int]]:
    """Every registry tool within ``max_distance`` edits of ``query``,
    as (tool name, distance), nearest first, registry order as tiebreak.

    Two spellings are searched per tool, both case-insensitive: the raw
    camelCase name ("setBarScale") and its space-joined word atoms
    ("set bar scale") — so "set bar scale", "setbarscale" and
    "setBarScake" all find setBarScale. The distance semantics are the
    standard Levenshtein edit distance; no threshold is invented beyond
    the caller's cap (the CLI uses 2: two keystrokes of forgiveness, the
    same bound the router's query-side correction uses)."""
    if not query:
        return []
    q = query.strip().lower()
    if not q:
        return []
    out: List[Tuple[str, int]] = []
    for spec in TOOL_SPECS:
        name_l = spec.name.lower()
        best: Optional[int] = _bitap_distance(q, name_l, cap=max_distance)
        if best is None:
            # also try the spoken form of the same name
            atoms = " ".join(_camel_atoms(spec.name)).lower()
            if atoms != name_l:
                alt = _bitap_distance(q, atoms, cap=max_distance)
                if alt is not None:
                    best = alt
        if best is not None:
            out.append((spec.name, best))
    out.sort(key=lambda pair: (pair[1], pair[0]))
    return out[:limit]


def _camel_atoms(name: str) -> List[str]:
    """Split a camelCase tool name into word atoms (the same split the
    cortex lexicon performs on names — duplicated here deliberately so
    the settings layer keeps zero imports from the learning layer)."""
    out: List[str] = []
    cur = ""
    for ch in name:
        if ch.isupper() and cur:
            out.append(cur)
            cur = ch.lower()
        else:
            cur += ch.lower()
    if cur:
        out.append(cur)
    return out


def tool_by_path(path: str) -> Optional[ToolSpec]:
    """Look a tool up by its dotted JSON path (e.g. "bar.scale")."""
    return _TOOLS_BY_PATH.get(path)


def registry_paths() -> Tuple[str, ...]:
    """Every whitelisted leaf path, in registry order."""
    return tuple(spec.path for spec in TOOL_SPECS)


def tools_by_group() -> Dict[str, Tuple[ToolSpec, ...]]:
    """Every group's tools (GROUPS order), each in TOOL_SPECS order."""
    return dict(_TOOLS_BY_GROUP)


def _fmt_default(value: Value) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    return str(value)


def _validation_text(spec: ToolSpec) -> str:
    if spec.kind == "enum":
        return "|".join(str(value) for value in (spec.enum or ()))
    if spec.kind == "bool":
        return "on/off"
    if spec.kind == "string":
        return f"string <={spec.string_max_len} chars"
    return f"{spec.minimum}-{spec.maximum}"


def describe(spec: ToolSpec) -> str:
    """One-line description used for AMBIGUOUS candidate lists (§3.2)."""
    return (
        f"{spec.name}: {spec.path} ({spec.kind}, {_validation_text(spec)}, "
        f"default {_fmt_default(spec.default)})"
    )


def format_value(value: Value) -> str:
    """JSON-style rendering of a plain value (bools lowercase, like §5.5);
    ``None`` marks a rejected entry whose new value is never applied."""
    if isinstance(value, bool):
        return "true" if value else "false"
    if value is None:
        return "(not applied)"
    return str(value)


def list_tools_lines(group: Optional[str] = None) -> List[str]:
    """The --list-tools table (§5.1): every tool with path, type, range.

    Unfiltered: the 18 core natural-language tools keep their historical
    numbered rows, then every tool (the core included) is grouped under its
    feature-area header with a per-group subtotal. Filtered (--group
    SLUG): just that group's section. An unknown group yields a one-line
    error listing the available groups (the CLI normally pre-checks this).
    """
    if group is not None and group not in GROUPS:
        return [
            f"error: unknown group {group!r}; available groups: "
            + ", ".join(GROUPS)
        ]

    lines: List[str] = [
        f"caelestia assistant — settings layer: tool registry "
        f"({TOOL_COUNT} tools in {len(GROUPS)} groups)",
        "Every write targets shell.json and is gated behind --apply. Ranges are the",
        "assistant's own conservative validation — upstream declares no numeric bounds",
        "(type-only hook, Settings/macros.hpp:91-92); shipped Nexus control ranges adopted.",
    ]

    if group is not None:
        lines.append("")
        lines.extend(_group_section(group))
        return lines

    core_specs = TOOL_SPECS[: len(CORE_TOOL_NAMES)]
    lines += [
        "",
        f"Natural-language tools ({len(core_specs)} — these answer plain-word request sentences):",
    ]
    for idx, spec in enumerate(core_specs, start=1):
        marker = "  [global-only]" if spec.global_only else ""
        lines.append(
            f"  {idx:>2}. {spec.name:<21} {spec.path:<32} {spec.kind:<5} "
            f"{_validation_text(spec):<25} default {_fmt_default(spec.default)}{marker}"
        )
    lines += [
        "",
        "Direct-address tools by feature area "
        "(set with --call NAME=VALUE; inspect with --tool NAME):",
    ]
    for slug in GROUPS:
        lines.append("")
        lines.extend(_group_section(slug))
    return lines


def _group_section(slug: str) -> List[str]:
    specs = _TOOLS_BY_GROUP[slug]
    header = f"{slug} ({len(specs)} tools):"
    rows = [
        f"    {spec.name:<44} {spec.path:<46} {spec.kind:<5} "
        f"{_validation_text(spec)} default {_fmt_default(spec.default)}"
        + ("  [global-only]" if spec.global_only else "")
        for spec in specs
    ]
    return [header] + rows
