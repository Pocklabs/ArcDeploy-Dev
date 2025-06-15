#!/bin/bash

# ArcDeploy Network Failure Injection Scenarios
# Comprehensive network failure simulation for testing resilience and recovery

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
readonly NETWORK_LOG="$PROJECT_ROOT/test-results/failure-injection/network-failures.log"

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
# Network Configuration
# ============================================================================
readonly BLOCKLET_HTTP_PORT="8080"
readonly BLOCKLET_HTTPS_PORT="8443"
readonly SSH_PORT="2222"
readonly NGINX_HTTP_PORT="80"
readonly NGINX_HTTPS_PORT="443"
readonly REDIS_PORT="6379"

# Test targets
readonly TEST_DOMAINS=("google.com" "github.com" "npmjs.org" "nodejs.org")
readonly CRITICAL_PORTS=("$BLOCKLET_HTTP_PORT" "$BLOCKLET_HTTPS_PORT" "$SSH_PORT" "$REDIS_PORT")

# ============================================================================
# Logging Functions
# ============================================================================

log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    mkdir -p "$(dirname "$NETWORK_LOG")"
    
    case "$level" in
        "INFO")
            echo -e "${BLUE}[INFO]${NC} $message" | tee -a "$NETWORK_LOG"
            ;;
        "SUCCESS")
            echo -e "${GREEN}[SUCCESS]${NC} $message" | tee -a "$NETWORK_LOG"
            ;;
        "FAILURE")
            echo -e "${RED}[FAILURE]${NC} $message" | tee -a "$NETWORK_LOG"
            ;;
        "WARNING")
            echo -e "${YELLOW}[WARNING]${NC} $message" | tee -a "$NETWORK_LOG"
            ;;
        "INJECT")
            echo -e "${PURPLE}[INJECT]${NC} $message" | tee -a "$NETWORK_LOG"
            ;;
        "RECOVER")
            echo -e "${CYAN}[RECOVER]${NC} $message" | tee -a "$NETWORK_LOG"
            ;;
    esac
}

# ============================================================================
# Network Failure Scenarios
# ============================================================================

# Scenario 1: DNS Resolution Failures
inject_dns_failure() {
    local duration="${1:-60}"
    local severity="${2:-partial}"
    
    log "INJECT" "Starting DNS failure injection (duration: ${duration}s, severity: $severity)"
    
    # Backup original resolv.conf
    if [[ -f /etc/resolv.conf ]]; then
        sudo cp /etc/resolv.conf /etc/resolv.conf.backup.network-test
        log "INFO" "DNS resolver configuration backed up"
    fi
    
    case "$severity" in
        "complete")
            # Complete DNS failure - remove all nameservers
            echo "# DNS failure injection - no nameservers" | sudo tee /etc/resolv.conf > /dev/null
            log "INJECT" "Complete DNS failure injected - all nameservers removed"
            ;;
        "partial")
            # Partial DNS failure - use slow/unreliable DNS
            echo "nameserver 192.0.2.1" | sudo tee /etc/resolv.conf > /dev/null  # RFC3330 test address
            echo "nameserver 198.51.100.1" | sudo tee -a /etc/resolv.conf > /dev/null  # RFC3330 test address
            log "INJECT" "Partial DNS failure injected - using unreliable nameservers"
            ;;
        "slow")
            # Slow DNS - use distant/slow nameservers
            echo "nameserver 208.67.220.220" | sudo tee /etc/resolv.conf > /dev/null  # OpenDNS
            echo "nameserver 208.67.222.222" | sudo tee -a /etc/resolv.conf > /dev/null
            echo "options timeout:10" | sudo tee -a /etc/resolv.conf > /dev/null
            log "INJECT" "Slow DNS failure injected - using slow nameservers with timeout"
            ;;
    esac
    
    # Test DNS resolution impact
    for domain in "${TEST_DOMAINS[@]}"; do
        if ! nslookup "$domain" >/dev/null 2>&1; then
            log "INFO" "DNS resolution failed for $domain (expected)"
        else
            log "WARNING" "DNS resolution succeeded for $domain (unexpected)"
        fi
    done
    
    return 0
}

# Scenario 2: Port Blocking Failures
inject_port_blocking() {
    local duration="${1:-60}"
    local ports="${2:-$BLOCKLET_HTTP_PORT,$BLOCKLET_HTTPS_PORT}"
    
    log "INJECT" "Starting port blocking injection (duration: ${duration}s, ports: $ports)"
    
    # Convert comma-separated ports to array
    IFS=',' read -ra PORT_ARRAY <<< "$ports"
    
    # Block specified ports using iptables
    for port in "${PORT_ARRAY[@]}"; do
        # Block incoming connections
        sudo iptables -I INPUT -p tcp --dport "$port" -j DROP 2>/dev/null || true
        # Block outgoing connections
        sudo iptables -I OUTPUT -p tcp --sport "$port" -j DROP 2>/dev/null || true
        log "INJECT" "Blocked port $port (incoming and outgoing)"
    done
    
    # Test port accessibility
    for port in "${PORT_ARRAY[@]}"; do
        if ! nc -z localhost "$port" 2>/dev/null; then
            log "INFO" "Port $port is blocked (expected)"
        else
            log "WARNING" "Port $port is still accessible (unexpected)"
        fi
    done
    
    return 0
}

# Scenario 3: Bandwidth Throttling
inject_bandwidth_throttling() {
    local duration="${1:-60}"
    local limit="${2:-1mbit}"
    local interface="${3:-eth0}"
    
    log "INJECT" "Starting bandwidth throttling (duration: ${duration}s, limit: $limit, interface: $interface)"
    
    # Check if tc (traffic control) is available
    if ! command -v tc >/dev/null 2>&1; then
        log "WARNING" "tc (traffic control) not available, installing iproute2"
        sudo apt-get update >/dev/null 2>&1 || true
        sudo apt-get install -y iproute2 >/dev/null 2>&1 || true
    fi
    
    # Detect actual network interface if eth0 doesn't exist
    if ! ip link show "$interface" >/dev/null 2>&1; then
        interface=$(ip route get 8.8.8.8 | awk 'NR==1 {print $(NF-2)}' 2>/dev/null || echo "eth0")
        log "INFO" "Using detected network interface: $interface"
    fi
    
    # Apply bandwidth limiting
    if ip link show "$interface" >/dev/null 2>&1; then
        # Remove existing qdisc
        sudo tc qdisc del dev "$interface" root 2>/dev/null || true
        
        # Add bandwidth limiting
        sudo tc qdisc add dev "$interface" root handle 1: tbf rate "$limit" burst 32kbit latency 400ms
        log "INJECT" "Bandwidth limited to $limit on interface $interface"
        
        # Test bandwidth impact
        log "INFO" "Testing bandwidth limitation..."
        if command -v wget >/dev/null 2>&1; then
            timeout 10 wget -O /dev/null http://httpbin.org/bytes/1048576 2>/dev/null || log "INFO" "Bandwidth limitation affecting downloads"
        fi
    else
        log "WARNING" "Network interface $interface not found, skipping bandwidth throttling"
        return 1
    fi
    
    return 0
}

# Scenario 4: Network Interface Failures
inject_interface_failure() {
    local duration="${1:-60}"
    local interface="${2:-auto}"
    local failure_type="${3:-down}"
    
    log "INJECT" "Starting interface failure injection (duration: ${duration}s, interface: $interface, type: $failure_type)"
    
    # Auto-detect primary network interface
    if [[ "$interface" == "auto" ]]; then
        interface=$(ip route get 8.8.8.8 | awk 'NR==1 {print $(NF-2)}' 2>/dev/null || echo "eth0")
        log "INFO" "Auto-detected network interface: $interface"
    fi
    
    # Verify interface exists
    if ! ip link show "$interface" >/dev/null 2>&1; then
        log "FAILURE" "Network interface $interface not found"
        return 1
    fi
    
    case "$failure_type" in
        "down")
            # Bring interface down
            sudo ip link set "$interface" down
            log "INJECT" "Network interface $interface brought down"
            ;;
        "flapping")
            # Interface flapping simulation
            log "INJECT" "Starting interface flapping simulation on $interface"
            for i in {1..5}; do
                sudo ip link set "$interface" down
                sleep 2
                sudo ip link set "$interface" up
                sleep 3
                log "INFO" "Interface flap cycle $i/5 completed"
            done
            ;;
        "mtu_reduction")
            # Reduce MTU to cause fragmentation issues
            original_mtu=$(ip link show "$interface" | grep -oP 'mtu \K\d+' | head -1)
            sudo ip link set dev "$interface" mtu 500
            log "INJECT" "MTU reduced from $original_mtu to 500 on $interface"
            ;;
    esac
    
    # Test connectivity impact
    if ! ping -c 1 -W 5 8.8.8.8 >/dev/null 2>&1; then
        log "INFO" "Network connectivity lost (expected)"
    else
        log "WARNING" "Network connectivity still available (unexpected)"
    fi
    
    return 0
}

