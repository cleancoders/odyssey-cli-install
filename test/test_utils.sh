#!/bin/bash

# Unit tests for lib/utils.sh

# Get the project root directory
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "${TEST_DIR}")"

# Source shunit2
SHUNIT2="${PROJECT_DIR}/shunit2"

# Source the file under test
# shellcheck disable=SC1090
source "${PROJECT_DIR}/lib/utils.sh"

# Test fixtures
TEST_OUTPUT_DIR=""

# Setup function - runs before each test
setUp() {
  # Create a temporary directory for test output
  TEST_OUTPUT_DIR="$(mktemp -d)"
}

# Teardown function - runs after each test
tearDown() {
  # Clean up temporary directory
  if [[ -n "${TEST_OUTPUT_DIR}" && -d "${TEST_OUTPUT_DIR}" ]]; then
    rm -rf "${TEST_OUTPUT_DIR}"
  fi
}

# Example test - replace with actual tests
test_example() {
  assertTrue "Example test that always passes" "[ 1 -eq 1 ]"
}

# Add your tests here
# test_function_name() {
#   assertEquals "Description" "expected" "$(actual_command)"
# }

# Load and run shunit2
# shellcheck disable=SC1090
. "${SHUNIT2}"
