"""executor — the single tiny process surface: typed ActionPlans, argv
arrays only, never strings. Nothing else in assistant/ (except the dbus
surface pending migration) touches subprocess."""
from .plan import ActionPlan, BlastRadius, Reversibility, Step
from .runner import AUTO_APPLY_FLOOR, auto_apply_allowed, run, run_step

__all__ = ["ActionPlan", "Step", "Reversibility", "BlastRadius",
           "run", "run_step", "auto_apply_allowed", "AUTO_APPLY_FLOOR"]
