#!/bin/bash

# Network Failure Simulation Script for ArcDeploy Testing
# Simulates various network failure scenarios for comprehensive testing

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
readonly LOG_FILE="/tmp/arcdeploy-network-sim.log"
readonly PID_FILE="/tmp/arcdeploy-network-sim.pid"
readonly IPTABLES_BACKUP="/tmp/arcdeploy-iptables-backup"

# Network simulation parameters
readonly DEFAULT_DELAY_MS="100"
readonly DEFAULT_LOSS_PERCENT="5"
readonly DEFAULT_CORRUPT_PERCENT="1"
readonly DEFAULT_DUPLICATE_PERCENT="1"
readonly DEFAULT_BANDWIDTH_LIMIT="1mbit"

# Color output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# ============================================================================
# Logging Functions
# ============================================================================

log() {
    local message="$1"
    echo -e "${BLUE}[INFO]${NC} $message" | tee -a "$LOG_FILE"
}

success() {
    local message="$1"
    echo -e "${GREEN}[SUCCESS]${NC} $message" | tee -a "$LOG_FILE"
}

warning() {
    local message="$1"
    echo -e "${YELLOW}[WARNING]${NC} $message" | tee -a "$LOG_FILE"
}

error() {
    local message="$1"
    echo -e "${RED}[ERROR]${NC} $message" | tee -a "$LOG_FILE"
}

debug() {
    local message="$1"
    if [[ "${DEBUG_MODE:-false}" == "true" ]]; then
        echo -e "${BLUE}[DEBUG]${NC} $message" | tee -a "$LOG_FILE"
    fi
}

# ============================================================================
# Utility Functions
# ============================================================================

check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root for network manipulation"
        echo "Please run with sudo: sudo $0 $*"
        exit 1
    fi
}

check_dependencies() {
    local dependencies=("tc" "iptables" "netstat" "ss")
    local missing=()
    
    for cmd in "${dependencies[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing+=("$cmd")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        error "Missing required dependencies: ${missing[*]}"
        echo "Install with: apt-get install iproute2 iptables net-tools"
        exit 1
    fi
}

backup_iptables() {
    log "Backing up current iptables rules..."
    if iptables-save > "$IPTABLES_BACKUP"; then
        success "Iptables rules backed up to $IPTABLES_BACKUP"
    else
        error "Failed to backup iptables rules"
        exit 1
    fi
}

restore_iptables() {
    if [[ -f "$IPTABLES_BACKUP" ]]; then
        log "Restoring iptables rules from backup..."
        if iptables-restore < "$IPTABLES_BACKUP"; then
            success "Iptables rules restored"
            rm -f "$IPTABLES_BACKUP"
        else
            error "Failed to restore iptables rules"
        fi
    fi
}

cleanup() {
    log "Cleaning up network simulation..."
    
    # Remove traffic control rules
    tc qdisc del dev lo root 2>/dev/null || true
    
    # Restore iptables
    restore_iptables
    
    # Remove PID file
    rm -f "$PID_FILE"
    
    success "Network simulation cleanup completed"
}

# Set up cleanup trap
trap cleanup EXIT INT TERM

# ============================================================================
# Network Simulation Functions
# ============================================================================

simulate_latency() {
    local interface="${1:-lo}"
    local delay="${2:-$DEFAULT_DELAY_MS}"
    local jitter="${3:-10}"
    
    log "Simulating network latency: ${delay}ms ±${jitter}ms on $interface"
    
    # Add delay using tc (traffic control)
    tc qdisc add dev "$interface" root netem delay "${delay}ms" "${jitter}ms" 2>/dev/null || {
        # If rule already exists, replace it
        tc qdisc change dev "$interface" root netem delay "${delay}ms" "${jitter}ms" 2>/dev/null || {
            error "Failed to add latency simulation"
            return 1
        }
    }
    
    success "Latency simulation active: ${delay}ms ±${jitter}ms"
}

simulate_packet_loss() {
    local interface="${1:-lo}"
    local loss_percent="${2:-$DEFAULT_LOSS_PERCENT}"
    
    log "Simulating packet loss: ${loss_percent}% on $interface"
    
    # Add packet loss using tc
    tc qdisc add dev "$interface" root netem loss "${loss_percent}%" 2>/dev/null || {
        tc qdisc change dev "$interface" root netem loss "${loss_percent}%" 2>/dev/null || {
            error "Failed to add packet loss simulation"
            return 1
        }
    }
    
    success "Packet loss simulation active: ${loss_percent}%"
}

simulate_bandwidth_limit() {
    local interface="${1:-lo}"
    local bandwidth="${2:-$DEFAULT_BANDWIDTH_LIMIT}"
    
    log "Simulating bandwidth limitation: $bandwidth on $interface"
    
    # Create root qdisc with bandwidth limit
    tc qdisc add dev "$interface" root handle 1: tbf rate "$bandwidth" burst 32kbit latency 400ms 2>/dev/null || {
        tc qdisc change dev "$interface" root handle 1: tbf rate "$bandwidth" burst 32kbit latency 400ms 2>/dev/null || {
            error "Failed to add bandwidth limitation"
            return 1
        }
    }
    
    success "Bandwidth limitation active: $bandwidth"
}

simulate_packet_corruption() {
    local interface="${1:-lo}"
    local corrupt_percent="${2:-$DEFAULT_CORRUPT_PERCENT}"
    
    log "Simulating packet corruption: ${corrupt_percent}% on $interface"
    
    tc qdisc add dev "$interface" root netem corrupt "${corrupt_percent}%" 2>/dev/null || {
        tc qdisc change dev "$interface" root netem corrupt "${corrupt_percent}%" 2>/dev/null || {
            error "Failed to add packet corruption simulation"
            return 1
        }
    }
    
    success "Packet corruption simulation active: ${corrupt_percent}%"
}

simulate_packet_duplication() {
    local interface="${1:-lo}"
    local duplicate_percent="${2:-$DEFAULT_DUPLICATE_PERCENT}"
    
    log "Simulating packet duplication: ${duplicate_percent}% on $interface"
    
    tc qdisc add dev "$interface" root netem duplicate "${duplicate_percent}%" 2>/dev/null || {
        tc qdisc change dev "$interface" root netem duplicate "${duplicate_percent}%" 2>/dev/null || {
            error "Failed to add packet duplication simulation"
            return 1
        }
    }
    
    success "Packet duplication simulation active: ${duplicate_percent}%"
}

simulate_network_partition() {
    local target_ip="${1:-8.8.8.8}"
    local duration="${2:-30}"
    
    log "Simulating network partition to $target_ip for ${duration}s"
    backup_iptables
    
    # Block traffic to target IP
    iptables -A OUTPUT -d "$target_ip" -j DROP
    iptables -A INPUT -s "$target_ip" -j DROP
    
    success "Network partition active to $target_ip"
    
    # Auto-restore after duration
    if [[ "$duration" != "permanent" ]]; then
        (
            sleep "$duration"
            log "Restoring network partition to $target_ip"
            iptables -D OUTPUT -d "$target_ip" -j DROP 2>/dev/null || true
            iptables -D INPUT -s "$target_ip" -j DROP 2>/dev/null || true
            success "Network partition to $target_ip restored"
        ) &
    fi
}

simulate_dns_failure() {
    local duration="${1:-60}"
    
    log "Simulating DNS failure for ${duration}s"
    backup_iptables
    
    # Block DNS traffic (port 53)
    iptables -A OUTPUT -p udp --dport 53 -j DROP
    iptables -A OUTPUT -p tcp --dport 53 -j DROP
    iptables -A INPUT -p udp --sport 53 -j DROP
    iptables -A INPUT -p tcp --sport 53 -j DROP
    
    success "DNS failure simulation active"
    
    # Auto-restore after duration
    if [[ "$duration" != "permanent" ]]; then
        (
            sleep "$duration"
            log "Restoring DNS access"
            iptables -D OUTPUT -p udp --dport 53 -j DROP 2>/dev/null || true
            iptables -D OUTPUT -p tcp --dport 53 -j DROP 2>/dev/null || true
            iptables -D INPUT -p udp --sport 53 -j DROP 2>/dev/null || true
            iptables -D INPUT -p tcp --sport 53 -j DROP 2>/dev/null || true
            success "DNS access restored"
        ) &
    fi
}

simulate_http_failure() {
    local port="${1:-80}"
    local duration="${2:-60}"
    
    log "Simulating HTTP failure on port $port for ${duration}s"
    backup_iptables
    
    # Block HTTP traffic
    iptables -A OUTPUT -p tcp --dport "$port" -j DROP
    iptables -A INPUT -p tcp --sport "$port" -j DROP
    
    success "HTTP failure simulation active on port $port"
    
    # Auto-restore after duration
    if [[ "$duration" != "permanent" ]]; then
        (
            sleep "$duration"
            log "Restoring HTTP access on port $port"
            iptables -D OUTPUT -p tcp --dport "$port" -j DROP 2>/dev/null || true
            iptables -D INPUT -p tcp --sport "$port" -j DROP 2>/dev/null || true
            success "HTTP access restored on port $port"
        ) &
    fi
}

simulate_random_failures() {
    local duration="${1:-300}"
    local interface="${2:-lo}"
    
    log "Starting random network failure simulation for ${duration}s"
    
    local end_time=$(($(date +%s) + duration))
    
    while [[ $(date +%s) -lt $end_time ]]; do
        local failure_type=$((RANDOM % 6))
        local failure_duration=$((5 + RANDOM % 25))  # 5-30 seconds
        
        case $failure_type in
            0)
                log "Random failure: High latency"
                simulate_latency "$interface" "$((100 + RANDOM % 500))" "50"
                sleep "$failure_duration"
                tc qdisc del dev "$interface" root 2>/dev/null || true
                ;;
            1)
                log "Random failure: Packet loss"
                simulate_packet_loss "$interface" "$((5 + RANDOM % 15))"
                sleep "$failure_duration"
                tc qdisc del dev "$interface" root 2>/dev/null || true
                ;;
            2)
                log "Random failure: Bandwidth limit"
                simulate_bandwidth_limit "$interface" "500kbit"
                sleep "$failure_duration"
                tc qdisc del dev "$interface" root 2>/dev/null || true
                ;;
            3)
                log "Random failure: DNS failure"
                simulate_dns_failure "$failure_duration" &
                ;;
            4)
                log "Random failure: HTTP failure"
                simulate_http_failure "80" "$failure_duration" &
                ;;
            5)
                log "Random failure: Network partition"
                simulate_network_partition "8.8.8.8" "$failure_duration" &
                ;;
        esac
        
        # Wait between failures
        sleep $((30 + RANDOM % 60))
    done
    
    success "Random failure simulation completed"
}

# ============================================================================
# Monitoring Functions
# ============================================================================

monitor_network_conditions() {
    local duration="${1:-60}"
    local interval="${2:-5}"
    
    log "Monitoring network conditions for ${duration}s (sampling every ${interval}s)"
    
    local end_time=$(($(date +%s) + duration))
    local sample_count=0
    
    echo "Timestamp,Latency_ms,Packet_Loss_%,Bandwidth_kbps" > "/tmp/network-monitor.csv"
    
    while [[ $(date +%s) -lt $end_time ]]; do
        local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        
        # Test latency to localhost
        local latency=""
        if command -v ping >/dev/null 2>&1; then
            latency=$(ping -c 1 -W 1 127.0.0.1 2>/dev/null | grep 'time=' | sed 's/.*time=\([0-9.]*\).*/\1/' || echo "N/A")
        fi
        
        # Test bandwidth (simplified)
        local bandwidth="N/A"
        if command -v iperf3 >/dev/null 2>&1; then
            # Would need iperf3 server running
            bandwidth="N/A"
        fi
        
        # Simulated packet loss detection (would need real implementation)
        local packet_loss="0"
        
        echo "$timestamp,$latency,$packet_loss,$bandwidth" >> "/tmp/network-monitor.csv"
        echo "[$timestamp] Latency: ${latency}ms, Loss: ${packet_loss}%, Bandwidth: ${bandwidth}kbps"
        
        ((sample_count++))
        sleep "$interval"
    done
    
    success "Network monitoring completed. Data saved to /tmp/network-monitor.csv"
    log "Total samples collected: $sample_count"
}

show_network_status() {
    echo "=== Network Simulation Status ==="
    echo ""
    
    echo "Traffic Control Rules:"
    tc -s qdisc show 2>/dev/null || echo "No active traffic control rules"
    echo ""
    
    echo "Active Iptables Rules (last 10):"
    iptables -L -n --line-numbers | tail -10
    echo ""
    
    echo "Network Interface Status:"
    ip link show | grep -E "^[0-9]|state"
    echo ""
    
    echo "Active Network Connections:"
    ss -tuln | head -20
    echo ""
    
    if [[ -f "$PID_FILE" ]]; then
        echo "Simulation PID: $(cat "$PID_FILE")"
    else
        echo "No active simulation"
    fi
}

# ============================================================================
# Test Scenarios
# ============================================================================

test_scenario_poor_connectivity() {
    log "Testing scenario: Poor connectivity"
    
    simulate_latency "lo" "300" "100"     # High latency with jitter
    simulate_packet_loss "lo" "10"        # 10% packet loss
    simulate_bandwidth_limit "lo" "256kbit" # Low bandwidth
    
    success "Poor connectivity scenario active"
    log "Test your applications now. Press Enter to stop..."
    read -r
    
    tc qdisc del dev lo root 2>/dev/null || true
    success "Poor connectivity scenario stopped"
}

test_scenario_intermittent_failures() {
    log "Testing scenario: Intermittent failures"
    
    # Cycle through different failure modes
    for i in {1..5}; do
        log "Failure cycle $i/5"
        
        # 30 seconds of packet loss
        simulate_packet_loss "lo" "50"
        sleep 10
        tc qdisc del dev lo root 2>/dev/null || true
        
        # 30 seconds of high latency
        simulate_latency "lo" "1000" "500"
        sleep 10
        tc qdisc del dev lo root 2>/dev/null || true
        
        # 30 seconds normal
        log "Normal conditions"
        sleep 10
    done
    
    success "Intermittent failures scenario completed"
}

test_scenario_complete_outage() {
    log "Testing scenario: Complete network outage"
    
    # Block all outbound traffic
    backup_iptables
    iptables -A OUTPUT -j DROP
    
    success "Complete outage scenario active"
    log "Test your applications now. Press Enter to restore..."
    read -r
    
    restore_iptables
    success "Complete outage scenario stopped"
}

# ============================================================================
# Help and Usage
# ============================================================================

show_help() {
    cat << EOF
Network Failure Simulation Script v$SCRIPT_VERSION

Simulate various network failure conditions for testing ArcDeploy resilience.

Usage: $SCRIPT_NAME [COMMAND] [OPTIONS]

Commands:
    latency DELAY_MS [JITTER_MS]         Simulate network latency
    packet-loss PERCENT                  Simulate packet loss
    bandwidth-limit RATE                 Limit bandwidth (e.g., 1mbit, 500kbit)
    corruption PERCENT                   Simulate packet corruption
    duplication PERCENT                  Simulate packet duplication
    dns-failure [DURATION]               Block DNS traffic
    http-failure [PORT] [DURATION]       Block HTTP traffic
    network-partition IP [DURATION]      Simulate network partition
    random-failures [DURATION]          Random network failures
    monitor [DURATION] [INTERVAL]       Monitor network conditions
    status                              Show current simulation status
    stop                                Stop all simulations
    test-poor                           Test poor connectivity scenario
    test-intermittent                   Test intermittent failures
    test-outage                         Test complete outage

Options:
    -i, --interface INTERFACE           Network interface (default: lo)
    -d, --duration SECONDS              Duration in seconds
    -v, --verbose                       Enable verbose output
    -h, --help                          Show this help

Examples:
    # Simulate 200ms latency with 50ms jitter
    $SCRIPT_NAME latency 200 50

    # Simulate 15% packet loss
    $SCRIPT_NAME packet-loss 15

    # Limit bandwidth to 512kbit/s
    $SCRIPT_NAME bandwidth-limit 512kbit

    # Block DNS for 2 minutes
    $SCRIPT_NAME dns-failure 120

    # Random failures for 10 minutes
    $SCRIPT_NAME random-failures 600

    # Monitor network for 5 minutes, sample every 10 seconds
    $SCRIPT_NAME monitor 300 10

Test Scenarios:
    $SCRIPT_NAME test-poor              # Poor connectivity (high latency, packet loss)
    $SCRIPT_NAME test-intermittent      # Intermittent failures
    $SCRIPT_NAME test-outage            # Complete network outage

Requirements:
    - Root privileges (use sudo)
    - iproute2 package (tc command)
    - iptables package

EOF
}

# ============================================================================
# Main Function
# ============================================================================

main() {
    local interface="lo"
    local duration=""
    local verbose="false"
    
    # Parse global options
    while [[ $# -gt 0 ]]; do
        case $1 in
            -i|--interface)
                interface="$2"
                shift 2
                ;;
            -d|--duration)
                duration="$2"
                shift 2
                ;;
            -v|--verbose)
                verbose="true"
                export DEBUG_MODE="true"
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            -*)
                error "Unknown option: $1"
                show_help
                exit 1
                ;;
            *)
                break
                ;;
        esac
    done
    
    if [[ $# -eq 0 ]]; then
        show_help
        exit 1
    fi
    
    local command="$1"
    shift
    
    # Initialize logging
    echo "Network simulation started on $(date)" > "$LOG_FILE"
    echo "$$" > "$PID_FILE"
    
    log "Network Failure Simulation v$SCRIPT_VERSION"
    log "Command: $command"
    log "Interface: $interface"
    
    # Check prerequisites
    check_root
    check_dependencies
    
    # Execute command
    case "$command" in
        latency)
            local delay="${1:-$DEFAULT_DELAY_MS}"
            local jitter="${2:-10}"
            simulate_latency "$interface" "$delay" "$jitter"
            ;;
        packet-loss)
            local loss="${1:-$DEFAULT_LOSS_PERCENT}"
            simulate_packet_loss "$interface" "$loss"
            ;;
        bandwidth-limit)
            local bandwidth="${1:-$DEFAULT_BANDWIDTH_LIMIT}"
            simulate_bandwidth_limit "$interface" "$bandwidth"
            ;;
        corruption)
            local corrupt="${1:-$DEFAULT_CORRUPT_PERCENT}"
            simulate_packet_corruption "$interface" "$corrupt"
            ;;
        duplication)
            local duplicate="${1:-$DEFAULT_DUPLICATE_PERCENT}"
            simulate_packet_duplication "$interface" "$duplicate"
            ;;
        dns-failure)
            local dur="${1:-${duration:-60}}"
            simulate_dns_failure "$dur"
            ;;
        http-failure)
            local port="${1:-80}"
            local dur="${2:-${duration:-60}}"
            simulate_http_failure "$port" "$dur"
            ;;
        network-partition)
            local ip="${1:-8.8.8.8}"
            local dur="${2:-${duration:-30}}"
            simulate_network_partition "$ip" "$dur"
            ;;
        random-failures)
            local dur="${1:-${duration:-300}}"
            simulate_random_failures "$dur" "$interface"
            ;;
        monitor)
            local dur="${1:-${duration:-60}}"
            local interval="${2:-5}"
            monitor_network_conditions "$dur" "$interval"
            ;;
        status)
            show_network_status
            ;;
        stop)
            cleanup
            ;;
        test-poor)
            test_scenario_poor_connectivity
            ;;
        test-intermittent)
            test_scenario_intermittent_failures
            ;;
        test-outage)
            test_scenario_complete_outage
            ;;
        *)
            error "Unknown command: $command"
            show_help
            exit 1
            ;;
    esac
    
    success "Network simulation command completed"
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi