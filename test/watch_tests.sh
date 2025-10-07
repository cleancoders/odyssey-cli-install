#!/bin/bash

# Watch for file changes and re-run tests automatically
# This script watches for changes in bin/, lib/, and test/ directories

# Get the project root directory
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "${TEST_DIR}")"

# Color codes
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if fswatch is installed (macOS)
if command -v fswatch >/dev/null 2>&1; then
  WATCHER="fswatch"
elif command -v inotifywait >/dev/null 2>&1; then
  WATCHER="inotifywait"
else
  echo "Error: Neither fswatch (macOS) nor inotifywait (Linux) is installed."
  echo ""
  echo "To install:"
  echo "  macOS: brew install fswatch"
  echo "  Linux: apt-get install inotify-tools (or yum install inotify-tools)"
  exit 1
fi

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Test Watcher Started${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "Watching: ${YELLOW}bin/, lib/, test/${NC}"
echo -e "Press ${YELLOW}Ctrl+C${NC} to stop"
echo ""

# Run tests once at startup
echo -e "${GREEN}Running initial tests...${NC}"
echo ""
"${TEST_DIR}/run_all_tests.sh"

# Function to find test files that reference a given source file
find_related_tests() {
  local source_file="$1"
  local source_basename=$(basename "${source_file}")
  local related_tests=()

  # Search for test files that reference this source file
  for test_file in "${TEST_DIR}"/test_*.sh; do
    if [[ -f "${test_file}" ]] && grep -q "${source_basename}" "${test_file}" 2>/dev/null; then
      related_tests+=("${test_file}")
    fi
  done

  # If no specific tests found, check for naming conventions
  if [[ ${#related_tests[@]} -eq 0 ]]; then
    # Check for test file matching the source file name
    # e.g., lib/utils.sh -> test/test_utils.sh
    local name_without_ext="${source_basename%.sh}"
    local potential_test="${TEST_DIR}/test_${name_without_ext}.sh"

    if [[ -f "${potential_test}" ]]; then
      related_tests+=("${potential_test}")
    fi
  fi

  echo "${related_tests[@]}"
}

# Function to run appropriate tests based on changed file
run_tests_for_file() {
  local changed_file="$1"
  local file_basename=$(basename "${changed_file}")

  # If it's a test file, run only that test
  if [[ "${changed_file}" == *"/test/test_"*.sh ]] && [[ -f "${changed_file}" ]]; then
    echo -e "${BLUE}Change detected in: ${YELLOW}${file_basename}${NC}"
    echo -e "${BLUE}Running: ${YELLOW}${file_basename}${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    "${changed_file}"
  # If it's a source file in bin/ or lib/
  elif [[ "${changed_file}" == *"/bin/"*.sh ]] || [[ "${changed_file}" == *"/lib/"*.sh ]]; then
    echo -e "${BLUE}Change detected in: ${YELLOW}${file_basename}${NC}"

    # Find related test files
    related_tests=($(find_related_tests "${changed_file}"))

    if [[ ${#related_tests[@]} -gt 0 ]]; then
      echo -e "${BLUE}Running ${#related_tests[@]} related test file(s)${NC}"
      echo -e "${BLUE}========================================${NC}"
      echo ""

      local all_passed=true
      for test_file in "${related_tests[@]}"; do
        local test_name=$(basename "${test_file}")
        echo -e "${YELLOW}→ Running: ${test_name}${NC}"
        echo "---"

        if ! "${test_file}"; then
          all_passed=false
        fi
        echo ""
      done

      if [[ "${all_passed}" == true ]]; then
        echo -e "${GREEN}✓ All related tests passed${NC}"
      else
        echo -e "${RED}✗ Some tests failed${NC}"
      fi
    else
      # No related tests found, run all tests
      echo -e "${YELLOW}No related tests found, running all tests${NC}"
      echo -e "${BLUE}========================================${NC}"
      echo ""
      "${TEST_DIR}/run_all_tests.sh"
    fi
  else
    # For other changes, run all tests
    echo -e "${BLUE}Change detected in: ${YELLOW}${file_basename}${NC}"
    echo -e "${BLUE}Running all tests${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    "${TEST_DIR}/run_all_tests.sh"
  fi
}

# Watch for changes and re-run tests
if [[ "${WATCHER}" == "fswatch" ]]; then
  # macOS using fswatch
  fswatch \
    "${PROJECT_DIR}/bin" \
    "${PROJECT_DIR}/lib" \
    "${PROJECT_DIR}/test" \
    --exclude '.*\.swp$' \
    --exclude '.*~$' \
    --exclude '.*\.tmp$' \
    --exclude '.*/\..*' | while read -r changed_file; do
    clear
    echo -e "${BLUE}========================================${NC}"
    run_tests_for_file "${changed_file}"
    echo ""
    echo -e "${YELLOW}Watching for changes...${NC}"
  done
else
  # Linux using inotifywait
  while true; do
    changed_file=$(inotifywait -r -e modify,create,delete \
      --format '%w%f' \
      "${PROJECT_DIR}/bin" \
      "${PROJECT_DIR}/lib" \
      "${PROJECT_DIR}/test" \
      --exclude '.*\.swp$' \
      --exclude '.*~$' \
      --exclude '.*\.tmp$' 2>/dev/null)

    clear
    echo -e "${BLUE}========================================${NC}"
    run_tests_for_file "${changed_file}"
    echo ""
    echo -e "${YELLOW}Watching for changes...${NC}"
  done
fi
