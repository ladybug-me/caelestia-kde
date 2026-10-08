"""executor.runner — the tiny process runner.

Runs typed ActionPlans. Contract:
- argv TUPLES only (a str argv cannot reach here; Step rejects it);
- never shell=True;
- every run is timeout-bounded;
- honest result dicts, never exceptions across the boundary;
- if a postcondition probe fails after a mutating plan, the runner
  executes the plan's revert and SAYS SO in the result.

The runner is the one place in assistant/ that imports subprocess
(together with the dbus surface, pending its executor migration).
"""
from __future__ import annotations

import math
import subprocess
from typing import Any, Dict

from .plan import ActionPlan, Step

__all__ = ["run", "run_step", "auto_apply_allowed", "AUTO_APPLY_FLOOR"]

_RUNNER = {"subprocess": subprocess}  # patchable point for tests

# The auto-apply floor: a journaled/reversible plan may run without a
# prompt only when its calibrated confidence clears this Beta-posterior
# lower bound (Beta(1,1) prior, one observed success and no failures —
# i.e. the LOWEST honest floor; it rises with real approval history as
# the brain's posterior thickens). Destructive/privileged classes never
# clear it by construction (plan.py refuses system-blast-radius
# auto-apply entirely).
AUTO_APPLY_FLOOR = 0.5


def auto_apply_allowed(plan: ActionPlan,
                       successes: int = 0, failures: int = 0) -> bool:
    """Beta-posterior lower bound (Wilson-style one-sided 95%) on the
    true success rate must clear AUTO_APPLY_FLOOR; read-only plans are
    always allowed; system blast radius is never auto-applied."""
    if plan.reversibility == "read_only":
        return True
    if plan.reversibility in ("confirm", "privileged") \
            or plan.blast_radius == "system":
        return False
    if plan.reversibility not in ("journaled", "reversible"):
        return False
    n = successes + failures
    if n == 0:
        # pure prior: Beta(1,1) 5th percentile ≈ 0.05 — far below the floor
        return False
    z = 1.645
    phat = successes / n
    lower = (phat + z * z / (2 * n)
             - z * math.sqrt((phat * (1 - phat) + z * z / (4 * n)) / n)) \
        / (1 + z * z / n)
    return lower >= AUTO_APPLY_FLOOR


def run_step(step: Step) -> Dict[str, Any]:
    """Run one step. Returns an honest dict; never raises across the
    boundary (timeouts and missing binaries are results, not crashes)."""
    try:
        completed = _RUNNER["subprocess"].run(
            list(step.argv), capture_output=True, text=True,
            timeout=step.timeout_s, check=False)
    except subprocess.TimeoutExpired:
        return {"argv": list(step.argv), "ok": False,
                "error": f"timeout after {step.timeout_s}s"}
    except OSError as exc:
        return {"argv": list(step.argv), "ok": False,
                "error": f"{type(exc).__name__}: {exc}"}
    return {
        "argv": list(step.argv),
        "ok": completed.returncode == 0,
        "returncode": completed.returncode,
        "stdout": completed.stdout,
        "stderr": completed.stderr,
    }


def run(plan: ActionPlan) -> Dict[str, Any]:
    """Run an ActionPlan: steps in order; on failure stop and report;
    on postcondition failure after a mutating plan, run the revert and
    mark the result reverted=True. Read-only plans never auto-revert
    (there is nothing to revert)."""
    results = []
    for step in plan.steps:
        res = run_step(step)
        results.append(res)
        if not res["ok"]:
            return {
                "plan": plan.description or "<unnamed>",
                "ok": False, "reverted": False,
                "stopped_at": list(step.argv),
                "steps": results,
            }
    post_ok = True
    if plan.postcondition_argv is not None:
        probe = run_step(Step(plan.postcondition_argv))
        post_ok = probe["ok"]
        results.append({"postcondition": probe})
    if post_ok:
        return {"plan": plan.description or "<unnamed>", "ok": True,
                "reverted": False, "steps": results}
    # postcondition failed: auto-revert mutating plans
    if plan.revert is not None:
        rev = run(plan.revert)
        return {"plan": plan.description or "<unnamed>", "ok": False,
                "reverted": bool(rev.get("ok")),
                "steps": results, "revert": rev}
    if plan.on_postcondition_fail is not None:
        plan.on_postcondition_fail({"plan": plan.description,
                                    "steps": results})
    return {"plan": plan.description or "<unnamed>", "ok": False,
            "reverted": False, "steps": results}
