#!/bin/bash

# Unit tests for lib/execution.sh

# Get the project root directory
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "${TEST_DIR}")"

# Source shunit2
SHUNIT2="${PROJECT_DIR}/shunit2"

# Source the file under test
# shellcheck disable=SC1090
source "${PROJECT_DIR}/lib/execution.sh"

# Test fixtures
TEST_OUTPUT_DIR=""
MOCK_SUDO=""

# One-time setup - runs once before all tests
oneTimeSetUp() {
  # Create a single temporary directory for all tests
  TEST_OUTPUT_DIR="$(mktemp -d)"
}

# Setup function - runs before each test
setUp() {
  # Create a mock for sudo (recreate each time since some tests delete it)
  MOCK_SUDO="${TEST_OUTPUT_DIR}/sudo"

  # Create/clear log file to track sudo calls
  SUDO_CALLS_LOG="${TEST_OUTPUT_DIR}/sudo_calls.log"
  > "${SUDO_CALLS_LOG}"

  cat > "${MOCK_SUDO}" << EOF
#!/bin/bash
# Stores args and returns success/failure
printf '%s ' "\$@" >> "${SUDO_CALLS_LOG}"
exit \${MOCK_SUDO_EXIT_CODE:-0}
EOF

  chmod +x "${MOCK_SUDO}"

  unset HAVE_SUDO_ACCESS
  unset SUDO_ASKPASS
  unset NONINTERACTIVE
  unset ODYSSEY_ON_MACOS
}

# Teardown function - runs after each test
tearDown() {
  # Change back to project directory to avoid issues with deleted directories
  cd "${PROJECT_DIR}" 2>/dev/null || true
}

# One-time teardown - runs once after all tests
oneTimeTearDown() {
  # Clean up temporary directory
  if [[ -n "${TEST_OUTPUT_DIR}" && -d "${TEST_OUTPUT_DIR}" ]]; then
    rm -rf "${TEST_OUTPUT_DIR}"
  fi
}

mock_execute(){
    #shellcheck disable=SC2317
    #shellcheck disable=SC2050
    execute() {
      if [[ "$1" == "/usr/bin/sudo" ]]; then
        shift
        "${MOCK_SUDO}" "$@"
      else
        command "$@"
      fi
    }
    export -f execute
}

# Helper: Mock curl to simulate file download with status code
# Usage: mock_curl_with_file_output "body content" "status_code"
mock_curl_with_file_output() {
  export MOCK_CURL_BODY="$1"
  export MOCK_CURL_STATUS="$2"

  #shellcheck disable=SC2317
  execute_sudo() {
    if [[ "$1" == "curl" ]]; then
      # Find output file from -o flag or extract from URL for -O/-LO
      local i=0
      local output_file=""
      local has_O_flag=false

      while [[ $i -lt $# ]]; do
        if [[ "${!i}" == "-o" ]]; then
          ((i++))
          output_file="${!i}"
          break
        elif [[ "${!i}" == "-O" ]] || [[ "${!i}" == "-LO" ]]; then
          has_O_flag=true
        fi
        ((i++))
      done

      # If -O or -LO flag, extract filename from URL (last argument)
      if [[ "${has_O_flag}" == "true" ]]; then
        local url="${!#}"
        output_file="${url##*/}"
      fi

      # Write to file if output file specified, otherwise to stdout
      if [[ -n "${output_file}" ]]; then
        printf "%s" "${MOCK_CURL_BODY}" > "${output_file}"
        printf "\n%s" "${MOCK_CURL_STATUS}"
      else
        printf "%s\n%s" "${MOCK_CURL_BODY}" "${MOCK_CURL_STATUS}"
      fi
    elif [[ "$1" == "tee" ]]; then
      command tee "$2"
    fi
  }
  export -f execute_sudo
}

# Helper: Mock curl to simulate response without file output (for error cases)
# Usage: mock_curl_with_status "body content" "status_code"
mock_curl_with_status() {
  export MOCK_CURL_BODY="$1"
  export MOCK_CURL_STATUS="$2"

  #shellcheck disable=SC2317
  execute_sudo() {
    if [[ "$1" == "curl" ]]; then
      printf "%s\n%s" "${MOCK_CURL_BODY}" "${MOCK_CURL_STATUS}"
    elif [[ "$1" == "tee" ]]; then
      command tee "$2"
    fi
  }
  export -f execute_sudo
}

##################################
# have_sudo_access
##################################

test_sudo_access_returns_success() {
  have_sudo_access "${MOCK_SUDO}"
  local result=$?
  assertEquals "should return success" 0 ${result}
}

test_sudo_access_returns_1() {
  have_sudo_access "blah"
  local result=$?
  assertEquals "should return 1 when no sudo found" 1 ${result}
}

test_sudo_adds_askpass_flag() {
  export SUDO_ASKPASS="/path/to/askpass"
  have_sudo_access "${MOCK_SUDO}"
   # Check that sudo was called with -A flag
  grep -- "-A" "${SUDO_CALLS_LOG}" >/dev/null
  assertEquals "should call sudo with -A flag" 0 $?
}

test_sudo_adds_noninteractive_flag() {
  export NONINTERACTIVE=1
  have_sudo_access "${MOCK_SUDO}"
  # Check that sudo was called with -n flag
  grep -- "-n" "${SUDO_CALLS_LOG}" >/dev/null
  assertEquals "should call sudo with -n flag" 0 $?
}

test_sudo_askpass_takes_precedence_over_noninteractive() {
  export SUDO_ASKPASS="/path/to/askpass"
  export NONINTERACTIVE=1
  have_sudo_access "${MOCK_SUDO}"
  # Should have -A but not -n
  grep -- "-A" "${SUDO_CALLS_LOG}" >/dev/null
  assertEquals "should call sudo with -A flag" 0 $?
  grep -- "-n" "${SUDO_CALLS_LOG}" >/dev/null
  assertNotEquals "should not call sudo with -n flag" 0 $?
}

test_sudo_access_is_cached() {
  have_sudo_access "${MOCK_SUDO}"
  # Call it again - sudo should not be invoked again
  rm "${SUDO_CALLS_LOG}"
  have_sudo_access "${MOCK_SUDO}"
  assertFalse "should not call sudo again when cached" "[ -f '${SUDO_CALLS_LOG}' ]"
}

test_sudo_access_cached_value_is_used() {
  export HAVE_SUDO_ACCESS=0
  # Remove sudo to prove it's not being called
  rm "${MOCK_SUDO}"
  have_sudo_access
  assertEquals "should return cached value" 0 $?
}

test_no_sudo_on_mac() {
  export ODYSSEY_ON_MACOS=1
  export HAVE_SUDO_ACCESS=1
  # Run in subshell to capture output and prevent exit from killing test
  output=$(have_sudo_access "${MOCK_SUDO}" 2>&1)
  exit_code=$?
  assertEquals "should exit 1 if no sudo access on mac" 1 ${exit_code}
  # Check that abort was called with the expected message
  echo "$output" | grep "Need sudo access on macOS" >/dev/null
  assertEquals "should print error message about sudo" 0 $?
}

############
# execute
############

test_execute_runs_successful_command() {
  local test_file="${TEST_OUTPUT_DIR}/executed.txt"
  execute touch "${test_file}"
  assertTrue "should create file when command succeeds" "[ -f '${test_file}' ]"
}                                                                                       

test_execute_aborts_on_failure() {
  export ODYSSEY_ON_MACOS=0
  # Run in subshell to capture abort and prevent exit
  output=$(execute false 2>&1)
  exit_code=$?

  assertEquals "should exit 1 when command fails" 1 ${exit_code}
  echo "$output" | grep "Failed during: false" >/dev/null
  assertEquals "should print error message about failed command" 0 $?
}

test_execute_passes_arguments_correctly() {
  local test_file="${TEST_OUTPUT_DIR}/test.txt"
  execute echo "hello world" > "${test_file}"
  grep "hello world" "${test_file}" >/dev/null
  assertEquals "should pass arguments to command" 0 $?
}

############
# execute_sudo
############

test_execute_sudo_runs_without_sudo_when_root() {
  # We can't actually set EUID to 0, but we can test that when
  # have_sudo_access returns false (simulating no sudo), it runs without sudo
  local test_file="${TEST_OUTPUT_DIR}/sudo_test.txt"
  local execute_log="${TEST_OUTPUT_DIR}/execute_log.txt"

  # Mock have_sudo_access to return false (simulating EUID=0 or no sudo scenario)
  #shellcheck disable=SC2317
  have_sudo_access() {
    return 1
  }
  export -f have_sudo_access

  # Mock execute to log what it's called with
  #shellcheck disable=SC2317
  execute() {
    printf '%s ' "$@" >> "${execute_log}"
    command "$@"
  }
  export -f execute

  execute_sudo touch "${test_file}" >/dev/null 2>&1
  assertTrue "should create file" "[ -f '${test_file}' ]"
  # Verify sudo was NOT called
  grep "/usr/bin/sudo" "${execute_log}" >/dev/null
  assertNotEquals "should not call sudo when have_sudo_access returns false" 0 $?
}

test_execute_sudo_calls_sudo_with_command() {
  # Mock have_sudo_access to return success without prompting
  #shellcheck disable=SC2317
  have_sudo_access() {
    return 0
  }
  export -f have_sudo_access
  mock_execute


  execute_sudo echo "test command" >/dev/null 2>&1
  grep "echo test command" "${SUDO_CALLS_LOG}" >/dev/null
  assertEquals "should pass command to sudo" 0 $?
}

test_execute_sudo_adds_askpass_flag() {
  export SUDO_ASKPASS="/path/to/askpass"

  # Mock have_sudo_access to return success without prompting
  #shellcheck disable=SC2317
  have_sudo_access() {
    return 0
  }
  export -f have_sudo_access
  mock_execute

  execute_sudo echo "test" >/dev/null 2>&1
  grep -- "-A" "${SUDO_CALLS_LOG}" >/dev/null
  assertEquals "should add -A flag when SUDO_ASKPASS is set" 0 $?

  unset SUDO_ASKPASS
}

############
# execute_curl
############

test_execute_curl_succeeds_with_200_status() {
  mock_curl_with_file_output "test content" "200"

  local output_file="${TEST_OUTPUT_DIR}/downloaded.txt"
  execute_curl "-o" "${output_file}" "http://example.com/file"

  assertTrue "should create output file" "[ -f '${output_file}' ]"
  grep "test content" "${output_file}" >/dev/null
  assertEquals "should write body to file" 0 $?
}

test_execute_curl_succeeds_with_201_status() {
  mock_curl_with_file_output "created" "201"

  local output_file="${TEST_OUTPUT_DIR}/created.txt"
  execute_curl "-o" "${output_file}" "http://example.com/resource"

  assertTrue "should create output file for 201 status" "[ -f '${output_file}' ]"
}

test_execute_curl_aborts_on_404_status() {
  mock_curl_with_status "Not Found" "404"

  local output_file="${TEST_OUTPUT_DIR}/notfound.txt"
  output=$(execute_curl "-o" "${output_file}" "http://example.com/missing" 2>&1)
  exit_code=$?

  assertEquals "should exit 1 on 404 status" 1 ${exit_code}
  echo "$output" | grep "HTTP request failed with status code 404" >/dev/null
  assertEquals "should print error about 404 status" 0 $?
}

test_execute_curl_aborts_on_500_status() {
  mock_curl_with_status "Internal Server Error" "500"

  output=$(execute_curl "-o" "${TEST_OUTPUT_DIR}/error.txt" "http://example.com/fail" 2>&1)
  exit_code=$?

  assertEquals "should exit 1 on 500 status" 1 ${exit_code}
  echo "$output" | grep "HTTP request failed with status code 500" >/dev/null
  assertEquals "should print error about 500 status" 0 $?
}

test_execute_curl_handles_dash_O_flag() {
  mock_curl_with_file_output "file contents" "200"

  cd "${TEST_OUTPUT_DIR}" || exit 1
  execute_curl "-O" "http://example.com/path/to/myfile.txt"

  assertTrue "should create file with name from URL" "[ -f 'myfile.txt' ]"
  grep "file contents" "myfile.txt" >/dev/null
  assertEquals "should write correct contents" 0 $?
}

test_execute_curl_handles_dash_LO_flag() {
  mock_curl_with_file_output "redirected content" "200"

  cd "${TEST_OUTPUT_DIR}" || exit 1
  execute_curl "-LO" "http://example.com/redirect/target.bin"

  assertTrue "should create file with name from URL" "[ -f 'target.bin' ]"
  grep "redirected content" "target.bin" >/dev/null
  assertEquals "should write redirected content" 0 $?
}

test_execute_curl_writes_to_stdout_without_output_flag() {
  mock_curl_with_file_output "stdout content" "200"

  output=$(execute_curl "http://example.com/data")

  echo "$output" | grep "stdout content" >/dev/null
  assertEquals "should write to stdout when no output file specified" 0 $?
}

test_execute_curl_passes_curl_args_correctly() {
  local captured_args="${TEST_OUTPUT_DIR}/curl_args.txt"

  # Mock execute_sudo to capture arguments
  #shellcheck disable=SC2317
  execute_sudo() {
    if [[ "$1" == "curl" ]]; then
      # Save all arguments to file
      printf '%s\n' "$@" > "${captured_args}"
      echo -e "data\n200"
    elif [[ "$1" == "tee" ]]; then
      command tee "$2"
    fi
  }
  export -f execute_sudo

  execute_curl "-H" "Authorization: Bearer token" "-L" "http://example.com/api" >/dev/null

  grep -- "curl" "${captured_args}" >/dev/null
  assertEquals "should pass curl command" 0 $?
  grep -- "-H" "${captured_args}" >/dev/null
  assertEquals "should pass -H flag" 0 $?
  grep -- "Authorization: Bearer token" "${captured_args}" >/dev/null
  assertEquals "should pass header value" 0 $?
}

test_execute_curl_handles_multiline_response() {
  mock_curl_with_file_output "line1
line2
line3" "200"

  local output_file="${TEST_OUTPUT_DIR}/multiline.txt"
  execute_curl "-o" "${output_file}" "http://example.com/multiline"

  assertTrue "should create output file" "[ -f '${output_file}' ]"
  grep "line1" "${output_file}" >/dev/null
  assertEquals "should contain first line" 0 $?
  grep "line3" "${output_file}" >/dev/null
  assertEquals "should contain last line" 0 $?
  grep "200" "${output_file}" >/dev/null
  assertNotEquals "should not include status code in body" 0 $?
}

# Load and run shunit2
# shellcheck disable=SC1090
. "${SHUNIT2}"

#  1. Test the caching behavior (easiest - set HAVE_SUDO_ACCESS before calling)
#  2. Test environment variable handling (check if -A or -n flags would be used)
#  3. Mock abort() to test macOS failure case
