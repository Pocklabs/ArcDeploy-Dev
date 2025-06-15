#!/bin/bash

# ArcDeploy System Diagnostics Script
# Comprehensive system analysis and troubleshooting tool for deployment issues

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

# ============================================================================
# Configuration
# ============================================================================
readonly LOG_FILE="/tmp/arcdeploy-diagnostics.log"
readonly REPORT_FILE="/tmp/arcdeploy-diagnostics-report.txt"
readonly JSON_REPORT_FILE="/tmp/arcdeploy-diagnostics-report.json"

# Color output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color

# Diagnostic levels
readonly LEVEL_INFO="INFO"
readonly LEVEL_WARNING="WARNING"
readonly LEVEL_ERROR="ERROR"
readonly LEVEL_CRITICAL="CRITICAL"

# ============================================================================
# Global Variables
# ============================================================================
declare -A DIAGNOSTIC_RESULTS=()
declare -A SYSTEM_INFO=()
declare -A PERFORMANCE_METRICS=()
declare -A SECURITY_STATUS=()
declare -A NETWORK_STATUS=()
declare -A SERVICE_STATUS=()
declare -g TOTAL_CHECKS=0
declare -g PASSED_CHECKS=0
declare -g WARNING_CHECKS=0
declare -g FAILED_CHECKS=0
declare -g CRITICAL_CHECKS=0

# ============================================================================
# Logging and Output Functions
# ============================================================================

log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        "$LEVEL_INFO")
            echo -e "${BLUE}[INFO]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        "$LEVEL_WARNING")
            echo -e "${YELLOW}[WARNING]${NC} $message" | tee -a "$LOG_FILE"
            ((WARNING_CHECKS++))
            ;;
        "$LEVEL_ERROR")
            echo -e "${RED}[ERROR]${NC} $message" | tee -a "$LOG_FILE"
            ((FAILED_CHECKS++))
            ;;
        "$LEVEL_CRITICAL")
            echo -e "${RED}[CRITICAL]${NC} $message" | tee -a "$LOG_FILE"
            ((CRITICAL_CHECKS++))
            ;;
    esac
    
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

success() {
    local message="$1"
    echo -e "${GREEN}[PASS]${NC} $message" | tee -a "$LOG_FILE"
    ((PASSED_CHECKS++))
}

section_header() {
    local title="$1"
    local separator=$(printf '=%.0s' $(seq 1 ${#title}))
    
    echo ""
    echo -e "${CYAN}$separator${NC}"
    echo -e "${CYAN}$title${NC}"
    echo -e "${CYAN}$separator${NC}"
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
# System Information Collection
# ============================================================================

collect_system_info() {
    section_header "System Information Collection"
    
    # Basic system information
    SYSTEM_INFO["hostname"]=$(hostname 2>/dev/null || echo "unknown")
    SYSTEM_INFO["os_name"]=$(lsb_release -d 2>/dev/null | cut -f2 | tr -d '\t' || echo "unknown")
    SYSTEM_INFO["os_version"]=$(lsb_release -r 2>/dev/null | cut -f2 | tr -d '\t' || echo "unknown")
    SYSTEM_INFO["kernel_version"]=$(uname -r 2>/dev/null || echo "unknown")
    SYSTEM_INFO["architecture"]=$(uname -m 2>/dev/null || echo "unknown")
    SYSTEM_INFO["uptime"]=$(uptime -p 2>/dev/null || echo "unknown")
    SYSTEM_INFO["timezone"]=$(timedatectl show --property=Timezone --value 2>/dev/null || echo "unknown")
    
    # Hardware information
    SYSTEM_INFO["cpu_model"]=$(grep "model name" /proc/cpuinfo 2>/dev/null | head -1 | cut -d: -f2 | sed 's/^ *//' || echo "unknown")
    SYSTEM_INFO["cpu_cores"]=$(nproc 2>/dev/null || echo "unknown")
    SYSTEM_INFO["total_memory"]=$(free -h 2>/dev/null | awk '/^Mem:/ {print $2}' || echo "unknown")
    SYSTEM_INFO["total_disk"]=$(df -h / 2>/dev/null | awk 'NR==2 {print $2}' || echo "unknown")
    
    # Network information
    SYSTEM_INFO["public_ip"]=$(curl -s -m 5 ifconfig.me 2>/dev/null || echo "unknown")
    SYSTEM_INFO["private_ip"]=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "unknown")
    SYSTEM_INFO["dns_servers"]=$(grep nameserver /etc/resolv.conf 2>/dev/null | awk '{print $2}' | tr '\n' ',' | sed 's/,$//' || echo "unknown")
    
    # Display collected information
    for key in "${!SYSTEM_INFO[@]}"; do
        printf "%-20s: %s\n" "$key" "${SYSTEM_INFO[$key]}"
    done
    
    success "System information collected"
}

# ============================================================================
# Hardware and Resource Checks
# ============================================================================

check_system_requirements() {
    section_header "System Requirements Check"
    local issues=0
    
    ((TOTAL_CHECKS++))
    
    # Check CPU cores
    local cpu_cores=${SYSTEM_INFO["cpu_cores"]}
    if [[ "$cpu_cores" != "unknown" ]]; then
        if [[ $cpu_cores -ge 2 ]]; then
            success "CPU cores: $cpu_cores (sufficient)"
        else
            log "$LEVEL_WARNING" "CPU cores: $cpu_cores (minimum 2 recommended)"
            ((issues++))
        fi
    fi
    
    # Check memory
    local memory_kb=$(free 2>/dev/null | awk '/^Mem:/ {print $2}' || echo "0")
    local memory_gb=$((memory_kb / 1024 / 1024))
    
    if [[ $memory_gb -ge 4 ]]; then
        success "Memory: ${memory_gb}GB (sufficient)"
    elif [[ $memory_gb -ge 2 ]]; then
        log "$LEVEL_WARNING" "Memory: ${memory_gb}GB (minimum for basic deployment)"
        ((issues++))
    else
        log "$LEVEL_ERROR" "Memory: ${memory_gb}GB (insufficient - minimum 2GB required)"
        ((issues++))
    fi
    
    # Check disk space
    local disk_usage=$(df / 2>/dev/null | awk 'NR==2 {print $5}' | sed 's/%//' || echo "100")
    local available_gb=$(df -BG / 2>/dev/null | awk 'NR==2 {print $4}' | sed 's/G//' || echo "0")
    
    if [[ $available_gb -ge 20 ]]; then
        success "Disk space: ${available_gb}GB available (sufficient)"
    elif [[ $available_gb -ge 10 ]]; then
        log "$LEVEL_WARNING" "Disk space: ${available_gb}GB available (tight but usable)"
        ((issues++))
    else
        log "$LEVEL_ERROR" "Disk space: ${available_gb}GB available (insufficient - minimum 10GB required)"
        ((issues++))
    fi
    
    # Check disk usage percentage
    if [[ $disk_usage -lt 80 ]]; then
        success "Disk usage: ${disk_usage}% (healthy)"
    elif [[ $disk_usage -lt 90 ]]; then
        log "$LEVEL_WARNING" "Disk usage: ${disk_usage}% (getting full)"
        ((issues++))
    else
        log "$LEVEL_ERROR" "Disk usage: ${disk_usage}% (critically full)"
        ((issues++))
    fi
    
    if [[ $issues -eq 0 ]]; then
        success "All system requirements met"
    else
        log "$LEVEL_WARNING" "System requirements check completed with $issues issues"
    fi
}

check_performance_metrics() {
    section_header "Performance Metrics"
    
    # CPU load average
    local load_avg=$(uptime 2>/dev/null | awk -F'load average:' '{print $2}' | sed 's/^ *//' || echo "unknown")
    PERFORMANCE_METRICS["load_average"]="$load_avg"
    
    if [[ "$load_avg" != "unknown" ]]; then
        local load_1min=$(echo "$load_avg" | awk '{print $1}' | sed 's/,//')
        local cpu_cores=${SYSTEM_INFO["cpu_cores"]}
        
        if [[ "$cpu_cores" != "unknown" ]] && [[ $(echo "$load_1min < $cpu_cores" | bc -l 2>/dev/null || echo "1") -eq 1 ]]; then
            success "CPU load: $load_1min (normal for $cpu_cores cores)"
        else
            log "$LEVEL_WARNING" "CPU load: $load_1min (high for $cpu_cores cores)"
        fi
    fi
    
    # Memory usage
    local memory_usage=$(free 2>/dev/null | awk '/^Mem:/ {printf "%.1f", ($3/$2) * 100}' || echo "unknown")
    PERFORMANCE_METRICS["memory_usage_percent"]="$memory_usage"
    
    if [[ "$memory_usage" != "unknown" ]]; then
        if [[ $(echo "$memory_usage < 80" | bc -l 2>/dev/null || echo "0") -eq 1 ]]; then
            success "Memory usage: ${memory_usage}% (healthy)"
        elif [[ $(echo "$memory_usage < 90" | bc -l 2>/dev/null || echo "0") -eq 1 ]]; then
            log "$LEVEL_WARNING" "Memory usage: ${memory_usage}% (high)"
        else
            log "$LEVEL_ERROR" "Memory usage: ${memory_usage}% (critical)"
        fi
    fi
    
    # Disk I/O
    if command -v iostat >/dev/null 2>&1; then
        local io_wait=$(iostat -c 1 2 2>/dev/null | tail -1 | awk '{print $4}' || echo "unknown")
        PERFORMANCE_METRICS["io_wait_percent"]="$io_wait"
        
        if [[ "$io_wait" != "unknown" ]]; then
            if [[ $(echo "$io_wait < 10" | bc -l 2>/dev/null || echo "1") -eq 1 ]]; then
                success "I/O wait: ${io_wait}% (good)"
            else
                log "$LEVEL_WARNING" "I/O wait: ${io_wait}% (high disk activity)"
            fi
        fi
    fi
    
    # Process count
    local process_count=$(ps aux 2>/dev/null | wc -l || echo "unknown")
    PERFORMANCE_METRICS["process_count"]="$process_count"
    
    if [[ "$process_count" != "unknown" ]]; then
        if [[ $process_count -lt 300 ]]; then
            success "Process count: $process_count (normal)"
        else
            log "$LEVEL_WARNING" "Process count: $process_count (high)"
        fi
    fi
}

# ============================================================================
# Network Diagnostics
# ============================================================================

check_network_connectivity() {
    section_header "Network Connectivity Check"
    local issues=0
    
    # Test DNS resolution
    ((TOTAL_CHECKS++))
    if nslookup google.com >/dev/null 2>&1; then
        success "DNS resolution: Working"
        NETWORK_STATUS["dns_resolution"]="working"
    else
        log "$LEVEL_ERROR" "DNS resolution: Failed"
        NETWORK_STATUS["dns_resolution"]="failed"
        ((issues++))
    fi
    
    # Test internet connectivity
    ((TOTAL_CHECKS++))
    if ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1; then
        success "Internet connectivity: Working"
        NETWORK_STATUS["internet_connectivity"]="working"
    else
        log "$LEVEL_ERROR" "Internet connectivity: Failed"
        NETWORK_STATUS["internet_connectivity"]="failed"
        ((issues++))
    fi
    
    # Test HTTP connectivity
    ((TOTAL_CHECKS++))
    if curl -s -m 5 http://httpbin.org/status/200 >/dev/null 2>&1; then
        success "HTTP connectivity: Working"
        NETWORK_STATUS["http_connectivity"]="working"
    else
        log "$LEVEL_WARNING" "HTTP connectivity: Failed or slow"
        NETWORK_STATUS["http_connectivity"]="failed"
        ((issues++))
    fi
    
    # Test HTTPS connectivity
    ((TOTAL_CHECKS++))
    if curl -s -m 5 https://httpbin.org/status/200 >/dev/null 2>&1; then
        success "HTTPS connectivity: Working"
        NETWORK_STATUS["https_connectivity"]="working"
    else
        log "$LEVEL_WARNING" "HTTPS connectivity: Failed or slow"
        NETWORK_STATUS["https_connectivity"]="failed"
        ((issues++))
    fi
    
    # Check network interfaces
    local interfaces=$(ip link show 2>/dev/null | grep "state UP" | awk '{print $2}' | sed 's/:$//' | tr '\n' ',' | sed 's/,$//' || echo "unknown")
    NETWORK_STATUS["active_interfaces"]="$interfaces"
    
    if [[ "$interfaces" != "unknown" ]] && [[ -n "$interfaces" ]]; then
        success "Active network interfaces: $interfaces"
    else
        log "$LEVEL_ERROR" "No active network interfaces found"
        ((issues++))
    fi
    
    # Check listening ports
    local ssh_port=$(ss -tlnp 2>/dev/null | grep ":22 " | wc -l || echo "0")
    local alt_ssh_port=$(ss -tlnp 2>/dev/null | grep ":2222 " | wc -l || echo "0")
    
    if [[ $ssh_port -gt 0 ]]; then
        success "SSH service: Listening on port 22"
        NETWORK_STATUS["ssh_port_22"]="listening"
    elif [[ $alt_ssh_port -gt 0 ]]; then
        success "SSH service: Listening on port 2222"
        NETWORK_STATUS["ssh_port_2222"]="listening"
    else
        log "$LEVEL_WARNING" "SSH service: Not detected on standard ports"
        NETWORK_STATUS["ssh_service"]="not_detected"
    fi
    
    if [[ $issues -eq 0 ]]; then
        success "All network connectivity checks passed"
    else
        log "$LEVEL_WARNING" "Network connectivity check completed with $issues issues"
    fi
}

check_firewall_status() {
    section_header "Firewall Configuration Check"
    
    ((TOTAL_CHECKS++))
    
    # Check UFW status
    if command -v ufw >/dev/null 2>&1; then
        local ufw_status=$(ufw status 2>/dev/null | head -1 | awk '{print $2}' || echo "unknown")
        
        if [[ "$ufw_status" == "active" ]]; then
            success "UFW firewall: Active"
            NETWORK_STATUS["ufw_status"]="active"
            
            # Check specific rules
            local ssh_allowed=$(ufw status 2>/dev/null | grep -E "22|2222" | grep "ALLOW" | wc -l || echo "0")
            if [[ $ssh_allowed -gt 0 ]]; then
                success "SSH access: Allowed through firewall"
            else
                log "$LEVEL_WARNING" "SSH access: No explicit allow rules found"
            fi
            
        elif [[ "$ufw_status" == "inactive" ]]; then
            log "$LEVEL_WARNING" "UFW firewall: Inactive (security risk)"
            NETWORK_STATUS["ufw_status"]="inactive"
        else
            log "$LEVEL_WARNING" "UFW firewall: Status unknown"
            NETWORK_STATUS["ufw_status"]="unknown"
        fi
    else
        log "$LEVEL_WARNING" "UFW firewall: Not installed"
        NETWORK_STATUS["ufw_status"]="not_installed"
    fi
    
    # Check iptables rules
    if command -v iptables >/dev/null 2>&1; then
        local iptables_rules=$(iptables -L 2>/dev/null | wc -l || echo "0")
        if [[ $iptables_rules -gt 10 ]]; then
            success "Iptables: Rules configured ($iptables_rules lines)"
            NETWORK_STATUS["iptables_rules"]="configured"
        else
            log "$LEVEL_INFO" "Iptables: Minimal or no custom rules"
            NETWORK_STATUS["iptables_rules"]="minimal"
        fi
    fi
}

# ============================================================================
# Service Status Checks
# ============================================================================

check_system_services() {
    section_header "System Services Check"
    
    local services=("ssh" "networking" "systemd-resolved" "systemd-networkd" "cron")
    local optional_services=("nginx" "apache2" "docker" "fail2ban")
    
    # Check essential services
    for service in "${services[@]}"; do
        ((TOTAL_CHECKS++))
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            success "Service $service: Active"
            SERVICE_STATUS["$service"]="active"
        else
            if systemctl list-unit-files --type=service 2>/dev/null | grep -q "^$service.service"; then
                log "$LEVEL_WARNING" "Service $service: Inactive"
                SERVICE_STATUS["$service"]="inactive"
            else
                log "$LEVEL_INFO" "Service $service: Not installed"
                SERVICE_STATUS["$service"]="not_installed"
            fi
        fi
    done
    
    # Check optional services
    for service in "${optional_services[@]}"; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            success "Optional service $service: Active"
            SERVICE_STATUS["$service"]="active"
        elif systemctl list-unit-files --type=service 2>/dev/null | grep -q "^$service.service"; then
            log "$LEVEL_INFO" "Optional service $service: Installed but inactive"
            SERVICE_STATUS["$service"]="inactive"
        else
            log "$LEVEL_INFO" "Optional service $service: Not installed"
            SERVICE_STATUS["$service"]="not_installed"
        fi
    done
    
    # Check for failed services
    local failed_services=$(systemctl --failed --no-legend 2>/dev/null | wc -l || echo "0")
    if [[ $failed_services -eq 0 ]]; then
        success "Failed services: None"
    else
        log "$LEVEL_WARNING" "Failed services: $failed_services found"
        systemctl --failed --no-legend 2>/dev/null | while read -r service; do
            log "$LEVEL_WARNING" "Failed service: $service"
        done
    fi
}

check_package_management() {
    section_header "Package Management Check"
    
    ((TOTAL_CHECKS++))
    
    # Check if package lists are current
    local apt_update_log="/var/log/apt/history.log"
    if [[ -f "$apt_update_log" ]]; then
        local last_update=$(stat -c %Y "$apt_update_log" 2>/dev/null || echo "0")
        local current_time=$(date +%s)
        local days_since_update=$(( (current_time - last_update) / 86400 ))
        
        if [[ $days_since_update -le 7 ]]; then
            success "Package lists: Updated within last week"
        elif [[ $days_since_update -le 30 ]]; then
            log "$LEVEL_WARNING" "Package lists: Last updated $days_since_update days ago"
        else
            log "$LEVEL_WARNING" "Package lists: Last updated $days_since_update days ago (consider updating)"
        fi
    fi
    
    # Check for available updates
    local updates_available=0
    if command -v apt list >/dev/null 2>&1; then
        updates_available=$(apt list --upgradable 2>/dev/null | grep -c "upgradable" || echo "0")
    fi
    
    if [[ $updates_available -eq 0 ]]; then
        success "System updates: No updates available"
    elif [[ $updates_available -le 10 ]]; then
        log "$LEVEL_INFO" "System updates: $updates_available updates available"
    else
        log "$LEVEL_WARNING" "System updates: $updates_available updates available (consider updating)"
    fi
    
    # Check for broken packages
    if command -v dpkg >/dev/null 2>&1; then
        local broken_packages=$(dpkg -l 2>/dev/null | grep "^i[^i]" | wc -l || echo "0")
        if [[ $broken_packages -eq 0 ]]; then
            success "Package integrity: No broken packages"
        else
            log "$LEVEL_ERROR" "Package integrity: $broken_packages broken packages found"
        fi
    fi
}

# ============================================================================
# Security Checks
# ============================================================================

check_security_configuration() {
    section_header "Security Configuration Check"
    
    # Check SSH configuration
    ((TOTAL_CHECKS++))
    local ssh_config="/etc/ssh/sshd_config"
    if [[ -f "$ssh_config" ]]; then
        # Check password authentication
        local password_auth=$(grep "^PasswordAuthentication" "$ssh_config" 2>/dev/null | awk '{print $2}' || echo "unknown")
        if [[ "$password_auth" == "no" ]]; then
            success "SSH password authentication: Disabled (secure)"
            SECURITY_STATUS["ssh_password_auth"]="disabled"
        else
            log "$LEVEL_WARNING" "SSH password authentication: Enabled (security risk)"
            SECURITY_STATUS["ssh_password_auth"]="enabled"
        fi
        
        # Check root login
        local root_login=$(grep "^PermitRootLogin" "$ssh_config" 2>/dev/null | awk '{print $2}' || echo "unknown")
        if [[ "$root_login" == "no" ]]; then
            success "SSH root login: Disabled (secure)"
            SECURITY_STATUS["ssh_root_login"]="disabled"
        else
            log "$LEVEL_WARNING" "SSH root login: Enabled (security risk)"
            SECURITY_STATUS["ssh_root_login"]="enabled"
        fi
        
        # Check SSH port
        local ssh_port=$(grep "^Port" "$ssh_config" 2>/dev/null | awk '{print $2}' || echo "22")
        if [[ "$ssh_port" != "22" ]]; then
            success "SSH port: Changed from default ($ssh_port)"
            SECURITY_STATUS["ssh_port"]="changed"
        else
            log "$LEVEL_WARNING" "SSH port: Using default port 22 (consider changing)"
            SECURITY_STATUS["ssh_port"]="default"
        fi
    else
        log "$LEVEL_WARNING" "SSH configuration: File not found"
        SECURITY_STATUS["ssh_config"]="not_found"
    fi
    
    # Check fail2ban
    ((TOTAL_CHECKS++))
    if systemctl is-active --quiet fail2ban 2>/dev/null; then
        success "Fail2ban: Active (intrusion prevention)"
        SECURITY_STATUS["fail2ban"]="active"
    else
        log "$LEVEL_WARNING" "Fail2ban: Not active (install for intrusion prevention)"
        SECURITY_STATUS["fail2ban"]="inactive"
    fi
    
    # Check automatic updates
    ((TOTAL_CHECKS++))
    if [[ -f "/etc/apt/apt.conf.d/20auto-upgrades" ]]; then
        local auto_updates=$(grep "Unattended-Upgrade" /etc/apt/apt.conf.d/20auto-upgrades 2>/dev/null | grep -c '"1"' || echo "0")
        if [[ $auto_updates -gt 0 ]]; then
            success "Automatic security updates: Enabled"
            SECURITY_STATUS["auto_updates"]="enabled"
        else
            log "$LEVEL_WARNING" "Automatic security updates: Disabled"
            SECURITY_STATUS["auto_updates"]="disabled"
        fi
    else
        log "$LEVEL_WARNING" "Automatic security updates: Not configured"
        SECURITY_STATUS["auto_updates"]="not_configured"
    fi
    
    # Check file permissions
    ((TOTAL_CHECKS++))
    local ssh_dir="/home/*/.ssh"
    local permission_issues=0
    
    for ssh_path in $ssh_dir; do
        if [[ -d "$ssh_path" ]]; then
            local perms=$(stat -c "%a" "$ssh_path" 2>/dev/null || echo "000")
            if [[ "$perms" == "700" ]]; then
                success "SSH directory permissions: Secure ($ssh_path)"
            else
                log "$LEVEL_WARNING" "SSH directory permissions: Insecure ($ssh_path: $perms)"
                ((permission_issues++))
            fi
        fi
    done
    
    if [[ $permission_issues -eq 0 ]]; then
        SECURITY_STATUS["ssh_permissions"]="secure"
    else
        SECURITY_STATUS["ssh_permissions"]="issues_found"
    fi
}

# ============================================================================
# ArcDeploy Specific Checks
# ============================================================================

check_arcdeploy_environment() {
    section_header "ArcDeploy Environment Check"
    
    # Check if we're in ArcDeploy project
    ((TOTAL_CHECKS++))
    if [[ -f "$PROJECT_ROOT/README.md" ]] && grep -q "ArcDeploy" "$PROJECT_ROOT/README.md" 2>/dev/null; then
        success "ArcDeploy project: Detected"
        
        # Check project structure
        local expected_dirs=("scripts" "docs")
        local missing_dirs=()
        
        for dir in "${expected_dirs[@]}"; do
            if [[ ! -d "$PROJECT_ROOT/$dir" ]]; then
                missing_dirs+=("$dir")
            fi
        done
        
        if [[ ${#missing_dirs[@]} -eq 0 ]]; then
            success "Project structure: Complete"
        else
            log "$LEVEL_WARNING" "Project structure: Missing directories: ${missing_dirs[*]}"
        fi
        
        # Check configuration files
        if [[ -f "$PROJECT_ROOT/config/arcdeploy.conf" ]]; then
            success "Configuration: Found arcdeploy.conf"
        elif [[ -f "$PROJECT_ROOT/cloud-init.yaml" ]]; then
            success "Configuration: Found cloud-init.yaml"
        else
            log "$LEVEL_WARNING" "Configuration: No configuration files found"
        fi
        
        # Check scripts
        local script_count=$(find "$PROJECT_ROOT/scripts" -name "*.sh" -type f 2>/dev/null | wc -l || echo "0")
        if [[ $script_count -gt 0 ]]; then
            success "Scripts: Found $script_count shell scripts"
        else
            log "$LEVEL_WARNING" "Scripts: No shell scripts found"
        fi
        
    else
        log "$LEVEL_INFO" "ArcDeploy project: Not detected (running in different context)"
    fi
    
    # Check Node.js installation
    ((TOTAL_CHECKS++))
    if command -v node >/dev/null 2>&1; then
        local node_version=$(node --version 2>/dev/null || echo "unknown")
        success "Node.js: Installed ($node_version)"
        
        # Check if version is suitable
        local major_version=$(echo "$node_version" | sed 's/^v//' | cut -d. -f1)
        if [[ "$major_version" != "unknown" ]] && [[ $major_version -ge 16 ]]; then
            success "Node.js version: Compatible (v$major_version.x)"
        else
            log "$LEVEL_WARNING" "Node.js version: Old or incompatible ($node_version)"
        fi
    else
        log "$LEVEL_WARNING" "Node.js: Not installed"
    fi
    
    # Check npm
    if command -v npm >/dev/null 2>&1; then
        local npm_version=$(npm --version 2>/dev/null || echo "unknown")
        success "npm: Installed ($npm_version)"
    else
        log "$LEVEL_WARNING" "npm: Not installed"
    fi
}

# ============================================================================
# Report Generation
# ============================================================================

generate_summary_report() {
    section_header "Diagnostic Summary"
    
    echo "=== ArcDeploy System Diagnostics Report ===" > "$REPORT_FILE"
    echo "Generated: $(date)" >> "$REPORT_FILE"
    echo "Hostname: ${SYSTEM_INFO["hostname"]}" >> "$REPORT_FILE"
    echo "OS: ${SYSTEM_INFO["os_name"]} ${SYSTEM_INFO["os_version"]}" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    # Summary statistics
    echo "=== Summary Statistics ===" >> "$REPORT_FILE"
    echo "Total checks: $TOTAL_CHECKS" >> "$REPORT_FILE"
    echo "Passed: $PASSED_CHECKS" >> "$REPORT_FILE"
    echo "Warnings: $WARNING_CHECKS" >> "$REPORT_FILE"
    echo "Errors: $FAILED_CHECKS" >> "$REPORT_FILE"
    echo "Critical: $CRITICAL_CHECKS" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    # Calculate overall health score
    local total_issues=$((WARNING_CHECKS + FAILED_CHECKS + CRITICAL_CHECKS))
    local health_score=100
    
    if [[ $TOTAL_CHECKS -gt 0 ]]; then
        health_score=$(( 100 - (total_issues * 100 / TOTAL_CHECKS) ))
    fi
    
    echo "=== Overall System Health ===" >> "$REPORT_FILE"
    if [[ $health_score -ge 90 ]]; then
        echo "Health Score: $health_score% (Excellent)" >> "$REPORT_FILE"
        echo -e "${GREEN}Health Score: $health_score% (Excellent)${NC}"
    elif [[ $health_score -ge 75 ]]; then
        echo "Health Score: $health_score% (Good)" >> "$REPORT_FILE"
        echo -e "${YELLOW}Health Score: $health_score% (Good)${NC}"
    elif [[ $health_score -ge 50 ]]; then
        echo "Health Score: $health_score% (Fair)" >> "$REPORT_FILE"
        echo -e "${YELLOW}Health Score: $health_score% (Fair)${NC}"
    else
        echo "Health Score: $health_score% (Poor)" >> "$REPORT_FILE"
        echo -e "${RED}Health Score: $health_score% (Poor)${NC}"
    fi
    echo "" >> "$REPORT_FILE"
    
    # Recommendations
    echo "=== Recommendations ===" >> "$REPORT_FILE"
    if [[ $CRITICAL_CHECKS -gt 0 ]]; then
        echo "- Address critical issues immediately" >> "$REPORT_FILE"
    fi
    if [[ $FAILED_CHECKS -gt 0 ]]; then
        echo "- Fix error conditions before deployment" >> "$REPORT_FILE"
    fi
    if [[ $WARNING_CHECKS -gt 0 ]]; then
        echo "- Review warnings for potential improvements" >> "$REPORT_FILE"
    fi
    if [[ $total_issues -eq 0 ]]; then
        echo "- System appears healthy for deployment" >> "$REPORT_FILE"
    fi
    echo "" >> "$REPORT_FILE"
    
    success "Diagnostic report saved to $REPORT_FILE"
}

generate_json_report() {
    cat > "$JSON_REPORT_FILE" << EOF
{
  "timestamp": "$(date -Iseconds)",
  "hostname": "${SYSTEM_INFO["hostname"]}",
  "system_info": {
$(for key in "${!SYSTEM_INFO[@]}"; do
    echo "    \"$key\": \"${SYSTEM_INFO[$key]}\","
done | sed '$ s/,$//')
  },
  "performance_metrics": {
$(for key in "${!PERFORMANCE_METRICS[@]}"; do
    echo "    \"$key\": \"${PERFORMANCE_METRICS[$key]}\","
done | sed '$ s/,$//')
  },
  "network_status": {
$(for key in "${!NETWORK_STATUS[@]}"; do
    echo "    \"$key\": \"${NETWORK_STATUS[$key]}\","
done | sed '$ s/,$//')
  },
  "service_status": {
$(for key in "${!SERVICE_STATUS[@]}"; do
    echo "    \"$key\": \"${SERVICE_STATUS[$key]}\","
done | sed '$ s/,$//')
  },
  "security_status": {
$(for key in "${!SECURITY_STATUS[@]}"; do
    echo "    \"$key\": \"${SECURITY_STATUS[$key]}\","
done | sed '$ s/,$//')
  },
  "summary": {
    "total_checks": $TOTAL_CHECKS,
    "passed_checks": $PASSED_CHECKS,
    "warning_checks": $WARNING_CHECKS,
    "failed_checks": $FAILED_CHECKS,
    "critical_checks": $CRITICAL_CHECKS,
    "health_score": $((100 - ((WARNING_CHECKS + FAILED_CHECKS + CRITICAL_CHECKS) * 100 / (TOTAL_CHECKS > 0 ? TOTAL_CHECKS : 1))))
  }
}
EOF
    
    success "JSON report saved to $JSON_REPORT_FILE"
}

# ============================================================================
# Help and Usage
# ============================================================================

show_help() {
    cat << EOF
ArcDeploy System Diagnostics Script v$SCRIPT_VERSION

Comprehensive system analysis and troubleshooting tool for deployment issues.

Usage: $SCRIPT_NAME [OPTIONS]

Options:
    -q, --quick                     Quick check (essential tests only)
    -f, --full                      Full diagnostic scan (default)
    -j, --json                      Generate JSON output
    -s, --silent                    Minimal output
    -v, --verbose                   Verbose output with debug info
    -o, --output FILE               Save report to specific file
    -h, --help                      Show this help

Diagnostic Categories:
    - System information collection
    - Hardware and resource checks
    - Network connectivity tests
    - Service status verification
    - Security configuration review
    - ArcDeploy environment validation

Examples:
    $SCRIPT_NAME                    # Run full diagnostics
    $SCRIPT_NAME --quick            # Quick essential checks
    $SCRIPT_NAME --json             # Generate JSON report
    $SCRIPT_NAME --output my-report.txt  # Custom output file

Output Files:
    - Text Report: $REPORT_FILE
    - JSON Report: $JSON_REPORT_FILE
    - Debug Log: $LOG_FILE

Exit Codes:
    0  - All checks passed
    1  - Warnings found
    2  - Errors found
    3  - Critical issues found

EOF
}

# ============================================================================
# Main Function
# ============================================================================

main() {
    local quick_mode="false"
    local json_output="false"
    local silent_mode="false"
    local verbose_mode="false"
    local custom_output=""
    
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
            -j|--json)
                json_output="true"
                shift
                ;;
            -s|--silent)
                silent_mode="true"
                shift
                ;;
            -v|--verbose)
                verbose_mode="true"
                export DEBUG_MODE="true"
                shift
                ;;
            -o|--output)
                custom_output="$2"
                shift 2
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log "$LEVEL_ERROR" "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # Set custom output file if specified
    if [[ -n "$custom_output" ]]; then
        readonly REPORT_FILE="$custom_output"
    fi
    
    # Initialize
    echo "System diagnostics started on $(date)" > "$LOG_FILE"
    
    if [[ "$silent_mode" != "true" ]]; then
        echo -e "${BLUE}ArcDeploy System Diagnostics v$SCRIPT_VERSION${NC}"
        echo "=============================================="
        echo ""
    fi
    
    # Run diagnostic checks
    local total_steps=7
    local current_step=0
    
    if [[ "$silent_mode" != "true" ]]; then
        progress_bar $current_step $total_steps
    fi
    
    # Step 1: System Information
    ((current_step++))
    collect_system_info
    if [[ "$silent_mode" != "true" ]]; then
        progress_bar $current_step $total_steps
    fi
    
    # Step 2: Hardware Requirements
    ((current_step++))
    check_system_requirements
    if [[ "$silent_mode" != "true" ]]; then
        progress_bar $current_step $total_steps
    fi
    
    # Step 3: Performance Metrics
    ((current_step++))
    if [[ "$quick_mode" != "true" ]]; then
        check_performance_metrics
    fi
    if [[ "$silent_mode" != "true" ]]; then
        progress_bar $current_step $total_steps
    fi
    
    # Step 4: Network Connectivity
    ((current_step++))
    check_network_connectivity
    if [[ "$silent_mode" != "true" ]]; then
        progress_bar $current_step $total_steps
    fi
    
    # Step 5: Firewall Status
    ((current_step++))
    if [[ "$quick_mode" != "true" ]]; then
        check_firewall_status
    fi
    if [[ "$silent_mode" != "true" ]]; then
        progress_bar $current_step $total_steps
    fi
    
    # Step 6: System Services
    ((current_step++))
    check_system_services
    if [[ "$quick_mode" != "true" ]]; then
        check_package_management
    fi
    if [[ "$silent_mode" != "true" ]]; then
        progress_bar $current_step $total_steps
    fi
    
    # Step 7: Security and ArcDeploy
    ((current_step++))
    if [[ "$quick_mode" != "true" ]]; then
        check_security_configuration
    fi
    check_arcdeploy_environment
    if [[ "$silent_mode" != "true" ]]; then
        progress_bar $current_step $total_steps
        echo ""
    fi
    
    # Generate reports
    generate_summary_report
    if [[ "$json_output" == "true" ]]; then
        generate_json_report
    fi
    
    # Final summary
    if [[ "$silent_mode" != "true" ]]; then
        echo ""
        echo "=============================================="
        echo "Diagnostics completed successfully!"
        echo "Reports saved:"
        echo "  - Text: $REPORT_FILE"
        if [[ "$json_output" == "true" ]]; then
            echo "  - JSON: $JSON_REPORT_FILE"
        fi
        echo "  - Log: $LOG_FILE"
        echo ""
    fi
    
    # Determine exit code
    if [[ $CRITICAL_CHECKS -gt 0 ]]; then
        exit 3
    elif [[ $FAILED_CHECKS -gt 0 ]]; then
        exit 2
    elif [[ $WARNING_CHECKS -gt 0 ]]; then
        exit 1
    else
        exit 0
    fi
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi