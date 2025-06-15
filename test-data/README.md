# ArcDeploy Test Data Documentation

This directory contains comprehensive test data for validating ArcDeploy functionality across various scenarios, including edge cases, failure conditions, and performance testing.

## 📁 Directory Structure

```
test-data/
├── ssh-keys/                    # SSH key test data
│   ├── valid/                   # Valid SSH keys for testing
│   ├── invalid/                 # Invalid SSH keys for validation testing
│   └── edge-cases/              # Edge case SSH keys
├── cloud-providers/             # Cloud provider mock data
│   ├── hetzner/                 # Hetzner Cloud specific test data
│   │   └── api-responses/       # Mock API response files
│   ├── aws/                     # AWS specific test data
│   ├── gcp/                     # Google Cloud specific test data
│   └── azure/                   # Azure specific test data
├── configurations/              # Configuration test files
│   ├── valid/                   # Valid configuration files
│   ├── invalid/                 # Invalid configuration files
│   └── edge-cases/              # Edge case configurations
├── environments/                # System environment simulations
│   ├── ubuntu-versions/         # Different Ubuntu version scenarios
│   ├── resource-constraints/    # Resource limitation scenarios
│   └── failure-scenarios/       # System failure simulations
└── README.md                    # This file
```

## 🔑 SSH Key Test Data

### Valid SSH Keys (`ssh-keys/valid/`)

These SSH keys represent properly formatted keys that should pass validation:

| File | Key Type | Description |
|------|----------|-------------|
| `ed25519-standard.pub` | ED25519 | Standard ED25519 key with basic comment |
| `ed25519-with-comment.pub` | ED25519 | ED25519 key with detailed comment |
| `rsa-4096.pub` | RSA-4096 | 4096-bit RSA key for compatibility testing |
| `ecdsa-256.pub` | ECDSA-256 | ECDSA key with NIST P-256 curve |

**Usage Example:**
```bash
# Test SSH key validation
./tests/comprehensive-test-suite.sh ssh-keys

# Manual validation test
ssh-keygen -l -f test-data/ssh-keys/valid/ed25519-standard.pub
```

### Invalid SSH Keys (`ssh-keys/invalid/`)

These files contain malformed or invalid SSH keys for negative testing:

| File | Issue | Expected Behavior |
|------|--------|------------------|
| `malformed-key.pub` | Corrupted base64 encoding | Should reject with parse error |
| `wrong-format.pub` | Multiple format violations | Should reject with format error |
| `missing-type.pub` | Missing key type prefix | Should reject with type error |

**Test Purpose:** Ensure validation functions properly reject invalid keys without crashing.

### Edge Case SSH Keys (`ssh-keys/edge-cases/`)

These files test boundary conditions and unusual but valid scenarios:

| File | Scenario | Expected Behavior |
|------|----------|------------------|
| `very-long-comment.pub` | Extremely long comment field | Should handle gracefully |
| `no-comment.pub` | SSH key without comment | Should accept as valid |
| `unicode-comment.pub` | Unicode characters in comment | Should handle encoding properly |

## ☁️ Cloud Provider Test Data

### Hetzner Cloud (`cloud-providers/hetzner/`)

Mock API responses for comprehensive Hetzner Cloud testing:

#### Success Scenarios
- `success-create-server.json` - Successful server creation response
- `success-list-servers.json` - Server listing response
- `success-server-status.json` - Server status check response

#### Error Scenarios
- `rate-limit-exceeded.json` - API rate limiting response (HTTP 429)
- `quota-exceeded.json` - Resource quota exceeded (HTTP 422)
- `auth-failed.json` - Authentication failure (HTTP 401)
- `network-error.json` - Network connectivity issues

**Usage with Mock API Server:**
```bash
# Start mock API server
python3 mock-infrastructure/mock-api-server.py &

# Test successful server creation
curl http://127.0.0.1:8888/hetzner/servers

# Test rate limiting scenario
curl http://127.0.0.1:8888/hetzner/servers?scenario=rate-limit-exceeded

# Test quota exceeded scenario  
curl http://127.0.0.1:8888/hetzner/servers?scenario=quota-exceeded
```

