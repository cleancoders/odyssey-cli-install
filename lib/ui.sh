#!/bin/bash

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
