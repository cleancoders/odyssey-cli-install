#!/bin/bash

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
