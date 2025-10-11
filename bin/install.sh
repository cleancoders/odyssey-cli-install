#!/bin/bash

# We don't need return codes for "$(command)", only stdout is needed.
# Allow `[[ -n "$(command)" ]]`, `func "$(command)"`, pipes, etc.
# shellcheck disable=SC2312

set -u

# Get the directory where the script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "${SCRIPT_DIR}/../lib" && pwd)"

# Source library files
# shellcheck source=../lib/utils.sh
source "${LIB_DIR}/utils.sh"
# shellcheck source=../lib/version.sh
source "${LIB_DIR}/version.sh"
# shellcheck source=../lib/file_permissions.sh
source "${LIB_DIR}/file_permissions.sh"
# shellcheck source=../lib/execution.sh
source "${LIB_DIR}/execution.sh"
# shellcheck source=../lib/tool_validation.sh
source "${LIB_DIR}/tool_validation.sh"
# shellcheck source=../lib/ui.sh
source "${LIB_DIR}/ui.sh"
# shellcheck source=../lib/validation.sh
source "${LIB_DIR}/validation.sh"
# shellcheck source=../lib/setup.sh
source "${LIB_DIR}/setup.sh"

# Global variables (will be set by setup functions)
declare ODYSSEY_PREFIX
# shellcheck disable=SC2034
declare ODYSSEY_REPOSITORY
# shellcheck disable=SC2034
declare ODYSSEY_CACHE
# shellcheck disable=SC2034
declare STAT_PRINTF
# shellcheck disable=SC2034
declare PERMISSION_FORMAT
# shellcheck disable=SC2034
declare CHOWN
# shellcheck disable=SC2034
declare CHGRP
# shellcheck disable=SC2034
declare GROUP
# shellcheck disable=SC2034
declare TOUCH
# shellcheck disable=SC2034
declare INSTALL
declare CHMOD
declare MKDIR
# shellcheck disable=SC2034
declare ODYSSEY_ON_LINUX
declare ODYSSEY_ON_MACOS
# shellcheck disable=SC2034
declare UNAME_MACHINE
# shellcheck disable=SC2034
declare macos_version
declare NONINTERACTIVE
# shellcheck disable=SC2034
declare ADD_PATHS_D

usage() {
  cat <<EOS
Clean Code Odyssey CLI Installer
Usage: [NONINTERACTIVE=1] [CI=1] install.sh [options]
    -h, --help       Display this message.
    NONINTERACTIVE   Install without prompting for user input
    CI               Install in CI mode (e.g. do not prompt for user input)
EOS
  exit "${1:-0}"
}

parse_args() {
  while [[ $# -gt 0 ]]
  do
    case "$1" in
      -h | --help) usage ;;
      *)
        warn "Unrecognized option: '$1'"
        usage 1
        ;;
    esac
  done
}

setup_directories() {
  # Create the bin directory if it doesn't exist
  if ! [[ -d "${ODYSSEY_PREFIX}/bin" ]]
  then
    execute_sudo "${MKDIR[@]}" "${ODYSSEY_PREFIX}/bin"
    execute_sudo "${CHMOD[@]}" "755" "${ODYSSEY_PREFIX}/bin"
  fi
}

maybe_make_existing_file_mutable(){
  if [[ -e "odyssey" ]]
  then
    if [[ -n "${ODYSSEY_ON_MACOS-}" ]]
    then
      execute_sudo "/usr/bin/chflags" "nouchg" "odyssey"
    else
      execute_sudo "$(which chattr)" "-i" "odyssey"
    fi
  fi
}

make_odyssey_file_immutable(){
  if [[ -n "${ODYSSEY_ON_MACOS-}" ]]
  then
    execute_sudo "/usr/bin/chflags" "uchg" "odyssey"
  else
    execute_sudo "$(which chattr)" "+i" "odyssey"
  fi
}

install_odyssey_cli() {
  ohai "Downloading and installing Odyssey CLI..."
  (
    cd "${ODYSSEY_PREFIX}/bin" >/dev/null || exit 1
    maybe_make_existing_file_mutable
    execute_sudo "curl" "-LO" "http://127.0.0.1:8080/bin/odyssey"
    execute_sudo "${CHMOD[@]}" "+x" "odyssey"
    make_odyssey_file_immutable
  ) || exit 1
}

main() {
  # Initial checks
  check_bash_version
  check_environment_conflicts
  parse_args "$@"

  # Setup
  setup_noninteractive_mode
  setup_user
  detect_os
  setup_paths
  setup_sudo_trap

  # Change to /usr to avoid pwd issues
  cd "/usr" || exit 1

  # Validation checks
  check_sudo_access
  check_prefix_permissions
  check_architecture
  check_macos_version

  # Display summary and get confirmation
  display_installation_summary

  if [[ -z "${NONINTERACTIVE-}" ]]
  then
    ring_bell
    wait_for_user
  fi

  # Perform installation
  setup_directories
  setup_repository_and_cache
  maybe_install_babashka
  install_odyssey_cli

  # Display success
  display_success_message
}

# Call main if running as script (not being sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi