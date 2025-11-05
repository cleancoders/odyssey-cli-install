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
# shellcheck disable=SC2034
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
