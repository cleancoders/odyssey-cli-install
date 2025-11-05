#!/bin/bash

# Unit tests for bin/install.sh

# Get the project root directory
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "${TEST_DIR}")"

# Source shunit2
SHUNIT2="${PROJECT_DIR}/shunit2"
source "${PROJECT_DIR}/bin/install.sh"

# Setup function - runs before each test
setUp() {
  # Clear environment variables
  unset NONINTERACTIVE
  unset INTERACTIVE
  unset CI
  unset ODYSSEY_ON_LINUX
  unset ODYSSEY_ON_MACOS

  # Initialize CHMOD as array to prevent set -u issues
  CHMOD=("/bin/chmod")

  # Mock have_sudo_access to prevent password prompts during setup
  have_sudo_access() {
    # shellcheck disable=SC2317
    return 0
  }
  export -f have_sudo_access

  # Mock execute_sudo to prevent actual sudo calls
  execute_sudo() {
    # shellcheck disable=SC2317
    return 0
  }
  export -f execute_sudo
}

# Teardown function - runs after each test
tearDown() {
  # Clean up any temp files
  rm -f /tmp/odyssey_*.txt
  rm -f /tmp/curl_test_* /tmp/chmod_test_* /tmp/chflags_test_* /tmp/chattr_test_*
  rm -f /tmp/chflags_unset_test_* /tmp/chattr_unset_test_* /tmp/pwd_test_* /tmp/ohai_test_*
  rm -f /tmp/order_check.txt
  rm -rf /tmp/odyssey_test_*

  # Clean up environment variables that tests might have set
  unset POSIXLY_CORRECT
  unset CI
  unset INTERACTIVE
  unset NONINTERACTIVE
  unset ODYSSEY_PREFIX
  unset ODYSSEY_ON_MACOS
  unset ODYSSEY_ON_LINUX
  unset CHMOD
  unset ODYSSEY_TEST_TRACKER

  # Re-source install.sh to restore original functions that may have been mocked
  # shellcheck disable=SC1090
  source "${PROJECT_DIR}/bin/install.sh"
}

####################
# Helper functions
####################

# Sets up a test odyssey environment with common mocks
setup_test_odyssey_env() {
  export ODYSSEY_PREFIX="/tmp/odyssey_test_$$"
  mkdir -p "${ODYSSEY_PREFIX}/bin"
  export CHMOD=("/bin/chmod")
}

# Mocks execute_sudo to run commands directly (for permission tests)
mock_execute_sudo_passthrough() {
  execute_sudo() {
    "$@"
  }
  export -f execute_sudo
}

# Creates a tracking file to verify command calls
# Returns the temp file path
create_tracker_file() {
  local temp_file="/tmp/${1:-test}_$$"
  echo "0" > "${temp_file}"
  echo "${temp_file}"
}

# Mock ohai to prevent output
mock_ohai_silent() {
  # shellcheck disable=SC2317
  ohai() {
    return 0
  }
  export -f ohai
}

# Mock execute_sudo for install_odyssey_cli tests
# Tracks curl/chmod/chflags/chattr calls in temp file
mock_execute_sudo_for_install() {
  local tracker="$1"
  local os_type="${2:-macos}"  # macos or linux

  # Export the tracker path so the execute_sudo function can access it
  export ODYSSEY_TEST_TRACKER="${tracker}"

  # shellcheck disable=SC2317
  execute_sudo() {
    if [[ "$1" == "curl" ]]; then
      # Find the URL argument (look for argument after -LO or -O flag)
      local url=""
      local i=0
      for arg in "$@"; do
        if [[ "${arg}" == http* ]]; then
          url="${arg}"
          break
        fi
      done
      echo "curl:${url}" >> "${ODYSSEY_TEST_TRACKER}"
      # Return mock response in format expected by execute_curl: body\n<status_code>
      printf "mock binary content\n200"
    elif [[ "$1" == "/bin/chmod" ]]; then
      echo "chmod:$2" >> "${ODYSSEY_TEST_TRACKER}"
      chmod "$2" "${ODYSSEY_PREFIX}/bin/odyssey" 2>/dev/null || true
    elif [[ "$1" == "/usr/bin/chflags" ]]; then
      echo "chflags:$2:$3" >> "${ODYSSEY_TEST_TRACKER}"
    elif [[ "$1" == *"chattr"* ]]; then
      echo "chattr:$2:$3" >> "${ODYSSEY_TEST_TRACKER}"
    fi
  }
  export -f execute_sudo

  # Mock which for Linux chattr tests
  if [[ "${os_type}" == "linux" ]]; then
    # shellcheck disable=SC2317
    which() {
      echo "/usr/bin/chattr"
    }
    export -f which
  fi
}

####################
# usage
####################

test_usage_displays_help() {
  output=$(usage 0 2>&1)

  echo "$output" | grep "Clean Code Odyssey CLI Installer" >/dev/null
  assertEquals "should display installer name" 0 $?

  echo "$output" | grep "Usage:" >/dev/null
  assertEquals "should display usage" 0 $?
}

####################
# parse_args
####################

test_parse_args_handles_no_args() {
  parse_args
  assertEquals "should succeed with no arguments" 0 $?
}

test_parse_args_handles_help_flag() {
  # parse_args calls usage which calls exit, so run in subshell
  output=$(parse_args --help 2>&1 || true)

  echo "$output" | grep "Usage:" >/dev/null
  assertEquals "should print usage" 0 $?
}

####################
# setup_directories
####################

test_setup_directories_creates_bin_directory() {
  setup_test_odyssey_env
  MKDIR=("/bin/mkdir" "-p")
  mock_execute_sudo_passthrough

  setup_directories

  [[ -d "${ODYSSEY_PREFIX}/bin" ]]
  assertEquals "bin directory should be created" 0 $?
}

test_setup_directories_sets_correct_permissions() {
  setup_test_odyssey_env
  MKDIR=("/bin/mkdir" "-p")
  mock_execute_sudo_passthrough

  setup_directories

  local perms
  perms=$(stat -f "%OLp" "${ODYSSEY_PREFIX}/bin" 2>/dev/null || stat -c "%a" "${ODYSSEY_PREFIX}/bin" 2>/dev/null)
  assertEquals "bin directory should have 755 permissions" "755" "${perms}"
}

test_setup_directories_skips_existing_directory() {
  setup_test_odyssey_env
  MKDIR=("/bin/mkdir" "-p")

  # Track if execute_sudo was called
  local execute_sudo_called=0
  execute_sudo() {
    execute_sudo_called=1
    "$@"
  }
  export -f execute_sudo

  setup_directories

  assertEquals "should not call execute_sudo for existing directory" 0 "${execute_sudo_called}"
}

test_setup_directories_uses_execute_sudo() {
  ODYSSEY_PREFIX="/tmp/odyssey_test_$$"
  mkdir -p "${ODYSSEY_PREFIX}"
  MKDIR=("/bin/mkdir" "-p")
  CHMOD=("/bin/chmod")

  # Track execute_sudo calls
  local mkdir_called=0
  local chmod_called=0

# shellcheck disable=SC2317
  execute_sudo() {
    if [[ "$1" == "/bin/mkdir" ]]; then
      mkdir_called=1
    elif [[ "$1" == "/bin/chmod" ]]; then
      chmod_called=1
    fi
    "$@"
  }
  export -f execute_sudo

  setup_directories

  assertEquals "should call mkdir via execute_sudo" 1 "${mkdir_called}"
  assertEquals "should call chmod via execute_sudo" 1 "${chmod_called}"
}

####################
# install_odyssey_cli
####################

test_install_odyssey_cli_downloads_binary() {
  setup_test_odyssey_env
  export ODYSSEY_ON_MACOS=1

  local tracker=$(create_tracker_file "curl_test")
  mock_execute_sudo_for_install "${tracker}" "macos"
  mock_ohai_silent

  install_odyssey_cli

  local curl_line
  curl_line=$(grep "^curl:" "${tracker}")
  local curl_url="${curl_line#curl:}"

  assertEquals "should download from correct URL" "https://d154yre1ylyo3c.cloudfront.net/bin/odyssey" "${curl_url}"
}

test_install_odyssey_cli_sets_executable_permissions() {
  setup_test_odyssey_env
  export ODYSSEY_ON_MACOS=1

  local tracker=$(create_tracker_file "chmod_test")
  mock_execute_sudo_for_install "${tracker}" "macos"
  mock_ohai_silent

  install_odyssey_cli

  local chmod_line
  chmod_line=$(grep "^chmod:" "${tracker}")
  local chmod_mode="${chmod_line#chmod:}"

  assertEquals "should set executable permission with +x" "+x" "${chmod_mode}"
}

test_install_odyssey_cli_sets_immutable_flag_on_macos() {
  setup_test_odyssey_env
  export ODYSSEY_ON_MACOS=1

  local tracker=$(create_tracker_file "chflags_test")
  mock_execute_sudo_for_install "${tracker}" "macos"
  mock_ohai_silent

  install_odyssey_cli

  local chflags_line
  chflags_line=$(grep "^chflags:" "${tracker}")
  local chflags_data="${chflags_line#chflags:}"
  local chflags_flag="${chflags_data%%:*}"

  assertEquals "should set user immutable flag" "uchg" "${chflags_flag}"
}

test_install_odyssey_cli_unsets_immutable_if_file_exists_on_mac() {
  setup_test_odyssey_env
  export ODYSSEY_ON_MACOS=1

  # Create existing odyssey file to simulate update scenario
  touch "${ODYSSEY_PREFIX}/bin/odyssey"

  local tracker=$(create_tracker_file "chflags_unset_test")
  mock_execute_sudo_for_install "${tracker}" "macos"
  mock_ohai_silent

  install_odyssey_cli

  local chflags_calls
  chflags_calls=$(grep "^chflags:" "${tracker}")

  echo "${chflags_calls}" | head -1 | grep -q "nouchg:odyssey"
  assertEquals "should call chflags with nouchg to remove immutable flag first" 0 $?

  echo "${chflags_calls}" | tail -1 | grep -q "uchg:odyssey"
  assertEquals "should call chflags with uchg to set immutable flag after download" 0 $?

  local call_count
  call_count=$(echo "${chflags_calls}" | wc -l | tr -d ' ')
  assertEquals "should call chflags twice (nouchg then uchg)" "2" "${call_count}"
}

test_install_odyssey_cli_unsets_immutable_if_file_exists_on_linux() {
  setup_test_odyssey_env
  unset ODYSSEY_ON_MACOS

  # Create existing odyssey file to simulate update scenario
  touch "${ODYSSEY_PREFIX}/bin/odyssey"

  local tracker=$(create_tracker_file "chattr_unset_test")
  mock_execute_sudo_for_install "${tracker}" "linux"
  mock_ohai_silent

  install_odyssey_cli

  local chattr_calls
  chattr_calls=$(grep "^chattr:" "${tracker}")

  echo "${chattr_calls}" | head -1 | grep -q "\-i:odyssey"
  assertEquals "should call chattr with -i to remove immutable flag first" 0 $?

  echo "${chattr_calls}" | tail -1 | grep -q "+i:odyssey"
  assertEquals "should call chattr with +i to set immutable flag after download" 0 $?

  local call_count
  call_count=$(echo "${chattr_calls}" | wc -l | tr -d ' ')
  assertEquals "should call chattr twice (-i then +i)" "2" "${call_count}"
}

test_install_odyssey_cli_sets_immutable_flag_on_linux() {
  setup_test_odyssey_env
  unset ODYSSEY_ON_MACOS

  local tracker=$(create_tracker_file "chattr_test")
  mock_execute_sudo_for_install "${tracker}" "linux"
  mock_ohai_silent

  install_odyssey_cli

  local chattr_line
  chattr_line=$(grep "^chattr:" "${tracker}")
  local chattr_data="${chattr_line#chattr:}"
  local chattr_flag="${chattr_data%%:*}"

  assertEquals "should set immutable flag" "+i" "${chattr_flag}"
}

test_install_odyssey_cli_changes_to_bin_directory() {
  setup_test_odyssey_env
  export ODYSSEY_ON_MACOS=1
  local original_pwd="${PWD}"

  local tracker=$(create_tracker_file "pwd_test")

  # shellcheck disable=SC2317
  execute_sudo() {
    if [[ "$1" == "curl" ]]; then
      pwd > "${tracker}"
      # Return mock response in format expected by execute_curl
      printf "mock content\n200"
    elif [[ "$1" == "/bin/chmod" ]]; then
      chmod +x "${ODYSSEY_PREFIX}/bin/odyssey"
    elif [[ "$1" == "/usr/bin/chflags" || "$1" == *"chattr"* ]]; then
      return 0
    fi
  }
  export -f execute_sudo
  mock_ohai_silent

  install_odyssey_cli

  assertEquals "should return to original directory after install" "${original_pwd}" "${PWD}"

  local curl_pwd
  curl_pwd=$(cat "${tracker}")
  assertEquals "should change to bin directory for install" "${ODYSSEY_PREFIX}/bin" "${curl_pwd}"
}

test_install_odyssey_cli_exits_on_cd_failure() {
  export ODYSSEY_PREFIX="/tmp/odyssey_test_nonexistent_$$"
  export CHMOD=("/bin/chmod")
  export ODYSSEY_ON_MACOS=1

  execute_sudo() {
    return 0
  }
  export -f execute_sudo
  mock_ohai_silent

  ( install_odyssey_cli 2>/dev/null )
  local exit_code=$?

  assertNotEquals "should exit with error when cd fails" 0 "${exit_code}"
}

test_install_odyssey_cli_displays_downloading_message() {
  setup_test_odyssey_env
  export ODYSSEY_ON_MACOS=1

  local tracker=$(create_tracker_file "ohai_test")
  mock_execute_sudo_for_install "${tracker}" "macos"

  # Custom ohai mock to track the message
  # shellcheck disable=SC2317
  ohai() {
    echo "1:$1" > "${tracker}"
  }
  export -f ohai

  install_odyssey_cli

  local result
  result=$(cat "${tracker}")
  local ohai_message="${result#*:}"

  echo "${ohai_message}" | grep -q "Downloading"
  assertEquals "message should mention downloading" 0 $?
}



####################
# main() function tests
####################

test_main_calls_check_bash_version() {
  # Verify main function calls check_bash_version
  type main | grep -q 'check_bash_version'
  assertEquals "main should call check_bash_version" 0 $?
}

test_main_calls_check_environment_conflicts() {
  # Verify main function calls check_environment_conflicts
  type main | grep -q 'check_environment_conflicts'
  assertEquals "main should call check_environment_conflicts" 0 $?
}

test_main_calls_parse_args() {
  # Verify main function calls parse_args
  type main | grep -q 'parse_args'
  assertEquals "main should call parse_args" 0 $?
}

test_main_calls_setup_functions() {
  # Verify main calls all setup functions
  type main | grep -q 'setup_noninteractive_mode'
  assertEquals "main should call setup_noninteractive_mode" 0 $?

  type main | grep -q 'setup_user'
  assertEquals "main should call setup_user" 0 $?

  type main | grep -q 'detect_os'
  assertEquals "main should call detect_os" 0 $?

  type main | grep -q 'setup_paths'
  assertEquals "main should call setup_paths" 0 $?

  type main | grep -q 'setup_sudo_trap'
  assertEquals "main should call setup_sudo_trap" 0 $?
}

test_main_calls_validation_checks() {
  # Verify main calls all validation functions
  type main | grep -q 'check_sudo_access'
  assertEquals "main should call check_sudo_access" 0 $?

  type main | grep -q 'check_prefix_permissions'
  assertEquals "main should call check_prefix_permissions" 0 $?

  type main | grep -q 'check_architecture'
  assertEquals "main should call check_architecture" 0 $?

  type main | grep -q 'check_macos_version'
  assertEquals "main should call check_macos_version" 0 $?
}

test_main_calls_display_installation_summary() {
  # Verify main displays installation summary
  type main | grep -q 'display_installation_summary'
  assertEquals "main should call display_installation_summary" 0 $?
}

test_main_calls_wait_for_user_when_interactive() {
  # Verify main calls wait_for_user in interactive mode
  type main | grep -q 'wait_for_user'
  assertEquals "main should call wait_for_user" 0 $?
}

test_main_calls_installation_functions() {
  # Verify main calls installation functions
  type main | grep -q 'setup_directories'
  assertEquals "main should call setup_directories" 0 $?

  type main | grep -q 'maybe_install_babashka'
  assertEquals "main should call maybe_install_babashka" 0 $?

  type main | grep -q 'install_odyssey_cli'
  assertEquals "main should call install_odyssey_cli" 0 $?
}

test_main_calls_display_success_message() {
  # Verify main displays success message at end
  type main | grep -q 'display_success_message'
  assertEquals "main should call display_success_message" 0 $?
}

test_main_execution_order() {
  # Verify main executes functions in correct order
  local main_body
  main_body=$(type main | tail -n +4)

  # Check that validation comes before installation
  echo "$main_body" | grep -n "check_bash_version" > /tmp/order_check.txt
  echo "$main_body" | grep -n "install_odyssey_cli" >> /tmp/order_check.txt

  local check_line=$(head -1 /tmp/order_check.txt | cut -d: -f1)
  local install_line=$(tail -1 /tmp/order_check.txt | cut -d: -f1)

  rm -f /tmp/order_check.txt

  [[ ${check_line} -lt ${install_line} ]]
  assertEquals "validation should occur before installation" 0 $?
}

test_main_skips_wait_for_user_in_noninteractive_mode() {
  # Verify that wait_for_user is conditional on NONINTERACTIVE
  type main | grep -B2 "wait_for_user" | grep -q "NONINTERACTIVE"
  assertEquals "wait_for_user should be conditional on NONINTERACTIVE" 0 $?
}

# Load and run shunit2
# Suppress harmless function export warnings from shunit2
# shellcheck disable=SC1090
. "${SHUNIT2}" 2> >(grep -v "error importing function definition" >&2)
