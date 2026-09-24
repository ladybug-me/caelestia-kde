# Caelestia - developer entry points.
#
# Installing and updating stays with the shell entry points at the repo root
# (install.sh, update.sh, uninstall.sh) so the published `curl | sh` one-liner
# keeps working. Everything here is for working on the repo itself.
#
#   make            list every target
#   make test       everything CI runs for tests
#   make check      everything CI runs for lint

SHELL_DIR     := shell
PLASMOIDS_DIR := src/kde/plasmoids
INSTALLER_DIR := installer
TUI_DIR       := $(INSTALLER_DIR)/tui
BUILD_DIR     := $(INSTALLER_DIR)/build
STEPS_DIR     := scripts
TESTS_DIR     := tests
TOOLS_DIR     := tools
CI_DIR        := .github/scripts

PYTHON ?= python3
BASH   ?= bash

.DEFAULT_GOAL := help

.PHONY: help install update uninstall build-shell installer \
        test test-bash test-repo validate hygiene \
        check check-shell check-python check-qml search-coverage \
        sync-fetch sync-report translations clean

help: ## List the available targets
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

# Install / update
# These call the shipped entry points rather than reimplementing them, so the
# commands here and the published ones cannot drift apart.

install: ## Full install into the current user's session
	$(BASH) install.sh

update: ## Update an existing install (prompts for main or dev)
	$(BASH) update.sh

uninstall: ## Remove the shell, its configs and the lockscreen plugin
	$(BASH) uninstall.sh

# Build

build-shell: ## Build and install the C++ QML plugin (needs Qt6 + CMake; Linux only)
	$(BASH) $(STEPS_DIR)/08-build-shell.sh

installer: ## Compile the TUI installer to installer/build/caelestia-install
	cmake -B $(BUILD_DIR) -S $(TUI_DIR) -DCMAKE_BUILD_TYPE=Release
	cmake --build $(BUILD_DIR)

# Test

test: test-bash test-repo validate ## Run every test CI runs

test-bash: ## Run the bash helper and step-unit tests
	$(BASH) $(TESTS_DIR)/run-tests.sh

test-repo: ## Check cross-cutting invariants (paths, versions, workflows, submodules)
	$(PYTHON) -m unittest discover -s $(CI_DIR) -p 'test_*.py'

validate: ## Validate the installer's menu.json and theme.json
	$(PYTHON) $(CI_DIR)/validate_json_configs.py

hygiene: ## Check file sizes, merge markers, trailing whitespace, line endings
	$(PYTHON) $(CI_DIR)/check_file_hygiene.py --all

# Lint

check: check-python check-shell ## Lint the repo's own Python and shell

check-python: ## flake8 the repo's own Python (as CI does)
	$(PYTHON) -m flake8 $(CI_DIR)/ $(SHELL_DIR)/scripts/ \
		--exclude 'orion_search.py,menu_perf_stats.py' \
		--max-line-length=120 \
		--extend-ignore=E402,W503,E501,E203 \
		--count --show-source --statistics

check-shell: ## shellcheck and syntax-check every shell script
	$(BASH) $(CI_DIR)/check_shell_quality.sh

check-qml: ## QML conventions, syntax, imports, embedded bash, config references
	$(PYTHON) $(CI_DIR)/check_qml_conventions.py
	$(PYTHON) $(CI_DIR)/check_qml_syntax.py --source-root $(SHELL_DIR)
	$(PYTHON) $(CI_DIR)/check_qml_syntax.py --source-root $(PLASMOIDS_DIR)
	$(PYTHON) $(CI_DIR)/check_qml_imports.py --shell-root $(SHELL_DIR)
	$(PYTHON) $(CI_DIR)/check_embedded_bash.py
	$(PYTHON) $(CI_DIR)/check_config_references.py
	$(PYTHON) $(CI_DIR)/check_qml_deployment.py --source-root $(SHELL_DIR)

search-coverage: ## Report settings pages that no search entry can open
	$(PYTHON) $(CI_DIR)/audit_search_coverage.py

# Repo tooling

sync-fetch: ## Refresh the upstream mirror used by the shell sync report
	$(PYTHON) $(TOOLS_DIR)/sync-shell.py fetch

sync-report: ## Report how shell/ diverges from upstream
	$(PYTHON) $(TOOLS_DIR)/sync-shell.py report

translations: ## Refresh the Qt translation catalogs
	$(BASH) $(TOOLS_DIR)/update-translations.sh

clean: ## Remove build output
	rm -rf $(BUILD_DIR) $(SHELL_DIR)/build
