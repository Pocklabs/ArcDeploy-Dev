#!/bin/bash

# ArcDeploy Failure Injection Testing Framework
# Comprehensive failure injection system for testing resilience and recovery mechanisms
# This framework simulates real-world failure scenarios for thorough testing

set -euo pipefail

# ============================================================================
# Script Metadata
# ============================================================================
readonly SCRIPT_VERSION="1.0.0"
readonly SCRIPT_NAME="$(basename "$0")"

# Directory setup
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
readonly PROJECT_ROOT

# Framework directories
readonly FAILURE_SCENARIOS_DIR="$SCRIPT_DIR/scenarios"
readonly FAILURE_LOGS_DIR="$PROJECT_ROOT/test-results/failure-injection"
readonly FAILURE_CONFIGS_DIR="$SCRIPT_DIR/configs"
readonly RECOVERY_SCRIPTS_DIR="$SCRIPT_DIR/recovery"

# ============================================================================
# Configuration
# ============================================================================
readonly INJECTION_LOG="$FAILURE_LOGS_DIR/injection.log"
readonly RECOVERY_LOG="$FAILURE_LOGS_DIR/recovery.log"
readonly RESULTS_LOG="$FAILURE_LOGS_DIR/results.log"
readonly METRICS_LOG="$FAILURE_LOGS_DIR/metrics.log"

# Failure categories
readonly FAILURE_CATEGORIES=("network" "disk" "memory" "cpu" "service" "security" "config")

# Injection parameters
readonly DEFAULT_DURATION="60"
readonly DEFAULT_INTENSITY="medium"
readonly DEFAULT_RECOVERY_TIMEOUT="300"

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
declare -g CURRENT_FAILURES=()
declare -g ACTIVE_INJECTIONS=()
declare -g RECOVERY_PROCEDURES=()
declare -g FAILURE_STACK=()
declare -g INJECTION_START_TIME=""
declare -g CLEANUP_REQUIRED="false"

# Metrics tracking
declare -g TOTAL_INJECTIONS=0
declare -g SUCCESSFUL_INJECTIONS=0
declare -g FAILED_INJECTIONS=0
declare -g RECOVERY_SUCCESSES=0
declare -g RECOVERY_FAILURES=0

# ============================================================================
# Logging and Output Functions
# ============================================================================

log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        "INFO")
            echo -e "${BLUE}[INFO]${NC} $message" | tee -a "$INJECTION_LOG"
            ;;
        "SUCCESS")
            echo -e "${GREEN}[SUCCESS]${NC} $message" | tee -a "$INJECTION_LOG"
            ;;
        "FAILURE")
            echo -e "${RED}[FAILURE]${NC} $message" | tee -a "$INJECTION_LOG"
            ;;
        "WARNING")
            echo -e "${YELLOW}[WARNING]${NC} $message" | tee -a "$INJECTION_LOG"
            ;;
        "INJECT")
            echo -e "${PURPLE}[INJECT]${NC} $message" | tee -a "$INJECTION_LOG"
            ;;
        "RECOVER")
            echo -e "${CYAN}[RECOVER]${NC} $message" | tee -a "$RECOVERY_LOG"
            ;;
        "DEBUG")
            if [[ "${DEBUG_MODE:-false}" == "true" ]]; then
                echo -e "${WHITE}[DEBUG]${NC} $message" | tee -a "$INJECTION_LOG"
            fi
            ;;
    esac
    
    echo "[$timestamp] [$level] $message" >> "$INJECTION_LOG"
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

# ============================================================================
# Utility Functions
# ============================================================================

initialize_framework() {
    log "INFO" "Initializing Failure Injection Framework v$SCRIPT_VERSION"
    
    # Create necessary directories
    mkdir -p "$FAILURE_LOGS_DIR" "$FAILURE_SCENARIOS_DIR" "$FAILURE_CONFIGS_DIR" "$RECOVERY_SCRIPTS_DIR"
    
    # Initialize log files
    echo "Failure Injection Framework - Session started $(date)" > "$INJECTION_LOG"
    echo "Recovery Operations Log - Session started $(date)" > "$RECOVERY_LOG"
    echo "Results Summary - Session started $(date)" > "$RESULTS_LOG"
    echo "timestamp,injection_type,duration,intensity,success,recovery_time,impact_level" > "$METRICS_LOG"
    
    # Check prerequisites
    check_prerequisites
    
    # Set up cleanup
    trap cleanup_framework EXIT INT TERM
    
    log "INFO" "Framework initialization completed"
}

check_prerequisites() {
    local missing_tools=()
    local required_tools=("tc" "iptables" "stress" "dd" "timeout" "pgrep" "kill")
    
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing_tools+=("$tool")
        fi
    done
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log "WARNING" "Missing optional tools: ${missing_tools[*]}"
        log "INFO" "Install with: apt-get install iproute2 iptables stress-ng coreutils procps"
    fi
    
    # Check permissions for network manipulation
    if [[ $EUID -ne 0 ]]; then
        log "WARNING" "Not running as root - some failure injections will be limited"
        log "INFO" "Run with sudo for full functionality"
    fi
}

cleanup_framework() {
    log "INFO" "Starting framework cleanup..."
    CLEANUP_REQUIRED="true"
    
    # Stop all active injections
    if [[ ${#ACTIVE_INJECTIONS[@]} -gt 0 ]]; then
        log "INFO" "Stopping ${#ACTIVE_INJECTIONS[@]} active injections"
        for injection in "${ACTIVE_INJECTIONS[@]}"; do
            stop_injection "$injection"
        done
    fi
    
    # Execute recovery procedures
    if [[ ${#RECOVERY_PROCEDURES[@]} -gt 0 ]]; then
        log "INFO" "Executing ${#RECOVERY_PROCEDURES[@]} recovery procedures"
        for recovery_proc in "${RECOVERY_PROCEDURES[@]}"; do
            execute_recovery "$recovery_proc"
        done
    fi
    
    # Clean up temporary files
    find /tmp -name "arcdeploy-injection-*" -type f -mmin +60 -delete 2>/dev/null || true
    
    # Generate final report
    generate_session_report
    
    log "INFO" "Framework cleanup completed"
}

# ============================================================================
# Core Failure Injection Functions
# ============================================================================

inject_failure() {
    local failure_type="$1"
    local duration="${2:-$DEFAULT_DURATION}"
    local intensity="${3:-$DEFAULT_INTENSITY}"
    local target="${4:-system}"
    
    ((TOTAL_INJECTIONS++))
    local injection_id="injection_${TOTAL_INJECTIONS}_$$"
    
    log "INJECT" "Starting $failure_type injection (ID: $injection_id, Duration: ${duration}s, Intensity: $intensity)"
    
    INJECTION_START_TIME=$(date +%s)
    ACTIVE_INJECTIONS+=("$injection_id")
    
    case "$failure_type" in
        "network_latency")
            inject_network_latency "$injection_id" "$duration" "$intensity" "$target"
            ;;
        "network_loss")
            inject_network_loss "$injection_id" "$duration" "$intensity" "$target"
            ;;
        "network_partition")
            inject_network_partition "$injection_id" "$duration" "$intensity" "$target"
            ;;
        "disk_full")
            inject_disk_full "$injection_id" "$duration" "$intensity" "$target"
            ;;
        "disk_slow")
            inject_disk_slowdown "$injection_id" "$duration" "$intensity" "$target"
            ;;
        "memory_pressure")
            inject_memory_pressure "$injection_id" "$duration" "$intensity" "$target"
            ;;
        "cpu_stress")
            inject_cpu_stress "$injection_id" "$duration" "$intensity" "$target"
            ;;
        "service_kill")
            inject_service_kill "$injection_id" "$duration" "$intensity" "$target"
            ;;
        "config_corruption")
            inject_config_corruption "$injection_id" "$duration" "$intensity" "$target"
            ;;
        "permission_denial")
            inject_permission_denial "$injection_id" "$duration" "$intensity" "$target"
            ;;
        *)
            log "FAILURE" "Unknown failure type: $failure_type"
            return 1
            ;;
    esac
    
    local injection_result=$?
    
    if [[ $injection_result -eq 0 ]]; then
        ((SUCCESSFUL_INJECTIONS++))
        log "SUCCESS" "Failure injection $injection_id completed successfully"
    else
        ((FAILED_INJECTIONS++))
        log "FAILURE" "Failure injection $injection_id failed"
    fi
    
    # Log metrics
    local end_time=$(date +%s)
    local actual_duration=$((end_time - INJECTION_START_TIME))
    echo "$(date -Iseconds),$failure_type,$actual_duration,$intensity,$injection_result,0,unknown" >> "$METRICS_LOG"
    
    return $injection_result
}

# ============================================================================
# Network Failure Injections
# ============================================================================

