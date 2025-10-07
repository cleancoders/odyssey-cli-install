#!/bin/bash

# Create a test file for a given source file
# Usage: create_test.sh <source_file>

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "${SCRIPT_DIR}")"
TEST_DIR="${PROJECT_DIR}/test"

# Check if source file is provided
if [[ $# -eq 0 ]]; then
  echo "Error: No source file provided"
  echo ""
  echo "Usage: create_test.sh <source_file>"
  echo "  Example: create_test.sh lib/utils.sh"
  echo "  Example: create_test.sh bin/build_installer.sh"
  exit 1
fi

SOURCE_FILE="$1"

# Extract the basename without path and extension
SOURCE_BASENAME=$(basename "${SOURCE_FILE}")
SOURCE_NAME="${SOURCE_BASENAME%.sh}"

# Determine test file name
TEST_FILE="${TEST_DIR}/test_${SOURCE_NAME}.sh"

# Check if test file already exists
if [[ -f "${TEST_FILE}" ]]; then
  echo "Error: Test file already exists: ${TEST_FILE}"
  exit 1
fi

# Determine the relative path to the source file from project root
if [[ "${SOURCE_FILE}" == */* ]]; then
  SOURCE_PATH="${SOURCE_FILE}"
else
  SOURCE_PATH="bin/${SOURCE_FILE}"
fi

# Create the test file
cat > "${TEST_FILE}" << 'EOF'
#!/bin/bash

# Unit tests for SOURCE_PATH

# Get the project root directory
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "${TEST_DIR}")"

# Source shunit2
SHUNIT2="${PROJECT_DIR}/shunit2"

# Source the file under test
# shellcheck disable=SC1090
source "${PROJECT_DIR}/SOURCE_PATH"

# Test fixtures
TEST_OUTPUT_DIR=""

# Setup function - runs before each test
setUp() {
  # Create a temporary directory for test output
  TEST_OUTPUT_DIR="$(mktemp -d)"
}

# Teardown function - runs after each test
tearDown() {
  # Clean up temporary directory
  if [[ -n "${TEST_OUTPUT_DIR}" && -d "${TEST_OUTPUT_DIR}" ]]; then
    rm -rf "${TEST_OUTPUT_DIR}"
  fi
}

# Example test - replace with actual tests
test_example() {
  assertTrue "Example test that always passes" "[ 1 -eq 1 ]"
}

# Add your tests here
# test_function_name() {
#   assertEquals "Description" "expected" "$(actual_command)"
# }

# Load and run shunit2
# shellcheck disable=SC1090
. "${SHUNIT2}"
EOF

# Replace SOURCE_PATH placeholder with actual path
sed -i.bak "s|SOURCE_PATH|${SOURCE_PATH}|g" "${TEST_FILE}"
rm -f "${TEST_FILE}.bak"

# Make the test file executable
chmod +x "${TEST_FILE}"

echo "✓ Created test file: ${TEST_FILE}"
echo ""
echo "To run the test:"
echo "  ./test/test_${SOURCE_NAME}.sh"
echo "  # or"
echo "  make test"
echo ""
echo "To edit the test:"
echo "  \$EDITOR ${TEST_FILE}"
