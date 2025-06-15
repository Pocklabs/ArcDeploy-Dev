#!/bin/bash

# ArcDeploy Service Failure Injection Scenarios
# Comprehensive service failure simulation for testing resilience and recovery

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
readonly SERVICE_LOG="$PROJECT_ROOT/test-results/failure-injection/service-failures.log"

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
# Service Configuration
# ============================================================================
readonly SERVICES=("blocklet-server" "nginx" "redis-server" "ssh" "fail2ban" "ufw")
readonly CRITICAL_SERVICES=("blocklet-server" "nginx" "redis-server")
readonly SECURITY_SERVICES=("ssh" "fail2ban" "ufw")

# Service endpoints for testing
readonly BLOCKLET_HTTP_PORT="8080"
readonly BLOCKLET_HTTPS_PORT="8443"
readonly SSH_PORT="2222"
readonly NGINX_HTTP_PORT="80"
readonly NGINX_HTTPS_PORT="443"
readonly REDIS_PORT="6379"

# Service paths and files
readonly BLOCKLET_DATA_DIR="/opt/blocklet-server/data"
readonly BLOCKLET_CONFIG_DIR="/opt/blocklet-server/config"
readonly BLOCKLET_LOGS_DIR="/opt/blocklet-server/logs"
readonly NGINX_CONFIG_DIR="/etc/nginx"
readonly REDIS_CONFIG="/etc/redis/redis.conf"

# ============================================================================
# Logging Functions
# ============================================================================

log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    mkdir -p "$(dirname "$SERVICE_LOG")"
    
    case "$level" in
        "INFO")
            echo -e "${BLUE}[INFO]${NC} $message" | tee -a "$SERVICE_LOG"
            ;;
        "SUCCESS")
            echo -e "${GREEN}[SUCCESS]${NC} $message" | tee -a "$SERVICE_LOG"
            ;;
        "FAILURE")
            echo -e "${RED}[FAILURE]${NC} $message" | tee -a "$SERVICE_LOG"
            ;;
        "WARNING")
            echo -e "${YELLOW}[WARNING]${NC} $message" | tee -a "$SERVICE_LOG"
            ;;
        "INJECT")
            echo -e "${PURPLE}[INJECT]${NC} $message" | tee -a "$SERVICE_LOG"
            ;;
        "RECOVER")
            echo -e "${CYAN}[RECOVER]${NC} $message" | tee -a "$SERVICE_LOG"
            ;;
    esac
}

# ============================================================================
# Service Failure Scenarios
# ============================================================================

# Scenario 1: Complete Service Stop
inject_service_stop() {
    local service="$1"
    local duration="${2:-60}"
    
    log "INJECT" "Stopping service: $service (duration: ${duration}s)"
    
    # Check if service exists
    if ! systemctl list-unit-files | grep -q "^$service.service"; then
        log "WARNING" "Service $service not found in systemd"
        return 1
    fi
    
    # Stop the service
    if systemctl is-active --quiet "$service"; then
        sudo systemctl stop "$service"
        log "INJECT" "Service $service stopped"
        
        # Verify service is stopped
        if ! systemctl is-active --quiet "$service"; then
            log "INFO" "Service $service confirmed stopped"
        else
            log "WARNING" "Service $service may still be running"
        fi
    else
        log "WARNING" "Service $service was already stopped"
    fi
    
    return 0
}

# Scenario 2: Service Process Kill
inject_service_kill() {
    local service="$1"
    local signal="${2:-TERM}"
    local duration="${3:-60}"
    
    log "INJECT" "Killing service processes: $service (signal: $signal, duration: ${duration}s)"
    
    # Get service PID(s)
    local pids
    pids=$(systemctl show --property MainPID --value "$service" 2>/dev/null || echo "")
    
    if [[ -z "$pids" || "$pids" == "0" ]]; then
        # Try to find process by name
        case "$service" in
            "blocklet-server")
                pids=$(pgrep -f "blocklet.*server" || echo "")
                ;;
            "nginx")
                pids=$(pgrep -f "nginx.*master" || echo "")
                ;;
            "redis-server")
                pids=$(pgrep -f "redis-server" || echo "")
                ;;
            *)
                pids=$(pgrep "$service" || echo "")
                ;;
        esac
    fi
    
    if [[ -n "$pids" && "$pids" != "0" ]]; then
        for pid in $pids; do
            if kill -0 "$pid" 2>/dev/null; then
                sudo kill -"$signal" "$pid"
                log "INJECT" "Sent $signal signal to $service process (PID: $pid)"
            fi
        done
    else
        log "WARNING" "No running processes found for service: $service"
        return 1
    fi
    
    return 0
}

