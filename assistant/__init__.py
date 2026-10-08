"""Caelestia on-device assistant.

Narrow, offline-first helper for caelestia-kde: deterministic diagnostics,
local retrieval over the repo's own docs and resolved issues, an optional
generative suggestion layer, and an issue-drafting helper.

Hard invariants (enforced by behavioral tests):
- The assistant never executes shell commands. Suggested commands are inert
  strings, always prefixed with SUGGESTED_NOT_EXECUTED.
- No network access except an explicitly enabled optional localhost Ollama
  call in the generative layer.
- Issue drafts are written to local files only and are never submitted.
"""

__version__ = "0.1.0"
