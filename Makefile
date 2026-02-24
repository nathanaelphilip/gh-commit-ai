# gh-commit-ai Build System
# Concatenates src/ modules into the single-file gh-commit-ai script

SHELL := /bin/bash
SRC_DIR := src
OUTPUT := gh-commit-ai
MODULES := $(sort $(wildcard $(SRC_DIR)/*.sh))

.PHONY: build test verify clean

# Build: concatenate all src/*.sh modules (sorted by numeric prefix)
build: $(OUTPUT)

$(OUTPUT): $(MODULES)
	@echo "Building $(OUTPUT) from $(words $(MODULES)) modules..."
	@cat $(MODULES) > $(OUTPUT)
	@chmod +x $(OUTPUT)
	@echo "Built $(OUTPUT) ($(shell wc -l < $(OUTPUT)) lines)"

# Run unit tests
test: $(OUTPUT)
	@echo "Running tests..."
	@bats tests/

# Verify all expected functions exist in the built output
verify: $(OUTPUT)
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
