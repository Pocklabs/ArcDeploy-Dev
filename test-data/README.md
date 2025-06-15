# ArcDeploy Test Data

This directory contains test data for validating ArcDeploy functionality across various scenarios.

## Directory Structure

```
test-data/
├── ssh-keys/                    # SSH key test data
│   ├── valid/                   # Valid SSH keys
│   ├── invalid/                 # Invalid SSH keys (negative testing)
│   └── edge-cases/              # Boundary condition testing
├── configurations/              # Configuration test files
│   ├── valid/                   # Valid configuration files
│   ├── invalid/                 # Invalid configurations
│   └── edge-cases/              # Edge case configurations
├── cloud-providers/             # Mock cloud provider data
│   └── hetzner/                 # Hetzner Cloud mock responses
└── environments/                # System environment simulations
```

## Usage

### SSH Key Testing
```bash
# Test SSH key validation
./tests/comprehensive-test-suite.sh ssh-keys

# Manual validation
ssh-keygen -l -f test-data/ssh-keys/valid/ed25519-standard.pub
```

### Configuration Testing
```bash
# Test configuration validation
./tests/comprehensive-test-suite.sh configurations

# Validate specific config
bash -n test-data/configurations/valid/standard.conf
```

### Mock API Testing
```bash
# Start mock API server
python3 mock-infrastructure/mock-api-server.py &

# Test API responses
curl http://127.0.0.1:8888/hetzner/servers
```

## Test Categories

| Category | Valid Cases | Invalid Cases | Edge Cases |
|----------|-------------|---------------|------------|
| SSH Keys | 4 | 3 | 3 |
| Configurations | 4 | 4 | 4 |
| Cloud Providers | 8 | 6 | 4 |
| Environments | 12 | 8 | 6 |

## Integration

Test data is automatically used by:
- `./tests/comprehensive-test-suite.sh` - Main test runner
- `./tests/debug-tool-validation.sh` - Debug tool testing
- Mock infrastructure for API simulation

## Adding Test Data

1. Create test file in appropriate directory
2. Follow naming convention: `descriptive-name.ext`
3. Add to relevant test suite if needed
4. Document purpose and expected behavior

## Validation

```bash
# Validate all SSH keys
for key in test-data/ssh-keys/valid/*.pub; do
    ssh-keygen -l -f "$key" || echo "Invalid: $key"
done

# Validate JSON files
find test-data -name "*.json" -exec jq empty {} \;

# Validate configuration syntax
find test-data/configurations/valid -name "*.conf" -exec bash -n {} \;
```

---

**Note**: This test data is for development and testing only. All data contains dummy/mock information.