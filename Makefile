.PHONY: test build clean help

# Default target
.DEFAULT_GOAL := help

help: ## Show this help message
	@echo 'Usage: make [target]'
	@echo ''
	@echo 'Available targets:'
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

test: ## Run all tests
	@./test/run_all_tests.sh

build: ## Build the distributable install.sh
	@./bin/build_installer.sh

clean: ## Remove generated files
	@rm -f install.sh
	@echo "Cleaned generated files"

all: clean build test ## Clean, build, and test
