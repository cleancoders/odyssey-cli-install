#!/bin/bash

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
