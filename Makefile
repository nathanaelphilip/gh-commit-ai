# gh-commit-ai Build System
# Concatenates src/ modules into the single-file gh-commit-ai script

SHELL := /bin/bash
SRC_DIR := src
OUTPUT := gh-commit-ai
MODULES := $(sort $(wildcard $(SRC_DIR)/*.sh))

.PHONY: build test test-bats test-sh verify verify-sync lint clean

# Build: concatenate all src/*.sh modules (sorted by numeric prefix).
#
# Deliberately unconditional rather than a timestamp rule on $(MODULES).
# Hand-editing the built script makes it NEWER than its sources, so a
# timestamp-driven rule would decide there was nothing to do and leave the
# hand-edit in place - which is how the built file drifted 819 lines ahead of
# src/ without anyone noticing. Concatenating 25 files costs nothing.
build:
	@echo "Building $(OUTPUT) from $(words $(MODULES)) modules..."
	@cat $(MODULES) > $(OUTPUT)
	@chmod +x $(OUTPUT)
	@echo "Built $(OUTPUT) ($$(wc -l < $(OUTPUT) | tr -d ' ') lines)"

# Confirm the committed single-file script still matches src/.
#
# gh-commit-ai is generated output, but it is also the file the gh extension
# installs, so it is committed. Nothing used to check the two agreed and they
# silently drifted 819 lines apart, which meant a later `make build` would have
# quietly deleted working features. This is the guard that was missing.
verify-sync:
	@printf 'Checking src/ matches %s... ' "$(OUTPUT)"
	@if cat $(MODULES) | cmp -s - $(OUTPUT); then \
		echo "in sync."; \
	else \
		echo "OUT OF SYNC."; \
		echo "  $(OUTPUT) does not match 'cat $(SRC_DIR)/*.sh'."; \
		echo "  If src/ is correct, run 'make build' and commit both."; \
		echo "  If $(OUTPUT) was hand-edited, port the change into src/ first."; \
		exit 1; \
	fi

# Run every test suite: the bats files and the plain-bash ones.
#
# `bats tests/` only globs *.bats, so the five tests/*.sh suites were invisible
# to `make test` - and tests/test_repo_scoping.sh was referenced nowhere at all,
# in neither the Makefile nor either workflow.
test: test-bats test-sh

test-bats: build
	@echo "Running bats suites..."
	@bats tests/

test-sh: build
	@echo "Running shell suites..."
	@failed=0; \
	for t in tests/*.sh; do \
		[ -f "$$t" ] || continue; \
		echo "  → $$t"; \
		bash "$$t" >/dev/null 2>&1 || { echo "    FAILED: $$t"; failed=1; }; \
	done; \
	if [ $$failed -ne 0 ]; then echo "Shell test suite(s) failed."; exit 1; fi
	@echo "Shell suites passed."

# Lint the generated script. Kept as its own target so CI can gate on it.
lint: build
	@echo "Running shellcheck..."
	@shellcheck -S warning $(OUTPUT)

# Verify all expected functions exist in the built output
verify: build
	@echo "Verifying built script..."
	@errors=0; \
	for func in parse_yaml_config detect_language create_secure_temp_file \
		validate_positive_integer sanitize_string check_network_connectivity \
		show_offline_error show_api_key_error retry_api_call \
		detect_available_providers get_best_ollama_model \
		generate_changelog suggest_next_version suggest_commit_splits \
		generate_code_review generate_pr_description \
		save_message_history get_last_message is_recent_message clear_message_history \
		get_diff_hash get_cached_response save_cached_response \
		show_spinner smart_sample_diff analyze_commit_size \
		detect_smart_type detect_breaking_changes analyze_commit_history \
		detect_wordpress_plugin_update extract_file_context \
		extract_changed_functions extract_wordpress_function_calls \
		lookup_wordpress_function build_wordpress_context \
		get_best_commit_examples analyze_change_type \
		generate_file_summaries detect_file_relationships \
		escape_json unescape_json enforce_lowercase auto_fix_message \
		detect_trailing_whitespace detect_line_endings detect_missing_final_newline \
		fix_trailing_whitespace fix_line_endings fix_missing_final_newline \
		check_and_fix_formatting cloud_providers_in_play diagnose_network_failure \
		ollama_model_list untracked_files_diff create_secure_temp_dir \
		detect_project_type load_template parse_commit_components apply_template \
		calculate_cost track_cumulative_cost strip_ansi_codes convert_newlines \
		parse_multiple_options display_options select_option \
		call_ollama call_anthropic call_openai call_groq; do \
		if ! grep -q "^$${func}()" $(OUTPUT); then \
			echo "MISSING: $${func}()"; \
			errors=$$((errors + 1)); \
		fi; \
	done; \
	if [ $$errors -eq 0 ]; then \
		echo "All functions verified present."; \
	else \
		echo "$$errors function(s) missing!"; \
		exit 1; \
	fi
	@echo "Verifying shebang..."
	@head -1 $(OUTPUT) | grep -q '^#!/usr/bin/env bash' || { echo "MISSING shebang!"; exit 1; }
	@echo "Verifying executable..."
	@test -x $(OUTPUT) || { echo "Not executable!"; exit 1; }
	@echo "Verification passed."

# Remove built output (use with caution)
clean:
	@echo "Note: $(OUTPUT) is committed to the repo for gh extension install."
	@echo "Run 'make build' to rebuild it."
