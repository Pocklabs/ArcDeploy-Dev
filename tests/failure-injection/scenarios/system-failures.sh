#!/bin/bash

# ArcDeploy System Resource Failure Injection Scenarios
# Comprehensive system resource failure simulation for testing resilience and recovery

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
readonly SYSTEM_LOG="$PROJECT_ROOT/test-results/failure-injection/system-failures.log"

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
# System Configuration
# ============================================================================
readonly MEMORY_THRESHOLD_CRITICAL="95"
readonly MEMORY_THRESHOLD_WARNING="85"
readonly CPU_THRESHOLD_CRITICAL="95"
readonly CPU_THRESHOLD_WARNING="80"
readonly DISK_THRESHOLD_CRITICAL="95"
readonly DISK_THRESHOLD_WARNING="85"

# System paths
readonly PROC_MEMINFO="/proc/meminfo"
readonly PROC_CPUINFO="/proc/cpuinfo"
readonly PROC_LOADAVG="/proc/loadavg"

# ============================================================================
# Logging Functions
# ============================================================================

log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    mkdir -p "$(dirname "$SYSTEM_LOG")"
    
    case "$level" in
        "INFO")
            echo -e "${BLUE}[INFO]${NC} $message" | tee -a "$SYSTEM_LOG"
            ;;
        "SUCCESS")
            echo -e "${GREEN}[SUCCESS]${NC} $message" | tee -a "$SYSTEM_LOG"
            ;;
        "FAILURE")
            echo -e "${RED}[FAILURE]${NC} $message" | tee -a "$SYSTEM_LOG"
            ;;
        "WARNING")
            echo -e "${YELLOW}[WARNING]${NC} $message" | tee -a "$SYSTEM_LOG"
            ;;
        "INJECT")
            echo -e "${PURPLE}[INJECT]${NC} $message" | tee -a "$SYSTEM_LOG"
            ;;
        "RECOVER")
            echo -e "${CYAN}[RECOVER]${NC} $message" | tee -a "$SYSTEM_LOG"
            ;;
    esac
}

# ============================================================================
# System Resource Monitoring
# ============================================================================

get_memory_usage() {
    local total_mem
    local available_mem
    local used_percentage
    
    total_mem=$(awk '/MemTotal:/ {print $2}' "$PROC_MEMINFO")
    available_mem=$(awk '/MemAvailable:/ {print $2}' "$PROC_MEMINFO")
    used_percentage=$(( (total_mem - available_mem) * 100 / total_mem ))
    
    echo "$used_percentage"
}

get_cpu_usage() {
    # Get 1-minute load average
    local load_avg
    local cpu_cores
    local cpu_percentage
    
    load_avg=$(awk '{print $1}' "$PROC_LOADAVG")
    cpu_cores=$(nproc)
    cpu_percentage=$(echo "scale=0; $load_avg * 100 / $cpu_cores" | bc -l 2>/dev/null || echo "0")
    
    echo "$cpu_percentage"
}

get_disk_usage() {
    local path="${1:-/}"
    local disk_percentage
    
    disk_percentage=$(df "$path" | awk 'NR==2 {print substr($5, 1, length($5)-1)}')
    echo "$disk_percentage"
}

get_swap_usage() {
    local total_swap
    local free_swap
    local used_percentage
    
    total_swap=$(awk '/SwapTotal:/ {print $2}' "$PROC_MEMINFO")
    free_swap=$(awk '/SwapFree:/ {print $2}' "$PROC_MEMINFO")
    
    if [[ "$total_swap" -eq 0 ]]; then
        echo "0"
        return
    fi
    
    used_percentage=$(( (total_swap - free_swap) * 100 / total_swap ))
    echo "$used_percentage"
}

get_io_wait() {
    local io_wait
    io_wait=$(iostat -c 1 2 2>/dev/null | tail -1 | awk '{print $4}' || echo "0")
    echo "${io_wait%.*}"  # Remove decimal part
}

# ============================================================================
# Memory Failure Scenarios
# ============================================================================

inject_memory_bomb() {
    local duration="${1:-60}"
    local intensity="${2:-high}"
    
    log "INJECT" "Starting memory bomb injection (duration: ${duration}s, intensity: $intensity)"
    
    local memory_size
    case "$intensity" in
        "low")
            memory_size="512M"
            ;;
        "medium")
            memory_size="1G"
            ;;
        "high")
            memory_size="2G"
            ;;
        "extreme")
            memory_size="4G"
            ;;
        *)
            memory_size="1G"
            ;;
    esac
    
    # Create memory pressure using multiple methods
    local pids=()
    
    # Method 1: stress-ng if available
    if command -v stress-ng >/dev/null 2>&1; then
        stress-ng --vm 2 --vm-bytes "$memory_size" --timeout "${duration}s" &
        pids+=($!)
        log "INJECT" "Started stress-ng memory bomb with $memory_size"
    fi
    
    # Method 2: Python memory allocator
    python3 -c "
import time
import gc
import signal
import sys

def signal_handler(sig, frame):
    gc.collect()
    sys.exit(0)

signal.signal(signal.SIGTERM, signal_handler)
signal.signal(signal.SIGINT, signal_handler)

memory_chunks = []
chunk_size = 1024 * 1024 * 10  # 10MB chunks
duration = $duration

start_time = time.time()
try:
    while time.time() - start_time < duration:
        try:
            chunk = b'x' * chunk_size
            memory_chunks.append(chunk)
            time.sleep(0.1)
        except MemoryError:
            time.sleep(1)
            # Keep trying to allocate
            pass
except KeyboardInterrupt:
    pass
finally:
    gc.collect()
" &
    pids+=($!)
    log "INJECT" "Started Python memory allocator"
    
    # Method 3: Shell-based memory allocation
    (
        for i in $(seq 1 100); do
            dd if=/dev/zero of="/tmp/memory_fill_$i" bs=1M count=50 2>/dev/null &
        done
        sleep "$duration"
        rm -f /tmp/memory_fill_*
    ) &
    pids+=($!)
    log "INJECT" "Started shell-based memory allocation"
    
    # Store PIDs for cleanup
    printf '%s\n' "${pids[@]}" > "/tmp/memory_bomb_pids.$$"
    
    # Monitor memory impact
    sleep 5
    local memory_usage
    memory_usage=$(get_memory_usage)
    log "INFO" "Current memory usage: $memory_usage%"
    
    if [[ $memory_usage -gt $MEMORY_THRESHOLD_WARNING ]]; then
        log "WARNING" "Memory usage exceeded warning threshold ($MEMORY_THRESHOLD_WARNING%)"
    fi
    
    return 0
}

inject_memory_leak() {
    local duration="${1:-60}"
    local leak_rate="${2:-10}"  # MB per second
    
    log "INJECT" "Starting memory leak injection (duration: ${duration}s, rate: ${leak_rate}MB/s)"
    
    # Create gradual memory leak
    python3 -c "
import time
import gc

leak_rate_mb = $leak_rate
duration = $duration
leaked_memory = []

start_time = time.time()
mb_size = 1024 * 1024

while time.time() - start_time < duration:
    try:
        # Allocate leak_rate_mb worth of memory
        for _ in range(leak_rate_mb):
            chunk = b'x' * mb_size
            leaked_memory.append(chunk)
        
        # Disable garbage collection to simulate real leak
        gc.disable()
        time.sleep(1)
        
    except MemoryError:
        print('Memory exhausted during leak simulation')
        break
    except KeyboardInterrupt:
        break

# Re-enable garbage collection for cleanup
gc.enable()
gc.collect()
" &
    
    local leak_pid=$!
    echo "$leak_pid" > "/tmp/memory_leak_pid.$$"
    log "INJECT" "Memory leak started (PID: $leak_pid)"
    
    # Monitor leak progress
    local start_memory
    start_memory=$(get_memory_usage)
    log "INFO" "Starting memory usage: $start_memory%"
    
    return 0
}

inject_swap_thrashing() {
    local duration="${1:-60}"
    local intensity="${2:-medium}"
    
    log "INJECT" "Starting swap thrashing injection (duration: ${duration}s, intensity: $intensity)"
    
    # Check if swap is available
    local total_swap
    total_swap=$(awk '/SwapTotal:/ {print $2}' "$PROC_MEMINFO")
    
    if [[ "$total_swap" -eq 0 ]]; then
        log "WARNING" "No swap space available, creating temporary swap file"
        sudo fallocate -l 1G /tmp/emergency_swap
        sudo chmod 600 /tmp/emergency_swap
        sudo mkswap /tmp/emergency_swap
        sudo swapon /tmp/emergency_swap
        log "INFO" "Created 1GB temporary swap file"
    fi
    
    # Force system to use swap by allocating more memory than available RAM
    local total_ram_kb
    total_ram_kb=$(awk '/MemTotal:/ {print $2}' "$PROC_MEMINFO")
    local target_allocation=$((total_ram_kb + 512 * 1024))  # RAM + 512MB
    
    case "$intensity" in
        "low")
            target_allocation=$((total_ram_kb + 256 * 1024))
            ;;
        "medium")
            target_allocation=$((total_ram_kb + 512 * 1024))
            ;;
        "high")
            target_allocation=$((total_ram_kb + 1024 * 1024))
            ;;
    esac
    
    python3 -c "
