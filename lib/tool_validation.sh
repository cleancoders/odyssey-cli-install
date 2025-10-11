#!/bin/bash

# Validation functions for Odyssey CLI installer

# Source version.sh for version comparison functions
# shellcheck source=lib/version.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/version.sh"
source "${SCRIPT_DIR}/utils.sh"

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

# TODO bb --version comes back with a v on the front. This needs to be shaved off for this to work,
# TODO otherwise the script just always re-installs babashka
REQUIRED_BB_VERSION="1.12.193"
test_bb() {
  if [[ ! -x "$1" ]]
  then
    return 1
  fi

  local bb_version_output bb_name_and_version
  bb_version_output="$("$1" --version 2>/dev/null)"
  bb_name_and_version="${bb_version_output%% (*}"
  version_ge "$(major_minor "${bb_name_and_version##* }")" "$(major_minor "${REQUIRED_BB_VERSION}")"
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
   execute_sudo "curl" "-sSLO" "https://raw.githubusercontent.com/babashka/babashka/master/install"
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