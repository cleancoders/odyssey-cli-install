#!/bin/bash

# Unit tests for bin/file_permissions.sh

# Get the project root directory
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "${TEST_DIR}")"

# Source shunit2
SHUNIT2="${PROJECT_DIR}/shunit2"

# Setup STAT_PRINTF and PERMISSION_FORMAT based on OS
if [[ "$(uname)" == "Darwin" ]]; then
  STAT_PRINTF=("/usr/bin/stat" "-f")
  PERMISSION_FORMAT="%A"
else
  STAT_PRINTF=("/usr/bin/stat" "-c")
  PERMISSION_FORMAT="%a"
fi

# Source the file under test
# shellcheck disable=SC1090
source "${PROJECT_DIR}/lib/file_permissions.sh"

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
# get_permission
####################

test_get_permission_returns_permission() {
  local test_file="${TEST_OUTPUT_DIR}/test.txt"
  touch "${test_file}"
  chmod 644 "${test_file}"

  # shellcheck disable=SC2155
  local result=$(get_permission "${test_file}")

  # Result should be numeric permissions
  [[ "${result}" =~ ^[0-7]+$ ]]
  assertEquals "should return numeric permissions" 0 $?
}

test_get_permission_for_directory() {
  local test_dir="${TEST_OUTPUT_DIR}/test_dir"
  mkdir "${test_dir}"
  chmod 755 "${test_dir}"
# shellcheck disable=SC2155
  local result=$(get_permission "${test_dir}")

  assertEquals "should return 755 for directory" "755" "${result}"
}

####################
# user_only_chmod
####################

test_user_only_chmod_returns_true_for_700() {
  local test_dir="${TEST_OUTPUT_DIR}/test_dir"
  mkdir "${test_dir}"
  chmod 700 "${test_dir}"

  user_only_chmod "${test_dir}"
  assertEquals "should return 0 for 700 permissions" 0 $?
}

test_user_only_chmod_returns_false_for_755() {
  local test_dir="${TEST_OUTPUT_DIR}/test_dir"
  mkdir "${test_dir}"
  chmod 755 "${test_dir}"

  user_only_chmod "${test_dir}"
  assertNotEquals "should return non-zero for 755 permissions" 0 $?
}

test_user_only_chmod_returns_false_for_file() {
  local test_file="${TEST_OUTPUT_DIR}/test.txt"
  touch "${test_file}"
  chmod 700 "${test_file}"

  user_only_chmod "${test_file}"
  assertNotEquals "should return non-zero for file (not directory)" 0 $?
}

####################
# exists_but_not_writable
####################

test_exists_but_not_writable_returns_false_for_writable() {
  local test_file="${TEST_OUTPUT_DIR}/test.txt"
  touch "${test_file}"
  chmod 755 "${test_file}"

  exists_but_not_writable "${test_file}"
  assertNotEquals "should return non-zero for writable file" 0 $?
}

test_exists_but_not_writable_returns_true_for_readonly() {
  local test_file="${TEST_OUTPUT_DIR}/test.txt"
  touch "${test_file}"
  chmod 444 "${test_file}"

  exists_but_not_writable "${test_file}"
  assertEquals "should return 0 for read-only file" 0 $?
}

test_exists_but_not_writable_returns_false_for_nonexistent() {
  exists_but_not_writable "${TEST_OUTPUT_DIR}/nonexistent.txt"
  assertNotEquals "should return non-zero for nonexistent file" 0 $?
}

####################
# get_owner
####################

test_get_owner_returns_current_user() {
  local test_file="${TEST_OUTPUT_DIR}/test.txt"
  touch "${test_file}"
# shellcheck disable=SC2155
  local result=$(get_owner "${test_file}")

  assertEquals "should return current user id" "$(id -u)" "${result}"
}

####################
# file_not_owned
####################

test_file_not_owned_returns_false_for_owned_file() {
  local test_file="${TEST_OUTPUT_DIR}/test.txt"
  touch "${test_file}"

  file_not_owned "${test_file}"
  assertNotEquals "should return non-zero for owned file" 0 $?
}

####################
# get_group
####################

test_get_group_returns_group_id() {
  local test_file="${TEST_OUTPUT_DIR}/test.txt"
  touch "${test_file}"
# shellcheck disable=SC2155
  local result=$(get_group "${test_file}")

  # Result should be a numeric group id
  [[ "${result}" =~ ^[0-9]+$ ]]
  assertEquals "should return numeric group id" 0 $?
}

####################
# file_not_grpowned
####################

test_file_not_grpowned_returns_false_for_owned_file() {
  local test_file="${TEST_OUTPUT_DIR}/test.txt"
  touch "${test_file}"

  file_not_grpowned "${test_file}"
  assertNotEquals "should return non-zero for file in user's group" 0 $?
}

# Load and run shunit2
# shellcheck disable=SC1090
. "${SHUNIT2}"
