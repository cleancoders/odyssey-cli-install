#!/bin/bash

# Execution functions for Odyssey CLI installer

# Source utils.sh for shell_join function
# shellcheck source=lib/utils.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"

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
    ohai "/usr/bin/sudo" "${args[@]}"
    execute "/usr/bin/sudo" "${args[@]}"
  else
    ohai "${args[@]}"
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

  # Build curl arguments with HTTP status code capture
  # -w '\n%{http_code}' writes a newline followed by HTTP status code at the end
  # -S shows errors
  local -a full_curl_args=("curl" "-w" "\n%{http_code}" "-S" "${curl_args[@]}")
  response=$(execute_sudo "${full_curl_args[@]}")
  http_code=$(extract_http_status "${response}")
  body=$(extract_response_body "${response}")
  output_file=$(parse_curl_output_file "${curl_args[@]}")
  write_curl_output "${body}" "${output_file}" "${needs_sudo}"
  validate_http_status "${http_code}" "${curl_args[@]}"
}