inject_network_latency() {
    local injection_id="$1"
    local duration="$2"
    local intensity="$3"
    local target="${4:-lo}"
    
    local delay_ms
    case "$intensity" in
        "low") delay_ms="50" ;;
        "medium") delay_ms="200" ;;
        "high") delay_ms="500" ;;
        "extreme") delay_ms="2000" ;;
        *) delay_ms="$intensity" ;;
    esac
    
    log "INJECT" "Network latency: ${delay_ms}ms on $target for ${duration}s"
    
    # Add network delay
    if tc qdisc add dev "$target" root netem delay "${delay_ms}ms" 50ms 2>/dev/null; then
        RECOVERY_PROCEDURES+=("tc qdisc del dev $target root 2>/dev/null || true")
        
        # Wait for duration
        sleep "$duration"
        
        # Remove delay
        tc qdisc del dev "$target" root 2>/dev/null || true
        
        log "SUCCESS" "Network latency injection completed"
        return 0
    else
        log "FAILURE" "Failed to inject network latency"
        return 1
    fi
}

inject_network_loss() {
    local injection_id="$1"
    local duration="$2"
    local intensity="$3"
    local target="${4:-lo}"
    
    local loss_percent
    case "$intensity" in
        "low") loss_percent="5" ;;
        "medium") loss_percent="15" ;;
        "high") loss_percent="30" ;;
        "extreme") loss_percent="75" ;;
        *) loss_percent="$intensity" ;;
    esac
    
    log "INJECT" "Network packet loss: ${loss_percent}% on $target for ${duration}s"
    
    # Add packet loss
    if tc qdisc add dev "$target" root netem loss "${loss_percent}%" 2>/dev/null; then
        RECOVERY_PROCEDURES+=("tc qdisc del dev $target root 2>/dev/null || true")
        
        # Wait for duration
        sleep "$duration"
        
        # Remove packet loss
        tc qdisc del dev "$target" root 2>/dev/null || true
        
        log "SUCCESS" "Network packet loss injection completed"
        return 0
    else
        log "FAILURE" "Failed to inject network packet loss"
        return 1
    fi
}

inject_network_partition() {
    local injection_id="$1"
    local duration="$2"
    local intensity="$3"
    local target="${4:-8.8.8.8}"
    
    log "INJECT" "Network partition to $target for ${duration}s"
    
    # Create iptables backup
    local backup_file="/tmp/arcdeploy-injection-iptables-$injection_id"
    iptables-save > "$backup_file" 2>/dev/null || {
        log "FAILURE" "Failed to backup iptables rules"
        return 1
    }
    
    # Block traffic to target
    if iptables -A OUTPUT -d "$target" -j DROP 2>/dev/null && iptables -A INPUT -s "$target" -j DROP 2>/dev/null; then
        RECOVERY_PROCEDURES+=("iptables-restore < $backup_file 2>/dev/null || true; rm -f $backup_file")
        
        # Wait for duration
        sleep "$duration"
        
        # Restore iptables
        iptables-restore < "$backup_file" 2>/dev/null || true
        rm -f "$backup_file"
        
        log "SUCCESS" "Network partition injection completed"
        return 0
    else
        log "FAILURE" "Failed to inject network partition"
        return 1
    fi
}

# ============================================================================
# Disk Failure Injections
# ============================================================================

inject_disk_full() {
    local injection_id="$1"
    local duration="$2"
    local intensity="$3"
    local target="${4:-/tmp}"
    
    local fill_size
    case "$intensity" in
        "low") fill_size="100M" ;;
        "medium") fill_size="500M" ;;
        "high") fill_size="1G" ;;
        "extreme") fill_size="5G" ;;
        *) fill_size="$intensity" ;;
    esac
    
    log "INJECT" "Disk space exhaustion: $fill_size in $target for ${duration}s"
    
    local fill_file="/tmp/arcdeploy-injection-diskfill-$injection_id"
    
    # Create large file to fill disk
    if dd if=/dev/zero of="$fill_file" bs=1M count="${fill_size%M}" 2>/dev/null; then
        RECOVERY_PROCEDURES+=("rm -f $fill_file")
        
        # Wait for duration
        sleep "$duration"
        
        # Remove fill file
        rm -f "$fill_file"
        
        log "SUCCESS" "Disk full injection completed"
        return 0
    else
        log "FAILURE" "Failed to inject disk full condition"
        return 1
    fi
}

