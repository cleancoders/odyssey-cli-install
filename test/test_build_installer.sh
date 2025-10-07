#!/bin/bash

# Unit tests for bin/build_installer.sh

# Get the project root directory
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "${TEST_DIR}")"

# Source shunit2
SHUNIT2="${PROJECT_DIR}/shunit2"

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

# Test that build script exists and is executable
test_build_script_exists() {
  assertTrue "build_installer.sh should exist" "[ -f '${PROJECT_DIR}/bin/build_installer.sh' ]"
  assertTrue "build_installer.sh should be executable" "[ -x '${PROJECT_DIR}/bin/build_installer.sh' ]"
}

# Test that build script creates output file
test_build_creates_output_file() {
  cd "${PROJECT_DIR}" || fail "Could not cd to project directory"

  ./bin/build_installer.sh > /dev/null 2>&1

  assertTrue "install.sh should be created" "[ -f '${PROJECT_DIR}/install.sh' ]"
  assertTrue "install.sh should be executable" "[ -x '${PROJECT_DIR}/install.sh' ]"

  # Clean up
  rm -f "${PROJECT_DIR}/install.sh"
}

# Test that output file has correct shebang
test_output_has_shebang() {
  cd "${PROJECT_DIR}" || fail "Could not cd to project directory"

  ./bin/build_installer.sh > /dev/null 2>&1

  local first_line
  first_line="$(head -n 1 "${PROJECT_DIR}/install.sh")"

  assertEquals "First line should be shebang" "#!/bin/bash" "${first_line}"

  # Clean up
  rm -f "${PROJECT_DIR}/install.sh"
}

# Test that output file contains library functions
test_output_contains_library_functions() {
  cd "${PROJECT_DIR}" || fail "Could not cd to project directory"

  ./bin/build_installer.sh > /dev/null 2>&1

  # Check for functions from each library
  assertContains "Should contain abort function" "$(cat "${PROJECT_DIR}/install.sh")" "abort()"
  assertContains "Should contain ohai function" "$(cat "${PROJECT_DIR}/install.sh")" "ohai()"
  assertContains "Should contain version_gt function" "$(cat "${PROJECT_DIR}/install.sh")" "version_gt()"
  assertContains "Should contain execute function" "$(cat "${PROJECT_DIR}/install.sh")" "execute()"
  assertContains "Should contain find_tool function" "$(cat "${PROJECT_DIR}/install.sh")" "find_tool()"

  # Clean up
  rm -f "${PROJECT_DIR}/install.sh"
}

# Test that output file does not contain duplicate shebangs
test_output_no_duplicate_shebangs() {
  cd "${PROJECT_DIR}" || fail "Could not cd to project directory"

  ./bin/build_installer.sh > /dev/null 2>&1

  local shebang_count
  shebang_count="$(grep -c '^#!/bin/bash' "${PROJECT_DIR}/install.sh")"

  assertEquals "Should have exactly one shebang" "1" "${shebang_count}"

  # Clean up
  rm -f "${PROJECT_DIR}/install.sh"
}

# Test that output file does not contain source statements
test_output_no_source_statements() {
  cd "${PROJECT_DIR}" || fail "Could not cd to project directory"

  ./bin/build_installer.sh > /dev/null 2>&1

  if grep -q '^source.*lib/' "${PROJECT_DIR}/install.sh" 2>/dev/null; then
    fail "Should have no source statements for lib files"
  fi

  # Clean up
  rm -f "${PROJECT_DIR}/install.sh"
}

# Test that output file has valid bash syntax
test_output_valid_syntax() {
  cd "${PROJECT_DIR}" || fail "Could not cd to project directory"

  ./bin/build_installer.sh > /dev/null 2>&1

  bash -n "${PROJECT_DIR}/install.sh"
  local syntax_check=$?

  assertEquals "Output file should have valid bash syntax" "0" "${syntax_check}"

  # Clean up
  rm -f "${PROJECT_DIR}/install.sh"
}

# Test that output file is not empty
test_output_not_empty() {
  cd "${PROJECT_DIR}" || fail "Could not cd to project directory"

  ./bin/build_installer.sh > /dev/null 2>&1

  assertTrue "Output file should not be empty" "[ -s '${PROJECT_DIR}/install.sh' ]"

  local file_size
  file_size="$(wc -c < "${PROJECT_DIR}/install.sh")"

  assertTrue "Output file should be larger than 10KB" "[ ${file_size} -gt 10000 ]"

  # Clean up
  rm -f "${PROJECT_DIR}/install.sh"
}

# Test that output file contains library section markers
test_output_has_section_markers() {
  cd "${PROJECT_DIR}" || fail "Could not cd to project directory"

  ./bin/build_installer.sh > /dev/null 2>&1

  assertContains "Should contain utils.sh marker" "$(cat "${PROJECT_DIR}/install.sh")" "# --- lib/utils.sh ---"
  assertContains "Should contain version.sh marker" "$(cat "${PROJECT_DIR}/install.sh")" "# --- lib/version.sh ---"
  assertContains "Should contain file_permissions.sh marker" "$(cat "${PROJECT_DIR}/install.sh")" "# --- lib/file_permissions.sh ---"
  assertContains "Should contain execution.sh marker" "$(cat "${PROJECT_DIR}/install.sh")" "# --- lib/execution.sh ---"
  assertContains "Should contain validation.sh marker" "$(cat "${PROJECT_DIR}/install.sh")" "# --- lib/validation.sh ---"

  # Clean up
  rm -f "${PROJECT_DIR}/install.sh"
}

# Test that build script exits with 0 on success
test_build_exits_successfully() {
  cd "${PROJECT_DIR}" || fail "Could not cd to project directory"

  ./bin/build_installer.sh > /dev/null 2>&1
  local exit_code=$?

  assertEquals "Build script should exit with 0" "0" "${exit_code}"

  # Clean up
  rm -f "${PROJECT_DIR}/install.sh"
}

# Test that output contains header comment
test_output_has_header_comment() {
  cd "${PROJECT_DIR}" || fail "Could not cd to project directory"

  ./bin/build_installer.sh > /dev/null 2>&1

  assertContains "Should contain generated file warning" "$(head -n 10 "${PROJECT_DIR}/install.sh")" "This is a generated file"

  # Clean up
  rm -f "${PROJECT_DIR}/install.sh"
}

# Load and run shunit2
# shellcheck disable=SC1090
. "${SHUNIT2}"
