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

# Fail fast with a concise message when not using bash
# Single brackets are needed here for POSIX compatibility
# shellcheck disable=SC2292
if [ -z "${BASH_VERSION:-}" ]
then
  printf "%s\n" "Bash is required to interpret this script." >&2
  exit 1
fi

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

# USER isn't always set so provide a fall back for the installer and subprocesses.
if [[ -z "${USER-}" ]]
then
  USER="$(chomp "$(id -un)")"
  export USER
fi

# First check OS.
OS="$(uname)"
if [[ "${OS}" == "Linux" ]]
then
  ODYSSEY_ON_LINUX=1
elif [[ "${OS}" == "Darwin" ]]
then
  ODYSSEY_ON_MACOS=1
else
  abort "Odyssey CLI is only supported on macOS and Linux."
fi

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
ODYSSEY_DEFAULT_GIT_REMOTE="https://github.com/cleancoders/odyssey-cli"

# Use remote URLs of Odyssey repositories from environment if set.
ODYSSEY_GIT_REMOTE="${ODYSSEY_GIT_REMOTE:-"${ODYSSEY_DEFAULT_GIT_REMOTE}"}"
# The URLs with and without the '.git' suffix are the same Git remote. Do not prompt.
if [[ "${ODYSSEY_GIT_REMOTE}" == "${ODYSSEY_DEFAULT_GIT_REMOTE}.git" ]]
then
  ODYSSEY_GIT_REMOTE="${ODYSSEY_DEFAULT_GIT_REMOTE}"
fi
if [[ "${ODYSSEY_GIT_REMOTE}" == "${ODYSSEY_DEFAULT_GIT_REMOTE}.git" ]]
then
  ODYSSEY_GIT_REMOTE="${ODYSSEY_DEFAULT_GIT_REMOTE}"
fi
export ODYSSEY_GIT_REMOTE

# TODO: bump version when new macOS is released or announced
MACOS_NEWEST_UNSUPPORTED="27.0"
# TODO: bump version when new macOS is released
MACOS_OLDEST_SUPPORTED="14.0"

REQUIRED_BB_VERSION=1.12.193

# For Odyssey on Linux
REQUIRED_CURL_VERSION=7.41.0
REQUIRED_GIT_VERSION=2.7.0

# create paths.d file for /opt/odyssey installs
# (/usr/local/bin is already in the PATH)
if [[ -d "/etc/paths.d" && "${ODYSSEY_PREFIX}" != "/usr/local" && -x "$(command -v tee)" ]]
then
  ADD_PATHS_D=1
fi

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

should_install_command_line_tools() {
  if [[ -n "${ODYSSEY_ON_LINUX-}" ]]
  then
    return 1
  fi

  if version_gt "${macos_version}" "10.13"
  then
    ! [[ -e "/Library/Developer/CommandLineTools/usr/bin/git" ]]
  else
    ! [[ -e "/Library/Developer/CommandLineTools/usr/bin/git" ]] ||
      ! [[ -e "/usr/include/iconv.h" ]]
  fi
}

# Invalidate sudo timestamp before exiting (if it wasn't active before).
if [[ -x /usr/bin/sudo ]] && ! /usr/bin/sudo -n -v 2>/dev/null
then
  trap '/usr/bin/sudo -k' EXIT
fi

# Things can fail later if `pwd` doesn't exist.
# Also sudo prints a warning message for no good reason
cd "/usr" || exit 1

####################################################################### script

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

# Get tty formatting variables from utils.sh

if [[ -d "${ODYSSEY_PREFIX}" && ! -x "${ODYSSEY_PREFIX}" ]]
then
abort "The Odyssey prefix ${tty_underline}${ODYSSEY_PREFIX}${tty_reset} exists but is not searchable.
If this is not intentional, please restore the default permissions and
try running the installer again:
    sudo chmod 775 ${ODYSSEY_PREFIX}"
fi

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

ohai "This script will install:"
echo "${ODYSSEY_PREFIX}/bin/clean-code"
echo "${ODYSSEY_REPOSITORY}"
if [[ -n "${ADD_PATHS_D-}" ]]
then
  echo "/etc/paths.d/odyssey"
fi
ohai "If not already installed, this script will install Babashka on your system"

directories=(
  bin
)
group_chmods=()
for dir in "${directories[@]}"
do
  if exists_but_not_writable "${ODYSSEY_PREFIX}/${dir}"
  then
    group_chmods+=("${ODYSSEY_PREFIX}/${dir}")
  fi
done

# zsh refuses to read from these directories if group writable
directories=(share/zsh share/zsh/site-functions)
zsh_dirs=()
for dir in "${directories[@]}"
do
  zsh_dirs+=("${ODYSSEY_PREFIX}/${dir}")
done

directories=(
  bin
)
mkdirs=()
for dir in "${directories[@]}"
do
  if ! [[ -d "${ODYSSEY_PREFIX}/${dir}" ]]
  then
    mkdirs+=("${ODYSSEY_PREFIX}/${dir}")
  fi
done

user_chmods=()
mkdirs_user_only=()
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

chmods=()
if [[ "${#group_chmods[@]}" -gt 0 ]]
then
  chmods+=("${group_chmods[@]}")
fi
if [[ "${#user_chmods[@]}" -gt 0 ]]
then
  chmods+=("${user_chmods[@]}")
fi

chowns=()
chgrps=()
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

if should_install_command_line_tools
then
  ohai "The Xcode Command Line Tools will be installed."
fi

if [[ -z "${NONINTERACTIVE-}" ]]
then
  ring_bell
  wait_for_user
fi

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

if should_install_command_line_tools && version_ge "${macos_version}" "10.13"
then
  ohai "Searching online for the Command Line Tools"
  # This temporary file prompts the 'softwareupdate' utility to list the Command Line Tools
  clt_placeholder="/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress"
  execute_sudo "${TOUCH[@]}" "${clt_placeholder}"

  clt_label_command="/usr/sbin/softwareupdate -l |
                      grep -B 1 -E 'Command Line Tools' |
                      awk -F'*' '/^ *\\*/ {print \$2}' |
                      sed -e 's/^ *Label: //' -e 's/^ *//' |
                      sort -V |
                      tail -n1"
  clt_label="$(chomp "$(/bin/bash -c "${clt_label_command}")")"

  if [[ -n "${clt_label}" ]]
  then
    ohai "Installing ${clt_label}"
    execute_sudo "/usr/sbin/softwareupdate" "-i" "${clt_label}"
    execute_sudo "/usr/bin/xcode-select" "--switch" "/Library/Developer/CommandLineTools"
  fi
  execute_sudo "/bin/rm" "-f" "${clt_placeholder}"
fi

# Headless install may have failed, so fallback to original 'xcode-select' method
if should_install_command_line_tools && test -t 0
then
  ohai "Installing the Command Line Tools (expect a GUI popup):"
  execute "/usr/bin/xcode-select" "--install"
  echo "Press any key when the installation has completed."
  getc
  execute_sudo "/usr/bin/xcode-select" "--switch" "/Library/Developer/CommandLineTools"
fi

if [[ -n "${ODYSSEY_ON_MACOS-}" ]] && ! output="$(/usr/bin/xcrun clang 2>&1)" && [[ "${output}" == *"license"* ]]
then
  abort <<EOABORT
You have not agreed to the Xcode license.
Before running the installer again please agree to the license by opening
Xcode.app or running:
    sudo xcodebuild -license
EOABORT
fi

USABLE_GIT=/usr/bin/git
if [[ -n "${ODYSSEY_ON_LINUX-}" ]]
then
  USABLE_GIT="$(find_tool git)"
  if [[ -z "$(command -v git)" ]]
  then
    abort "$(
      cat <<EOABORT
  You must install Git before installing Odyssey. See:
    ${tty_underline}https://docs.brew.sh/Installation${tty_reset}
EOABORT
    )"
  fi
  if [[ -z "${USABLE_GIT}" ]]
  then
    abort "The version of Git that was found does not satisfy requirements for Odyssey.
    Please install Git ${REQUIRED_GIT_VERSION} or newer and add it to your PATH."
  fi
  if [[ "${USABLE_GIT}" != /usr/bin/git ]]
  then
    export ODYSSEY_GIT_PATH="${USABLE_GIT}"
    ohai "Found Git: ${ODYSSEY_GIT_PATH}"
  fi
fi

if ! command -v curl >/dev/null
then
  abort "$(
    cat <<EOABORT
You must install cURL before installing Odyssey.
EOABORT
  )"
elif [[ -n "${ODYSSEY_ON_LINUX-}" ]]
then
  USABLE_CURL="$(find_tool curl)"
  if [[ -z "${USABLE_CURL}" ]]
  then
abort "The version of cURL that was found does not satisfy requirements for Odyssey.
Please install cURL ${REQUIRED_CURL_VERSION} or newer and add it to your PATH."
  elif [[ "${USABLE_CURL}" != /usr/bin/curl ]]
  then
    export ODYSSEY_CURL_PATH="${USABLE_CURL}"
    ohai "Found cURL: ${ODYSSEY_CURL_PATH}"
  fi
fi

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

ohai "Downloading and installing Odyssey CLI..."
(

  cd "${ODYSSEY_PREFIX}/bin" >/dev/null || exit 1
  execute_sudo "curl" "-LO" "http://127.0.0.1:8080/bin/odyssey"
  execute_sudo "${CHMOD[@]}" "+x" odyssey
) || exit 1

ohai "Installation successful!"
echo

ring_bell

cat <<EOS
- Run ${tty_bold}odyssey config${tty_reset} to set your run command and get started!
EOS