inject_disk_slowdown() {
    local injection_id="$1"
    local duration="$2"
    local intensity="$3"
    local target="${4:-/tmp}"
    
    log "INJECT" "Disk I/O slowdown simulation for ${duration}s"
    
    # Create background I/O stress
    local stress_file="/tmp/arcdeploy-injection-iostress-$injection_id"
    local stress_pid=""
    
    case "$intensity" in
        "low")
            # Light I/O stress
            (while true; do dd if=/dev/zero of="$stress_file" bs=1M count=10 2>/dev/null; rm -f "$stress_file"; sleep 1; done) &
            stress_pid=$!
            ;;
        "medium")
            # Medium I/O stress
            (while true; do dd if=/dev/zero of="$stress_file" bs=1M count=50 2>/dev/null; rm -f "$stress_file"; sleep 0.5; done) &
            stress_pid=$!
            ;;
        "high")
            # Heavy I/O stress
            (while true; do dd if=/dev/zero of="$stress_file" bs=1M count=100 2>/dev/null; rm -f "$stress_file"; sleep 0.1; done) &
            stress_pid=$!
            ;;
        "extreme")
            # Extreme I/O stress
            (while true; do dd if=/dev/zero of="$stress_file" bs=1M count=200 2>/dev/null; rm -f "$stress_file"; done) &
            stress_pid=$!
            ;;
    esac
    
    if [[ -n "$stress_pid" ]]; then
        RECOVERY_PROCEDURES+=("kill $stress_pid 2>/dev/null || true; rm -f $stress_file")
        
        # Wait for duration
        sleep "$duration"
        
        # Stop stress and cleanup
        kill "$stress_pid" 2>/dev/null || true
        rm -f "$stress_file"
        
        log "SUCCESS" "Disk slowdown injection completed"
        return 0
    else
        log "FAILURE" "Failed to inject disk slowdown"
        return 1
    fi
}

# ============================================================================
# Memory and CPU Failure Injections
# ============================================================================

inject_memory_pressure() {
    local injection_id="$1"
    local duration="$2"
    local intensity="$3"
    local target="$4"
    
    local memory_mb
    case "$intensity" in
        "low") memory_mb="256" ;;
        "medium") memory_mb="512" ;;
        "high") memory_mb="1024" ;;
        "extreme") memory_mb="2048" ;;
        *) memory_mb="$intensity" ;;
    esac
    
    log "INJECT" "Memory pressure: ${memory_mb}MB allocation for ${duration}s"
    
    # Use stress tool if available, otherwise use a simple memory hog
    local stress_pid=""
    
    if command -v stress >/dev/null 2>&1; then
        stress --vm 1 --vm-bytes "${memory_mb}M" --timeout "${duration}s" &
        stress_pid=$!
    else
        # Fallback: Simple memory allocator
        python3 -c "
import time
data = []
try:
    for i in range($memory_mb):
        data.append('A' * 1024 * 1024)  # 1MB chunks
    time.sleep($duration)
except KeyboardInterrupt:
    pass
" &
        stress_pid=$!
    fi
    
    if [[ -n "$stress_pid" ]]; then
        RECOVERY_PROCEDURES+=("kill $stress_pid 2>/dev/null || true")
        
        # Wait for completion
        wait "$stress_pid" 2>/dev/null || true
        
        log "SUCCESS" "Memory pressure injection completed"
        return 0
    else
        log "FAILURE" "Failed to inject memory pressure"
        return 1
    fi
}

inject_cpu_stress() {
    local injection_id="$1"
    local duration="$2"
    local intensity="$3"
    local target="$4"
    
    local cpu_workers
    case "$intensity" in
        "low") cpu_workers="1" ;;
        "medium") cpu_workers="$(nproc)" ;;
        "high") cpu_workers="$(($(nproc) * 2))" ;;
        "extreme") cpu_workers="$(($(nproc) * 4))" ;;
        *) cpu_workers="$intensity" ;;
    esac
    
    log "INJECT" "CPU stress: $cpu_workers workers for ${duration}s"
    
    local stress_pid=""
    
    if command -v stress >/dev/null 2>&1; then
        stress --cpu "$cpu_workers" --timeout "${duration}s" &
        stress_pid=$!
    else
        # Fallback: Simple CPU burner
        for ((i=0; i<cpu_workers; i++)); do
            (timeout "${duration}s" bash -c 'while true; do :; done') &
        done
        stress_pid=$!
    fi
    
    if [[ -n "$stress_pid" ]]; then
        RECOVERY_PROCEDURES+=("pkill -f 'stress --cpu' 2>/dev/null || true")
        
        # Wait for completion
        sleep "$duration"
        pkill -f 'stress --cpu' 2>/dev/null || true
        
        log "SUCCESS" "CPU stress injection completed"
        return 0
    else
        log "FAILURE" "Failed to inject CPU stress"
        return 1
    fi
}

# ============================================================================
# Service and Configuration Failure Injections
# ============================================================================

inject_service_kill() {
    local injection_id="$1"
    local duration="$2"
    local intensity="$3"
    local target="${4:-ssh}"
    
    log "INJECT" "Service kill: $target for ${duration}s"
    
    # Check if service exists and is running
    if ! systemctl is-active --quiet "$target" 2>/dev/null; then
        log "WARNING" "Service $target is not running, skipping injection"
        return 0
    fi
    
    # Stop the service
    if systemctl stop "$target" 2>/dev/null; then
        RECOVERY_PROCEDURES+=("systemctl start $target 2>/dev/null || true")
        
        # Wait for duration
        sleep "$duration"
        
        # Restart the service
        systemctl start "$target" 2>/dev/null || {
            log "FAILURE" "Failed to restart service $target"
            return 1
        }
        
        log "SUCCESS" "Service kill injection completed"
        return 0
    else
        log "FAILURE" "Failed to stop service $target"
        return 1
    fi
}

inject_config_corruption() {
    local injection_id="$1"
    local duration="$2"
    local intensity="$3"
    local target="${4:-/etc/ssh/sshd_config}"
    
    log "INJECT" "Configuration corruption: $target for ${duration}s"
    
    # Create backup
    local backup_file="/tmp/arcdeploy-injection-config-backup-$injection_id"
    if ! cp "$target" "$backup_file" 2>/dev/null; then
        log "FAILURE" "Failed to backup configuration file $target"
        return 1
    fi
    
    # Corrupt the configuration based on intensity
    case "$intensity" in
        "low")
            # Add invalid comment
            echo "# CORRUPTED BY FAILURE INJECTION" >> "$target"
            ;;
        "medium")
            # Add invalid configuration line
            echo "InvalidConfigOption yes" >> "$target"
            ;;
        "high")
            # Truncate file partially
            head -n $(($(wc -l < "$target") / 2)) "$target" > "${target}.tmp"
            mv "${target}.tmp" "$target"
            ;;
        "extreme")
            # Complete corruption
            echo "COMPLETELY CORRUPTED CONFIG FILE" > "$target"
            ;;
    esac
    
    RECOVERY_PROCEDURES+=("cp $backup_file $target 2>/dev/null || true; rm -f $backup_file")
    
    # Wait for duration
    sleep "$duration"
    
    # Restore configuration
    cp "$backup_file" "$target" 2>/dev/null || {
        log "FAILURE" "Failed to restore configuration file $target"
        return 1
    }
    rm -f "$backup_file"
    
    log "SUCCESS" "Configuration corruption injection completed"
    return 0
}

inject_permission_denial() {
    local injection_id="$1"
    local duration="$2"
    local intensity="$3"
    local target="${4:-/tmp/arcdeploy-test-permissions}"
    
    log "INJECT" "Permission denial: $target for ${duration}s"
    
    # Create test file if it doesn't exist
    if [[ ! -f "$target" ]]; then
        echo "Test file for permission injection" > "$target"
    fi
    
    # Store original permissions
    local original_perms
    original_perms=$(stat -c "%a" "$target" 2>/dev/null) || {
        log "FAILURE" "Failed to get permissions for $target"
        return 1
    }
    
    # Apply permission restriction based on intensity
    case "$intensity" in
        "low") chmod 644 "$target" ;;      # Remove execute
        "medium") chmod 444 "$target" ;;   # Read-only
        "high") chmod 000 "$target" ;;     # No permissions
        "extreme") chmod 000 "$target" && chattr +i "$target" 2>/dev/null ;; # Immutable
    esac
    
    RECOVERY_PROCEDURES+=("chmod $original_perms $target 2>/dev/null || true; chattr -i $target 2>/dev/null || true")
    
    # Wait for duration
    sleep "$duration"
    
    # Restore permissions
    chattr -i "$target" 2>/dev/null || true
    chmod "$original_perms" "$target" 2>/dev/null || {
        log "FAILURE" "Failed to restore permissions for $target"
        return 1
    }
    
    log "SUCCESS" "Permission denial injection completed"
    return 0
}

# ============================================================================
# Recovery and Monitoring Functions
# ============================================================================

execute_recovery() {
    local recovery_command="$1"
    local recovery_start=$(date +%s)
    
    log "RECOVER" "Executing recovery: $recovery_command"
    
    if eval "$recovery_command"; then
        local recovery_end=$(date +%s)
        local recovery_time=$((recovery_end - recovery_start))
        ((RECOVERY_SUCCESSES++))
        log "SUCCESS" "Recovery completed in ${recovery_time}s"
        return 0
    else
        ((RECOVERY_FAILURES++))
        log "FAILURE" "Recovery failed: $recovery_command"
        return 1
    fi
}

stop_injection() {
    local injection_id="$1"
    
    log "INFO" "Stopping injection: $injection_id"
    
    # Remove from active injections list
    local new_active=()
    for active in "${ACTIVE_INJECTIONS[@]}"; do
        if [[ "$active" != "$injection_id" ]]; then
            new_active+=("$active")
        fi
    done
    ACTIVE_INJECTIONS=("${new_active[@]}")
    
    log "INFO" "Injection $injection_id stopped"
}

monitor_system_during_injection() {
    local injection_id="$1"
    local monitor_duration="$2"
    
    log "INFO" "Starting system monitoring for injection $injection_id"
    
    local monitor_log="$FAILURE_LOGS_DIR/monitor_${injection_id}.log"
    local end_time=$(($(date +%s) + monitor_duration))
    
    echo "timestamp,cpu_usage,memory_usage,disk_usage,load_avg,network_errors" > "$monitor_log"
    
    while [[ $(date +%s) -lt $end_time ]]; do
        local timestamp=$(date -Iseconds)
        local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%us,//' || echo "0")
        local memory_usage=$(free | awk '/^Mem:/ {printf "%.1f", ($3/$2) * 100}' || echo "0")
        local disk_usage=$(df / | awk 'NR==2 {print $5}' | sed 's/%//' || echo "0")
        local load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//' || echo "0")
        local network_errors=$(cat /proc/net/dev | awk 'NR>2 {sum+=$4+$12} END {print sum+0}' || echo "0")
        
        echo "$timestamp,$cpu_usage,$memory_usage,$disk_usage,$load_avg,$network_errors" >> "$monitor_log"
        sleep 5
    done
    
    log "INFO" "System monitoring completed for injection $injection_id"
}

# ============================================================================
# Test Scenario Functions
# ============================================================================

run_chaos_monkey() {
    local duration="${1:-300}"
    local max_concurrent="${2:-3}"
    
    section_header "Chaos Monkey - Random Failure Injection"
    log "INFO" "Starting Chaos Monkey for ${duration}s with max $max_concurrent concurrent failures"
    
    local end_time=$(($(date +%s) + duration))
    local failure_types=("network_latency" "network_loss" "memory_pressure" "cpu_stress" "disk_slow")
    local intensities=("low" "medium" "high")
    
    while [[ $(date +%s) -lt $end_time ]]; do
        # Check current load
        if [[ ${#ACTIVE_INJECTIONS[@]} -lt $max_concurrent ]]; then
            # Select random failure type and intensity
            local failure_type="${failure_types[$((RANDOM % ${#failure_types[@]}))]}"
            local intensity="${intensities[$((RANDOM % ${#intensities[@]}))]}"
            local failure_duration=$((30 + RANDOM % 120))  # 30-150 seconds
            
            log "INFO" "Chaos Monkey: Injecting $failure_type ($intensity) for ${failure_duration}s"
            
            # Inject failure in background
            (inject_failure "$failure_type" "$failure_duration" "$intensity") &
        fi
        
        # Wait before next potential injection
        sleep $((10 + RANDOM % 20))  # 10-30 seconds
    done
    
    log "INFO" "Chaos Monkey session completed"
}

run_cascade_failure() {
    local initial_failure="${1:-network_partition}"
    local cascade_delay="${2:-30}"
    
    section_header "Cascade Failure Simulation"
    log "INFO" "Starting cascade failure simulation with initial failure: $initial_failure"
    
    # Stage 1: Initial failure
    log "INJECT" "Stage 1: Initial failure injection"
    inject_failure "$initial_failure" "60" "medium" &
    local stage1_pid=$!
    
    sleep "$cascade_delay"
    
    # Stage 2: Secondary failures triggered by initial failure
    log "INJECT" "Stage 2: Secondary failures"
    inject_failure "memory_pressure" "90" "high" &
    local stage2_pid=$!
    
    sleep "$cascade_delay"
    
    # Stage 3: System under stress - more failures
    log "INJECT" "Stage 3: System stress failures"
    inject_failure "disk_slow" "60" "high" &
    inject_failure "cpu_stress" "45" "medium" &
    
    # Wait for all stages to complete
    wait "$stage1_pid" "$stage2_pid" 2>/dev/null || true
    
    log "INFO" "Cascade failure simulation completed"
}

run_resilience_test() {
    local test_duration="${1:-180}"
    
    section_header "System Resilience Test"
    log "INFO" "Starting resilience test for ${test_duration}s"
    
    # Test 1: Gradual load increase
    log "INJECT" "Test 1: Gradual load increase"
    inject_failure "cpu_stress" "60" "low" &
    sleep 20
    inject_failure "memory_pressure" "60" "medium" &
    sleep 20
    inject_failure "disk_slow" "60" "high" &
    
    # Wait for all tests to complete
    sleep "$test_duration"
    
    log "INFO" "System resilience test completed"
}

# ============================================================================
# Report Generation Functions
# ============================================================================

generate_session_report() {
    log "INFO" "Generating session report..."
    
    local session_end=$(date)
    local success_rate=0
    
    if [[ $TOTAL_INJECTIONS -gt 0 ]]; then
        success_rate=$(( (SUCCESSFUL_INJECTIONS * 100) / TOTAL_INJECTIONS ))
    fi
    
    cat > "$RESULTS_LOG" << EOF
ArcDeploy Failure Injection Framework - Session Report
====================================================
Session End: $session_end
Framework Version: $SCRIPT_VERSION

=== Injection Summary ===
Total Injections: $TOTAL_INJECTIONS
Successful: $SUCCESSFUL_INJECTIONS
Failed: $FAILED_INJECTIONS
Success Rate: ${success_rate}%

=== Recovery Summary ===
Recovery Attempts: $((RECOVERY_SUCCESSES + RECOVERY_FAILURES))
Successful Recoveries: $RECOVERY_SUCCESSES
Failed Recoveries: $RECOVERY_FAILURES

=== Files Generated ===
Injection Log: $INJECTION_LOG
Recovery Log: $RECOVERY_LOG
Metrics Log: $METRICS_LOG
Results Log: $RESULTS_LOG

=== Recommendations ===
EOF

    if [[ $FAILED_INJECTIONS -gt 0 ]]; then
        echo "- Review failed injections in $INJECTION_LOG" >> "$RESULTS_LOG"
    fi
    
    if [[ $RECOVERY_FAILURES -gt 0 ]]; then
        echo "- Investigate recovery failures in $RECOVERY_LOG" >> "$RESULTS_LOG"
    fi
    
    if [[ $success_rate -lt 80 ]]; then
        echo "- Low success rate indicates system instability" >> "$RESULTS_LOG"
    fi
    
    echo "- Review system metrics in $METRICS_LOG for performance impact" >> "$RESULTS_LOG"
    
    log "INFO" "Session report generated: $RESULTS_LOG"
}

# ============================================================================
# Help and Usage Functions
# ============================================================================

show_help() {
    cat << EOF
ArcDeploy Failure Injection Framework v$SCRIPT_VERSION

Comprehensive failure injection system for testing resilience and recovery mechanisms.

Usage: $SCRIPT_NAME [COMMAND] [OPTIONS]

Commands:
    inject TYPE [DURATION] [INTENSITY] [TARGET]    Inject specific failure
    chaos [DURATION] [MAX_CONCURRENT]              Run chaos monkey
    cascade [INITIAL_FAILURE] [CASCADE_DELAY]      Run cascade failure test
    resilience [DURATION]                          Run resilience test
    monitor [INJECTION_ID] [DURATION]              Monitor system during injection
    list-types                                      List available failure types
    cleanup                                         Manual cleanup
    help                                            Show this help

Failure Types:
    network_latency        Add network latency
    network_loss          Inject packet loss
    network_partition     Create network partition
    disk_full            Fill disk space
    disk_slow            Slow down disk I/O
    memory_pressure      Create memory pressure
    cpu_stress           Stress CPU cores
    service_kill         Kill system service
    config_corruption    Corrupt configuration file
    permission_denial    Deny file permissions

Intensity Levels:
    low, medium, high, extreme (or specific values)

Options:
    --duration SECONDS    Override default duration ($DEFAULT_DURATION)
    --intensity LEVEL     Override default intensity ($DEFAULT_INTENSITY)
    --target TARGET       Specify injection target
    --debug              Enable debug output
    --no-cleanup         Skip automatic cleanup

Examples:
    $SCRIPT_NAME inject network_latency 60 medium lo
    $SCRIPT_NAME inject memory_pressure 120 high
    $SCRIPT_NAME chaos 300 2
    $SCRIPT_NAME cascade network_partition 30
    $SCRIPT_NAME resilience 180
    $SCRIPT_NAME monitor injection_1 300

Output Files:
    - Injection Log: $INJECTION_LOG
    - Recovery Log: $RECOVERY_LOG
    - Results Log: $RESULTS_LOG
    - Metrics Log: $METRICS_LOG

EOF
}

list_failure_types() {
    echo "Available Failure Types:"
    echo "========================"
    echo ""
    echo "Network Failures:"
    echo "  network_latency     - Add network delay/latency"
    echo "  network_loss        - Inject packet loss"
    echo "  network_partition   - Create network partition"
    echo ""
    echo "Disk Failures:"
    echo "  disk_full          - Fill disk space"
    echo "  disk_slow          - Slow down disk I/O"
    echo ""
    echo "Resource Failures:"
    echo "  memory_pressure    - Create memory pressure"
    echo "  cpu_stress         - Stress CPU cores"
    echo ""
    echo "Service Failures:"
    echo "  service_kill       - Kill system service"
    echo ""
    echo "Configuration Failures:"
    echo "  config_corruption  - Corrupt configuration file"
    echo "  permission_denial  - Deny file permissions"
    echo ""
    echo "Intensity Levels: low, medium, high, extreme"
    echo "Default Duration: $DEFAULT_DURATION seconds"
}

# ============================================================================
# Main Function
# ============================================================================

main() {
    local command=""
    local duration="$DEFAULT_DURATION"
    local intensity="$DEFAULT_INTENSITY"
    local target=""
    local debug_mode="false"
    local no_cleanup="false"
    
    # Parse global options first
    while [[ $# -gt 0 ]]; do
        case $1 in
            --duration)
                duration="$2"
                shift 2
                ;;
            --intensity)
                intensity="$2"
                shift 2
                ;;
            --target)
                target="$2"
                shift 2
                ;;
            --debug)
                debug_mode="true"
                export DEBUG_MODE="true"
                shift
                ;;
            --no-cleanup)
                no_cleanup="true"
                shift
                ;;
            -h|--help|help)
                show_help
                exit 0
                ;;
            -*)
                log "FAILURE" "Unknown option: $1"
                show_help
                exit 1
                ;;
            *)
                command="$1"
                shift
                break
                ;;
        esac
    done
    
    if [[ -z "$command" ]]; then
        show_help
        exit 1
    fi
    
    # Initialize framework
    initialize_framework
    
    # Execute command
    case "$command" in
        inject)
            local failure_type="${1:-network_latency}"
            local cmd_duration="${2:-$duration}"
            local cmd_intensity="${3:-$intensity}"
            local cmd_target="${4:-$target}"
            
            inject_failure "$failure_type" "$cmd_duration" "$cmd_intensity" "$cmd_target"
            ;;
        chaos)
            local chaos_duration="${1:-300}"
            local max_concurrent="${2:-3}"
            run_chaos_monkey "$chaos_duration" "$max_concurrent"
            ;;
        cascade)
            local initial_failure="${1:-network_partition}"
            local cascade_delay="${2:-30}"
            run_cascade_failure "$initial_failure" "$cascade_delay"
            ;;
        resilience)
            local test_duration="${1:-180}"
            run_resilience_test "$test_duration"
            ;;
        monitor)
            local injection_id="${1:-current}"
            local monitor_duration="${2:-300}"
            monitor_system_during_injection "$injection_id" "$monitor_duration"
            ;;
        list-types)
            list_failure_types
            ;;
        cleanup)
            log "INFO" "Manual cleanup requested"
            cleanup_framework
            ;;
        *)
            log "FAILURE" "Unknown command: $command"
            show_help
            exit 1
            ;;
    esac
    
    # Generate final report
    if [[ "$no_cleanup" != "true" ]]; then
        generate_session_report
    fi
    
    log "INFO" "Failure injection framework session completed"
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi