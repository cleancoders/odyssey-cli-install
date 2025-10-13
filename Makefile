.PHONY: test test-watch test-file build-install all help

# Default target
.DEFAULT_GOAL := help

help: ## Show this help message
	@echo 'Usage: make [target]'
	@echo ''
	@echo 'Available targets:'
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'
	@echo ''
	@echo 'Examples:'
	@echo '  make test-file FILE=lib/utils.sh'
	@echo '  make test-file FILE=bin/build_installer.sh'

test: ## Run all tests
	@./test/helper/run_tests_parallel.sh

test-watch: ## Watch for changes and re-run tests automatically
	@./test/helper/watch_tests.sh

test-file: ## Create a test file for a source file (use FILE=path/to/file.sh)
	@if [ -z "$(FILE)" ]; then \
		echo "Error: FILE parameter is required"; \
		echo "Usage: make test-file FILE=lib/utils.sh"; \
		exit 1; \
	fi
	@./test/helper/create_test.sh $(FILE)

build-install: ## Build the distributable install.sh
	@./bin/build_installer.sh

all: build-install test ## Build and test