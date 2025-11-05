#!/bin/bash

# Odyssey CLI Installer
# This is a generated file. Do not edit directly.
# Source files are in bin/install.sh and lib/

# We don't need return codes for "$(command)", only stdout is needed.
# Allow `[[ -n "$(command)" ]]`, `func "$(command)"`, pipes, etc.
# shellcheck disable=SC2312

set -u

# ============================================================================
# Library Functions (from lib/)
# ============================================================================

# --- lib/utils.sh ---

# Utility functions for Odyssey CLI installer

abort() {
  printf "%s\n" "$@" >&2
  exit 1
}

# string formatters
if [[ -t 1 ]]
then
  tty_escape() { printf "\033[%sm" "$1"; }
else
  tty_escape() { :; }
fi
tty_mkbold() { tty_escape "1;$1"; }
tty_underline="$(tty_escape "4;39")"
tty_blue="$(tty_mkbold 34)"
tty_red="$(tty_mkbold 31)"
tty_bold="$(tty_mkbold 39)"
tty_reset="$(tty_escape 0)"
export tty_underline
export tty_blue
export tty_red
export tty_reset

shell_join() {
  local arg
  printf "%s" "$1"
  shift
  for arg in "$@"
  do
    printf " "
    printf "%s" "${arg// /\ }"
  done
}

chomp() {
  printf "%s" "${1/"$'\n'"/}"
}

ohai() {
  printf "${tty_blue}==>${tty_bold} %s${tty_reset}\n" "$(shell_join "$@")"
}

warn() {
  printf "${tty_red}Warning${tty_reset}: %s\n" "$(chomp "$1")" >&2
}

# --- lib/version.sh ---

# Version comparison functions for Odyssey CLI installer

major_minor() {
  echo "${1%%.*}.$(
    x="${1#*.}"
    if [[ "${x}" == "$1" ]]
    then
      echo "0"
    else
     echo "${x%%.*}"
    fi
  )"
}

version_gt() {
  [[ "${1%.*}" -gt "${2%.*}" ]] || [[ "${1%.*}" -eq "${2%.*}" && "${1#*.}" -gt "${2#*.}" ]]
}

version_ge() {
  [[ "${1%.*}" -gt "${2%.*}" ]] || [[ "${1%.*}" -eq "${2%.*}" && "${1#*.}" -ge "${2#*.}" ]]
}

version_lt() {
  [[ "${1%.*}" -lt "${2%.*}" ]] || [[ "${1%.*}" -eq "${2%.*}" && "${1#*.}" -lt "${2#*.}" ]]
}

# --- lib/file_permissions.sh ---

# File permission functions for Odyssey CLI installer

get_permission() {
  "${STAT_PRINTF[@]}" "${PERMISSION_FORMAT}" "$1"
}

user_only_chmod() {
  [[ -d "$1" ]] && [[ "$(get_permission "$1")" != 75[0145] ]]
}

exists_but_not_writable() {
  [[ -e "$1" ]] && ! [[ -r "$1" && -w "$1" && -x "$1" ]]
}

get_owner() {
  "${STAT_PRINTF[@]}" "%u" "$1"
}

file_not_owned() {
  [[ "$(get_owner "$1")" != "$(id -u)" ]]
}

get_group() {
  "${STAT_PRINTF[@]}" "%g" "$1"
}

file_not_grpowned() {
  [[ " $(id -G "${USER}") " != *" $(get_group "$1") "* ]]
}

# --- lib/execution.sh ---

# Execution functions for Odyssey CLI installer

# Source utils.sh for shell_join function

unset HAVE_SUDO_ACCESS # unset this from the environment

# shellcheck disable=SC2120
have_sudo_access() {
  local -a SUDO=()

  if [[ $# -gt 0 ]];
  then
    SUDO=("$1")
  else
    SUDO=("/usr/bin/sudo")
  fi

  if [[ ! -x ${SUDO[0]} ]]
  then
    return 1
  fi

  if [[ -n "${SUDO_ASKPASS-}" ]]
  then
    SUDO+=("-A")
  elif [[ -n "${NONINTERACTIVE-}" ]]
  then
    SUDO+=("-n")
  fi

  if [[ -z "${HAVE_SUDO_ACCESS-}" ]]
  then
    if [[ -n "${NONINTERACTIVE-}" ]]
    then
      "${SUDO[@]}" -l mkdir &>/dev/null
    else
      "${SUDO[@]}" -v && "${SUDO[@]}" -l mkdir &>/dev/null
    fi
    HAVE_SUDO_ACCESS="$?"
  fi

  if [[ -n "${ODYSSEY_ON_MACOS-}" ]] && [[ "${HAVE_SUDO_ACCESS}" -ne 0 ]]
  then
    abort "Need sudo access on macOS (e.g. the user ${USER} needs to be an Administrator)!"
  fi

  return "${HAVE_SUDO_ACCESS}"
}

execute() {
  if ! "$@"
  then
    abort "$(printf "Failed during: %s" "$(shell_join "$@")")"
  fi
}

execute_sudo() {
  local -a args=("$@")
  if [[ "${EUID:-${UID}}" != "0" ]] && have_sudo_access
  then
    if [[ -n "${SUDO_ASKPASS-}" ]]
    then
      args=("-A" "${args[@]}")
    fi
    ohai "/usr/bin/sudo" "${args[@]}" >&2
    execute "/usr/bin/sudo" "${args[@]}"
  else
    ohai "${args[@]}" >&2
    execute "${args[@]}"
  fi
}

# Helper: Extract filename from curl arguments based on -o, -O, or -LO flags
parse_curl_output_file() {
  local -a curl_args=("$@")
  local output_file=""
  local i=0
  local last_arg_idx=$((${#curl_args[@]} - 1))

  while [[ $i -lt ${#curl_args[@]} ]]; do
    if [[ "${curl_args[$i]}" == "-o" ]]; then
      output_file="${curl_args[$((i+1))]}"
      break
    elif [[ "${curl_args[$i]}" == "-O" ]]; then
      # Extract filename from URL (last argument)
      local url="${curl_args[$last_arg_idx]}"
      output_file="${url##*/}"
      break
    elif [[ "${curl_args[$i]}" == "-LO" ]]; then
      # -LO is shorthand for -L -O
      local url="${curl_args[$last_arg_idx]}"
      output_file="${url##*/}"
      break
    fi
    ((i++))
  done

  echo "${output_file}"
}

# Helper: Extract HTTP status code from curl response
extract_http_status() {
  local response="$1"
  echo "${response}" | tail -n 1
}

# Helper: Extract response body from curl response (everything except last line)
extract_response_body() {
  local response="$1"
  echo "${response}" | sed '$d'
}

# Helper: Write content to file or stdout (with appropriate permissions)
write_curl_output() {
  local body="$1"
  local output_file="$2"
  local needs_sudo="$3"

  if [[ -n "${output_file}" ]]; then
    if [[ "${needs_sudo}" == "true" ]]; then
      # Use execute_sudo to write with elevated permissions
      echo "${body}" | execute_sudo tee "${output_file}" >/dev/null
    else
      echo "${body}" > "${output_file}"
    fi
  else
    echo "${body}"
  fi
}

# Helper: Validate HTTP status code is 2xx
validate_http_status() {
  local http_code="$1"
  shift
  local -a curl_args=("$@")

  if [[ "${http_code}" =~ ^2[0-9][0-9]$ ]]; then
    return 0
  else
    abort "$(printf "HTTP request failed with status code %s during: %s" "${http_code}" "$(shell_join curl "${curl_args[@]}")")"
  fi
}

execute_curl() {
  local -a curl_args=("$@")
  local http_code
  local response
  local body
  local output_file
  local needs_sudo="false"

  # Determine if we need sudo for file operations
  if [[ "${EUID:-${UID}}" != "0" ]] && have_sudo_access; then
    needs_sudo="true"
  fi

  output_file=$(parse_curl_output_file "${curl_args[@]}")

  # Build curl arguments with HTTP status code capture
  # -w '\n%{http_code}' writes a newline followed by HTTP status code at the end
  # -S shows errors
  local -a full_curl_args=("curl" "-w" "\n%{http_code}" "-S" "${curl_args[@]}")

  # If curl is writing to a file directly (-o, -O, -LO), capture only stderr+status
  # Otherwise capture stdout (body + status)
  if [[ -n "${output_file}" ]]; then
    response=$(execute_sudo "${full_curl_args[@]}")
    http_code=$(echo "${response}" | tail -n 1)
  else
    # curl writes to stdout, we need to capture body and status code
    response=$(execute_sudo "${full_curl_args[@]}")
    http_code=$(extract_http_status "${response}")
    body=$(extract_response_body "${response}")
    write_curl_output "${body}" "" "${needs_sudo}"
  fi

  validate_http_status "${http_code}" "${curl_args[@]}"
}

# --- lib/tool_validation.sh ---

# Validation functions for Odyssey CLI installer

# Source version.sh for version comparison functions

test_curl() {
  if [[ ! -x "$1" ]]
  then
    return 1
  fi

  if [[ "$1" == "/snap/bin/curl" ]]
  then
    warn "Ignoring $1 (curl snap is too restricted)"
    return 1
  fi

  local curl_version_output curl_name_and_version
  curl_version_output="$("$1" --version 2>/dev/null)"
  curl_name_and_version="${curl_version_output%% (*}"
  version_ge "$(major_minor "${curl_name_and_version##* }")" "$(major_minor "${REQUIRED_CURL_VERSION}")"
}

test_git() {
  if [[ ! -x "$1" ]]
  then
    return 1
  fi

  local git_version_output
  git_version_output="$("$1" --version 2>/dev/null)"
  if [[ "${git_version_output}" =~ "git version "([^ ]*).* ]]
  then
    version_ge "$(major_minor "${BASH_REMATCH[1]}")" "$(major_minor "${REQUIRED_GIT_VERSION}")"
  else
    abort "Unexpected Git version: '${git_version_output}'!"
  fi
}

REQUIRED_BB_VERSION="1.12.193"
test_bb() {
  if [[ ! -x "$1" ]]
  then
    return 1
  fi

  local bb_version_output bb_name_and_version bb_version
  bb_version_output="$("$1" --version 2>/dev/null)"
  bb_name_and_version="${bb_version_output%% (*}"
  bb_version="${bb_name_and_version##* }"
  # Strip leading 'v' if present (babashka outputs "babashka v1.12.193")
  bb_version="${bb_version#v}"
  version_ge "$(major_minor "${bb_version}")" "$(major_minor "${REQUIRED_BB_VERSION}")"
}

# Search for the given executable in PATH (avoids a dependency on the `which` command)
which() {
  # Alias to Bash built-in command `type -P`
  type -P "$@"
}

# Search PATH for the specified program that satisfies Odyssey requirements
# function which is set above
# shellcheck disable=SC2230
find_tool() {
  if [[ $# -ne 1 ]]
  then
    return 1
  fi

  local executable
  while read -r executable
  do
    if [[ "${executable}" != /* ]]
    then
      warn "Ignoring ${executable} (relative paths don't work)"
    elif "test_$1" "${executable}"
    then
      echo "${executable}"
      break
    fi
  done < <(which -a "$1")
}

install_babashka() {
   cd /usr/local || exit 1
   execute_curl "-sSLO" "https://raw.githubusercontent.com/babashka/babashka/master/install"
   execute_sudo "${CHMOD[@]}" "+x" install
   execute_sudo "./install" "--static"
}

maybe_install_babashka() {
  if ! command -v bb >/dev/null
  then
    ohai "Babashka not found, installing"
    install_babashka
  else
    USABLE_BB="$(find_tool bb)"
    if [[ -z "${USABLE_BB}" ]]
    then
      warn "Outdated Babashka found, updating"
      install_babashka
    else
      ohai "Found Babashka: ${USABLE_BB}"
    fi
  fi
}

# --- lib/ui.sh ---

# UI/Terminal interaction functions

getc() {
  local save_state
  save_state="$(/bin/stty -g)"
  /bin/stty raw -echo
  IFS='' read -r -n 1 -d '' "$@"
  /bin/stty "${save_state}"
}

ring_bell() {
  # Use the shell's audible bell.
  if [[ -t 1 ]]
  then
    printf "\a"
  fi
}

wait_for_user() {
  local c
  echo
  echo "Press ${tty_bold}RETURN${tty_reset}/${tty_bold}ENTER${tty_reset} to continue or any other key to abort:"
  getc c
  # we test for \r and \n because some stuff does \r instead
  if ! [[ "${c}" == $'\r' || "${c}" == $'\n' ]]
  then
    exit 1
  fi
}

display_installation_summary() {
  ohai "This script will install:"
  echo "${ODYSSEY_PREFIX}/bin/odyssey"
  echo "${ODYSSEY_REPOSITORY}"
  if [[ -n "${ADD_PATHS_D-}" ]]
  then
    echo "/etc/paths.d/odyssey"
  fi
  ohai "If not already installed, this script will install Babashka for the current user"
}

display_success_message() {
  ohai "Installation successful!"
  echo

  ring_bell

  cat <<EOS
- Run ${tty_bold}odyssey config${tty_reset} to set your run command and get started!
EOS
}

# --- lib/validation.sh ---

# Environment and system validation functions

check_run_command_as_root() {
  [[ "${EUID:-${UID}}" == "0" ]] || return

  # Allow Azure Pipelines/GitHub Actions/Docker/Concourse/Kubernetes to do everything as root (as it's normal there)
  [[ -f /.dockerenv ]] && return
  [[ -f /run/.containerenv ]] && return
  [[ -f /proc/1/cgroup ]] && grep -E "azpl_job|actions_job|docker|garden|kubepods" -q /proc/1/cgroup && return

  abort "Don't run this as root!"
}

check_bash_version() {
  # Fail fast with a concise message when not using bash
  # Single brackets are needed here for POSIX compatibility
  # shellcheck disable=SC2292
  if [ -z "${BASH_VERSION:-}" ]
  then
    printf "%s\n" "Bash is required to interpret this script." >&2
    exit 1
  fi
}

check_environment_conflicts() {
  # Check if script is run with force-interactive mode in CI
  if [[ -n "${CI-}" && -n "${INTERACTIVE-}" ]]
  then
    abort "Cannot run force-interactive mode in CI."
  fi

  # Check if both `INTERACTIVE` and `NONINTERACTIVE` are set
  # Always use single-quoted strings with `exp` expressions
  # shellcheck disable=SC2016
  if [[ -n "${INTERACTIVE-}" && -n "${NONINTERACTIVE-}" ]]
  then
    abort 'Both `$INTERACTIVE` and `$NONINTERACTIVE` are set. Please unset at least one variable and try again.'
  fi

  # Check if script is run in POSIX mode
  if [[ -n "${POSIXLY_CORRECT+1}" ]]
  then
    abort 'Bash must not run in POSIX mode. Please unset POSIXLY_CORRECT and try again.'
  fi
}

check_prefix_permissions() {
  if [[ -d "${ODYSSEY_PREFIX}" && ! -x "${ODYSSEY_PREFIX}" ]]
  then
    abort "The Odyssey prefix ${tty_underline}${ODYSSEY_PREFIX}${tty_reset} exists but is not searchable.
If this is not intentional, please restore the default permissions and
try running the installer again:
    sudo chmod 775 ${ODYSSEY_PREFIX}"
  fi
}

check_architecture() {
  if [[ -n "${ODYSSEY_ON_MACOS-}" ]]
  then
    # On macOS, support 64-bit Intel and ARM
    if [[ "${UNAME_MACHINE}" != "arm64" ]] && [[ "${UNAME_MACHINE}" != "x86_64" ]]
    then
      abort "Odyssey is only supported on Intel and ARM processors!"
    fi
  else
    if [[ "${UNAME_MACHINE}" != "x86_64" ]] && [[ "${UNAME_MACHINE}" != "aarch64" ]]
    then
      abort "Odyssey on Linux is only supported on Intel x86_64 and ARM64 processors!"
    fi
  fi
}

check_sudo_access() {
  # shellcheck disable=SC2016
  ohai "Checking for \`sudo\` access (which may request your password)..."

  if [[ -n "${ODYSSEY_ON_MACOS-}" ]]
  then
    [[ "${EUID:-${UID}}" == "0" ]] || have_sudo_access
  elif ! [[ -w "${ODYSSEY_PREFIX}" ]] &&
       ! [[ -w "/home/odyssey" ]] &&
       ! [[ -w "/home" ]] &&
       ! have_sudo_access
  then
    abort "Insufficient permissions to install Odyssey CLI to \"${ODYSSEY_PREFIX}\" (the default prefix)."
  fi

  check_run_command_as_root
}

MACOS_NEWEST_UNSUPPORTED="27.0"
MACOS_OLDEST_SUPPORTED="14.0"
check_macos_version() {
  if [[ -n "${ODYSSEY_ON_MACOS-}" ]]
  then
    macos_version="$(major_minor "$(/usr/bin/sw_vers -productVersion)")"
    if version_lt "${macos_version}" "10.7"
    then
      abort "Your Mac OS X version is too old."
    elif version_lt "${macos_version}" "10.11"
    then
      abort "Your OS X version is too old."
    elif version_ge "${macos_version}" "${MACOS_NEWEST_UNSUPPORTED}" ||
         version_lt "${macos_version}" "${MACOS_OLDEST_SUPPORTED}"
    then
      who="We"
      what=""
      if version_ge "${macos_version}" "${MACOS_NEWEST_UNSUPPORTED}"
      then
        what="pre-release version"
      else
        who+=" (and Apple)"
        what="old version"
      fi
      ohai "You are using macOS ${macos_version}."
      ohai "${who} do not provide support for this ${what}."

      printf "This installation may not succeed.\nYou are responsible for resolving any issues you experience while you are running this %s.\n" "$what" | tr -d "\\"
    fi
  fi
}

# --- lib/setup.sh ---

# System setup and configuration functions

setup_noninteractive_mode() {
  # Check if script is run non-interactively (e.g. CI)
  # If it is run non-interactively we should not prompt for passwords.
  # Always use single-quoted strings with `exp` expressions
  # shellcheck disable=SC2016
  if [[ -z "${NONINTERACTIVE-}" ]]
  then
    if [[ -n "${CI-}" ]]
    then
      warn 'Running in non-interactive mode because `$CI` is set.'
      NONINTERACTIVE=1
    elif [[ ! -t 0 ]]
    then
      if [[ -z "${INTERACTIVE-}" ]]
      then
        warn 'Running in non-interactive mode because `stdin` is not a TTY.'
        NONINTERACTIVE=1
      else
        warn 'Running in interactive mode despite `stdin` not being a TTY because `$INTERACTIVE` is set.'
      fi
    fi
  else
    ohai 'Running in non-interactive mode because `$NONINTERACTIVE` is set.'
  fi
}

setup_user() {
  # USER isn't always set so provide a fall back for the installer and subprocesses.
  if [[ -z "${USER-}" ]]
  then
    USER="$(chomp "$(id -un)")"
    export USER
  fi
}

# shellcheck disable=SC2120
detect_os() {
  # First check OS.
  OS="$(uname)"

  if [[ $# -gt 0 ]];
  then
    OS="$1"
  fi

  if [[ "${OS}" == "Linux" ]]
  then
    ODYSSEY_ON_LINUX=1
  elif [[ "${OS}" == "Darwin" ]]
  then
    ODYSSEY_ON_MACOS=1
  else
    abort "Odyssey CLI is only supported on macOS and Linux."
  fi
}

# shellcheck disable=SC2034
setup_paths() {
  UNAME_MACHINE="$(/usr/bin/uname -m)"
  ODYSSEY_PREFIX="/usr/local"
  ODYSSEY_REPOSITORY="${ODYSSEY_PREFIX}/odyssey"
  STAT_PRINTF=("/usr/bin/stat" "-f")
  PERMISSION_FORMAT="%A"
  CHOWN=("/usr/sbin/chown")
  CHGRP=("/usr/bin/chgrp")
  GROUP="admin"
  TOUCH=("/usr/bin/touch")
  INSTALL=("/usr/bin/install" -d -o "root" -g "wheel" -m "0755")
  CHMOD=("/bin/chmod")
  MKDIR=("/bin/mkdir" "-p")
}

setup_sudo_trap() {
  # Invalidate sudo timestamp before exiting (if it wasn't active before).
  if [[ -x /usr/bin/sudo ]] && ! /usr/bin/sudo -n -v 2>/dev/null
  then
    trap '/usr/bin/sudo -k' EXIT
  fi
}

# ============================================================================
# Main Installation Script (from bin/install.sh)
# ============================================================================


# Global variables (will be set by setup functions)
declare ODYSSEY_PREFIX
# shellcheck disable=SC2034
declare ODYSSEY_REPOSITORY
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
    execute_curl "-LO" "https://d154yre1ylyo3c.cloudfront.net/bin/odyssey"
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
  maybe_install_babashka
  install_odyssey_cli

  # Display success
  display_success_message
}


# ============================================================================
# Execute main function with all arguments
# ============================================================================

main "$@"
