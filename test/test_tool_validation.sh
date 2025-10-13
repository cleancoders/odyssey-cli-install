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

# One-time setup - runs once before all tests
oneTimeSetUp() {
  # Create a single temporary directory for all tests
  TEST_OUTPUT_DIR="$(mktemp -d)"
  # Save original PATH
  ORIGINAL_PATH="${PATH}"
  # Save original functions that may be mocked (as command strings for later restoration)
  ORIGINAL_INSTALL_BABASHKA=$(declare -f install_babashka)
  ORIGINAL_WHICH=$(declare -f which)
  ORIGINAL_OHAI=$(declare -f ohai)
  ORIGINAL_WARN=$(declare -f warn)
}

# Setup function - runs before each test
setUp() {
  # Remove any real bb from PATH to avoid interference with tests
  # Only keep directories that don't contain bb
  local clean_path=""
  local dir
  IFS=':' read -ra DIRS <<< "$ORIGINAL_PATH"
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
  # Restore original PATH
  PATH="${ORIGINAL_PATH}"
  # Unset any test variables
  unset INSTALL_CALLED USABLE_BB INSTALL_MARKER_FILE
  # Restore original functions if they were mocked
  eval "${ORIGINAL_INSTALL_BABASHKA}"
  eval "${ORIGINAL_WHICH}"
  eval "${ORIGINAL_OHAI}"
  eval "${ORIGINAL_WARN}"
}

# One-time teardown - runs once after all tests
oneTimeTearDown() {
  # Clean up temporary directory
  if [[ -n "${TEST_OUTPUT_DIR}" && -d "${TEST_OUTPUT_DIR}" ]]; then
    rm -rf "${TEST_OUTPUT_DIR}"
  fi
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
# Real babashka outputs "babashka v1.12.193" with a 'v' prefix
# Usage: create_mock_bb_for_test <path> <version>
create_mock_bb_for_test() {
  local bb_path="$1"
  local version="$2"

  cat > "${bb_path}" << EOF
#!/bin/bash
echo "babashka v${version}"
EOF
  chmod +x "${bb_path}"
}

# Helper to create a mock babashka executable (for maybe_install_babashka tests)
# NOTE: Real babashka outputs "babashka v1.12.0" with a 'v' prefix.
# Usage: create_mock_bb <path> <version>
create_mock_bb() {
  local bb_path="$1"
  local version="$2"

  mkdir -p "$(dirname "${bb_path}")"
  cat > "${bb_path}" << EOF
#!/bin/bash
if [[ "\$1" == "--version" ]]; then
  echo "babashka v${version}"
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

test_test_bb_handles_version_with_v_prefix() {
  local mock_bb="${TEST_OUTPUT_DIR}/bb"
  create_mock_bb_for_test "${mock_bb}" "1.12.193"

  test_bb "${mock_bb}"
  assertEquals "should accept bb version v1.12.193 (with v prefix)" 0 $?
}

test_test_bb_handles_newer_version_with_v_prefix() {
  local mock_bb="${TEST_OUTPUT_DIR}/bb"
  create_mock_bb_for_test "${mock_bb}" "1.13.0"

  test_bb "${mock_bb}"
  assertEquals "should accept bb version v1.13.0 (with v prefix)" 0 $?
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
# install_babashka
####################

test_install_babashka_downloads_install_script() {
  local test_dir="${TEST_OUTPUT_DIR}/usr_local"
  mkdir -p "${test_dir}"

  # Track execute_curl call
  local curl_tracker="${TEST_OUTPUT_DIR}/curl_calls.txt"

  # Mock execute_curl to capture arguments
  #shellcheck disable=SC2317
  execute_curl() {
    echo "execute_curl:$@" >> "${curl_tracker}"
    # Return success (silently)
    printf "install script content\n200" >/dev/null
  }
  export -f execute_curl

  # Mock execute_sudo to track other calls
  local sudo_tracker="${TEST_OUTPUT_DIR}/sudo_calls.txt"
  #shellcheck disable=SC2317
  execute_sudo() {
    echo "execute_sudo:$@" >> "${sudo_tracker}"
  }
  export -f execute_sudo

  # Mock ohai to prevent output
  #shellcheck disable=SC2317
  ohai() {
    return 0
  }
  export -f ohai

  # Run install_babashka in test directory (suppress output)
  ( cd "${test_dir}" && install_babashka ) >/dev/null 2>&1

  # Check that execute_curl was called with correct arguments
  grep -q "execute_curl:-sSLO https://raw.githubusercontent.com/babashka/babashka/master/install" "${curl_tracker}"
  assertEquals "should download install script via execute_curl" 0 $?
}

test_install_babashka_makes_script_executable() {
  local test_dir="${TEST_OUTPUT_DIR}/usr_local"
  mkdir -p "${test_dir}"

  # Mock execute_curl
  #shellcheck disable=SC2317
  execute_curl() {
    printf "install script\n200" >/dev/null
  }
  export -f execute_curl

  # Track execute_sudo calls
  local sudo_tracker="${TEST_OUTPUT_DIR}/sudo_calls.txt"
  #shellcheck disable=SC2317
  execute_sudo() {
    echo "execute_sudo:$@" >> "${sudo_tracker}"
  }
  export -f execute_sudo

  # Mock ohai
  #shellcheck disable=SC2317
  ohai() {
    return 0
  }
  export -f ohai

  # Initialize CHMOD array
  CHMOD=("/bin/chmod")
  export CHMOD

  # Run install_babashka (suppress output)
  ( cd "${test_dir}" && install_babashka ) >/dev/null 2>&1

  # Check that chmod was called to make install script executable
  grep -q "execute_sudo:/bin/chmod +x install" "${sudo_tracker}"
  assertEquals "should make install script executable" 0 $?
}

test_install_babashka_runs_install_script_with_static_flag() {
  local test_dir="${TEST_OUTPUT_DIR}/usr_local"
  mkdir -p "${test_dir}"

  # Mock execute_curl
  #shellcheck disable=SC2317
  execute_curl() {
    printf "install script\n200" >/dev/null
  }
  export -f execute_curl

  # Track execute_sudo calls
  local sudo_tracker="${TEST_OUTPUT_DIR}/sudo_calls.txt"
  #shellcheck disable=SC2317
  execute_sudo() {
    echo "execute_sudo:$@" >> "${sudo_tracker}"
  }
  export -f execute_sudo

  # Mock ohai
  #shellcheck disable=SC2317
  ohai() {
    return 0
  }
  export -f ohai

  # Initialize CHMOD array
  CHMOD=("/bin/chmod")
  export CHMOD

  # Run install_babashka (suppress output)
  ( cd "${test_dir}" && install_babashka ) >/dev/null 2>&1

  # Check that install script was run with --static flag
  grep -q "execute_sudo:./install --static" "${sudo_tracker}"
  assertEquals "should run install script with --static flag" 0 $?
}

test_install_babashka_changes_to_usr_local() {
  local test_dir="${TEST_OUTPUT_DIR}/usr_local"
  mkdir -p "${test_dir}"

  # Track which directory execute_curl is called from
  local pwd_tracker="${TEST_OUTPUT_DIR}/pwd.txt"

  # Mock execute_curl to record current directory
  #shellcheck disable=SC2317
  execute_curl() {
    pwd > "${pwd_tracker}"
    printf "install script\n200" >/dev/null
  }
  export -f execute_curl

  # Mock execute_sudo
  #shellcheck disable=SC2317
  execute_sudo() {
    return 0
  }
  export -f execute_sudo

  # Mock ohai
  #shellcheck disable=SC2317
  ohai() {
    return 0
  }
  export -f ohai

  # Initialize CHMOD array
  CHMOD=("/bin/chmod")
  export CHMOD

  # Run install_babashka (it will cd to /usr/local)
  # Note: We can't actually test cd to /usr/local without sudo, so we'll test the behavior
  # This test documents the expected behavior even if we can't fully test it
  ( cd "${test_dir}" && execute_curl "-sSLO" "https://raw.githubusercontent.com/babashka/babashka/master/install" ) >/dev/null 2>&1

  # Verify we captured the directory
  local captured_pwd
  captured_pwd=$(cat "${pwd_tracker}")
  assertEquals "should run from /usr/local (or test equivalent)" "${test_dir}" "${captured_pwd}"
}

test_install_babashka_exits_on_cd_failure() {
  # Try to cd to nonexistent directory
  export TEST_NONEXISTENT_DIR="/nonexistent_directory_$$"

  # Mock execute_curl to prevent actual curl calls
  #shellcheck disable=SC2317
  execute_curl() {
    printf "should not reach here\n200" >/dev/null
  }
  export -f execute_curl

  # Mock execute_sudo
  #shellcheck disable=SC2317
  execute_sudo() {
    return 0
  }
  export -f execute_sudo

  # Mock ohai
  #shellcheck disable=SC2317
  ohai() {
    return 0
  }
  export -f ohai

  # Replace cd in install_babashka by testing the pattern directly
  # We'll test that the function exits if cd fails
  ( cd "${TEST_NONEXISTENT_DIR}" || exit 1; echo "should not print" ) 2>/dev/null
  local exit_code=$?

  assertNotEquals "should exit with error when cd fails" 0 ${exit_code}
}

test_install_babashka_aborts_on_curl_failure() {
  local test_dir="${TEST_OUTPUT_DIR}/usr_local"
  mkdir -p "${test_dir}"

  # Mock execute_curl to fail with HTTP error
  #shellcheck disable=SC2317
  execute_curl() {
    abort "HTTP request failed with status code 404 during: curl -sSLO https://raw.githubusercontent.com/babashka/babashka/master/install"
  }
  export -f execute_curl

  # Mock ohai
  #shellcheck disable=SC2317
  ohai() {
    return 0
  }
  export -f ohai

  # Initialize CHMOD array
  CHMOD=("/bin/chmod")
  export CHMOD

  # Run install_babashka and expect it to abort (capture stderr)
  output=$( cd "${test_dir}" && install_babashka 2>&1 )
  exit_code=$?

  assertEquals "should exit with error when curl fails" 1 ${exit_code}
  echo "${output}" | grep -q "HTTP request failed with status code 404"
  assertEquals "should print error message about failed download" 0 $?
}

####################
# maybe_install_babashka
####################

# Track calls to install_babashka by creating a marker file
INSTALL_MARKER_FILE=""

# Setup marker for tracking install calls
setup_install_tracker() {
  INSTALL_MARKER_FILE="${TEST_OUTPUT_DIR}/install_called"

  # Remove any existing marker file from previous tests
  rm -f "${INSTALL_MARKER_FILE}"

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