# Scenario 3: Service Configuration Corruption
inject_config_corruption() {
    local service="$1"
    local corruption_type="${2:-syntax_error}"
    local duration="${3:-60}"
    
    log "INJECT" "Corrupting configuration for service: $service (type: $corruption_type)"
    
    local config_file=""
    local backup_file=""
    
    # Determine config file based on service
    case "$service" in
        "blocklet-server")
            config_file="/etc/systemd/system/blocklet-server.service"
            backup_file="$config_file.backup.test"
            ;;
        "nginx")
            config_file="/etc/nginx/nginx.conf"
            backup_file="$config_file.backup.test"
            ;;
        "redis-server")
            config_file="/etc/redis/redis.conf"
            backup_file="$config_file.backup.test"
            ;;
        "ssh")
            config_file="/etc/ssh/sshd_config"
            backup_file="$config_file.backup.test"
            ;;
        *)
            log "WARNING" "No configuration corruption test available for service: $service"
            return 1
            ;;
    esac
    
    # Check if config file exists
    if [[ ! -f "$config_file" ]]; then
        log "WARNING" "Configuration file not found: $config_file"
        return 1
    fi
    
    # Backup original configuration
    sudo cp "$config_file" "$backup_file"
    log "INFO" "Configuration backed up to: $backup_file"
    
    # Apply corruption based on type
    case "$corruption_type" in
        "syntax_error")
            # Add syntax error to config
            echo "INVALID_SYNTAX_ERROR_LINE_FOR_TESTING" | sudo tee -a "$config_file" > /dev/null
            log "INJECT" "Added syntax error to $config_file"
            ;;
        "permission_deny")
            # Change permissions to deny access
            sudo chmod 000 "$config_file"
            log "INJECT" "Removed read permissions from $config_file"
            ;;
        "empty_config")
            # Empty the configuration file
            sudo truncate -s 0 "$config_file"
            log "INJECT" "Emptied configuration file: $config_file"
            ;;
        "wrong_values")
            # Add incorrect configuration values
            case "$service" in
                "nginx")
                    echo "listen 99999;" | sudo tee -a "$config_file" > /dev/null
                    ;;
                "redis-server")
                    echo "port 99999" | sudo tee -a "$config_file" > /dev/null
                    ;;
                *)
                    echo "invalid_option invalid_value" | sudo tee -a "$config_file" > /dev/null
                    ;;
            esac
            log "INJECT" "Added invalid configuration values to $config_file"
            ;;
    esac
    
    return 0
}

# Scenario 4: Resource Exhaustion
inject_resource_exhaustion() {
    local service="$1"
    local resource_type="${2:-memory}"
    local duration="${3:-60}"
    
    log "INJECT" "Injecting resource exhaustion for service: $service (resource: $resource_type)"
    
    case "$resource_type" in
        "memory")
            inject_memory_exhaustion "$service" "$duration"
            ;;
        "cpu")
            inject_cpu_exhaustion "$service" "$duration"
            ;;
        "disk")
            inject_disk_exhaustion "$service" "$duration"
            ;;
        "file_descriptors")
            inject_fd_exhaustion "$service" "$duration"
            ;;
        *)
            log "WARNING" "Unknown resource type: $resource_type"
            return 1
            ;;
    esac
}

inject_memory_exhaustion() {
    local service="$1"
    local duration="$2"
    
    log "INJECT" "Creating memory pressure for service: $service"
    
    # Create memory pressure using stress-ng or dd
    if command -v stress-ng >/dev/null 2>&1; then
        # Use stress-ng if available
        stress-ng --vm 1 --vm-bytes 75% --timeout "${duration}s" &
        local stress_pid=$!
        echo "$stress_pid" > "/tmp/memory_stress_$service.pid"
        log "INJECT" "Memory stress started with stress-ng (PID: $stress_pid)"
    else
        # Fallback to memory allocation script
        (
            log "INFO" "Allocating memory to create pressure..."
            python3 -c "
import time
import gc
memory_chunks = []
try:
    while True:
        chunk = ' ' * (1024 * 1024 * 10)  # 10MB chunks
        memory_chunks.append(chunk)
        time.sleep(0.1)
except MemoryError:
    time.sleep($duration)
finally:
    gc.collect()
" &
        local stress_pid=$!
        echo "$stress_pid" > "/tmp/memory_stress_$service.pid"
        log "INJECT" "Memory stress started with Python script (PID: $stress_pid)"
        )
    fi
    
    # Monitor service impact
    sleep 5
    if systemctl is-active --quiet "$service"; then
        log "INFO" "Service $service still active under memory pressure"
    else
        log "WARNING" "Service $service appears to have stopped due to memory pressure"
    fi
    
    return 0
}

inject_cpu_exhaustion() {
    local service="$1"
    local duration="$2"
    
    log "INJECT" "Creating CPU pressure for service: $service"
    
    # Get number of CPU cores
    local cpu_cores
    cpu_cores=$(nproc)
    
    # Create CPU stress
    if command -v stress-ng >/dev/null 2>&1; then
        stress-ng --cpu "$cpu_cores" --timeout "${duration}s" &
        local stress_pid=$!
        echo "$stress_pid" > "/tmp/cpu_stress_$service.pid"
        log "INJECT" "CPU stress started with stress-ng using $cpu_cores cores (PID: $stress_pid)"
    else
        # Fallback to busy loops
        for ((i=1; i<=cpu_cores; i++)); do
            (while true; do :; done) &
            echo $! >> "/tmp/cpu_stress_$service.pid"
        done
        log "INJECT" "CPU stress started with $cpu_cores busy loops"
    fi
    
    # Monitor service impact
    sleep 5
    if systemctl is-active --quiet "$service"; then
        log "INFO" "Service $service still active under CPU pressure"
    else
        log "WARNING" "Service $service appears to have stopped due to CPU pressure"
    fi
    
    return 0
}

inject_disk_exhaustion() {
    local service="$1"
    local duration="$2"
    
    log "INJECT" "Creating disk I/O pressure for service: $service"
    
    # Determine appropriate directory for I/O stress
    local stress_dir="/tmp/disk_stress_$service"
    mkdir -p "$stress_dir"
    
    # Create disk I/O stress
    if command -v stress-ng >/dev/null 2>&1; then
        stress-ng --io 4 --hdd 2 --hdd-bytes 1G --temp-path "$stress_dir" --timeout "${duration}s" &
        local stress_pid=$!
        echo "$stress_pid" > "/tmp/disk_stress_$service.pid"
        log "INJECT" "Disk I/O stress started with stress-ng (PID: $stress_pid)"
    else
        # Fallback to dd commands
        for i in {1..4}; do
            (
                while true; do
                    dd if=/dev/zero of="$stress_dir/testfile_$i" bs=1M count=100 2>/dev/null
                    rm -f "$stress_dir/testfile_$i"
                done
            ) &
            echo $! >> "/tmp/disk_stress_$service.pid"
        done
        log "INJECT" "Disk I/O stress started with dd commands"
    fi
    
    # Monitor service impact
    sleep 5
    if systemctl is-active --quiet "$service"; then
        log "INFO" "Service $service still active under disk I/O pressure"
    else
        log "WARNING" "Service $service appears to have stopped due to disk I/O pressure"
    fi
    
    return 0
}

inject_fd_exhaustion() {
    local service="$1"
    local duration="$2"
    
    log "INJECT" "Creating file descriptor exhaustion for service: $service"
    
    # Create file descriptor exhaustion
    (
        exec {fd_array[@]}< <(yes)
        for ((i=1; i<=1000; i++)); do
            exec {fd_array[$i]}< <(sleep "$duration")
        done
        wait
    ) &
    
    local stress_pid=$!
    echo "$stress_pid" > "/tmp/fd_stress_$service.pid"
    log "INJECT" "File descriptor exhaustion started (PID: $stress_pid)"
    
    # Monitor service impact
    sleep 5
    if systemctl is-active --quiet "$service"; then
        log "INFO" "Service $service still active with FD exhaustion"
    else
        log "WARNING" "Service $service appears to have stopped due to FD exhaustion"
    fi
    
    return 0
}

