#!/bin/bash

# Unit tests for lib/version.sh

# Get the project root directory
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "${TEST_DIR}")"

# Source shunit2
SHUNIT2="${PROJECT_DIR}/shunit2"

# Source the file under test
# shellcheck disable=SC1090
source "${PROJECT_DIR}/lib/version.sh"

####################
# major_minor
####################

test_major_minor_extracts_two_components() {
  result=$(major_minor "2.7.4")
  assertEquals "should extract major.minor" "2.7" "${result}"
}

test_major_minor_handles_two_component_version() {
  result=$(major_minor "3.5")
  assertEquals "should handle two component version" "3.5" "${result}"
}

test_major_minor_handles_single_component() {
  result=$(major_minor "4")
  assertEquals "should handle single component version" "4.0" "${result}"
}

test_major_minor_handles_duplicate_number() {
  result=$(major_minor "4.4")
  assertEquals "should handle single component version" "4.4" "${result}"
}

test_major_minor_handles_triplicate_number() {
  result=$(major_minor "4.4.4")
  assertEquals "should handle single component version" "4.4" "${result}"
}

test_major_minor_handles_many_components() {
  result=$(major_minor "1.2.3.4.5")
  assertEquals "should extract first two components" "1.2" "${result}"
}

####################
# version_gt
####################

test_version_gt_returns_true_for_greater_major() {
  version_gt "3.0" "2.9"
  assertEquals "3.0 should be greater than 2.9" 0 $?
}

test_version_gt_returns_true_for_greater_minor() {
  version_gt "2.8" "2.7"
  assertEquals "2.8 should be greater than 2.7" 0 $?
}

test_version_gt_returns_false_for_equal() {
  version_gt "2.7" "2.7"
  assertNotEquals "2.7 should not be greater than 2.7" 0 $?
}

test_version_gt_returns_false_for_less_major() {
  version_gt "1.9" "2.0"
  assertNotEquals "1.9 should not be greater than 2.0" 0 $?
}

test_version_gt_returns_false_for_less_minor() {
  version_gt "2.6" "2.7"
  assertNotEquals "2.6 should not be greater than 2.7" 0 $?
}

test_version_gt_with_zero_minor() {
  version_gt "2.1" "2.0"
  assertEquals "2.1 should be > 2.0" 0 $?
}

####################
# version_ge
####################

test_version_ge_returns_true_for_greater_major() {
  version_ge "3.0" "2.9"
  assertEquals "3.0 should be >= 2.9" 0 $?
}

test_version_ge_returns_true_for_greater_minor() {
  version_ge "2.8" "2.7"
  assertEquals "2.8 should be >= 2.7" 0 $?
}

test_version_ge_returns_true_for_equal() {
  version_ge "2.7" "2.7"
  assertEquals "2.7 should be >= 2.7" 0 $?
}

test_version_ge_returns_false_for_less_major() {
  version_ge "1.9" "2.0"
  assertNotEquals "1.9 should not be >= 2.0" 0 $?
}

test_version_ge_returns_false_for_less_minor() {
  version_ge "2.6" "2.7"
  assertNotEquals "2.6 should not be >= 2.7" 0 $?
}

test_version_ge_with_zero_minor() {
  version_ge "2.0" "2.0"
  assertEquals "2.0 should be >= 2.0" 0 $?
}

test_version_ge_with_large_numbers() {
  version_ge "10.20" "10.5"
  assertEquals "10.20 should be >= 10.5" 0 $?
}

####################
# version_lt
####################

test_version_lt_returns_true_for_less_major() {
  version_lt "1.9" "2.0"
  assertEquals "1.9 should be < 2.0" 0 $?
}

test_version_lt_returns_true_for_less_minor() {
  version_lt "2.6" "2.7"
  assertEquals "2.6 should be < 2.7" 0 $?
}

test_version_lt_returns_false_for_equal() {
  version_lt "2.7" "2.7"
  assertNotEquals "2.7 should not be < 2.7" 0 $?
}

test_version_lt_returns_false_for_greater_major() {
  version_lt "3.0" "2.9"
  assertNotEquals "3.0 should not be < 2.9" 0 $?
}

test_version_lt_returns_false_for_greater_minor() {
  version_lt "2.8" "2.7"
  assertNotEquals "2.8 should not be < 2.7" 0 $?
}

test_version_lt_with_large_numbers() {
  version_lt "10.5" "10.20"
  assertEquals "10.5 should be < 10.20" 0 $?
}

# Load and run shunit2
# shellcheck disable=SC1090
. "${SHUNIT2}"
