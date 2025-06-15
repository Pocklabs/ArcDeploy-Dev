#!/bin/bash

# ArcDeploy Emergency Recovery Script
# Comprehensive recovery and cleanup for failure injection testing
# This script provides emergency recovery capabilities for all failure scenarios

set -euo pipefail

# ============================================================================
# Script Metadata
# ============================================================================
readonly SCRIPT_VERSION="1.0.0"
readonly SCRIPT_NAME="$(basename "$0")"

# Directory setup
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
readonly PROJECT_ROOT

# Logging
readonly RECOVERY_LOG="$PROJECT_ROOT/test-results/failure-injection/emergency-recovery.log"
readonly RECOVERY_REPORT="$PROJECT_ROOT/test-results/failure-injection/recovery-report.txt"

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
# Configuration
# ============================================================================
readonly SERVICES=("blocklet-server" "nginx" "redis-server" "ssh" "fail2ban" "ufw")
readonly CRITICAL_SERVICES=("blocklet-server" "nginx" "redis-server")
readonly SECURITY_SERVICES=("ssh" "fail2ban" "ufw")

# Process patterns to clean up
readonly STRESS_PATTERNS=("stress-ng" "memory_fill" "cpu_bomb" "io_storm" "context_switch")

# Temporary file patterns
readonly TEMP_PATTERNS=(
    "/tmp/*_stress_*"
    "/tmp/*_bomb_*"
    "/tmp/*_exhaustion_*"
    "/tmp/memory_fill_*"
    "/tmp/disk_fill_*"
    "/tmp/*_pid.*"
    "/tmp/emergency_swap"
    "/tmp/*.backup.test"
)

# Configuration backup patterns
readonly CONFIG_BACKUPS=(
    "/etc/systemd/system/blocklet-server.service.backup.test"
    "/etc/nginx/nginx.conf.backup.test"
    "/etc/redis/redis.conf.backup.test"
    "/etc/ssh/sshd_config.backup.test"
    "/etc/resolv.conf.backup.network-test"
)

# ============================================================================
# Global State
# ============================================================================
declare -g RECOVERY_START_TIME=""
declare -g TOTAL_RECOVERIES=0
declare -g SUCCESSFUL_RECOVERIES=0
declare -g FAILED_RECOVERIES=0
declare -g WARNINGS=0

# ============================================================================
# Logging Functions
# ============================================================================

log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    mkdir -p "$(dirname "$RECOVERY_LOG")"
    
    case "$level" in
        "INFO")
            echo -e "${BLUE}[INFO]${NC} $message" | tee -a "$RECOVERY_LOG"
            ;;
        "SUCCESS")
            echo -e "${GREEN}[SUCCESS]${NC} $message" | tee -a "$RECOVERY_LOG"
            ;;
        "FAILURE")
            echo -e "${RED}[FAILURE]${NC} $message" | tee -a "$RECOVERY_LOG"
            ;;
        "WARNING")
            echo -e "${YELLOW}[WARNING]${NC} $message" | tee -a "$RECOVERY_LOG"
            ((WARNINGS++))
            ;;
        "RECOVER")
            echo -e "${CYAN}[RECOVER]${NC} $message" | tee -a "$RECOVERY_LOG"
            ;;
        "EMERGENCY")
            echo -e "${RED}${BOLD}[EMERGENCY]${NC} $message" | tee -a "$RECOVERY_LOG"
            ;;
        "DEBUG")
            if [[ "${DEBUG_MODE:-false}" == "true" ]]; then
                echo -e "${PURPLE}[DEBUG]${NC} $message" | tee -a "$RECOVERY_LOG"
            fi
            ;;
    esac
}

# ============================================================================
# System State Assessment
# ============================================================================

assess_system_state() {
    log "INFO" "Assessing current system state..."
    
    local issues_found=0
    
    # Check memory usage
    local memory_usage
    memory_usage=$(awk '/MemTotal:/ {total=$2} /MemAvailable:/ {avail=$2} END {printf "%.0f", (total-avail)*100/total}' /proc/meminfo)
    log "INFO" "Memory usage: $memory_usage%"
    
    if [[ $memory_usage -gt 90 ]]; then
        log "WARNING" "High memory usage detected: $memory_usage%"
        ((issues_found++))
    fi
    
    # Check CPU load
    local load_avg
    load_avg=$(awk '{print $1}' /proc/loadavg)
    local cpu_cores
    cpu_cores=$(nproc)
    local cpu_percentage
    cpu_percentage=$(echo "scale=0; $load_avg * 100 / $cpu_cores" | bc -l 2>/dev/null || echo "0")
    log "INFO" "CPU load: $load_avg ($cpu_percentage%)"
    
    if [[ $cpu_percentage -gt 90 ]]; then
        log "WARNING" "High CPU load detected: $cpu_percentage%"
        ((issues_found++))
    fi
    
    # Check disk usage
    local disk_usage
    disk_usage=$(df / | awk 'NR==2 {print substr($5, 1, length($5)-1)}')
    log "INFO" "Root disk usage: $disk_usage%"
    
    if [[ $disk_usage -gt 90 ]]; then
        log "WARNING" "High disk usage detected: $disk_usage%"
        ((issues_found++))
    fi
    
    # Check swap usage
    local swap_usage
    local total_swap
    local free_swap
    total_swap=$(awk '/SwapTotal:/ {print $2}' /proc/meminfo)
    free_swap=$(awk '/SwapFree:/ {print $2}' /proc/meminfo)
    
    if [[ "$total_swap" -gt 0 ]]; then
        swap_usage=$(( (total_swap - free_swap) * 100 / total_swap ))
        log "INFO" "Swap usage: $swap_usage%"
        
        if [[ $swap_usage -gt 50 ]]; then
            log "WARNING" "High swap usage detected: $swap_usage%"
            ((issues_found++))
        fi
    else
        log "INFO" "No swap space configured"
    fi
    
    # Check critical services
    for service in "${CRITICAL_SERVICES[@]}"; do
        if systemctl is-active --quiet "$service"; then
            log "INFO" "Service $service is running"
        else
            log "WARNING" "Critical service $service is not running"
            ((issues_found++))
        fi
    done
    
    # Check for stress processes
    local stress_processes
    stress_processes=$(pgrep -f "stress-ng\|memory_fill\|cpu_bomb" | wc -l)
    if [[ $stress_processes -gt 0 ]]; then
        log "WARNING" "Found $stress_processes stress processes still running"
        ((issues_found++))
    fi
    
    log "INFO" "System assessment complete. Issues found: $issues_found"
    return $issues_found
}

# ============================================================================
# Process Cleanup
# ============================================================================

cleanup_stress_processes() {
    log "RECOVER" "Cleaning up stress and test processes..."
    
    local cleaned_processes=0
    
    # Kill stress-ng processes
    if pgrep -f "stress-ng" >/dev/null; then
        pkill -TERM -f "stress-ng" 2>/dev/null || true
        sleep 3
        pkill -KILL -f "stress-ng" 2>/dev/null || true
        local stress_ng_count
        stress_ng_count=$(pgrep -f "stress-ng" | wc -l)
        if [[ $stress_ng_count -eq 0 ]]; then
            log "SUCCESS" "All stress-ng processes terminated"
            ((cleaned_processes++))
        else
            log "WARNING" "$stress_ng_count stress-ng processes still running"
        fi
    fi
    
    # Clean up PID files and associated processes
    for pid_file in /tmp/*_pid.*; do
        if [[ -f "$pid_file" ]]; then
            while read -r pid; do
                if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
                    kill -TERM "$pid" 2>/dev/null || true
                    sleep 1
                    kill -KILL "$pid" 2>/dev/null || true
                    log "RECOVER" "Terminated process from PID file: $pid_file (PID: $pid)"
                    ((cleaned_processes++))
                fi
            done < "$pid_file" 2>/dev/null || true
            rm -f "$pid_file"
        fi
    done
    
    # Kill processes by pattern
    for pattern in "${STRESS_PATTERNS[@]}"; do
        if pgrep -f "$pattern" >/dev/null; then
            pkill -TERM -f "$pattern" 2>/dev/null || true
            sleep 2
            pkill -KILL -f "$pattern" 2>/dev/null || true
            log "RECOVER" "Cleaned up processes matching pattern: $pattern"
            ((cleaned_processes++))
        fi
    done
    
    log "SUCCESS" "Process cleanup completed. Cleaned $cleaned_processes process groups"
}

# ============================================================================
# File System Cleanup
# ============================================================================

cleanup_temporary_files() {
    log "RECOVER" "Cleaning up temporary files and directories..."
    
    local cleaned_files=0
    
    # Remove temporary files by pattern
    for pattern in "${TEMP_PATTERNS[@]}"; do
        # Use find to safely handle patterns
        if find /tmp -maxdepth 1 -name "$(basename "$pattern")" -type f 2>/dev/null | grep -q .; then
            find /tmp -maxdepth 1 -name "$(basename "$pattern")" -type f -delete 2>/dev/null || true
            log "RECOVER" "Removed temporary files matching: $pattern"
            ((cleaned_files++))
        fi
    done
    
    # Clean up stress directories
    find /tmp -maxdepth 1 -name "*_stress_*" -type d -exec rm -rf {} \; 2>/dev/null || true
    find /tmp -maxdepth 1 -name "disk_stress_*" -type d -exec rm -rf {} \; 2>/dev/null || true
    find /tmp -maxdepth 1 -name "inode_exhaustion_*" -type d -exec rm -rf {} \; 2>/dev/null || true
    
    # Remove emergency swap file
    if [[ -f "/tmp/emergency_swap" ]]; then
        sudo swapoff /tmp/emergency_swap 2>/dev/null || true
        sudo rm -f /tmp/emergency_swap
        log "RECOVER" "Removed emergency swap file"
        ((cleaned_files++))
    fi
    
    # Clean up large test files
    find /tmp -maxdepth 1 -name "disk_fill_test.*" -size +10M -delete 2>/dev/null || true
    find /tmp -maxdepth 1 -name "memory_fill_*" -delete 2>/dev/null || true
    
    log "SUCCESS" "Temporary file cleanup completed. Cleaned $cleaned_files file groups"
}

# ============================================================================
# Configuration Recovery
# ============================================================================

restore_configurations() {
    log "RECOVER" "Restoring service configurations from backups..."
    
    local restored_configs=0
    
    # Restore from backup files
    for backup_file in "${CONFIG_BACKUPS[@]}"; do
        if [[ -f "$backup_file" ]]; then
            local original_file="${backup_file%.backup.test}"
            sudo mv "$backup_file" "$original_file"
            sudo chmod 644 "$original_file"
            log "RECOVER" "Restored configuration: $original_file"
            ((restored_configs++))
        fi
    done
    
    # Restore DNS configuration
    if [[ -f "/etc/resolv.conf.backup.network-test" ]]; then
        sudo mv "/etc/resolv.conf.backup.network-test" "/etc/resolv.conf"
        log "RECOVER" "Restored DNS configuration"
        ((restored_configs++))
    else
        # Fallback DNS configuration
        if ! grep -q "nameserver" /etc/resolv.conf 2>/dev/null; then
            echo "nameserver 8.8.8.8" | sudo tee /etc/resolv.conf > /dev/null
            echo "nameserver 8.8.4.4" | sudo tee -a /etc/resolv.conf > /dev/null
            log "RECOVER" "Applied fallback DNS configuration"
            ((restored_configs++))
        fi
    fi
    
    # Restore CPU governor
    if [[ -f "/tmp/cpu_governor_backup.$$" ]]; then
        local original_governor
        original_governor=$(cat "/tmp/cpu_governor_backup.$$")
        if [[ "$original_governor" != "unknown" ]] && [[ -d "/sys/devices/system/cpu/cpu0/cpufreq" ]]; then
            echo "$original_governor" | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor >/dev/null 2>&1 || true
            log "RECOVER" "Restored CPU governor to: $original_governor"
            ((restored_configs++))
        fi
        rm -f "/tmp/cpu_governor_backup.$$"
    fi
    
    log "SUCCESS" "Configuration restoration completed. Restored $restored_configs configurations"
}

# ============================================================================
# Network Recovery
# ============================================================================

restore_network_configuration() {
    log "RECOVER" "Restoring network configuration..."
    
    local network_fixes=0
    
    # Remove iptables rules added during testing
    local critical_ports=("8080" "8443" "2222" "6379")
    for port in "${critical_ports[@]}"; do
        sudo iptables -D INPUT -p tcp --dport "$port" -j DROP 2>/dev/null || true
        sudo iptables -D OUTPUT -p tcp --sport "$port" -j DROP 2>/dev/null || true
    done
    log "RECOVER" "Removed test iptables rules"
    ((network_fixes++))
    
    # Remove traffic control rules
    local interfaces
    interfaces=$(ip route | awk '/default/ {print $5}' | head -1)
    for interface in $interfaces; do
        if ip link show "$interface" >/dev/null 2>&1; then
            sudo tc qdisc del dev "$interface" root 2>/dev/null || true
            log "RECOVER" "Removed traffic control rules from $interface"
        fi
    done
    ((network_fixes++))
    
    # Bring up network interfaces
    for interface in $interfaces; do
        if ip link show "$interface" >/dev/null 2>&1; then
            sudo ip link set "$interface" up 2>/dev/null || true
            # Restore MTU to standard size
            sudo ip link set dev "$interface" mtu 1500 2>/dev/null || true
            log "RECOVER" "Ensured interface $interface is up with standard MTU"
        fi
    done
    ((network_fixes++))
    
    # Test network connectivity
    if ping -c 1 -W 5 8.8.8.8 >/dev/null 2>&1; then
        log "SUCCESS" "Network connectivity verified"
    else
        log "WARNING" "Network connectivity test failed"
    fi
    
    log "SUCCESS" "Network recovery completed. Applied $network_fixes network fixes"
}

# ============================================================================
# Service Recovery
# ============================================================================

restore_services() {
    log "RECOVER" "Restoring critical services..."
    
    local restored_services=0
    local failed_services=0
    
    # Reload systemd if configurations were restored
    sudo systemctl daemon-reload
    
    # Restart critical services
    for service in "${CRITICAL_SERVICES[@]}"; do
        log "RECOVER" "Checking service: $service"
        
        if ! systemctl is-active --quiet "$service"; then
            log "RECOVER" "Starting service: $service"
            if sudo systemctl start "$service"; then
                sleep 3
                if systemctl is-active --quiet "$service"; then
                    log "SUCCESS" "Service $service started successfully"
                    ((restored_services++))
                else
                    log "FAILURE" "Service $service failed to start"
                    ((failed_services++))
                fi
            else
                log "FAILURE" "Failed to start service: $service"
                ((failed_services++))
            fi
        else
            log "INFO" "Service $service is already running"
            ((restored_services++))
        fi
    done
    
    # Test service endpoints
    test_service_endpoints
    
    log "SUCCESS" "Service recovery completed. Restored: $restored_services, Failed: $failed_services"
}

test_service_endpoints() {
    log "INFO" "Testing service endpoints..."
    
    # Test Blocklet Server
    if curl -sf --max-time 10 http://localhost:8080 >/dev/null 2>&1; then
        log "SUCCESS" "Blocklet Server HTTP endpoint responding"
    else
        log "WARNING" "Blocklet Server HTTP endpoint not responding"
    fi
    
    # Test Redis
    if command -v redis-cli >/dev/null 2>&1; then
        if redis-cli ping 2>/dev/null | grep -q "PONG"; then
            log "SUCCESS" "Redis service responding"
        else
            log "WARNING" "Redis service not responding"
        fi
    fi
    
    # Test Nginx
    if curl -sf --max-time 5 http://localhost:80 >/dev/null 2>&1; then
        log "SUCCESS" "Nginx HTTP endpoint responding"
    else
        log "WARNING" "Nginx HTTP endpoint not responding"
    fi
}

# ============================================================================
# System Resource Recovery
# ============================================================================

recover_system_resources() {
    log "RECOVER" "Recovering system resources..."
    
    local recovery_actions=0
    
    # Clear memory caches
    echo 3 | sudo tee /proc/sys/vm/drop_caches >/dev/null 2>&1 || true
    log "RECOVER" "Cleared system memory caches"
    ((recovery_actions++))
    
    # Clear swap if heavily used
    local swap_usage
    local total_swap
    local free_swap
    total_swap=$(awk '/SwapTotal:/ {print $2}' /proc/meminfo)
    free_swap=$(awk '/SwapFree:/ {print $2}' /proc/meminfo)
    
    if [[ "$total_swap" -gt 0 ]]; then
        swap_usage=$(( (total_swap - free_swap) * 100 / total_swap ))
        if [[ $swap_usage -gt 30 ]]; then
            log "RECOVER" "Clearing swap space (usage: $swap_usage%)"
            sudo swapoff -a && sudo swapon -a 2>/dev/null || true
            ((recovery_actions++))
        fi
    fi
    
    # Restart system services if needed
    local high_load
    high_load=$(awk '{print int($1)}' /proc/loadavg)
    local cpu_cores
    cpu_cores=$(nproc)
    
    if [[ $high_load -gt $((cpu_cores * 2)) ]]; then
        log "WARNING" "System load is very high: $high_load (cores: $cpu_cores)"
        # Consider more aggressive recovery if needed
    fi
    
    log "SUCCESS" "System resource recovery completed. Applied $recovery_actions recovery actions"
}

# ============================================================================
# Health Verification
# ============================================================================

verify_system_health() {
    log "INFO" "Verifying system health post-recovery..."
    
    local health_score=0
    local max_score=10
    
    # Memory health
    local memory_usage
    memory_usage=$(awk '/MemTotal:/ {total=$2} /MemAvailable:/ {avail=$2} END {printf "%.0f", (total-avail)*100/total}' /proc/meminfo)
    if [[ $memory_usage -lt 80 ]]; then
        ((health_score++))
        log "SUCCESS" "Memory usage healthy: $memory_usage%"
    else
        log "WARNING" "Memory usage still high: $memory_usage%"
    fi
    
    # CPU health
    sleep 5  # Let system settle
    local load_avg
    load_avg=$(awk '{print $1}' /proc/loadavg)
    local cpu_cores
    cpu_cores=$(nproc)
    local cpu_percentage
    cpu_percentage=$(echo "scale=0; $load_avg * 100 / $cpu_cores" | bc -l 2>/dev/null || echo "0")
    
    if [[ $cpu_percentage -lt 70 ]]; then
        ((health_score++))
        log "SUCCESS" "CPU load healthy: $cpu_percentage%"
    else
        log "WARNING" "CPU load still high: $cpu_percentage%"
    fi
    
    # Disk health
    local disk_usage
    disk_usage=$(df / | awk 'NR==2 {print substr($5, 1, length($5)-1)}')
    if [[ $disk_usage -lt 85 ]]; then
        ((health_score++))
        log "SUCCESS" "Disk usage healthy: $disk_usage%"
    else
        log "WARNING" "Disk usage high: $disk_usage%"
    fi
    
    # Service health
    local running_services=0
    for service in "${CRITICAL_SERVICES[@]}"; do
        if systemctl is-active --quiet "$service"; then
            ((running_services++))
        fi
    done
    
    if [[ $running_services -eq ${#CRITICAL_SERVICES[@]} ]]; then
        ((health_score+=2))
        log "SUCCESS" "All critical services are running"
    else
        log "WARNING" "Some critical services are not running ($running_services/${#CRITICAL_SERVICES[@]})"
    fi
    
    # Network health
    if ping -c 1 -W 5 8.8.8.8 >/dev/null 2>&1; then
        ((health_score++))
        log "SUCCESS" "Network connectivity healthy"
    else
        log "WARNING" "Network connectivity issues detected"
    fi
    
    # Process health (no stress processes)
    local stress_count
    stress_count=$(pgrep -f "stress-ng\|memory_fill\|cpu_bomb" | wc -l)
    if [[ $stress_count -eq 0 ]]; then
        ((health_score++))
        log "SUCCESS" "No stress processes detected"
    else
        log "WARNING" "$stress_count stress processes still running"
    fi
    
    # File system health
    if [[ ! -f "/tmp/emergency_swap" ]] && [[ $(find /tmp -name "*_stress_*" | wc -l) -eq 0 ]]; then
        ((health_score++))
        log "SUCCESS" "File system clean"
    else
        log "WARNING" "Temporary files still present"
    fi
    
    # Configuration health
    local config_issues=0
    for service in "${CRITICAL_SERVICES[@]}"; do
        if systemctl status "$service" >/dev/null 2>&1; then
            continue
        else
            ((config_issues++))
        fi
    done
    
    if [[ $config_issues -eq 0 ]]; then
        ((health_score++))
        log "SUCCESS" "Service configurations healthy"
    else
        log "WARNING" "$config_issues service configuration issues detected"
    fi
    
    # Overall health assessment
    local health_percentage=$((health_score * 100 / max_score))
    
    if [[ $health_percentage -ge 90 ]]; then
        log "SUCCESS" "System health excellent: $health_percentage% ($health_score/$max_score)"
    elif [[ $health_percentage -ge 70 ]]; then
        log "WARNING" "System health good: $health_percentage% ($health_score/$max_score)"
    else
        log "FAILURE" "System health poor: $health_percentage% ($health_score/$max_score)"
    fi
    
    return $((max_score - health_score))
}

# ============================================================================
# Report Generation
# ============================================================================

generate_recovery_report() {
    log "INFO" "Generating recovery report..."
    
    local recovery_end_time
    recovery_end_time=$(date '+%Y-%m-%d %H:%M:%S')
    local duration=$(($(date +%s) - $(date -d "$RECOVERY_START_TIME" +%s)))
    
    mkdir -p "$(dirname "$RECOVERY_REPORT")"
    
    cat > "$RECOVERY_REPORT" << EOF
# ArcDeploy Emergency Recovery Report

## Recovery Summary
- **Start Time:** $RECOVERY_START_TIME
- **End Time:** $recovery_end_time
- **Duration:** ${duration}s
- **Total Recoveries:** $TOTAL_RECOVERIES
- **Successful:** $SUCCESSFUL_RECOVERIES
- **Failed:** $FAILED_RECOVERIES
- **Warnings:** $WARNINGS

## System State After Recovery
$(show_system_status)

## Actions Performed
$(tail -50 "$RECOVERY_LOG" | grep "\[RECOVER\]")

## Recommendations
EOF
    
    # Add recommendations based on health check
    if [[ $WARNINGS -gt 5 ]]; then
        echo "- Consider system reboot due to high warning count" >> "$RECOVERY_REPORT"
    fi
    
    if [[ $FAILED_RECOVERIES -gt 0 ]]; then
        echo "- Manual intervention may be required for failed recoveries" >> "$RECOVERY_REPORT"
        echo "- Check service logs for detailed error information" >> "$RECOVERY_REPORT"
    fi
    
    echo "- Monitor system performance for next 24 hours" >> "$RECOVERY_REPORT"
    echo "- Review failure injection test procedures" >> "$RECOVERY_REPORT"
    
    log "SUCCESS" "Recovery report generated: $RECOVERY_REPORT"
}

show_system_status() {
    echo "### System Resources"
    echo "- Memory Usage: $(awk '/MemTotal:/ {total=$2} /MemAvailable:/ {avail=$2} END {printf "%.0f%%", (total-avail)*100/total}' /proc/meminfo)"
    echo "- CPU Load: $(awk '{print $1}' /proc/loadavg) ($(nproc) cores)"
    echo "- Disk Usage: $(df / | awk 'NR==2 {print $5}')"
    
    local total_swap
    total_swap=$(awk '/SwapTotal:/ {print $2}' /proc/meminfo)
    if [[ "$total_swap" -gt 0 ]]; then
        local free_swap
        free_swap=$(awk '/SwapFree:/ {print $2}' /proc/meminfo)
        local swap_usage=$(( (total_swap - free_swap) * 100 / total_swap ))
        echo "- Swap Usage: $swap_usage%"
    else
        echo "- Swap Usage: N/A (no swap)"
    fi
    
    echo ""
    echo "### Service Status"
    for service in "${CRITICAL_SERVICES[@]}"; do
        if systemctl is-active --quiet "$service"; then
            echo "- $service: ✓ Running"
        else
            echo "- $service: ✗ Stopped"
        fi
    done
    
    echo ""
    echo "### Network Status"
    if ping -c 1 -W 5 8.8.8.8 >/dev/null 2>&1; then
        echo "- Internet Connectivity: ✓ Available"
    else
        echo "- Internet Connectivity: ✗ Failed"
    fi
}

# ============================================================================
# Main Recovery Function
# ============================================================================

perform_emergency_recovery() {
    local recovery_type="${1:-full}"
    
    RECOVERY_START_TIME=$(date '+%Y-%m-%d %H:%M:%S')
    log "EMERGENCY" "Starting emergency recovery (type: $recovery_type)"
    
    # Assess initial state
    assess_system_state
    local initial_issues=$?
    
    case "$recovery_type" in
        "quick")
            cleanup_stress_processes
            ((TOTAL_RECOVERIES++))
            if [[ $? -eq 0 ]]; then ((SUCCESSFUL_RECOVERIES++)); else ((FAILED_RECOVERIES++)); fi
            ;;
        "network")
            restore_network_configuration
            ((TOTAL_RECOVERIES++))
            if [[ $? -eq 0 ]]; then ((SUCCESSFUL_RECOVERIES++)); else ((FAILED_RECOVERIES++)); fi
            ;;
        "services")
            restore_configurations
            ((TOTAL_RECOVERIES++))
            if [[ $? -eq 0 ]]; then ((SUCCESSFUL_RECOVERIES++)); else ((FAILED_RECOVERIES++)); fi
            
            restore_services
            ((TOTAL_RECOVERIES++))
            if [[ $? -eq 0 ]]; then ((SUCCESSFUL_RECOVERIES++)); else ((FAILED_RECOVERIES++)); fi
            ;;
        "full"|*)
            # Full recovery process
            cleanup_stress_processes
            ((TOTAL_RECOVERIES++))
            if [[ $? -eq 0 ]]; then ((SUCCESSFUL_RECOVERIES++)); else ((FAILED_RECOVERIES++)); fi
            
            cleanup_temporary_files
            ((TOTAL_RECOVERIES++))
            if [[ $? -eq 0 ]]; then ((SUCCESSFUL_RECOVERIES++)); else ((FAILED_RECOVERIES++)); fi
            
            restore_configurations
            ((TOTAL_RECOVERIES++))
            if [[ $? -eq 0 ]]; then ((SUCCESSFUL_RECOVERIES++)); else ((FAILED_RECOVERIES++)); fi
            
            restore_network_configuration
            ((TOTAL_RECOVERIES++))
            if [[ $? -eq 0 ]]; then ((SUCCESSFUL_RECOVERIES++)); else ((FAILED_RECOVERIES++)); fi
            
            restore_services
            ((TOTAL_RECOVERIES++))
            if [[ $? -eq 0 ]]; then ((SUCCESSFUL_RECOVERIES++)); else ((FAILED_RECOVERIES++)); fi
            
            recover_system_resources
            ((TOTAL_RECOVERIES++))
            if [[ $? -eq 0 ]]; then ((SUCCESSFUL_RECOVERIES++)); else ((FAILED_RECOVERIES++)); fi
            ;;
    esac
    
    # Final health verification
    verify_system_health
    local health_issues=$?
    
    # Generate report
    generate_recovery_report
    
    log "EMERGENCY" "Emergency recovery completed"
    log "INFO" "Recovery summary: $SUCCESSFUL_RECOVERIES successful, $FAILED_RECOVERIES failed, $WARNINGS warnings"
    
    if [[ $health_issues -eq 0 ]] && [[ $FAILED_RECOVERIES -eq 0 ]]; then
        log "SUCCESS" "System fully recovered"
        return 0
    elif [[ $health_issues -le 2 ]] && [[ $FAILED_RECOVERIES -le 1 ]]; then
        log "WARNING" "System mostly recovered with minor issues"
        return 1
    else
        log "FAILURE" "System recovery incomplete - manual intervention required"
        return 2
    fi
}

# ============================================================================
# Usage and Help
# ============================================================================

show_usage() {
    cat << EOF
ArcDeploy Emergency Recovery Script

Usage: $SCRIPT_NAME [OPTION]... [RECOVERY_TYPE]

RECOVERY TYPES:
  quick                 Quick cleanup of stress processes only
  network              Restore network configuration only
  services             Restore service configurations and restart services
  full                 Complete system recovery (default)

OPTIONS:
  -a, --assess         Assess current system state without recovery
  -v, --verify         Verify system health only
  -r, --report         Show latest recovery report
  -h, --help           Show this help message
  --version            Show script version

EXAMPLES:
  $SCRIPT_NAME                    # Full recovery
  $SCRIPT_NAME quick              # Quick cleanup only
  $SCRIPT_NAME services           # Service recovery only
  $SCRIPT_NAME --assess           # Assessment only
  $SCRIPT_NAME --verify           # Health check only

EMERGENCY USAGE:
  # If system is unresponsive, try quick recovery first
  $SCRIPT_NAME quick

  # For network issues only
  $SCRIPT_NAME network

  # For service failures
  $SCRIPT_NAME services

  # For complete recovery
  $SCRIPT_NAME full

EOF
}

# ============================================================================
# Main Script Logic
# ============================================================================

main() {
    case "${1:-full}" in
        -h|--help)
            show_usage
            exit 0
            ;;
        --version)
            echo "$SCRIPT_NAME version $SCRIPT_VERSION"
            exit 0
            ;;
        -a|--assess)
            assess_system_state
            exit $?
            ;;
        -v|--verify)
            verify_system_health
            exit $?
            ;;
        -r|--report)
            if [[ -f "$RECOVERY_REPORT" ]]; then
                cat "$RECOVERY_REPORT"
            else
                echo "No recovery report found at: $RECOVERY_REPORT"
                exit 1
            fi
            exit 0
            ;;
        quick|network|services|full)
            perform_emergency_recovery "$1"
            exit $?
            ;;
        *)
            echo "Error: Unknown option or recovery type: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi