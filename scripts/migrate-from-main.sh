#!/bin/bash

# ArcDeploy Migration Script: Main Branch to Unified Architecture
# This script helps users migrate from the main branch to the unified architecture
# with the new configuration system and enhanced features

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
readonly MIGRATION_LOG="$PROJECT_ROOT/migration.log"
readonly BACKUP_DIR="$PROJECT_ROOT/migration-backup-$(date +%Y%m%d_%H%M%S)"
readonly CONFIG_DIR="$PROJECT_ROOT/config"
readonly LEGACY_CONFIG="$PROJECT_ROOT/cloud-init.yaml"

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
    echo -e "${BLUE}[INFO]${NC} $message" | tee -a "$MIGRATION_LOG"
}

success() {
    local message="$1"
    echo -e "${GREEN}[SUCCESS]${NC} $message" | tee -a "$MIGRATION_LOG"
}

warning() {
    local message="$1"
    echo -e "${YELLOW}[WARNING]${NC} $message" | tee -a "$MIGRATION_LOG"
}

error() {
    local message="$1"
    echo -e "${RED}[ERROR]${NC} $message" | tee -a "$MIGRATION_LOG"
}

error_exit() {
    local message="$1"
    error "$message"
    echo -e "${RED}Migration failed. Check $MIGRATION_LOG for details.${NC}"
    exit 1
}

# ============================================================================
# Utility Functions
# ============================================================================

# Check if we're on the correct branch
check_branch() {
    local current_branch
    current_branch=$(git -C "$PROJECT_ROOT" branch --show-current 2>/dev/null || echo "unknown")
    
    if [[ "$current_branch" != "dev-deployment" ]]; then
        warning "You are not on the dev-deployment branch (currently on: $current_branch)"
        echo "The unified architecture is available on the dev-deployment branch."
        echo ""
        echo "Would you like to switch to dev-deployment branch? (y/N)"
        read -r response
        
        if [[ "${response,,}" == "y" || "${response,,}" == "yes" ]]; then
            log "Switching to dev-deployment branch..."
            if ! git -C "$PROJECT_ROOT" checkout dev-deployment; then
                error_exit "Failed to switch to dev-deployment branch"
            fi
            success "Switched to dev-deployment branch"
        else
            error_exit "Migration requires dev-deployment branch"
        fi
    fi
}

# Create backup of current configuration
create_backup() {
    log "Creating backup of current configuration..."
    
    mkdir -p "$BACKUP_DIR"
    
    # Backup important files
    local files_to_backup=(
        "cloud-init.yaml"
        "README.md"
        "QUICK_START.md"
        "scripts/"
        "docs/"
    )
    
    for item in "${files_to_backup[@]}"; do
        if [[ -e "$PROJECT_ROOT/$item" ]]; then
            cp -r "$PROJECT_ROOT/$item" "$BACKUP_DIR/"
            log "Backed up: $item"
        fi
    done
    
    # Backup any existing config directory
    if [[ -d "$CONFIG_DIR" ]]; then
        cp -r "$CONFIG_DIR" "$BACKUP_DIR/config-existing"
        log "Backed up existing config directory"
    fi
    
    success "Backup completed: $BACKUP_DIR"
}

# Extract configuration from cloud-init.yaml
extract_legacy_config() {
    log "Extracting configuration from cloud-init.yaml..."
    
    if [[ ! -f "$LEGACY_CONFIG" ]]; then
        warning "No cloud-init.yaml found, skipping legacy config extraction"
        return 0
    fi
    
    local temp_config="/tmp/arcdeploy-extracted-config.conf"
    
    {
        echo "# Configuration extracted from cloud-init.yaml"
        echo "# Generated on $(date)"
        echo "# Review and adjust these settings as needed"
        echo ""
        
        # Extract SSH key if present
        if grep -q "ssh_authorized_keys:" "$LEGACY_CONFIG"; then
            echo "# SSH Configuration"
            local ssh_key
            ssh_key=$(awk '/ssh_authorized_keys:/,/^[[:space:]]*-/ {if(/^[[:space:]]*-/) print $0}' "$LEGACY_CONFIG" | head -n1 | sed 's/^[[:space:]]*-[[:space:]]*//')
            if [[ -n "$ssh_key" ]]; then
                echo "SSH_PUBLIC_KEY=\"$ssh_key\""
            fi
            echo ""
        fi
        
        # Extract user configuration
        echo "# User Configuration"
        if grep -q "name: arcblock" "$LEGACY_CONFIG"; then
            echo "USER_NAME=\"arcblock\""
        fi
        echo ""
        
        # Extract port configuration from write_files or runcmd
        echo "# Network Configuration"
        if grep -q "Port 2222" "$LEGACY_CONFIG"; then
            echo "SSH_PORT=\"2222\""
        fi
        
        if grep -q "8080" "$LEGACY_CONFIG"; then
            echo "BLOCKLET_HTTP_PORT=\"8080\""
        fi
        
        if grep -q "8443" "$LEGACY_CONFIG"; then
            echo "BLOCKLET_HTTPS_PORT=\"8443\""
        fi
        echo ""
        
        # Extract domain if present
        echo "# Optional Configuration"
        if grep -q "server_name" "$LEGACY_CONFIG" && ! grep -q "server_name _" "$LEGACY_CONFIG"; then
            local domain
            domain=$(grep "server_name" "$LEGACY_CONFIG" | grep -v "_" | head -n1 | awk '{print $2}' | tr -d ';')
            if [[ -n "$domain" ]]; then
                echo "DOMAIN_NAME=\"$domain\""
            fi
        fi
        
        # Extract SSL configuration
        if grep -q "ssl_certificate" "$LEGACY_CONFIG"; then
            echo "ENABLE_SSL=\"true\""
        else
            echo "ENABLE_SSL=\"false\""
        fi
        
        echo ""
        echo "# Feature Flags (adjust based on your needs)"
        echo "ENABLE_SSH_HARDENING=\"true\""
        echo "ENABLE_BASIC_FIREWALL=\"true\""
        echo "ENABLE_FAIL2BAN=\"true\""
        echo "ENABLE_AUTO_UPDATES=\"true\""
        echo "ENABLE_HEALTH_CHECKS=\"true\""
        
    } > "$temp_config"
    
    echo "$temp_config"
}

# Create main configuration file
create_main_config() {
    local extracted_config="$1"
    
    log "Creating main configuration file..."
    
    mkdir -p "$CONFIG_DIR"
    
    local main_config="$CONFIG_DIR/arcdeploy.conf"
    
    {
        echo "# ArcDeploy Main Configuration"
        echo "# This file contains your customizations and overrides"
        echo "# It will be loaded after defaults and profile settings"
        echo ""
        echo "# Generated by migration script on $(date)"
        echo "# Source: migrated from main branch configuration"
        echo ""
        
        if [[ -f "$extracted_config" ]]; then
            cat "$extracted_config"
        else
            echo "# No legacy configuration found"
            echo "# Add your customizations below"
            echo ""
            echo "# Example configuration:"
            echo "# USER_NAME=\"arcblock\""
            echo "# SSH_PORT=\"2222\""
            echo "# BLOCKLET_HTTP_PORT=\"8080\""
            echo "# DOMAIN_NAME=\"your-domain.com\""
            echo "# EMAIL_ADDRESS=\"admin@your-domain.com\""
        fi
        
        echo ""
        echo "# Advanced features (uncomment to enable)"
        echo "# ENABLE_MULTI_CLOUD=\"true\""
        echo "# ENABLE_ADVANCED_TESTING=\"true\""
        echo "# ENABLE_PERFORMANCE_MONITORING=\"true\""
        echo "# ENABLE_DEBUG_MODE=\"true\""
        
    } > "$main_config"
    
    success "Created main configuration: $main_config"
}

# Detect user preferences
detect_user_preferences() {
    log "Detecting user preferences and recommending profile..."
    
    local recommended_profile="simple"
    local reasons=()
    
    # Check for advanced usage patterns
    if [[ -d "$PROJECT_ROOT/tests" ]]; then
        recommended_profile="advanced"
        reasons+=("Testing framework detected")
    fi
    
    if [[ -f "$PROJECT_ROOT/scripts/generate-config.sh" ]]; then
        recommended_profile="advanced"
        reasons+=("Multi-cloud configuration generator detected")
    fi
    
    if grep -q "multiple cloud" "$PROJECT_ROOT"/*.md 2>/dev/null; then
        recommended_profile="advanced"
        reasons+=("Multi-cloud usage mentioned in documentation")
    fi
    
    # Check complexity of existing cloud-init.yaml
    if [[ -f "$LEGACY_CONFIG" ]]; then
        local line_count
        line_count=$(wc -l < "$LEGACY_CONFIG")
        if [[ $line_count -gt 200 ]]; then
            recommended_profile="advanced"
            reasons+=("Complex cloud-init configuration detected ($line_count lines)")
        fi
    fi
    
    echo ""
    echo "=== Profile Recommendation ==="
    echo "Recommended profile: $recommended_profile"
    
    if [[ ${#reasons[@]} -gt 0 ]]; then
        echo "Reasons:"
        for reason in "${reasons[@]}"; do
            echo "  - $reason"
        done
    fi
    
    echo ""
    echo "Profile options:"
    echo "  simple   - Basic deployment, minimal configuration (main branch compatibility)"
    echo "  advanced - Full features, multi-cloud, testing framework"
    echo ""
    
    echo "Would you like to use the recommended profile ($recommended_profile)? (Y/n)"
    read -r response
    
    if [[ "${response,,}" == "n" || "${response,,}" == "no" ]]; then
        echo "Available profiles:"
        echo "  1) simple"
        echo "  2) advanced"
        echo ""
        echo "Choose profile (1-2): "
        read -r choice
        
        case "$choice" in
            1) recommended_profile="simple" ;;
            2) recommended_profile="advanced" ;;
            *) 
                warning "Invalid choice, using recommended profile: $recommended_profile"
                ;;
        esac
    fi
    
    echo "$recommended_profile"
}

# Set up profile preference
setup_profile() {
    local profile="$1"
    
    log "Setting up profile preference: $profile"
    
    # Create profile indicator file
    echo "$profile" > "$CONFIG_DIR/.profile"
    
    # Set environment variable for current session
    export ARCDEPLOY_PROFILE="$profile"
    
    # Add to user's shell profile if desired
    echo ""
    echo "Would you like to set the profile permanently for your user? (y/N)"
    read -r response
    
    if [[ "${response,,}" == "y" || "${response,,}" == "yes" ]]; then
        local shell_profile=""
        
        if [[ -f "$HOME/.bashrc" ]]; then
            shell_profile="$HOME/.bashrc"
        elif [[ -f "$HOME/.bash_profile" ]]; then
            shell_profile="$HOME/.bash_profile"
        elif [[ -f "$HOME/.profile" ]]; then
            shell_profile="$HOME/.profile"
        fi
        
        if [[ -n "$shell_profile" ]]; then
            echo "" >> "$shell_profile"
            echo "# ArcDeploy profile preference" >> "$shell_profile"
            echo "export ARCDEPLOY_PROFILE=\"$profile\"" >> "$shell_profile"
            success "Added profile preference to $shell_profile"
        else
            warning "Could not find shell profile file to update"
        fi
    fi
    
    success "Profile setup completed: $profile"
}

# Test new configuration
test_configuration() {
    log "Testing new configuration..."
    
    # Source the configuration loader
    if [[ -f "$SCRIPT_DIR/lib/config-loader.sh" ]]; then
        source "$SCRIPT_DIR/lib/config-loader.sh"
        
        if init_configuration "${ARCDEPLOY_PROFILE:-simple}" "true"; then
            success "Configuration system test passed"
            
            echo ""
            echo "=== Configuration Summary ==="
            show_configuration_summary
            
            return 0
        else
            error "Configuration system test failed"
            return 1
        fi
    else
        error "Configuration loader not found"
        return 1
    fi
}

# Generate new deployment configuration
generate_deployment_config() {
    log "Generating new deployment configuration..."
    
    if [[ -f "$SCRIPT_DIR/generate-config.sh" ]]; then
        local ssh_key_file=""
        
        # Try to find SSH key
        local key_locations=(
            "$HOME/.ssh/id_ed25519.pub"
            "$HOME/.ssh/id_rsa.pub"
            "$HOME/.ssh/id_ecdsa.pub"
        )
        
        for key_file in "${key_locations[@]}"; do
            if [[ -f "$key_file" ]]; then
                ssh_key_file="$key_file"
                break
            fi
        done
        
        if [[ -z "$ssh_key_file" ]]; then
            warning "No SSH key found in standard locations"
            echo "Please specify your SSH public key file path:"
            read -r ssh_key_file
            
            if [[ ! -f "$ssh_key_file" ]]; then
                error "SSH key file not found: $ssh_key_file"
                return 1
            fi
        fi
        
        log "Using SSH key: $ssh_key_file"
        
        # Generate configuration
        local provider="${DEFAULT_CLOUD_PROVIDER:-hetzner}"
        local domain="${DOMAIN_NAME:-}"
        local email="${EMAIL_ADDRESS:-}"
        
        local generate_cmd="$SCRIPT_DIR/generate-config.sh -p $provider -k $ssh_key_file"
        
        if [[ -n "$domain" ]]; then
            generate_cmd="$generate_cmd -d $domain"
        fi
        
        if [[ -n "$email" ]]; then
            generate_cmd="$generate_cmd -e $email"
        fi
        
        log "Generating deployment configuration with: $generate_cmd"
        
        if $generate_cmd; then
            success "Deployment configuration generated successfully"
            
            # Show generated files
            if [[ -d "$PROJECT_ROOT/generated" ]]; then
                echo ""
                echo "Generated files:"
                find "$PROJECT_ROOT/generated" -name "*.yaml" -type f | while read -r file; do
                    echo "  - $file"
                done
            fi
            
            return 0
        else
            error "Failed to generate deployment configuration"
            return 1
        fi
    else
        warning "Configuration generator not available"
        warning "You can manually create deployment configurations later"
        return 0
    fi
}

# Show migration summary
show_migration_summary() {
    echo ""
    echo "============================================"
    echo "         Migration Summary"
    echo "============================================"
    echo ""
    echo "✅ Backup created: $BACKUP_DIR"
    echo "✅ Configuration system migrated"
    echo "✅ Profile configured: ${ARCDEPLOY_PROFILE:-simple}"
    echo "✅ Main configuration created: $CONFIG_DIR/arcdeploy.conf"
    
    if [[ -d "$PROJECT_ROOT/generated" ]]; then
        echo "✅ Deployment configurations generated"
    fi
    
    echo ""
    echo "Next steps:"
    echo "1. Review your configuration: $CONFIG_DIR/arcdeploy.conf"
    echo "2. Test deployment with: ./scripts/validate-setup.sh"
    
    if [[ -f "$SCRIPT_DIR/generate-config.sh" ]]; then
        echo "3. Generate cloud-specific configs: ./scripts/generate-config.sh -h"
    fi
    
    if [[ -d "$PROJECT_ROOT/tests" ]]; then
        echo "4. Run tests: ./tests/test-suite.sh"
    fi
    
    echo ""
    echo "Documentation:"
    echo "- Configuration guide: docs/CONFIGURATION.md"
    echo "- Branch strategy: docs/BRANCH_STRATEGY.md"
    echo "- Development guide: README-dev-deployment.md"
    echo ""
    echo "Migration completed successfully! 🎉"
    echo ""
}

# Show help
show_help() {
    cat << EOF
ArcDeploy Migration Script v$SCRIPT_VERSION

Migrate from main branch to unified architecture with enhanced configuration system.

Usage: $SCRIPT_NAME [OPTIONS]

Options:
    -h, --help              Show this help message
    -p, --profile PROFILE   Set specific profile (simple|advanced)
    -b, --backup-only       Only create backup, don't migrate
    -t, --test-only         Only test configuration, don't migrate
    -v, --verbose           Enable verbose output
    --no-backup             Skip backup creation (not recommended)
    --no-generate           Skip deployment config generation

Examples:
    $SCRIPT_NAME                    # Interactive migration
    $SCRIPT_NAME -p advanced        # Migrate to advanced profile
    $SCRIPT_NAME --backup-only      # Create backup only
    $SCRIPT_NAME --test-only        # Test configuration only

The migration process:
1. Creates backup of current configuration
2. Extracts settings from cloud-init.yaml
3. Sets up unified configuration system
4. Configures profile preference
5. Generates new deployment configurations
6. Tests the new configuration

For more information, see: docs/MIGRATION.md

EOF
}

# ============================================================================
# Main Migration Process
# ============================================================================

main() {
    local profile=""
    local backup_only="false"
    local test_only="false"
    local verbose="false"
    local no_backup="false"
    local no_generate="false"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -p|--profile)
                profile="$2"
                shift 2
                ;;
            -b|--backup-only)
                backup_only="true"
                shift
                ;;
            -t|--test-only)
                test_only="true"
                shift
                ;;
            -v|--verbose)
                verbose="true"
                shift
                ;;
            --no-backup)
                no_backup="true"
                shift
                ;;
            --no-generate)
                no_generate="true"
                shift
                ;;
            *)
                error "Unknown option: $1"
                echo "Use -h or --help for usage information"
                exit 1
                ;;
        esac
    done
    
    # Initialize log
    echo "Migration started on $(date)" > "$MIGRATION_LOG"
    
    echo "🚀 ArcDeploy Migration Script v$SCRIPT_VERSION"
    echo "================================================"
    echo ""
    
    # Test configuration only
    if [[ "$test_only" == "true" ]]; then
        log "Running configuration test only..."
        if test_configuration; then
            success "Configuration test completed successfully"
            exit 0
        else
            error_exit "Configuration test failed"
        fi
    fi
    
    # Check prerequisites
    check_branch
    
    # Create backup
    if [[ "$no_backup" != "true" ]]; then
        create_backup
        
        if [[ "$backup_only" == "true" ]]; then
            success "Backup completed: $BACKUP_DIR"
            exit 0
        fi
    fi
    
    # Extract legacy configuration
    local extracted_config
    extracted_config=$(extract_legacy_config)
    
    # Create main configuration
    create_main_config "$extracted_config"
    
    # Detect and set up profile
    if [[ -z "$profile" ]]; then
        profile=$(detect_user_preferences)
    fi
    
    setup_profile "$profile"
    
    # Test new configuration
    if ! test_configuration; then
        error "Configuration test failed - migration incomplete"
        echo "Check the configuration files and try again"
        exit 1
    fi
    
    # Generate deployment configuration
    if [[ "$no_generate" != "true" ]]; then
        generate_deployment_config || warning "Deployment config generation failed"
    fi
    
    # Clean up temporary files
    if [[ -f "$extracted_config" ]]; then
        rm -f "$extracted_config"
    fi
    
    # Show summary
    show_migration_summary
    
    success "Migration completed successfully!"
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi