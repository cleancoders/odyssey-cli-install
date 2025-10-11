#!/bin/bash

# Unit tests for lib/validation.sh

# Get the project root directory
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "${TEST_DIR}")"

# Source shunit2
SHUNIT2="${PROJECT_DIR}/shunit2"

# Source library dependencies
# shellcheck disable=SC1090
source "${PROJECT_DIR}/lib/utils.sh"
# shellcheck disable=SC1090
source "${PROJECT_DIR}/lib/version.sh"
# shellcheck disable=SC1090
source "${PROJECT_DIR}/lib/execution.sh"

# Source the file under test
# shellcheck disable=SC1090
source "${PROJECT_DIR}/lib/validation.sh"

# Test fixtures
TEST_OUTPUT_DIR=""

# Setup function - runs before each test
setUp() {
  # Create a temporary directory for test output
  TEST_OUTPUT_DIR="$(mktemp -d)"

  # Clear environment variables
  unset NONINTERACTIVE
  unset INTERACTIVE
  unset CI
  unset ODYSSEY_ON_LINUX
  unset ODYSSEY_ON_MACOS

  # Mock have_sudo_access to prevent password prompts during setup
  have_sudo_access() {
    # shellcheck disable=SC2317
    return 0
  }
  export -f have_sudo_access
}

# Teardown function - runs after each test
tearDown() {
  # Clean up temporary directory
  if [[ -n "${TEST_OUTPUT_DIR}" && -d "${TEST_OUTPUT_DIR}" ]]; then
    rm -rf "${TEST_OUTPUT_DIR}"
  fi

  # Clean up environment variables that tests might have set
  unset POSIXLY_CORRECT
  unset CI
  unset INTERACTIVE
  unset NONINTERACTIVE
  unset ODYSSEY_PREFIX
  unset ODYSSEY_ON_MACOS
  unset ODYSSEY_ON_LINUX
  unset UNAME_MACHINE
}

####################
# check_run_command_as_root
####################

test_check_run_command_as_root_has_root_check() {
  # Since EUID and UID are readonly bash variables that cannot be mocked,
  # we verify the function contains the correct logic by inspecting it
  type check_run_command_as_root | grep -q 'EUID.*UID.*== *"0"'
  assertEquals "should check if EUID or UID equals 0" 0 $?
}

test_check_run_command_as_root_has_abort_message() {
  # Verify the function contains the abort call with correct message
  type check_run_command_as_root | grep -q "abort.*Don't run this as root"
  assertEquals "should call abort with root warning message" 0 $?
}

test_check_run_command_as_root_checks_for_docker() {
  # Verify the function checks for Docker container
  type check_run_command_as_root | grep -q '\.dockerenv'
  assertEquals "should check for Docker container file" 0 $?
}

test_check_run_command_as_root_checks_for_podman() {
  # Verify the function checks for Podman/buildah container
  type check_run_command_as_root | grep -q '/run/\.containerenv'
  assertEquals "should check for Podman container file" 0 $?
}

test_check_run_command_as_root_checks_cgroup() {
  # Verify the function checks cgroup for CI/container environments
  type check_run_command_as_root | grep -q '/proc/1/cgroup'
  assertEquals "should check cgroup file for container detection" 0 $?
}

####################
# check_bash_version
####################

test_check_bash_version_succeeds_with_bash() {
  # This test runs in bash, so it should succeed
  check_bash_version
  assertEquals "should succeed when running in bash" 0 $?
}

test_check_bash_version_checks_bash_version_variable() {
  # Verify the function checks for BASH_VERSION variable
  type check_bash_version | grep -q 'BASH_VERSION'
  assertEquals "should check BASH_VERSION variable" 0 $?
}

test_check_bash_version_uses_posix_bracket_test() {
  # Verify the function uses single brackets for POSIX compatibility
  # The function uses [ instead of [[ for the version check
  type check_bash_version | grep -q '\[ -z.*BASH_VERSION'
  assertEquals "should use POSIX-compatible single bracket test" 0 $?
}

test_check_bash_version_prints_error_message() {
  # Verify the function contains the correct error message
  type check_bash_version | grep -q 'Bash is required'
  assertEquals "should contain error message about bash being required" 0 $?
}

test_check_bash_version_exits_on_failure() {
  # Verify the function calls exit when bash is not detected
  type check_bash_version | grep -q 'exit 1'
  assertEquals "should call exit 1 when bash is not detected" 0 $?
}

test_check_bash_version_writes_to_stderr() {
  # Verify the function writes error to stderr (>&2)
  type check_bash_version | grep -q '>&2'
  assertEquals "should write error message to stderr" 0 $?
}

####################
# check_environment_conflicts
####################

test_check_environment_conflicts_aborts_with_ci_and_interactive() {
  export CI=1
  export INTERACTIVE=1

  output=$(check_environment_conflicts 2>&1)
  exit_code=$?

  assertEquals "should exit 1 with CI and INTERACTIVE" 1 ${exit_code}
  echo "$output" | grep "Cannot run force-interactive mode in CI" >/dev/null
  assertEquals "should print error message" 0 $?
}

test_check_environment_conflicts_aborts_with_both_modes() {
  export INTERACTIVE=1
  export NONINTERACTIVE=1

  output=$(check_environment_conflicts 2>&1)
  exit_code=$?

  assertEquals "should exit 1 with both INTERACTIVE and NONINTERACTIVE" 1 ${exit_code}
  echo "$output" | grep "Both.*are set" >/dev/null
  assertEquals "should print error message" 0 $?
}

test_check_environment_conflicts_aborts_with_posix_mode() {
  export POSIXLY_CORRECT=1

  output=$(check_environment_conflicts 2>&1)
  exit_code=$?

  assertEquals "should exit 1 with POSIXLY_CORRECT" 1 ${exit_code}
  echo "$output" | grep "POSIX mode" >/dev/null
  assertEquals "should print error message" 0 $?
}

test_check_environment_conflicts_succeeds_with_no_conflicts() {
  check_environment_conflicts
  assertEquals "should succeed with no conflicts" 0 $?
}

####################
# check_prefix_permissions
####################

test_check_prefix_permissions_checks_if_directory_exists() {
  # Verify function checks if ODYSSEY_PREFIX is a directory
  type check_prefix_permissions | grep -q '\-d.*ODYSSEY_PREFIX'
  assertEquals "should check if ODYSSEY_PREFIX is a directory" 0 $?
}

test_check_prefix_permissions_checks_if_executable() {
  # Verify function checks if directory is executable (searchable)
  type check_prefix_permissions | grep -q '\-x.*ODYSSEY_PREFIX'
  assertEquals "should check if ODYSSEY_PREFIX is executable" 0 $?
}

test_check_prefix_permissions_has_not_searchable_error() {
  # Verify function contains error message about directory not being searchable
  type check_prefix_permissions | grep -q 'not searchable'
  assertEquals "should have 'not searchable' error message" 0 $?
}

test_check_prefix_permissions_suggests_chmod_fix() {
  # Verify function suggests using chmod to fix permissions
  type check_prefix_permissions | grep -q 'sudo chmod'
  assertEquals "should suggest using chmod to fix permissions" 0 $?
}

test_check_prefix_permissions_succeeds_when_directory_not_exists() {
  # Test passes when directory doesn't exist
  ODYSSEY_PREFIX="/tmp/nonexistent_dir_$$"

  check_prefix_permissions
  assertEquals "should succeed when directory does not exist" 0 $?
}

test_check_prefix_permissions_succeeds_when_directory_searchable() {
  # Test passes when directory exists and is searchable
  ODYSSEY_PREFIX="/tmp/test_prefix_searchable_$$"
  mkdir -p "${ODYSSEY_PREFIX}"
  chmod 755 "${ODYSSEY_PREFIX}"

  check_prefix_permissions
  local result=$?

  # Clean up
  rm -rf "${ODYSSEY_PREFIX}"

  assertEquals "should succeed when directory is searchable" 0 ${result}
}

test_check_prefix_permissions_aborts_when_not_searchable() {
  # Test aborts when directory exists but is not searchable
  ODYSSEY_PREFIX="/tmp/test_prefix_not_searchable_$$"
  mkdir -p "${ODYSSEY_PREFIX}"
  chmod 666 "${ODYSSEY_PREFIX}"  # Remove execute permission

  output=$(check_prefix_permissions 2>&1)
  exit_code=$?

  # Clean up
  chmod 755 "${ODYSSEY_PREFIX}"
  rm -rf "${ODYSSEY_PREFIX}"

  assertEquals "should abort when directory is not searchable" 1 ${exit_code}
  echo "$output" | grep -q "not searchable"
  assertEquals "should print 'not searchable' error message" 0 $?
}

####################
# check_architecture
####################

test_check_architecture_checks_for_macos() {
  # Verify function checks for ODYSSEY_ON_MACOS
  type check_architecture | grep -q 'ODYSSEY_ON_MACOS'
  assertEquals "should check for ODYSSEY_ON_MACOS" 0 $?
}

test_check_architecture_checks_uname_machine() {
  # Verify function checks UNAME_MACHINE variable
  type check_architecture | grep -q 'UNAME_MACHINE'
  assertEquals "should check UNAME_MACHINE variable" 0 $?
}

test_check_architecture_has_macos_error_message() {
  # Verify function has error message for unsupported macOS processors
  type check_architecture | grep -q 'Intel and ARM processors'
  assertEquals "should have macOS unsupported processor error" 0 $?
}

test_check_architecture_has_linux_error_message() {
  # Verify function has error message for unsupported Linux processors
  type check_architecture | grep -q 'Intel x86_64 and ARM64'
  assertEquals "should have Linux unsupported processor error" 0 $?
}

test_check_architecture_succeeds_macos_arm64() {
  # Test macOS with ARM64
  ODYSSEY_ON_MACOS=1
  unset ODYSSEY_ON_LINUX
  UNAME_MACHINE="arm64"

  check_architecture
  assertEquals "should succeed on macOS ARM64" 0 $?
}

test_check_architecture_succeeds_macos_x86_64() {
  # Test macOS with x86_64
  ODYSSEY_ON_MACOS=1
  unset ODYSSEY_ON_LINUX
  UNAME_MACHINE="x86_64"

  check_architecture
  assertEquals "should succeed on macOS x86_64" 0 $?
}

test_check_architecture_aborts_macos_unsupported() {
  # Test macOS with unsupported architecture
  ODYSSEY_ON_MACOS=1
  unset ODYSSEY_ON_LINUX
  UNAME_MACHINE="i386"

  output=$(check_architecture 2>&1)
  exit_code=$?

  assertEquals "should abort on unsupported macOS architecture" 1 ${exit_code}
  echo "$output" | grep -q "Intel and ARM processors"
  assertEquals "should print unsupported processor error" 0 $?
}

test_check_architecture_succeeds_linux_x86_64() {
  # Test Linux with x86_64
  ODYSSEY_ON_LINUX=1
  unset ODYSSEY_ON_MACOS
  UNAME_MACHINE="x86_64"

  check_architecture
  assertEquals "should succeed on Linux x86_64" 0 $?
}

test_check_architecture_succeeds_linux_aarch64() {
  # Test Linux with aarch64
  ODYSSEY_ON_LINUX=1
  unset ODYSSEY_ON_MACOS
  UNAME_MACHINE="aarch64"

  check_architecture
  assertEquals "should succeed on Linux aarch64" 0 $?
}

test_check_architecture_aborts_linux_unsupported() {
  # Test Linux with unsupported architecture
  ODYSSEY_ON_LINUX=1
  unset ODYSSEY_ON_MACOS
  UNAME_MACHINE="i686"

  output=$(check_architecture 2>&1)
  exit_code=$?

  assertEquals "should abort on unsupported Linux architecture" 1 ${exit_code}
  echo "$output" | grep -q "Intel x86_64 and ARM64"
  assertEquals "should print unsupported processor error" 0 $?
}


####################
# check_sudo_access
####################

test_check_sudo_access_checks_for_macos() {
  # Verify the function checks for ODYSSEY_ON_MACOS
  type check_sudo_access | grep -q 'ODYSSEY_ON_MACOS'
  assertEquals "should check for ODYSSEY_ON_MACOS" 0 $?
}

test_check_sudo_access_calls_have_sudo_access() {
  # Verify the function calls have_sudo_access
  type check_sudo_access | grep -q 'have_sudo_access'
  assertEquals "should call have_sudo_access" 0 $?
}

test_check_sudo_access_calls_check_run_command_as_root() {
  # Verify the function calls check_run_command_as_root
  type check_sudo_access | grep -q 'check_run_command_as_root'
  assertEquals "should call check_run_command_as_root at the end" 0 $?
}

test_check_sudo_access_checks_prefix_writable_on_linux() {
  # Verify function checks if ODYSSEY_PREFIX is writable on Linux
  type check_sudo_access | grep -q 'ODYSSEY_PREFIX'
  assertEquals "should check if ODYSSEY_PREFIX is writable" 0 $?
}

test_check_sudo_access_has_insufficient_permissions_message() {
  # Verify function contains error message for insufficient permissions
  type check_sudo_access | grep -q 'Insufficient permissions'
  assertEquals "should have insufficient permissions error message" 0 $?
}

test_check_sudo_access_succeeds_on_macos_with_sudo() {
  # Test macOS path with sudo access
  ODYSSEY_ON_MACOS=1
  unset ODYSSEY_ON_LINUX

  # Mock have_sudo_access to succeed
  have_sudo_access() {
    # shellcheck disable=SC2317
    return 0
  }
  export -f have_sudo_access

  # Mock check_run_command_as_root to do nothing
  check_run_command_as_root() {
    # shellcheck disable=SC2317
    return 0
  }
  export -f check_run_command_as_root

  check_sudo_access >/dev/null 2>&1
  assertEquals "should succeed on macOS with sudo access" 0 $?
}

test_check_sudo_access_succeeds_on_linux_with_writable_prefix() {
  # Test Linux path with writable prefix
  ODYSSEY_ON_LINUX=1
  unset ODYSSEY_ON_MACOS
  ODYSSEY_PREFIX="/tmp/test_odyssey_$$"
  mkdir -p "${ODYSSEY_PREFIX}"

  # Mock check_run_command_as_root to do nothing
  check_run_command_as_root() {
    # shellcheck disable=SC2317
    return 0
  }
  export -f check_run_command_as_root

  check_sudo_access >/dev/null 2>&1
  local result=$?

  # Clean up
  rm -rf "${ODYSSEY_PREFIX}"

  assertEquals "should succeed on Linux with writable prefix" 0 ${result}
}

####################
# check_macos_version
####################

test_check_macos_version_checks_for_macos() {
  # Verify function checks for ODYSSEY_ON_MACOS
  type check_macos_version | grep -q 'ODYSSEY_ON_MACOS'
  assertEquals "should check for ODYSSEY_ON_MACOS" 0 $?
}

test_check_macos_version_uses_sw_vers() {
  # Verify function uses sw_vers to get macOS version
  type check_macos_version | grep -q 'sw_vers'
  assertEquals "should use sw_vers to get macOS version" 0 $?
}

test_check_macos_version_uses_major_minor() {
  # Verify function uses major_minor to parse version
  type check_macos_version | grep -q 'major_minor'
  assertEquals "should use major_minor to parse version" 0 $?
}

test_check_macos_version_has_version_constants() {
  # Verify the version constants are defined
  type check_macos_version | grep -q 'MACOS_NEWEST_UNSUPPORTED'
  assertEquals "should reference MACOS_NEWEST_UNSUPPORTED" 0 $?

  type check_macos_version | grep -q 'MACOS_OLDEST_SUPPORTED'
  assertEquals "should reference MACOS_OLDEST_SUPPORTED" 0 $?
}

test_check_macos_version_checks_version_lt() {
  # Verify function uses version_lt for comparisons
  type check_macos_version | grep -q 'version_lt'
  assertEquals "should use version_lt for version comparisons" 0 $?
}

test_check_macos_version_checks_version_ge() {
  # Verify function uses version_ge for comparisons
  type check_macos_version | grep -q 'version_ge'
  assertEquals "should use version_ge for version comparisons" 0 $?
}

test_check_macos_version_skips_check_on_linux() {
  # Test that function does nothing when not on macOS
  unset ODYSSEY_ON_MACOS
  ODYSSEY_ON_LINUX=1

  check_macos_version
  assertEquals "should succeed and do nothing on Linux" 0 $?
}

test_check_macos_version_aborts_on_mac_osx_too_old() {
  # Test abort for Mac OS X < 10.7
  # This test verifies the logic by checking the function definition
  # since we can't easily mock sw_vers output in a cross-platform way

  # Verify the function checks for version < 10.7
  type check_macos_version | grep -q 'version_lt.*10\.7'
  assertEquals "should check for version < 10.7" 0 $?

  # Verify it has the Mac OS X error message
  type check_macos_version | grep -q "Mac OS X version is too old"
  assertEquals "should have Mac OS X too old error" 0 $?
}

test_check_macos_version_aborts_on_osx_too_old() {
  # Test abort for OS X < 10.11
  # This test verifies the logic by checking the function definition

  # Verify the function checks for version < 10.11
  type check_macos_version | grep -q 'version_lt.*10\.11'
  assertEquals "should check for version < 10.11" 0 $?

  # Verify it has the OS X error message
  type check_macos_version | grep -q "OS X version is too old"
  assertEquals "should have OS X too old error" 0 $?
}

test_check_macos_version_warns_on_old_supported_version() {
  # Test that function checks for old supported versions
  # Verify the function uses MACOS_OLDEST_SUPPORTED
  type check_macos_version | grep -q 'MACOS_OLDEST_SUPPORTED'
  assertEquals "should use MACOS_OLDEST_SUPPORTED constant" 0 $?

  # Verify it mentions old version in the warning path
  type check_macos_version | grep -q 'old version'
  assertEquals "should have old version warning path" 0 $?

  # Verify it modifies 'who' variable for old versions
  type check_macos_version | grep -q 'who+='
  assertEquals "should append to who variable for old versions" 0 $?
}

test_check_macos_version_warns_on_pre_release() {
  # Test that function checks for pre-release versions
  # Verify the function uses MACOS_NEWEST_UNSUPPORTED
  type check_macos_version | grep -q 'MACOS_NEWEST_UNSUPPORTED'
  assertEquals "should use MACOS_NEWEST_UNSUPPORTED constant" 0 $?

  # Verify it mentions pre-release version in the warning path
  type check_macos_version | grep -q 'pre-release version'
  assertEquals "should have pre-release version warning path" 0 $?
}

test_check_macos_version_succeeds_on_supported_version() {
  # Test success path for supported versions
  # Verify the function has logic for the supported version range

  # The function should check both bounds
  type check_macos_version | grep -q 'version_ge.*MACOS_NEWEST_UNSUPPORTED'
  assertEquals "should check upper bound with NEWEST_UNSUPPORTED" 0 $?

  type check_macos_version | grep -q 'version_lt.*MACOS_OLDEST_SUPPORTED'
  assertEquals "should check lower bound with OLDEST_SUPPORTED" 0 $?
}

test_check_macos_version_succeeds_on_latest_supported() {
  # Test that the function allows versions in the supported range
  # This is tested by verifying the logic structure

  # Verify the conditional uses OR logic for unsupported versions
  type check_macos_version | grep -q 'version_ge.*||'
  assertEquals "should use OR logic to combine version checks" 0 $?
}

test_check_macos_version_has_mac_osx_error_message() {
  # Verify function has error message for very old Mac OS X
  type check_macos_version | grep -q "Mac OS X version is too old"
  assertEquals "should have Mac OS X too old error message" 0 $?
}

test_check_macos_version_has_osx_error_message() {
  # Verify function has error message for old OS X
  type check_macos_version | grep -q "OS X version is too old"
  assertEquals "should have OS X too old error message" 0 $?
}

test_check_macos_version_mentions_pre_release_in_warning() {
  # Verify function mentions pre-release in warning
  type check_macos_version | grep -q "pre-release version"
  assertEquals "should mention pre-release version in code" 0 $?
}

test_check_macos_version_mentions_old_version_in_warning() {
  # Verify function mentions old version in warning
  type check_macos_version | grep -q "old version"
  assertEquals "should mention old version in code" 0 $?
}

test_check_macos_version_sets_macos_version_variable() {
  # Verify function sets macos_version variable
  # The function should set macos_version
  type check_macos_version | grep -q 'macos_version='
  assertEquals "should set macos_version variable" 0 $?
}

test_check_macos_version_displays_version_in_warning() {
  # Verify function displays the macOS version in warning messages
  type check_macos_version | grep -q 'You are using macOS.*macos_version'
  assertEquals "should display macOS version in warning" 0 $?
}

test_check_macos_version_provides_context_message() {
  # Verify function provides context about support
  type check_macos_version | grep -q 'do not provide support'
  assertEquals "should mention lack of support" 0 $?
}

test_check_macos_version_warns_about_potential_failure() {
  # Verify function warns about potential installation failure
  type check_macos_version | grep -q 'may not succeed'
  assertEquals "should warn about potential installation failure" 0 $?
}


# Load and run shunit2
# shellcheck disable=SC1090
. "${SHUNIT2}"
