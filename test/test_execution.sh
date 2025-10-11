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
printf '%s ' "\$@" >> "${SUDO_CALLS_LOG}"
exit \${MOCK_SUDO_EXIT_CODE:-0}
EOF

  chmod +x "${MOCK_SUDO}"

  unset HAVE_SUDO_ACCESS
  unset SUDO_ASKPASS
  unset NONINTERACTIVE
  unset ODYSSEY_ON_MACOS
}

# Teardown function - runs after each test
tearDown() {
  # Clean up temporary directory
  if [[ -n "${TEST_OUTPUT_DIR}" && -d "${TEST_OUTPUT_DIR}" ]]; then
    rm -rf "${TEST_OUTPUT_DIR}"
  fi
}

mock_execute(){
    #shellcheck disable=SC2317
    #shellcheck disable=SC2050
    execute() {
      if [[ "$1" == "/usr/bin/sudo" ]]; then
        shift
        "${MOCK_SUDO}" "$@"
      else
        command "$@"
      fi
    }
    export -f execute
}

##################################
# have_sudo_access
##################################

test_sudo_access_returns_success() {
  have_sudo_access "${MOCK_SUDO}"
  local result=$?
  assertEquals "should return success" 0 ${result}
}

test_sudo_access_returns_1() {
  have_sudo_access "blah"
  local result=$?
  assertEquals "should return 1 when no sudo found" 1 ${result}
}

test_sudo_adds_askpass_flag() {
  export SUDO_ASKPASS="/path/to/askpass"
  have_sudo_access "${MOCK_SUDO}"
   # Check that sudo was called with -A flag
  grep -- "-A" "${SUDO_CALLS_LOG}" >/dev/null
  assertEquals "should call sudo with -A flag" 0 $?
}

test_sudo_adds_noninteractive_flag() {
  export NONINTERACTIVE=1
  have_sudo_access "${MOCK_SUDO}"
  # Check that sudo was called with -n flag
  grep -- "-n" "${SUDO_CALLS_LOG}" >/dev/null
  assertEquals "should call sudo with -n flag" 0 $?
}

test_sudo_askpass_takes_precedence_over_noninteractive() {
  export SUDO_ASKPASS="/path/to/askpass"
  export NONINTERACTIVE=1
  have_sudo_access "${MOCK_SUDO}"
  # Should have -A but not -n
  grep -- "-A" "${SUDO_CALLS_LOG}" >/dev/null
  assertEquals "should call sudo with -A flag" 0 $?
  grep -- "-n" "${SUDO_CALLS_LOG}" >/dev/null
  assertNotEquals "should not call sudo with -n flag" 0 $?
}

test_sudo_access_is_cached() {
  have_sudo_access "${MOCK_SUDO}"
  # Call it again - sudo should not be invoked again
  rm "${SUDO_CALLS_LOG}"
  have_sudo_access "${MOCK_SUDO}"
  assertFalse "should not call sudo again when cached" "[ -f '${SUDO_CALLS_LOG}' ]"
}

test_sudo_access_cached_value_is_used() {
  export HAVE_SUDO_ACCESS=0
  # Remove sudo to prove it's not being called
  rm "${MOCK_SUDO}"
  have_sudo_access
  assertEquals "should return cached value" 0 $?
}

test_no_sudo_on_mac() {
  export ODYSSEY_ON_MACOS=1
  export HAVE_SUDO_ACCESS=1
  # Run in subshell to capture output and prevent exit from killing test
  output=$(have_sudo_access "${MOCK_SUDO}" 2>&1)
  exit_code=$?
  assertEquals "should exit 1 if no sudo access on mac" 1 ${exit_code}
  # Check that abort was called with the expected message
  echo "$output" | grep "Need sudo access on macOS" >/dev/null
  assertEquals "should print error message about sudo" 0 $?
}

############
# execute
############

test_execute_runs_successful_command() {
  local test_file="${TEST_OUTPUT_DIR}/executed.txt"
  execute touch "${test_file}"
  assertTrue "should create file when command succeeds" "[ -f '${test_file}' ]"
}                                                                                       

test_execute_aborts_on_failure() {
  export ODYSSEY_ON_MACOS=0
  # Run in subshell to capture abort and prevent exit
  output=$(execute false 2>&1)
  exit_code=$?

  assertEquals "should exit 1 when command fails" 1 ${exit_code}
  echo "$output" | grep "Failed during: false" >/dev/null
  assertEquals "should print error message about failed command" 0 $?
}

test_execute_passes_arguments_correctly() {
  local test_file="${TEST_OUTPUT_DIR}/test.txt"
  execute echo "hello world" > "${test_file}"
  grep "hello world" "${test_file}" >/dev/null
  assertEquals "should pass arguments to command" 0 $?
}

############
# execute_sudo
############

test_execute_sudo_runs_without_sudo_when_root() {
  # We can't actually set EUID to 0, but we can test that when
  # have_sudo_access returns false (simulating no sudo), it runs without sudo
  local test_file="${TEST_OUTPUT_DIR}/sudo_test.txt"
  local execute_log="${TEST_OUTPUT_DIR}/execute_log.txt"

  # Mock have_sudo_access to return false (simulating EUID=0 or no sudo scenario)
  #shellcheck disable=SC2317
  have_sudo_access() {
    return 1
  }
  export -f have_sudo_access

  # Mock execute to log what it's called with
  #shellcheck disable=SC2317
  execute() {
    printf '%s ' "$@" >> "${execute_log}"
    command "$@"
  }
  export -f execute

  execute_sudo touch "${test_file}" >/dev/null 2>&1
  assertTrue "should create file" "[ -f '${test_file}' ]"
  # Verify sudo was NOT called
  grep "/usr/bin/sudo" "${execute_log}" >/dev/null
  assertNotEquals "should not call sudo when have_sudo_access returns false" 0 $?
}

test_execute_sudo_calls_sudo_with_command() {
  # Mock have_sudo_access to return success without prompting
  #shellcheck disable=SC2317
  have_sudo_access() {
    return 0
  }
  export -f have_sudo_access
  mock_execute


  execute_sudo echo "test command" >/dev/null 2>&1
  grep "echo test command" "${SUDO_CALLS_LOG}" >/dev/null
  assertEquals "should pass command to sudo" 0 $?
}

test_execute_sudo_adds_askpass_flag() {
  export SUDO_ASKPASS="/path/to/askpass"

  # Mock have_sudo_access to return success without prompting
  #shellcheck disable=SC2317
  have_sudo_access() {
    return 0
  }
  export -f have_sudo_access
  mock_execute

  execute_sudo echo "test" >/dev/null 2>&1
  grep -- "-A" "${SUDO_CALLS_LOG}" >/dev/null
  assertEquals "should add -A flag when SUDO_ASKPASS is set" 0 $?

  unset SUDO_ASKPASS
}

# Load and run shunit2
# shellcheck disable=SC1090
. "${SHUNIT2}"

#  1. Test the caching behavior (easiest - set HAVE_SUDO_ACCESS before calling)
#  2. Test environment variable handling (check if -A or -n flags would be used)
#  3. Mock abort() to test macOS failure case
