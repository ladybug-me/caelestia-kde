"""Capability manifests: permissions, risk tier, ms/MB budgets.

One manifest per capability plugin, typed by CapManifest. The loader
(``all_manifests`` / ``manifest_for``) is the only sanctioned way to
read them; budgets are advisory upper bounds for the resource governor
(Phase 4.9), enforced at the call surface, not inside the plugin.
"""
from __future__ import annotations

from dataclasses import dataclass
from importlib import import_module
from typing import Dict, List

__all__ = ["CapManifest", "all_manifests", "manifest_for"]

# risk tiers, ordered by autonomy ladder (see executor.plan.Reversibility):
#   read_only   - runs without prompts
#   journaled   - runs without prompts; every write is journaled+reversible
#   confirm     - requires explicit confirmation per change-set
#   privileged  - requires confirmation + capability flag (file edit, never NL)
TIERS = ("read_only", "journaled", "confirm", "privileged")


@dataclass(frozen=True)
class CapManifest:
    name: str
    permissions: tuple          # e.g. ("fs:read",) — declared capability surface
    risk_tier: str              # one of TIERS
    latency_budget_ms: int      # p95 budget for one CLI call
    memory_budget_mb: int       # peak RSS budget


_ALL = ("diagnostics", "retrieval", "generative", "issues", "settings",
        "graph", "brain", "genius", "agent", "devflow", "scan", "shellkb")


def all_manifests() -> List[CapManifest]:
    out = []
    for name in _ALL:
        mod = import_module(f"assistant.capabilities.{name}.manifest")
        out.append(mod.MANIFEST)
    return out


def manifest_for(name: str) -> CapManifest:
    mod = import_module(f"assistant.capabilities.{name}.manifest")
    return mod.MANIFEST