import time
import mmap

target_kb = $target_allocation
duration = $duration
chunk_size = 1024 * 1024  # 1MB chunks

allocated_memory = []
start_time = time.time()

try:
    allocated_kb = 0
    while allocated_kb < target_kb and time.time() - start_time < duration:
        try:
            chunk = mmap.mmap(-1, chunk_size)
            chunk.write(b'x' * chunk_size)
            allocated_memory.append(chunk)
            allocated_kb += 1024
            
            if allocated_kb % (100 * 1024) == 0:  # Every 100MB
                print(f'Allocated: {allocated_kb // 1024}MB')
            
            time.sleep(0.01)  # Small delay
        except (MemoryError, OSError):
            break
    
    # Keep memory allocated for remaining duration
    remaining_time = duration - (time.time() - start_time)
    if remaining_time > 0:
        time.sleep(remaining_time)

finally:
    # Cleanup
    for chunk in allocated_memory:
        chunk.close()
" &
    
    local thrash_pid=$!
    echo "$thrash_pid" > "/tmp/swap_thrash_pid.$$"
    log "INJECT" "Swap thrashing started (PID: $thrash_pid)"
    
    return 0
}

# ============================================================================
# CPU Failure Scenarios
# ============================================================================

inject_cpu_bomb() {
    local duration="${1:-60}"
    local cpu_count="${2:-auto}"
    
    log "INJECT" "Starting CPU bomb injection (duration: ${duration}s, CPUs: $cpu_count)"
    
    # Auto-detect CPU count
    if [[ "$cpu_count" == "auto" ]]; then
        cpu_count=$(nproc)
    fi
    
    local pids=()
    
    # Method 1: stress-ng if available
    if command -v stress-ng >/dev/null 2>&1; then
        stress-ng --cpu "$cpu_count" --timeout "${duration}s" &
        pids+=($!)
        log "INJECT" "Started stress-ng CPU bomb on $cpu_count cores"
    fi
    
    # Method 2: CPU-intensive loops
    for ((i=1; i<=cpu_count; i++)); do
        (
            end_time=$(($(date +%s) + duration))
            while [[ $(date +%s) -lt $end_time ]]; do
                # CPU-intensive operations
                for ((j=1; j<=10000; j++)); do
                    echo "scale=100; 4*a(1)" | bc -l >/dev/null 2>&1
                done
            done
        ) &
        pids+=($!)
    done
    
    log "INJECT" "Started $cpu_count CPU-intensive processes"
    
    # Method 3: Fork bomb (controlled)
    (
        bomb() {
            bomb | bomb &
        }
        
        # Start controlled fork bomb
        timeout "${duration}s" bash -c 'bomb() { bomb | bomb & }; bomb' 2>/dev/null || true
    ) &
    pids+=($!)
    
    # Store PIDs for cleanup
    printf '%s\n' "${pids[@]}" > "/tmp/cpu_bomb_pids.$$"
    
    # Monitor CPU impact
    sleep 5
    local cpu_usage
    cpu_usage=$(get_cpu_usage)
    log "INFO" "Current CPU usage: $cpu_usage%"
    
    return 0
}

inject_context_switching() {
    local duration="${1:-60}"
    local process_count="${2:-1000}"
    
    log "INJECT" "Starting context switching storm (duration: ${duration}s, processes: $process_count)"
    
    local pids=()
    
    # Create many short-lived processes that constantly yield
    for ((i=1; i<=process_count; i++)); do
        (
            end_time=$(($(date +%s) + duration))
            while [[ $(date +%s) -lt $end_time ]]; do
                sleep 0.001  # Frequent context switches
                sched_yield 2>/dev/null || true
            done
        ) &
        pids+=($!)
        
        # Small delay to prevent overwhelming system
        if [[ $((i % 100)) -eq 0 ]]; then
            sleep 0.1
            log "INFO" "Created $i/$process_count processes..."
        fi
    done
    
    # Store PIDs for cleanup
    printf '%s\n' "${pids[@]}" > "/tmp/context_switch_pids.$$"
    
    log "INJECT" "Context switching storm started with $process_count processes"
    
    return 0
}

inject_cpu_frequency_scaling() {
    local duration="${1:-60}"
    local mode="${2:-powersave}"
    
    log "INJECT" "Starting CPU frequency scaling injection (duration: ${duration}s, mode: $mode)"
    
    # Check if cpufreq is available
    if [[ ! -d "/sys/devices/system/cpu/cpu0/cpufreq" ]]; then
        log "WARNING" "CPU frequency scaling not available on this system"
        return 1
    fi
    
    # Backup current governor
    local current_governor
    current_governor=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo "unknown")
    echo "$current_governor" > "/tmp/cpu_governor_backup.$$"
    
    # Set new governor mode
    case "$mode" in
        "powersave")
            echo "powersave" | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor >/dev/null
            log "INJECT" "Set CPU governor to powersave mode"
            ;;
        "performance")
            echo "performance" | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor >/dev/null
            log "INJECT" "Set CPU governor to performance mode"
            ;;
        "userspace")
            if [[ -f "/sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq" ]]; then
                echo "userspace" | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor >/dev/null
                local min_freq
                min_freq=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq)
                echo "$min_freq" | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_setspeed >/dev/null
                log "INJECT" "Set CPU to minimum frequency: $min_freq"
            fi
            ;;
    esac
    
    return 0
}

# ============================================================================
# Disk I/O Failure Scenarios
# ============================================================================

inject_io_storm() {
    local duration="${1:-60}"
    local intensity="${2:-high}"
    local target_dir="${3:-/tmp}"
    
    log "INJECT" "Starting I/O storm injection (duration: ${duration}s, intensity: $intensity, target: $target_dir)"
    
    # Create stress directory
    local stress_dir="$target_dir/io_stress_$$"
    mkdir -p "$stress_dir"
    
    local concurrent_ops
    local file_size
    local sync_interval
    
    case "$intensity" in
        "low")
            concurrent_ops=2
            file_size="10M"
            sync_interval=5
            ;;
        "medium")
            concurrent_ops=4
            file_size="50M"
            sync_interval=2
            ;;
        "high")
            concurrent_ops=8
            file_size="100M"
            sync_interval=1
            ;;
        "extreme")
            concurrent_ops=16
            file_size="200M"
            sync_interval=0
            ;;
    esac
    
    local pids=()
    
    # Method 1: stress-ng if available
    if command -v stress-ng >/dev/null 2>&1; then
        stress-ng --io 4 --hdd 2 --hdd-bytes 1G --temp-path "$stress_dir" --timeout "${duration}s" &
        pids+=($!)
        log "INJECT" "Started stress-ng I/O storm"
    fi
    
    # Method 2: Concurrent read/write operations
    for ((i=1; i<=concurrent_ops; i++)); do
        (
            end_time=$(($(date +%s) + duration))
            file_counter=0
            while [[ $(date +%s) -lt $end_time ]]; do
                local test_file="$stress_dir/io_test_${i}_${file_counter}"
                
                # Write operation
                dd if=/dev/urandom of="$test_file" bs=1M count="${file_size%M}" 2>/dev/null
                
                # Sync if needed
                if [[ $sync_interval -gt 0 ]] && [[ $((file_counter % sync_interval)) -eq 0 ]]; then
                    sync
                fi
                
                # Read operation
                dd if="$test_file" of=/dev/null bs=1M 2>/dev/null
                
                # Delete file
                rm -f "$test_file"
                
                ((file_counter++))
            done
        ) &
        pids+=($!)
    done
    
    # Method 3: Random I/O pattern
    (
        end_time=$(($(date +%s) + duration))
        while [[ $(date +%s) -lt $end_time ]]; do
            # Random seeks and writes
            dd if=/dev/urandom of="$stress_dir/random_io" bs=4K count=1 seek=$((RANDOM % 10000)) conv=notrunc 2>/dev/null
            
            # Random reads
            dd if="$stress_dir/random_io" of=/dev/null bs=4K count=1 skip=$((RANDOM % 1000)) 2>/dev/null
            
            sleep 0.01
        done
        rm -f "$stress_dir/random_io"
    ) &
    pids+=($!)
    
    # Store PIDs and stress directory for cleanup
    printf '%s\n' "${pids[@]}" > "/tmp/io_storm_pids.$$"
    echo "$stress_dir" > "/tmp/io_storm_dir.$$"
    
    log "INJECT" "I/O storm started with $concurrent_ops concurrent operations"
    
    return 0
}

