#!/bin/bash

# Unit tests for lib/utils.sh

# Get the project root directory
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "${TEST_DIR}")"

# Source shunit2
SHUNIT2="${PROJECT_DIR}/shunit2"

# Source the file under test
# shellcheck disable=SC1090
source "${PROJECT_DIR}/lib/utils.sh"

####################
# abort
####################

test_abort_exits_with_1() {
  output=$(abort "test error message" 2>&1)
  exit_code=$?

  assertEquals "should exit with code 1" 1 ${exit_code}
  echo "$output" | grep "test error message" >/dev/null
  assertEquals "should print error message" 0 $?
}

test_abort_prints_to_stderr() {
  output=$(abort "error on stderr" 2>&1 1>/dev/null)

  echo "$output" | grep "error on stderr" >/dev/null
  assertEquals "should print to stderr" 0 $?
}

test_abort_handles_multiple_arguments() {
  output=$(abort "line 1" "line 2" "line 3" 2>&1)

  echo "$output" | grep "line 1" >/dev/null
  assertEquals "should print first argument" 0 $?
  echo "$output" | grep "line 2" >/dev/null
  assertEquals "should print second argument" 0 $?
  echo "$output" | grep "line 3" >/dev/null
  assertEquals "should print third argument" 0 $?
}

####################
# shell_join
####################

test_shell_join_single_arg() {
  result=$(shell_join "hello")
  assertEquals "should return single arg" "hello" "${result}"
}

test_shell_join_multiple_args() {
  result=$(shell_join "hello" "world" "test")
  assertEquals "should join with spaces" "hello world test" "${result}"
}

test_shell_join_escapes_spaces_in_args() {
  result=$(shell_join "hello world" "foo bar")
  # Only spaces in args after the first are escaped
  assertEquals "should escape spaces in arguments after first" "hello world foo\ bar" "${result}"
}

test_shell_join_empty_args() {
  result=$(shell_join "" "test" "")
  assertEquals "should handle empty args" " test " "${result}"
}

####################
# chomp
####################

test_chomp_removes_trailing_newline() {
  result=$(chomp $'hello\n')
  assertEquals "should remove trailing newline" "hello" "${result}"
}

test_chomp_no_newline() {
  result=$(chomp "hello")
  assertEquals "should return unchanged if no newline" "hello" "${result}"
}

test_chomp_only_removes_trailing_newline() {
  result=$(chomp $'hello\nworld\n')
  # Only removes the first occurrence of newline
  assertEquals "should only remove trailing newline" $'hello\nworld' "${result}"
}

####################
# ohai
####################

test_ohai_prints_message() {
  output=$(ohai "test message" 2>&1)

  echo "$output" | grep "test message" >/dev/null
  assertEquals "should print message" 0 $?
}

test_ohai_joins_arguments() {
  output=$(ohai "hello" "world" 2>&1)

  echo "$output" | grep "hello world" >/dev/null
  assertEquals "should join arguments" 0 $?
}

test_ohai_includes_arrow() {
  output=$(ohai "test" 2>&1)

  echo "$output" | grep "==>" >/dev/null
  assertEquals "should include arrow prefix" 0 $?
}

####################
# warn
####################

test_warn_prints_message() {
  output=$(warn "test warning" 2>&1)

  echo "$output" | grep "test warning" >/dev/null
  assertEquals "should print warning message" 0 $?
}

test_warn_includes_warning_prefix() {
  output=$(warn "test" 2>&1)

  # Strip ANSI color codes before checking for Warning prefix
  output_stripped=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
  echo "$output_stripped" | grep "Warning:" >/dev/null
  assertEquals "should include Warning prefix" 0 $?
}

test_warn_prints_to_stderr() {
  output=$(warn "stderr test" 2>&1 1>/dev/null)

  echo "$output" | grep "stderr test" >/dev/null
  assertEquals "should print to stderr" 0 $?
}

test_warn_chomps_input() {
  output=$(warn $'test\n' 2>&1)

  # Should not have trailing newline beyond the one printf adds
  [[ "$output" != *$'\n\n'* ]]
  assertEquals "should chomp trailing newlines from input" 0 $?
}

####################
# tty functions
####################

test_tty_escape_returns_escape_code() {
  # When stdout is not a tty, tty_escape should do nothing
  # We can test the function directly
  if [[ -t 1 ]]; then
    result=$(tty_escape "1")
    [[ "$result" == $'\033[1m' ]]
    assertEquals "should return escape sequence when tty" 0 $?
  else
    result=$(tty_escape "1")
    assertEquals "should return empty when not tty" "" "${result}"
  fi
}

# Load and run shunit2
# shellcheck disable=SC1090
. "${SHUNIT2}"
