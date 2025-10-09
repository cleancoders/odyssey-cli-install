#!/bin/bash

# Build script to create a single distributable install.sh
# This concatenates all library files into the main install script
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

# Start with the shebang and initial comments from the source
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

  # Add lib/utils.sh (skip shebang)
  echo "# --- lib/utils.sh ---"
  tail -n +2 "${PROJECT_DIR}/lib/utils.sh"
  echo ""

  # Add lib/version.sh (skip shebang)
  echo "# --- lib/version.sh ---"
  tail -n +2 "${PROJECT_DIR}/lib/version.sh"
  echo ""

  # Add lib/file_permissions.sh (skip shebang)
  echo "# --- lib/file_permissions.sh ---"
  tail -n +2 "${PROJECT_DIR}/lib/file_permissions.sh"
  echo ""

  # Add lib/execution.sh (skip shebang and source statements)
  echo "# --- lib/execution.sh ---"
  tail -n +2 "${PROJECT_DIR}/lib/execution.sh" | grep -v "^source " | grep -v "^# shellcheck source="
  echo ""

  # Add lib/validation.sh (skip shebang and source statements)
  echo "# --- lib/validation.sh ---"
  tail -n +2 "${PROJECT_DIR}/lib/validation.sh" | grep -v "^source " | grep -v "^# shellcheck source=" | grep -v "^PROJECT_DIR="
  echo ""

  echo "# ============================================================================"
  echo "# Main Installation Script (from bin/install.sh)"
  echo "# ============================================================================"
  echo ""

  # Add main install.sh (skip shebang, set -u, and library sourcing)
  tail -n +8 "${PROJECT_DIR}/bin/install.sh" | \
    sed '/^# Get the directory where the script is located/,/^source.*validation\.sh/d'

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
