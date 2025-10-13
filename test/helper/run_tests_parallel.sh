#!/bin/bash

# Parallel test runner for Odyssey CLI installer tests
# Runs test files concurrently to speed up the test suite

# Get the project root directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_DIR="$(dirname "${SCRIPT_DIR}")"
PROJECT_DIR="$(dirname "${TEST_DIR}")"

# Change to project directory
cd "${PROJECT_DIR}" || exit 1

# Configuration
MAX_PARALLEL_JOBS=${MAX_PARALLEL_JOBS:-3}  # Run up to 3 tests in parallel
# TEST_DIR already set above

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Spinner frames
SPINNER_FRAMES=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
spinner_index=0

# Track results
declare -a TEST_FILES
declare -a TEST_RESULTS  # Will store "PASS:name:count" or "FAIL:name:failure_details"
declare -a ACTIVE_PIDS
declare -a ACTIVE_NAMES
declare -a ACTIVE_OUTPUT_FILES

total_tests=0
failed_tests=0
completed_tests=0


# Find all test files
while IFS= read -r test_file; do
  TEST_FILES+=("${test_file}")
done < <(find "${TEST_DIR}" -name "test_*.sh" -type f | sort)

total_test_files=${#TEST_FILES[@]}

# Function to update spinner
show_spinner() {
  local frame="${SPINNER_FRAMES[$spinner_index]}"
  printf "\r${CYAN}${BOLD}%s${NC} Running tests... (%d/%d completed)" "$frame" "$completed_tests" "$total_test_files"
  spinner_index=$(( (spinner_index + 1) % ${#SPINNER_FRAMES[@]} ))
}

# Function to run a single test file
run_test() {
  local test_file="$1"
  local output_file="$2"

  bash "${test_file}" > "${output_file}" 2>&1
  return $?
}

# Function to check and report completed tests
check_completed_tests() {
  local i=0

  while [[ $i -lt ${#ACTIVE_PIDS[@]} ]]; do
    local pid="${ACTIVE_PIDS[$i]}"
    local test_name="${ACTIVE_NAMES[$i]}"
    local output_file="${ACTIVE_OUTPUT_FILES[$i]}"

    # Check if this PID is still running
    if ! kill -0 "${pid}" 2>/dev/null; then
      # Test completed, process results
      wait "${pid}" 2>/dev/null

      ((completed_tests++))

      # Determine result and store it
      if grep -q "FAILED" "${output_file}"; then
        ((failed_tests++))

        # Extract failure details (function name and assertion message)
        local failure_details=""
        local func_name=""
        while IFS= read -r line; do
          # Extract test function name from lines like "test_something"
          if [[ "$line" =~ ^(test_[a-zA-Z_0-9]+) ]]; then
            func_name="${BASH_REMATCH[1]}"
          fi
          # Extract ASSERT lines
          if [[ "$line" =~ ASSERT: ]]; then
            # Remove ANSI codes and extract the assertion message
            local assert_msg=$(echo "$line" | sed 's/\x1b\[[0-9;]*m//g' | sed 's/^.*ASSERT://')
            if [[ -n "${func_name}" ]]; then
              failure_details+="||${func_name}:${assert_msg}"
            fi
          fi
        done < "${output_file}"

        # Store result with failure details
        TEST_RESULTS+=("FAIL:${test_name}${failure_details}")
      elif grep -q "OK" "${output_file}"; then
        # Strip ANSI color codes before extracting number
        test_count=$(grep "^Ran" "${output_file}" | sed 's/\x1b\[[0-9;]*m//g' | awk '{print $2}')
        TEST_RESULTS+=("PASS:${test_name}:${test_count}")
        if [[ -n "${test_count}" ]]; then
          total_tests=$((total_tests + test_count))
        fi
      else
        TEST_RESULTS+=("UNKNOWN:${test_name}")
        ((failed_tests++))
      fi

      # Clean up output file
      rm -f "${output_file}"

      # Remove from active arrays
      unset 'ACTIVE_PIDS[$i]'
      unset 'ACTIVE_NAMES[$i]'
      unset 'ACTIVE_OUTPUT_FILES[$i]'

      # Reindex arrays
      ACTIVE_PIDS=("${ACTIVE_PIDS[@]}")
      ACTIVE_NAMES=("${ACTIVE_NAMES[@]}")
      ACTIVE_OUTPUT_FILES=("${ACTIVE_OUTPUT_FILES[@]}")

      # Don't increment i since we removed an element
    else
      ((i++))
    fi
  done

  return 0
}

# Show initial message
echo -e "${CYAN}==>${NC} Running ${total_test_files} test files (up to ${MAX_PARALLEL_JOBS} in parallel)..."
echo ""

# Run all tests with spinner
for test_file in "${TEST_FILES[@]}"; do
  test_name=$(basename "${test_file}")
  output_file="${PROJECT_DIR}/.test_output_${test_name}.tmp"

  # Wait if we've reached max parallel jobs
  while [[ ${#ACTIVE_PIDS[@]} -ge ${MAX_PARALLEL_JOBS} ]]; do
    check_completed_tests
    show_spinner
    sleep 0.1
  done

  # Start the test in background
  run_test "${test_file}" "${output_file}" &
  pid=$!

  ACTIVE_PIDS+=("${pid}")
  ACTIVE_NAMES+=("${test_name}")
  ACTIVE_OUTPUT_FILES+=("${output_file}")
done

# Wait for remaining tests to complete
while [[ ${#ACTIVE_PIDS[@]} -gt 0 ]]; do
  check_completed_tests
  show_spinner
  sleep 0.1
done

# Clear spinner line
printf "\r\033[K"

# Print results summary
echo ""
echo "========================================"
echo "Results:"
echo "========================================"
for result in "${TEST_RESULTS[@]}"; do
  # Split on first colon to get status
  status="${result%%:*}"
  rest="${result#*:}"

  if [[ "$status" == "PASS" ]]; then
    # PASS:name:count
    name="${rest%%:*}"
    count="${rest#*:}"
    echo -e "${GREEN}✓ PASS${NC} ${name} ${CYAN}(${count} tests)${NC}"
  elif [[ "$status" == "FAIL" ]]; then
    # FAIL:name||func:msg||func:msg...
    name="${rest%%||*}"
    failures="${rest#*||}"

    echo -e "${RED}✗ FAIL${NC} ${name}"

    # Show failure details if available
    if [[ "$failures" != "$rest" ]]; then
      # Split on || and print each failure
      IFS='||' read -ra FAILURE_ARRAY <<< "$failures"
      for failure in "${FAILURE_ARRAY[@]}"; do
        if [[ -n "$failure" ]]; then
          echo -e "${RED}  ${failure}${NC}"
        fi
      done
    fi
  else
    echo -e "${YELLOW}? UNKNOWN${NC} ${rest}"
  fi
done

echo ""
echo "========================================"
echo "Summary:"
echo "========================================"
echo "Test files: ${completed_tests}/${total_test_files}"
echo "Total tests: ${total_tests}"

if [[ ${failed_tests} -eq 0 ]]; then
  echo -e "${GREEN}✓ All tests passed!${NC}"
  exit 0
else
  echo -e "${RED}✗ ${failed_tests} test file(s) failed${NC}"
  exit 1
fi
