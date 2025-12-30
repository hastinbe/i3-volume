#!/bin/bash
#
# Test runner for i3-volume module tests
#
# Usage:
#   ./test_runner.sh              # Run all tests
#   ./test_runner.sh helpers      # Run only helpers tests
#   ./test_runner.sh -v           # Verbose mode
#   ./test_runner.sh -h           # Show help

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERBOSE=false
TEST_MODULE=""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

usage() {
    cat << EOF
Usage: $0 [OPTIONS] [MODULE]

Run unit tests for i3-volume modules.

Options:
    -h, --help      Show this help message
    -v, --verbose   Enable verbose output
    --list          List available test modules

Modules:
    helpers         Test lib/helpers.sh
    config          Test lib/config.sh
    audio           Test lib/audio.sh
    notify          Test lib/notify.sh
    output          Test lib/output.sh
    commands        Test lib/commands.sh
    all             Run all tests (default)

Examples:
    $0                    # Run all tests
    $0 helpers            # Run only helpers tests
    $0 -v config          # Run config tests with verbose output
EOF
}

list_modules() {
    echo "Available test modules:"
    for test_file in "$SCRIPT_DIR"/test_*.sh; do
        if [[ -f "$test_file" ]]; then
            local module_name
            module_name=$(basename "$test_file" .sh | sed 's/^test_//')
            echo "  - $module_name"
        fi
    done
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        --list)
            list_modules
            exit 0
            ;;
        helpers|config|audio|notify|output|commands|all)
            TEST_MODULE="$1"
            shift
            ;;
        *)
            echo -e "${RED}Error: Unknown option or module: $1${NC}" >&2
            usage
            exit 1
            ;;
    esac
done

# Default to all if no module specified
TEST_MODULE="${TEST_MODULE:-all}"

# Run tests
run_test_module() {
    local module=$1
    local test_file="$SCRIPT_DIR/test_${module}.sh"

    if [[ ! -f "$test_file" ]]; then
        echo -e "${RED}Error: Test file not found: $test_file${NC}" >&2
        return 1
    fi

    if [[ ! -x "$test_file" ]]; then
        chmod +x "$test_file"
    fi

    echo -e "\n${BLUE}=========================================="
    echo "Running tests for: $module"
    printf "==========================================%s\n\n" "${NC}"

    if $VERBOSE; then
        bash -x "$test_file"
    else
        bash "$test_file"
    fi
}

# Main execution
main() {
    echo -e "${YELLOW}i3-volume Module Test Runner${NC}"
    echo "=========================================="

    local exit_code=0

    if [[ "$TEST_MODULE" == "all" ]]; then
        # Run all test modules
        for test_file in "$SCRIPT_DIR"/test_*.sh; do
            if [[ -f "$test_file" ]]; then
                local module_name
                module_name=$(basename "$test_file" .sh | sed 's/^test_//')
                if ! run_test_module "$module_name"; then
                    exit_code=1
                fi
            fi
        done
    else
        # Run specific module
        if ! run_test_module "$TEST_MODULE"; then
            exit_code=1
        fi
    fi

    # Final summary
    echo -e "\n${YELLOW}=========================================="
    if [[ $exit_code -eq 0 ]]; then
        echo -e "${GREEN}All tests completed successfully!${NC}"
    else
        echo -e "${RED}Some tests failed${NC}"
    fi
    printf "==========================================%s\n" "${NC}"

    return $exit_code
}

main "$@"

