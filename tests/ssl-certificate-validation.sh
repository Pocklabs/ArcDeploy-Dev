#!/bin/bash

# ArcDeploy SSL Certificate Validation Test Suite
# Comprehensive SSL/TLS certificate testing and validation for production deployments

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
readonly TEST_RESULTS_DIR="$PROJECT_ROOT/test-results"
readonly TEST_LOGS_DIR="$TEST_RESULTS_DIR/ssl-certificate-logs"
readonly SSL_LOG="$TEST_LOGS_DIR/ssl-validation.log"
readonly SSL_REPORT="$TEST_RESULTS_DIR/ssl-certificate-report.txt"

# ============================================================================
# Configuration
# ============================================================================
readonly DEFAULT_TIMEOUT=30
readonly CERT_EXPIRY_WARNING_DAYS=30
readonly CERT_EXPIRY_CRITICAL_DAYS=7

# SSL/TLS Testing Configuration
readonly SSL_PORTS=("443" "8443")
readonly TEST_HOSTS=("localhost" "127.0.0.1")
readonly EXPECTED_CIPHER_SUITES=("TLS_AES_256_GCM_SHA384" "TLS_CHACHA20_POLY1305_SHA256" "TLS_AES_128_GCM_SHA256")
readonly EXPECTED_PROTOCOLS=("TLSv1.2" "TLSv1.3")
readonly SECURITY_HEADERS=("Strict-Transport-Security" "X-Frame-Options" "X-Content-Type-Options" "X-XSS-Protection")

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
# Counters
# ============================================================================
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
WARNINGS=0
CRITICAL_ISSUES=0

# ============================================================================
# Logging Functions
# ============================================================================

log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    mkdir -p "$TEST_LOGS_DIR"

    case "$level" in
        "INFO")
            echo -e "${BLUE}[INFO]${NC} $message" | tee -a "$SSL_LOG"
            ;;
        "PASS")
            echo -e "${GREEN}[PASS]${NC} $message" | tee -a "$SSL_LOG"
            ((PASSED_TESTS++))
            ;;
        "FAIL")
            echo -e "${RED}[FAIL]${NC} $message" | tee -a "$SSL_LOG"
            ((FAILED_TESTS++))
            ;;
        "WARN")
            echo -e "${YELLOW}[WARN]${NC} $message" | tee -a "$SSL_LOG"
            ((WARNINGS++))
            ;;
        "CRITICAL")
            echo -e "${RED}[CRITICAL]${NC} $message" | tee -a "$SSL_LOG"
            ((CRITICAL_ISSUES++))
            ;;
        "DEBUG")
            if [[ "${DEBUG:-false}" == "true" ]]; then
                echo -e "${PURPLE}[DEBUG]${NC} $message" | tee -a "$SSL_LOG"
            fi
            ;;
    esac
}

# ============================================================================
# Utility Functions
# ============================================================================

increment_test_counter() {
    ((TOTAL_TESTS++))
}

check_dependencies() {
    local missing_deps=()

    # Check for required tools
    local required_tools=("openssl" "curl" "timeout" "nc" "dig")

    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            missing_deps+=("$tool")
        fi
    done

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log "CRITICAL" "Missing required dependencies: ${missing_deps[*]}"
        log "INFO" "Install missing tools: sudo apt-get install ${missing_deps[*]}"
        return 1
    fi

    log "INFO" "All required dependencies are available"
    return 0
}

# ============================================================================
# SSL Certificate Testing Functions
# ============================================================================

test_certificate_validity() {
    local host="$1"
    local port="$2"

    increment_test_counter
    log "INFO" "Testing certificate validity for ${host}:${port}"

    # Check if port is open
    if ! timeout 5 nc -z "$host" "$port" 2>/dev/null; then
        log "FAIL" "Port ${port} is not accessible on ${host}"
        return 1
    fi

    # Get certificate information
    local cert_info
    if cert_info=$(timeout "$DEFAULT_TIMEOUT" openssl s_client -connect "${host}:${port}" -servername "$host" </dev/null 2>/dev/null | openssl x509 -noout -text 2>/dev/null); then
        log "PASS" "Certificate retrieved successfully from ${host}:${port}"

        # Check certificate validity dates
        local not_before not_after
        not_before=$(echo "$cert_info" | grep "Not Before" | cut -d: -f2- | xargs)
        not_after=$(echo "$cert_info" | grep "Not After" | cut -d: -f2- | xargs)

        if [[ -n "$not_before" && -n "$not_after" ]]; then
            log "INFO" "Certificate valid from: $not_before"
            log "INFO" "Certificate valid until: $not_after"

            # Check if certificate is currently valid
            if timeout "$DEFAULT_TIMEOUT" openssl s_client -connect "${host}:${port}" -servername "$host" </dev/null 2>/dev/null | openssl x509 -noout -checkend 0 >/dev/null 2>&1; then
                log "PASS" "Certificate is currently valid"
            else
                log "FAIL" "Certificate is expired or not yet valid"
                return 1
            fi
        else
            log "FAIL" "Could not parse certificate validity dates"
            return 1
        fi
    else
        log "FAIL" "Could not retrieve certificate from ${host}:${port}"
        return 1
    fi
}

test_certificate_expiry() {
    local host="$1"
    local port="$2"

    increment_test_counter
    log "INFO" "Testing certificate expiry for ${host}:${port}"

    # Check certificate expiry in specified days
    if timeout "$DEFAULT_TIMEOUT" openssl s_client -connect "${host}:${port}" -servername "$host" </dev/null 2>/dev/null | openssl x509 -noout -checkend $((CERT_EXPIRY_CRITICAL_DAYS * 86400)) >/dev/null 2>&1; then
        log "PASS" "Certificate valid for more than $CERT_EXPIRY_CRITICAL_DAYS days"
    else
        log "CRITICAL" "Certificate expires within $CERT_EXPIRY_CRITICAL_DAYS days"
        return 1
    fi

    # Check warning threshold
    if timeout "$DEFAULT_TIMEOUT" openssl s_client -connect "${host}:${port}" -servername "$host" </dev/null 2>/dev/null | openssl x509 -noout -checkend $((CERT_EXPIRY_WARNING_DAYS * 86400)) >/dev/null 2>&1; then
        log "PASS" "Certificate valid for more than $CERT_EXPIRY_WARNING_DAYS days"
    else
        log "WARN" "Certificate expires within $CERT_EXPIRY_WARNING_DAYS days"
    fi
}

test_ssl_protocols() {
    local host="$1"
    local port="$2"

    increment_test_counter
    log "INFO" "Testing SSL/TLS protocols for ${host}:${port}"

    # Test for deprecated protocols (should fail)
    local deprecated_protocols=("ssl2" "ssl3" "tls1" "tls1_1")

    for protocol in "${deprecated_protocols[@]}"; do
        if timeout 10 openssl s_client -"$protocol" -connect "${host}:${port}" </dev/null >/dev/null 2>&1; then
            log "FAIL" "Deprecated protocol $protocol is supported"
            return 1
        else
            log "PASS" "Deprecated protocol $protocol is properly disabled"
        fi
    done

    # Test for supported protocols (should succeed)
    local supported_protocols=("tls1_2" "tls1_3")
    local protocol_supported=false

    for protocol in "${supported_protocols[@]}"; do
        if timeout 10 openssl s_client -"$protocol" -connect "${host}:${port}" </dev/null >/dev/null 2>&1; then
            log "PASS" "Secure protocol $protocol is supported"
            protocol_supported=true
        fi
    done

    if [[ "$protocol_supported" == "false" ]]; then
        log "FAIL" "No secure protocols (TLS 1.2+) are supported"
        return 1
    fi
}

test_cipher_suites() {
    local host="$1"
    local port="$2"

    increment_test_counter
    log "INFO" "Testing cipher suites for ${host}:${port}"

    # Get supported cipher suites
    local cipher_output
    if cipher_output=$(timeout "$DEFAULT_TIMEOUT" openssl s_client -connect "${host}:${port}" -cipher 'ALL:!ADH:!LOW:!EXP:!MD5:@STRENGTH' </dev/null 2>/dev/null); then
        local used_cipher
        used_cipher=$(echo "$cipher_output" | grep "Cipher    :" | cut -d: -f2 | xargs)

        if [[ -n "$used_cipher" ]]; then
            log "INFO" "Negotiated cipher: $used_cipher"

            # Check for weak ciphers
            if echo "$used_cipher" | grep -qE "(DES|RC4|MD5|NULL)"; then
                log "FAIL" "Weak cipher suite detected: $used_cipher"
                return 1
            else
                log "PASS" "Strong cipher suite in use: $used_cipher"
            fi
        else
            log "FAIL" "Could not determine cipher suite"
            return 1
        fi
    else
        log "FAIL" "Could not connect to test cipher suites"
        return 1
    fi
}

test_certificate_chain() {
    local host="$1"
    local port="$2"

    increment_test_counter
    log "INFO" "Testing certificate chain for ${host}:${port}"

    # Verify certificate chain
    if timeout "$DEFAULT_TIMEOUT" openssl s_client -connect "${host}:${port}" -servername "$host" -verify_return_error </dev/null >/dev/null 2>&1; then
        log "PASS" "Certificate chain is valid"
    else
        # For self-signed certificates in development, this is expected
        if [[ "$host" == "localhost" || "$host" == "127.0.0.1" ]]; then
            log "WARN" "Certificate chain validation failed (expected for self-signed development certificates)"
        else
            log "FAIL" "Certificate chain validation failed"
            return 1
        fi
    fi
}

test_security_headers() {
    local host="$1"
    local port="$2"

    increment_test_counter
    log "INFO" "Testing security headers for ${host}:${port}"

    local scheme="https"
    local url="${scheme}://${host}:${port}"

    # Get HTTP headers
    local headers
    if headers=$(timeout "$DEFAULT_TIMEOUT" curl -sI -k "$url" 2>/dev/null); then
        local missing_headers=()

        for header in "${SECURITY_HEADERS[@]}"; do
            if echo "$headers" | grep -qi "^${header}:"; then
                log "PASS" "Security header present: $header"
            else
                missing_headers+=("$header")
                log "WARN" "Security header missing: $header"
            fi
        done

        if [[ ${#missing_headers[@]} -eq 0 ]]; then
            log "PASS" "All expected security headers are present"
        else
            log "WARN" "Missing security headers: ${missing_headers[*]}"
        fi
    else
        log "FAIL" "Could not retrieve HTTP headers from $url"
        return 1
    fi
}

test_http_to_https_redirect() {
    local host="$1"

    increment_test_counter
    log "INFO" "Testing HTTP to HTTPS redirect for $host"

    local http_url="http://${host}"
    local response

    if response=$(timeout "$DEFAULT_TIMEOUT" curl -sI -k "$http_url" 2>/dev/null); then
        local status_code
        status_code=$(echo "$response" | grep -E "^HTTP/[0-9.]+ [0-9]+" | cut -d' ' -f2 | head -1)

        if [[ "$status_code" =~ ^30[1-8]$ ]]; then
            local location
            location=$(echo "$response" | grep -i "^location:" | cut -d' ' -f2- | tr -d '\r\n')

            if [[ "$location" =~ ^https:// ]]; then
                log "PASS" "HTTP to HTTPS redirect working (status: $status_code, location: $location)"
            else
                log "FAIL" "HTTP redirect does not use HTTPS (location: $location)"
                return 1
            fi
        else
            log "FAIL" "HTTP to HTTPS redirect not configured (status: $status_code)"
            return 1
        fi
    else
        log "WARN" "Could not test HTTP to HTTPS redirect (HTTP port may not be accessible)"
    fi
}

test_ssl_certificate_san() {
    local host="$1"
    local port="$2"

    increment_test_counter
    log "INFO" "Testing certificate Subject Alternative Names for ${host}:${port}"

    # Get certificate and check SAN
    local cert_info
    if cert_info=$(timeout "$DEFAULT_TIMEOUT" openssl s_client -connect "${host}:${port}" -servername "$host" </dev/null 2>/dev/null | openssl x509 -noout -text 2>/dev/null); then
        local san_info
        san_info=$(echo "$cert_info" | grep -A 1 "Subject Alternative Name" | tail -1 | sed 's/^[[:space:]]*//')

        if [[ -n "$san_info" ]]; then
            log "INFO" "Certificate SAN: $san_info"

            # Check if current host is in SAN
            if echo "$san_info" | grep -q "$host"; then
                log "PASS" "Host $host is included in certificate SAN"
            else
                log "WARN" "Host $host is not explicitly listed in certificate SAN"
            fi
        else
            log "WARN" "No Subject Alternative Names found in certificate"
        fi
    else
        log "FAIL" "Could not retrieve certificate information"
        return 1
    fi
}

test_ssl_vulnerability_checks() {
    local host="$1"
    local port="$2"

    increment_test_counter
    log "INFO" "Testing for SSL vulnerabilities on ${host}:${port}"

    # Test for POODLE vulnerability (SSLv3)
    if timeout 10 openssl s_client -ssl3 -connect "${host}:${port}" </dev/null >/dev/null 2>&1; then
        log "CRITICAL" "POODLE vulnerability: SSLv3 is enabled"
        return 1
    else
        log "PASS" "POODLE vulnerability: SSLv3 is properly disabled"
    fi

    # Test for BEAST vulnerability (TLS 1.0 with CBC ciphers)
    if timeout 10 openssl s_client -tls1 -cipher 'AES:DES:3DES:CAMELLIA' -connect "${host}:${port}" </dev/null >/dev/null 2>&1; then
        log "WARN" "Potential BEAST vulnerability: TLS 1.0 with CBC ciphers enabled"
    else
        log "PASS" "BEAST vulnerability: TLS 1.0 with CBC ciphers is disabled"
    fi

    # Test for CRIME vulnerability (compression)
    local compression_test
    if compression_test=$(timeout 10 openssl s_client -connect "${host}:${port}" </dev/null 2>/dev/null | grep "Compression:"); then
        if echo "$compression_test" | grep -q "NONE"; then
            log "PASS" "CRIME vulnerability: Compression is disabled"
        else
            log "CRITICAL" "CRIME vulnerability: Compression is enabled"
            return 1
        fi
    fi
}

# ============================================================================
# Main Testing Functions
# ============================================================================

run_ssl_tests_for_host() {
    local host="$1"
    local port="$2"

    log "INFO" "Starting SSL certificate validation for ${host}:${port}"

    # Run all SSL tests
    test_certificate_validity "$host" "$port"
    test_certificate_expiry "$host" "$port"
    test_ssl_protocols "$host" "$port"
    test_cipher_suites "$host" "$port"
    test_certificate_chain "$host" "$port"
    test_security_headers "$host" "$port"
    test_ssl_certificate_san "$host" "$port"
    test_ssl_vulnerability_checks "$host" "$port"

    # HTTP to HTTPS redirect test (only for port 443)
    if [[ "$port" == "443" ]]; then
        test_http_to_https_redirect "$host"
    fi

    log "INFO" "Completed SSL certificate validation for ${host}:${port}"
}

run_comprehensive_ssl_tests() {
    log "INFO" "Starting comprehensive SSL certificate validation"

    # Test all configured hosts and ports
    for host in "${TEST_HOSTS[@]}"; do
        for port in "${SSL_PORTS[@]}"; do
            run_ssl_tests_for_host "$host" "$port"
            echo "" # Add spacing between host:port combinations
        done
    done
}

# ============================================================================
# Reporting Functions
# ============================================================================

generate_ssl_report() {
    local report_file="$1"

    log "INFO" "Generating SSL certificate validation report"

    cat > "$report_file" << EOF
# ArcDeploy SSL Certificate Validation Report

Generated: $(date)
Script Version: $SCRIPT_VERSION

## Test Summary
- Total Tests: $TOTAL_TESTS
- Passed: $PASSED_TESTS
- Failed: $FAILED_TESTS
- Warnings: $WARNINGS
- Critical Issues: $CRITICAL_ISSUES

## Test Results
$(if [[ $FAILED_TESTS -eq 0 && $CRITICAL_ISSUES -eq 0 ]]; then
    echo "✅ All SSL certificate tests passed successfully"
elif [[ $CRITICAL_ISSUES -gt 0 ]]; then
    echo "❌ Critical SSL security issues detected"
else
    echo "⚠️ Some SSL certificate tests failed"
fi)

## Recommendations
$(if [[ $CRITICAL_ISSUES -gt 0 ]]; then
    echo "- Address critical security vulnerabilities immediately"
fi)
$(if [[ $FAILED_TESTS -gt 0 ]]; then
    echo "- Review failed tests and fix SSL configuration issues"
fi)
$(if [[ $WARNINGS -gt 0 ]]; then
    echo "- Consider addressing warning items for improved security"
fi)
$(if [[ $FAILED_TESTS -eq 0 && $CRITICAL_ISSUES -eq 0 ]]; then
    echo "- SSL configuration appears to be secure and properly implemented"
fi)

## Detailed Logs
See: $SSL_LOG

EOF

    log "INFO" "SSL certificate validation report saved to: $report_file"
}

# ============================================================================
# Help and Usage
# ============================================================================

show_help() {
    cat << EOF
Usage: $SCRIPT_NAME [OPTIONS]

ArcDeploy SSL Certificate Validation Test Suite

This script performs comprehensive SSL/TLS certificate validation including:
- Certificate validity and expiry checks
- SSL protocol security testing
- Cipher suite validation
- Certificate chain verification
- Security headers validation
- HTTP to HTTPS redirect testing
- SSL vulnerability scanning

OPTIONS:
    -h, --help              Show this help message
    -d, --debug             Enable debug output
    -q, --quick             Run quick tests only
    --host HOST             Test specific host (default: localhost, 127.0.0.1)
    --port PORT             Test specific port (default: 443, 8443)
    --timeout SECONDS       Set connection timeout (default: $DEFAULT_TIMEOUT)
    --report-only           Generate report from existing logs
    --version               Show script version

EXAMPLES:
    $SCRIPT_NAME                           # Run all SSL tests
    $SCRIPT_NAME --quick                   # Run quick validation only
    $SCRIPT_NAME --host example.com       # Test specific host
    $SCRIPT_NAME --port 8443               # Test specific port
    $SCRIPT_NAME --debug                   # Enable debug output

REPORTS:
    - Detailed logs: $SSL_LOG
    - Summary report: $SSL_REPORT

RETURN CODES:
    0 - All tests passed
    1 - Some tests failed
    2 - Critical security issues detected
    3 - Missing dependencies or configuration errors

EOF
}

# ============================================================================
# Main Script Logic
# ============================================================================

main() {
    local quick_mode=false
    local report_only=false
    local custom_host=""
    local custom_port=""

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
            -q|--quick)
                quick_mode=true
                shift
                ;;
            --host)
                custom_host="$2"
                shift 2
                ;;
            --port)
                custom_port="$2"
                shift 2
                ;;
            --timeout)
                readonly DEFAULT_TIMEOUT="$2"
                shift 2
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
    mkdir -p "$TEST_LOGS_DIR"

    # Header
    echo "=============================================="
    echo "ArcDeploy SSL Certificate Validation Suite"
    echo "Version: $SCRIPT_VERSION"
    echo "=============================================="
    echo ""

    # Check dependencies
    if ! check_dependencies; then
        exit 3
    fi

    # Handle report-only mode
    if [[ "$report_only" == "true" ]]; then
        generate_ssl_report "$SSL_REPORT"
        exit 0
    fi

    # Run tests
    if [[ -n "$custom_host" && -n "$custom_port" ]]; then
        # Test specific host:port
        run_ssl_tests_for_host "$custom_host" "$custom_port"
    elif [[ -n "$custom_host" ]]; then
        # Test specific host on all ports
        for port in "${SSL_PORTS[@]}"; do
            run_ssl_tests_for_host "$custom_host" "$port"
        done
    elif [[ -n "$custom_port" ]]; then
        # Test specific port on all hosts
        for host in "${TEST_HOSTS[@]}"; do
            run_ssl_tests_for_host "$host" "$custom_port"
        done
    else
        # Run comprehensive tests
        run_comprehensive_ssl_tests
    fi

    # Generate report
    generate_ssl_report "$SSL_REPORT"

    # Summary
    echo ""
    echo "=============================================="
    echo "SSL Certificate Validation Complete"
    echo "=============================================="
    echo "Total Tests: $TOTAL_TESTS"
    echo "Passed: $PASSED_TESTS"
    echo "Failed: $FAILED_TESTS"
    echo "Warnings: $WARNINGS"
    echo "Critical Issues: $CRITICAL_ISSUES"
    echo ""
    echo "Reports saved to:"
    echo "- Summary: $SSL_REPORT"
    echo "- Detailed logs: $SSL_LOG"
    echo ""

    # Exit with appropriate code
    if [[ $CRITICAL_ISSUES -gt 0 ]]; then
        log "CRITICAL" "Critical security issues detected. Immediate attention required."
        exit 2
    elif [[ $FAILED_TESTS -gt 0 ]]; then
        log "WARN" "Some SSL certificate tests failed. Review and fix issues."
        exit 1
    else
        log "INFO" "All SSL certificate tests passed successfully."
        exit 0
    fi
}

# Execute main function with all arguments
main "$@"