#### Response Structure
All mock responses follow this structure:
```json
{
  "server|error": { ... },          // Main response data
  "meta": {                         // Metadata
    "request_id": "req_...",
    "timestamp": "2024-01-15T10:30:00+00:00",
    "api_version": "v1"
  },
  "status_code": 200|4xx|5xx        // HTTP status code
}
```

### Other Cloud Providers

**AWS (`cloud-providers/aws/`)**
- EC2 instance creation responses
- IAM role and policy responses
- CloudWatch monitoring data

**Google Cloud (`cloud-providers/gcp/`)**
- Compute Engine instance responses
- Cloud Operations monitoring
- Service account configurations

**Azure (`cloud-providers/azure/`)**
- Virtual Machine creation responses
- Resource group configurations
- Monitor agent responses

## ⚙️ Configuration Test Data

### Valid Configurations (`configurations/valid/`)

Well-formed configuration files for positive testing:

| File | Description | Key Features |
|------|-------------|--------------|
| `standard.conf` | Basic valid configuration | Standard deployment settings |
| `minimal.conf` | Minimal required settings | Only essential parameters |
| `full-featured.conf` | Complete configuration | All available options |
| `production.conf` | Production-ready settings | Security-hardened configuration |

### Invalid Configurations (`configurations/invalid/`)

Malformed configuration files for validation testing:

| File | Issue | Test Purpose |
|------|--------|--------------|
| `syntax-error.conf` | Shell syntax errors | Test error handling |
| `missing-required.conf` | Missing required fields | Test validation logic |
| `conflicting-values.conf` | Contradictory settings | Test conflict detection |
| `out-of-range.conf` | Invalid port/range values | Test boundary validation |

### Edge Case Configurations (`configurations/edge-cases/`)

Boundary condition and unusual configuration scenarios:

| File | Scenario | Purpose |
|------|----------|---------|
| `unicode-values.conf` | Unicode characters in values | Test encoding handling |
| `very-long-strings.conf` | Extremely long configuration values | Test memory limits |
| `special-characters.conf` | Special shell characters | Test escaping/sanitization |
| `empty-values.conf` | Empty configuration values | Test default handling |

## 🖥️ Environment Test Data

### Ubuntu Versions (`environments/ubuntu-versions/`)

System environment simulations for different Ubuntu releases:

- `20.04-minimal/` - Ubuntu 20.04 LTS minimal installation
- `22.04-standard/` - Ubuntu 22.04 LTS standard installation  
- `22.04-full/` - Ubuntu 22.04 LTS with additional packages
- `24.04-preview/` - Ubuntu 24.04 LTS preview/beta

### Resource Constraints (`environments/resource-constraints/`)

Simulated resource-limited environments:

- `low-memory-1gb/` - 1GB RAM constraint simulation
- `low-disk-10gb/` - 10GB disk space limitation
- `slow-cpu-1core/` - Single-core CPU constraint
- `network-limited/` - Bandwidth-limited network

### Failure Scenarios (`environments/failure-scenarios/`)

System failure condition simulations:

- `disk-full/` - Disk space exhaustion scenarios
- `network-down/` - Network connectivity failures
- `dns-failure/` - DNS resolution failures
- `package-repo-unavailable/` - Package repository issues

## 🧪 Testing Framework Integration

### Automated Testing

The test data is automatically used by:

```bash
# Comprehensive test suite
./tests/comprehensive-test-suite.sh

# Specific category testing
./tests/comprehensive-test-suite.sh ssh-keys
./tests/comprehensive-test-suite.sh cloud-providers
./tests/comprehensive-test-suite.sh configurations

# Performance testing
./tests/comprehensive-test-suite.sh --performance-only

# Debug tool testing
./tests/comprehensive-test-suite.sh debug-tools
```

### Mock Infrastructure Integration

Test data works with mock infrastructure:

```bash
# Start mock API server with test data
python3 mock-infrastructure/mock-api-server.py --test-data-dir test-data

# Network failure simulation
sudo mock-infrastructure/network-failure-sim.sh random-failures 300

# System diagnostics with test data
debug-tools/system-diagnostics.sh --full --json
```

