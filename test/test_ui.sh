#!/bin/bash

# Unit tests for lib/ui.sh

# Get the project root directory
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "${TEST_DIR}")"

# Source shunit2
SHUNIT2="${PROJECT_DIR}/shunit2"

# Source library dependencies
# shellcheck disable=SC1090
source "${PROJECT_DIR}/lib/utils.sh"

# Source the file under test
# shellcheck disable=SC1090
source "${PROJECT_DIR}/lib/ui.sh"

# Setup function - runs before each test
setUp() {
  # Clear environment variables
  unset NONINTERACTIVE
  unset ODYSSEY_PREFIX
  unset ODYSSEY_REPOSITORY
  unset ADD_PATHS_D
}

# Teardown function - runs after each test
tearDown() {
  # Clean up environment variables that tests might have set
  unset NONINTERACTIVE
  unset ODYSSEY_PREFIX
  unset ODYSSEY_REPOSITORY
  unset ADD_PATHS_D
}

####################
# Helper functions
####################

# Sets up installation summary environment
# Usage: setup_installation_env <prefix> <repository> [add_paths_d]
setup_installation_env() {
  ODYSSEY_PREFIX="$1"
  ODYSSEY_REPOSITORY="$2"
  if [[ -n "${3:-}" ]]; then
    ADD_PATHS_D=1
  else
    unset ADD_PATHS_D
  fi
}

####################
# ring_bell
####################

test_ring_bell_runs_without_error() {
  ring_bell
  assertEquals "should run without error" 0 $?
}

test_ring_bell_checks_for_terminal() {
  type ring_bell | grep -q "if.*-t 1"
  assertEquals "should check if stdout is a terminal" 0 $?
}

test_ring_bell_uses_printf_with_bell() {
  type ring_bell | grep -q 'printf.*\\a'
  assertEquals "should use printf with bell character" 0 $?
}

####################
# getc
####################

test_getc_accepts_variable_argument() {
  # Mock stty to do nothing
  # shellcheck disable=SC2317
  /bin/stty() {
    return 0
  }
  export -f /bin/stty

  # Override read builtin using a function
  # shellcheck disable=SC2317
  read() {
    # Get the last argument which is the variable name
    local var_name="${!#}"
    # Set the variable to 'a'
    printf -v "${var_name}" 'a'
    return 0
  }
  export -f read

  local result
  getc result

  assertEquals "should store character in variable" "a" "${result}"
}

test_getc_saves_and_restores_terminal_state() {
  # Track calls to stty
  local stty_calls=0
  local saved_state=""

# shellcheck disable=SC2317
  /bin/stty() {
    stty_calls=$((stty_calls + 1))
    if [[ "$1" == "-g" ]]; then
      # Return saved state
      echo "saved_terminal_state"
    elif [[ "$1" == "raw" ]]; then
      # Setting raw mode
      return 0
    elif [[ "$1" == "saved_terminal_state" ]]; then
      # Restoring state
      saved_state="$1"
      return 0
    fi
  }
  export -f /bin/stty
  export stty_calls saved_state

# shellcheck disable=SC2317
  read() {
    # Mock read
    local var_name="${!#}"
    printf -v "${var_name}" 'x'
    return 0
  }
  export -f read

  local char
  getc char

  # stty should be called at least twice: once to save, once to restore
  [[ ${stty_calls} -ge 2 ]]
  assertEquals "should call stty multiple times" 0 $?
}

test_getc_handles_special_characters() {
  # Mock stty to do nothing
  # shellcheck disable=SC2317
  /bin/stty() {
    return 0
  }
  export -f /bin/stty

  # Override read builtin to return newline
  # shellcheck disable=SC2317
  read() {
    local var_name="${!#}"
    printf -v "${var_name}" $'\n'
    return 0
  }
  export -f read

  local result
  getc result

  assertEquals "should handle newline character" $'\n' "${result}"
}

test_getc_reads_single_character() {
  # shellcheck disable=SC2317
  /bin/stty() {
    return 0
  }
  export -f /bin/stty
# shellcheck disable=SC2317
  read() {
    # Check that read is called with -n (for single character)
    # The exact check is looking for -n flag followed by 1
    local has_n_flag=false
    local i
    for ((i=1; i<=$#; i++)); do
      if [[ "${!i}" == "-n" ]]; then
        has_n_flag=true
        break
      fi
    done

    if [[ "${has_n_flag}" == "true" ]]; then
      local var_name="${!#}"
      printf -v "${var_name}" 'y'
      return 0
    fi
    return 1
  }
  export -f read

  local result
  getc result

  assertEquals "should read single character" "y" "${result}"
}

test_getc_disables_echo() {
  local echo_disabled=false

  # shellcheck disable=SC2317
  /bin/stty() {
    if [[ "$*" == *"-echo"* ]]; then
      echo_disabled=true
    fi
    return 0
  }
  export -f /bin/stty
  export echo_disabled

  # Override read builtin
  # shellcheck disable=SC2317
  read() {
    local var_name="${!#}"
    printf -v "${var_name}" 'z'
    return 0
  }
  export -f read

  local result
  getc result

  assertTrue "should disable echo" "${echo_disabled}"
}

####################
# wait_for_user
####################

test_wait_for_user_continues_on_return() {
  # Mock getc to simulate RETURN key (\r)
  # shellcheck disable=SC2317
  getc() {
    # Set the variable passed as argument to \r
    eval "$1=$'\\r'"
  }
  export -f getc

  wait_for_user >/dev/null 2>&1
  assertEquals "should continue when RETURN is pressed" 0 $?
}

test_wait_for_user_continues_on_newline() {
  # Mock getc to simulate ENTER key (\n)
  # shellcheck disable=SC2317
  getc() {
    # Set the variable passed as argument to \n
    eval "$1=$'\\n'"
  }
  export -f getc

  wait_for_user >/dev/null 2>&1
  assertEquals "should continue when ENTER is pressed" 0 $?
}

test_wait_for_user_exits_on_other_key() {
  # Mock getc to simulate 'q' key
  # shellcheck disable=SC2317
  getc() {
    eval "$1='q'"
  }
  export -f getc

  # Run in subshell since wait_for_user calls exit
  (wait_for_user >/dev/null 2>&1)
  exit_code=$?
  assertEquals "should exit with code 1 when other key is pressed" 1 ${exit_code}
}

test_wait_for_user_exits_on_space() {
  # Mock getc to simulate space key
  # shellcheck disable=SC2317
  getc() {
    eval "$1=' '"
  }
  export -f getc

  # Run in subshell since wait_for_user calls exit
  (wait_for_user >/dev/null 2>&1)
  exit_code=$?
  assertEquals "should exit with code 1 when space is pressed" 1 ${exit_code}
}

test_wait_for_user_exits_on_escape() {
  # Mock getc to simulate ESC key
  # shellcheck disable=SC2317
  getc() {
    eval "$1=$'\\e'"
  }
  export -f getc

  # Run in subshell since wait_for_user calls exit
  (wait_for_user >/dev/null 2>&1)
  exit_code=$?
  assertEquals "should exit with code 1 when ESC is pressed" 1 ${exit_code}
}

test_wait_for_user_displays_prompt() {
  # Mock getc to simulate RETURN key
  # shellcheck disable=SC2317
  getc() {
    eval "$1=$'\\r'"
  }
  export -f getc

  output=$(wait_for_user 2>&1)

  echo "$output" | grep -q "Press.*RETURN.*ENTER.*to continue or any other key to abort:"
  assertEquals "should display prompt message" 0 $?
}

####################
# display_installation_summary
####################

test_display_installation_summary_shows_prefix_path() {
  setup_installation_env "/opt/test" "/opt/test/repo"

  output=$(display_installation_summary 2>&1)

  echo "$output" | grep -q "/opt/test/bin/odyssey"
  assertEquals "should display ODYSSEY_PREFIX/bin/odyssey path" 0 $?
}

test_display_installation_summary_shows_repository_path() {
  setup_installation_env "/opt/test" "/opt/test/repo"

  output=$(display_installation_summary 2>&1)

  echo "$output" | grep -q "/opt/test/repo"
  assertEquals "should display ODYSSEY_REPOSITORY path" 0 $?
}

test_display_installation_summary_shows_paths_d_when_set() {
  setup_installation_env "/opt/odyssey" "/opt/odyssey" 1

  output=$(display_installation_summary 2>&1)

  echo "$output" | grep -q "/etc/paths.d/odyssey"
  assertEquals "should display /etc/paths.d/odyssey when ADD_PATHS_D is set" 0 $?
}

test_display_installation_summary_hides_paths_d_when_not_set() {
  setup_installation_env "/usr/local" "/usr/local/odyssey"

  output=$(display_installation_summary 2>&1)

  echo "$output" | grep -q "/etc/paths.d/odyssey"
  assertNotEquals "should not display /etc/paths.d/odyssey when ADD_PATHS_D is not set" 0 $?
}

test_display_installation_summary_mentions_babashka() {
  setup_installation_env "/opt/test" "/opt/test/repo"

  output=$(display_installation_summary 2>&1)

  echo "$output" | grep -q "Babashka"
  assertEquals "should mention Babashka installation" 0 $?
}

test_display_installation_summary_has_install_header() {
  setup_installation_env "/opt/test" "/opt/test/repo"

  output=$(display_installation_summary 2>&1)

  echo "$output" | grep -q "This script will install"
  assertEquals "should display installation header" 0 $?
}

test_display_installation_summary_checks_add_paths_d() {
  type display_installation_summary | grep -q 'ADD_PATHS_D'
  assertEquals "should check ADD_PATHS_D variable" 0 $?
}


# Load and run shunit2
# Suppress harmless function export warnings from shunit2
# shellcheck disable=SC1090
. "${SHUNIT2}" 2> >(grep -v "error importing function definition" >&2)
