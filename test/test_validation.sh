#!/bin/bash

# Unit tests for lib/validation.sh

# Get the project root directory
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "${TEST_DIR}")"

# Source shunit2
SHUNIT2="${PROJECT_DIR}/shunit2"

# Set required versions before sourcing validation.sh
# shellcheck disable=SC2034
REQUIRED_CURL_VERSION="7.41.0"
# shellcheck disable=SC2034
REQUIRED_GIT_VERSION="2.7.0"

# Source the file under test
# shellcheck disable=SC1090
source "${PROJECT_DIR}/lib/validation.sh"

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

####################
# test_curl
####################

test_test_curl_returns_false_for_nonexistent() {
  test_curl "/nonexistent/curl"
  assertNotEquals "should return non-zero for nonexistent curl" 0 $?
}

test_test_curl_returns_false_for_snap() {
  # Create a mock curl in snap location
  local mock_curl="${TEST_OUTPUT_DIR}/snap_curl"
  cat > "${mock_curl}" << 'EOF'
#!/bin/bash
echo "curl 7.68.0 (x86_64-pc-linux-gnu)"
EOF
  chmod +x "${mock_curl}"
  output=$(test_curl "/snap/bin/curl")
  assertNotEquals "should return non-zero for snap curl" 0 "${exit_code}"
  assertEquals "should warn about snap curl" 0 $?
}

test_test_curl_accepts_valid_version() {
  # Create a mock curl with valid version
  local mock_curl="${TEST_OUTPUT_DIR}/curl"
  cat > "${mock_curl}" << 'EOF'
#!/bin/bash
echo "curl 7.68.0 (x86_64-pc-linux-gnu) libcurl/7.68.0"
EOF
  chmod +x "${mock_curl}"

  test_curl "${mock_curl}"
  assertEquals "should accept curl version 7.68.0" 0 $?
}

test_test_curl_rejects_old_version() {
  # Create a mock curl with old version
  local mock_curl="${TEST_OUTPUT_DIR}/curl"
  cat > "${mock_curl}" << 'EOF'
#!/bin/bash
echo "curl 7.40.0 (x86_64-pc-linux-gnu) libcurl/7.40.0"
EOF
  chmod +x "${mock_curl}"

  test_curl "${mock_curl}"
  assertNotEquals "should reject curl version 7.40.0" 0 $?
}

####################
# test_git
####################

test_test_git_returns_false_for_nonexistent() {
  test_git "/nonexistent/git"
  assertNotEquals "should return non-zero for nonexistent git" 0 $?
}

test_test_git_accepts_valid_version() {
  # Create a mock git with valid version
  local mock_git="${TEST_OUTPUT_DIR}/git"
  cat > "${mock_git}" << 'EOF'
#!/bin/bash
echo "git version 2.30.0"
EOF
  chmod +x "${mock_git}"

  test_git "${mock_git}"
  assertEquals "should accept git version 2.30.0" 0 $?
}

test_test_git_rejects_old_version() {
  # Create a mock git with old version
  local mock_git="${TEST_OUTPUT_DIR}/git"
  cat > "${mock_git}" << 'EOF'
#!/bin/bash
echo "git version 2.6.0"
EOF
  chmod +x "${mock_git}"

  test_git "${mock_git}"
  assertNotEquals "should reject git version 2.6.0" 0 $?
}

test_test_git_aborts_on_unexpected_format() {
  # Create a mock git with unexpected output
  local mock_git="${TEST_OUTPUT_DIR}/git"
  cat > "${mock_git}" << 'EOF'
#!/bin/bash
echo "unexpected output"
EOF
  chmod +x "${mock_git}"

  output=$(test_git "${mock_git}" 2>&1)
  exit_code=$?

  assertEquals "should exit 1 on unexpected format" 1 ${exit_code}
  echo "$output" | grep "Unexpected Git version" >/dev/null
  assertEquals "should print error about unexpected format" 0 $?
}

####################
# which
####################

test_which_finds_executable() {
  result=$(which bash)
  [[ -n "$result" ]]
  assertEquals "should find bash" 0 $?
}

test_which_returns_empty_for_nonexistent() {
  result=$(which nonexistent_command_xyz)
  [[ -z "$result" ]]
  assertEquals "should return empty for nonexistent command" 0 $?
}

####################
# find_tool
####################

test_find_tool_returns_error_for_no_args() {
  find_tool
  assertNotEquals "should return non-zero with no arguments" 0 $?
}

test_find_tool_returns_error_for_multiple_args() {
  find_tool arg1 arg2
  assertNotEquals "should return non-zero with multiple arguments" 0 $?
}

test_find_tool_finds_curl() {
  result=$(find_tool curl)
  if [[ -n "$result" ]]; then
    [[ "$result" == /* ]]
    assertEquals "should return absolute path" 0 $?
  else
    # Skip test if curl not found on system
    startSkipping
  fi
}

test_find_tool_ignores_relative_paths() {
  # Mock the which function to return a relative path
  which() {
    # shellcheck disable=SC2317
    echo "relative/path/curl"
  }
  export -f which

  output=$(find_tool curl 2>&1)

  echo "$output" | grep "relative paths don't work" >/dev/null
  assertEquals "should warn about relative paths" 0 $?
}

# Load and run shunit2
# shellcheck disable=SC1090
. "${SHUNIT2}"
