#!/bin/bash

# ArcDeploy Performance Benchmarking Suite
# Comprehensive performance testing framework for measuring and analyzing system performance
# under various conditions including dummy data processing and debug tool execution

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
readonly BENCHMARK_RESULTS_DIR="$PROJECT_ROOT/test-results/performance-benchmarks"
readonly BENCHMARK_LOGS_DIR="$BENCHMARK_RESULTS_DIR/logs"
readonly BENCHMARK_DATA_DIR="$BENCHMARK_RESULTS_DIR/data"
readonly TEST_DATA_DIR="$PROJECT_ROOT/test-data"
readonly DEBUG_TOOLS_DIR="$PROJECT_ROOT/debug-tools"

# ============================================================================
# Configuration
# ============================================================================
readonly BENCHMARK_LOG="$BENCHMARK_LOGS_DIR/benchmark.log"
readonly PERFORMANCE_DATA="$BENCHMARK_DATA_DIR/performance.csv"
readonly SYSTEM_METRICS="$BENCHMARK_DATA_DIR/system-metrics.csv"
readonly COMPARISON_REPORT="$BENCHMARK_RESULTS_DIR/performance-comparison.txt"
readonly JSON_REPORT="$BENCHMARK_RESULTS_DIR/benchmark-report.json"

# Benchmark parameters
readonly DEFAULT_ITERATIONS="10"
readonly DEFAULT_WARMUP_RUNS="3"
readonly DEFAULT_TIMEOUT="300"
readonly MONITORING_INTERVAL="1"

# Performance thresholds
readonly CPU_USAGE_THRESHOLD="80"
readonly MEMORY_USAGE_THRESHOLD="75"
readonly DISK_IO_THRESHOLD="90"
readonly LOAD_AVERAGE_THRESHOLD="4.0"

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
# Global State Management
# ============================================================================
declare -g TOTAL_BENCHMARKS=0
declare -g SUCCESSFUL_BENCHMARKS=0
declare -g FAILED_BENCHMARKS=0
declare -g SKIPPED_BENCHMARKS=0

declare -g CURRENT_BENCHMARK=""
declare -g BENCHMARK_START_TIME=""
declare -g SYSTEM_BASELINE=""

# Performance tracking
declare -A BENCHMARK_RESULTS=()
declare -A BASELINE_METRICS=()
declare -A CURRENT_METRICS=()

# ============================================================================
# Logging and Output Functions
# ============================================================================

log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        "INFO")
            echo -e "${BLUE}[INFO]${NC} $message" | tee -a "$BENCHMARK_LOG"
            ;;
        "SUCCESS")
            echo -e "${GREEN}[SUCCESS]${NC} $message" | tee -a "$BENCHMARK_LOG"
            ;;
        "FAILURE")
            echo -e "${RED}[FAILURE]${NC} $message" | tee -a "$BENCHMARK_LOG"
            ;;
        "WARNING")
            echo -e "${YELLOW}[WARNING]${NC} $message" | tee -a "$BENCHMARK_LOG"
            ;;
        "BENCHMARK")
            echo -e "${PURPLE}[BENCHMARK]${NC} $message" | tee -a "$BENCHMARK_LOG"
            ;;
        "METRIC")
            echo -e "${CYAN}[METRIC]${NC} $message" | tee -a "$BENCHMARK_LOG"
            ;;
        "DEBUG")
            if [[ "${DEBUG_MODE:-false}" == "true" ]]; then
                echo -e "${WHITE}[DEBUG]${NC} $message" | tee -a "$BENCHMARK_LOG"
            fi
            ;;
    esac
    
    echo "[$timestamp] [$level] $message" >> "$BENCHMARK_LOG"
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

progress_indicator() {
    local current="$1"
    local total="$2"
    local benchmark_name="$3"
    local width=50
    local percentage=$((current * 100 / total))
    local filled=$((width * current / total))
    
    printf "\r${BLUE}Benchmarking %s:${NC} [" "$benchmark_name"
    printf "%*s" $filled | tr ' ' '='
    printf "%*s" $((width - filled)) | tr ' ' '-'
    printf "] %d%% (%d/%d)" $percentage $current $total
}

# ============================================================================
# Utility Functions
# ============================================================================

initialize_benchmark_framework() {
    log "INFO" "Initializing Performance Benchmark Framework v$SCRIPT_VERSION"
    
    # Create necessary directories
    mkdir -p "$BENCHMARK_RESULTS_DIR" "$BENCHMARK_LOGS_DIR" "$BENCHMARK_DATA_DIR"
    
    # Initialize log files
    echo "Performance Benchmark Framework - Session started $(date)" > "$BENCHMARK_LOG"
    
    # Initialize CSV files with headers
    echo "timestamp,benchmark_name,operation,iteration,duration_ms,cpu_usage,memory_usage,disk_io,load_avg,exit_code" > "$PERFORMANCE_DATA"
    echo "timestamp,cpu_usage,memory_usage,memory_available,disk_usage,disk_io_read,disk_io_write,load_avg_1m,load_avg_5m,load_avg_15m,network_rx,network_tx" > "$SYSTEM_METRICS"
    
    # Check prerequisites
    check_benchmark_prerequisites
    
    # Establish baseline metrics
    establish_system_baseline
    
    log "INFO" "Benchmark framework initialization completed"
}

