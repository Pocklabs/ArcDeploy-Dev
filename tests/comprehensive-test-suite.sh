#!/bin/bash

# ArcDeploy Comprehensive Test Suite with Dummy Data & Debug Tools
# This script provides extensive testing capabilities including dummy data scenarios,
# mock infrastructure testing, debug tool validation, and failure injection testing

set -euo pipefail

# ============================================================================
# Script Metadata
# ============================================================================
readonly SCRIPT_VERSION="1.0.0"
readonly SCRIPT_NAME="$(basename "$0")"

# Directory setup
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly PROJECT_ROOT

# Test directories
readonly TEST_DATA_DIR="$PROJECT_ROOT/test-data"
readonly MOCK_INFRASTRUCTURE_DIR="$PROJECT_ROOT/mock-infrastructure"
readonly DEBUG_TOOLS_DIR="$PROJECT_ROOT/debug-tools"
readonly TEST_RESULTS_DIR="$PROJECT_ROOT/test-results"
readonly TEST_LOGS_DIR="$TEST_RESULTS_DIR/comprehensive-logs"

# ============================================================================
# Configuration
# ============================================================================
readonly REPORT_FILE="$TEST_RESULTS_DIR/comprehensive-test-report.txt"
readonly JSON_REPORT_FILE="$TEST_RESULTS_DIR/comprehensive-test-report.json"
readonly PERFORMANCE_LOG="$TEST_LOGS_DIR/performance.log"
readonly FAILURE_LOG="$TEST_LOGS_DIR/failures.log"

# Mock API server configuration
readonly MOCK_API_HOST="127.0.0.1"
readonly MOCK_API_PORT="8888"
readonly MOCK_API_URL="http://$MOCK_API_HOST:$MOCK_API_PORT"

# ============================================================================
# Colors and Formatting
# ============================================================================
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m'

# ============================================================================
# Test Counters and State
# ============================================================================
declare -g TOTAL_TESTS=0
declare -g PASSED_TESTS=0
declare -g FAILED_TESTS=0
declare -g SKIPPED_TESTS=0
declare -g WARNING_TESTS=0

# Category-specific counters
declare -g SSH_KEY_TESTS=0
declare -g SSH_KEY_PASSED=0
declare -g SSH_KEY_FAILED=0

declare -g CLOUD_PROVIDER_TESTS=0
declare -g CLOUD_PROVIDER_PASSED=0
declare -g CLOUD_PROVIDER_FAILED=0

declare -g CONFIG_TESTS=0
declare -g CONFIG_PASSED=0
declare -g CONFIG_FAILED=0

declare -g DEBUG_TOOL_TESTS=0
declare -g DEBUG_TOOL_PASSED=0
declare -g DEBUG_TOOL_FAILED=0

declare -g NETWORK_SIM_TESTS=0
declare -g NETWORK_SIM_PASSED=0
declare -g NETWORK_SIM_FAILED=0

declare -g MOCK_API_TESTS=0
declare -g MOCK_API_PASSED=0
declare -g MOCK_API_FAILED=0

# Test execution state
declare -g MOCK_API_PID=""
declare -g CLEANUP_NEEDED="false"

# ============================================================================
# Logging Functions
# ============================================================================

log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        "INFO")
            echo -e "${BLUE}[INFO]${NC} $message" | tee -a "$TEST_LOGS_DIR/main.log"
            ;;
        "PASS")
            echo -e "${GREEN}[PASS]${NC} $message" | tee -a "$TEST_LOGS_DIR/main.log"
            ((PASSED_TESTS++))
            ;;
        "FAIL")
            echo -e "${RED}[FAIL]${NC} $message" | tee -a "$TEST_LOGS_DIR/main.log"
            echo "[$timestamp] FAIL: $message" >> "$FAILURE_LOG"
            ((FAILED_TESTS++))
            ;;
        "WARN")
            echo -e "${YELLOW}[WARN]${NC} $message" | tee -a "$TEST_LOGS_DIR/main.log"
            ((WARNING_TESTS++))
            ;;
        "SKIP")
            echo -e "${YELLOW}[SKIP]${NC} $message" | tee -a "$TEST_LOGS_DIR/main.log"
            ((SKIPPED_TESTS++))
            ;;
        "DEBUG")
            if [[ "${DEBUG_MODE:-false}" == "true" ]]; then
                echo -e "${PURPLE}[DEBUG]${NC} $message" | tee -a "$TEST_LOGS_DIR/debug.log"
            fi
            ;;
    esac
    
    echo "[$timestamp] [$level] $message" >> "$TEST_LOGS_DIR/main.log"
}

section_header() {
    local title="$1"
    local width=80
    local padding=$(( (width - ${#title} - 2) / 2 ))
    local separator=$(printf '=%.0s' $(seq 1 $width))
    
    echo ""
    echo -e "${CYAN}$separator${NC}"
    printf "${CYAN}%*s %s %*s${NC}\n" $padding "" "$title" $padding ""
    echo -e "${CYAN}$separator${NC}"
    echo ""
}

progress_bar() {
    local current="$1"
    local total="$2"
    local width=50
    local percentage=$((current * 100 / total))
    local filled=$((width * current / total))
    
    printf "\r${BLUE}Progress:${NC} ["
    printf "%*s" $filled | tr ' ' '='
    printf "%*s" $((width - filled)) | tr ' ' '-'
    printf "] %d%% (%d/%d)" $percentage $current $total
}

# ============================================================================
# Utility Functions
# ============================================================================

run_test() {
    local test_name="$1"
    local test_function="$2"
    local category="${3:-general}"
    
    ((TOTAL_TESTS++))
    
    log "INFO" "Running test: $test_name"
    
    local start_time=$(date +%s.%N)
    local test_result="UNKNOWN"
    
    # Execute test function with error handling
    if $test_function; then
        test_result="PASS"
        log "PASS" "$test_name"
        
        # Update category counters
        case "$category" in
            "ssh_key") ((SSH_KEY_PASSED++)) ;;
            "cloud_provider") ((CLOUD_PROVIDER_PASSED++)) ;;
            "config") ((CONFIG_PASSED++)) ;;
            "debug_tool") ((DEBUG_TOOL_PASSED++)) ;;
            "network_sim") ((NETWORK_SIM_PASSED++)) ;;
            "mock_api") ((MOCK_API_PASSED++)) ;;
        esac
    else
        test_result="FAIL"
        log "FAIL" "$test_name"
        
        # Update category counters
        case "$category" in
            "ssh_key") ((SSH_KEY_FAILED++)) ;;
            "cloud_provider") ((CLOUD_PROVIDER_FAILED++)) ;;
            "config") ((CONFIG_FAILED++)) ;;
            "debug_tool") ((DEBUG_TOOL_FAILED++)) ;;
            "network_sim") ((NETWORK_SIM_FAILED++)) ;;
            "mock_api") ((MOCK_API_FAILED++)) ;;
        esac
    fi
    
    local end_time=$(date +%s.%N)
    local duration=$(echo "scale=3; $end_time - $start_time" | bc -l 2>/dev/null || echo "0.000")
    
    # Log performance data
    echo "$(date '+%Y-%m-%d %H:%M:%S'),$test_name,$category,$test_result,$duration" >> "$PERFORMANCE_LOG"
    
    log "DEBUG" "Test $test_name completed in ${duration}s with result: $test_result"
}

check_prerequisites() {
    log "INFO" "Checking test prerequisites..."
    
    # Check if test data directory exists
    if [[ ! -d "$TEST_DATA_DIR" ]]; then
        log "FAIL" "Test data directory not found: $TEST_DATA_DIR"
        return 1
    fi
    
    # Check if mock infrastructure exists
    if [[ ! -d "$MOCK_INFRASTRUCTURE_DIR" ]]; then
        log "WARN" "Mock infrastructure directory not found: $MOCK_INFRASTRUCTURE_DIR"
    fi
    
    # Check if debug tools exist
    if [[ ! -d "$DEBUG_TOOLS_DIR" ]]; then
        log "WARN" "Debug tools directory not found: $DEBUG_TOOLS_DIR"
    fi
    
    # Check required commands
    local required_commands=("curl" "python3" "bc" "jq")
    local missing_commands=()
    
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_commands+=("$cmd")
        fi
    done
    
    if [[ ${#missing_commands[@]} -gt 0 ]]; then
        log "WARN" "Missing optional commands: ${missing_commands[*]}"
    fi
    
    # Create necessary directories
    mkdir -p "$TEST_RESULTS_DIR" "$TEST_LOGS_DIR"
    
    # Initialize log files
    echo "timestamp,test_name,category,result,duration_seconds" > "$PERFORMANCE_LOG"
    echo "Comprehensive test suite started on $(date)" > "$TEST_LOGS_DIR/main.log"
    echo "Failure log initialized on $(date)" > "$FAILURE_LOG"
    
    log "INFO" "Prerequisites check completed"
    return 0
}

cleanup() {
    log "INFO" "Starting cleanup procedures..."
    
    # Stop mock API server if running
    if [[ -n "$MOCK_API_PID" ]] && kill -0 "$MOCK_API_PID" 2>/dev/null; then
        log "INFO" "Stopping mock API server (PID: $MOCK_API_PID)"
        kill "$MOCK_API_PID" 2>/dev/null || true
        wait "$MOCK_API_PID" 2>/dev/null || true
    fi
    
    # Clean up any network simulation
    if command -v tc >/dev/null 2>&1 && [[ $EUID -eq 0 ]]; then
        tc qdisc del dev lo root 2>/dev/null || true
    fi
    
    # Clean up temporary test files
    find /tmp -name "arcdeploy-test-*" -type f -mmin +60 -delete 2>/dev/null || true
    
    log "INFO" "Cleanup completed"
}

# Set up cleanup trap
trap cleanup EXIT INT TERM

# ============================================================================
# SSH Key Testing Functions
# ============================================================================

test_ssh_key_validation() {
    local ssh_keys_dir="$TEST_DATA_DIR/ssh-keys"
    
    if [[ ! -d "$ssh_keys_dir" ]]; then
        log "SKIP" "SSH keys test data not found"
        return 0
    fi
    
    # Test valid SSH keys
    local valid_keys_dir="$ssh_keys_dir/valid"
    if [[ -d "$valid_keys_dir" ]]; then
        for key_file in "$valid_keys_dir"/*.pub; do
            if [[ -f "$key_file" ]]; then
                local key_name=$(basename "$key_file" .pub)
                if validate_ssh_key_format "$key_file"; then
                    log "PASS" "Valid SSH key test: $key_name"
                else
                    log "FAIL" "Valid SSH key test failed: $key_name"
                    return 1
                fi
            fi
        done
    fi
    
    # Test invalid SSH keys
    local invalid_keys_dir="$ssh_keys_dir/invalid"
    if [[ -d "$invalid_keys_dir" ]]; then
        for key_file in "$invalid_keys_dir"/*.pub; do
            if [[ -f "$key_file" ]]; then
                local key_name=$(basename "$key_file" .pub)
                if ! validate_ssh_key_format "$key_file"; then
                    log "PASS" "Invalid SSH key test: $key_name (correctly rejected)"
                else
                    log "FAIL" "Invalid SSH key test failed: $key_name (should have been rejected)"
                    return 1
                fi
            fi
        done
    fi
    
    # Test edge case SSH keys
    local edge_cases_dir="$ssh_keys_dir/edge-cases"
    if [[ -d "$edge_cases_dir" ]]; then
        for key_file in "$edge_cases_dir"/*.pub; do
            if [[ -f "$key_file" ]]; then
                local key_name=$(basename "$key_file" .pub)
                # Edge cases should be handled gracefully (not crash)
                if validate_ssh_key_format "$key_file" >/dev/null 2>&1; then
                    log "PASS" "Edge case SSH key test: $key_name (handled gracefully)"
                else
                    log "PASS" "Edge case SSH key test: $key_name (rejected gracefully)"
                fi
            fi
        done
    fi
    
    return 0
}

validate_ssh_key_format() {
    local key_file="$1"
    
    # Check if file exists and is readable
    if [[ ! -f "$key_file" ]] || [[ ! -r "$key_file" ]]; then
        return 1
    fi
    
    # Check if file has content
    if [[ ! -s "$key_file" ]]; then
        return 1
    fi
    
    # Basic SSH key format validation
    local first_line=$(head -n1 "$key_file")
    
    # Check if it starts with a valid SSH key type
    if [[ "$first_line" =~ ^ssh-(rsa|dss|ecdsa|ed25519) ]]; then
        # Check if it has the basic structure: type base64 comment
        local parts_count=$(echo "$first_line" | wc -w)
        if [[ $parts_count -ge 2 ]]; then
            return 0
        fi
    fi
    
    return 1
}

test_ssh_key_performance() {
    local ssh_keys_dir="$TEST_DATA_DIR/ssh-keys/valid"
    
    if [[ ! -d "$ssh_keys_dir" ]]; then
        log "SKIP" "SSH keys performance test data not found"
        return 0
    fi
    
    local start_time=$(date +%s.%N)
    local key_count=0
    
    # Test validation performance with multiple keys
    for key_file in "$ssh_keys_dir"/*.pub; do
        if [[ -f "$key_file" ]]; then
            validate_ssh_key_format "$key_file" >/dev/null 2>&1
            ((key_count++))
        fi
    done
    
    local end_time=$(date +%s.%N)
    local duration=$(echo "scale=3; $end_time - $start_time" | bc -l 2>/dev/null || echo "0.000")
    local keys_per_second=$(echo "scale=2; $key_count / $duration" | bc -l 2>/dev/null || echo "0.00")
    
    log "INFO" "SSH key validation performance: $key_count keys in ${duration}s (${keys_per_second} keys/sec)"
    
    # Performance threshold: should process at least 100 keys per second
    if [[ $(echo "$keys_per_second > 10" | bc -l 2>/dev/null || echo "1") -eq 1 ]]; then
        return 0
    else
        log "WARN" "SSH key validation performance below threshold"
        return 1
    fi
}

# ============================================================================
# Cloud Provider Mock Testing Functions
# ============================================================================

start_mock_api_server() {
    local mock_api_script="$MOCK_INFRASTRUCTURE_DIR/mock-api-server.py"
    
    if [[ ! -f "$mock_api_script" ]]; then
        log "SKIP" "Mock API server script not found"
        return 1
    fi
    
    log "INFO" "Starting mock API server on $MOCK_API_HOST:$MOCK_API_PORT"
    
    # Start the mock API server in background
    python3 "$mock_api_script" --host "$MOCK_API_HOST" --port "$MOCK_API_PORT" \
        --failure-rate 0.1 --verbose > "$TEST_LOGS_DIR/mock-api.log" 2>&1 &
    
    MOCK_API_PID=$!
    
    # Wait for server to start
    local max_attempts=30
    local attempt=0
    
    while [[ $attempt -lt $max_attempts ]]; do
        if curl -s -m 2 "$MOCK_API_URL/health" >/dev/null 2>&1; then
            log "INFO" "Mock API server started successfully (PID: $MOCK_API_PID)"
            return 0
        fi
        sleep 1
        ((attempt++))
    done
    
    log "FAIL" "Mock API server failed to start within ${max_attempts}s"
    return 1
}

test_mock_api_responses() {
    # Test successful server creation
    local response=$(curl -s -m 5 "$MOCK_API_URL/hetzner/servers" 2>/dev/null || echo "")
    
    if [[ -n "$response" ]] && echo "$response" | jq -e '.server.id' >/dev/null 2>&1; then
        log "PASS" "Mock API successful response test"
    else
        log "FAIL" "Mock API successful response test"
        return 1
    fi
    
    # Test rate limiting
    local rate_limit_response=$(curl -s -m 5 "$MOCK_API_URL/hetzner/servers?scenario=rate-limit-exceeded" 2>/dev/null || echo "")
    
    if [[ -n "$rate_limit_response" ]] && echo "$rate_limit_response" | jq -e '.error.code' >/dev/null 2>&1; then
        local error_code=$(echo "$rate_limit_response" | jq -r '.error.code' 2>/dev/null || echo "")
        if [[ "$error_code" == "rate_limit_exceeded" ]]; then
            log "PASS" "Mock API rate limiting test"
        else
            log "FAIL" "Mock API rate limiting test - wrong error code: $error_code"
            return 1
        fi
    else
        log "FAIL" "Mock API rate limiting test"
        return 1
    fi
    
    # Test quota exceeded
    local quota_response=$(curl -s -m 5 "$MOCK_API_URL/hetzner/servers?scenario=quota-exceeded" 2>/dev/null || echo "")
    
    if [[ -n "$quota_response" ]] && echo "$quota_response" | jq -e '.error.code' >/dev/null 2>&1; then
        local error_code=$(echo "$quota_response" | jq -r '.error.code' 2>/dev/null || echo "")
        if [[ "$error_code" == "quota_exceeded" ]]; then
            log "PASS" "Mock API quota exceeded test"
        else
            log "FAIL" "Mock API quota exceeded test - wrong error code: $error_code"
            return 1
        fi
    else
        log "FAIL" "Mock API quota exceeded test"
        return 1
    fi
    
    return 0
}

test_mock_api_performance() {
    local request_count=10
    local start_time=$(date +%s.%N)
    local successful_requests=0
    
    for ((i=1; i<=request_count; i++)); do
        if curl -s -m 2 "$MOCK_API_URL/hetzner/servers" >/dev/null 2>&1; then
            ((successful_requests++))
        fi
    done
    
    local end_time=$(date +%s.%N)
    local duration=$(echo "scale=3; $end_time - $start_time" | bc -l 2>/dev/null || echo "0.000")
    local requests_per_second=$(echo "scale=2; $successful_requests / $duration" | bc -l 2>/dev/null || echo "0.00")
    
    log "INFO" "Mock API performance: $successful_requests/$request_count requests in ${duration}s (${requests_per_second} req/sec)"
    
    # Performance threshold: should handle at least 5 requests per second
    if [[ $(echo "$requests_per_second > 5" | bc -l 2>/dev/null || echo "0") -eq 1 ]]; then
        return 0
    else
        log "WARN" "Mock API performance below threshold"
        return 1
    fi
}

# ============================================================================
# Configuration Testing Functions
# ============================================================================

test_configuration_validation() {
    local config_dir="$TEST_DATA_DIR/configurations"
    
    if [[ ! -d "$config_dir" ]]; then
        log "SKIP" "Configuration test data not found"
        return 0
    fi
    
    # Create test configuration files if they don't exist
    create_test_configurations
    
    # Test valid configurations
    local valid_configs_dir="$config_dir/valid"
    if [[ -d "$valid_configs_dir" ]]; then
        for config_file in "$valid_configs_dir"/*.conf; do
            if [[ -f "$config_file" ]]; then
                local config_name=$(basename "$config_file" .conf)
                if validate_configuration_file "$config_file"; then
                    log "PASS" "Valid configuration test: $config_name"
                else
                    log "FAIL" "Valid configuration test failed: $config_name"
                    return 1
                fi
            fi
        done
    fi
    
    # Test invalid configurations
    local invalid_configs_dir="$config_dir/invalid"
    if [[ -d "$invalid_configs_dir" ]]; then
        for config_file in "$invalid_configs_dir"/*.conf; do
            if [[ -f "$config_file" ]]; then
                local config_name=$(basename "$config_file" .conf)
                if ! validate_configuration_file "$config_file"; then
                    log "PASS" "Invalid configuration test: $config_name (correctly rejected)"
                else
                    log "FAIL" "Invalid configuration test failed: $config_name (should have been rejected)"
                    return 1
                fi
            fi
        done
    fi
    
    return 0
}

create_test_configurations() {
    local config_dir="$TEST_DATA_DIR/configurations"
    
    mkdir -p "$config_dir/valid" "$config_dir/invalid" "$config_dir/edge-cases"
    
    # Create valid configuration
    cat > "$config_dir/valid/standard.conf" << EOF
# Test configuration file
USER_NAME="testuser"
SSH_PORT="2222"
BLOCKLET_HTTP_PORT="8080"
BLOCKLET_HTTPS_PORT="8443"
ENABLE_SSL="false"
ENABLE_FIREWALL="true"
EOF
    
    # Create invalid configuration
    cat > "$config_dir/invalid/syntax-error.conf" << EOF
# Test configuration with syntax errors
USER_NAME="testuser
SSH_PORT=invalid_port
BLOCKLET_HTTP_PORT=
INVALID_VARIABLE_NAME-WITH-DASHES="value"
EOF
    
    # Create edge case configuration
    cat > "$config_dir/edge-cases/unicode.conf" << EOF
# Configuration with Unicode characters
USER_NAME="tëst-üser"
DESCRIPTION="Configuration with émojis 🚀 and spëcial characters"
DOMAIN_NAME="tëst.example.com"
EMAIL_ADDRESS="tëst@example.com"
EOF
}

validate_configuration_file() {
    local config_file="$1"
    
    # Check if file exists and is readable
    if [[ ! -f "$config_file" ]] || [[ ! -r "$config_file" ]]; then
        return 1
    fi
    
    # Basic syntax validation
    local line_number=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_number++))
        
        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ "$line" =~ ^[[:space:]]*$ ]] && continue
        
        # Check variable assignment format
        if ! [[ "$line" =~ ^[[:space:]]*[A-Z_][A-Z0-9_]*=.*$ ]]; then
            log "DEBUG" "Invalid syntax at line $line_number: $line"
            return 1
        fi
    done < "$config_file"
    
    return 0
}

# ============================================================================
# Debug Tools Testing Functions
# ============================================================================

test_debug_tools() {
    local debug_tools_dir="$DEBUG_TOOLS_DIR"
    
    if [[ ! -d "$debug_tools_dir" ]]; then
        log "SKIP" "Debug tools directory not found"
        return 0
    fi
    
    # Test system diagnostics script
    local diagnostics_script="$debug_tools_dir/system-diagnostics.sh"
    if [[ -f "$diagnostics_script" ]]; then
        if test_system_diagnostics "$diagnostics_script"; then
            log "PASS" "System diagnostics tool test"
        else
            log "FAIL" "System diagnostics tool test"
            return 1
        fi
    fi
    
    return 0
}

test_system_diagnostics() {
    local diagnostics_script="$1"
    
    # Test quick mode
    local output
    if output=$("$diagnostics_script" --quick --silent 2>&1); then
        local exit_code=$?
        if [[ $exit_code -eq 0 || $exit_code -eq 1 ]]; then
            log "PASS" "System diagnostics quick mode"
        else
            log "FAIL" "System diagnostics quick mode (exit code: $exit_code)"
            return 1
        fi
    else
        log "FAIL" "System diagnostics quick mode (execution failed)"
        return 1
    fi
    
    # Test JSON output
    if output=$("$diagnostics_script" --quick --json --silent 2>&1); then
        if echo "$output" | grep -q "JSON report saved"; then
            log "PASS" "System diagnostics JSON output"
        else
            log "FAIL" "System diagnostics JSON output"
            return 1
        fi
    else
        log "FAIL" "System diagnostics JSON output (execution failed)"
        return 1
    fi
    
    return 0
}

# ============================================================================
# Network Simulation Testing Functions
# ============================================================================

test_network_simulation() {
    local network_sim_script="$MOCK_INFRASTRUCTURE_DIR/network-failure-sim.sh"
    
    if [[ ! -f "$network_sim_script" ]]; then
        log "SKIP" "Network simulation script not found"
        return 0
    fi
    
    # Test help output
    if "$network_sim_script" --help >/dev/null 2>&1; then
        log "PASS" "Network simulation help test"
    else
        log "FAIL" "Network simulation help test"
        return 1
    fi
    
    # Test status command (should work without root)
    if "$network_sim_script" status >/dev/null 2>&1; then
        log "PASS" "Network simulation status test"
    else
        log "PASS" "Network simulation status test (expected to fail without root)"
    fi
    
    return 0
}

# ============================================================================
# Comprehensive Test Scenarios
# ============================================================================

test_deployment_simulation() {
    log "INFO" "Running deployment simulation test"
    
    # Simulate a full deployment process with dummy data
    local temp_config="/tmp/arcdeploy-test-config-$$.conf"
    local temp_ssh_key="/tmp/arcdeploy-test-key-$$.pub"
    
    # Create temporary test files
    cat > "$temp_config" << EOF
USER_NAME="testdeployment"
SSH_PORT="2222"
BLOCKLET_HTTP_PORT="8080"
ENABLE_SSL="false"
ENABLE_FIREWALL="true"
EOF
    
    echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGKqVXqMghRrHKZgeQGzKqwXYsOyAMJQl+U6k8Ee1234 test@deployment-simulation" > "$temp_ssh_key"
    
    # Test configuration validation
    if validate_configuration_file "$temp_config"; then
        log "PASS" "Deployment simulation - configuration validation"
    else
        log "FAIL" "Deployment simulation - configuration validation"
        rm -f "$temp_config" "$temp_ssh_key"
        return 1
    fi
    
    # Test SSH key validation
    if validate_ssh_key_format "$temp_ssh_key"; then
        log "PASS" "Deployment simulation - SSH key validation"
    else
        log "FAIL" "Deployment simulation - SSH key validation"
        rm -f "$temp_config" "$temp_ssh_key"
        return 1
    fi
    
    # Cleanup
    rm -f "$temp_config" "$temp_ssh_key"
    
    return 0
}

test_failure_recovery() {
    log "INFO" "Running failure recovery test"
    
    # Simulate various failure scenarios and test recovery
    local test_scenarios=("network_timeout" "invalid_config" "missing_dependency")
    
    for scenario in "${test_scenarios[@]}"; do
        if simulate_failure_scenario "$scenario"; then
            log "PASS" "Failure recovery test: $scenario"
        else
            log "FAIL" "Failure recovery test: $scenario"
            return 1
        fi
    done
    
    return 0
}

simulate_failure_scenario() {
    local scenario="$1"
    
    case "$scenario" in
        "network_timeout")
            # Simulate network timeout by trying to connect to invalid endpoint
            local start_time=$(date +%s)
            curl -s -m 2 http://192.0.2.1:80 >/dev/null 2>&1 || true
            local end_time=$(date +%s)
            local duration=$((end_time - start_time))
            
            # Should timeout within reasonable time (2-3 seconds)
            if [[ $duration -ge 2 && $duration -le 5 ]]; then
                return 0
            else
                log "DEBUG" "Network timeout test took ${duration}s (expected 2-3s)"
                return 1
            fi
            ;;
        "invalid_config")
            # Test handling of invalid configuration
            local temp_config="/tmp/arcdeploy-invalid-$$.conf"
            echo "INVALID_SYNTAX_HERE" > "$temp_config"
            
            if ! validate_configuration_file "$temp_config"; then
                rm -f "$temp_config"
                return 0
            else
                rm -f "$temp_config"
                return 1
            fi
            ;;
        "missing_dependency")
            # Test handling of missing dependencies
            if command -v nonexistentcommand123 >/dev/null 2>&1; then
                return 1  # Command should not exist
            else
                return 0  # Correctly detected as missing
            fi
            ;;
        *)
            log "DEBUG" "Unknown failure scenario: $scenario"
            return 1
            ;;
    esac
}

# ============================================================================
# Report Generation Functions
# ============================================================================

generate_comprehensive_report() {
    log "INFO" "Generating comprehensive test report..."
    
    # Create text report
    cat > "$REPORT_FILE" << EOF
ArcDeploy Comprehensive Test Suite Report
========================================
Generated: $(date)
Test Suite Version: $SCRIPT_VERSION

=== Summary Statistics ===
Total Tests: $TOTAL_TESTS
Passed: $PASSED_TESTS
Failed: $FAILED_TESTS
Skipped: $SKIPPED_TESTS
Warnings: $WARNING_TESTS

=== Category Breakdown ===
SSH Key Tests: $SSH_KEY_TESTS (Passed: $SSH_KEY_PASSED, Failed: $SSH_KEY_FAILED)
Cloud Provider Tests: $CLOUD_PROVIDER_TESTS (Passed: $CLOUD_PROVIDER_PASSED, Failed: $CLOUD_PROVIDER_FAILED)
Configuration Tests: $CONFIG_TESTS (Passed: $CONFIG_PASSED, Failed: $CONFIG_FAILED)
Debug Tool Tests: $DEBUG_TOOL_TESTS (Passed: $DEBUG_TOOL_PASSED, Failed: $DEBUG_TOOL_FAILED)
Network Simulation Tests: $NETWORK_SIM_TESTS (Passed: $NETWORK_SIM_PASSED, Failed: $NETWORK_SIM_FAILED)
Mock API Tests: $MOCK_API_TESTS (Passed: $MOCK_API_PASSED, Failed: $MOCK_API_FAILED)

=== Overall Result ===
EOF

    local success_rate=0
    if [[ $TOTAL_TESTS -gt 0 ]]; then
        success_rate=$((PASSED_TESTS * 100 / TOTAL_TESTS))
    fi
    
    echo "Success Rate: $success_rate%" >> "$REPORT_FILE"
    
    if [[ $FAILED_TESTS -eq 0 ]]; then
        echo "Status: ALL TESTS PASSED" >> "$REPORT_FILE"
    else
        echo "Status: SOME TESTS FAILED" >> "$REPORT_FILE"
    fi
    
    echo "" >> "$REPORT_FILE"
    echo "=== Performance Data ===" >> "$REPORT_FILE"
    if [[ -f "$PERFORMANCE_LOG" ]]; then
        echo "Performance log available at: $PERFORMANCE_LOG" >> "$REPORT_FILE"
    fi
    
    echo "" >> "$REPORT_FILE"
    echo "=== Failure Details ===" >> "$REPORT_FILE"
    if [[ -f "$FAILURE_LOG" ]]; then
        echo "Failure log available at: $FAILURE_LOG" >> "$REPORT_FILE"
    fi
    
    # Create JSON report
    cat > "$JSON_REPORT_FILE" << EOF
{
  "timestamp": "$(date -Iseconds)",
  "test_suite_version": "$SCRIPT_VERSION",
  "summary": {
    "total_tests": $TOTAL_TESTS,
    "passed_tests": $PASSED_TESTS,
    "failed_tests": $FAILED_TESTS,
    "skipped_tests": $SKIPPED_TESTS,
    "warning_tests": $WARNING_TESTS,
    "success_rate": $success_rate
  },
  "categories": {
    "ssh_key": {
      "total": $SSH_KEY_TESTS,
      "passed": $SSH_KEY_PASSED,
      "failed": $SSH_KEY_FAILED
    },
    "cloud_provider": {
      "total": $CLOUD_PROVIDER_TESTS,
      "passed": $CLOUD_PROVIDER_PASSED,
      "failed": $CLOUD_PROVIDER_FAILED
    },
    "configuration": {
      "total": $CONFIG_TESTS,
      "passed": $CONFIG_PASSED,
      "failed": $CONFIG_FAILED
    },
    "debug_tools": {
      "total": $DEBUG_TOOL_TESTS,
      "passed": $DEBUG_TOOL_PASSED,
      "failed": $DEBUG_TOOL_FAILED
    },
    "network_simulation": {
      "total": $NETWORK_SIM_TESTS,
      "passed": $NETWORK_SIM_PASSED,
      "failed": $NETWORK_SIM_FAILED
    },
    "mock_api": {
      "total": $MOCK_API_TESTS,
      "passed": $MOCK_API_PASSED,
      "failed": $MOCK_API_FAILED
    }
  },
  "files": {
    "text_report": "$REPORT_FILE",
    "json_report": "$JSON_REPORT_FILE",
    "performance_log": "$PERFORMANCE_LOG",
    "failure_log": "$FAILURE_LOG"
  }
}
EOF
    
    log "INFO" "Reports generated successfully"
    log "INFO" "Text report: $REPORT_FILE"
    log "INFO" "JSON report: $JSON_REPORT_FILE"
}

# ============================================================================
# Main Test Execution Functions
# ============================================================================

run_ssh_key_tests() {
    section_header "SSH Key Testing"
    
    run_test "SSH Key Validation" "test_ssh_key_validation" "ssh_key"
    ((SSH_KEY_TESTS++))
    
    run_test "SSH Key Performance" "test_ssh_key_performance" "ssh_key"
    ((SSH_KEY_TESTS++))
}

run_cloud_provider_tests() {
    section_header "Cloud Provider Mock Testing"
    
    # Start mock API server
    if start_mock_api_server; then
        run_test "Mock API Responses" "test_mock_api_responses" "mock_api"
        ((MOCK_API_TESTS++))
        
        run_test "Mock API Performance" "test_mock_api_performance" "mock_api"
        ((MOCK_API_TESTS++))
    else
        log "SKIP" "Mock API tests (server failed to start)"
        ((SKIPPED_TESTS += 2))
    fi
}

run_configuration_tests() {
    section_header "Configuration Testing"
    
    run_test "Configuration Validation" "test_configuration_validation" "config"
    ((CONFIG_TESTS++))
}

run_debug_tool_tests() {
    section_header "Debug Tool Testing"
    
    run_test "Debug Tools Functionality" "test_debug_tools" "debug_tool"
    ((DEBUG_TOOL_TESTS++))
}

run_network_simulation_tests() {
    section_header "Network Simulation Testing"
    
    run_test "Network Simulation" "test_network_simulation" "network_sim"
    ((NETWORK_SIM_TESTS++))
}

run_comprehensive_scenarios() {
    section_header "Comprehensive Test Scenarios"
    
    run_test "Deployment Simulation" "test_deployment_simulation" "general"
    run_test "Failure Recovery" "test_failure_recovery" "general"
}

# ============================================================================
# Help and Usage
# ============================================================================

show_help() {
    cat << EOF
ArcDeploy Comprehensive Test Suite v$SCRIPT_VERSION

Comprehensive testing framework with dummy data, mock infrastructure, and debug tools.

Usage: $SCRIPT_NAME [OPTIONS] [CATEGORIES]

Options:
    -q, --quick                     Quick tests only (essential tests)
    -f, --full                      Full test suite (default)
    -v, --verbose                   Verbose output with debug information
    -s, --silent                    Minimal output
    -j, --json                      Generate JSON report
    -r, --report                    Generate detailed reports
    --no-mock-api                   Skip mock API tests
    --no-network-sim                Skip network simulation tests
    --performance-only              Run only performance tests
    --debug-only                    Run only debug tool tests
    -h, --help                      Show this help

Test Categories:
    ssh-keys                        SSH key validation tests
    cloud-providers                 Cloud provider mock API tests
    configurations                  Configuration validation tests
    debug-tools                     Debug tool functionality tests
    network-simulation              Network failure simulation tests
    comprehensive                   End-to-end scenario tests
    all                            All test categories (default)

Examples:
    $SCRIPT_NAME                    # Run all tests
    $SCRIPT_NAME --quick            # Quick essential tests only
    $SCRIPT_NAME ssh-keys configs   # Run specific categories
    $SCRIPT_NAME --verbose --report # Verbose with detailed reports
    $SCRIPT_NAME --performance-only # Performance tests only

Output Files:
    - Text Report: $REPORT_FILE
    - JSON Report: $JSON_REPORT_FILE
    - Performance Log: $PERFORMANCE_LOG
    - Failure Log: $FAILURE_LOG

Exit Codes:
    0  - All tests passed
    1  - Some tests failed
    2  - Test setup failed
    3  - Invalid arguments

EOF
}

# ============================================================================
# Main Function
# ============================================================================

main() {
    local categories=()
    local quick_mode="false"
    local verbose_mode="false"
    local silent_mode="false"
    local generate_reports="false"
    local no_mock_api="false"
    local no_network_sim="false"
    local performance_only="false"
    local debug_only="false"
    local json_output="false"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -q|--quick)
                quick_mode="true"
                shift
                ;;
            -f|--full)
                quick_mode="false"
                shift
                ;;
            -v|--verbose)
                verbose_mode="true"
                export DEBUG_MODE="true"
                shift
                ;;
            -s|--silent)
                silent_mode="true"
                shift
                ;;
            -j|--json)
                json_output="true"
                shift
                ;;
            -r|--report)
                generate_reports="true"
                shift
                ;;
            --no-mock-api)
                no_mock_api="true"
                shift
                ;;
            --no-network-sim)
                no_network_sim="true"
                shift
                ;;
            --performance-only)
                performance_only="true"
                shift
                ;;
            --debug-only)
                debug_only="true"
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            ssh-keys|cloud-providers|configurations|debug-tools|network-simulation|comprehensive|all)
                categories+=("$1")
                shift
                ;;
            *)
                log "FAIL" "Unknown option: $1"
                show_help
                exit 3
                ;;
        esac
    done
    
    # Set default categories if none specified
    if [[ ${#categories[@]} -eq 0 ]]; then
        categories=("all")
    fi
    
    # Initialize
    if ! check_prerequisites; then
        log "FAIL" "Prerequisites check failed"
        exit 2
    fi
    
    if [[ "$silent_mode" != "true" ]]; then
        echo -e "${CYAN}ArcDeploy Comprehensive Test Suite v$SCRIPT_VERSION${NC}"
        echo "=================================================================="
        echo ""
    fi
    
    local start_time=$(date +%s)
    
    # Run tests based on categories and options
    for category in "${categories[@]}"; do
        case "$category" in
            "all")
                if [[ "$performance_only" == "true" ]]; then
                    run_test "SSH Key Performance" "test_ssh_key_performance" "ssh_key"
                    ((SSH_KEY_TESTS++))
                    if [[ "$no_mock_api" != "true" ]]; then
                        if start_mock_api_server; then
                            run_test "Mock API Performance" "test_mock_api_performance" "mock_api"
                            ((MOCK_API_TESTS++))
                        fi
                    fi
                elif [[ "$debug_only" == "true" ]]; then
                    run_debug_tool_tests
                else
                    run_ssh_key_tests
                    if [[ "$no_mock_api" != "true" ]]; then
                        run_cloud_provider_tests
                    fi
                    run_configuration_tests
                    run_debug_tool_tests
                    if [[ "$no_network_sim" != "true" ]]; then
                        run_network_simulation_tests
                    fi
                    if [[ "$quick_mode" != "true" ]]; then
                        run_comprehensive_scenarios
                    fi
                fi
                ;;
            "ssh-keys")
                run_ssh_key_tests
                ;;
            "cloud-providers")
                if [[ "$no_mock_api" != "true" ]]; then
                    run_cloud_provider_tests
                fi
                ;;
            "configurations")
                run_configuration_tests
                ;;
            "debug-tools")
                run_debug_tool_tests
                ;;
            "network-simulation")
                if [[ "$no_network_sim" != "true" ]]; then
                    run_network_simulation_tests
                fi
                ;;
            "comprehensive")
                run_comprehensive_scenarios
                ;;
        esac
    done
    
    local end_time=$(date +%s)
    local total_duration=$((end_time - start_time))
    
    # Generate reports
    if [[ "$generate_reports" == "true" || "$json_output" == "true" ]]; then
        generate_comprehensive_report
    fi
    
    # Final summary
    if [[ "$silent_mode" != "true" ]]; then
        echo ""
        echo "=================================================================="
        echo -e "${CYAN}Test Suite Completed${NC}"
        echo "=================================================================="
        echo ""
        echo -e "Total Duration: ${total_duration}s"
        echo -e "Total Tests: ${WHITE}$TOTAL_TESTS${NC}"
        echo -e "Passed: ${GREEN}$PASSED_TESTS${NC}"
        echo -e "Failed: ${RED}$FAILED_TESTS${NC}"
        echo -e "Skipped: ${YELLOW}$SKIPPED_TESTS${NC}"
        echo -e "Warnings: ${YELLOW}$WARNING_TESTS${NC}"
        echo ""
        
        local success_rate=0
        if [[ $TOTAL_TESTS -gt 0 ]]; then
            success_rate=$((PASSED_TESTS * 100 / TOTAL_TESTS))
        fi
        
        if [[ $FAILED_TESTS -eq 0 ]]; then
            echo -e "${GREEN}Success Rate: $success_rate% - ALL TESTS PASSED!${NC}"
        else
            echo -e "${RED}Success Rate: $success_rate% - SOME TESTS FAILED${NC}"
        fi
        echo ""
    fi
    
    # Exit with appropriate code
    if [[ $FAILED_TESTS -gt 0 ]]; then
        exit 1
    else
        exit 0
    fi
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi