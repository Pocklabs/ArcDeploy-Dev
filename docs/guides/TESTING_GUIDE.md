# ArcDeploy Testing Guide

**Last Updated:** June 15, 2025  
**Version:** 1.0  
**Compatibility:** ArcDeploy v4.0+

---

## 📋 Overview

This comprehensive testing guide provides step-by-step procedures for validating ArcDeploy installations, running comprehensive test suites, and performing failure injection testing. The testing framework includes over 100 test scenarios with advanced failure injection capabilities.

---

## 🎯 Quick Start Testing

### Basic Validation
```bash
# Quick system validation
./scripts/validate-setup.sh

# Essential debug checks
./scripts/debug_commands.sh

# Comprehensive test suite
./tests/comprehensive-test-suite.sh --quick
```

### Test Status Check
```bash
# Check test environment
./tests/master-test-orchestrator.sh --status

# Verify all test dependencies
./tests/comprehensive-test-suite.sh --check-deps
```

---

## 🧪 Comprehensive Test Suite

### Test Categories

#### 1. SSH Key Validation (21 scenarios)
- SSH key generation and validation
- Key permissions and ownership
- Public/private key pair verification
- SSH agent functionality
- Key rotation procedures

#### 2. Cloud Provider Testing (15+ scenarios)
- Hetzner Cloud API connectivity
- AWS, GCP, Azure configuration validation
- Provider-specific template generation
- Authentication and authorization
- Resource quota validation

#### 3. Configuration Validation (25+ scenarios)
- Central configuration file validation
- Template generation accuracy
- Multi-cloud configuration consistency
- Profile-based configuration testing
- Environment variable validation

#### 4. Debug Tool Testing (30+ validations)
- Debug command availability
- Output format validation
- Performance impact assessment
- Tool version compatibility
- Error handling verification

#### 5. Network Simulation (11 failure scenarios)
- DNS resolution failures
- Port blocking simulation
- Bandwidth throttling
- Network interface failures
- Packet loss injection

#### 6. Service Resilience (11 failure scenarios)
- Service stop/start procedures
- Process termination testing
- Configuration corruption simulation
- Resource exhaustion testing
- Dependency failure handling

#### 7. System Resource Testing (9 failure scenarios)
- Memory stress testing
- CPU load simulation
- Disk I/O testing
- Storage exhaustion scenarios
- System resource monitoring

---

## 🔧 Test Execution

### Standard Test Execution

#### Run All Tests
```bash
# Complete test suite (all categories)
./tests/comprehensive-test-suite.sh

# Parallel execution (faster)
./tests/comprehensive-test-suite.sh --parallel
```

#### Category-Specific Testing
```bash
# SSH key tests only
./tests/comprehensive-test-suite.sh ssh-keys

# Debug tools validation
./tests/comprehensive-test-suite.sh debug-tools

# Configuration validation
./tests/comprehensive-test-suite.sh config

# Multiple categories
./tests/comprehensive-test-suite.sh ssh-keys config debug-tools
```

#### Quick Testing Options
```bash
# Essential tests only (5-10 minutes)
./tests/comprehensive-test-suite.sh --quick

# Smoke tests (basic functionality)
./tests/comprehensive-test-suite.sh --smoke

# Fast validation (no network tests)
./tests/comprehensive-test-suite.sh --fast
```

### Advanced Test Orchestration

#### Master Test Orchestrator
```bash
# Coordinated test execution
./tests/master-test-orchestrator.sh

# With detailed monitoring
./tests/master-test-orchestrator.sh --monitor

# Generate comprehensive report
./tests/master-test-orchestrator.sh --report
```

#### Performance Benchmarking
```bash
# System performance testing
./tests/performance-benchmark.sh

# Extended benchmarking
./tests/performance-benchmark.sh --extended

# With monitoring
./tests/performance-benchmark.sh --monitor --duration 300
```

---

## 💥 Failure Injection Testing

The failure injection framework provides 31 comprehensive failure scenarios to test system resilience and recovery capabilities.

### Network Failure Testing

#### DNS Failures
```bash
# Complete DNS failure
./tests/failure-injection/scenarios/network-failures.sh dns_complete 60

# Partial DNS failure
./tests/failure-injection/scenarios/network-failures.sh dns_partial 90

# Slow DNS resolution
./tests/failure-injection/scenarios/network-failures.sh dns_slow 120
```

#### Network Interface Failures
```bash
# Network interface down
./tests/failure-injection/scenarios/network-failures.sh interface_down 60

# Interface flapping
./tests/failure-injection/scenarios/network-failures.sh interface_flapping 180

# MTU reduction
./tests/failure-injection/scenarios/network-failures.sh mtu_reduction 90
```

#### Connectivity Issues
```bash
# Port blocking
./tests/failure-injection/scenarios/network-failures.sh port_blocking 8080 120

# Bandwidth throttling
./tests/failure-injection/scenarios/network-failures.sh bandwidth_throttling 1000 300

# Connection exhaustion
./tests/failure-injection/scenarios/network-failures.sh connection_exhaustion 60
```

### Service Failure Testing

#### Service Management
```bash
# Service stop
./tests/failure-injection/scenarios/service-failures.sh service_stop nginx 120

# Process termination
./tests/failure-injection/scenarios/service-failures.sh process_kill blocklet-server 90

# Service restart loop
./tests/failure-injection/scenarios/service-failures.sh restart_loop redis 180
```

#### Configuration Corruption
```bash
# Main configuration corruption
./tests/failure-injection/scenarios/service-failures.sh config_corruption main 60

# Service configuration corruption
./tests/failure-injection/scenarios/service-failures.sh config_corruption nginx 120

# Template corruption
./tests/failure-injection/scenarios/service-failures.sh config_corruption template 90
```

#### Resource Exhaustion
```bash
# Memory exhaustion
./tests/failure-injection/scenarios/service-failures.sh memory_exhaustion blocklet-server 180

# CPU exhaustion
./tests/failure-injection/scenarios/service-failures.sh cpu_exhaustion 120

# Disk space exhaustion
./tests/failure-injection/scenarios/service-failures.sh disk_exhaustion 300

# File descriptor exhaustion
./tests/failure-injection/scenarios/service-failures.sh fd_exhaustion 60
```

### System Resource Testing

#### Memory Testing
```bash
# Memory bomb (high intensity)
./tests/failure-injection/scenarios/system-failures.sh memory_bomb 60 high

# Memory leak simulation
./tests/failure-injection/scenarios/system-failures.sh memory_leak 300 medium

# Swap thrashing
./tests/failure-injection/scenarios/system-failures.sh swap_thrashing 120 low
```

#### CPU Testing
```bash
# CPU bomb (auto-detect cores)
./tests/failure-injection/scenarios/system-failures.sh cpu_bomb 120 auto

# Context switching storm
./tests/failure-injection/scenarios/system-failures.sh context_switching 90 high

# CPU frequency scaling
./tests/failure-injection/scenarios/system-failures.sh cpu_scaling 180 medium
```

#### I/O Testing
```bash
# I/O storm
./tests/failure-injection/scenarios/system-failures.sh io_storm 60 high

# Disk fill
./tests/failure-injection/scenarios/system-failures.sh disk_fill 300 medium

# Inode exhaustion
./tests/failure-injection/scenarios/system-failures.sh inode_exhaustion 180 low
```

---

## 🛡️ Safety and Recovery

### Safety Mechanisms

#### Resource Monitoring
- **Memory Usage:** Automatic monitoring with 95% threshold
- **CPU Load:** Continuous monitoring with 95% threshold  
- **Disk Space:** Real-time monitoring with 95% threshold
- **Process Limits:** Automatic process count monitoring

#### Emergency Stops
- **Out-of-Memory Protection:** Automatic test termination
- **Disk Full Prevention:** Pre-emptive test stopping
- **Service Crash Detection:** Immediate test halt
- **System Overload Protection:** Load-based termination

#### Protected Resources
- **Critical Services:** System-essential services protected
- **Configuration Files:** Backup before modification
- **System Directories:** Boot and system paths protected
- **Network Interfaces:** Primary interface protection

### Recovery Procedures

#### Quick Recovery
```bash
# Quick cleanup and recovery
./tests/failure-injection/recovery/emergency-recovery.sh quick

# Verify system health
./tests/failure-injection/recovery/emergency-recovery.sh --assess
```

#### Full Recovery
```bash
# Complete system recovery
./tests/failure-injection/recovery/emergency-recovery.sh full

# With configuration restoration
./tests/failure-injection/recovery/emergency-recovery.sh full --restore-config

# Comprehensive cleanup
./tests/failure-injection/recovery/emergency-recovery.sh full --deep-clean
```

#### Recovery Verification
```bash
# Verify recovery completion
./tests/failure-injection/recovery/emergency-recovery.sh --verify

# System health assessment
./tests/failure-injection/recovery/emergency-recovery.sh --health-check

# Generate recovery report
./tests/failure-injection/recovery/emergency-recovery.sh --report
```

---

## 📊 Test Reporting

### Report Generation

#### Standard Reports
```bash
# Text report (human-readable)
./tests/comprehensive-test-suite.sh --report text

# JSON report (machine-parseable)
./tests/comprehensive-test-suite.sh --report json

# HTML dashboard (interactive)
./tests/comprehensive-test-suite.sh --report html
```

#### Detailed Analysis
```bash
# Performance metrics report
./tests/performance-benchmark.sh --report

# Failure analysis report
./tests/failure-injection/failure-injection-framework.sh --analyze

# Historical comparison
./tests/master-test-orchestrator.sh --compare-history
```

### Report Locations
- **Text Reports:** `test-results/reports/`
- **JSON Data:** `test-results/json/`
- **HTML Dashboard:** `test-results/html/`
- **Performance Metrics:** `test-results/performance/`
- **Logs:** `test-results/logs/`

---

## 🔍 Verification Checklist

### ✅ Pre-Test Verification

#### System Requirements
- [ ] Minimum 4GB RAM (8GB recommended for stress tests)
- [ ] Minimum 2 CPU cores (4+ recommended) 
- [ ] 10GB free disk space for testing
- [ ] Internet connectivity for cloud provider tests
- [ ] Root/sudo access for system-level tests

#### Environment Setup
- [ ] ArcDeploy installation completed
- [ ] All services running (nginx, redis, blocklet-server)
- [ ] Test dependencies installed
- [ ] Firewall configured properly
- [ ] SSH keys generated and configured

#### Test Framework Validation
- [ ] Test scripts executable
- [ ] Mock infrastructure accessible
- [ ] Emergency recovery procedures tested
- [ ] Backup and restore capabilities verified

### ✅ Post-Test Verification

#### System Health
- [ ] All services running normally
- [ ] System resources within normal limits
- [ ] No configuration corruption
- [ ] Log files clean and accessible
- [ ] Network connectivity restored

#### Test Results
- [ ] All test categories completed
- [ ] No critical failures detected
- [ ] Recovery procedures successful
- [ ] Performance metrics within acceptable ranges
- [ ] Test reports generated successfully

---

## 🎯 Test Scenarios

### Debug Scripts Verification

#### Architecture Validation
- [x] Native Node.js installation (no containers)
- [x] Port configuration (8080/8443 instead of 8089)
- [x] Directory paths (/opt/blocklet-server)
- [x] Systemd service management
- [x] Nginx and Redis service integration

#### Debug Command Validation (30+ checks)
- [x] System information collection
- [x] Service status verification
- [x] Network connectivity testing
- [x] Configuration file validation
- [x] Log file accessibility
- [x] Resource usage monitoring
- [x] Security configuration verification
- [x] Performance metrics collection

#### Validation Script Testing (16 categories)
- [x] Node.js version validation (v16+ requirement)
- [x] Blocklet CLI verification
- [x] Port availability testing
- [x] Service configuration validation
- [x] Directory structure verification
- [x] File permissions checking
- [x] System resource validation
- [x] Network configuration testing

#### Recovery Script Testing (22 steps)
- [x] Node.js LTS installation
- [x] Blocklet CLI global installation
- [x] Service configuration restoration
- [x] System health verification
- [x] Security configuration restoration
- [x] Performance optimization
- [x] Comprehensive cleanup procedures

---

## 🚀 Performance Testing

### Benchmarking Metrics

#### System Performance
- **CPU Usage:** Average, peak, and sustained load
- **Memory Usage:** Peak consumption and leak detection
- **Disk I/O:** Read/write performance and latency
- **Network:** Throughput and connection handling

#### Application Performance
- **Service Startup Time:** All services initialization
- **Response Time:** API and web interface responsiveness
- **Throughput:** Request handling capacity
- **Resource Efficiency:** CPU/memory per operation

### Performance Targets
- **Service Startup:** < 30 seconds
- **Memory Usage:** < 2GB under normal load
- **CPU Usage:** < 50% average under normal load
- **Disk I/O:** < 80% utilization under normal load

---

## 🔧 Troubleshooting

### Common Issues

#### Test Failures
- **Permission Denied:** Ensure proper sudo/root access
- **Network Timeouts:** Check internet connectivity
- **Service Failures:** Verify all services are running
- **Resource Exhaustion:** Increase system resources

#### Recovery Issues
- **Partial Recovery:** Run full recovery procedure
- **Configuration Corruption:** Use backup restoration
- **Service Restart Failures:** Check service dependencies
- **System Instability:** Reboot and re-run tests

### Debug Procedures
```bash
# Check test environment
./tests/comprehensive-test-suite.sh --debug

# Verbose failure injection
./tests/failure-injection/failure-injection-framework.sh --verbose

# System health assessment
./scripts/debug_commands.sh --health-check
```

---

## 📞 Support and Resources

### Documentation References
- **[Main README](../../README.md)** - Project overview
- **[Debugging Guide](../DEBUGGING_GUIDE.md)** - Troubleshooting procedures
- **[Implementation Details](../IMPLEMENTATION_DETAILS.md)** - Technical specifications
- **[Security Assessment](../SECURITY_ASSESSMENT.md)** - Security documentation

### Test Framework Files
- **Test Suite:** `tests/comprehensive-test-suite.sh`
- **Failure Injection:** `tests/failure-injection/`
- **Performance Testing:** `tests/performance-benchmark.sh`
- **Debug Validation:** `tests/debug-tool-validation.sh`
- **Recovery Scripts:** `tests/failure-injection/recovery/`

### Getting Help
1. Check the troubleshooting section above
2. Review test logs in `test-results/logs/`
3. Run debug commands for system analysis
4. Check GitHub issues for known problems
5. Contact support with detailed error information

---

**Testing Status:** ✅ Comprehensive framework with 100+ scenarios  
**Failure Injection:** ✅ 31 advanced failure scenarios  
**Recovery Systems:** ✅ Automated cleanup and restoration  
**Performance Testing:** ✅ Benchmarking and monitoring tools  
**Safety Mechanisms:** ✅ Resource protection and emergency stops  

*This guide covers the complete testing framework for ArcDeploy v4.0+*