inject_disk_fill() {
    local duration="${1:-60}"
    local target_dir="${2:-/tmp}"
    local fill_percentage="${3:-90}"
    
    log "INJECT" "Starting disk fill injection (duration: ${duration}s, target: $target_dir, fill: $fill_percentage%)"
    
    # Get available space
    local available_space_kb
    available_space_kb=$(df "$target_dir" | awk 'NR==2 {print $4}')
    
    # Calculate fill size
    local fill_size_kb=$((available_space_kb * fill_percentage / 100))
    local fill_file="$target_dir/disk_fill_test.$$"
    
    # Create fill file
    log "INFO" "Creating ${fill_size_kb}KB fill file..."
    dd if=/dev/zero of="$fill_file" bs=1K count="$fill_size_kb" 2>/dev/null &
    
    local fill_pid=$!
    echo "$fill_pid" > "/tmp/disk_fill_pid.$$"
    echo "$fill_file" > "/tmp/disk_fill_file.$$"
    
    # Monitor disk usage
    sleep 5
    local disk_usage
    disk_usage=$(get_disk_usage "$target_dir")
    log "INFO" "Current disk usage for $target_dir: $disk_usage%"
    
    if [[ $disk_usage -gt $DISK_THRESHOLD_WARNING ]]; then
        log "WARNING" "Disk usage exceeded warning threshold ($DISK_THRESHOLD_WARNING%)"
    fi
    
    return 0
}

inject_inode_exhaustion() {
    local duration="${1:-60}"
    local target_dir="${2:-/tmp}"
    
    log "INJECT" "Starting inode exhaustion injection (duration: ${duration}s, target: $target_dir)"
    
    # Create directory for inode exhaustion
    local inode_dir="$target_dir/inode_exhaustion_$$"
    mkdir -p "$inode_dir"
    
    # Get current inode usage
    local total_inodes
    local used_inodes
    total_inodes=$(df -i "$target_dir" | awk 'NR==2 {print $2}')
    used_inodes=$(df -i "$target_dir" | awk 'NR==2 {print $3}')
    local available_inodes=$((total_inodes - used_inodes))
    
    log "INFO" "Available inodes: $available_inodes"
    
    # Create many small files to exhaust inodes
    local target_files=$((available_inodes * 80 / 100))  # Use 80% of available inodes
    
    (
        for ((i=1; i<=target_files; i++)); do
            touch "$inode_dir/inode_file_$i" 2>/dev/null || break
            
            if [[ $((i % 10000)) -eq 0 ]]; then
                echo "Created $i files..."
            fi
        done
        
        sleep "$duration"
    ) &
    
    local inode_pid=$!
    echo "$inode_pid" > "/tmp/inode_exhaustion_pid.$$"
    echo "$inode_dir" > "/tmp/inode_exhaustion_dir.$$"
    
    log "INJECT" "Inode exhaustion started, targeting $target_files files"
    
    return 0
}

# ============================================================================
# Recovery Functions
# ============================================================================

recover_memory_bomb() {
    log "RECOVER" "Recovering from memory bomb injection"
    
    # Kill memory bomb processes
    if [[ -f "/tmp/memory_bomb_pids.$$" ]]; then
        while read -r pid; do
            kill -TERM "$pid" 2>/dev/null || true
            sleep 1
            kill -KILL "$pid" 2>/dev/null || true
        done < "/tmp/memory_bomb_pids.$$"
        rm -f "/tmp/memory_bomb_pids.$$"
        log "RECOVER" "Terminated memory bomb processes"
    fi
    
    # Clean up memory fill files
    rm -f /tmp/memory_fill_* 2>/dev/null || true
    
    # Force garbage collection
    echo 3 | sudo tee /proc/sys/vm/drop_caches >/dev/null 2>&1 || true
    
    # Wait and check memory usage
    sleep 5
    local memory_usage
    memory_usage=$(get_memory_usage)
    log "INFO" "Post-recovery memory usage: $memory_usage%"
    
    if [[ $memory_usage -lt $MEMORY_THRESHOLD_WARNING ]]; then
        log "SUCCESS" "Memory usage recovered successfully"
        return 0
    else
        log "WARNING" "Memory usage still elevated after recovery"
        return 1
    fi
}

recover_memory_leak() {
    log "RECOVER" "Recovering from memory leak injection"
    
    # Kill memory leak process
    if [[ -f "/tmp/memory_leak_pid.$$" ]]; then
        local leak_pid
        leak_pid=$(cat "/tmp/memory_leak_pid.$$")
        kill -TERM "$leak_pid" 2>/dev/null || true
        sleep 2
        kill -KILL "$leak_pid" 2>/dev/null || true
        rm -f "/tmp/memory_leak_pid.$$"
        log "RECOVER" "Terminated memory leak process"
    fi
    
    # Force garbage collection and cache drop
    echo 3 | sudo tee /proc/sys/vm/drop_caches >/dev/null 2>&1 || true
    
    # Wait and check memory usage
    sleep 5
    local memory_usage
    memory_usage=$(get_memory_usage)
    log "INFO" "Post-recovery memory usage: $memory_usage%"
    
    return 0
}

recover_swap_thrashing() {
    log "RECOVER" "Recovering from swap thrashing injection"
    
    # Kill swap thrashing process
    if [[ -f "/tmp/swap_thrash_pid.$$" ]]; then
        local thrash_pid
        thrash_pid=$(cat "/tmp/swap_thrash_pid.$$")
        kill -TERM "$thrash_pid" 2>/dev/null || true
        sleep 2
        kill -KILL "$thrash_pid" 2>/dev/null || true
        rm -f "/tmp/swap_thrash_pid.$$"
        log "RECOVER" "Terminated swap thrashing process"
    fi
    
    # Remove temporary swap if created
    if [[ -f "/tmp/emergency_swap" ]]; then
        sudo swapoff /tmp/emergency_swap 2>/dev/null || true
        sudo rm -f /tmp/emergency_swap
        log "RECOVER" "Removed temporary swap file"
    fi
    
    # Clear swap
    if [[ $(get_swap_usage) -gt 10 ]]; then
        sudo swapoff -a && sudo swapon -a 2>/dev/null || true
        log "RECOVER" "Cleared swap space"
    fi
    
    return 0
}

recover_cpu_bomb() {
    log "RECOVER" "Recovering from CPU bomb injection"
    
    # Kill CPU bomb processes
    if [[ -f "/tmp/cpu_bomb_pids.$$" ]]; then
        while read -r pid; do
            kill -TERM "$pid" 2>/dev/null || true
            sleep 1
            kill -KILL "$pid" 2>/dev/null || true
        done < "/tmp/cpu_bomb_pids.$$"
        rm -f "/tmp/cpu_bomb_pids.$$"
        log "RECOVER" "Terminated CPU bomb processes"
    fi
    
    # Kill any remaining high-CPU processes
    pkill -f "stress-ng" 2>/dev/null || true
    
    # Wait and check CPU usage
    sleep 10
    local cpu_usage
    cpu_usage=$(get_cpu_usage)
    log "INFO" "Post-recovery CPU usage: $cpu_usage%"
    
    if [[ $cpu_usage -lt $CPU_THRESHOLD_WARNING ]]; then
        log "SUCCESS" "CPU usage recovered successfully"
        return 0
    else
        log "WARNING" "CPU usage still elevated after recovery"
        return 1
    fi
}

recover_context_switching() {
    log "RECOVER" "Recovering from context switching storm"
    
    # Kill context switching processes
    if [[ -f "/tmp/context_switch_pids.$$" ]]; then
        while read -r pid; do
            kill -TERM "$pid" 2>/dev/null || true
        done < "/tmp/context_switch_pids.$$"
        
        # Give processes time to terminate gracefully
        sleep 3
        
        # Force kill any remaining processes
        while read -r pid; do
            kill -KILL "$pid" 2>/dev/null || true
        done < "/tmp/context_switch_pids.$$"
        
        rm -f "/tmp/context_switch_pids.$$"
        log "RECOVER" "Terminated context switching processes"
    fi
    
    return 0
}

recover_cpu_frequency_scaling() {
    log "RECOVER" "Recovering CPU frequency scaling"
    
    # Restore original governor
    if [[ -f "/tmp/cpu_governor_backup.$$" ]]; then
        local original_governor
        original_governor=$(cat "/tmp/cpu_governor_backup.$$")
        
        if [[ "$original_governor" != "unknown" ]]; then
            echo "$original_governor" | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor >/dev/null 2>&1 || true
            log "RECOVER" "Restored CPU governor to: $original_governor"
        fi
        
        rm -f "/tmp/cpu_governor_backup.$$"
    fi
    
    return 0
}

recover_io_storm() {
    log "RECOVER" "Recovering from I/O storm injection"
    
    # Kill I/O storm processes
    if [[ -f "/tmp/io_storm_pids.$$" ]]; then
        while read -r pid; do
            kill -TERM "$pid" 2>/dev/null || true
            sleep 1
            kill -KILL "$pid" 2>/dev/null || true
        done < "/tmp/io_storm_pids.$$"
        rm -f "/tmp/io_storm_pids.$$"
        log "RECOVER" "Terminated I/O storm processes"
    fi
    
    # Clean up stress directory
    if [[ -f "/tmp/io_storm_dir.$$" ]]; then
        local stress_dir
        stress_dir=$(cat "/tmp/io_storm_dir.$$")
        rm -rf "$stress_dir"
        rm -f "/tmp/io_storm_dir.$$"
        log "RECOVER" "Cleaned up I/O stress directory: $stress_dir"
    fi
    
    # Kill any remaining stress-ng processes
    pkill -f "stress-ng.*io" 2>/dev/null || true
    
    return 0
}

recover_disk_fill() {
    log "RECOVER" "Recovering from disk fill injection"
    
    # Kill disk fill process
    if [[ -f "/tmp/disk_fill_pid.$$" ]]; then
        local fill_pid
        fill_pid=$(cat "/tmp/disk_fill_pid.$$")
        kill -TERM "$fill_pid" 2>/dev/null || true
        sleep 2
        kill -KILL "$fill_pid" 2>/dev/null || true
        rm -f "/tmp/disk_fill_pid.$$"
        log "RECOVER" "Terminated disk fill process"
    fi
    
    # Remove fill file
    if [[ -f "/tmp/disk_fill_file.$$" ]]; then
        local fill_file
        fill_file=$(cat "/tmp/disk_fill_file.$$")
        rm -f "$fill_file" "/tmp/disk_fill_file.$$"
        log "RECOVER" "Removed disk fill file: $fill_file"
    fi
    
    return 0
}

recover_inode_exhaustion() {
    log "RECOVER" "Recovering from inode exhaustion injection"
    
    # Kill inode exhaustion process
    if [[ -f "/tmp/inode_exhaustion_pid.$$" ]]; then
        local inode_pid
        inode_pid=$(cat "/tmp/inode_exhaustion_pid.$$")
        kill -TERM "$inode_pid" 2>/dev/null || true
        sleep 2
        kill -KILL "$inode_pid" 2>/dev/null || true
        rm -f "/tmp/inode_exhaustion_pid.$$"
        log "RECOVER" "Terminated inode exhaustion process"
    fi
    
    # Remove inode exhaustion directory
    if [[ -f "/tmp/inode_exhaustion_dir.$$" ]]; then
        local inode_dir
        inode_dir=$(cat "/tmp/inode_exhaustion_dir.$$")
        rm -rf "$inode_dir"
        rm -f "/tmp/inode_exhaustion_dir.$$"
        log "RECOVER" "Removed inode exhaustion directory: $inode_dir"
    fi
    
    return 0
}

# ============================================================================
# Main Functions
# ============================================================================

run_system_failure_scenario() {
    local scenario="$1"
    local duration="${2:-60}"
    local params="${3:-}"
    
    log "INFO" "Running system failure scenario: $scenario"
    
    case "$scenario" in
        "memory_bomb")
            inject_memory_bomb "$duration" "${params:-high}"
            ;;
        "memory_leak")
            inject_memory_leak "$duration" "${params:-10}"
            ;;
        "swap_thrashing")
            inject_swap_thrashing "$duration" "${params:-medium}"
            ;;
        "cpu_bomb")
            inject_cpu_bomb "$duration" "${params:-auto}"
            ;;
        "context_switching")
            inject_context_switching "$duration" "${params:-1000}"
            ;;
        "cpu_frequency_scaling")
            inject_cpu_frequency_scaling "$duration" "${params:-powersave}"
            ;;
        "io_storm")
            inject_io_storm "$duration" "${params:-high}" "/tmp"
            ;;
        "disk_fill")
            inject_disk_fill "$duration" "/tmp" "${params:-90}"
            ;;
        "inode_exhaustion")
            inject_inode_exhaustion "$duration" "/tmp"
            ;;
        *)
            log "FAILURE" "Unknown system failure scenario: $scenario"
            return 1
            ;;
    esac
}

recover_system_failure_scenario() {
    local scenario="$1"
    
    log "INFO" "Recovering from system failure scenario: $scenario"
    
    case "$scenario" in
        "memory_bomb")
            recover_memory_bomb
            ;;
        "memory_leak")
            recover_memory_leak
            ;;
        "swap_thrashing")
            recover_swap_thrashing
            ;;
        "cpu_bomb")
            recover_cpu_bomb
            ;;
        "context_switching")
            recover_context_switching
            ;;
        "cpu_frequency_scaling")
            recover_cpu_frequency_scaling
            ;;
        "io_storm")
            recover_io_storm
            ;;
        "disk_fill")
            recover_disk_fill
            ;;
        "inode_exhaustion")
            recover_inode_exhaustion
            ;;
        *)
            log "WARNING" "No specific recovery procedure for scenario: $scenario"
            # Generic cleanup
            recover_memory_bomb 2>/dev/null || true
            recover_memory_leak 2>/dev/null || true
            recover_swap_thrashing 2>/dev/null || true
            recover_cpu_bomb 2>/dev/null || true
            recover_context_switching 2>/dev/null || true
            recover_cpu_frequency_scaling 2>/dev/null || true
            recover_io_storm 2>/dev/null || true
            recover_disk_fill 2>/dev/null || true
            recover_inode_exhaustion 2>/dev/null || true
            ;;
    esac
}

# ============================================================================
# Usage and Help
# ============================================================================

show_usage() {
    cat << EOF
ArcDeploy System Resource Failure Injection Scenarios

Usage: $SCRIPT_NAME [OPTION]... SCENARIO [DURATION] [PARAMS]

SCENARIOS:
  memory_bomb           Exhaust system memory (params: intensity)
  memory_leak           Gradual memory leak (params: rate_mb_per_sec)
  swap_thrashing        Force swap usage (params: intensity)
  cpu_bomb              Exhaust CPU resources (params: cpu_count)
  context_switching     Context switching storm (params: process_count)
  cpu_frequency_scaling CPU frequency scaling (params: mode)
  io_storm              Intensive disk I/O (params: intensity)
  disk_fill             Fill disk space (params: percentage)
  inode_exhaustion      Exhaust filesystem inodes

INTENSITIES:
  low, medium, high, extreme

CPU FREQUENCY MODES:
  powersave, performance, userspace

OPTIONS:
  -r, --recover SCENARIO    Recover from specific scenario
  -l, --list               List all available scenarios
  -m, --monitor            Show current system resource usage
  -h, --help               Show this help message
  -v, --version            Show script version

EXAMPLES:
  $SCRIPT_NAME memory_bomb 60 high
  $SCRIPT_NAME cpu_bomb 120 4
  $SCRIPT_NAME io_storm 90 medium
  $SCRIPT_NAME disk_fill 60 85
  $SCRIPT_NAME --recover memory_bomb
  $SCRIPT_NAME --monitor

DURATION: Time in seconds (default: 60)
PARAMS: Scenario-specific parameters

EOF
}

show_system_monitor() {
    log "INFO" "Current system resource usage:"
    
    local memory_usage
    memory_usage=$(get_memory_usage)
    echo "Memory Usage: $memory_usage%"
    
    local cpu_usage
    cpu_usage=$(get_cpu_usage)
    echo "CPU Usage: $cpu_usage%"
    
    local disk_usage
    disk_usage=$(get_disk_usage "/")
    echo "Root Disk Usage: $disk_usage%"
    
    local swap_usage
    swap_usage=$(get_swap_usage)
    echo "Swap Usage: $swap_usage%"
    
    if command -v iostat >/dev/null 2>&1; then
        local io_wait
        io_wait=$(get_io_wait)
        echo "I/O Wait: $io_wait%"
    fi
    
    echo ""
    echo "Load Average: $(cat /proc/loadavg | cut -d' ' -f1-3)"
    echo "CPU Cores: $(nproc)"
    echo "Total Memory: $(awk '/MemTotal:/ {printf "%.1f GB", $2/1024/1024}' /proc/meminfo)"
    echo "Available Memory: $(awk '/MemAvailable:/ {printf "%.1f GB", $2/1024/1024}' /proc/meminfo)"
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
            echo "Available system failure scenarios:"
            echo "  Memory: memory_bomb, memory_leak, swap_thrashing"
            echo "  CPU: cpu_bomb, context_switching, cpu_frequency_scaling"
            echo "  Disk I/O: io_storm, disk_fill, inode_exhaustion"
            exit 0
            ;;
        -m|--monitor)
            show_system_monitor
            exit 0
            ;;
        -r|--recover)
            if [[ $# -lt 2 ]]; then
                echo "Error: Scenario name required for recovery"
                exit 1
            fi
            recover_system_failure_scenario "$2"
            exit $?
            ;;
        *)
            scenario="$1"
            duration="${2:-60}"
            params="${3:-}"
            
            run_system_failure_scenario "$scenario" "$duration" "$params"
            exit $?
            ;;
    esac
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