check_benchmark_prerequisites() {
    local missing_tools=()
    local required_tools=("time" "bc" "awk" "free" "df" "uptime" "ps" "iostat" "vmstat")
    local optional_tools=("stress" "stress-ng" "htop" "iotop")
    
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing_tools+=("$tool")
        fi
    done
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log "FAILURE" "Missing required tools: ${missing_tools[*]}"
        log "INFO" "Install with: apt-get install sysstat procps coreutils"
        exit 1
    fi
    
    local missing_optional=()
    for tool in "${optional_tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing_optional+=("$tool")
        fi
    done
    
    if [[ ${#missing_optional[@]} -gt 0 ]]; then
        log "WARNING" "Missing optional tools: ${missing_optional[*]}"
        log "INFO" "Install with: apt-get install stress-ng htop iotop"
    fi
}

establish_system_baseline() {
    log "INFO" "Establishing system performance baseline..."
    
    # Collect baseline system metrics
    local cpu_idle=$(vmstat 1 3 | tail -1 | awk '{print 100-$15}')
    local memory_used=$(free | awk '/^Mem:/ {printf "%.1f", ($3/$2) * 100}')
    local disk_usage=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
    local load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
    
    BASELINE_METRICS["cpu_usage"]="$cpu_idle"
    BASELINE_METRICS["memory_usage"]="$memory_used"
    BASELINE_METRICS["disk_usage"]="$disk_usage"
    BASELINE_METRICS["load_avg"]="$load_avg"
    
    SYSTEM_BASELINE="CPU: ${cpu_idle}%, Memory: ${memory_used}%, Disk: ${disk_usage}%, Load: ${load_avg}"
    
    log "METRIC" "System baseline established: $SYSTEM_BASELINE"
}

# ============================================================================
# System Monitoring Functions
# ============================================================================

start_system_monitoring() {
    local duration="$1"
    local benchmark_name="$2"
    
    log "DEBUG" "Starting system monitoring for $benchmark_name (${duration}s)"
    
    # Start background monitoring
    (
        local end_time=$(($(date +%s) + duration))
        while [[ $(date +%s) -lt $end_time ]]; do
            collect_system_metrics "$benchmark_name"
            sleep "$MONITORING_INTERVAL"
        done
    ) &
    
    echo $!
}

collect_system_metrics() {
    local benchmark_name="$1"
    local timestamp=$(date -Iseconds)
    
    # CPU usage
    local cpu_usage=$(vmstat 1 2 | tail -1 | awk '{print 100-$15}' 2>/dev/null || echo "0")
    
    # Memory metrics
    local memory_info
    memory_info=$(free -m)
    local memory_usage=$(echo "$memory_info" | awk '/^Mem:/ {printf "%.1f", ($3/$2) * 100}' 2>/dev/null || echo "0")
    local memory_available=$(echo "$memory_info" | awk '/^Mem:/ {print $7}' 2>/dev/null || echo "0")
    
    # Disk metrics
    local disk_usage=$(df / | awk 'NR==2 {print $5}' | sed 's/%//' 2>/dev/null || echo "0")
    
    # I/O metrics (if iostat available)
    local disk_io_read="0"
    local disk_io_write="0"
    if command -v iostat >/dev/null 2>&1; then
        local io_stats
        io_stats=$(iostat -d 1 2 | tail -n +4 | head -1)
        disk_io_read=$(echo "$io_stats" | awk '{print $3}' 2>/dev/null || echo "0")
        disk_io_write=$(echo "$io_stats" | awk '{print $4}' 2>/dev/null || echo "0")
    fi
    
    # Load averages
    local load_averages
    load_averages=$(uptime | awk -F'load average:' '{print $2}' | sed 's/^[[:space:]]*//')
    local load_avg_1m=$(echo "$load_averages" | awk '{print $1}' | sed 's/,//' 2>/dev/null || echo "0")
    local load_avg_5m=$(echo "$load_averages" | awk '{print $2}' | sed 's/,//' 2>/dev/null || echo "0")
    local load_avg_15m=$(echo "$load_averages" | awk '{print $3}' 2>/dev/null || echo "0")
    
    # Network metrics (basic)
    local network_rx="0"
    local network_tx="0"
    if [[ -f /proc/net/dev ]]; then
        local net_stats
        net_stats=$(awk '/eth0|enp|ens/ {rx+=$2; tx+=$10} END {print rx, tx}' /proc/net/dev 2>/dev/null || echo "0 0")
        network_rx=$(echo "$net_stats" | awk '{print $1}')
        network_tx=$(echo "$net_stats" | awk '{print $2}')
    fi
    
    # Log metrics to CSV
    echo "$timestamp,$cpu_usage,$memory_usage,$memory_available,$disk_usage,$disk_io_read,$disk_io_write,$load_avg_1m,$load_avg_5m,$load_avg_15m,$network_rx,$network_tx" >> "$SYSTEM_METRICS"
    
    # Update current metrics
    CURRENT_METRICS["cpu_usage"]="$cpu_usage"
    CURRENT_METRICS["memory_usage"]="$memory_usage"
    CURRENT_METRICS["disk_usage"]="$disk_usage"
    CURRENT_METRICS["load_avg"]="$load_avg_1m"
}

stop_system_monitoring() {
    local monitor_pid="$1"
    
    if [[ -n "$monitor_pid" ]] && kill -0 "$monitor_pid" 2>/dev/null; then
        kill "$monitor_pid" 2>/dev/null || true
        wait "$monitor_pid" 2>/dev/null || true
        log "DEBUG" "System monitoring stopped"
    fi
}

# ============================================================================
# Core Benchmarking Functions
# ============================================================================

run_benchmark() {
    local benchmark_name="$1"
    local benchmark_function="$2"
    local iterations="${3:-$DEFAULT_ITERATIONS}"
    local warmup_runs="${4:-$DEFAULT_WARMUP_RUNS}"
    
    ((TOTAL_BENCHMARKS++))
    CURRENT_BENCHMARK="$benchmark_name"
    
    log "BENCHMARK" "Starting benchmark: $benchmark_name (${iterations} iterations, ${warmup_runs} warmup runs)"
    
    # Warmup runs
    if [[ $warmup_runs -gt 0 ]]; then
        log "DEBUG" "Performing $warmup_runs warmup runs..."
        for ((i=1; i<=warmup_runs; i++)); do
            $benchmark_function >/dev/null 2>&1 || true
        done
    fi
    
    # Start system monitoring
    local monitor_pid
    monitor_pid=$(start_system_monitoring $((iterations * 10)) "$benchmark_name")
    
    # Run benchmark iterations
    local total_duration=0
    local successful_runs=0
    local failed_runs=0
    
    for ((i=1; i<=iterations; i++)); do
        progress_indicator "$i" "$iterations" "$benchmark_name"
        
        local start_time=$(date +%s.%N)
        local benchmark_output
        local exit_code
        
        if benchmark_output=$(timeout "$DEFAULT_TIMEOUT" $benchmark_function 2>&1); then
            exit_code=$?
        else
            exit_code=124  # timeout exit code
        fi
        
        local end_time=$(date +%s.%N)
        local duration_ms=$(echo "scale=3; ($end_time - $start_time) * 1000" | bc -l 2>/dev/null || echo "999999")
        
        # Collect current system metrics
        collect_system_metrics "$benchmark_name"
        
        # Log performance data
        local timestamp=$(date -Iseconds)
        echo "$timestamp,$benchmark_name,${benchmark_function##*_},$i,$duration_ms,${CURRENT_METRICS[cpu_usage]},${CURRENT_METRICS[memory_usage]},${CURRENT_METRICS[disk_usage]},${CURRENT_METRICS[load_avg]},$exit_code" >> "$PERFORMANCE_DATA"
        
        if [[ $exit_code -eq 0 ]]; then
            ((successful_runs++))
            total_duration=$(echo "scale=3; $total_duration + $duration_ms" | bc -l 2>/dev/null || echo "$total_duration")
        else
            ((failed_runs++))
            log "DEBUG" "Benchmark iteration $i failed with exit code $exit_code"
        fi
    done
    
    # Stop system monitoring
    stop_system_monitoring "$monitor_pid"
    
    # Calculate statistics
    local avg_duration=0
    if [[ $successful_runs -gt 0 ]]; then
        avg_duration=$(echo "scale=3; $total_duration / $successful_runs" | bc -l 2>/dev/null || echo "0")
    fi
    
    # Store results
    BENCHMARK_RESULTS["${benchmark_name}_avg_duration"]="$avg_duration"
    BENCHMARK_RESULTS["${benchmark_name}_successful_runs"]="$successful_runs"
    BENCHMARK_RESULTS["${benchmark_name}_failed_runs"]="$failed_runs"
    BENCHMARK_RESULTS["${benchmark_name}_success_rate"]="$(echo "scale=2; $successful_runs * 100 / $iterations" | bc -l 2>/dev/null || echo "0")"
    
    echo ""  # New line after progress indicator
    
    if [[ $successful_runs -ge $((iterations / 2)) ]]; then
        ((SUCCESSFUL_BENCHMARKS++))
        log "SUCCESS" "$benchmark_name completed: ${avg_duration}ms avg, ${successful_runs}/${iterations} successful runs"
    else
        ((FAILED_BENCHMARKS++))
        log "FAILURE" "$benchmark_name failed: Only ${successful_runs}/${iterations} successful runs"
    fi
}

# ============================================================================
# Specific Benchmark Functions
# ============================================================================

benchmark_ssh_key_validation() {
    local ssh_keys_dir="$TEST_DATA_DIR/ssh-keys/valid"
    
    if [[ ! -d "$ssh_keys_dir" ]]; then
        log "WARNING" "SSH keys test data not found, skipping"
        return 1
    fi
    
    # Validate all SSH keys in the directory
    for key_file in "$ssh_keys_dir"/*.pub; do
        if [[ -f "$key_file" ]]; then
            ssh-keygen -l -f "$key_file" >/dev/null 2>&1 || return 1
        fi
    done
    
    return 0
}

benchmark_config_processing() {
    local config_dir="$TEST_DATA_DIR/configurations"
    
    if [[ ! -d "$config_dir" ]]; then
        log "WARNING" "Configuration test data not found, skipping"
        return 1
    fi
    
    # Process configuration files
    for config_file in "$config_dir"/valid/*.conf; do
        if [[ -f "$config_file" ]]; then
            bash -n "$config_file" >/dev/null 2>&1 || return 1
            source "$config_file" >/dev/null 2>&1 || return 1
        fi
    done
    
    return 0
}

benchmark_system_diagnostics() {
    local diagnostics_script="$DEBUG_TOOLS_DIR/system-diagnostics.sh"
    
    if [[ ! -f "$diagnostics_script" ]]; then
        log "WARNING" "System diagnostics script not found, skipping"
        return 1
    fi
    
    # Run system diagnostics in quick mode
    "$diagnostics_script" --quick --silent >/dev/null 2>&1
    return $?
}

benchmark_mock_api_response() {
    # Simulate processing a mock API response
    local api_response='{"server":{"id":42,"name":"test-server","status":"running"},"meta":{"timestamp":"2024-01-15T10:30:00Z"}}'
    
    # Parse JSON and extract values
    if command -v jq >/dev/null 2>&1; then
        echo "$api_response" | jq -r '.server.id' >/dev/null 2>&1 || return 1
        echo "$api_response" | jq -r '.server.status' >/dev/null 2>&1 || return 1
        echo "$api_response" | jq -r '.meta.timestamp' >/dev/null 2>&1 || return 1
    else
        # Fallback parsing without jq
        echo "$api_response" | grep -o '"id":[0-9]*' >/dev/null 2>&1 || return 1
        echo "$api_response" | grep -o '"status":"[^"]*"' >/dev/null 2>&1 || return 1
    fi
    
    return 0
}

benchmark_file_operations() {
    local temp_dir="/tmp/arcdeploy-benchmark-$$"
    mkdir -p "$temp_dir"
    
    # Create test files
    for i in {1..100}; do
        echo "Test file content $i" > "$temp_dir/test_file_$i.txt"
    done
    
    # Read all files
    for file in "$temp_dir"/*.txt; do
        cat "$file" >/dev/null 2>&1 || { rm -rf "$temp_dir"; return 1; }
    done
    
    # Clean up
    rm -rf "$temp_dir"
    return 0
}

benchmark_network_operations() {
    # Test localhost connectivity
    ping -c 1 -W 1 127.0.0.1 >/dev/null 2>&1 || return 1
    
    # Test HTTP request to localhost
    if command -v curl >/dev/null 2>&1; then
        curl -s -m 2 http://127.0.0.1:80 >/dev/null 2>&1 || true
    fi
    
    # Test DNS resolution
    nslookup localhost >/dev/null 2>&1 || return 1
    
    return 0
}

benchmark_cpu_intensive() {
    # CPU-intensive calculation
    local result=0
    for ((i=1; i<=10000; i++)); do
        result=$((result + i * i))
    done
    
    # Additional CPU work
    if command -v bc >/dev/null 2>&1; then
        echo "scale=20; 4*a(1)" | bc -l >/dev/null 2>&1 || true
    fi
    
    return 0
}

benchmark_memory_intensive() {
    # Allocate and use memory
    local temp_file="/tmp/arcdeploy-memory-test-$$"
    
    # Create a moderately sized file in memory
    dd if=/dev/zero of="$temp_file" bs=1M count=50 2>/dev/null || return 1
    
    # Process the file
    wc -c "$temp_file" >/dev/null 2>&1 || { rm -f "$temp_file"; return 1; }
    md5sum "$temp_file" >/dev/null 2>&1 || { rm -f "$temp_file"; return 1; }
    
    # Clean up
    rm -f "$temp_file"
    return 0
}

benchmark_disk_intensive() {
    local temp_dir="/tmp/arcdeploy-disk-benchmark-$$"
    mkdir -p "$temp_dir"
    
    # Write test
    dd if=/dev/zero of="$temp_dir/test_write.bin" bs=1M count=100 2>/dev/null || { rm -rf "$temp_dir"; return 1; }
    
    # Read test
    dd if="$temp_dir/test_write.bin" of=/dev/null bs=1M 2>/dev/null || { rm -rf "$temp_dir"; return 1; }
    
    # Sync to ensure writes are flushed
    sync
    
    # Clean up
    rm -rf "$temp_dir"
    return 0
}

# ============================================================================
# Stress Testing Functions
# ============================================================================

benchmark_under_stress() {
    local stress_type="$1"
    local benchmark_function="$2"
    local iterations="${3:-5}"
    
    log "BENCHMARK" "Running $benchmark_function under $stress_type stress"
    
    local stress_pid=""
    
    # Start stress condition
    case "$stress_type" in
        "cpu")
            if command -v stress >/dev/null 2>&1; then
                stress --cpu 2 --timeout 60s &
                stress_pid=$!
            fi
            ;;
        "memory")
            if command -v stress >/dev/null 2>&1; then
                stress --vm 1 --vm-bytes 256M --timeout 60s &
                stress_pid=$!
            fi
            ;;
        "io")
            if command -v stress >/dev/null 2>&1; then
                stress --io 4 --timeout 60s &
                stress_pid=$!
            fi
            ;;
    esac
    
    # Wait for stress to take effect
    sleep 2
    
    # Run benchmark under stress
    run_benchmark "${benchmark_function}_under_${stress_type}_stress" "$benchmark_function" "$iterations" 1
    
    # Stop stress
    if [[ -n "$stress_pid" ]]; then
        kill "$stress_pid" 2>/dev/null || true
        wait "$stress_pid" 2>/dev/null || true
    fi
}

# ============================================================================
# Analysis and Reporting Functions
# ============================================================================

analyze_performance_data() {
    log "INFO" "Analyzing performance data..."
    
    if [[ ! -f "$PERFORMANCE_DATA" ]]; then
        log "WARNING" "No performance data found for analysis"
        return 1
    fi
    
    # Calculate statistics for each benchmark
    local benchmarks
    benchmarks=$(tail -n +2 "$PERFORMANCE_DATA" | cut -d',' -f2 | sort -u)
    
    while IFS= read -r benchmark; do
        if [[ -n "$benchmark" ]]; then
            analyze_benchmark_performance "$benchmark"
        fi
    done <<< "$benchmarks"
}

analyze_benchmark_performance() {
    local benchmark_name="$1"
    
    # Extract data for this benchmark
    local benchmark_data
    benchmark_data=$(grep ",$benchmark_name," "$PERFORMANCE_DATA")
    
    if [[ -z "$benchmark_data" ]]; then
        return 1
    fi
    
    # Calculate statistics
    local durations
    durations=$(echo "$benchmark_data" | cut -d',' -f5)
    
    local count=0
    local sum=0
    local min=999999999
    local max=0
    
    while IFS= read -r duration; do
        if [[ -n "$duration" ]] && [[ "$duration" != "duration_ms" ]]; then
            count=$((count + 1))
            sum=$(echo "scale=3; $sum + $duration" | bc -l 2>/dev/null || echo "$sum")
            
            if [[ $(echo "$duration < $min" | bc -l 2>/dev/null || echo "0") -eq 1 ]]; then
                min="$duration"
            fi
            
            if [[ $(echo "$duration > $max" | bc -l 2>/dev/null || echo "0") -eq 1 ]]; then
                max="$duration"
            fi
        fi
    done <<< "$durations"
    
    if [[ $count -gt 0 ]]; then
        local avg
        avg=$(echo "scale=3; $sum / $count" | bc -l 2>/dev/null || echo "0")
        
        log "METRIC" "$benchmark_name: avg=${avg}ms, min=${min}ms, max=${max}ms, count=${count}"
        
        # Store analysis results
        BENCHMARK_RESULTS["${benchmark_name}_analysis_avg"]="$avg"
        BENCHMARK_RESULTS["${benchmark_name}_analysis_min"]="$min"
        BENCHMARK_RESULTS["${benchmark_name}_analysis_max"]="$max"
        BENCHMARK_RESULTS["${benchmark_name}_analysis_count"]="$count"
    fi
}

generate_performance_report() {
    log "INFO" "Generating performance report..."
    
    cat > "$COMPARISON_REPORT" << EOF
ArcDeploy Performance Benchmark Report
=====================================
Generated: $(date)
Framework Version: $SCRIPT_VERSION

=== System Information ===
Hostname: $(hostname)
OS: $(lsb_release -d 2>/dev/null | cut -f2 | tr -d '\t' || echo "Unknown")
Kernel: $(uname -r)
CPU: $(grep "model name" /proc/cpuinfo | head -1 | cut -d: -f2 | sed 's/^ *//' || echo "Unknown")
Memory: $(free -h | awk '/^Mem:/ {print $2}' || echo "Unknown")
Architecture: $(uname -m)

=== System Baseline ===
$SYSTEM_BASELINE

=== Benchmark Summary ===
Total Benchmarks: $TOTAL_BENCHMARKS
Successful: $SUCCESSFUL_BENCHMARKS
Failed: $FAILED_BENCHMARKS
Skipped: $SKIPPED_BENCHMARKS

=== Individual Benchmark Results ===
EOF

    # Add individual benchmark results
    for key in "${!BENCHMARK_RESULTS[@]}"; do
        if [[ "$key" =~ _analysis_avg$ ]]; then
            local benchmark_name="${key%_analysis_avg}"
            echo "Benchmark: $benchmark_name" >> "$COMPARISON_REPORT"
            echo "  Average Duration: ${BENCHMARK_RESULTS[${key}]}ms" >> "$COMPARISON_REPORT"
            echo "  Min Duration: ${BENCHMARK_RESULTS[${benchmark_name}_analysis_min]}ms" >> "$COMPARISON_REPORT"
            echo "  Max Duration: ${BENCHMARK_RESULTS[${benchmark_name}_analysis_max]}ms" >> "$COMPARISON_REPORT"
            echo "  Iterations: ${BENCHMARK_RESULTS[${benchmark_name}_analysis_count]}" >> "$COMPARISON_REPORT"
            echo "" >> "$COMPARISON_REPORT"
        fi
    done
    
    cat >> "$COMPARISON_REPORT" << EOF

=== Performance Thresholds ===
CPU Usage Threshold: ${CPU_USAGE_THRESHOLD}%
Memory Usage Threshold: ${MEMORY_USAGE_THRESHOLD}%
Disk I/O Threshold: ${DISK_IO_THRESHOLD}%
Load Average Threshold: ${LOAD_AVERAGE_THRESHOLD}

=== Data Files ===
Performance Data: $PERFORMANCE_DATA
System Metrics: $SYSTEM_METRICS
Benchmark Log: $BENCHMARK_LOG

=== Recommendations ===
EOF

    # Add recommendations based on results
    if [[ $FAILED_BENCHMARKS -gt 0 ]]; then
        echo "- Investigate $FAILED_BENCHMARKS failed benchmarks" >> "$COMPARISON_REPORT"
    fi
    
    if [[ $SUCCESSFUL_BENCHMARKS -eq $TOTAL_BENCHMARKS ]] && [[ $TOTAL_BENCHMARKS -gt 0 ]]; then
        echo "- All benchmarks passed - system performance is good" >> "$COMPARISON_REPORT"
    fi
    
    echo "- Review system metrics for resource usage patterns" >> "$COMPARISON_REPORT"
    echo "- Consider optimizing slow-performing operations" >> "$COMPARISON_REPORT"
    
    log "INFO" "Performance report generated: $COMPARISON_REPORT"
}

generate_json_report() {
    log "INFO" "Generating JSON performance report..."
    
    cat > "$JSON_REPORT" << EOF
{
  "timestamp": "$(date -Iseconds)",
  "framework_version": "$SCRIPT_VERSION",
  "system_info": {
    "hostname": "$(hostname)",
    "os": "$(lsb_release -d 2>/dev/null | cut -f2 | tr -d '\t' || echo "Unknown")",
    "kernel": "$(uname -r)",
    "cpu": "$(grep "model name" /proc/cpuinfo | head -1 | cut -d: -f2 | sed 's/^ *//' || echo "Unknown")",
    "memory": "$(free -h | awk '/^Mem:/ {print $2}' || echo "Unknown")",
    "architecture": "$(uname -m)"
  },
  "baseline_metrics": {
    "cpu_usage": "${BASELINE_METRICS[cpu_usage]}",
    "memory_usage": "${BASELINE_METRICS[memory_usage]}",
    "disk_usage": "${BASELINE_METRICS[disk_usage]}",
    "load_avg": "${BASELINE_METRICS[load_avg]}"
  },
  "summary": {
    "total_benchmarks": $TOTAL_BENCHMARKS,
    "successful_benchmarks": $SUCCESSFUL_BENCHMARKS,
    "failed_benchmarks": $FAILED_BENCHMARKS,
    "skipped_benchmarks": $SKIPPED_BENCHMARKS
  },
  "benchmark_results": {
EOF

    # Add benchmark results to JSON
    local first_result=true
    for key in "${!BENCHMARK_RESULTS[@]}"; do
        if [[ "$key" =~ _analysis_avg$ ]]; then
            local benchmark_name="${key%_analysis_avg}"
            
            if [[ "$first_result" == "false" ]]; then
                echo "    }," >> "$JSON_REPORT"
            fi
            first_result=false
            
            cat >> "$JSON_REPORT" << EOF
    "$benchmark_name": {
      "average_duration_ms": "${BENCHMARK_RESULTS[$key]}",
      "min_duration_ms": "${BENCHMARK_RESULTS[${benchmark_name}_analysis_min]}",
      "max_duration_ms": "${BENCHMARK_RESULTS[${benchmark_name}_analysis_max]}",
      "iterations": "${BENCHMARK_RESULTS[${benchmark_name}_analysis_count]}",
      "successful_runs": "${BENCHMARK_RESULTS[${benchmark_name}_successful_runs]}",
      "failed_runs": "${BENCHMARK_RESULTS[${benchmark_name}_failed_runs]}",
      "success_rate": "${BENCHMARK_RESULTS[${benchmark_name}_success_rate]}"
EOF
        fi
    done
    
    if [[ "$first_result" == "false" ]]; then
        echo "    }" >> "$JSON_REPORT"
    fi
    
    cat >> "$JSON_REPORT" << EOF
  },
  "data_files": {
    "performance_data": "$PERFORMANCE_DATA",
    "system_metrics": "$SYSTEM_METRICS",
    "benchmark_log": "$BENCHMARK_LOG",
    "comparison_report": "$COMPARISON_REPORT"
  }
}
EOF
    
    log "INFO" "JSON performance report generated: $JSON_REPORT"
}

# ============================================================================
# Help and Usage Functions
# ============================================================================

show_help() {
    cat << EOF
ArcDeploy Performance Benchmark Suite v$SCRIPT_VERSION

Comprehensive performance testing framework for measuring system performance.

Usage: $SCRIPT_NAME [OPTIONS] [BENCHMARKS]

Benchmark Categories:
    ssh-keys                        SSH key validation performance
    configs                         Configuration processing performance
    diagnostics                     System diagnostics performance
    api-responses                   Mock API response processing
    file-ops                        File operations performance
    network-ops                     Network operations performance
    cpu-intensive                   CPU-intensive operations
    memory-intensive                Memory-intensive operations
    disk-intensive                  Disk I/O intensive operations
    stress-cpu                      Performance under CPU stress
    stress-memory                   Performance under memory stress
    stress-io                       Performance under I/O stress
    all                            All benchmark categories (default)

Options:
    --iterations NUM               Number of benchmark iterations ($DEFAULT_ITERATIONS)
    --warmup NUM                   Number of warmup runs ($DEFAULT_WARMUP_RUNS)
    --timeout SECONDS              Benchmark timeout ($DEFAULT_TIMEOUT)
    --json                         Generate JSON report
    --monitoring-interval SEC      System monitoring interval ($MONITORING_INTERVAL)
    --debug                        Enable debug output
    -h, --help                     Show this help

Examples:
    $SCRIPT_NAME                   # Run all benchmarks
    $SCRIPT_NAME ssh-keys configs  # Run specific benchmarks
    $SCRIPT_NAME --iterations 20   # Run with more iterations
    $SCRIPT_NAME --json all        # Generate JSON report

Output Files:
    - Performance Report: $COMPARISON_REPORT
    - JSON Report: $JSON_REPORT
    - Performance Data: $PERFORMANCE_DATA
    - System Metrics: $SYSTEM_METRICS

EOF
}

# ============================================================================
# Main Function
# ============================================================================

main() {
    local benchmarks=()
    local iterations="$DEFAULT_ITERATIONS"
    local warmup_runs="$DEFAULT_WARMUP_RUNS"
    local timeout="$DEFAULT_TIMEOUT"
    local generate_json="false"
    local monitoring_interval="$MONITORING_INTERVAL"
    local debug_mode="false"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --iterations)
                iterations="$2"
                shift 2
                ;;
            --warmup)
                warmup_runs="$2"
                shift 2
                ;;
            --timeout)
                timeout="$2"
                shift 2
                ;;
            --json)
                generate_json="true"
                shift
                ;;
            --monitoring-interval)
                monitoring_interval="$2"
                shift 2
                ;;
            --debug)
                debug_mode="true"
                export DEBUG_MODE="true"
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            ssh-keys|configs|diagnostics|api-responses|file-ops|network-ops|cpu-intensive|memory-intensive|disk-intensive|stress-cpu|stress-memory|stress-io|all)
                benchmarks+=("$1")
                shift
                ;;
            *)
                log "FAILURE" "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # Set default benchmarks if none specified
    if [[ ${#benchmarks[@]} -eq 0 ]]; then
        benchmarks=("all")
    fi
    
    # Initialize framework
    initialize_benchmark_framework
    
    section_header "ArcDeploy Performance Benchmark Suite v$SCRIPT_VERSION"
    log "INFO" "Starting performance benchmarks: ${benchmarks[*]}"
    log "INFO" "Configuration: iterations=$iterations, warmup=$warmup_runs, timeout=$timeout"
    
    # Run benchmarks based on categories
    for category in "${benchmarks[@]}"; do
        case "$category" in
            "all")
                # Run all benchmarks
                run_benchmark "SSH Key Validation" "benchmark_ssh_key_validation" "$iterations" "$warmup_runs"
                run_benchmark "Configuration Processing" "benchmark_config_processing" "$iterations" "$warmup_runs"
                run_benchmark "System Diagnostics" "benchmark_system_diagnostics" "$iterations" "$warmup_runs"
                run_benchmark "Mock API Response" "benchmark_mock_api_response" "$iterations" "$warmup_runs"
                run_benchmark "File Operations" "benchmark_file_operations" "$iterations" "$warmup_runs"
                run_benchmark "Network Operations" "benchmark_network_operations" "$iterations" "$warmup_runs"
                run_benchmark "CPU Intensive" "benchmark_cpu_intensive" "$iterations" "$warmup_runs"
                run_benchmark "Memory Intensive" "benchmark_memory_intensive" "$iterations" "$warmup_runs"
                run_benchmark "Disk Intensive" "benchmark_disk_intensive" "$iterations" "$warmup_runs"
                
                # Stress testing
                benchmark_under_stress "cpu" "benchmark_system_diagnostics" 3
                benchmark_under_stress "memory" "benchmark_config_processing" 3
                benchmark_under_stress "io" "benchmark_file_operations" 3
                ;;
            "ssh-keys")
                run_benchmark "SSH Key Validation" "benchmark_ssh_key_validation" "$iterations" "$warmup_runs"
                ;;
            "configs")
                run_benchmark "Configuration Processing" "benchmark_config_processing" "$iterations" "$warmup_runs"
                ;;
            "diagnostics")
                run_benchmark "System Diagnostics" "benchmark_system_diagnostics" "$iterations" "$warmup_runs"
                ;;
            "api-responses")
                run_benchmark "Mock API Response" "benchmark_mock_api_response" "$iterations" "$warmup_runs"
                ;;
            "file-ops")
                run_benchmark "File Operations" "benchmark_file_operations" "$iterations" "$warmup_runs"
                ;;
            "network-ops")
                run_benchmark "Network Operations" "benchmark_network_operations" "$iterations" "$warmup_runs"
                ;;
            "cpu-intensive")
                run_benchmark "CPU Intensive" "benchmark_cpu_intensive" "$iterations" "$warmup_runs"
                ;;
            "memory-intensive")
                run_benchmark "Memory Intensive" "benchmark_memory_intensive" "$iterations" "$warmup_runs"
                ;;
            "disk-intensive")
                run_benchmark "Disk Intensive" "benchmark_disk_intensive" "$iterations" "$warmup_runs"
                ;;
            "stress-cpu")
                benchmark_under_stress "cpu" "benchmark_system_diagnostics" "$iterations"
                ;;
            "stress-memory")
                benchmark_under_stress "memory" "benchmark_config_processing" "$iterations"
                ;;
            "stress-io")
                benchmark_under_stress "io" "benchmark_file_operations" "$iterations"
                ;;
        esac
    done
    
    # Analyze results
    analyze_performance_data
    
    # Generate reports
    generate_performance_report
    if [[ "$generate_json" == "true" ]]; then
        generate_json_report
    fi
    
    # Final summary
    section_header "Benchmark Summary"
    log "INFO" "Performance benchmarking completed"
    log "INFO" "Total benchmarks: $TOTAL_BENCHMARKS"
    log "INFO" "Successful: $SUCCESSFUL_BENCHMARKS"
    log "INFO" "Failed: $FAILED_BENCHMARKS"
    log "INFO" "Skipped: $SKIPPED_BENCHMARKS"
    
    local overall_success_rate=0
    if [[ $TOTAL_BENCHMARKS -gt 0 ]]; then
        overall_success_rate=$(( (SUCCESSFUL_BENCHMARKS * 100) / TOTAL_BENCHMARKS ))
    fi
    
    if [[ $overall_success_rate -ge 90 ]]; then
        log "SUCCESS" "Excellent performance: $overall_success_rate% success rate"
        exit 0
    elif [[ $overall_success_rate -ge 75 ]]; then
        log "SUCCESS" "Good performance: $overall_success_rate% success rate"
        exit 0
    elif [[ $overall_success_rate -ge 50 ]]; then
        log "WARNING" "Fair performance: $overall_success_rate% success rate"
        exit 1
    else
        log "FAILURE" "Poor performance: $overall_success_rate% success rate"
        exit 2
    fi
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi