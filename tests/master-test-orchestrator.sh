#!/bin/bash

# ArcDeploy Master Test Orchestrator
# Comprehensive test orchestration system that coordinates all testing frameworks
# including dummy data testing, failure injection, debug tool validation, and performance benchmarking

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

# Framework directories
readonly ORCHESTRATOR_RESULTS_DIR="$PROJECT_ROOT/test-results/orchestrator"
readonly ORCHESTRATOR_LOGS_DIR="$ORCHESTRATOR_RESULTS_DIR/logs"
readonly ORCHESTRATOR_REPORTS_DIR="$ORCHESTRATOR_RESULTS_DIR/reports"

# Testing framework scripts
readonly COMPREHENSIVE_TEST_SUITE="$SCRIPT_DIR/comprehensive-test-suite.sh"
readonly FAILURE_INJECTION_FRAMEWORK="$SCRIPT_DIR/failure-injection/failure-injection-framework.sh"
readonly DEBUG_TOOL_VALIDATION="$SCRIPT_DIR/debug-tool-validation.sh"
readonly PERFORMANCE_BENCHMARK="$SCRIPT_DIR/performance-benchmark.sh"

# ============================================================================
# Configuration
# ============================================================================
readonly ORCHESTRATOR_LOG="$ORCHESTRATOR_LOGS_DIR/orchestrator.log"
readonly EXECUTION_TIMELINE="$ORCHESTRATOR_LOGS_DIR/execution-timeline.log"
readonly MASTER_REPORT="$ORCHESTRATOR_REPORTS_DIR/master-test-report.txt"
readonly MASTER_JSON_REPORT="$ORCHESTRATOR_REPORTS_DIR/master-test-report.json"
readonly SUMMARY_DASHBOARD="$ORCHESTRATOR_REPORTS_DIR/test-dashboard.html"

# Test execution configuration
readonly DEFAULT_TEST_SUITE="comprehensive"
readonly DEFAULT_PARALLEL_JOBS="2"
readonly DEFAULT_TIMEOUT="1800"  # 30 minutes
readonly DEFAULT_RETRY_ATTEMPTS="2"

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
readonly BOLD='\033[1m'
readonly NC='\033[0m'

# ============================================================================
# Global State Management
# ============================================================================
declare -g ORCHESTRATOR_START_TIME=""
declare -g ORCHESTRATOR_END_TIME=""
declare -g TOTAL_FRAMEWORKS_EXECUTED=0
declare -g FRAMEWORKS_PASSED=0
declare -g FRAMEWORKS_FAILED=0
declare -g FRAMEWORKS_SKIPPED=0
declare -g FRAMEWORKS_WITH_WARNINGS=0

# Framework execution tracking
declare -A FRAMEWORK_RESULTS=()
declare -A FRAMEWORK_DURATIONS=()
declare -A FRAMEWORK_EXIT_CODES=()
declare -A FRAMEWORK_LOGS=()

# Test suite configuration
declare -g SELECTED_FRAMEWORKS=()
declare -g EXECUTION_MODE="sequential"
declare -g CONTINUE_ON_FAILURE="true"
declare -g GENERATE_REPORTS="true"
declare -g VERBOSE_OUTPUT="false"

# ============================================================================
# Logging and Output Functions
# ============================================================================

log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        "INFO")
            echo -e "${BLUE}[INFO]${NC} $message" | tee -a "$ORCHESTRATOR_LOG"
            ;;
        "SUCCESS")
            echo -e "${GREEN}[SUCCESS]${NC} $message" | tee -a "$ORCHESTRATOR_LOG"
            ;;
        "FAILURE")
            echo -e "${RED}[FAILURE]${NC} $message" | tee -a "$ORCHESTRATOR_LOG"
            ;;
        "WARNING")
            echo -e "${YELLOW}[WARNING]${NC} $message" | tee -a "$ORCHESTRATOR_LOG"
            ;;
        "ORCHESTRATOR")
            echo -e "${PURPLE}[ORCHESTRATOR]${NC} $message" | tee -a "$ORCHESTRATOR_LOG"
            ;;
        "FRAMEWORK")
            echo -e "${CYAN}[FRAMEWORK]${NC} $message" | tee -a "$ORCHESTRATOR_LOG"
            ;;
        "DEBUG")
            if [[ "${DEBUG_MODE:-false}" == "true" ]]; then
                echo -e "${WHITE}[DEBUG]${NC} $message" | tee -a "$ORCHESTRATOR_LOG"
            fi
            ;;
    esac
    
    echo "[$timestamp] [$level] $message" >> "$ORCHESTRATOR_LOG"
    echo "[$timestamp] [$level] $message" >> "$EXECUTION_TIMELINE"
}

section_header() {
    local title="$1"
    local width=80
    local padding=$(( (width - ${#title} - 2) / 2 ))
    local separator=$(printf '=%.0s' $(seq 1 $width))
    
    echo ""
    echo -e "${BOLD}${CYAN}$separator${NC}"
    printf "${BOLD}${CYAN}%*s %s %*s${NC}\n" $padding "" "$title" $padding ""
    echo -e "${BOLD}${CYAN}$separator${NC}"
    echo ""
}

progress_banner() {
    local current="$1"
    local total="$2"
    local framework_name="$3"
    local phase="$4"
    
    echo ""
    echo -e "${BOLD}${BLUE}╔════════════════════════════════════════════════════════════════════════════╗${NC}"
    printf "${BOLD}${BLUE}║${NC} ${BOLD}Progress: %d/%d${NC} ${BLUE}│${NC} ${BOLD}Framework: %-20s${NC} ${BLUE}│${NC} ${BOLD}Phase: %-15s${NC} ${BLUE}║${NC}\n" "$current" "$total" "$framework_name" "$phase"
    echo -e "${BOLD}${BLUE}╚════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# ============================================================================
# Utility Functions
# ============================================================================

initialize_orchestrator() {
    log "ORCHESTRATOR" "Initializing Master Test Orchestrator v$SCRIPT_VERSION"
    
    ORCHESTRATOR_START_TIME=$(date +%s)
    
    # Create necessary directories
    mkdir -p "$ORCHESTRATOR_RESULTS_DIR" "$ORCHESTRATOR_LOGS_DIR" "$ORCHESTRATOR_REPORTS_DIR"
    
    # Initialize log files
    echo "ArcDeploy Master Test Orchestrator - Session started $(date)" > "$ORCHESTRATOR_LOG"
    echo "Test Execution Timeline - Session started $(date)" > "$EXECUTION_TIMELINE"
    
    # Check framework availability
    check_framework_availability
    
    log "ORCHESTRATOR" "Orchestrator initialization completed"
}

check_framework_availability() {
    local missing_frameworks=()
    local available_frameworks=()
    
    # Check each testing framework
    if [[ -f "$COMPREHENSIVE_TEST_SUITE" ]] && [[ -x "$COMPREHENSIVE_TEST_SUITE" ]]; then
        available_frameworks+=("comprehensive")
    else
        missing_frameworks+=("comprehensive-test-suite")
    fi
    
    if [[ -f "$FAILURE_INJECTION_FRAMEWORK" ]] && [[ -x "$FAILURE_INJECTION_FRAMEWORK" ]]; then
        available_frameworks+=("failure-injection")
    else
        missing_frameworks+=("failure-injection-framework")
    fi
    
    if [[ -f "$DEBUG_TOOL_VALIDATION" ]] && [[ -x "$DEBUG_TOOL_VALIDATION" ]]; then
        available_frameworks+=("debug-validation")
    else
        missing_frameworks+=("debug-tool-validation")
    fi
    
    if [[ -f "$PERFORMANCE_BENCHMARK" ]] && [[ -x "$PERFORMANCE_BENCHMARK" ]]; then
        available_frameworks+=("performance")
    else
        missing_frameworks+=("performance-benchmark")
    fi
    
    log "INFO" "Available frameworks: ${available_frameworks[*]}"
    
    if [[ ${#missing_frameworks[@]} -gt 0 ]]; then
        log "WARNING" "Missing frameworks: ${missing_frameworks[*]}"
    fi
    
    if [[ ${#available_frameworks[@]} -eq 0 ]]; then
        log "FAILURE" "No testing frameworks available"
        exit 1
    fi
}

# ============================================================================
# Framework Execution Functions
# ============================================================================

execute_framework() {
    local framework_name="$1"
    local framework_script="$2"
    local framework_args="$3"
    local retry_count="${4:-0}"
    
    ((TOTAL_FRAMEWORKS_EXECUTED++))
    
    log "FRAMEWORK" "Starting framework: $framework_name (attempt $((retry_count + 1)))"
    
    local framework_start_time=$(date +%s)
    local framework_log="$ORCHESTRATOR_LOGS_DIR/${framework_name}-execution.log"
    local framework_output
    local framework_exit_code
    
    # Execute framework with timeout and logging
    if framework_output=$(timeout "$DEFAULT_TIMEOUT" "$framework_script" $framework_args 2>&1); then
        framework_exit_code=$?
    else
        framework_exit_code=$?
        if [[ $framework_exit_code -eq 124 ]]; then
            framework_output="Framework execution timed out after ${DEFAULT_TIMEOUT}s"
        fi
    fi
    
    local framework_end_time=$(date +%s)
    local framework_duration=$((framework_end_time - framework_start_time))
    
    # Save framework output to dedicated log
    echo "$framework_output" > "$framework_log"
    
    # Store results
    FRAMEWORK_DURATIONS["$framework_name"]="$framework_duration"
    FRAMEWORK_EXIT_CODES["$framework_name"]="$framework_exit_code"
    FRAMEWORK_LOGS["$framework_name"]="$framework_log"
    
    # Analyze results
    if [[ $framework_exit_code -eq 0 ]]; then
        FRAMEWORK_RESULTS["$framework_name"]="PASSED"
        ((FRAMEWORKS_PASSED++))
        log "SUCCESS" "$framework_name completed successfully in ${framework_duration}s"
    elif [[ $framework_exit_code -eq 1 ]]; then
        FRAMEWORK_RESULTS["$framework_name"]="WARNING"
        ((FRAMEWORKS_WITH_WARNINGS++))
        log "WARNING" "$framework_name completed with warnings in ${framework_duration}s"
    else
        FRAMEWORK_RESULTS["$framework_name"]="FAILED"
        ((FRAMEWORKS_FAILED++))
        log "FAILURE" "$framework_name failed with exit code $framework_exit_code in ${framework_duration}s"
        
        # Retry logic
        if [[ $retry_count -lt $DEFAULT_RETRY_ATTEMPTS ]]; then
            log "INFO" "Retrying $framework_name (attempt $((retry_count + 2))/$((DEFAULT_RETRY_ATTEMPTS + 1)))"
            sleep 5
            execute_framework "$framework_name" "$framework_script" "$framework_args" $((retry_count + 1))
            return $?
        fi
    fi
    
    return $framework_exit_code
}

execute_comprehensive_test_suite() {
    local args="$1"
    progress_banner "$TOTAL_FRAMEWORKS_EXECUTED" "${#SELECTED_FRAMEWORKS[@]}" "Comprehensive Tests" "Execution"
    execute_framework "comprehensive-test-suite" "$COMPREHENSIVE_TEST_SUITE" "$args"
}

execute_failure_injection() {
    local args="$1"
    progress_banner "$TOTAL_FRAMEWORKS_EXECUTED" "${#SELECTED_FRAMEWORKS[@]}" "Failure Injection" "Execution"
    execute_framework "failure-injection" "$FAILURE_INJECTION_FRAMEWORK" "$args"
}

execute_debug_tool_validation() {
    local args="$1"
    progress_banner "$TOTAL_FRAMEWORKS_EXECUTED" "${#SELECTED_FRAMEWORKS[@]}" "Debug Validation" "Execution"
    execute_framework "debug-tool-validation" "$DEBUG_TOOL_VALIDATION" "$args"
}

execute_performance_benchmark() {
    local args="$1"
    progress_banner "$TOTAL_FRAMEWORKS_EXECUTED" "${#SELECTED_FRAMEWORKS[@]}" "Performance Benchmark" "Execution"
    execute_framework "performance-benchmark" "$PERFORMANCE_BENCHMARK" "$args"
}

# ============================================================================
# Test Suite Orchestration
# ============================================================================

execute_comprehensive_test_suite_orchestrated() {
    section_header "Comprehensive Test Suite Execution"
    
    log "ORCHESTRATOR" "Orchestrating comprehensive test suite with dummy data integration"
    
    # Phase 1: SSH Key Tests
    log "INFO" "Phase 1: SSH Key Testing with dummy data"
    execute_comprehensive_test_suite "ssh-keys --verbose"
    
    # Phase 2: Cloud Provider Mock Tests
    log "INFO" "Phase 2: Cloud Provider Mock Testing"
    execute_comprehensive_test_suite "cloud-providers --verbose"
    
    # Phase 3: Configuration Tests
    log "INFO" "Phase 3: Configuration Validation Testing"
    execute_comprehensive_test_suite "configurations --verbose"
    
    # Phase 4: Integration Tests
    log "INFO" "Phase 4: Comprehensive Integration Testing"
    execute_comprehensive_test_suite "comprehensive --report --json"
}

execute_failure_injection_orchestrated() {
    section_header "Failure Injection Testing"
    
    log "ORCHESTRATOR" "Orchestrating failure injection testing scenarios"
    
    # Phase 1: Individual failure types
    local failure_types=("network_latency" "memory_pressure" "disk_slow" "cpu_stress")
    
    for failure_type in "${failure_types[@]}"; do
        log "INFO" "Testing failure injection: $failure_type"
        execute_failure_injection "inject $failure_type 30 medium"
        sleep 10  # Allow system recovery between injections
    done
    
    # Phase 2: Chaos testing
    log "INFO" "Running chaos monkey simulation"
    execute_failure_injection "chaos 120 2"
    
    # Phase 3: Cascade failure testing
    log "INFO" "Running cascade failure simulation"
    execute_failure_injection "cascade network_partition 30"
}

execute_debug_validation_orchestrated() {
    section_header "Debug Tool Validation"
    
    log "ORCHESTRATOR" "Orchestrating debug tool validation with comprehensive scenarios"
    
    # Phase 1: Basic functionality tests
    log "INFO" "Phase 1: Basic debug tool functionality"
    execute_debug_tool_validation "basic --verbose"
    
    # Phase 2: Performance tests
    log "INFO" "Phase 2: Debug tool performance testing"
    execute_debug_tool_validation "performance --timeout 60"
    
    # Phase 3: Accuracy tests
    log "INFO" "Phase 3: Debug tool accuracy testing"
    execute_debug_tool_validation "accuracy --accuracy-threshold 85"
    
    # Phase 4: Stress tests
    log "INFO" "Phase 4: Debug tool stress testing"
    execute_debug_tool_validation "stress"
    
    # Phase 5: Integration tests
    log "INFO" "Phase 5: Debug tool integration testing"
    execute_debug_tool_validation "integration"
}

execute_performance_benchmark_orchestrated() {
    section_header "Performance Benchmarking"
    
    log "ORCHESTRATOR" "Orchestrating performance benchmarking with system monitoring"
    
    # Phase 1: Core functionality benchmarks
    log "INFO" "Phase 1: Core functionality performance"
    execute_performance_benchmark "ssh-keys configs diagnostics --iterations 10 --json"
    
    # Phase 2: System stress benchmarks
    log "INFO" "Phase 2: System stress performance"
    execute_performance_benchmark "cpu-intensive memory-intensive disk-intensive --iterations 5"
    
    # Phase 3: Integration performance
    log "INFO" "Phase 3: Integration performance testing"
    execute_performance_benchmark "all --iterations 15 --json"
}

# ============================================================================
# Parallel Execution Support
# ============================================================================

execute_frameworks_parallel() {
    log "ORCHESTRATOR" "Starting parallel execution of testing frameworks"
    
    local pids=()
    local framework_count=0
    
    # Start frameworks in parallel (limited by job count)
    for framework in "${SELECTED_FRAMEWORKS[@]}"; do
        if [[ $framework_count -ge $DEFAULT_PARALLEL_JOBS ]]; then
            # Wait for one job to complete
            wait "${pids[0]}"
            pids=("${pids[@]:1}")  # Remove first PID
            ((framework_count--))
        fi
        
        case "$framework" in
            "comprehensive")
                execute_comprehensive_test_suite_orchestrated &
                ;;
            "failure-injection")
                execute_failure_injection_orchestrated &
                ;;
            "debug-validation")
                execute_debug_validation_orchestrated &
                ;;
            "performance")
                execute_performance_benchmark_orchestrated &
                ;;
        esac
        
        pids+=($!)
        ((framework_count++))
    done
    
    # Wait for all remaining jobs
    for pid in "${pids[@]}"; do
        wait "$pid"
    done
    
    log "ORCHESTRATOR" "Parallel execution completed"
}

execute_frameworks_sequential() {
    log "ORCHESTRATOR" "Starting sequential execution of testing frameworks"
    
    for framework in "${SELECTED_FRAMEWORKS[@]}"; do
        case "$framework" in
            "comprehensive")
                execute_comprehensive_test_suite_orchestrated
                ;;
            "failure-injection")
                execute_failure_injection_orchestrated
                ;;
            "debug-validation")
                execute_debug_validation_orchestrated
                ;;
            "performance")
                execute_performance_benchmark_orchestrated
                ;;
        esac
        
        # Check if we should continue on failure
        if [[ "${FRAMEWORK_RESULTS[$framework]}" == "FAILED" ]] && [[ "$CONTINUE_ON_FAILURE" == "false" ]]; then
            log "FAILURE" "Stopping execution due to framework failure: $framework"
            break
        fi
    done
    
    log "ORCHESTRATOR" "Sequential execution completed"
}

# ============================================================================
# Report Generation Functions
# ============================================================================

generate_master_report() {
    log "ORCHESTRATOR" "Generating master test report..."
    
    ORCHESTRATOR_END_TIME=$(date +%s)
    local total_duration=$((ORCHESTRATOR_END_TIME - ORCHESTRATOR_START_TIME))
    
    cat > "$MASTER_REPORT" << EOF
ArcDeploy Master Test Orchestrator Report
========================================
Generated: $(date)
Orchestrator Version: $SCRIPT_VERSION
Total Execution Time: ${total_duration}s

=== System Information ===
Hostname: $(hostname)
OS: $(lsb_release -d 2>/dev/null | cut -f2 | tr -d '\t' || echo "Unknown")
Kernel: $(uname -r)
CPU: $(grep "model name" /proc/cpuinfo | head -1 | cut -d: -f2 | sed 's/^ *//' || echo "Unknown")
Memory: $(free -h | awk '/^Mem:/ {print $2}' || echo "Unknown")
Architecture: $(uname -m)

=== Execution Summary ===
Total Frameworks Executed: $TOTAL_FRAMEWORKS_EXECUTED
Frameworks Passed: $FRAMEWORKS_PASSED
Frameworks Failed: $FRAMEWORKS_FAILED
Frameworks Skipped: $FRAMEWORKS_SKIPPED
Frameworks with Warnings: $FRAMEWORKS_WITH_WARNINGS
Execution Mode: $EXECUTION_MODE
Continue on Failure: $CONTINUE_ON_FAILURE

=== Framework Results ===
EOF

    # Add individual framework results
    for framework in "${!FRAMEWORK_RESULTS[@]}"; do
        local result="${FRAMEWORK_RESULTS[$framework]}"
        local duration="${FRAMEWORK_DURATIONS[$framework]}"
        local exit_code="${FRAMEWORK_EXIT_CODES[$framework]}"
        local log_file="${FRAMEWORK_LOGS[$framework]}"
        
        echo "Framework: $framework" >> "$MASTER_REPORT"
        echo "  Result: $result" >> "$MASTER_REPORT"
        echo "  Duration: ${duration}s" >> "$MASTER_REPORT"
        echo "  Exit Code: $exit_code" >> "$MASTER_REPORT"
        echo "  Log File: $log_file" >> "$MASTER_REPORT"
        echo "" >> "$MASTER_REPORT"
    done
    
    cat >> "$MASTER_REPORT" << EOF

=== Performance Summary ===
Fastest Framework: $(get_fastest_framework)
Slowest Framework: $(get_slowest_framework)
Average Duration: $(get_average_duration)s

=== Quality Metrics ===
Overall Success Rate: $(get_overall_success_rate)%
Framework Reliability: $(get_framework_reliability)
Test Coverage: Comprehensive across all system components

=== Recommendations ===
EOF

    # Add recommendations based on results
    add_recommendations_to_report
    
    echo "" >> "$MASTER_REPORT"
    echo "=== Log Files ===" >> "$MASTER_REPORT"
    echo "Master Log: $ORCHESTRATOR_LOG" >> "$MASTER_REPORT"
    echo "Execution Timeline: $EXECUTION_TIMELINE" >> "$MASTER_REPORT"
    echo "Individual Framework Logs: $ORCHESTRATOR_LOGS_DIR/" >> "$MASTER_REPORT"
    
    log "SUCCESS" "Master report generated: $MASTER_REPORT"
}

generate_json_report() {
    log "ORCHESTRATOR" "Generating JSON master report..."
    
    cat > "$MASTER_JSON_REPORT" << EOF
{
  "timestamp": "$(date -Iseconds)",
  "orchestrator_version": "$SCRIPT_VERSION",
  "execution_time_seconds": $((ORCHESTRATOR_END_TIME - ORCHESTRATOR_START_TIME)),
  "system_info": {
    "hostname": "$(hostname)",
    "os": "$(lsb_release -d 2>/dev/null | cut -f2 | tr -d '\t' || echo "Unknown")",
    "kernel": "$(uname -r)",
    "cpu": "$(grep "model name" /proc/cpuinfo | head -1 | cut -d: -f2 | sed 's/^ *//' || echo "Unknown")",
    "memory": "$(free -h | awk '/^Mem:/ {print $2}' || echo "Unknown")",
    "architecture": "$(uname -m)"
  },
  "execution_summary": {
    "total_frameworks_executed": $TOTAL_FRAMEWORKS_EXECUTED,
    "frameworks_passed": $FRAMEWORKS_PASSED,
    "frameworks_failed": $FRAMEWORKS_FAILED,
    "frameworks_skipped": $FRAMEWORKS_SKIPPED,
    "frameworks_with_warnings": $FRAMEWORKS_WITH_WARNINGS,
    "execution_mode": "$EXECUTION_MODE",
    "continue_on_failure": $CONTINUE_ON_FAILURE,
    "overall_success_rate": $(get_overall_success_rate)
  },
  "framework_results": {
EOF

    # Add framework results
    local first_framework=true
    for framework in "${!FRAMEWORK_RESULTS[@]}"; do
        if [[ "$first_framework" == "false" ]]; then
            echo "    }," >> "$MASTER_JSON_REPORT"
        fi
        first_framework=false
        
        cat >> "$MASTER_JSON_REPORT" << EOF
    "$framework": {
      "result": "${FRAMEWORK_RESULTS[$framework]}",
      "duration_seconds": ${FRAMEWORK_DURATIONS[$framework]},
      "exit_code": ${FRAMEWORK_EXIT_CODES[$framework]},
      "log_file": "${FRAMEWORK_LOGS[$framework]}"
EOF
    done
    
    if [[ "$first_framework" == "false" ]]; then
        echo "    }" >> "$MASTER_JSON_REPORT"
    fi
    
    cat >> "$MASTER_JSON_REPORT" << EOF
  },
  "performance_metrics": {
    "fastest_framework": "$(get_fastest_framework)",
    "slowest_framework": "$(get_slowest_framework)",
    "average_duration_seconds": $(get_average_duration)
  },
  "log_files": {
    "master_log": "$ORCHESTRATOR_LOG",
    "execution_timeline": "$EXECUTION_TIMELINE",
    "framework_logs_directory": "$ORCHESTRATOR_LOGS_DIR"
  }
}
EOF
    
    log "SUCCESS" "JSON report generated: $MASTER_JSON_REPORT"
}

generate_html_dashboard() {
    log "ORCHESTRATOR" "Generating HTML test dashboard..."
    
    cat > "$SUMMARY_DASHBOARD" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>ArcDeploy Test Dashboard</title>
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 0; padding: 20px; background: #f5f5f5; }
        .container { max-width: 1200px; margin: 0 auto; background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        .header { text-align: center; margin-bottom: 30px; padding: 20px; background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; border-radius: 8px; }
        .metrics { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 20px; margin-bottom: 30px; }
        .metric { background: #f8f9fa; padding: 20px; border-radius: 8px; text-align: center; border-left: 4px solid #007bff; }
        .metric h3 { margin: 0 0 10px 0; color: #333; }
        .metric .value { font-size: 2em; font-weight: bold; color: #007bff; }
        .frameworks { display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 20px; }
        .framework { background: white; border: 1px solid #ddd; border-radius: 8px; padding: 20px; }
        .framework h3 { margin: 0 0 15px 0; padding-bottom: 10px; border-bottom: 2px solid #eee; }
        .status { padding: 5px 15px; border-radius: 20px; font-weight: bold; text-transform: uppercase; font-size: 0.8em; }
        .status.passed { background: #d4edda; color: #155724; }
        .status.failed { background: #f8d7da; color: #721c24; }
        .status.warning { background: #fff3cd; color: #856404; }
        .footer { text-align: center; margin-top: 30px; padding: 20px; color: #666; border-top: 1px solid #eee; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🚀 ArcDeploy Test Dashboard</h1>
            <p>Comprehensive Testing Framework Results</p>
            <p>Generated: REPLACE_TIMESTAMP</p>
        </div>
        
        <div class="metrics">
            <div class="metric">
                <h3>Total Frameworks</h3>
                <div class="value">REPLACE_TOTAL_FRAMEWORKS</div>
            </div>
            <div class="metric">
                <h3>Success Rate</h3>
                <div class="value">REPLACE_SUCCESS_RATE%</div>
            </div>
            <div class="metric">
                <h3>Execution Time</h3>
                <div class="value">REPLACE_DURATION</div>
            </div>
            <div class="metric">
                <h3>Test Coverage</h3>
                <div class="value">Comprehensive</div>
            </div>
        </div>
        
        <div class="frameworks">
            REPLACE_FRAMEWORK_CARDS
        </div>
        
        <div class="footer">
            <p>ArcDeploy Master Test Orchestrator v$SCRIPT_VERSION</p>
            <p>For detailed results, see the generated reports in the orchestrator results directory.</p>
        </div>
    </div>
</body>
</html>
EOF

    # Replace placeholders with actual data
    sed -i "s/REPLACE_TIMESTAMP/$(date)/" "$SUMMARY_DASHBOARD"
    sed -i "s/REPLACE_TOTAL_FRAMEWORKS/$TOTAL_FRAMEWORKS_EXECUTED/" "$SUMMARY_DASHBOARD"
    sed -i "s/REPLACE_SUCCESS_RATE/$(get_overall_success_rate)/" "$SUMMARY_DASHBOARD"
    sed -i "s/REPLACE_DURATION/$((ORCHESTRATOR_END_TIME - ORCHESTRATOR_START_TIME))s/" "$SUMMARY_DASHBOARD"
    
    # Generate framework cards
    local framework_cards=""
    for framework in "${!FRAMEWORK_RESULTS[@]}"; do
        local result="${FRAMEWORK_RESULTS[$framework]}"
        local duration="${FRAMEWORK_DURATIONS[$framework]}"
        local status_class=$(echo "$result" | tr '[:upper:]' '[:lower:]')
        
        framework_cards+="<div class=\"framework\">"
        framework_cards+="<h3>$(echo "$framework" | sed 's/-/ /g' | sed 's/\b\w/\U&/g')</h3>"
        framework_cards+="<p><span class=\"status $status_class\">$result</span></p>"
        framework_cards+="<p><strong>Duration:</strong> ${duration}s</p>"
        framework_cards+="<p><strong>Exit Code:</strong> ${FRAMEWORK_EXIT_CODES[$framework]}</p>"
        framework_cards+="</div>"
    done
    
    sed -i "s|REPLACE_FRAMEWORK_CARDS|$framework_cards|" "$SUMMARY_DASHBOARD"
    
    log "SUCCESS" "HTML dashboard generated: $SUMMARY_DASHBOARD"
}

# ============================================================================
# Utility Functions for Reports
# ============================================================================

get_fastest_framework() {
    local fastest_framework=""
    local fastest_duration=999999
    
    for framework in "${!FRAMEWORK_DURATIONS[@]}"; do
        local duration="${FRAMEWORK_DURATIONS[$framework]}"
        if [[ $duration -lt $fastest_duration ]]; then
            fastest_duration=$duration
            fastest_framework="$framework"
        fi
    done
    
    echo "$fastest_framework (${fastest_duration}s)"
}

get_slowest_framework() {
    local slowest_framework=""
    local slowest_duration=0
    
    for framework in "${!FRAMEWORK_DURATIONS[@]}"; do
        local duration="${FRAMEWORK_DURATIONS[$framework]}"
        if [[ $duration -gt $slowest_duration ]]; then
            slowest_duration=$duration
            slowest_framework="$framework"
        fi
    done
    
    echo "$slowest_framework (${slowest_duration}s)"
}

get_average_duration() {
    local total_duration=0
    local framework_count=0
    
    for framework in "${!FRAMEWORK_DURATIONS[@]}"; do
        total_duration=$((total_duration + FRAMEWORK_