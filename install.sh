#!/bin/bash
#
# dotnet-termux Interactive Installation Script
# Version: 1.0.0
# Platform: Android ARM32 Termux
#
# This script provides an interactive installation experience for dotnet-termux
# allowing users to select between:
#  - Runtime Only (minimal, ~300MB)
#  - Full SDK (includes runtime, ~800MB)
#  - Runtime + SDK (both components)
#
# All components are compiled for ARM32 (ARMv7) architecture
#

set -e

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Global configuration
DOTNET_VERSION="8.0.11"
ARCHITECTURE="arm32"
RID="linux-arm-termux"
BASE_URL="https://github.com/rianalwis0v0-a11y/dotnet-termux/releases/download"
INSTALL_PREFIX="${TERMUX_PREFIX:-/data/data/com.termux/files/usr}"
DOTNET_HOME="${INSTALL_PREFIX}/share/dotnet"
TEMP_DIR="${TMPDIR:-/tmp}/dotnet-install"
LOG_FILE="${INSTALL_PREFIX}/var/log/dotnet-install.log"

# Platform detection variables
DETECTED_ARCH=""
DETECTED_OS=""

# ==============================================================================
# Utility Functions
# ==============================================================================

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')]" "$@" | tee -a "$LOG_FILE"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $@"
    log "[INFO] $@"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $@"
    log "[SUCCESS] $@"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $@"
    log "[WARNING] $@"
}

error() {
    echo -e "${RED}[ERROR]${NC} $@" >&2
    log "[ERROR] $@"
}

die() {
    error "$@"
    exit 1
}

# ==============================================================================
# Platform Detection
# ==============================================================================

detect_platform() {
    info "Detecting platform..."
    
    # Detect OS
    if [[ -f "/proc/version" ]] && grep -q "Linux" /proc/version; then
        DETECTED_OS="Linux"
    else
        die "This installation script only works on Linux/Termux"
    fi
    
    # Detect Architecture
    local uname_m=$(uname -m)
    case "$uname_m" in
        armv7l|armv7*|arm)
            DETECTED_ARCH="arm32"
            ;;
        aarch64|arm64)
            die "This build is for ARM32 (32-bit). Your device appears to be ARM64 (64-bit). Please use the ARM64 build instead."
            ;;
        i686)
            die "ARM32 build requested, but detected i686 architecture. Use the x86 build."
            ;;
        x86_64)
            die "ARM32 build requested, but detected x86_64 architecture. Use the x64 build."
            ;;
        *)
            die "Unknown/unsupported architecture: $uname_m"
            ;;
    esac
    
    # Check for Termux
    if [[ ! -d "$INSTALL_PREFIX" ]]; then
        warn "TERMUX_PREFIX not detected. Assuming standard Linux installation."
        INSTALL_PREFIX="/usr/local"
        DOTNET_HOME="${INSTALL_PREFIX}/share/dotnet"
    else
        success "Termux environment detected"
    fi
    
    success "Platform detection complete"
    info "  OS: $DETECTED_OS"
    info "  Architecture: $DETECTED_ARCH (ARM32 - ARMv7)"
    info "  Install Prefix: $INSTALL_PREFIX"
}

# ==============================================================================
# Validation Functions
# ==============================================================================

validate_arm32() {
    info "Validating ARM32 compatibility..."
    
    # Check CPU flags for ARMv7
    if grep -q "Features.*vfpv[3-4]" /proc/cpuinfo; then
        success "ARMv7 with VFPv3+ detected (compatible)"
    elif grep -q "Features.*vfp" /proc/cpuinfo; then
        success "ARMv7 with VFP detected (compatible)"
    elif grep -q "Features" /proc/cpuinfo; then
        warn "Could not verify full ARMv7 feature set, but CPU detected"
    else
        warn "Could not detect CPU flags, assuming ARMv7 compatibility"
    fi
    
    # Check kernel version (Android 5.0+ = kernel 3.10+)
    local kernel_version=$(uname -r | cut -d. -f1-2)
    if (( $(echo "$kernel_version >= 3.10" | bc -l) )); then
        success "Kernel version $kernel_version compatible (Android 5.0+)"
    else
        warn "Kernel version $kernel_version detected; .NET may have compatibility issues"
    fi
    
    # Check libc
    if ldd --version 2>/dev/null | head -1 | grep -q "musl"; then
        success "musl libc detected (Termux standard)"
    elif ldd --version 2>/dev/null | head -1 | grep -q "glibc"; then
        success "glibc detected (compatible)"
    else
        warn "Could not determine libc type"
    fi
}

check_disk_space() {
    local required=$1
    local available=$(df "$INSTALL_PREFIX" | awk 'NR==2 {print $4}')
    
    if (( available < required )); then
        die "Insufficient disk space. Required: ${required}KB, Available: ${available}KB"
    fi
    
    info "Disk space check: OK (available: ${available}KB)"
}

check_dependencies() {
    info "Checking dependencies..."
    
    local deps=("curl" "tar" "bash")
    local missing=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing+=("$dep")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        die "Missing required tools: ${missing[@]}. Please install them first."
    fi
    
    success "All dependencies present"
}

# ==============================================================================
# Installation Options Menu
# ==============================================================================

show_installation_menu() {
    echo ""
    echo -e "${BLUE}==========================================="
    echo -e "  dotnet-termux Installation (v${DOTNET_VERSION})"
    echo -e "  Platform: Android ARM32"
    echo -e "  Architecture: ARMv7"
    echo -e "===========================================${NC}"
    echo ""
    echo "Select installation type:"
    echo ""
    echo "  1) Runtime Only (~300 MB)"
    echo "     - Minimal installation"
    echo "     - Run pre-built .NET applications"
    echo "     - Use: dotnet app.dll"
    echo ""
    echo "  2) SDK Only (~800 MB)"
    echo "     - Includes SDK tools"
    echo "     - Create and build .NET projects"
    echo "     - Use: dotnet new, dotnet build, dotnet publish"
    echo "     - WARNING: Runtime must be separately installed"
    echo ""
    echo "  3) Runtime + SDK (Recommended, ~1.1 GB)"
    echo "     - Complete .NET development environment"
    echo "     - Full functionality"
    echo "     - Use: Everything"
    echo ""
    echo "  4) Cancel"
    echo ""
}

get_installation_choice() {
    local choice
    
    while true; do
        read -p "Enter your choice (1-4): " choice
        
        case $choice in
            1)
                info "Selected: Runtime Only"
                return 1
                ;;
            2)
                info "Selected: SDK Only"
                return 2
                ;;
            3)
                info "Selected: Runtime + SDK (Recommended)"
                return 3
                ;;
            4)
                info "Installation cancelled"
                exit 0
                ;;
            *)
                error "Invalid choice. Please select 1-4."
                ;;
        esac
    done
}

# ==============================================================================
# Installation Functions
# ==============================================================================

setup_directories() {
    info "Setting up directories..."
    
    mkdir -p "$TEMP_DIR"
    mkdir -p "$DOTNET_HOME"
    mkdir -p "$(dirname "$LOG_FILE")"
    mkdir -p "${INSTALL_PREFIX}/bin"
    mkdir -p "${INSTALL_PREFIX}/lib"
    
    success "Directories created"
}

download_file() {
    local url=$1
    local output=$2
    local description=$3
    
    info "Downloading $description..."
    info "  URL: $url"
    
    if ! curl -L --progress-bar --retry 3 --retry-delay 2 -o "$output" "$url"; then
        die "Failed to download $description from $url"
    fi
    
    success "Downloaded: $(basename "$output") ($(du -h "$output" | cut -f1))"
}

verify_checksum() {
    local file=$1
    local expected_checksum=$2
    local description=$3
    
    info "Verifying checksum for $description..."
    
    local actual_checksum=$(sha256sum "$file" | awk '{print $1}')
    
    if [[ "$actual_checksum" == "$expected_checksum" ]]; then
        success "Checksum verification passed"
        return 0
    else
        error "Checksum mismatch for $description"
        error "  Expected: $expected_checksum"
        error "  Got:      $actual_checksum"
        return 1
    fi
}

install_runtime() {
    info "Installing .NET Runtime ${DOTNET_VERSION}..."
    
    local runtime_file="$TEMP_DIR/dotnet-runtime-${DOTNET_VERSION}-linux-${ARCHITECTURE}.tar.gz"
    local runtime_url="${BASE_URL}/v${DOTNET_VERSION}/dotnet-runtime-${DOTNET_VERSION}-linux-arm32.tar.gz"
    local runtime_checksum="PLACEHOLDER_RUNTIME_SHA256"
    
    # Check disk space: runtime ~300 MB
    check_disk_space 400000
    
    # Download
    download_file "$runtime_url" "$runtime_file" "Runtime"
    
    # Verify
    verify_checksum "$runtime_file" "$runtime_checksum" "Runtime" || die "Checksum verification failed"
    
    # Extract
    info "Extracting runtime..."
    tar -xzf "$runtime_file" -C "$DOTNET_HOME" --strip-components=1
    success "Runtime extracted"
    
    # Create symlinks for binaries
    info "Creating symlinks..."
    ln -sf "${DOTNET_HOME}/dotnet" "${INSTALL_PREFIX}/bin/dotnet" || true
    ln -sf "${DOTNET_HOME}/host/fxr/${DOTNET_VERSION}"/* "${INSTALL_PREFIX}/lib/" 2>/dev/null || true
    
    success "Runtime installation complete"
}

install_sdk() {
    info "Installing .NET SDK ${DOTNET_VERSION}..."
    
    local sdk_file="$TEMP_DIR/dotnet-sdk-${DOTNET_VERSION}-linux-${ARCHITECTURE}.tar.gz"
    local sdk_url="${BASE_URL}/v${DOTNET_VERSION}/dotnet-sdk-${DOTNET_VERSION}-linux-arm32.tar.gz"
    local sdk_checksum="PLACEHOLDER_SDK_SHA256"
    
    # Check disk space: SDK ~800 MB total (may already have runtime)
    check_disk_space 1000000
    
    # Download
    download_file "$sdk_url" "$sdk_file" "SDK"
    
    # Verify
    verify_checksum "$sdk_file" "$sdk_checksum" "SDK" || die "Checksum verification failed"
    
    # Extract
    info "Extracting SDK..."
    tar -xzf "$sdk_file" -C "$DOTNET_HOME" --strip-components=1
    success "SDK extracted"
    
    # Create symlinks
    info "Creating symlinks..."
    ln -sf "${DOTNET_HOME}/dotnet" "${INSTALL_PREFIX}/bin/dotnet" || true
    
    success "SDK installation complete"
}

configure_environment() {
    info "Configuring environment..."
    
    # Create or update environment configuration
    local env_file="${INSTALL_PREFIX}/etc/profile.d/dotnet-termux.sh"
    mkdir -p "$(dirname "$env_file")"
    
    cat > "$env_file" << 'EOF'
#!/bin/bash
# dotnet-termux Environment Configuration
# Auto-generated by install script

# Set DOTNET_ROOT for .NET runtime discovery
export DOTNET_ROOT="${DOTNET_ROOT:-$TERMUX_PREFIX/share/dotnet}"
export DOTNET_HOME="${DOTNET_HOME:-$TERMUX_PREFIX/share/dotnet}"

# Add dotnet to PATH
if [[ ":$PATH:" != *":$TERMUX_PREFIX/bin:"* ]]; then
    export PATH="$TERMUX_PREFIX/bin:$PATH"
fi

# Configure library path for ARM32
export LD_LIBRARY_PATH="$TERMUX_PREFIX/lib:$TERMUX_PREFIX/lib/arm-linux-gnueabihf:$DOTNET_ROOT/host/fxr:$LD_LIBRARY_PATH"

# Set custom RID for Termux ARM32
export DOTNET_RID="linux-arm-termux"

# Optimize for ARM32 low-memory environments
export DOTNET_GCHeapHardLimit=268435456      # 256 MB hard limit for GC
export DOTNET_GCHeapHardLimitPercent=95      # Use 95% of limit
export DOTNET_GCConserveMemory=1             # Conservative memory usage

# Enable minimal verbosity for troubleshooting
# export DOTNET_ROOT_X64=      # Prevent accidental 64-bit detection
EOF
    
    chmod 755 "$env_file"
    success "Environment configured: $env_file"
    
    # Source it for current session
    source "$env_file" || true
}

generate_runtime_config() {
    info "Generating RID configuration..."
    
    local rid_config="${DOTNET_HOME}/runtime.json"
    
    cat > "$rid_config" << 'EOF'
{
  "runtimes": {
    "linux-arm-termux": {
      "#import": [
        "linux-arm",
        "base"
      ]
    },
    "android-arm32-termux": {
      "#import": [
        "linux-arm-termux"
      ]
    }
  }
}
EOF
    
    success "RID configuration generated: $rid_config"
}

validate_installation() {
    info "Validating installation..."
    
    # Check if dotnet binary exists
    if [[ ! -f "${INSTALL_PREFIX}/bin/dotnet" ]]; then
        die "dotnet binary not found at ${INSTALL_PREFIX}/bin/dotnet"
    fi
    
    # Check if it's executable
    if [[ ! -x "${INSTALL_PREFIX}/bin/dotnet" ]]; then
        die "dotnet binary is not executable"
    fi
    
    # Try to run dotnet --version
    local dotnet_path="${INSTALL_PREFIX}/bin/dotnet"
    local dotnet_version=$($dotnet_path --version 2>&1 || echo "FAILED")
    
    if [[ "$dotnet_version" == "FAILED" ]]; then
        warn "Could not verify dotnet version. This may be normal if libraries are not yet loaded."
    else
        success "dotnet binary verified: $dotnet_version"
    fi
}

cleanup() {
    info "Cleaning up temporary files..."
    
    if [[ -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
        success "Temporary files removed"
    fi
}

# ==============================================================================
# Post-Installation Information
# ==============================================================================

show_post_install_info() {
    echo ""
    echo -e "${GREEN}==========================================="
    echo -e "  Installation Complete!"
    echo -e "===========================================${NC}"
    echo ""
    echo -e "${BLUE}Installation Summary:${NC}"
    echo "  Version: ${DOTNET_VERSION}"
    echo "  Architecture: ARM32 (ARMv7)"
    echo "  Platform: Android Termux"
    echo "  Install Location: ${DOTNET_HOME}"
    echo ""
    
    echo -e "${BLUE}Next Steps:${NC}"
    echo ""
    echo "1. Create a new project:"
    echo "   ${GREEN}dotnet new console -n MyApp${NC}"
    echo ""
    echo "2. Navigate to project:"
    echo "   ${GREEN}cd MyApp${NC}"
    echo ""
    echo "3. Run the application:"
    echo "   ${GREEN}dotnet run${NC}"
    echo ""
    echo -e "${BLUE}Useful Commands:${NC}"
    echo "   dotnet --version          # Show .NET version"
    echo "   dotnet --list-sdks        # List installed SDKs"
    echo "   dotnet --list-runtimes    # List installed runtimes"
    echo "   dotnet --info             # Show detailed information"
    echo ""
    echo -e "${BLUE}Documentation:${NC}"
    echo "   Official Docs: https://docs.microsoft.com/en-us/dotnet/"
    echo "   Project Repo: https://github.com/rianalwis0v0-a11y/dotnet-termux"
    echo "   Issues/Support: https://github.com/rianalwis0v0-a11y/dotnet-termux/issues"
    echo ""
    echo -e "${BLUE}Environment:${NC}"
    echo "   Configuration file: ${INSTALL_PREFIX}/etc/profile.d/dotnet-termux.sh"
    echo "   Log file: ${LOG_FILE}"
    echo ""
    
    if [[ -n "$TERMUX_PREFIX" ]]; then
        echo -e "${YELLOW}Note: Restart your Termux session or run:${NC}"
        echo "   ${GREEN}source ${INSTALL_PREFIX}/etc/profile.d/dotnet-termux.sh${NC}"
        echo ""
    fi
    
    echo -e "${GREEN}Happy coding! 🚀${NC}"
    echo ""
}

# ==============================================================================
# Main Installation Flow
# ==============================================================================

main() {
    echo -e "${BLUE}"
    echo ".NET Runtime & SDK for Android ARM32 Termux"
    echo "Installer Script v1.0.0"
    echo -e "${NC}"
    echo ""
    
    # Initialize logging
    mkdir -p "$(dirname "$LOG_FILE")"
    echo "Installation started at $(date)" > "$LOG_FILE"
    
    info "Starting installation process..."
    info "User: $(whoami), Shell: $SHELL, PWD: $PWD"
    
    # Step 1: Check dependencies
    check_dependencies
    echo ""
    
    # Step 2: Detect platform
    detect_platform
    echo ""
    
    # Step 3: Validate ARM32 compatibility
    validate_arm32
    echo ""
    
    # Step 4: Show menu and get choice
    show_installation_menu
    get_installation_choice
    local choice=$?
    echo ""
    
    # Step 5: Setup directories
    setup_directories
    echo ""
    
    # Step 6: Install based on choice
    case $choice in
        1)
            # Runtime only
            install_runtime
            ;;
        2)
            # SDK only
            warn "SDK selected without runtime. Runtime must be installed separately."
            install_sdk
            ;;
        3)
            # Runtime + SDK
            install_runtime
            echo ""
            install_sdk
            ;;
    esac
    echo ""
    
    # Step 7: Configure environment
    configure_environment
    echo ""
    
    # Step 8: Generate RID configuration
    generate_runtime_config
    echo ""
    
    # Step 9: Validate
    validate_installation
    echo ""
    
    # Step 10: Cleanup
    cleanup
    echo ""
    
    # Step 11: Show completion info
    show_post_install_info
    
    success "Installation finished at $(date)"
}

# Run main function
main "$@"