## 📊 Test Data Metrics

### Coverage Statistics

| Category | Valid Cases | Invalid Cases | Edge Cases | Total |
|----------|-------------|---------------|------------|-------|
| SSH Keys | 4 | 3 | 3 | 10 |
| Cloud Providers | 8 | 6 | 4 | 18 |
| Configurations | 4 | 4 | 4 | 12 |
| Environments | 12 | 8 | 6 | 26 |
| **Total** | **28** | **21** | **17** | **66** |

### Test Scenarios

- **Positive Tests:** 28 scenarios (42.4%)
- **Negative Tests:** 21 scenarios (31.8%)
- **Edge Cases:** 17 scenarios (25.8%)
- **Performance Tests:** Integrated across all categories

## 🔧 Maintenance and Updates

### Adding New Test Data

1. **Create the test file** in the appropriate directory
2. **Update this README** with file description
3. **Add to test suite** if automated testing is needed
4. **Verify integration** with existing tests

### Test Data Validation

```bash
# Validate SSH key test data
for key in test-data/ssh-keys/valid/*.pub; do
    ssh-keygen -l -f "$key" || echo "Invalid: $key"
done

# Validate JSON structure
for json in test-data/cloud-providers/*/api-responses/*.json; do
    jq empty "$json" || echo "Invalid JSON: $json"
done

# Validate configuration syntax
for conf in test-data/configurations/valid/*.conf; do
    bash -n "$conf" || echo "Invalid syntax: $conf"
done
```

### Performance Considerations

- **File Sizes:** Keep test files under 1MB each
- **Load Times:** Optimize for fast test execution
- **Memory Usage:** Consider memory constraints during testing
- **Cleanup:** Automatic cleanup of temporary test data

## 🚀 Best Practices

### Creating New Test Data

1. **Follow naming conventions**: Use descriptive, lowercase filenames with hyphens
2. **Include metadata**: Add comments explaining the test purpose
3. **Test realistic scenarios**: Base test data on real-world conditions
4. **Document edge cases**: Clearly explain boundary conditions
5. **Maintain consistency**: Follow established patterns and formats

### Using Test Data in Scripts

```bash
# Source test data location
readonly TEST_DATA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../test-data" && pwd)"

# Check if test data exists
if [[ ! -d "$TEST_DATA_DIR" ]]; then
    echo "Test data directory not found: $TEST_DATA_DIR"
    exit 1
fi

# Use specific test files
local ssh_key="$TEST_DATA_DIR/ssh-keys/valid/ed25519-standard.pub"
local config="$TEST_DATA_DIR/configurations/valid/standard.conf"

# Validate before use
if [[ -f "$ssh_key" ]] && [[ -f "$config" ]]; then
    # Proceed with testing
    run_test_with_data "$ssh_key" "$config"
fi
```

## 📞 Support and Troubleshooting

### Common Issues

**Issue:** Test data files not found
**Solution:** Ensure you're on the `dev-deployment` branch and test data exists

**Issue:** Mock API responses not working
**Solution:** Verify JSON syntax and check mock server logs

**Issue:** Configuration validation failures
**Solution:** Check for shell syntax errors and required fields

### Getting Help

- Check test suite logs in `test-results/comprehensive-logs/`
- Review failure details in `test-results/comprehensive-logs/failures.log`
- Run tests with verbose mode: `--verbose` flag
- Examine specific test data files for format examples

### Contributing Test Data

1. **Fork the repository**
2. **Create test data** following established patterns
3. **Add documentation** explaining the test scenario
4. **Update test suite** to use new test data
5. **Submit pull request** with clear description

---

## 📄 License

This test data is part of the ArcDeploy project and is licensed under the MIT License. Test data files are provided for development and testing purposes only.

## 🔄 Version History

- **v1.0.0** - Initial comprehensive test data framework
- **v1.1.0** - Added cloud provider mock responses
- **v1.2.0** - Enhanced edge case coverage
- **v2.0.0** - Integrated with comprehensive test suite

---

**Note:** This test data is designed for the `dev-deployment` branch testing framework and is not intended for production use. All test data contains dummy/mock information only.