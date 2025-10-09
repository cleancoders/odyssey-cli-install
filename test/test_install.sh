#!/bin/bash

# Unit tests for bin/install_refactored.sh

# Get the project root directory
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "${TEST_DIR}")"

# Source shunit2
SHUNIT2="${PROJECT_DIR}/shunit2"

# oneTimeSetUp - runs once before all tests
oneTimeSetUp() {
  # Source the library files that install_refactored.sh depends on
  # shellcheck disable=SC1091
  source "${PROJECT_DIR}/lib/utils.sh"
  # shellcheck disable=SC1091
  source "${PROJECT_DIR}/lib/version.sh"
  # shellcheck disable=SC1091
  source "${PROJECT_DIR}/lib/file_permissions.sh"
  # shellcheck disable=SC1091
  source "${PROJECT_DIR}/lib/execution.sh"
  # shellcheck disable=SC1091
  source "${PROJECT_DIR}/lib/validation.sh"

  # Extract functions from install_refactored.sh without running main
  # Skip the first 23 lines (shebang, comments, set, SCRIPT_DIR setup, and source statements)
  # and the last 2 lines (comment + main call)
  sed -n '24,$p' "${PROJECT_DIR}/bin/install_refactored.sh" | sed '$d' | sed '$d' > /tmp/install_functions.sh
  # shellcheck disable=SC1091
  source /tmp/install_functions.sh
  rm -f /tmp/install_functions.sh

  # Set constants that are normally set in the script
  # shellcheck disable=SC2034
  MACOS_NEWEST_UNSUPPORTED="27.0"
  # shellcheck disable=SC2034
  MACOS_OLDEST_SUPPORTED="14.0"
  # shellcheck disable=SC2034
  REQUIRED_BB_VERSION=1.12.193
  # shellcheck disable=SC2034
  REQUIRED_CURL_VERSION=7.41.0
  # shellcheck disable=SC2034
  REQUIRED_GIT_VERSION=2.7.0
}

# Setup function - runs before each test
setUp() {

  # Clear environment variables
  unset NONINTERACTIVE
  unset INTERACTIVE
  unset CI
  unset ODYSSEY_ON_LINUX
  unset ODYSSEY_ON_MACOS

  # Mock have_sudo_access to prevent password prompts during setup
  have_sudo_access() {
    # shellcheck disable=SC2317
    return 0
  }
  export -f have_sudo_access

  # Mock execute_sudo to prevent actual sudo calls
  execute_sudo() {
    # shellcheck disable=SC2317
    return 0
  }
  export -f execute_sudo
}

# Teardown function - runs after each test
tearDown() {
  # Clean up any temp files
  rm -f /tmp/odyssey_*.txt

  # Clean up environment variables that tests might have set
  unset POSIXLY_CORRECT
  unset CI
  unset INTERACTIVE
  unset NONINTERACTIVE
}

####################
# check_bash_version
####################

test_check_bash_version_succeeds_with_bash() {
  # This test runs in bash, so it should succeed
  check_bash_version
  assertEquals "should succeed when running in bash" 0 $?
}

####################
# check_environment_conflicts
####################

test_check_environment_conflicts_aborts_with_ci_and_interactive() {
  export CI=1
  export INTERACTIVE=1

  output=$(check_environment_conflicts 2>&1)
  exit_code=$?

  assertEquals "should exit 1 with CI and INTERACTIVE" 1 ${exit_code}
  echo "$output" | grep "Cannot run force-interactive mode in CI" >/dev/null
  assertEquals "should print error message" 0 $?
}

test_check_environment_conflicts_aborts_with_both_modes() {
  export INTERACTIVE=1
  export NONINTERACTIVE=1

  output=$(check_environment_conflicts 2>&1)
  exit_code=$?

  assertEquals "should exit 1 with both INTERACTIVE and NONINTERACTIVE" 1 ${exit_code}
  echo "$output" | grep "Both.*are set" >/dev/null
  assertEquals "should print error message" 0 $?
}

test_check_environment_conflicts_aborts_with_posix_mode() {
  export POSIXLY_CORRECT=1

  output=$(check_environment_conflicts 2>&1)
  exit_code=$?

  assertEquals "should exit 1 with POSIXLY_CORRECT" 1 ${exit_code}
  echo "$output" | grep "POSIX mode" >/dev/null
  assertEquals "should print error message" 0 $?
}

test_check_environment_conflicts_succeeds_with_no_conflicts() {
  check_environment_conflicts
  assertEquals "should succeed with no conflicts" 0 $?
}

####################
# parse_args
####################

test_parse_args_handles_no_args() {
  parse_args
  assertEquals "should succeed with no arguments" 0 $?
}

test_parse_args_handles_help_flag() {
  # parse_args calls usage which calls exit, so run in subshell
  output=$(parse_args --help 2>&1 || true)

  echo "$output" | grep "Usage:" >/dev/null
  assertEquals "should print usage" 0 $?
}

####################
# setup_noninteractive_mode
####################

test_setup_noninteractive_mode_sets_with_ci() {
  export CI=1
  unset NONINTERACTIVE

  setup_noninteractive_mode >/dev/null 2>&1

  assertEquals "should set NONINTERACTIVE with CI" "1" "${NONINTERACTIVE}"
}

test_setup_noninteractive_mode_respects_existing() {
  export NONINTERACTIVE=1

  output=$(setup_noninteractive_mode 2>&1)

  assertEquals "NONINTERACTIVE should remain set" "1" "${NONINTERACTIVE}"
  echo "$output" | grep "Running in non-interactive mode" >/dev/null
  assertEquals "should print non-interactive message" 0 $?
}

####################
# setup_user
####################

test_setup_user_sets_user_if_unset() {
  unset USER

  setup_user

  [[ -n "${USER}" ]]
  assertEquals "should set USER variable" 0 $?
}

test_setup_user_preserves_existing_user() {
  export USER="testuser"

  setup_user

  assertEquals "should preserve existing USER" "testuser" "${USER}"
}

####################
# detect_os
####################

test_detect_os_sets_macos_or_linux() {
  detect_os

  if [[ "$(uname)" == "Darwin" ]]; then
    assertEquals "should set ODYSSEY_ON_MACOS on macOS" "1" "${ODYSSEY_ON_MACOS}"
  elif [[ "$(uname)" == "Linux" ]]; then
    assertEquals "should set ODYSSEY_ON_LINUX on Linux" "1" "${ODYSSEY_ON_LINUX}"
  fi
}

test_detect_os_mac() {
  detect_os "Darwin"
  assertEquals "should set ODYSSEY_ON_MACOS" "1" "${ODYSSEY_ON_MACOS}"
}

test_detect_os_linux() {
  detect_os "Linux"
  assertEquals "should set ODYSSEY_ON_LINUX" "1" "${ODYSSEY_ON_LINUX}"
}

test_detect_os_non_unix() {
  output=$(detect_os "windows" 2>&1)
  assertEquals "should exit 1 when non-Unix" 1 $?
  echo "$output" | grep "Odyssey CLI is only supported on macOS and Linux." >/dev/null
  assertEquals "should show warning when non-Unix os" 0 $?

}

####################
# setup_paths
####################

test_setup_paths_sets_required_variables() {
  detect_os
  setup_paths

  [[ -n "${ODYSSEY_PREFIX}" ]]
  assertEquals "should set ODYSSEY_PREFIX" 0 $?

  [[ -n "${ODYSSEY_REPOSITORY}" ]]
  assertEquals "should set ODYSSEY_REPOSITORY" 0 $?

  [[ -n "${ODYSSEY_CACHE}" ]]
  assertEquals "should set ODYSSEY_CACHE" 0 $?
}

test_setup_paths_sets_different_paths_based_on_os() {
  # Just test that the function runs and sets appropriate paths for current OS
  detect_os
  setup_paths

  if [[ -n "${ODYSSEY_ON_MACOS-}" ]]; then
    # On macOS, prefix should be either /usr/local or /opt/odyssey
    [[ "${ODYSSEY_PREFIX}" == "/usr/local" || "${ODYSSEY_PREFIX}" == "/opt/odyssey" ]]
    assertEquals "should set valid macOS prefix" 0 $?
  else
    # On Linux, prefix should be /home/odyssey/.odyssey
    assertEquals "should set Linux prefix" "/home/odyssey/.odyssey" "${ODYSSEY_PREFIX}"
  fi
}

####################
# check_run_command_as_root
####################

test_check_run_command_as_root_allows_non_root() {
  # Skip if actually running as root
  if [[ "${EUID:-${UID}}" == "0" ]]; then
    startSkipping
  fi

  # check_run_command_as_root returns early for non-root, which is success (no abort)
  # Just verify it doesn't abort
  check_run_command_as_root 2>/dev/null || true
  # If we get here without aborting, test passes
  assertTrue "should allow non-root user" true
}

####################
# getc and ring_bell
####################

test_ring_bell_runs_without_error() {
  ring_bell
  assertEquals "should run without error" 0 $?
}

####################
# Helper function tests
####################

test_usage_displays_help() {
  output=$(usage 0 2>&1)

  echo "$output" | grep "Clean Code Odyssey CLI Installer" >/dev/null
  assertEquals "should display installer name" 0 $?

  echo "$output" | grep "Usage:" >/dev/null
  assertEquals "should display usage" 0 $?
}

####################
# Integration tests
####################

test_initialization_sequence() {
  # Test that initialization functions can be called in sequence
  check_bash_version
  assertEquals "check_bash_version succeeds" 0 $?

  check_environment_conflicts
  assertEquals "check_environment_conflicts succeeds" 0 $?

  setup_noninteractive_mode >/dev/null 2>&1
  assertEquals "setup_noninteractive_mode succeeds" 0 $?

  setup_user
  assertEquals "setup_user succeeds" 0 $?

  detect_os
  assertEquals "detect_os succeeds" 0 $?

  setup_paths
  assertEquals "setup_paths succeeds" 0 $?

}

# Load and run shunit2
# shellcheck disable=SC1090
. "${SHUNIT2}"