# Scenario 5: Packet Loss Simulation
inject_packet_loss() {
    local duration="${1:-60}"
    local loss_percentage="${2:-25}"
    local interface="${3:-auto}"
    
    log "INJECT" "Starting packet loss injection (duration: ${duration}s, loss: $loss_percentage%, interface: $interface)"
    
    # Auto-detect primary network interface
    if [[ "$interface" == "auto" ]]; then
        interface=$(ip route get 8.8.8.8 | awk 'NR==1 {print $(NF-2)}' 2>/dev/null || echo "eth0")
        log "INFO" "Auto-detected network interface: $interface"
    fi
    
    # Verify interface exists
    if ! ip link show "$interface" >/dev/null 2>&1; then
        log "WARNING" "Network interface $interface not found, skipping packet loss injection"
        return 1
    fi
    
    # Check if tc is available
    if ! command -v tc >/dev/null 2>&1; then
        log "WARNING" "tc (traffic control) not available, installing iproute2"
        sudo apt-get update >/dev/null 2>&1 || true
        sudo apt-get install -y iproute2 >/dev/null 2>&1 || true
    fi
    
    # Remove existing qdisc
    sudo tc qdisc del dev "$interface" root 2>/dev/null || true
    
    # Add packet loss
    sudo tc qdisc add dev "$interface" root netem loss "$loss_percentage%"
    log "INJECT" "Packet loss of $loss_percentage% injected on interface $interface"
    
    # Test packet loss impact
    local lost_packets=0
    local total_packets=10
    
    for i in $(seq 1 $total_packets); do
        if ! ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
            ((lost_packets++))
        fi
    done
    
    local actual_loss=$((lost_packets * 100 / total_packets))
    log "INFO" "Actual packet loss observed: $actual_loss% ($lost_packets/$total_packets packets)"
    
    return 0
}

# Scenario 6: Latency Injection
inject_network_latency() {
    local duration="${1:-60}"
    local latency="${2:-500ms}"
    local jitter="${3:-100ms}"
    local interface="${4:-auto}"
    
    log "INJECT" "Starting latency injection (duration: ${duration}s, latency: $latency, jitter: $jitter, interface: $interface)"
    
    # Auto-detect primary network interface
    if [[ "$interface" == "auto" ]]; then
        interface=$(ip route get 8.8.8.8 | awk 'NR==1 {print $(NF-2)}' 2>/dev/null || echo "eth0")
        log "INFO" "Auto-detected network interface: $interface"
    fi
    
    # Verify interface exists
    if ! ip link show "$interface" >/dev/null 2>&1; then
        log "WARNING" "Network interface $interface not found, skipping latency injection"
        return 1
    fi
    
    # Check if tc is available
    if ! command -v tc >/dev/null 2>&1; then
        log "WARNING" "tc (traffic control) not available, installing iproute2"
        sudo apt-get update >/dev/null 2>&1 || true
        sudo apt-get install -y iproute2 >/dev/null 2>&1 || true
    fi
    
    # Remove existing qdisc
    sudo tc qdisc del dev "$interface" root 2>/dev/null || true
    
    # Add latency and jitter
    sudo tc qdisc add dev "$interface" root netem delay "$latency" "$jitter"
    log "INJECT" "Network latency of $latency (±$jitter) injected on interface $interface"
    
    # Test latency impact
    log "INFO" "Testing latency impact..."
    if command -v ping >/dev/null 2>&1; then
        avg_latency=$(ping -c 5 8.8.8.8 2>/dev/null | tail -1 | awk -F '/' '{print $5}' || echo "unknown")
        log "INFO" "Average ping latency: ${avg_latency}ms"
    fi
    
    return 0
}

# Scenario 7: Connection Limit Exhaustion
inject_connection_exhaustion() {
    local duration="${1:-60}"
    local target_port="${2:-$BLOCKLET_HTTP_PORT}"
    local connections="${3:-1000}"
    
    log "INJECT" "Starting connection exhaustion (duration: ${duration}s, port: $target_port, connections: $connections)"
    
    # Array to store background process PIDs
    local pids=()
    
    # Create multiple connections to exhaust limits
    for i in $(seq 1 "$connections"); do
        if [[ $((i % 100)) -eq 0 ]]; then
            log "INFO" "Created $i/$connections connections..."
        fi
        
        # Create connection in background
        (
            exec 3<>/dev/tcp/localhost/"$target_port" 2>/dev/null || true
            sleep "$duration"
            exec 3<&-
        ) &
        
        pids+=($!)
        
        # Small delay to prevent overwhelming the system
        sleep 0.01
    done
    
    log "INJECT" "Created $connections concurrent connections to port $target_port"
    
    # Test service availability during exhaustion
    if ! curl -sf --max-time 5 "http://localhost:$target_port" >/dev/null 2>&1; then
        log "INFO" "Service appears affected by connection exhaustion (expected)"
    else
        log "WARNING" "Service still responding normally (unexpected)"
    fi
    
    # Store PIDs for cleanup
    printf '%s\n' "${pids[@]}" > "/tmp/network_exhaustion_pids.$$"
    
    return 0
}

# ============================================================================
# Recovery Functions
# ============================================================================

recover_dns_failure() {
    log "RECOVER" "Recovering from DNS failure injection"
    
    if [[ -f /etc/resolv.conf.backup.network-test ]]; then
        sudo mv /etc/resolv.conf.backup.network-test /etc/resolv.conf
        log "RECOVER" "DNS resolver configuration restored from backup"
    else
        # Fallback DNS configuration
        echo "nameserver 8.8.8.8" | sudo tee /etc/resolv.conf > /dev/null
        echo "nameserver 8.8.4.4" | sudo tee -a /etc/resolv.conf > /dev/null
        log "RECOVER" "DNS resolver configuration restored to default"
    fi
    
    # Test DNS recovery
    if nslookup google.com >/dev/null 2>&1; then
        log "SUCCESS" "DNS resolution recovered successfully"
        return 0
    else
        log "FAILURE" "DNS resolution still failing after recovery"
        return 1
    fi
}

recover_port_blocking() {
    log "RECOVER" "Recovering from port blocking injection"
    
    # Remove all iptables rules related to our test ports
    for port in "${CRITICAL_PORTS[@]}"; do
        sudo iptables -D INPUT -p tcp --dport "$port" -j DROP 2>/dev/null || true
        sudo iptables -D OUTPUT -p tcp --sport "$port" -j DROP 2>/dev/null || true
        log "RECOVER" "Removed iptables rules for port $port"
    done
    
    # Test port recovery
    local recovery_success=true
    for port in "${CRITICAL_PORTS[@]}"; do
        if nc -z localhost "$port" 2>/dev/null; then
            log "SUCCESS" "Port $port is accessible again"
        else
            log "WARNING" "Port $port still not accessible"
            recovery_success=false
        fi
    done
    
    if $recovery_success; then
        return 0
    else
        return 1
    fi
}

recover_bandwidth_throttling() {
    local interface="${1:-auto}"
    
    log "RECOVER" "Recovering from bandwidth throttling"
    
    # Auto-detect interface if needed
    if [[ "$interface" == "auto" ]]; then
        interface=$(ip route get 8.8.8.8 | awk 'NR==1 {print $(NF-2)}' 2>/dev/null || echo "eth0")
    fi
    
    # Remove traffic control rules
    if ip link show "$interface" >/dev/null 2>&1; then
        sudo tc qdisc del dev "$interface" root 2>/dev/null || true
        log "RECOVER" "Bandwidth throttling removed from interface $interface"
        
        # Test bandwidth recovery
        log "INFO" "Testing bandwidth recovery..."
        if command -v wget >/dev/null 2>&1; then
            if timeout 10 wget -O /dev/null http://httpbin.org/bytes/1048576 >/dev/null 2>&1; then
                log "SUCCESS" "Bandwidth appears to be restored"
                return 0
            else
                log "WARNING" "Bandwidth may still be limited"
                return 1
            fi
        fi
        return 0
    else
        log "WARNING" "Interface $interface not found during recovery"
        return 1
    fi
}

recover_interface_failure() {
    local interface="${1:-auto}"
    
    log "RECOVER" "Recovering from interface failure"
    
    # Auto-detect interface if needed
    if [[ "$interface" == "auto" ]]; then
        interface=$(ip route get 8.8.8.8 | awk 'NR==1 {print $(NF-2)}' 2>/dev/null || echo "eth0")
    fi
    
    # Bring interface up
    if ip link show "$interface" >/dev/null 2>&1; then
        sudo ip link set "$interface" up
        log "RECOVER" "Network interface $interface brought up"
        
        # Restore original MTU if it was changed
        sudo ip link set dev "$interface" mtu 1500 2>/dev/null || true
        log "RECOVER" "MTU restored to 1500 on interface $interface"
        
        # Wait for interface to be ready
        sleep 5
        
        # Test connectivity recovery
        if ping -c 1 -W 5 8.8.8.8 >/dev/null 2>&1; then
            log "SUCCESS" "Network connectivity recovered"
            return 0
        else
            log "WARNING" "Network connectivity not yet restored"
            return 1
        fi
    else
        log "FAILURE" "Interface $interface not found during recovery"
        return 1
    fi
}

recover_packet_loss() {
    local interface="${1:-auto}"
    
    log "RECOVER" "Recovering from packet loss injection"
    
    # Auto-detect interface if needed
    if [[ "$interface" == "auto" ]]; then
        interface=$(ip route get 8.8.8.8 | awk 'NR==1 {print $(NF-2)}' 2>/dev/null || echo "eth0")
    fi
    
    # Remove traffic control rules
    if ip link show "$interface" >/dev/null 2>&1; then
        sudo tc qdisc del dev "$interface" root 2>/dev/null || true
        log "RECOVER" "Packet loss injection removed from interface $interface"
        
        # Test packet loss recovery
        local lost_packets=0
        local total_packets=5
        
        for i in $(seq 1 $total_packets); do
            if ! ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
                ((lost_packets++))
            fi
        done
        
        local actual_loss=$((lost_packets * 100 / total_packets))
        log "INFO" "Post-recovery packet loss: $actual_loss% ($lost_packets/$total_packets packets)"
        
        if [[ $actual_loss -le 10 ]]; then
            log "SUCCESS" "Packet loss recovered successfully"
            return 0
        else
            log "WARNING" "High packet loss still observed after recovery"
            return 1
        fi
    else
        log "WARNING" "Interface $interface not found during recovery"
        return 1
    fi
}

recover_network_latency() {
    local interface="${1:-auto}"
    
    log "RECOVER" "Recovering from network latency injection"
    
    # Auto-detect interface if needed
    if [[ "$interface" == "auto" ]]; then
        interface=$(ip route get 8.8.8.8 | awk 'NR==1 {print $(NF-2)}' 2>/dev/null || echo "eth0")
    fi
    
    # Remove traffic control rules
    if ip link show "$interface" >/dev/null 2>&1; then
        sudo tc qdisc del dev "$interface" root 2>/dev/null || true
        log "RECOVER" "Network latency injection removed from interface $interface"
        
        # Test latency recovery
        if command -v ping >/dev/null 2>&1; then
            avg_latency=$(ping -c 3 8.8.8.8 2>/dev/null | tail -1 | awk -F '/' '{print $5}' || echo "unknown")
            log "INFO" "Post-recovery average latency: ${avg_latency}ms"
            
            # If latency is reasonable (< 100ms), consider it recovered
            if [[ "$avg_latency" != "unknown" ]] && (( $(echo "$avg_latency < 100" | bc -l 2>/dev/null || echo 1) )); then
                log "SUCCESS" "Network latency recovered successfully"
                return 0
            else
                log "WARNING" "Network latency may still be elevated"
                return 1
            fi
        fi
        return 0
    else
        log "WARNING" "Interface $interface not found during recovery"
        return 1
    fi
}

recover_connection_exhaustion() {
    log "RECOVER" "Recovering from connection exhaustion"
    
    # Kill all background connection processes
    if [[ -f "/tmp/network_exhaustion_pids.$$" ]]; then
        while read -r pid; do
            kill "$pid" 2>/dev/null || true
        done < "/tmp/network_exhaustion_pids.$$"
        rm -f "/tmp/network_exhaustion_pids.$$"
        log "RECOVER" "Terminated exhaustion connection processes"
    fi
    
    # Wait for connections to close
    sleep 5
    
    # Test service recovery
    if curl -sf --max-time 5 "http://localhost:$BLOCKLET_HTTP_PORT" >/dev/null 2>&1; then
        log "SUCCESS" "Service recovered from connection exhaustion"
        return 0
    else
        log "WARNING" "Service may still be affected by connection exhaustion"
        return 1
    fi
}

# ============================================================================
# Main Functions
# ============================================================================

run_network_failure_scenario() {
    local scenario="$1"
    local duration="${2:-60}"
    local params="${3:-}"
    
    log "INFO" "Running network failure scenario: $scenario"
    
    case "$scenario" in
        "dns_complete")
            inject_dns_failure "$duration" "complete"
            ;;
        "dns_partial")
            inject_dns_failure "$duration" "partial"
            ;;
        "dns_slow")
            inject_dns_failure "$duration" "slow"
            ;;
        "port_blocking")
            inject_port_blocking "$duration" "$params"
            ;;
        "bandwidth_throttle")
            inject_bandwidth_throttling "$duration" "${params:-1mbit}"
            ;;
        "interface_down")
            inject_interface_failure "$duration" "auto" "down"
            ;;
        "interface_flapping")
            inject_interface_failure "$duration" "auto" "flapping"
            ;;
        "mtu_reduction")
            inject_interface_failure "$duration" "auto" "mtu_reduction"
            ;;
        "packet_loss")
            inject_packet_loss "$duration" "${params:-25}"
            ;;
        "high_latency")
            inject_network_latency "$duration" "${params:-500ms}" "100ms"
            ;;
        "connection_exhaustion")
            inject_connection_exhaustion "$duration" "$BLOCKLET_HTTP_PORT" "${params:-500}"
            ;;
        *)
            log "FAILURE" "Unknown network failure scenario: $scenario"
            return 1
            ;;
    esac
}

recover_network_failure_scenario() {
    local scenario="$1"
    
    log "INFO" "Recovering from network failure scenario: $scenario"
    
    case "$scenario" in
        "dns_"*)
            recover_dns_failure
            ;;
        "port_blocking")
            recover_port_blocking
            ;;
        "bandwidth_throttle")
            recover_bandwidth_throttling
            ;;
        "interface_"* | "mtu_reduction")
            recover_interface_failure
            ;;
        "packet_loss")
            recover_packet_loss
            ;;
        "high_latency")
            recover_network_latency
            ;;
        "connection_exhaustion")
            recover_connection_exhaustion
            ;;
        *)
            log "WARNING" "No specific recovery procedure for scenario: $scenario"
            # Generic cleanup
            recover_dns_failure 2>/dev/null || true
            recover_port_blocking 2>/dev/null || true
            recover_bandwidth_throttling 2>/dev/null || true
            recover_interface_failure 2>/dev/null || true
            recover_packet_loss 2>/dev/null || true
            recover_network_latency 2>/dev/null || true
            recover_connection_exhaustion 2>/dev/null || true
            ;;
    esac
}

# ============================================================================
# Usage and Help
# ============================================================================

show_usage() {
    cat << EOF
ArcDeploy Network Failure Injection Scenarios

Usage: $SCRIPT_NAME [OPTION]... SCENARIO [DURATION] [PARAMS]

SCENARIOS:
  dns_complete          Complete DNS failure (no resolution)
  dns_partial           Partial DNS failure (unreliable nameservers)
  dns_slow              Slow DNS resolution
  port_blocking         Block specific ports (default: 8080,8443)
  bandwidth_throttle    Limit bandwidth (default: 1mbit)
  interface_down        Bring network interface down
  interface_flapping    Simulate interface flapping
  mtu_reduction         Reduce MTU size
  packet_loss           Inject packet loss (default: 25%)
  high_latency          Add network latency (default: 500ms)
  connection_exhaustion Exhaust connection limits (default: 500 connections)

OPTIONS:
  -r, --recover SCENARIO    Recover from specific scenario
  -l, --list               List all available scenarios
  -h, --help               Show this help message
  -v, --version            Show script version

EXAMPLES:
  $SCRIPT_NAME dns_complete 60
  $SCRIPT_NAME port_blocking 120 "8080,8443,22"
  $SCRIPT_NAME bandwidth_throttle 90 "500kbit"
  $SCRIPT_NAME packet_loss 60 "50"
  $SCRIPT_NAME --recover dns_complete

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
            echo "Available network failure scenarios:"
            echo "  - dns_complete, dns_partial, dns_slow"
            echo "  - port_blocking, bandwidth_throttle"
            echo "  - interface_down, interface_flapping, mtu_reduction"
            echo "  - packet_loss, high_latency, connection_exhaustion"
            exit 0
            ;;
        -r|--recover)
            if [[ $# -lt 2 ]]; then
                echo "Error: Scenario name required for recovery"
                exit 1
            fi
            recover_network_failure_scenario "$2"
            exit $?
            ;;
        *)
            scenario="$1"
            duration="${2:-60}"
            params="${3:-}"
            
            run_network_failure_scenario "$scenario" "$duration" "$params"
            exit $?
            ;;
    esac
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi