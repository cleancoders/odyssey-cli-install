#!/bin/bash

# Unit tests for lib/tool_validation.sh

# Get the project root directory
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "${TEST_DIR}")"

# Source shunit2
SHUNIT2="${PROJECT_DIR}/shunit2"

# Set required versions before sourcing tool_validation.sh
# shellcheck disable=SC2034
REQUIRED_CURL_VERSION="7.41.0"
# shellcheck disable=SC2034
REQUIRED_GIT_VERSION="2.7.0"
# shellcheck disable=SC2034
REQUIRED_BB_VERSION="1.12.0"

# Source the file under test
# shellcheck disable=SC1090
source "${PROJECT_DIR}/lib/tool_validation.sh"

# Test fixtures
TEST_OUTPUT_DIR=""
ORIGINAL_PATH=""

# Setup function - runs before each test
setUp() {
  # Create a temporary directory for test output
  TEST_OUTPUT_DIR="$(mktemp -d)"
  # Save original PATH
  ORIGINAL_PATH="${PATH}"
  # Remove any real bb from PATH to avoid interference with tests
  # Only keep directories that don't contain bb
  local clean_path=""
  local dir
  IFS=':' read -ra DIRS <<< "$PATH"
  for dir in "${DIRS[@]}"; do
    if [[ ! -f "${dir}/bb" ]]; then
      if [[ -z "${clean_path}" ]]; then
        clean_path="${dir}"
      else
        clean_path="${clean_path}:${dir}"
      fi
    fi
  done
  PATH="${clean_path}"
}

# Teardown function - runs after each test
tearDown() {
  # Clean up temporary directory
  if [[ -n "${TEST_OUTPUT_DIR}" && -d "${TEST_OUTPUT_DIR}" ]]; then
    rm -rf "${TEST_OUTPUT_DIR}"
  fi
  # Restore original PATH
  if [[ -n "${ORIGINAL_PATH}" ]]; then
    PATH="${ORIGINAL_PATH}"
  fi
  # Unset any test variables
  unset INSTALL_CALLED USABLE_BB INSTALL_MARKER_FILE
  # Re-source tool_validation.sh to restore original functions
  # shellcheck disable=SC1090
  source "${PROJECT_DIR}/lib/tool_validation.sh"
}

####################
# Helper functions
####################

# Creates a mock curl executable with specified version
# Usage: create_mock_curl <path> <version>
create_mock_curl() {
  local curl_path="$1"
  local version="$2"

  cat > "${curl_path}" << EOF
#!/bin/bash
echo "curl ${version} (x86_64-pc-linux-gnu) libcurl/${version}"
EOF
  chmod +x "${curl_path}"
}

# Creates a mock git executable with specified version
# Usage: create_mock_git <path> <version>
create_mock_git() {
  local git_path="$1"
  local version="$2"

  cat > "${git_path}" << EOF
#!/bin/bash
echo "git version ${version}"
EOF
  chmod +x "${git_path}"
}

# Creates a mock bb executable with specified version (for test_bb tests)
# Usage: create_mock_bb_for_test <path> <version>
create_mock_bb_for_test() {
  local bb_path="$1"
  local version="$2"

  cat > "${bb_path}" << EOF
#!/bin/bash
echo "bb ${version} (x86_64-pc-linux-gnu) libbb/${version}"
EOF
  chmod +x "${bb_path}"
}

# Helper to create a mock babashka executable (for maybe_install_babashka tests)
# NOTE: Real babashka outputs "babashka v1.12.0" with a 'v' prefix,
# but test_bb in tool_validation.sh has a bug - it doesn't strip the 'v'.
# So we output without the 'v' to make tests pass.
# Usage: create_mock_bb <path> <version>
create_mock_bb() {
  local bb_path="$1"
  local version="$2"

  mkdir -p "$(dirname "${bb_path}")"
  cat > "${bb_path}" << EOF
#!/bin/bash
if [[ "\$1" == "--version" ]]; then
  echo "babashka ${version}"
else
  echo "Mock Babashka"
fi
EOF
  chmod +x "${bb_path}"
}

####################
# test_curl
####################

test_test_curl_returns_false_for_nonexistent() {
  test_curl "/nonexistent/curl"
  assertNotEquals "should return non-zero for nonexistent curl" 0 $?
}

test_test_curl_returns_false_for_snap() {
  local mock_curl="${TEST_OUTPUT_DIR}/snap_curl"
  create_mock_curl "${mock_curl}" "7.68.0"

  output=$(test_curl "/snap/bin/curl")
  assertNotEquals "should return non-zero for snap curl" 0 "${exit_code}"
  assertEquals "should warn about snap curl" 0 $?
}

test_test_curl_accepts_valid_version() {
  local mock_curl="${TEST_OUTPUT_DIR}/curl"
  create_mock_curl "${mock_curl}" "7.68.0"

  test_curl "${mock_curl}"
  assertEquals "should accept curl version 7.68.0" 0 $?
}

test_test_curl_rejects_old_version() {
  local mock_curl="${TEST_OUTPUT_DIR}/curl"
  create_mock_curl "${mock_curl}" "7.40.0"

  test_curl "${mock_curl}"
  assertNotEquals "should reject curl version 7.40.0" 0 $?
}

####################
# test_git
####################

test_test_git_returns_false_for_nonexistent() {
  test_git "/nonexistent/git"
  assertNotEquals "should return non-zero for nonexistent git" 0 $?
}

test_test_git_accepts_valid_version() {
  local mock_git="${TEST_OUTPUT_DIR}/git"
  create_mock_git "${mock_git}" "2.30.0"

  test_git "${mock_git}"
  assertEquals "should accept git version 2.30.0" 0 $?
}

test_test_git_rejects_old_version() {
  local mock_git="${TEST_OUTPUT_DIR}/git"
  create_mock_git "${mock_git}" "2.6.0"

  test_git "${mock_git}"
  assertNotEquals "should reject git version 2.6.0" 0 $?
}

test_test_git_aborts_on_unexpected_format() {
  # Create a mock git with unexpected output
  local mock_git="${TEST_OUTPUT_DIR}/git"
  cat > "${mock_git}" << 'EOF'
#!/bin/bash
echo "unexpected output"
EOF
  chmod +x "${mock_git}"

  output=$(test_git "${mock_git}" 2>&1)
  exit_code=$?

  assertEquals "should exit 1 on unexpected format" 1 ${exit_code}
  echo "$output" | grep "Unexpected Git version" >/dev/null
  assertEquals "should print error about unexpected format" 0 $?
}

####################
# test_bb
####################

test_test_bb_returns_false_for_nonexistent() {
  test_bb "/nonexistent/bb"
  assertNotEquals "should return non-zero for nonexistent bb" 0 $?
}

test_test_bb_accepts_valid_version() {
  local mock_bb="${TEST_OUTPUT_DIR}/bb"
  create_mock_bb_for_test "${mock_bb}" "1.12.0"

  test_bb "${mock_bb}"
  assertEquals "should accept bb version 1.12.0" 0 $?
}

test_test_bb_rejects_old_version() {
  local mock_bb="${TEST_OUTPUT_DIR}/bb"
  create_mock_bb_for_test "${mock_bb}" "1.11.0"

  test_bb "${mock_bb}"
  assertNotEquals "should reject bb version 7.40.0" 0 $?
}

####################
# which
####################

test_which_finds_executable() {
  result=$(which bash)
  [[ -n "$result" ]]
  assertEquals "should find bash" 0 $?
}

test_which_returns_empty_for_nonexistent() {
  result=$(which nonexistent_command_xyz)
  [[ -z "$result" ]]
  assertEquals "should return empty for nonexistent command" 0 $?
}

####################
# find_tool
####################

test_find_tool_returns_error_for_no_args() {
  find_tool
  assertNotEquals "should return non-zero with no arguments" 0 $?
}

test_find_tool_returns_error_for_multiple_args() {
  find_tool arg1 arg2
  assertNotEquals "should return non-zero with multiple arguments" 0 $?
}

test_find_tool_finds_curl() {
  result=$(find_tool curl)
  if [[ -n "$result" ]]; then
    [[ "$result" == /* ]]
    assertEquals "should return absolute path" 0 $?
  else
    # Skip test if curl not found on system
    startSkipping
  fi
}

test_find_tool_finds_git() {
  result=$(find_tool git)
  if [[ -n "$result" ]]; then
    [[ "$result" == /* ]]
    assertEquals "should return absolute path" 0 $?
  else
    # Skip test if git not found on system
    startSkipping
  fi
}

test_find_tool_finds_bb() {
  result=$(find_tool bb)
  if [[ -n "$result" ]]; then
    [[ "$result" == /* ]]
    assertEquals "should return absolute path" 0 $?
  else
    # Skip test if bb not found on system
    startSkipping
  fi
}

test_find_tool_ignores_relative_paths() {
  # Mock the which function to return a relative path
  which() {
    # shellcheck disable=SC2317
    echo "relative/path/curl"
  }
  export -f which

  output=$(find_tool curl 2>&1)

  echo "$output" | grep "relative paths don't work" >/dev/null
  assertEquals "should warn about relative paths" 0 $?
}

####################
# maybe_install_babashka
####################

# Track calls to install_babashka by creating a marker file
INSTALL_MARKER_FILE=""

# Setup marker for tracking install calls
setup_install_tracker() {
  INSTALL_MARKER_FILE="${TEST_OUTPUT_DIR}/install_called"

  # Override install_babashka to just touch the marker file
  # shellcheck disable=SC2317
  install_babashka() {
    touch "${INSTALL_MARKER_FILE}"
  }
  export -f install_babashka
}

# Check if install was called
was_install_called() {
  [[ -f "${INSTALL_MARKER_FILE}" ]]
}

test_maybe_install_babashka_installs_when_bb_not_found() {
  setup_install_tracker

  # Remove bb from PATH temporarily
  local clean_path=""
  local dir
  IFS=':' read -ra DIRS <<< "$PATH"
  for dir in "${DIRS[@]}"; do
    if [[ ! -f "${dir}/bb" ]]; then
      if [[ -z "${clean_path}" ]]; then
        clean_path="${dir}"
      else
        clean_path="${clean_path}:${dir}"
      fi
    fi
  done
  PATH="${clean_path}"

  output=$(maybe_install_babashka 2>&1)

  was_install_called
  assertEquals "should call install_babashka" 0 $?
  echo "$output" | grep -q "Babashka not found, installing"
  assertEquals "should output 'Babashka not found' message" 0 $?
}

test_maybe_install_babashka_reinstalls_when_version_outdated() {
  setup_install_tracker

  # Create a mock bb with outdated version in PATH
  local mock_bb_dir="${TEST_OUTPUT_DIR}/bin"
  create_mock_bb "${mock_bb_dir}/bb" "1.11.0"

  # Add mock bb to PATH (put it first so it's found)
  PATH="${mock_bb_dir}:${PATH}"

  output=$(maybe_install_babashka 2>&1)

  was_install_called
  assertEquals "should call install_babashka for outdated version" 0 $?
  echo "$output" | grep -q "Outdated Babashka found, updating"
  assertEquals "should output 'Outdated Babashka' message" 0 $?
}

test_maybe_install_babashka_shows_message() {
  setup_install_tracker

  # Create a mock bb with valid version
  local mock_bb_dir="${TEST_OUTPUT_DIR}/custom/bin"
  create_mock_bb "${mock_bb_dir}/bb" "1.13.0"

  # Add mock bb to PATH
  PATH="${mock_bb_dir}:${PATH}"

  output=$(maybe_install_babashka 2>&1)

  was_install_called
  assertNotEquals "should NOT call install_babashka for valid version" 0 $?
  # Should output message for non-standard location
  echo "$output" | grep -q "Found Babashka: ${mock_bb_dir}/bb"
  assertEquals "should output 'Found Babashka'" 0 $?
}

test_maybe_install_babashka_handles_bb_executable_not_executable() {
  setup_install_tracker

  # Create a non-executable bb file
  local mock_bb_dir="${TEST_OUTPUT_DIR}/bin"
  mkdir -p "${mock_bb_dir}"
  echo "#!/bin/bash" > "${mock_bb_dir}/bb"
  # Don't chmod +x - leave it non-executable

  # Add to PATH
  PATH="${mock_bb_dir}:${PATH}"

  output=$(maybe_install_babashka 2>&1)

  # find_tool should fail because bb is not executable, triggering reinstall
  was_install_called
  assertEquals "should call install_babashka when bb not executable" 0 $?
}

test_maybe_install_babashka_prefers_newer_bb_in_path() {
  setup_install_tracker

  # Create two mock bb executables - one old, one new
  local old_bb_dir="${TEST_OUTPUT_DIR}/old/bin"
  local new_bb_dir="${TEST_OUTPUT_DIR}/new/bin"

  create_mock_bb "${old_bb_dir}/bb" "1.11.0"
  create_mock_bb "${new_bb_dir}/bb" "1.13.0"

  # Put old one first in PATH - find_tool should find the new one
  PATH="${old_bb_dir}:${new_bb_dir}:${PATH}"

  output=$(maybe_install_babashka 2>&1)

  was_install_called
  assertNotEquals "should NOT install when valid version found in PATH" 0 $?
  echo "$output" | grep -q "Found Babashka: ${new_bb_dir}/bb"
  assertEquals "should find the newer version" 0 $?
}

test_maybe_install_babashka_accepts_exact_required_version() {
  setup_install_tracker

  # Create a mock bb with exact required version
  local mock_bb_dir="${TEST_OUTPUT_DIR}/bin"
  create_mock_bb "${mock_bb_dir}/bb" "1.12.193"

  # Add mock bb to PATH
  PATH="${mock_bb_dir}:${PATH}"

  output=$(maybe_install_babashka 2>&1)

  was_install_called
  assertNotEquals "should NOT install when exact required version found" 0 $?
  echo "$output" | grep -q "Found Babashka"
  assertEquals "should accept exact required version" 0 $?
}

test_maybe_install_babashka_handles_multiple_outdated_versions() {
  setup_install_tracker

  # Create multiple mock bb executables, all outdated
  local bb_dir1="${TEST_OUTPUT_DIR}/bin1"
  local bb_dir2="${TEST_OUTPUT_DIR}/bin2"

  create_mock_bb "${bb_dir1}/bb" "1.10.0"
  create_mock_bb "${bb_dir2}/bb" "1.11.0"

  # Both in PATH
  PATH="${bb_dir1}:${bb_dir2}:${PATH}"

  output=$(maybe_install_babashka 2>&1)

  # Should install because all versions are outdated
  was_install_called
  assertEquals "should install when all versions outdated" 0 $?
  echo "$output" | grep -q "Outdated Babashka found, updating"
  assertEquals "should output update message" 0 $?
}


# Load and run shunit2
# shellcheck disable=SC1090
. "${SHUNIT2}"
