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
  cd "${PROJECT_DIR}" || fail "Could not cd to project directory"
  ./bin/build_installer.sh "${TEST_OUTPUT_DIR}"> /dev/null 2>&1
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
  assertTrue "install.sh should be created" "[ -f '${TEST_OUTPUT_DIR}/install.sh' ]"
  assertTrue "install.sh should be executable" "[ -x '${TEST_OUTPUT_DIR}/install.sh' ]"
}

# Test that output file has correct shebang
test_output_has_shebang() {
  local first_line
  first_line="$(head -n 1 "${TEST_OUTPUT_DIR}/install.sh")"

  assertEquals "First line should be shebang" "#!/bin/bash" "${first_line}"
}

# Test that output file contains library functions
test_output_contains_library_functions() {
  # Check for functions from each library
  assertContains "Should contain abort function" "$(cat "${TEST_OUTPUT_DIR}/install.sh")" "abort()"
  assertContains "Should contain ohai function" "$(cat "${TEST_OUTPUT_DIR}/install.sh")" "ohai()"
  assertContains "Should contain version_gt function" "$(cat "${TEST_OUTPUT_DIR}/install.sh")" "version_gt()"
  assertContains "Should contain execute function" "$(cat "${TEST_OUTPUT_DIR}/install.sh")" "execute()"
  assertContains "Should contain find_tool function" "$(cat "${TEST_OUTPUT_DIR}/install.sh")" "find_tool()"
}

# Test that output file does not contain duplicate shebangs
test_output_no_duplicate_shebangs() {
  local shebang_count
  shebang_count="$(grep -c '^#!/bin/bash' "${TEST_OUTPUT_DIR}/install.sh")"
  assertEquals "Should have exactly one shebang" "1" "${shebang_count}"
}

# Test that output file does not contain source statements
test_output_no_source_statements() {
  if grep -q '^source.*lib/' "${TEST_OUTPUT_DIR}/install.sh" 2>/dev/null; then
    fail "Should have no source statements for lib files"
  fi
}

# Test that output file has valid bash syntax
test_output_valid_syntax() {
  bash -n "${TEST_OUTPUT_DIR}/install.sh"
  local syntax_check=$?

  assertEquals "Output file should have valid bash syntax" "0" "${syntax_check}"
}

# Test that output file is not empty
test_output_not_empty() {
  assertTrue "Output file should not be empty" "[ -s '${TEST_OUTPUT_DIR}/install.sh' ]"

  local file_size
  file_size="$(wc -c < "${TEST_OUTPUT_DIR}/install.sh")"

  assertTrue "Output file should be larger than 10KB" "[ ${file_size} -gt 10000 ]"
}

# Test that output file contains library section markers
test_output_has_section_markers() {
  assertContains "Should contain utils.sh marker" "$(cat "${TEST_OUTPUT_DIR}/install.sh")" "# --- lib/utils.sh ---"
  assertContains "Should contain version.sh marker" "$(cat "${TEST_OUTPUT_DIR}/install.sh")" "# --- lib/version.sh ---"
  assertContains "Should contain file_permissions.sh marker" "$(cat "${TEST_OUTPUT_DIR}/install.sh")" "# --- lib/file_permissions.sh ---"
  assertContains "Should contain execution.sh marker" "$(cat "${TEST_OUTPUT_DIR}/install.sh")" "# --- lib/execution.sh ---"
  assertContains "Should contain tool_validation.sh marker" "$(cat "${TEST_OUTPUT_DIR}/install.sh")" "# --- lib/tool_validation.sh ---"
}

# Test that build script exits with 0 on success
test_build_exits_successfully() {
  local exit_code=$?
  assertEquals "Build script should exit with 0" "0" "${exit_code}"
}

# Test that output contains header comment
test_output_has_header_comment() {
  assertContains "Should contain generated file warning" "$(head -n 10 "${TEST_OUTPUT_DIR}/install.sh")" "This is a generated file"
}

# Test that build script accepts custom output directory
test_build_accepts_custom_output_directory() {
  local custom_dir="${TEST_OUTPUT_DIR}/custom"
  mkdir -p "${custom_dir}"
  ./bin/build_installer.sh "${custom_dir}" > /dev/null 2>&1

  assertTrue "install.sh should be created in custom directory" "[ -f '${custom_dir}/install.sh' ]"
  assertTrue "install.sh should be executable" "[ -x '${custom_dir}/install.sh' ]"
}

# Test that build script errors on nonexistent directory
test_build_errors_on_nonexistent_directory() {
  ./bin/build_installer.sh /nonexistent/path/xyz > /dev/null 2>&1
  local exit_code=$?
  assertNotEquals "Should exit with non-zero code for invalid directory" 0 "${exit_code}"
}

# Test that output file contains main function invocation
test_output_contains_main_invocation() {
  assertContains "Should contain main function call" "$(cat "${TEST_OUTPUT_DIR}/install.sh")" 'main "$@"'
}

# Test that main invocation is at the end of the file
test_main_invocation_at_end() {
  local last_line
  last_line="$(tail -n 1 "${TEST_OUTPUT_DIR}/install.sh")"

  assertEquals "Last line should be main invocation" 'main "$@"' "${last_line}"
}

# Test that output file can parse --help argument
test_output_parses_help_argument() {
  output=$("${TEST_OUTPUT_DIR}/install.sh" --help 2>&1 || true)

  assertContains "Should display usage when called with --help" "${output}" "Usage:"
}

# Load and run shunit2
# shellcheck disable=SC1090
. "${SHUNIT2}"
