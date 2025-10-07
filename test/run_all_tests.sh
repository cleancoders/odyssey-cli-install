#!/bin/bash

# Run all test files in the test directory
# This script discovers and executes all test_*.sh files

set -e

# Get the test directory
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
total_tests=0
passed_tests=0
failed_tests=0
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

  # Run the test and capture output and exit code
  if output=$("${test_file}" 2>&1); then
    echo -e "${GREEN}✓ ${test_name} PASSED${NC}"
    ((passed_tests++))
  else
    echo -e "${RED}✗ ${test_name} FAILED${NC}"
    echo "${output}"
    ((failed_tests++))
    failed_files+=("${test_name}")
  fi

  ((total_tests++))
  echo ""
done

# Print summary
echo -e "${BLUE}==================================================${NC}"
echo -e "${BLUE}Test Summary${NC}"
echo -e "${BLUE}==================================================${NC}"
echo "Total test files: ${total_tests}"
echo -e "${GREEN}Passed: ${passed_tests}${NC}"

if [[ ${failed_tests} -gt 0 ]]; then
  echo -e "${RED}Failed: ${failed_tests}${NC}"
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
