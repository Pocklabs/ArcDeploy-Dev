# ArcDeploy Troubleshooting Guide

Complete troubleshooting guide for ArcDeploy's native Blocklet Server deployment issues and ArcDeploy-Dev testing framework.

## 🚨 Emergency Quick Start

If your deployment failed, run these commands first:

```bash
# Check cloud-init status
sudo cloud-init status --long

# Check logs for errors
sudo tail -50 /var/log/cloud-init.log | grep -i error

# Check Blocklet Server status
sudo systemctl status blocklet-server

# Check Blocklet CLI installation
which blocklet && blocklet --version

# Test web interface
curl -I http://localhost:8080

# Run ArcDeploy-Dev diagnostics
./scripts/debug_commands.sh
```

## 📋 Production Deployment Issues

### 1. SSH Connection Problems

**Symptoms:**
- "Permission denied (publickey)" error
- Connection refused on port 2222
- SSH timeout

**Most Common Cause:** SSH key placeholder not replaced in cloud-init.yaml

**Check SSH Key Configuration:**
```bash
# Verify SSH key was replaced in cloud-init.yaml
grep "ssh-ed25519" cloud-init.yaml
# Should show YOUR actual key, not "IReplaceWithYourActualEd25519PublicKey"
```

**Debugging Steps:**
```bash
# Check if SSH service is running (from console)
sudo systemctl status ssh

# Check SSH configuration
sudo sshd -T | grep -i port
sudo sshd -T | grep -i passwordauth

# Check firewall status
sudo ufw status verbose

# Check user exists
id arcblock

# Check SSH logs
sudo journalctl -u ssh -f
```

**Solutions:**
```bash
# 1. Fix SSH key in cloud-init.yaml and redeploy
sed -i 's/ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIReplaceWithYourActualEd25519PublicKey your-email@example.com/YOUR_ACTUAL_SSH_PUBLIC_KEY/' cloud-init.yaml

# 2. Manual key addition via cloud console
sudo -u arcblock mkdir -p /home/arcblock/.ssh
echo "YOUR_SSH_PUBLIC_KEY" | sudo tee -a /home/arcblock/.ssh/authorized_keys
sudo chown -R arcblock:arcblock /home/arcblock/.ssh
sudo chmod 700 /home/arcblock/.ssh
sudo chmod 600 /home/arcblock/.ssh/authorized_keys

# 3. Connect with correct format
ssh -p 2222 arcblock@YOUR_SERVER_IP
```

### 2. Cloud-Init Never Started

**Symptoms:**
- `cloud-init status` shows "not run"
- No logs in `/var/log/cloud-init.log`
- Services show as inactive

**Debugging Steps:**
```bash
# Check datasource detection
sudo cat /run/cloud-init/ds-identify.log

# Check cloud-init services
sudo systemctl status cloud-init-local.service
sudo systemctl status cloud-init-network.service
sudo systemctl status cloud-config.service
sudo systemctl status cloud-final.service

# Check service order
sudo systemctl list-jobs --after
```

**Solutions:**
```bash
# Force cloud-init to run
sudo cloud-init clean
sudo cloud-init init
sudo cloud-init modules --mode=config
sudo cloud-init modules --mode=final

# Check for YAML syntax errors
sudo cloud-init schema --config-file cloud-init.yaml
```

### 3. Blocklet Server Won't Start

**Symptoms:**
- Service fails to start or keeps restarting
- Port 8080 not responding
- Systemd service errors

**Debugging Steps:**
```bash
# Check service status and logs
sudo systemctl status blocklet-server --no-pager -l
sudo journalctl -u blocklet-server --no-pager -l

# Check Node.js installation
node --version
npm --version
which blocklet

# Check directory permissions
ls -la /opt/blocklet-server/
ls -la /opt/blocklet-server/data/
ls -la /opt/blocklet-server/config/

# Check if port is available
sudo netstat -tlnp | grep :8080
```

