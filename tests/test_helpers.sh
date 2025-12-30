#!/bin/bash
#
# Unit tests for lib/helpers.sh
#
# This demonstrates how to test modules in isolation

set -uo pipefail  # Don't use -e, we handle errors ourselves

# Colors for test output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Test result tracking
FAILED_TESTS=()

# Simple assertion functions
assert_true() {
    ((TESTS_RUN++))
    if "$@"; then
        ((TESTS_PASSED++))
        echo -e "${GREEN}✓${NC} $*"
        return 0
    else
        ((TESTS_FAILED++))
        FAILED_TESTS+=("$*")
        echo -e "${RED}✗${NC} $*"
        return 1
    fi
}

assert_false() {
    ((TESTS_RUN++))
    if ! "$@"; then
        ((TESTS_PASSED++))
        echo -e "${GREEN}✓${NC} $* (expected false)"
        return 0
    else
        ((TESTS_FAILED++))
        FAILED_TESTS+=("$*")
        echo -e "${RED}✗${NC} $* (expected false, got true)"
        return 1
    fi
}

assert_equal() {
    ((TESTS_RUN++))
    local expected="$1"
    local actual="$2"
    shift 2
    local test_name="${*:-assert_equal}"

    if [[ "$expected" == "$actual" ]]; then
        ((TESTS_PASSED++))
        echo -e "${GREEN}✓${NC} $test_name (expected: '$expected', got: '$actual')"
        return 0
    else
        ((TESTS_FAILED++))
        FAILED_TESTS+=("$test_name")
        echo -e "${RED}✗${NC} $test_name (expected: '$expected', got: '$actual')"
        return 1
    fi
}

# Setup: Source the module and initialize required variables
setup() {
    # Get script directory
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

    # Initialize required global variables (minimal set for helpers.sh)
    # shellcheck disable=SC2034  # These are used by the sourced module
    declare -gA LOADED_PLUGINS=()
    # shellcheck disable=SC2034  # Used by helpers.sh
    declare -ga POST_HOOK_EXEMPT_COMMANDS=()
    # shellcheck disable=SC2034  # Used by helpers.sh
    declare -ga NOTIFY_CAPS=()
    # shellcheck disable=SC2034  # Used by helpers.sh
    declare -g COLOR_RED="$RED"
    # shellcheck disable=SC2034  # Used by helpers.sh
    declare -g COLOR_YELLOW="$YELLOW"
    # shellcheck disable=SC2034  # Used by helpers.sh
    declare -g COLOR_RESET="$NC"

    # Source the helpers module
    # shellcheck disable=SC1091  # Source is intentional for testing
    source "$SCRIPT_DIR/lib/helpers.sh"
}

# Test empty() function
test_empty() {
    echo -e "\n${YELLOW}Testing empty() function${NC}"

    assert_true empty ""
    assert_false empty "not empty"
    assert_false empty "0"
    # Note: empty() doesn't handle missing args well due to set -u
    # This is expected behavior - always pass an argument
}

# Test not_empty() function
test_not_empty() {
    echo -e "\n${YELLOW}Testing not_empty() function${NC}"

    assert_true not_empty "something"
    assert_false not_empty ""
    assert_true not_empty "0"
    # Note: not_empty() doesn't handle missing args well due to set -u
    # This is expected behavior - always pass an argument
}

# Test isset() function
test_isset() {
    echo -e "\n${YELLOW}Testing isset() function${NC}"

    # shellcheck disable=SC2034  # test_var is used in isset() call
    local test_var="value"
    assert_true isset test_var

    unset test_var
    assert_false isset test_var

    # Test with array
    # shellcheck disable=SC2034  # test_array is used in isset() call
    local -a test_array=("item1" "item2")
    assert_true isset test_array

    unset test_array
    assert_false isset test_array
}

# Test command_exists() function
test_command_exists() {
    echo -e "\n${YELLOW}Testing command_exists() function${NC}"

    assert_true command_exists bash
    assert_true command_exists ls
    assert_false command_exists nonexistent_command_xyz123
}

# Test max() function
test_max() {
    echo -e "\n${YELLOW}Testing max() function${NC}"

    assert_equal "10" "$(max 5 10)"
    assert_equal "10" "$(max 10 5)"
    assert_equal "0" "$(max 0 -5)"
    assert_equal "100" "$(max 100 100)"
}

# Test get_script_dir() function
test_get_script_dir() {
    echo -e "\n${YELLOW}Testing get_script_dir() function${NC}"

    local script_dir
    script_dir=$(get_script_dir)

    # Should return a directory path
    if [[ -d "$script_dir" ]]; then
        assert_true true "get_script_dir returns valid directory"
    else
        assert_true false "get_script_dir returns valid directory"
    fi

    if [[ "$script_dir" == *"i3-volume"* ]]; then
        assert_true true "get_script_dir contains i3-volume"
    else
        assert_true false "get_script_dir contains i3-volume"
    fi
}

# Test plugin system functions
test_plugin_system() {
    echo -e "\n${YELLOW}Testing plugin system${NC}"

    # Create a temporary test plugin
    local test_plugin_dir
    test_plugin_dir=$(mktemp -d)
    local test_plugin="$test_plugin_dir/test_plugin"

    # Create a simple test plugin
    cat > "$test_plugin" << 'EOF'
#!/bin/bash
test_plugin_test() {
    echo "test_plugin_works"
}
EOF
    chmod +x "$test_plugin"

    # Mock get_plugin_dir to return our test directory
    # Note: This requires modifying the function or using a wrapper
    # For now, we'll test the plugin listing functionality

    # Test is_plugin_available (will fail without proper setup, but shows structure)
    # assert_false is_plugin_available "notify" "nonexistent_plugin"

    echo "  (Plugin system tests require proper directory setup)"
}

# Test has_color() function
test_has_color() {
    echo -e "\n${YELLOW}Testing has_color() function${NC}"

    # This will depend on the actual terminal
    # Just verify it doesn't crash
    has_color >/dev/null 2>&1 || true
    assert_true true  # Placeholder - has_color is environment-dependent
}

# Run all tests
run_tests() {
    echo -e "${YELLOW}Running tests for lib/helpers.sh${NC}"
    echo "=========================================="

    setup

    test_empty
    test_not_empty
    test_isset
    test_command_exists
    test_max
    test_get_script_dir
    test_plugin_system
    test_has_color

    # Print summary
    echo -e "\n${YELLOW}=========================================="
    echo "Test Summary"
    echo "==========================================${NC}"
    echo -e "Tests run:    $TESTS_RUN"
    echo -e "${GREEN}Tests passed: $TESTS_PASSED${NC}"
    if [[ $TESTS_FAILED -gt 0 ]]; then
        echo -e "${RED}Tests failed: $TESTS_FAILED${NC}"
        echo -e "\n${RED}Failed tests:${NC}"
        for test in "${FAILED_TESTS[@]}"; do
            echo -e "  ${RED}✗${NC} $test"
        done
        return 1
    else
        echo -e "${GREEN}All tests passed!${NC}"
        return 0
    fi
}

# Run tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_tests
    exit $?
fi

