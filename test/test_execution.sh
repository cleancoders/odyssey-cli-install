#!/bin/bash

# Unit tests for lib/execution.sh

# Get the project root directory
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "${TEST_DIR}")"

# Source shunit2
SHUNIT2="${PROJECT_DIR}/shunit2"

# Source the file under test
# shellcheck disable=SC1090
source "${PROJECT_DIR}/lib/execution.sh"

# Test fixtures
TEST_OUTPUT_DIR=""
MOCK_SUDO=""

# Setup function - runs before each test
setUp() {
  # Create a temporary directory for test output
  TEST_OUTPUT_DIR="$(mktemp -d)"

  # Create a mock for sudo
  MOCK_SUDO="${TEST_OUTPUT_DIR}/sudo"

  # Create log file to track sudo calls
  SUDO_CALLS_LOG="${TEST_OUTPUT_DIR}/sudo_calls.log"
  cat > "${MOCK_SUDO}" << EOF
#!/bin/bash
# Stores args and returns success/failure
echo "\$@" >> "${SUDO_CALLS_LOG}"
exit \${MOCK_SUDO_EXIT_CODE:-0}
EOF

  chmod +x "${MOCK_SUDO}"

  unset HAVE_SUDO_ACCESS
  unset SUDO_ASKPASS
  unset NONINTERACTIVE
  unset ODYSSEY_ON_MACOS

  export UNDER_TEST=true
}

# Teardown function - runs after each test
tearDown() {
  # Clean up temporary directory
  if [[ -n "${TEST_OUTPUT_DIR}" && -d "${TEST_OUTPUT_DIR}" ]]; then
    rm -rf "${TEST_OUTPUT_DIR}"
  fi

  unset UNDER_TEST
}

# Example test - replace with actual tests
test_sudo_access_returns_success() {
  have_sudo_access "${MOCK_SUDO}"
  local result=$?
  assertEquals "should return success" 0 ${result}
}



# Load and run shunit2
# shellcheck disable=SC1090
. "${SHUNIT2}"
