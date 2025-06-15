#!/bin/bash

# ArcDeploy Production Compliance Checker
# Validates deployed system against production cloud-init configuration requirements

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

# Logging
readonly COMPLIANCE_LOG="$PROJECT_ROOT/test-results/compliance-check.log"
readonly COMPLIANCE_REPORT="$PROJECT_ROOT/test-results/compliance-report.txt"
readonly JSON_REPORT="$PROJECT_ROOT/test-results/compliance-report.json"

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
# Expected Production Configuration
# ============================================================================
readonly EXPECTED_USER="arcblock"
readonly EXPECTED_SERVICE_USER="blockletd"
readonly EXPECTED_SSH_PORT="2222"
readonly EXPECTED_HTTP_PORT="80"
readonly EXPECTED_HTTPS_PORT="443"
readonly EXPECTED_BLOCKLET_PORT="8080"
readonly EXPECTED_HEALTH_PORT="8081"
readonly EXPECTED_SYSTEMD_SERVICE="blocklet-server"
readonly EXPECTED_NGINX_SERVICE="nginx"
readonly EXPECTED_FAIL2BAN_SERVICE="fail2ban"

# Expected directories
readonly EXPECTED_BLOCKLET_DIR="/opt/blocklet-server"
readonly EXPECTED_DATA_DIR="/opt/blocklet-server/data"
readonly EXPECTED_CONFIG_DIR="/opt/blocklet-server/config"
readonly EXPECTED_LOGS_DIR="/opt/blocklet-server/logs"
readonly EXPECTED_BACKUP_DIR="/opt/blocklet-server/backups"

# Expected files
readonly EXPECTED_SYSTEMD_FILE="/etc/systemd/system/blocklet-server.service"
readonly EXPECTED_NGINX_CONFIG="/etc/nginx/sites-available/blocklet-server"
readonly EXPECTED_NGINX_ENABLED="/etc/nginx/sites-enabled/blocklet-server"
readonly EXPECTED_FAIL2BAN_CONFIG="/etc/fail2ban/jail.local"
readonly EXPECTED_SSH_CONFIG="/etc/ssh/sshd_config"

# Expected scripts
readonly EXPECTED_HEALTH_SCRIPT="/opt/blocklet-server/healthcheck.sh"
readonly EXPECTED_BACKUP_SCRIPT="/opt/blocklet-server/backup.sh"
readonly EXPECTED_MONITOR_SCRIPT="/opt/blocklet-server/monitor.sh"
readonly EXPECTED_SSL_SCRIPT="/opt/blocklet-server/ssl-setup.sh"

# ============================================================================
# Counters
# ============================================================================
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0
WARNINGS=0
CRITICAL_ISSUES=0

# ============================================================================
# Logging Functions
# ============================================================================

log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    mkdir -p "$(dirname "$COMPLIANCE_LOG")"

    case "$level" in
        "INFO")
            echo -e "${BLUE}[INFO]${NC} $message" | tee -a "$COMPLIANCE_LOG"
            ;;
        "PASS")
            echo -e "${GREEN}[PASS]${NC} $message" | tee -a "$COMPLIANCE_LOG"
            ((PASSED_CHECKS++))
            ;;
        "FAIL")
            echo -e "${RED}[FAIL]${NC} $message" | tee -a "$COMPLIANCE_LOG"
            ((FAILED_CHECKS++))
            ;;
        "WARN")
            echo -e "${YELLOW}[WARN]${NC} $message" | tee -a "$COMPLIANCE_LOG"
            ((WARNINGS++))
            ;;
        "CRITICAL")
            echo -e "${RED}[CRITICAL]${NC} $message" | tee -a "$COMPLIANCE_LOG"
            ((CRITICAL_ISSUES++))
            ;;
        "DEBUG")
            if [[ "${DEBUG:-false}" == "true" ]]; then
                echo -e "${PURPLE}[DEBUG]${NC} $message" | tee -a "$COMPLIANCE_LOG"
            fi
            ;;
    esac
}

increment_check_counter() {
    ((TOTAL_CHECKS++))
}

# ============================================================================
# Compliance Check Functions
# ============================================================================

check_system_users() {
    log "INFO" "Checking system users compliance"

    # Check arcblock user
    increment_check_counter
    if id "$EXPECTED_USER" >/dev/null 2>&1; then
        log "PASS" "User $EXPECTED_USER exists"

        # Check user groups
        local user_groups
        user_groups=$(id -Gn "$EXPECTED_USER")
        if echo "$user_groups" | grep -q "sudo"; then
            log "PASS" "User $EXPECTED_USER has sudo privileges"
        else
            log "FAIL" "User $EXPECTED_USER missing sudo privileges"
        fi
    else
        log "FAIL" "User $EXPECTED_USER does not exist"
    fi

    # Check blockletd service user
    increment_check_counter
    if id "$EXPECTED_SERVICE_USER" >/dev/null 2>&1; then
        log "PASS" "Service user $EXPECTED_SERVICE_USER exists"

        # Check it's a system user
        local uid
        uid=$(id -u "$EXPECTED_SERVICE_USER")
        if [[ $uid -lt 1000 ]]; then
            log "PASS" "Service user $EXPECTED_SERVICE_USER is a system user (UID: $uid)"
        else
            log "WARN" "Service user $EXPECTED_SERVICE_USER has regular user UID: $uid"
        fi
    else
        log "FAIL" "Service user $EXPECTED_SERVICE_USER does not exist"
    fi
}

check_directory_structure() {
    log "INFO" "Checking directory structure compliance"

    local expected_dirs=(
        "$EXPECTED_BLOCKLET_DIR"
        "$EXPECTED_DATA_DIR"
        "$EXPECTED_CONFIG_DIR"
        "$EXPECTED_LOGS_DIR"
        "$EXPECTED_BACKUP_DIR"
    )

    for dir in "${expected_dirs[@]}"; do
        increment_check_counter
        if [[ -d "$dir" ]]; then
            log "PASS" "Directory exists: $dir"

            # Check ownership
            local owner
            owner=$(stat -c '%U' "$dir" 2>/dev/null || echo "unknown")
            if [[ "$owner" == "$EXPECTED_USER" ]] || [[ "$owner" == "$EXPECTED_SERVICE_USER" ]]; then
                log "PASS" "Directory ownership correct: $dir ($owner)"
            else
                log "WARN" "Directory ownership unexpected: $dir ($owner)"
            fi
        else
            log "FAIL" "Directory missing: $dir"
        fi
    done
}

check_systemd_services() {
    log "INFO" "Checking systemd services compliance"

    local expected_services=(
        "$EXPECTED_SYSTEMD_SERVICE"
        "$EXPECTED_NGINX_SERVICE"
        "$EXPECTED_FAIL2BAN_SERVICE"
    )

    for service in "${expected_services[@]}"; do
        increment_check_counter
        if systemctl is-enabled "$service" >/dev/null 2>&1; then
            log "PASS" "Service enabled: $service"

            # Check if running
            if systemctl is-active --quiet "$service"; then
                log "PASS" "Service running: $service"
            else
                log "FAIL" "Service not running: $service"
            fi
        else
            log "FAIL" "Service not enabled: $service"
        fi
    done

    # Check systemd service file
    increment_check_counter
    if [[ -f "$EXPECTED_SYSTEMD_FILE" ]]; then
        log "PASS" "Systemd service file exists: $EXPECTED_SYSTEMD_FILE"

        # Check service file content
        local service_content
        service_content=$(cat "$EXPECTED_SYSTEMD_FILE")

        if echo "$service_content" | grep -q "User=$EXPECTED_SERVICE_USER"; then
            log "PASS" "Service runs as correct user: $EXPECTED_SERVICE_USER"
        else
            log "FAIL" "Service user not configured correctly in systemd file"
        fi

        if echo "$service_content" | grep -q "Restart=always"; then
            log "PASS" "Service configured for automatic restart"
        else
            log "WARN" "Service auto-restart not configured"
        fi
    else
        log "FAIL" "Systemd service file missing: $EXPECTED_SYSTEMD_FILE"
    fi
}