**Solutions:**
```bash
# 1. Reinstall Blocklet CLI
sudo npm uninstall -g @blocklet/cli
sudo npm install -g @blocklet/cli

# 2. Reinitialize Blocklet Server
sudo systemctl stop blocklet-server
sudo -u blockletd rm -rf /opt/blocklet-server/data/*
sudo -u blockletd /usr/local/bin/blocklet server init /opt/blocklet-server --skip-existing
sudo systemctl start blocklet-server

# 3. Check configuration
sudo -u blockletd /usr/local/bin/blocklet server config list
```

### 4. Nginx Reverse Proxy Issues

**Symptoms:**
- Port 80/443 not responding
- SSL certificate errors
- Proxy errors in logs

**Debugging Steps:**
```bash
# Check nginx status
sudo systemctl status nginx
sudo nginx -t

# Check configuration
sudo cat /etc/nginx/sites-available/blocklet-server
sudo ls -la /etc/nginx/sites-enabled/

# Check logs
sudo tail -f /var/log/nginx/error.log
sudo tail -f /var/log/nginx/access.log
```

**Solutions:**
```bash
# Restart nginx
sudo systemctl restart nginx

# Fix configuration
sudo nginx -t && sudo systemctl reload nginx

# Enable site if disabled
sudo ln -sf /etc/nginx/sites-available/blocklet-server /etc/nginx/sites-enabled/
sudo systemctl reload nginx
```

### 5. SSL Certificate Problems

**Symptoms:**
- HTTPS not working
- Certificate warnings in browser
- SSL handshake failures

**Debugging Steps:**
```bash
# Check certificate status
sudo openssl x509 -in /etc/ssl/certs/ssl-cert-snakeoil.pem -text -noout

# Test SSL connection
openssl s_client -connect localhost:443 -servername YOUR_DOMAIN

# Check Let's Encrypt status (if using real domain)
sudo certbot certificates
```

**Solutions:**
```bash
# Setup SSL for your domain
sudo /opt/blocklet-server/ssl-setup.sh your-domain.com your-email@domain.com

# Or check certificate with our SSL validation tool
./tests/ssl-certificate-validation.sh --host your-domain.com
```

### 6. Firewall and Port Issues

**Symptoms:**
- Cannot connect to any ports
- Connection timeouts
- Services running but not accessible

**Port Configuration Reference:**
| Port | Service | Purpose | Required |
|------|---------|---------|----------|
| 2222 | SSH | Secure Shell access | Critical |
| 80 | Nginx | HTTP proxy/redirect | Important |
| 443 | Nginx | HTTPS proxy | Important |
| 8080 | Blocklet | HTTP (localhost only) | Critical |
| 8443 | Blocklet | HTTPS (localhost only) | Critical |

**Debugging Steps:**
```bash
# Check UFW status
sudo ufw status verbose

# Check which ports are listening
sudo netstat -tlnp | grep -E ":80|:443|:2222|:8080"

# Check iptables rules
sudo iptables -L -n

# Check fail2ban status
sudo fail2ban-client status
sudo fail2ban-client status sshd
```

**Solutions:**
```bash
# Reset firewall to default ArcDeploy configuration
sudo ufw --force reset
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw limit 2222/tcp comment 'SSH'
sudo ufw allow 80/tcp comment 'HTTP'
sudo ufw allow 443/tcp comment 'HTTPS'
sudo ufw --force enable

# Check if you're banned by fail2ban
sudo fail2ban-client set sshd unbanip YOUR_IP

# Verify firewall rules
sudo ufw status numbered
```

## 🧪 ArcDeploy-Dev Testing Issues

### 1. Test Suite Failures

**Symptoms:**
- Tests failing unexpectedly
- Permission denied errors
- Missing dependencies

**Debugging Steps:**
```bash
# Run debug commands
./scripts/debug_commands.sh

# Check test environment
./tests/comprehensive-test-suite.sh --quick

# Validate setup
./scripts/validate-setup.sh

# Check permissions
ls -la scripts/
ls -la tests/
```

