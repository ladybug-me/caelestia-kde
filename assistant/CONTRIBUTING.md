# Contributing

- Python 3.12+, stdlib only (optional extras: `pip install ".[all]"`).
- Run the suite before proposing anything: `python3 -m unittest discover -s . -p "test_*.py"`,
  then `python3 -m assistant.hub selfcheck` and `bash tests/test_assistant.sh`.
- Every capability ships with a manifest (permissions, risk tier, budgets)
  and tests. Behavior changes need eval evidence: `python3 -m assistant eval --json`.
- Commands are passed as argv arrays through `assistant/executor` — never
  shell strings. Destructive or privileged actions require explicit confirm.
- Golden outputs (`tests/goldens/`) change only via
  `python3 scripts/regen_goldens.py` with a reviewed commit explaining why.
- No model files are ever committed or bundled.
- Keep the tree lean: no changelogs, scratch files, or committed build artifacts.