check_nginx_configuration() {
    log "INFO" "Checking Nginx configuration compliance"

    # Check nginx config files
    increment_check_counter
    if [[ -f "$EXPECTED_NGINX_CONFIG" ]]; then
        log "PASS" "Nginx config file exists: $EXPECTED_NGINX_CONFIG"

        # Check config content
        local nginx_config
        nginx_config=$(cat "$EXPECTED_NGINX_CONFIG")

        if echo "$nginx_config" | grep -q "proxy_pass.*$EXPECTED_BLOCKLET_PORT"; then
            log "PASS" "Nginx reverse proxy configured for port $EXPECTED_BLOCKLET_PORT"
        else
            log "FAIL" "Nginx reverse proxy not configured correctly"
        fi

        if echo "$nginx_config" | grep -q "ssl_certificate"; then
            log "PASS" "SSL configuration present in Nginx"
        else
            log "WARN" "SSL configuration not found in Nginx (may be using self-signed)"
        fi
    else
        log "FAIL" "Nginx config file missing: $EXPECTED_NGINX_CONFIG"
    fi

    # Check if site is enabled
    increment_check_counter
    if [[ -L "$EXPECTED_NGINX_ENABLED" ]]; then
        log "PASS" "Nginx site enabled: $EXPECTED_NGINX_ENABLED"
    else
        log "FAIL" "Nginx site not enabled: $EXPECTED_NGINX_ENABLED"
    fi

    # Test nginx configuration
    increment_check_counter
    if nginx -t >/dev/null 2>&1; then
        log "PASS" "Nginx configuration syntax is valid"
    else
        log "FAIL" "Nginx configuration syntax is invalid"
    fi
}

check_ssh_configuration() {
    log "INFO" "Checking SSH configuration compliance"

    increment_check_counter
    if [[ -f "$EXPECTED_SSH_CONFIG" ]]; then
        log "PASS" "SSH configuration file exists"

        local ssh_config
        ssh_config=$(cat "$EXPECTED_SSH_CONFIG")

        # Check SSH port
        if echo "$ssh_config" | grep -q "^Port $EXPECTED_SSH_PORT"; then
            log "PASS" "SSH port configured: $EXPECTED_SSH_PORT"
        else
            log "FAIL" "SSH port not configured correctly (expected: $EXPECTED_SSH_PORT)"
        fi

        # Check password authentication
        if echo "$ssh_config" | grep -q "^PasswordAuthentication no"; then
            log "PASS" "SSH password authentication disabled"
        else
            log "FAIL" "SSH password authentication not disabled"
        fi

        # Check root login
        if echo "$ssh_config" | grep -q "^PermitRootLogin no"; then
            log "PASS" "SSH root login disabled"
        else
            log "FAIL" "SSH root login not disabled"
        fi

        # Check key authentication
        if echo "$ssh_config" | grep -q "^PubkeyAuthentication yes"; then
            log "PASS" "SSH public key authentication enabled"
        else
            log "FAIL" "SSH public key authentication not enabled"
        fi
    else
        log "FAIL" "SSH configuration file missing: $EXPECTED_SSH_CONFIG"
    fi
}

check_firewall_configuration() {
    log "INFO" "Checking firewall configuration compliance"

    increment_check_counter
    if command -v ufw >/dev/null 2>&1; then
        log "PASS" "UFW firewall is installed"

        # Check if firewall is active
        if ufw status | grep -q "Status: active"; then
            log "PASS" "UFW firewall is active"

            # Check SSH port
            if ufw status | grep -q "$EXPECTED_SSH_PORT"; then
                log "PASS" "SSH port $EXPECTED_SSH_PORT allowed in firewall"
            else
                log "FAIL" "SSH port $EXPECTED_SSH_PORT not allowed in firewall"
            fi

            # Check HTTP/HTTPS ports
            if ufw status | grep -q "80/tcp" && ufw status | grep -q "443/tcp"; then
                log "PASS" "HTTP/HTTPS ports allowed in firewall"
            else
                log "FAIL" "HTTP/HTTPS ports not properly configured in firewall"
            fi
        else
            log "FAIL" "UFW firewall is not active"
        fi
    else
        log "FAIL" "UFW firewall is not installed"
    fi
}

check_fail2ban_configuration() {
    log "INFO" "Checking fail2ban configuration compliance"

    increment_check_counter
    if [[ -f "$EXPECTED_FAIL2BAN_CONFIG" ]]; then
        log "PASS" "Fail2ban configuration file exists"

        local fail2ban_config
        fail2ban_config=$(cat "$EXPECTED_FAIL2BAN_CONFIG")

        # Check SSH jail
        if echo "$fail2ban_config" | grep -A 10 "^\[sshd\]" | grep -q "enabled = true"; then
            log "PASS" "Fail2ban SSH jail enabled"
        else
            log "FAIL" "Fail2ban SSH jail not enabled"
        fi

        # Check nginx jails
        if echo "$fail2ban_config" | grep -q "nginx"; then
            log "PASS" "Fail2ban nginx jails configured"
        else
            log "WARN" "Fail2ban nginx jails not configured"
        fi
    else
        log "FAIL" "Fail2ban configuration file missing: $EXPECTED_FAIL2BAN_CONFIG"
    fi
}

check_network_ports() {
    log "INFO" "Checking network ports compliance"

    local expected_ports=(
        "$EXPECTED_HTTP_PORT"
        "$EXPECTED_HTTPS_PORT"
        "$EXPECTED_SSH_PORT"
    )

    for port in "${expected_ports[@]}"; do
        increment_check_counter
        if netstat -tlnp 2>/dev/null | grep -q ":$port "; then
            log "PASS" "Port $port is listening"
        else
            log "FAIL" "Port $port is not listening"
        fi
    done

    # Check application ports are localhost only
    increment_check_counter
    if netstat -tlnp 2>/dev/null | grep -q "127.0.0.1:$EXPECTED_BLOCKLET_PORT"; then
        log "PASS" "Blocklet port $EXPECTED_BLOCKLET_PORT restricted to localhost"
    else
        log "WARN" "Blocklet port $EXPECTED_BLOCKLET_PORT may not be restricted to localhost"
    fi
}

check_required_scripts() {
    log "INFO" "Checking required scripts compliance"

    local expected_scripts=(
        "$EXPECTED_HEALTH_SCRIPT"
        "$EXPECTED_BACKUP_SCRIPT"
        "$EXPECTED_MONITOR_SCRIPT"
        "$EXPECTED_SSL_SCRIPT"
    )

    for script in "${expected_scripts[@]}"; do
        increment_check_counter
        if [[ -f "$script" ]]; then
            log "PASS" "Required script exists: $script"

            # Check if executable
            if [[ -x "$script" ]]; then
                log "PASS" "Script is executable: $script"
            else
                log "FAIL" "Script is not executable: $script"
            fi
        else
            log "FAIL" "Required script missing: $script"
        fi
    done
}

check_system_hardening() {
    log "INFO" "Checking system hardening compliance"

    # Check kernel parameters
    increment_check_counter
    if grep -q "net.ipv4.ip_forward = 1" /etc/sysctl.conf 2>/dev/null; then
        log "PASS" "IP forwarding enabled in sysctl"
    else
        log "WARN" "IP forwarding not configured in sysctl"
    fi

    # Check security parameters
    increment_check_counter
    if grep -q "net.ipv4.conf.all.accept_redirects = 0" /etc/sysctl.conf 2>/dev/null; then
        log "PASS" "ICMP redirects disabled"
    else
        log "WARN" "ICMP redirects not disabled"
    fi

    # Check system limits
    increment_check_counter
    if grep -q "$EXPECTED_USER.*nofile.*65536" /etc/security/limits.conf 2>/dev/null; then
        log "PASS" "System limits configured for $EXPECTED_USER"
    else
        log "WARN" "System limits not configured for $EXPECTED_USER"
    fi
}

check_cron_jobs() {
    log "INFO" "Checking cron jobs compliance"

    # Check user cron jobs
    increment_check_counter
    if crontab -u "$EXPECTED_USER" -l 2>/dev/null | grep -q "healthcheck.sh"; then
        log "PASS" "Health check cron job configured"
    else
        log "FAIL" "Health check cron job missing"
    fi

    increment_check_counter
    if crontab -u "$EXPECTED_USER" -l 2>/dev/null | grep -q "backup.sh"; then
        log "PASS" "Backup cron job configured"
    else
        log "FAIL" "Backup cron job missing"
    fi

    increment_check_counter
    if crontab -u "$EXPECTED_USER" -l 2>/dev/null | grep -q "monitor.sh"; then
        log "PASS" "Monitor cron job configured"
    else
        log "FAIL" "Monitor cron job missing"
    fi
}

check_log_rotation() {
    log "INFO" "Checking log rotation compliance"

    increment_check_counter
    if [[ -f "/etc/logrotate.d/blocklet-server" ]]; then
        log "PASS" "Log rotation configured for blocklet-server"
    else
        log "FAIL" "Log rotation not configured for blocklet-server"
    fi
}

check_installation_completion() {
    log "INFO" "Checking installation completion markers"

    increment_check_counter
    if [[ -f "$EXPECTED_BLOCKLET_DIR/.installation-complete" ]]; then
        log "PASS" "Installation completion marker found"

        # Check completion marker content
        local completion_info
        completion_info=$(cat "$EXPECTED_BLOCKLET_DIR/.installation-complete")
        log "INFO" "Installation details: $(echo "$completion_info" | head -3 | tail -1)"
    else
        log "WARN" "Installation completion marker not found"
    fi
}

