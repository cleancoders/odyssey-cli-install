#!/bin/bash

# Run all test files in the test directory
# This script discovers and executes all test_*.sh files

set -e

# Get the test directory
TEST_DIR=$(dirname "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
total_test_files=0
total_test_cases=0
passed_test_files=0
failed_test_files=0
failed_files=()

echo -e "${BLUE}==================================================${NC}"
echo -e "${BLUE}Running all tests in ${TEST_DIR}${NC}"
echo -e "${BLUE}==================================================${NC}"
echo ""

# Find all test files (test_*.sh) and run them
for test_file in "${TEST_DIR}"/test_*.sh; do
  # Skip if no test files found
  if [[ ! -f "${test_file}" ]]; then
    echo -e "${YELLOW}No test files found matching pattern: test_*.sh${NC}"
    exit 0
  fi

  test_name="$(basename "${test_file}")"
  echo -e "${BLUE}Running: ${test_name}${NC}"
  echo "---"

  # Create a temporary file to capture output for parsing
  temp_output=$(mktemp)

  # Run the test with live output, while also capturing to temp file
  set +e
  "${test_file}" 2>&1 | tee "${temp_output}"
  exit_code=$?
  set -e

  # Parse the captured output to count test cases (shunit2 uses ANSI codes)
  # Strip ANSI codes first, then match
  output_clean=$(cat "${temp_output}" | sed 's/\x1b\[[0-9;]*m//g')
  if [[ "${output_clean}" =~ Ran\ ([0-9]+)\ test ]]; then
    test_count="${BASH_REMATCH[1]}"
    ((total_test_cases += test_count))
  fi

  # Clean up temp file
  rm -f "${temp_output}"

  if [[ ${exit_code} -eq 0 ]]; then
    echo -e "${GREEN}✓ ${test_name} PASSED${NC}"
    ((passed_test_files++))
  else
    echo -e "${RED}✗ ${test_name} FAILED${NC}"
    ((failed_test_files++))
    failed_files+=("${test_name}")
  fi

  ((total_test_files++))
  echo ""
done

# Print summary
echo -e "${BLUE}==================================================${NC}"
echo -e "${BLUE}Test Summary${NC}"
echo -e "${BLUE}==================================================${NC}"
echo "Total test files: ${total_test_files}"
echo "Total test cases: ${total_test_cases}"
echo -e "${GREEN}Passed test files: ${passed_test_files}${NC}"

if [[ ${failed_test_files} -gt 0 ]]; then
  echo -e "${RED}Failed test files: ${failed_test_files}${NC}"
  echo ""
  echo -e "${RED}Failed test files:${NC}"
  for failed_file in "${failed_files[@]}"; do
    echo -e "  ${RED}- ${failed_file}${NC}"
  done
  exit 1
else
  echo -e "${GREEN}All tests passed!${NC}"
  exit 0
fi
