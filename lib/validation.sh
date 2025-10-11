#!/bin/bash

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