# ============================================================================
# Reporting Functions
# ============================================================================

generate_compliance_report() {
    log "INFO" "Generating compliance report"

    local compliance_percentage
    compliance_percentage=$(( (PASSED_CHECKS * 100) / TOTAL_CHECKS ))

    # Generate text report
    cat > "$COMPLIANCE_REPORT" << EOF
# ArcDeploy Production Compliance Report

Generated: $(date)
Script Version: $SCRIPT_VERSION
Hostname: $(hostname)

## Compliance Summary
- Total Checks: $TOTAL_CHECKS
- Passed: $PASSED_CHECKS
- Failed: $FAILED_CHECKS
- Warnings: $WARNINGS
- Critical Issues: $CRITICAL_ISSUES
- Compliance Score: ${compliance_percentage}%

## Overall Status
$(if [[ $compliance_percentage -ge 90 && $CRITICAL_ISSUES -eq 0 ]]; then
    echo "✅ COMPLIANT - System meets production requirements"
elif [[ $compliance_percentage -ge 70 && $CRITICAL_ISSUES -eq 0 ]]; then
    echo "⚠️  PARTIALLY COMPLIANT - Some improvements needed"
else
    echo "❌ NON-COMPLIANT - Significant issues require attention"
fi)

## Key Findings
$(if [[ $CRITICAL_ISSUES -gt 0 ]]; then
    echo "- $CRITICAL_ISSUES critical security issues detected"
fi)
$(if [[ $FAILED_CHECKS -gt 0 ]]; then
    echo "- $FAILED_CHECKS configuration checks failed"
fi)
$(if [[ $WARNINGS -gt 0 ]]; then
    echo "- $WARNINGS warnings identified for improvement"
fi)
$(if [[ $PASSED_CHECKS -eq $TOTAL_CHECKS ]]; then
    echo "- All configuration checks passed successfully"
fi)

## Recommendations
$(if [[ $CRITICAL_ISSUES -gt 0 ]]; then
    echo "1. Address critical security issues immediately"
fi)
$(if [[ $FAILED_CHECKS -gt 0 ]]; then
    echo "2. Fix failed configuration checks"
fi)
$(if [[ $WARNINGS -gt 0 ]]; then
    echo "3. Review and address warning items"
fi)
$(if [[ $compliance_percentage -lt 90 ]]; then
    echo "4. Improve compliance score to 90%+ for production readiness"
fi)

## Detailed Logs
See: $COMPLIANCE_LOG

EOF

    # Generate JSON report
    cat > "$JSON_REPORT" << EOF
{
    "timestamp": "$(date -Iseconds)",
    "version": "$SCRIPT_VERSION",
    "hostname": "$(hostname)",
    "summary": {
        "total_checks": $TOTAL_CHECKS,
        "passed_checks": $PASSED_CHECKS,
        "failed_checks": $FAILED_CHECKS,
        "warnings": $WARNINGS,
        "critical_issues": $CRITICAL_ISSUES,
        "compliance_percentage": $compliance_percentage
    },
    "status": "$(if [[ $compliance_percentage -ge 90 && $CRITICAL_ISSUES -eq 0 ]]; then
        echo "COMPLIANT"
    elif [[ $compliance_percentage -ge 70 && $CRITICAL_ISSUES -eq 0 ]]; then
        echo "PARTIALLY_COMPLIANT"
    else
        echo "NON_COMPLIANT"
    fi)",
    "reports": {
        "detailed_log": "$COMPLIANCE_LOG",
        "summary_report": "$COMPLIANCE_REPORT"
    }
}
EOF

    log "INFO" "Compliance reports generated:"
    log "INFO" "- Text report: $COMPLIANCE_REPORT"
    log "INFO" "- JSON report: $JSON_REPORT"
    log "INFO" "- Detailed log: $COMPLIANCE_LOG"
}

# ============================================================================
# Help and Usage
# ============================================================================

show_help() {
    cat << EOF
Usage: $SCRIPT_NAME [OPTIONS]

ArcDeploy Production Compliance Checker

This script validates the current system configuration against the expected
production deployment configuration from the ArcDeploy cloud-init.yaml file.

OPTIONS:
    -h, --help              Show this help message
    -d, --debug             Enable debug output
    -q, --quiet             Suppress output (logs only)
    --report-only           Generate report from existing logs
    --json                  Output results in JSON format
    --version               Show script version

COMPLIANCE CHECKS:
    - System users and permissions
    - Directory structure and ownership
    - Systemd services configuration
    - Nginx reverse proxy setup
    - SSH hardening configuration
    - Firewall rules and settings
    - Fail2ban security configuration
    - Network port configuration
    - Required operational scripts
    - System hardening parameters
    - Cron job configuration
    - Log rotation setup
    - Installation completion status

EXAMPLES:
    $SCRIPT_NAME                    # Run full compliance check
    $SCRIPT_NAME --quiet            # Run quietly (logs only)
    $SCRIPT_NAME --json             # Output JSON results
    $SCRIPT_NAME --report-only      # Generate report from existing logs

REPORTS:
    - Detailed logs: $COMPLIANCE_LOG
    - Summary report: $COMPLIANCE_REPORT
    - JSON report: $JSON_REPORT

RETURN CODES:
    0 - Fully compliant (90%+ passed, no critical issues)
    1 - Partially compliant (70-89% passed, no critical issues)
    2 - Non-compliant (critical issues or <70% passed)
    3 - Script error or missing dependencies

EOF
}

# ============================================================================
# Main Script Logic
# ============================================================================

main() {
    local quiet_mode=false
    local json_output=false
    local report_only=false

    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -d|--debug)
                DEBUG=true
                shift
                ;;
            -q|--quiet)
                quiet_mode=true
                shift
                ;;
            --json)
                json_output=true
                shift
                ;;
            --report-only)
                report_only=true
                shift
                ;;
            --version)
                echo "$SCRIPT_NAME version $SCRIPT_VERSION"
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done

    # Initialize logging
    mkdir -p "$(dirname "$COMPLIANCE_LOG")"

    # Header
    if [[ "$quiet_mode" != "true" ]]; then
        echo "=============================================="
        echo "ArcDeploy Production Compliance Checker"
        echo "Version: $SCRIPT_VERSION"
        echo "=============================================="
        echo ""
    fi

    # Handle report-only mode
    if [[ "$report_only" == "true" ]]; then
        generate_compliance_report
        exit 0
    fi

    # Run compliance checks
    log "INFO" "Starting production compliance validation"

    check_system_users
    check_directory_structure
    check_systemd_services
    check_nginx_configuration
    check_ssh_configuration
    check_firewall_configuration
    check_fail2ban_configuration
    check_network_ports
    check_required_scripts
    check_system_hardening
    check_cron_jobs
    check_log_rotation
    check_installation_completion

    # Generate reports
    generate_compliance_report

    # Calculate compliance score
    local compliance_percentage
    compliance_percentage=$(( (PASSED_CHECKS * 100) / TOTAL_CHECKS ))

    # Summary output
    if [[ "$quiet_mode" != "true" ]]; then
        echo ""
        echo "=============================================="
        echo "Production Compliance Check Complete"
        echo "=============================================="
        echo "Total Checks: $TOTAL_CHECKS"
        echo "Passed: $PASSED_CHECKS"
        echo "Failed: $FAILED_CHECKS"
        echo "Warnings: $WARNINGS"
        echo "Critical Issues: $CRITICAL_ISSUES"
        echo "Compliance Score: ${compliance_percentage}%"
        echo ""

        if [[ $compliance_percentage -ge 90 && $CRITICAL_ISSUES -eq 0 ]]; then
            echo "✅ COMPLIANT - System meets production requirements"
        elif [[ $compliance_percentage -ge 70 && $CRITICAL_ISSUES -eq 0 ]]; then
            echo "⚠️  PARTIALLY COMPLIANT - Some improvements needed"
        else
            echo "❌ NON-COMPLIANT - Significant issues require attention"
        fi

        echo ""
        echo "Reports generated:"
        echo "- Summary: $COMPLIANCE_REPORT"
        echo "- JSON: $JSON_REPORT"
        echo "- Detailed: $COMPLIANCE_LOG"
    fi

    # JSON output mode
    if [[ "$json_output" == "true" ]]; then
        cat "$JSON_REPORT"
    fi

    # Exit with appropriate code
    if [[ $compliance_percentage -ge 90 && $CRITICAL_ISSUES -eq 0 ]]; then
        exit 0  # Fully compliant
    elif [[ $compliance_percentage -ge 70 && $CRITICAL_ISSUES -eq 0 ]]; then
        exit 1  # Partially compliant
    else
        exit 2  # Non-compliant
    fi
}

# Execute main function with all arguments
main "$@"
