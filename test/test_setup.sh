#!/bin/bash

# Unit tests for lib/setup.sh

# Get the project root directory
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "${TEST_DIR}")"

# Source shunit2
SHUNIT2="${PROJECT_DIR}/shunit2"

# Source library dependencies
# shellcheck disable=SC1090
source "${PROJECT_DIR}/lib/utils.sh"
# shellcheck disable=SC1090
source "${PROJECT_DIR}/lib/ui.sh"

# Source the file under test
# shellcheck disable=SC1090
source "${PROJECT_DIR}/lib/setup.sh"

# Setup function - runs before each test
setUp() {
  # Clear environment variables
  unset NONINTERACTIVE
  unset INTERACTIVE
  unset CI
  unset ODYSSEY_ON_LINUX
  unset ODYSSEY_ON_MACOS
  unset ODYSSEY_PREFIX
  unset ODYSSEY_REPOSITORY
  unset ODYSSEY_CACHE
  unset USER
}

# Teardown function - runs after each test
tearDown() {

  # Clean up environment variables that tests might have set
  unset POSIXLY_CORRECT
  unset CI
  unset INTERACTIVE
  unset NONINTERACTIVE
  unset ODYSSEY_PREFIX
  unset ODYSSEY_REPOSITORY
  unset ODYSSEY_CACHE
  unset ODYSSEY_ON_MACOS
  unset ODYSSEY_ON_LINUX
  unset UNAME_MACHINE
  unset USER
  unset ADD_PATHS_D
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
}

test_setup_paths_sets_macos_prefix_for_arm64() {
  # Test macOS ARM64 path setup
  ODYSSEY_ON_MACOS=1
  unset ODYSSEY_ON_LINUX

  # Mock uname to return arm64
  # shellcheck disable=SC2317
  /usr/bin/uname() {
    echo "arm64"
  }
  export -f /usr/bin/uname

  setup_paths

  assertEquals "should set /usr/local prefix for ARM macOS" "/usr/local" "${ODYSSEY_PREFIX}"
  assertEquals "should set repository to prefix on ARM macOS" "/usr/local/odyssey" "${ODYSSEY_REPOSITORY}"
}

test_setup_paths_sets_macos_prefix_for_intel() {
  # Test macOS Intel path setup
  ODYSSEY_ON_MACOS=1
  unset ODYSSEY_ON_LINUX

  # Mock uname to return x86_64
  # shellcheck disable=SC2317
  /usr/bin/uname() {
    echo "x86_64"
  }
  export -f /usr/bin/uname

  setup_paths

  assertEquals "should set /usr/local prefix for Intel macOS" "/usr/local" "${ODYSSEY_PREFIX}"
  assertEquals "should set repository under prefix on Intel macOS" "/usr/local/odyssey" "${ODYSSEY_REPOSITORY}"
}

test_setup_paths_sets_linux_prefix() {
  # Test Linux path setup
  ODYSSEY_ON_LINUX=1
  unset ODYSSEY_ON_MACOS

  setup_paths

  assertEquals "should set Linux prefix" "/usr/local" "${ODYSSEY_PREFIX}"
  assertEquals "should set Linux repository" "/usr/local/odyssey" "${ODYSSEY_REPOSITORY}"
}
####################
# setup_sudo_trap
####################

test_setup_sudo_trap_checks_for_sudo() {
  # Verify the function checks if sudo exists and is executable
  type setup_sudo_trap | grep -q '/usr/bin/sudo'
  assertEquals "should check for /usr/bin/sudo" 0 $?
}

test_setup_sudo_trap_uses_sudo_dash_k() {
  # Verify the function uses 'sudo -k' to invalidate sudo timestamp
  type setup_sudo_trap | grep -q 'sudo -k'
  assertEquals "should use 'sudo -k' to invalidate timestamp" 0 $?
}

test_setup_sudo_trap_sets_exit_trap() {
  # Verify the function sets an EXIT trap
  type setup_sudo_trap | grep -q "trap.*EXIT"
  assertEquals "should set EXIT trap" 0 $?
}

test_setup_sudo_trap_checks_sudo_not_active() {
  # Verify the function checks if sudo is not already active with -n -v flags
  type setup_sudo_trap | grep -q 'sudo -n -v'
  assertEquals "should check if sudo is not already active" 0 $?
}

test_setup_sudo_trap_runs_without_error() {
  # Mock sudo to simulate it not being active
  /usr/bin/sudo() {
    # shellcheck disable=SC2317
    if [[ "$1" == "-n" && "$2" == "-v" ]]; then
      return 1  # Simulate sudo not active
    fi
    return 0
  }
  export -f /usr/bin/sudo

  setup_sudo_trap
  assertEquals "should run without error when sudo not active" 0 $?
}


# Load and run shunit2
# Suppress harmless function export warnings from shunit2
# shellcheck disable=SC1090
. "${SHUNIT2}" 2> >(grep -v "error importing function definition" >&2)
