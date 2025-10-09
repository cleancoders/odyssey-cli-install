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
# shellcheck source=../lib/validation.sh
source "${LIB_DIR}/validation.sh"

# Global variables (will be set by setup functions)
declare ODYSSEY_PREFIX
declare ODYSSEY_REPOSITORY
declare ODYSSEY_CACHE
declare STAT_PRINTF
declare PERMISSION_FORMAT
declare CHOWN
declare CHGRP
declare GROUP
declare TOUCH
declare INSTALL
declare CHMOD
declare MKDIR
declare ODYSSEY_ON_LINUX
declare ODYSSEY_ON_MACOS
declare UNAME_MACHINE
declare macos_version
declare NONINTERACTIVE
declare ADD_PATHS_D

# Constants
ODYSSEY_DEFAULT_GIT_REMOTE="https://github.com/cleancoders/odyssey-cli"
MACOS_NEWEST_UNSUPPORTED="27.0"
MACOS_OLDEST_SUPPORTED="14.0"
REQUIRED_BB_VERSION=1.12.193
REQUIRED_CURL_VERSION=7.41.0
REQUIRED_GIT_VERSION=2.7.0

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

# TODO do we need all these? also, needs better testing
setup_paths() {
  # Required installation paths.
  if [[ -n "${ODYSSEY_ON_MACOS-}" ]]
  then
    UNAME_MACHINE="$(/usr/bin/uname -m)"

    if [[ "${UNAME_MACHINE}" == "arm64" ]]
    then
      # On ARM macOS, this script installs to /opt/odyssey only
      ODYSSEY_PREFIX="/opt/odyssey"
      ODYSSEY_REPOSITORY="${ODYSSEY_PREFIX}"
    else
      # On Intel macOS, this script installs to /usr/local only
      ODYSSEY_PREFIX="/usr/local"
      ODYSSEY_REPOSITORY="${ODYSSEY_PREFIX}/odyssey"
    fi
    ODYSSEY_CACHE="${HOME}/Library/Caches/Odyssey"

    STAT_PRINTF=("/usr/bin/stat" "-f")
    PERMISSION_FORMAT="%A"
    CHOWN=("/usr/sbin/chown")
    CHGRP=("/usr/bin/chgrp")
    GROUP="admin"
    TOUCH=("/usr/bin/touch")
    INSTALL=("/usr/bin/install" -d -o "root" -g "wheel" -m "0755")
  else
    UNAME_MACHINE="$(uname -m)"

    # On Linux, this script installs to /home/odyssey/.odyssey only
    ODYSSEY_PREFIX="/home/odyssey/.odyssey"
    ODYSSEY_REPOSITORY="${ODYSSEY_PREFIX}/odyssey"
    ODYSSEY_CACHE="${HOME}/.cache/odyssey"

    STAT_PRINTF=("/usr/bin/stat" "-c")
    PERMISSION_FORMAT="%a"
    CHOWN=("/bin/chown")
    CHGRP=("/bin/chgrp")
    GROUP="$(id -gn)"
    TOUCH=("/bin/touch")
    INSTALL=("/usr/bin/install" -d -o "${USER}" -g "${GROUP}" -m "0755")
  fi
  CHMOD=("/bin/chmod")
  MKDIR=("/bin/mkdir" "-p")

  # create paths.d file for /opt/odyssey installs
  # (/usr/local/bin is already in the PATH)
  if [[ -d "/etc/paths.d" && "${ODYSSEY_PREFIX}" != "/usr/local" && -x "$(command -v tee)" ]]
  then
    ADD_PATHS_D=1
  fi
}

setup_sudo_trap() {
  # Invalidate sudo timestamp before exiting (if it wasn't active before).
  if [[ -x /usr/bin/sudo ]] && ! /usr/bin/sudo -n -v 2>/dev/null
  then
    trap '/usr/bin/sudo -k' EXIT
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

display_installation_summary() {
  ohai "This script will install:"
  echo "${ODYSSEY_PREFIX}/bin/clean-code"
  echo "${ODYSSEY_REPOSITORY}"
  if [[ -n "${ADD_PATHS_D-}" ]]
  then
    echo "/etc/paths.d/odyssey"
  fi
  ohai "If not already installed, this script will install Babashka for the current user"
}

prepare_directories() {
  local directories=(bin)
  local group_chmods=()
  for dir in "${directories[@]}"
  do
    if exists_but_not_writable "${ODYSSEY_PREFIX}/${dir}"
    then
      group_chmods+=("${ODYSSEY_PREFIX}/${dir}")
    fi
  done

  # zsh refuses to read from these directories if group writable
  directories=(share/zsh share/zsh/site-functions)
  local zsh_dirs=()
  for dir in "${directories[@]}"
  do
    zsh_dirs+=("${ODYSSEY_PREFIX}/${dir}")
  done

  directories=(bin)
  local mkdirs=()
  for dir in "${directories[@]}"
  do
    if ! [[ -d "${ODYSSEY_PREFIX}/${dir}" ]]
    then
      mkdirs+=("${ODYSSEY_PREFIX}/${dir}")
    fi
  done

  local user_chmods=()
  local mkdirs_user_only=()
  if [[ "${#zsh_dirs[@]}" -gt 0 ]]
  then
    for dir in "${zsh_dirs[@]}"
    do
      if [[ ! -d "${dir}" ]]
      then
        mkdirs_user_only+=("${dir}")
      elif user_only_chmod "${dir}"
      then
        user_chmods+=("${dir}")
      fi
    done
  fi

  local chmods=()
  if [[ "${#group_chmods[@]}" -gt 0 ]]
  then
    chmods+=("${group_chmods[@]}")
  fi
  if [[ "${#user_chmods[@]}" -gt 0 ]]
  then
    chmods+=("${user_chmods[@]}")
  fi

  local chowns=()
  local chgrps=()
  if [[ "${#chmods[@]}" -gt 0 ]]
  then
    for dir in "${chmods[@]}"
    do
      if file_not_owned "${dir}"
      then
        chowns+=("${dir}")
      fi
      if file_not_grpowned "${dir}"
      then
        chgrps+=("${dir}")
      fi
    done
  fi

  # Display what will be changed
  if [[ "${#group_chmods[@]}" -gt 0 ]]
  then
    ohai "The following existing directories will be made group writable:"
    printf "%s\n" "${group_chmods[@]}"
  fi
  if [[ "${#user_chmods[@]}" -gt 0 ]]
  then
    ohai "The following existing directories will be made writable by user only:"
    printf "%s\n" "${user_chmods[@]}"
  fi
  if [[ "${#chowns[@]}" -gt 0 ]]
  then
    ohai "The following existing directories will have their owner set to ${tty_underline}${USER}${tty_reset}:"
    printf "%s\n" "${chowns[@]}"
  fi
  if [[ "${#chgrps[@]}" -gt 0 ]]
  then
    ohai "The following existing directories will have their group set to ${tty_underline}${GROUP}${tty_reset}:"
    printf "%s\n" "${chgrps[@]}"
  fi
  if [[ "${#mkdirs[@]}" -gt 0 ]]
  then
    ohai "The following new directories will be created:"
    printf "%s\n" "${mkdirs[@]}"
  fi

  # Store in arrays for setup_directory_permissions
  echo "${group_chmods[@]}" > /tmp/odyssey_group_chmods.txt
  echo "${user_chmods[@]}" > /tmp/odyssey_user_chmods.txt
  echo "${chmods[@]}" > /tmp/odyssey_chmods.txt
  echo "${chowns[@]}" > /tmp/odyssey_chowns.txt
  echo "${chgrps[@]}" > /tmp/odyssey_chgrps.txt
  echo "${mkdirs[@]}" > /tmp/odyssey_mkdirs.txt
  echo "${mkdirs_user_only[@]}" > /tmp/odyssey_mkdirs_user_only.txt
}

setup_directory_permissions() {
  # Read arrays from temp files
  local group_chmods=()
  local user_chmods=()
  local chmods=()
  local chowns=()
  local chgrps=()
  local mkdirs=()
  local mkdirs_user_only=()

  mapfile -t group_chmods < /tmp/odyssey_group_chmods.txt 2>/dev/null || true
  mapfile -t user_chmods < /tmp/odyssey_user_chmods.txt 2>/dev/null || true
  mapfile -t chmods < /tmp/odyssey_chmods.txt 2>/dev/null || true
  mapfile -t chowns < /tmp/odyssey_chowns.txt 2>/dev/null || true
  mapfile -t chgrps < /tmp/odyssey_chgrps.txt 2>/dev/null || true
  mapfile -t mkdirs < /tmp/odyssey_mkdirs.txt 2>/dev/null || true
  mapfile -t mkdirs_user_only < /tmp/odyssey_mkdirs_user_only.txt 2>/dev/null || true

  # Clean up temp files
  rm -f /tmp/odyssey_*.txt

  if [[ -d "${ODYSSEY_PREFIX}" ]]
  then
    if [[ "${#chmods[@]}" -gt 0 ]]
    then
      execute_sudo "${CHMOD[@]}" "u+rwx" "${chmods[@]}"
    fi
    if [[ "${#group_chmods[@]}" -gt 0 ]]
    then
      execute_sudo "${CHMOD[@]}" "g+rwx" "${group_chmods[@]}"
    fi
    if [[ "${#user_chmods[@]}" -gt 0 ]]
    then
      execute_sudo "${CHMOD[@]}" "go-w" "${user_chmods[@]}"
    fi
    if [[ "${#chowns[@]}" -gt 0 ]]
    then
      execute_sudo "${CHOWN[@]}" "${USER}" "${chowns[@]}"
    fi
    if [[ "${#chgrps[@]}" -gt 0 ]]
    then
      execute_sudo "${CHGRP[@]}" "${GROUP}" "${chgrps[@]}"
    fi
  else
    execute_sudo "${INSTALL[@]}" "${ODYSSEY_PREFIX}"
  fi

  if [[ "${#mkdirs[@]}" -gt 0 ]]
  then
    execute_sudo "${MKDIR[@]}" "${mkdirs[@]}"
    execute_sudo "${CHMOD[@]}" "ug=rwx" "${mkdirs[@]}"
    if [[ "${#mkdirs_user_only[@]}" -gt 0 ]]
    then
      execute_sudo "${CHMOD[@]}" "go-w" "${mkdirs_user_only[@]}"
    fi
    execute_sudo "${CHOWN[@]}" "${USER}" "${mkdirs[@]}"
    execute_sudo "${CHGRP[@]}" "${GROUP}" "${mkdirs[@]}"
  fi
}

setup_repository_and_cache() {
  if ! [[ -d "${ODYSSEY_REPOSITORY}" ]]
  then
    execute_sudo "${MKDIR[@]}" "${ODYSSEY_REPOSITORY}"
  fi
  execute_sudo "${CHOWN[@]}" "-R" "${USER}:${GROUP}" "${ODYSSEY_REPOSITORY}"

  if ! [[ -d "${ODYSSEY_CACHE}" ]]
  then
    execute "${MKDIR[@]}" "${ODYSSEY_CACHE}"
  fi
  if exists_but_not_writable "${ODYSSEY_CACHE}"
  then
    execute_sudo "${CHMOD[@]}" "g+rwx" "${ODYSSEY_CACHE}"
  fi
  if file_not_owned "${ODYSSEY_CACHE}"
  then
    execute_sudo "${CHOWN[@]}" "-R" "${USER}" "${ODYSSEY_CACHE}"
  fi
  if file_not_grpowned "${ODYSSEY_CACHE}"
  then
    execute_sudo "${CHGRP[@]}" "-R" "${GROUP}" "${ODYSSEY_CACHE}"
  fi
  if [[ -d "${ODYSSEY_CACHE}" ]]
  then
    execute "${TOUCH[@]}" "${ODYSSEY_CACHE}/.cleaned"
  fi
}

install_babashka() {
  if ! command -v bb >/dev/null
  then
    ohai "Babashka not found, installing"
    cd /usr/local || exit 1
    execute_sudo "curl" "-sSLO" "https://raw.githubusercontent.com/babashka/babashka/master/install"
    execute_sudo "${CHMOD[@]}" "+x" install
    execute_sudo "./install" "--static"
  elif [[ -n "${ODYSSEY_ON_LINUX-}" ]]
  then
    USABLE_BB="$(find_tool bb)"
    if [[ -z "${USABLE_BB}" ]]
    then
      abort "The version of Babashka that was found does not satisfy requirements for Odyssey.
Please install Babashka ${REQUIRED_BB_VERSION} or newer and add it to your PATH."
    elif [[ "${USABLE_BB}" != /usr/bin/bb ]]
    then
      export ODYSSEY_BB_PATH="${USABLE_BB}"
      ohai "Found Babashka: ${ODYSSEY_BB_PATH}"
    fi
  fi
}

install_odyssey_cli() {
  ohai "Downloading and installing Odyssey CLI..."
  (
    cd "${ODYSSEY_PREFIX}/bin" >/dev/null || exit 1
    execute_sudo "curl" "-LO" "http://127.0.0.1:8080/bin/odyssey"
    execute_sudo "${CHMOD[@]}" "+x" odyssey
    if [[ -n "${ODYSSEY_ON_MACOS-}" ]]
    then
      execute_sudo "/usr/bin/chflags" "uchg" odyssey
    else
      execute_sudo "/bin/chattr" "+i" odyssey
    fi
  ) || exit 1
}

display_success_message() {
  ohai "Installation successful!"
  echo

  ring_bell

  cat <<EOS
- Run ${tty_bold}odyssey config${tty_reset} to set your run command and get started!
EOS
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
  setup_git_remote
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
  prepare_directories

  if [[ -z "${NONINTERACTIVE-}" ]]
  then
    ring_bell
    wait_for_user
  fi

  # Perform installation
  setup_directory_permissions
  setup_repository_and_cache
  validate_and_setup_git
  install_babashka
  install_odyssey_cli

  # Display success
  display_success_message
}