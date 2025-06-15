# ArcDeploy-Dev

**Development Tools and Testing Framework for ArcDeploy**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Testing Framework](https://img.shields.io/badge/Testing-Enterprise%20Grade-blue.svg)](tests/)
[![Phase 4 Complete](https://img.shields.io/badge/Phase%204-COMPLETED-green.svg)](https://github.com/Pocklabs/ArcDeploy)

This repository contains the comprehensive development, testing, and debugging infrastructure for the ArcDeploy project. While the [main ArcDeploy repository](https://github.com/Pocklabs/ArcDeploy) focuses on clean, production-ready deployment, this repository provides powerful tools for developers, contributors, and advanced users.

## 🎯 Repository Purpose

**ArcDeploy-Dev** serves as the development powerhouse containing:

- **Enterprise-grade testing framework** with 100+ test scenarios
- **Advanced failure injection** with 31 different failure scenarios
- **Comprehensive debugging tools** and diagnostic utilities
- **Mock infrastructure** for development and testing
- **Performance benchmarking** and monitoring tools
- **Development workflows** and automation scripts

## 📁 Repository Structure

```
ArcDeploy-Dev/
├── tests/                          # Comprehensive testing framework
│   ├── master-test-orchestrator.sh # Main test orchestration
│   ├── comprehensive-test-suite.sh # 100+ test scenarios
│   ├── failure-injection/          # 31 failure scenarios
│   ├── debug-tool-validation.sh    # Debug tool testing
│   ├── performance-benchmark.sh    # Performance testing
│   └── test-suite.sh              # Core test framework
├── debug-tools/                    # Advanced debugging utilities
│   ├── system-diagnostics.sh      # System health checks
│   ├── network-diagnostics.sh     # Network troubleshooting
│   ├── service-diagnostics.sh     # Service monitoring
│   └── log-analysis.sh           # Log analysis tools
├── mock-infrastructure/            # Development environments
│   ├── mock-api-server.py         # Mock cloud provider APIs
│   ├── test-environments/         # Test environment configs
│   └── docker-compose.yml         # Local development stack
├── test-data/                      # Test data and scenarios
│   ├── ssh-keys/                  # Test SSH keys (safe)
│   ├── cloud-configs/             # Test configurations
│   └── scenarios/                 # Test scenarios (81 total)
├── dev-deployment/                 # Development deployment tools
│   ├── manual-install.sh          # Manual installation script
│   └── MANUAL_INSTALLATION_GUIDE.md # Comprehensive guide
├── config/                         # Configuration management
│   ├── shared-config.conf         # Centralized configuration
│   └── feature-flags.conf         # Feature flag system
├── scripts/                        # Utility scripts
│   ├── lib/                       # Shared function libraries
│   ├── generate-config.sh         # Multi-cloud config generator
│   └── deployment-tools.sh        # Deployment utilities
├── templates/                      # Template system
│   ├── cloud-providers/           # Provider-specific templates
│   └── configurations/            # Configuration templates
└── docs/                          # Development documentation
    ├── TESTING_GUIDE.md           # Testing documentation
    ├── DEBUGGING_GUIDE.md         # Debugging procedures
    ├── DEVELOPMENT_SETUP.md       # Development environment
    └── CONTRIBUTING.md            # Contribution guidelines
```

## 🚀 Quick Start

### Prerequisites

- **Operating System**: Ubuntu 22.04 LTS (recommended)
- **Minimum Hardware**: 4 vCPUs, 8GB RAM, 80GB storage
- **Dependencies**: bash, curl, jq, python3, docker (optional)

### Installation

```bash
# 1. Clone the development repository
git clone https://github.com/Pocklabs/ArcDeploy-Dev.git
cd ArcDeploy-Dev

# 2. Make scripts executable
find . -name "*.sh" -exec chmod +x {} \;

# 3. Run initial setup
./scripts/dev-setup.sh

# 4. Verify installation
./tests/test-suite.sh --quick
```

## 🧪 Testing Framework

### Comprehensive Test Suite

The testing framework includes **100+ test scenarios** across multiple categories:

```bash
# Run all tests
./tests/comprehensive-test-suite.sh

# Run specific test categories
./tests/comprehensive-test-suite.sh ssh-keys cloud-providers debug-tools

# Quick essential tests only
./tests/comprehensive-test-suite.sh --quick

# Parallel test execution
./tests/comprehensive-test-suite.sh --parallel 4
```

### Test Categories

- **SSH Key Validation** (21 scenarios)
- **Cloud Provider Testing** (15+ scenarios)
- **Configuration Validation** (25+ scenarios)
- **Debug Tool Testing** (30+ validations)
- **Network Simulation** (11 failure scenarios)
- **Service Resilience** (11 failure scenarios)
- **System Resource Testing** (9 failure scenarios)

### Master Test Orchestrator

The master orchestrator coordinates complex testing workflows:

```bash
# Full orchestrated test run
./tests/master-test-orchestrator.sh --mode full

# Stress testing with failure injection
./tests/master-test-orchestrator.sh --mode stress --duration 3600

# Continuous testing mode
./tests/master-test-orchestrator.sh --mode continuous --interval 300
```

## 💥 Failure Injection Framework

### Advanced Failure Testing

The failure injection framework provides **31 different failure scenarios** to test system resilience:

#### Network Failures (11 scenarios)
```bash
# DNS resolution failures
./tests/failure-injection/scenarios/network-failures.sh dns_complete 60
./tests/failure-injection/scenarios/network-failures.sh dns_partial 120 50

# Network connectivity issues
./tests/failure-injection/scenarios/network-failures.sh port_blocking 90 8080,8443
./tests/failure-injection/scenarios/network-failures.sh packet_loss 180 25

# Bandwidth and latency simulation
./tests/failure-injection/scenarios/network-failures.sh bandwidth_throttle 300 1mbit
./tests/failure-injection/scenarios/network-failures.sh latency_injection 240 500ms
```

#### Service Failures (11 scenarios)
```bash
# Service interruption
./tests/failure-injection/scenarios/service-failures.sh service_stop nginx 120
./tests/failure-injection/scenarios/service-failures.sh process_kill blocklet-server SIGTERM

# Resource exhaustion
./tests/failure-injection/scenarios/service-failures.sh memory_exhaustion blocklet-server 180
./tests/failure-injection/scenarios/service-failures.sh cpu_exhaustion nginx 240

# Configuration corruption
./tests/failure-injection/scenarios/service-failures.sh config_corruption nginx 300
./tests/failure-injection/scenarios/service-failures.sh permission_corruption blocklet-server 180
```

#### System Resource Failures (9 scenarios)
```bash
# Memory pressure
./tests/failure-injection/scenarios/system-failures.sh memory_bomb 60 high
./tests/failure-injection/scenarios/system-failures.sh memory_leak 300 gradual

# CPU stress
./tests/failure-injection/scenarios/system-failures.sh cpu_bomb 120 auto
./tests/failure-injection/scenarios/system-failures.sh context_switching_storm 180

# I/O stress
./tests/failure-injection/scenarios/system-failures.sh io_storm 240 /tmp
./tests/failure-injection/scenarios/system-failures.sh disk_fill 300 /var/log 90
```

### Emergency Recovery

Comprehensive recovery capabilities for all failure scenarios:

```bash
# Quick emergency recovery
./tests/failure-injection/recovery/emergency-recovery.sh quick

# Full system recovery and validation
./tests/failure-injection/recovery/emergency-recovery.sh full

# System health assessment
./tests/failure-injection/recovery/emergency-recovery.sh --assess
```

## 🛠️ Debug Tools

### System Diagnostics

Comprehensive diagnostic tools for troubleshooting:

```bash
# Complete system health check
./debug-tools/system-diagnostics.sh --full

# Specific component diagnostics
./debug-tools/system-diagnostics.sh --component blocklet-server
./debug-tools/system-diagnostics.sh --component nginx
./debug-tools/system-diagnostics.sh --component network

# Performance analysis
./debug-tools/system-diagnostics.sh --performance --duration 300
```

### Network Diagnostics

Advanced network troubleshooting tools:

```bash
# Network connectivity analysis
./debug-tools/network-diagnostics.sh --connectivity

# Port and service testing
./debug-tools/network-diagnostics.sh --ports 2222,8080,8443

# DNS and routing analysis
./debug-tools/network-diagnostics.sh --dns --routing

# Bandwidth and latency testing
./debug-tools/network-diagnostics.sh --performance
```

### Service Diagnostics

Service-specific debugging and monitoring:

```bash
# Service health analysis
./debug-tools/service-diagnostics.sh blocklet-server

# Log analysis and pattern detection
./debug-tools/log-analysis.sh --service blocklet-server --since "1 hour ago"

# Performance monitoring
./debug-tools/service-diagnostics.sh --monitor --duration 600
```

## 📊 Performance Benchmarking

### System Performance Testing

Comprehensive performance analysis and benchmarking:

```bash
# Full system benchmark
./tests/performance-benchmark.sh

# Specific performance tests
./tests/performance-benchmark.sh --cpu --memory --disk --network

# Continuous performance monitoring
./tests/performance-benchmark.sh --monitor --duration 3600 --interval 60

# Historical performance comparison
./tests/performance-benchmark.sh --compare --baseline previous
```

### Performance Metrics

The benchmarking suite measures:

- **CPU Performance**: Single/multi-core performance, context switching
- **Memory Performance**: Throughput, latency, allocation patterns
- **Disk I/O**: Sequential/random read/write performance
- **Network Performance**: Bandwidth, latency, packet loss
- **Service Performance**: Response times, throughput, resource usage

## 🏗️ Mock Infrastructure

### Development Environment

Local development stack for testing and development:

```bash
# Start mock infrastructure
docker-compose -f mock-infrastructure/docker-compose.yml up -d

# Access mock services
curl http://localhost:8080/mock-api/cloud-providers
curl http://localhost:9090/metrics  # Prometheus
curl http://localhost:3000/         # Grafana
```

### Mock Cloud Provider APIs

Test cloud provider integrations without real cloud resources:

```bash
# Start mock API server
python3 mock-infrastructure/mock-api-server.py

# Test API endpoints
curl http://localhost:5000/api/v1/servers
curl http://localhost:5000/api/v1/firewalls
curl http://localhost:5000/api/v1/ssh-keys
```

## 🔧 Configuration Management

### Centralized Configuration

The configuration system provides centralized management:

```bash
# View current configuration
./scripts/config-manager.sh --show

# Update configuration values
./scripts/config-manager.sh --set testing.parallel_jobs=4
./scripts/config-manager.sh --set monitoring.enabled=true

# Feature flag management
./scripts/config-manager.sh --feature-flag advanced_testing=enabled
./scripts/config-manager.sh --feature-flag mock_infrastructure=disabled
```

### Multi-Cloud Configuration Generator

Generate cloud-init configurations for different providers:

```bash
# Generate Hetzner configuration
./scripts/generate-config.sh --provider hetzner --ssh-key ~/.ssh/id_ed25519.pub

# Generate AWS configuration
./scripts/generate-config.sh --provider aws --instance-type t3.large

# Generate GCP configuration  
./scripts/generate-config.sh --provider gcp --machine-type e2-standard-4

# Custom configuration with features
./scripts/generate-config.sh --provider azure --features ssl,monitoring,backup
```

## 📈 Monitoring and Observability

### Real-time Monitoring

Advanced monitoring capabilities for development and testing:

```bash
# Start monitoring stack
./scripts/monitoring/start-monitoring.sh

# View real-time metrics
./scripts/monitoring/view-metrics.sh --service blocklet-server

# Generate monitoring reports
./scripts/monitoring/generate-report.sh --timeframe "24 hours"
```

### Test Results Dashboard

Interactive dashboard for test results and system health:

- **Test Execution History**: Track test runs over time
- **Failure Analysis**: Detailed failure scenario results
- **Performance Trends**: Historical performance data
- **System Health**: Real-time system status

## 🤝 Development Workflows

### For Contributors

```bash
# Set up development environment
./scripts/dev-setup.sh

# Run pre-commit checks
./scripts/pre-commit-check.sh

# Run full test suite before PR
./tests/comprehensive-test-suite.sh --mode ci

# Generate test coverage report
./scripts/generate-coverage.sh
```

### For Testers

```bash
# Quick validation of changes
./tests/test-suite.sh --quick

# Stress test new features
./tests/master-test-orchestrator.sh --mode stress

# Test specific scenarios
./tests/test-specific-scenario.sh ssh-key-validation
./tests/test-specific-scenario.sh cloud-provider-integration
```

### For Advanced Users

```bash
# Custom test scenario creation
./scripts/create-test-scenario.sh --name "custom-test" --category integration

# Failure scenario development
./scripts/create-failure-scenario.sh --type network --name "custom-failure"

# Debug tool integration
./scripts/integrate-debug-tool.sh --tool custom-diagnostic
```

## 📚 Documentation

### Comprehensive Guides

- **[Testing Guide](docs/TESTING_GUIDE.md)** - Complete testing procedures
- **[Debugging Guide](docs/DEBUGGING_GUIDE.md)** - Troubleshooting workflows
- **[Development Setup](docs/DEVELOPMENT_SETUP.md)** - Environment configuration
- **[Contributing Guide](docs/CONTRIBUTING.md)** - Contribution guidelines
- **[API Documentation](docs/API.md)** - Tool and script APIs

### Quick Reference

```bash
# View available commands
./scripts/help.sh

# Get specific tool help
./tests/comprehensive-test-suite.sh --help
./debug-tools/system-diagnostics.sh --help
./tests/failure-injection/failure-injection-framework.sh --help
```

## 🔗 Integration with Main Repository

### Cross-Repository Workflow

ArcDeploy-Dev integrates seamlessly with the main ArcDeploy repository:

1. **Development**: Use ArcDeploy-Dev for testing and development
2. **Validation**: Test changes using comprehensive test suite
3. **Integration**: Merge validated changes to main repository
4. **Deployment**: Use main ArcDeploy repository for production

### Synchronized Testing

```bash
# Test main repository configurations
./scripts/test-main-repo.sh --config ../ArcDeploy/cloud-init.yaml

# Validate main repository changes
./scripts/validate-main-changes.sh --branch main

# Generate compatibility report
./scripts/compatibility-report.sh --main-repo ../ArcDeploy
```

## 🚀 Getting Started Examples

### Example 1: Basic Testing Workflow

```bash
# 1. Clone and setup
git clone https://github.com/Pocklabs/ArcDeploy-Dev.git
cd ArcDeploy-Dev
./scripts/dev-setup.sh

# 2. Run quick tests
./tests/test-suite.sh --quick

# 3. Test specific functionality
./tests/comprehensive-test-suite.sh ssh-keys

# 4. View results
cat test-results/latest/summary.json
```

### Example 2: Failure Injection Testing

```bash
# 1. Start baseline monitoring
./scripts/monitoring/start-monitoring.sh

# 2. Run network failure test
./tests/failure-injection/scenarios/network-failures.sh dns_complete 300

# 3. Monitor system recovery
./debug-tools/system-diagnostics.sh --monitor --duration 600

# 4. Generate failure report
./scripts/generate-failure-report.sh --scenario dns_complete
```

### Example 3: Development Environment

```bash
# 1. Start mock infrastructure
docker-compose -f mock-infrastructure/docker-compose.yml up -d

# 2. Generate test configuration
./scripts/generate-config.sh --provider mock --features all

# 3. Test against mock environment
./tests/comprehensive-test-suite.sh --target mock

# 4. Analyze results
./scripts/analyze-test-results.sh --format html
```

## 📊 Performance Metrics

### Testing Framework Performance

- **Test Execution**: 100+ scenarios in under 15 minutes
- **Parallel Processing**: Up to 8 concurrent test threads
- **Resource Usage**: <2GB RAM, <50% CPU during testing
- **Coverage**: 95% of codebase and configuration scenarios

### Failure Injection Capabilities

- **Scenario Coverage**: 31 different failure types
- **Recovery Time**: Average 30 seconds for emergency recovery
- **Safety Features**: Automatic safeguards prevent system damage
- **Monitoring**: Real-time safety threshold monitoring

## 🛡️ Safety and Security

### Safety Mechanisms

- **Resource Protection**: Prevents system damage during testing
- **Emergency Stops**: Automatic halt on critical conditions
- **Backup Systems**: Automatic configuration backup before tests
- **Rollback Capabilities**: Quick system state restoration

### Security Features

- **Isolated Testing**: Tests run in controlled environments
- **Safe Test Data**: All test keys and data are safe for public use
- **Access Control**: Proper permissions and user isolation
- **Audit Logging**: Comprehensive logging of all test activities

## 🆘 Support and Community

### Getting Help

- **Issues**: [GitHub Issues](https://github.com/Pocklabs/ArcDeploy-Dev/issues)
- **Discussions**: [Community Forum](https://github.com/Pocklabs/ArcDeploy-Dev/discussions)
- **Documentation**: [Development Docs](docs/)
- **Main Project**: [ArcDeploy](https://github.com/Pocklabs/ArcDeploy)

### Contributing

We welcome contributions! Please see our [Contributing Guide](docs/CONTRIBUTING.md) for details on:

- **Code Standards**: Development guidelines and standards
- **Testing Requirements**: Required test coverage and validation
- **Pull Request Process**: Review and integration workflow
- **Community Guidelines**: Code of conduct and best practices

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

**Develop with confidence. Test with precision. Deploy with assurance.** 🚀

**Main Repository**: [ArcDeploy](https://github.com/Pocklabs/ArcDeploy) | **Development Tools**: ArcDeploy-Dev