**Solutions:**
```bash
# Make scripts executable
chmod +x scripts/*.sh tests/*.sh

# Install missing dependencies
sudo apt-get update
sudo apt-get install -y curl wget jq netcat-openbsd

# Run in debug mode
DEBUG=true ./tests/comprehensive-test-suite.sh
```

### 2. Mock Infrastructure Problems

**Symptoms:**
- Mock services not starting
- Network simulation failures
- API mocking errors

**Debugging Steps:**
```bash
# Check mock services
./scripts/debug_commands.sh

# Test network connectivity
ping -c 3 127.0.0.1
curl -f http://127.0.0.1:8888/health || echo "Mock API not responding"

# Check port availability
netstat -tlnp | grep :8888
```

**Solutions:**
```bash
# Restart mock infrastructure
./mock-infrastructure/network-failure-sim.sh --reset

# Clear any stuck processes
pkill -f "mock-infrastructure"

# Check for port conflicts
sudo lsof -i :8888
```

### 3. Failure Injection Issues

**Symptoms:**
- Failure scenarios not working
- System not recovering
- Emergency recovery needed

**Debugging Steps:**
```bash
# Check system health
./tests/failure-injection/recovery/emergency-recovery.sh --assess

# View active failure scenarios
ps aux | grep -E "(failure|inject)"

# Check system resources
df -h
free -h
uptime
```

**Solutions:**
```bash
# Emergency recovery
./tests/failure-injection/recovery/emergency-recovery.sh full

# Stop all failure scenarios
./tests/failure-injection/recovery/emergency-recovery.sh quick

# Reset network configuration
sudo systemctl restart networking
sudo systemctl restart systemd-resolved
```

### 4. SSL Certificate Testing Problems

**Symptoms:**
- SSL tests failing
- Certificate validation errors
- Connection timeouts

**Debugging Steps:**
```bash
# Run SSL validation
./tests/ssl-certificate-validation.sh --debug

# Check certificate status
openssl x509 -in /etc/ssl/certs/ssl-cert-snakeoil.pem -text -noout

# Test manual connection
openssl s_client -connect localhost:443 -servername localhost
```

**Solutions:**
```bash
# Generate new self-signed certificate
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/private/ssl-cert-snakeoil.key \
  -out /etc/ssl/certs/ssl-cert-snakeoil.pem \
  -subj "/CN=localhost"

# Restart nginx
sudo systemctl restart nginx
```

### 5. Production Compliance Issues

**Symptoms:**
- Compliance checks failing
- Configuration drift detected
- Missing production components

**Debugging Steps:**
```bash
# Run compliance check
./scripts/production-compliance-checker.sh

# Check specific components
./scripts/production-compliance-checker.sh --debug

# Compare with production
diff -u production-config.yaml current-config.yaml
```

**Solutions:**
```bash
# Fix compliance issues
./scripts/production-compliance-checker.sh --json | jq '.recommendations'

# Update configuration
./scripts/generate-config.sh --production

# Validate changes
./scripts/production-compliance-checker.sh --quiet
```

## 🔧 Performance Issues

### 1. Slow Performance

**Symptoms:**
- High response times
- System sluggishness
- Resource exhaustion

**Debugging Steps:**
```bash
# Check system resources
htop
iotop
df -h

# Run performance benchmark
./tests/performance-benchmark.sh

# Check service logs
sudo journalctl -u blocklet-server --since "10 minutes ago"
```

**Solutions:**
```bash
# Restart services
sudo systemctl restart blocklet-server nginx

# Clean up logs
sudo journalctl --vacuum-time=2d

# Check for resource leaks
./scripts/debug_commands.sh | grep -E "(memory|cpu|disk)"
```

### 2. Network Issues

**Symptoms:**
- Connection timeouts
- DNS resolution failures
- Network unreachability

**Debugging Steps:**
```bash
# Test connectivity
ping -c 3 8.8.8.8
nslookup google.com
curl -I https://google.com

# Check network configuration
ip addr show
ip route show
cat /etc/resolv.conf
```

**Solutions:**
```bash
# Restart networking
sudo systemctl restart systemd-networkd
sudo systemctl restart systemd-resolved

# Flush DNS cache
sudo systemd-resolve --flush-caches

# Test with different DNS
echo "nameserver 8.8.8.8" | sudo tee /etc/resolv.conf
```

## 📊 Logs and Monitoring

### Key Log Locations

```bash
# Cloud-init logs
/var/log/cloud-init.log
/var/log/cloud-init-output.log

# System logs
sudo journalctl -u blocklet-server
sudo journalctl -u nginx
sudo journalctl -u ssh

# Application logs
/opt/blocklet-server/logs/
/var/log/nginx/

# ArcDeploy-Dev logs
test-results/logs/
test-results/comprehensive-logs/
```

### Monitoring Commands

```bash
# System health
./scripts/debug_commands.sh

# Service status
sudo systemctl status blocklet-server nginx ssh fail2ban

# Resource usage
htop
df -h
free -h

# Network status
ss -tlnp
sudo ufw status verbose
```

## 🆘 Emergency Recovery

### Complete System Recovery

```bash
# 1. Emergency recovery for ArcDeploy-Dev
./tests/failure-injection/recovery/emergency-recovery.sh full

# 2. Restart all services
sudo systemctl restart blocklet-server nginx ssh

# 3. Reset firewall
sudo ufw --force reset
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw limit 2222/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw --force enable

# 4. Reinitialize Blocklet Server if needed
sudo systemctl stop blocklet-server
sudo -u blockletd /usr/local/bin/blocklet server init /opt/blocklet-server --skip-existing
sudo systemctl start blocklet-server

# 5. Validate recovery
./scripts/production-compliance-checker.sh
```

### Manual Recovery Steps

```bash
# 1. Check system basics
sudo cloud-init status --long
id arcblock
sudo systemctl status blocklet-server

# 2. Fix SSH access
sudo -u arcblock mkdir -p /home/arcblock/.ssh
echo "YOUR_SSH_PUBLIC_KEY" | sudo tee /home/arcblock/.ssh/authorized_keys
sudo chown -R arcblock:arcblock /home/arcblock/.ssh
sudo chmod 700 /home/arcblock/.ssh
sudo chmod 600 /home/arcblock/.ssh/authorized_keys

# 3. Restart core services
sudo systemctl restart ssh nginx blocklet-server

# 4. Test connectivity
curl -I http://localhost:8080
ssh -p 2222 arcblock@localhost
```

## 📞 Getting Help

### Self-Diagnosis

Before seeking help, run these diagnostic commands and include the output:

```bash
# System information
./scripts/debug_commands.sh > debug-output.txt

# Test results
./tests/comprehensive-test-suite.sh --quick > test-results.txt

# Compliance check
./scripts/production-compliance-checker.sh > compliance-check.txt

# System logs
sudo journalctl -u blocklet-server --since "1 hour ago" > service-logs.txt
```

### Support Channels

- **GitHub Issues**: [Report bugs and issues](https://github.com/Pocklabs/ArcDeploy-Dev/issues)
- **Documentation**: Check relevant guides in [docs/](docs/)
- **Production Repository**: [Main ArcDeploy project](https://github.com/Pocklabs/ArcDeploy)
- **Discussions**: [Feature requests and questions](https://github.com/Pocklabs/ArcDeploy-Dev/discussions)

### Issue Reporting Template

When reporting issues, please include:

```
**Environment:**
- OS: [Ubuntu version]
- Cloud Provider: [AWS/GCP/Azure/Hetzner/etc.]
- Server Specs: [CPU/RAM/Storage]

**Problem:**
- Description: [What's happening]
- Expected: [What should happen]
- Steps to reproduce: [How to trigger the issue]

**Diagnostic Output:**
[Paste output from debug_commands.sh]

**Logs:**
[Relevant log entries]

**Additional Context:**
[Any other relevant information]
```

---

**Last Updated**: June 15, 2025  
**For Production Issues**: Check the main [ArcDeploy repository](https://github.com/Pocklabs/ArcDeploy)  
**For Development/Testing Issues**: Use this repository's issue tracker