#!/bin/bash

# Build script to create a single distributable install.sh
# This dynamically concatenates all library files that are sourced in bin/install.sh
#
# HOW IT WORKS:
#   1. Scans bin/install.sh for all 'source "${LIB_DIR}/..." statements
#   2. Extracts the filenames in the order they appear
#   3. Concatenates each library file into the output (removing shebangs and source statements)
#   4. Appends the main install.sh content (after the library sources)
#   5. Adds a call to main() at the end
#
# This means you can add new library files to bin/install.sh and this script will
# automatically include them in the correct order - no need to update this build script!
#
# Usage: build_installer.sh [output_directory]
#   output_directory: Optional. Directory where install.sh will be created.
#                     Defaults to project root.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR=$(dirname "${SCRIPT_DIR}")

# Parse arguments
if [[ $# -gt 0 ]]; then
  OUTPUT_DIR="$1"
  # Resolve to absolute path
  OUTPUT_DIR="$(cd "${OUTPUT_DIR}" 2>/dev/null && pwd)" || {
    echo "Error: Output directory '${1}' does not exist" >&2
    exit 1
  }
else
  OUTPUT_DIR="${PROJECT_DIR}"
fi

OUTPUT_FILE="${OUTPUT_DIR}/install.sh"

echo "Building distributable install.sh..."
echo "Output: ${OUTPUT_FILE}"

# Extract library files from install.sh source statements
# This finds all lines like: source "${LIB_DIR}/filename.sh"
# and extracts the filename
get_sourced_files() {
  grep -E '^source "\$\{LIB_DIR\}/' "${PROJECT_DIR}/bin/install.sh" | \
    sed -E 's/^source "\$\{LIB_DIR\}\/(.*\.sh)"/\1/' | \
    grep -v '^#'
}

# Get the list of library files in the order they're sourced
LIBRARY_FILES=($(get_sourced_files))

echo "Found ${#LIBRARY_FILES[@]} library files to include:"
for file in "${LIBRARY_FILES[@]}"; do
  echo "  - lib/${file}"
done

# Determine where the main content starts (after source statements)
# We'll find the line number where the last source statement appears
LAST_SOURCE_LINE=$(grep -n '^source "\${LIB_DIR}/' "${PROJECT_DIR}/bin/install.sh" | tail -1 | cut -d: -f1)
# Skip to the line after the last source statement
MAIN_START_LINE=$((LAST_SOURCE_LINE + 1))

# Start building the output file
{
  # Add header
  cat << 'EOF'
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

EOF

  # Add each library file
  for lib_file in "${LIBRARY_FILES[@]}"; do
    lib_path="${PROJECT_DIR}/lib/${lib_file}"

    if [[ ! -f "${lib_path}" ]]; then
      echo "Error: Library file not found: ${lib_path}" >&2
      exit 1
    fi

    echo "# --- lib/${lib_file} ---"

    # Skip shebang, remove source statements and shellcheck directives
    tail -n +2 "${lib_path}" | \
      grep -v '^source ' | \
      grep -v '^# shellcheck source=' | \
      grep -v '^PROJECT_DIR='

    echo ""
  done

  echo "# ============================================================================"
  echo "# Main Installation Script (from bin/install.sh)"
  echo "# ============================================================================"
  echo ""

  # Add main install.sh starting after the library source statements
  # Also remove the SCRIPT_DIR and LIB_DIR setup since they're no longer needed
  # And remove the conditional main call at the end (we'll add an unconditional one)
  tail -n +${MAIN_START_LINE} "${PROJECT_DIR}/bin/install.sh" | \
    sed '/^# Get the directory where the script is located/,/^LIB_DIR=/d' | \
    sed '/^# Call main if running as script/,/^fi$/d'

  echo ""
  echo "# ============================================================================"
  echo "# Execute main function with all arguments"
  echo "# ============================================================================"
  echo ""
  echo 'main "$@"'

} > "${OUTPUT_FILE}"

# Make the output file executable
chmod +x "${OUTPUT_FILE}"

echo "✓ Build complete: ${OUTPUT_FILE}"
echo "  File size: $(wc -c < "${OUTPUT_FILE}") bytes"
echo "  Lines: $(wc -l < "${OUTPUT_FILE}") lines"

# Verify syntax
if bash -n "${OUTPUT_FILE}"; then
  echo "✓ Syntax check passed"
else
  echo "✗ Syntax check failed!"
  exit 1
fi
