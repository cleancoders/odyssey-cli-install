#!/bin/bash

# Build script to create a single distributable install.sh
# This concatenates all library files into the main install script

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR=$(dirname "${SCRIPT_DIR}")
OUTPUT_FILE="${PROJECT_DIR}/install.sh"

echo "Building distributable install.sh..."

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
