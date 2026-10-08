"""executor.plan — typed ActionPlans.

An ActionPlan is the ONLY thing the executor will run. Every step
carves the command as an argv TUPLE of str — never a shell string.
This is the structural half of the no-shell-injection posture: the
other half (what may run at all) lives in the confirm gates and the
per-capability manifests, not here.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from typing import Callable, Optional, Tuple

__all__ = ["ActionPlan", "Step", "Reversibility", "BlastRadius"]

# reversibility classes (the autonomy ladder, ordered safest first)
Reversibility = ("read_only", "journaled", "reversible", "irreversible")
# blast radius classes
BlastRadius = ("none", "file", "user_config", "package", "system")


@dataclass(frozen=True)
class Step:
    """One command. argv is a tuple of str — a bare str argv is a
    constructor-time TypeError, not a runtime surprise."""
    argv: Tuple[str, ...]
    timeout_s: float = 10.0

    def __post_init__(self):
        if isinstance(self.argv, str):
            raise TypeError(
                "Step.argv must be a tuple of str, never a shell string "
                "(executor contract: argv arrays only)")
        argv = tuple(self.argv)
        if not argv or not all(isinstance(a, str) for a in argv):
            raise TypeError(
                f"Step.argv must be a non-empty tuple of str, got {self.argv!r}")
        object.__setattr__(self, "argv", argv)


@dataclass(frozen=True)
class ActionPlan:
    """A typed plan the executor can run: argv arrays only, with the
    safety metadata every caller must own up to. The proposal protocol
    (capability 3) adds the fields a reviewer needs BEFORE approving:
    evidence for the change, a calibrated confidence (a probability in
    [0,1], never a vibe), reversibility class, and blast radius."""
    steps: Tuple[Step, ...]
    reversibility: str = "read_only"      # one of Reversibility
    blast_radius: str = "none"            # one of BlastRadius
    description: str = ""
    # capability-3 proposal protocol:
    evidence: Tuple[str, ...] = ()        # cited facts behind the change
    confidence: float = 0.0               # calibrated probability in [0,1]
    # postcondition: argv of a probe to run after the steps; a non-zero
    # exit means the plan did NOT hold and the caller must revert.
    postcondition_argv: Optional[Tuple[str, ...]] = None
    # revert: the plan that undoes this one (required unless read_only)
    revert: Optional["ActionPlan"] = None
    on_postcondition_fail: Optional[Callable[[dict], None]] = field(
        default=None, compare=False)

    def __post_init__(self):
        if self.reversibility not in Reversibility:
            raise TypeError(f"reversibility must be one of {Reversibility}")
        if self.blast_radius not in BlastRadius:
            raise TypeError(f"blast_radius must be one of {BlastRadius}")
        if not self.steps:
            raise TypeError("ActionPlan needs at least one step")
        if isinstance(self.steps, list):
            object.__setattr__(self, "steps", tuple(self.steps))
        if not (0.0 <= self.confidence <= 1.0):
            raise TypeError("confidence is a calibrated probability in [0,1]")
        if (self.reversibility not in ("read_only", "journaled", "reversible")
                and self.revert is None):
            raise TypeError(
                "plans that are not read-only/journaled/reversible must "
                "carry a revert plan")
        # the autonomy ladder: a mutating plan may only auto-apply when
        # its calibrated confidence clears the Beta-posterior lower bound
        # threshold recorded in runner.AUTO_APPLY_FLOOR — and never when
        # the blast radius is system-wide.
        if (self.reversibility in ("journaled", "reversible")
                and self.blast_radius == "system"
                and self.confidence < 1.0):
            raise TypeError(
                "system-blast-radius plans require explicit confirmation "
                "(confidence cannot substitute for consent)")