# Scenario 5: Dependency Service Failures
inject_dependency_failure() {
    local service="$1"
    local dependency="${2:-auto}"
    local duration="${3:-60}"
    
    log "INJECT" "Injecting dependency failure for service: $service"
    
    # Auto-detect dependencies if not specified
    if [[ "$dependency" == "auto" ]]; then
        case "$service" in
            "blocklet-server")
                dependency="redis-server"
                ;;
            "nginx")
                dependency="network-online.target"
                ;;
            *)
                log "WARNING" "No auto-dependency available for service: $service"
                return 1
                ;;
        esac
    fi
    
    log "INJECT" "Stopping dependency service: $dependency for $service"
    
    # Stop the dependency
    if systemctl is-active --quiet "$dependency"; then
        sudo systemctl stop "$dependency"
        log "INJECT" "Dependency $dependency stopped"
    else
        log "WARNING" "Dependency $dependency was already stopped"
    fi
    
    # Monitor main service impact
    sleep 5
    if systemctl is-active --quiet "$service"; then
        log "INFO" "Service $service still active without dependency $dependency"
    else
        log "WARNING" "Service $service stopped due to dependency failure"
    fi
    
    return 0
}

# Scenario 6: Service File System Issues
inject_filesystem_issues() {
    local service="$1"
    local issue_type="${2:-permissions}"
    local duration="${3:-60}"
    
    log "INJECT" "Injecting filesystem issues for service: $service (type: $issue_type)"
    
    case "$issue_type" in
        "permissions")
            inject_permission_issues "$service"
            ;;
        "disk_full")
            inject_disk_full "$service"
            ;;
        "readonly")
            inject_readonly_filesystem "$service"
            ;;
        "missing_files")
            inject_missing_files "$service"
            ;;
        *)
            log "WARNING" "Unknown filesystem issue type: $issue_type"
            return 1
            ;;
    esac
}

inject_permission_issues() {
    local service="$1"
    
    log "INJECT" "Creating permission issues for service: $service"
    
    case "$service" in
        "blocklet-server")
            # Change ownership of critical directories
            sudo chown root:root "$BLOCKLET_DATA_DIR" 2>/dev/null || true
            sudo chown root:root "$BLOCKLET_CONFIG_DIR" 2>/dev/null || true
            sudo chmod 700 "$BLOCKLET_DATA_DIR" 2>/dev/null || true
            log "INJECT" "Changed ownership and permissions for Blocklet Server directories"
            ;;
        "nginx")
            # Change permissions on nginx directories
            sudo chmod 000 /var/log/nginx 2>/dev/null || true
            sudo chmod 000 /var/lib/nginx 2>/dev/null || true
            log "INJECT" "Removed permissions from nginx directories"
            ;;
        "redis-server")
            # Change permissions on redis directories
            sudo chmod 000 /var/lib/redis 2>/dev/null || true
            sudo chmod 000 /var/log/redis 2>/dev/null || true
            log "INJECT" "Removed permissions from redis directories"
            ;;
    esac
    
    return 0
}

inject_disk_full() {
    local service="$1"
    
    log "INJECT" "Simulating disk full condition for service: $service"
    
    # Determine target directory based on service
    local target_dir="/tmp"
    case "$service" in
        "blocklet-server")
            target_dir="$BLOCKLET_DATA_DIR"
            ;;
        "nginx")
            target_dir="/var/log/nginx"
            ;;
        "redis-server")
            target_dir="/var/lib/redis"
            ;;
    esac
    
    # Create large file to fill disk
    local fill_file="$target_dir/disk_fill_test.tmp"
    
    # Get available space and fill most of it
    local available_space
    available_space=$(df "$target_dir" | awk 'NR==2 {print $4}')
    local fill_size=$((available_space - 1000)) # Leave 1MB free
    
    if [[ $fill_size -gt 0 ]]; then
        dd if=/dev/zero of="$fill_file" bs=1K count="$fill_size" 2>/dev/null &
        local dd_pid=$!
        echo "$dd_pid" > "/tmp/disk_fill_$service.pid"
        echo "$fill_file" > "/tmp/disk_fill_$service.file"
        log "INJECT" "Creating ${fill_size}KB file to simulate disk full"
    else
        log "WARNING" "Insufficient space to simulate disk full condition"
        return 1
    fi
    
    return 0
}

inject_readonly_filesystem() {
    local service="$1"
    
    log "WARNING" "Read-only filesystem injection requires root privileges and can be dangerous"
    log "INFO" "Skipping read-only filesystem injection for safety"
    return 0
}

inject_missing_files() {
    local service="$1"
    
    log "INJECT" "Creating missing files condition for service: $service"
    
    case "$service" in
        "blocklet-server")
            # Move critical files temporarily
            if [[ -f "/etc/systemd/system/blocklet-server.service" ]]; then
                sudo mv "/etc/systemd/system/blocklet-server.service" "/tmp/blocklet-server.service.backup"
                log "INJECT" "Moved blocklet-server systemd service file"
            fi
            ;;
        "nginx")
            # Move nginx configuration
            if [[ -f "/etc/nginx/nginx.conf" ]]; then
                sudo mv "/etc/nginx/nginx.conf" "/tmp/nginx.conf.backup"
                log "INJECT" "Moved nginx configuration file"
            fi
            ;;
        "redis-server")
            # Move redis configuration
            if [[ -f "/etc/redis/redis.conf" ]]; then
                sudo mv "/etc/redis/redis.conf" "/tmp/redis.conf.backup"
                log "INJECT" "Moved redis configuration file"
            fi
            ;;
    esac
    
    return 0
}

# ============================================================================
# Recovery Functions
# ============================================================================

recover_service_stop() {
    local service="$1"
    
    log "RECOVER" "Starting service: $service"
    
    if ! systemctl is-active --quiet "$service"; then
        sudo systemctl start "$service"
        sleep 3
        
        if systemctl is-active --quiet "$service"; then
            log "SUCCESS" "Service $service recovered successfully"
            return 0
        else
            log "FAILURE" "Failed to recover service $service"
            return 1
        fi
    else
        log "INFO" "Service $service is already running"
        return 0
    fi
}

recover_service_kill() {
    local service="$1"
    
    log "RECOVER" "Recovering from process kill for service: $service"
    
    # Try to restart the service
    sudo systemctl restart "$service"
    sleep 5
    
    if systemctl is-active --quiet "$service"; then
        log "SUCCESS" "Service $service recovered from process kill"
        return 0
    else
        log "FAILURE" "Failed to recover service $service from process kill"
        return 1
    fi
}

recover_config_corruption() {
    local service="$1"
    
    log "RECOVER" "Recovering configuration for service: $service"
    
    local config_file=""
    local backup_file=""
    
    # Determine config file based on service
    case "$service" in
        "blocklet-server")
            config_file="/etc/systemd/system/blocklet-server.service"
            backup_file="$config_file.backup.test"
            ;;
        "nginx")
            config_file="/etc/nginx/nginx.conf"
            backup_file="$config_file.backup.test"
            ;;
        "redis-server")
            config_file="/etc/redis/redis.conf"
            backup_file="$config_file.backup.test"
            ;;
        "ssh")
            config_file="/etc/ssh/sshd_config"
            backup_file="$config_file.backup.test"
            ;;
    esac
    
    # Restore from backup
    if [[ -f "$backup_file" ]]; then
        sudo mv "$backup_file" "$config_file"
        sudo chmod 644 "$config_file"
        log "RECOVER" "Configuration restored from backup: $config_file"
        
        # Reload service if needed
        case "$service" in
            "blocklet-server")
                sudo systemctl daemon-reload
                sudo systemctl restart "$service"
                ;;
            "nginx")
                sudo nginx -t && sudo systemctl restart nginx
                ;;
            "redis-server")
                sudo systemctl restart redis-server
                ;;
            "ssh")
                sudo systemctl restart ssh
                ;;
        esac
        
        log "SUCCESS" "Service $service configuration recovered"
        return 0
    else
        log "FAILURE" "No backup file found for $service configuration"
        return 1
    fi
}

recover_resource_exhaustion() {
    local service="$1"
    local resource_type="${2:-memory}"
    
    log "RECOVER" "Recovering from resource exhaustion: $resource_type for service $service"
    
    # Kill stress processes
    local pid_file="/tmp/${resource_type}_stress_${service}.pid"
    if [[ -f "$pid_file" ]]; then
        while read -r pid; do
            kill "$pid" 2>/dev/null || true
        done < "$pid_file"
        rm -f "$pid_file"
        log "RECOVER" "Terminated $resource_type stress processes"
    fi
    
    # Clean up stress files
    case "$resource_type" in
        "disk")
            rm -rf "/tmp/disk_stress_$service"
            local fill_file_marker="/tmp/disk_fill_${service}.file"
            if [[ -f "$fill_file_marker" ]]; then
                local fill_file
                fill_file=$(cat "$fill_file_marker")
                rm -f "$fill_file" "$fill_file_marker"
                log "RECOVER" "Removed disk fill file: $fill_file"
            fi
            ;;
    esac
    
    # Restart service if needed
    if ! systemctl is-active --quiet "$service"; then
        sudo systemctl restart "$service"
        log "RECOVER" "Restarted service $service after resource exhaustion"
    fi
    
    # Wait and verify recovery
    sleep 5
    if systemctl is-active --quiet "$service"; then
        log "SUCCESS" "Service $service recovered from $resource_type exhaustion"
        return 0
    else
        log "FAILURE" "Service $service failed to recover from $resource_type exhaustion"
        return 1
    fi
}

recover_dependency_failure() {
    local service="$1"
    local dependency="${2:-auto}"
    
    log "RECOVER" "Recovering dependency for service: $service"
    
    # Auto-detect dependencies if not specified
    if [[ "$dependency" == "auto" ]]; then
        case "$service" in
            "blocklet-server")
                dependency="redis-server"
                ;;
            "nginx")
                dependency="network-online.target"
                ;;
        esac
    fi
    
    # Start dependency
    if [[ "$dependency" != "network-online.target" ]]; then
        sudo systemctl start "$dependency"
        log "RECOVER" "Started dependency service: $dependency"
    fi
    
    # Start main service
    sudo systemctl start "$service"
    sleep 5
    
    if systemctl is-active --quiet "$service"; then
        log "SUCCESS" "Service $service recovered with dependency $dependency"
        return 0
    else
        log "FAILURE" "Service $service failed to recover with dependency"
        return 1
    fi
}

recover_filesystem_issues() {
    local service="$1"
    local issue_type="${2:-permissions}"
    
    log "RECOVER" "Recovering filesystem issues for service: $service (type: $issue_type)"
    
    case "$issue_type" in
        "permissions")
            recover_permission_issues "$service"
            ;;
        "disk_full")
            recover_disk_full "$service"
            ;;
        "missing_files")
            recover_missing_files "$service"
            ;;
    esac
}

recover_permission_issues() {
    local service="$1"
    
    log "RECOVER" "Fixing permission issues for service: $service"
    
    case "$service" in
        "blocklet-server")
            sudo chown -R arcblock:arcblock "$BLOCKLET_DATA_DIR" 2>/dev/null || true
            sudo chown -R arcblock:arcblock "$BLOCKLET_CONFIG_DIR" 2>/dev/null || true
            sudo chmod 755 "$BLOCKLET_DATA_DIR" 2>/dev/null || true
            sudo chmod 755 "$BLOCKLET_CONFIG_DIR" 2>/dev/null || true
            log "RECOVER" "Fixed ownership and permissions for Blocklet Server directories"
            ;;
        "nginx")
            sudo chmod 755 /var/log/nginx 2>/dev/null || true
            sudo chmod 755 /var/lib/nginx 2>/dev/null || true
            sudo chown -R www-data:www-data /var/log/nginx 2>/dev/null || true
            sudo chown -R www-data:www-data /var/lib/nginx 2>/dev/null || true
            log "RECOVER" "Fixed permissions for nginx directories"
            ;;
        "redis-server")
            sudo chmod 755 /var/lib/redis 2>/dev/null || true
            sudo chmod 755 /var/log/redis 2>/dev/null || true
            sudo chown -R redis:redis /var/lib/redis 2>/dev/null || true
            sudo chown -R redis:redis /var/log/redis 2>/dev/null || true
            log "RECOVER" "Fixed permissions for redis directories"
            ;;
    esac
    
    return 0
}

recover_disk_full() {
    local service="$1"
    
    log "RECOVER" "Recovering from disk full condition for service: $service"
    
    # Remove fill files
    local fill_file_marker="/tmp/disk_fill_${service}.file"
    if [[ -f "$fill_file_marker" ]]; then
        local fill_file
        fill_file=$(cat "$fill_file_marker")
        rm -f "$fill_file" "$fill_file_marker"
        log "RECOVER" "Removed disk fill file: $fill_file"
    fi
    
    # Kill any ongoing fill processes
    local pid_file="/tmp/disk_fill_${service}.pid"
    if [[ -f "$pid_file" ]]; then
        while read -r pid; do
            kill "$pid" 2>/dev/null || true
        done < "$pid_file"
        rm -f "$pid_file"
        log "RECOVER" "Terminated disk fill processes"
    fi
    
    return 0
}

recover_missing_files() {
    local service="$1"
    
    log "RECOVER" "Recovering missing files for service: $service"
    
    case "$service" in
        "blocklet-server")
            if [[ -f "/tmp/blocklet-server.service.backup" ]]; then
                sudo mv "/tmp/blocklet-server.service.backup" "/etc/systemd/system/blocklet-server.service"
                sudo systemctl daemon-reload
                log "RECOVER" "Restored blocklet-server systemd service file"
            fi
            ;;
        "nginx")
            if [[ -f "/tmp/nginx.conf.backup" ]]; then
                sudo mv "/tmp/nginx.conf.backup" "/etc/nginx/nginx.conf"
                log "RECOVER" "Restored nginx configuration file"
            fi
            ;;
        "redis-server")
            if [[ -f "/tmp/redis.conf.backup" ]]; then
                sudo mv "/tmp/redis.conf.backup" "/etc/redis/redis.conf"
                log "RECOVER" "Restored redis configuration file"
            fi
            ;;
    esac
    
    return 0
}

# ============================================================================
# Main Functions
# ============================================================================

run_service_failure_scenario() {
    local scenario="$1"
    local service="$2"
    local duration="${3:-60}"
    local params="${4:-}"
    
    log "INFO" "Running service failure scenario: $scenario for service: $service"
    
    case "$scenario" in
        "service_stop")
            inject_service_stop "$service" "$duration"
            ;;
        "service_kill")
            inject_service_kill "$service" "${params:-TERM}" "$duration"
            ;;
        "config_corruption")
            inject_config_corruption "$service" "${params:-syntax_error}" "$duration"
            ;;
        "memory_exhaustion")
            inject_resource_exhaustion "$service" "memory" "$duration"
            ;;
        "cpu_exhaustion")
            inject_resource_exhaustion "$service" "cpu" "$duration"
            ;;
        "disk_exhaustion")
            inject_resource_exhaustion "$service" "disk" "$duration"
            ;;
        "fd_exhaustion")
            inject_resource_exhaustion "$service" "file_descriptors" "$duration"
            ;;
        "dependency_failure")
            inject_dependency_failure "$service" "${params:-auto}" "$duration"
            ;;
        "permission_issues")
            inject_filesystem_issues "$service" "permissions" "$duration"
            ;;
        "disk_full")
            inject_filesystem_issues "$service" "disk_full" "$duration"
            ;;
        "missing_files")
            inject_filesystem_issues "$service" "missing_files" "$duration"
            ;;
        *)
            log "FAILURE" "Unknown service failure scenario: $scenario"
            return 1
            ;;
    esac
}

recover_service_failure_scenario() {
    local scenario="$1"
    local service="$2"
    local params="${3:-}"
    
    log "INFO" "Recovering from service failure scenario: $scenario for service: $service"
    
    case "$scenario" in
        "service_stop")
            recover_service_stop "$service"
            ;;
        "service_kill")
            recover_service_kill "$service"
            ;;
        "config_corruption")
            recover_config_corruption "$service"
            ;;
        "memory_exhaustion"|"cpu_exhaustion"|"disk_exhaustion"|"fd_exhaustion")
            local resource_type
            case "$scenario" in
                "memory_exhaustion") resource_type="memory" ;;
                "cpu_exhaustion") resource_type="cpu" ;;
                "disk_exhaustion") resource_type="disk" ;;
                "fd_exhaustion") resource_type="file_descriptors" ;;
            esac
            recover_resource_exhaustion "$service" "$resource_type"
            ;;
        "dependency_failure")
            recover_dependency_failure "$service" "${params:-auto}"
            ;;
        "permission_issues")
            recover_filesystem_issues "$service" "permissions"
            ;;
        "disk_full")
            recover_filesystem_issues "$service" "disk_full"
            ;;
        "missing_files")
            recover_filesystem_issues "$service" "missing_files"
            ;;
        *)
            log "WARNING" "No specific recovery procedure for scenario: $scenario"
            # Generic cleanup
            recover_service_stop "$service" 2>/dev/null || true
            recover_config_corruption "$service" 2>/dev/null || true
            recover_resource_exhaustion "$service" "memory" 2>/dev/null || true
            recover_resource_exhaustion "$service" "cpu" 2>/dev/null || true
            recover_resource_exhaustion "$service" "disk" 2>/dev/null || true
            recover_dependency_failure "$service" "auto" 2>/dev/null || true
            recover_filesystem_issues "$service" "permissions" 2>/dev/null || true
            recover_filesystem_issues "$service" "disk_full" 2>/dev/null || true
            recover_filesystem_issues "$service" "missing_files" 2>/dev/null || true
            ;;
    esac
}

# ============================================================================
# Usage and Help
# ============================================================================

show_usage() {
    cat << EOF
ArcDeploy Service Failure Injection Scenarios

Usage: $SCRIPT_NAME [OPTION]... SCENARIO SERVICE [DURATION] [PARAMS]

SCENARIOS:
  service_stop          Stop service completely
  service_kill          Kill service processes (params: signal)
  config_corruption     Corrupt service configuration (params: type)
  memory_exhaustion     Exhaust system memory
  cpu_exhaustion        Exhaust CPU resources
  disk_exhaustion       Exhaust disk I/O
  fd_exhaustion         Exhaust file descriptors
  dependency_failure    Stop service dependencies (params: dependency)
  permission_issues     Create permission problems
  disk_full             Fill disk space
  missing_files         Remove critical files

SERVICES:
  blocklet-server       Blocklet Server service
  nginx                 Nginx web server
  redis-server          Redis database
  ssh                   SSH daemon
  fail2ban              Fail2ban intrusion prevention
  ufw                   UFW firewall

CORRUPTION TYPES (for config_corruption):
  syntax_error          Add syntax errors to config
  permission_deny       Remove read permissions
  empty_config          Empty configuration file
  wrong_values          Add invalid configuration values

OPTIONS:
  -r, --recover SCENARIO SERVICE    Recover from specific scenario
  -l, --list                        List all available scenarios
  -s, --services                    List all supported services
  -h, --help                        Show this help message
  -v, --version                     Show script version

EXAMPLES:
  $SCRIPT_NAME service_stop blocklet-server 60
  $SCRIPT_NAME service_kill nginx 120 KILL
  $SCRIPT_NAME config_corruption redis-server 90 syntax_error
  $SCRIPT_NAME memory_exhaustion blocklet-server 180
  $SCRIPT_NAME dependency_failure blocklet-server 60 redis-server
  $SCRIPT_NAME --recover service_stop blocklet-server

DURATION: Time in seconds (default: 60)
PARAMS: Scenario-specific parameters

EOF
}

# ============================================================================
# Main Script Logic
# ============================================================================

main() {
    if [[ $# -eq 0 ]]; then
        show_usage
        exit 1
    fi
    
    case "$1" in
        -h|--help)
            show_usage
            exit 0
            ;;
        -v|--version)
            echo "$SCRIPT_NAME version $SCRIPT_VERSION"
            exit 0
            ;;
        -l|--list)
            echo "Available service failure scenarios:"
            echo "  - service_stop, service_kill, config_corruption"
            echo "  - memory_exhaustion, cpu_exhaustion, disk_exhaustion, fd_exhaustion"
            echo "  - dependency_failure, permission_issues, disk_full, missing_files"
            exit 0
            ;;
        -s|--services)
            echo "Supported services:"
            echo "  Critical Services: ${CRITICAL_SERVICES[*]}"
            echo "  Security Services: ${SECURITY_SERVICES[*]}"
            echo "  All Services: ${SERVICES[*]}"
            exit 0
            ;;
        -r|--recover)
            if [[ $# -lt 3 ]]; then
                echo "Error: Scenario and service name required for recovery"
                echo "Usage: $SCRIPT_NAME --recover SCENARIO SERVICE [PARAMS]"
                exit 1
            fi
            recover_service_failure_scenario "$2" "$3" "${4:-}"
            exit $?
            ;;
        *)
            if [[ $# -lt 2 ]]; then
                echo "Error: Scenario and service name required"
                echo "Usage: $SCRIPT_NAME SCENARIO SERVICE [DURATION] [PARAMS]"
                exit 1
            fi
            
            scenario="$1"
            service="$2"
            duration="${3:-60}"
            params="${4:-}"
            
            # Validate service
            if [[ ! " ${SERVICES[*]} " =~ " $service " ]]; then
                log "WARNING" "Service '$service' not in supported list, proceeding anyway"
            fi
            
            run_service_failure_scenario "$scenario" "$service" "$duration" "$params"
            exit $?
            ;;
    esac
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi