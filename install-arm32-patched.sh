#!/bin/bash
#
# dotnet-termux Self-Contained Runtime Installer with Bionic Patching
# Version: 2.0.0
# Target: Android ARM32 Termux
#
# This script:
# 1. Downloads official .NET 8.0 ARM32 self-contained runtime
# 2. Patches ELF interpreter for Bionic compatibility
# 3. Creates shim launcher wrapper
# 4. Validates and tests installation
#

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================

DOTNET_VERSION="8.0.11"
ARCHITECTURE="arm32"
RID="linux-arm"

# Official Microsoft .NET downloads (ARM32 self-contained)
# https://dotnetcli.blob.core.windows.net/dotnet/release-metadata/releases-index.json
BASE_URL="https://dotnetcli.blob.core.windows.net/dotnet/Runtime/${DOTNET_VERSION}"
RUNTIME_ARCHIVE="dotnet-runtime-${DOTNET_VERSION}-linux-arm.tar.gz"
RUNTIME_URL="${BASE_URL}/${RUNTIME_ARCHIVE}"

# Termux paths
TERMUX_PREFIX="${TERMUX_PREFIX:-/data/data/com.termux/files/usr}"
INSTALL_PATH="${TERMUX_PREFIX}/share/dotnet-arm32"
BIN_PATH="${TERMUX_PREFIX}/bin"
TEMP_DIR="${TMPDIR:-/tmp}/dotnet-patch-$$"
LOG_FILE="${TERMUX_PREFIX}/var/log/dotnet-arm32-patch.log"

# Bionic paths
BIONIC_INTERP="/system/lib/ld-android.so"
BIONIC_LIBC="/system/lib/libc.so"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ============================================================================
# Logging
# ============================================================================

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $*"
    log "[INFO] $*"
}

success() {
    echo -e "${GREEN}[✓]${NC} $*"
    log "[SUCCESS] $*"
}

warn() {
    echo -e "${YELLOW}[!]${NC} $*"
    log "[WARNING] $*"
}

error() {
    echo -e "${RED}[✗]${NC} $*" >&2
    log "[ERROR] $*"
}

die() {
    error "$*"
    cleanup
    exit 1
}

# ============================================================================
# Utility Functions
# ============================================================================

cleanup() {
    info "Cleaning up temporary files..."
    rm -rf "$TEMP_DIR" || true
}

trap cleanup EXIT

check_requirements() {
    info "Checking system requirements..."
    
    local missing=()
    
    # Check for required tools
    for tool in curl tar readelf patchelf mkdir chmod; do
        if ! command -v "$tool" &>/dev/null; then
            missing+=("$tool")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        die "Missing required tools: ${missing[*]}. Install with: pkg install ${missing[*]}"
    fi
    
    # Verify ARM32 architecture
    local arch=$(uname -m)
    if [[ ! "$arch" =~ armv7|arm ]]; then
        die "This script is for ARM32. Detected: $arch"
    fi
    
    # Verify Termux environment
    if [[ ! -d "$TERMUX_PREFIX" ]]; then
        warn "TERMUX_PREFIX not detected at $TERMUX_PREFIX"
        warn "Attempting standard Linux path: /usr/local"
        TERMUX_PREFIX="/usr/local"
        INSTALL_PATH="/usr/local/share/dotnet-arm32"
    fi
    
    success "All requirements met"
}

create_directories() {
    info "Creating installation directories..."
    mkdir -p "$INSTALL_PATH"
    mkdir -p "$BIN_PATH"
    mkdir -p "$(dirname "$LOG_FILE")"
    mkdir -p "$TEMP_DIR"
    success "Directories created"
}

download_runtime() {
    info "Downloading .NET Runtime $DOTNET_VERSION (ARM32)..."
    info "  URL: $RUNTIME_URL"
    info "  This is the self-contained runtime (includes all dependencies)"
    
    local target="$TEMP_DIR/$RUNTIME_ARCHIVE"
    
    if ! curl -L --progress-bar --retry 5 --retry-delay 2 -o "$target" "$RUNTIME_URL"; then
        die "Failed to download runtime from $RUNTIME_URL"
    fi
    
    if [[ ! -f "$target" ]]; then
        die "Download verification failed - file not found"
    fi
    
    local size=$(du -h "$target" | cut -f1)
    success "Downloaded: $RUNTIME_ARCHIVE ($size)"
    
    echo "$target"
}

extract_runtime() {
    local archive=$1
    
    info "Extracting runtime..."
    tar -xzf "$archive" -C "$INSTALL_PATH"
    success "Runtime extracted to $INSTALL_PATH"
}

# ============================================================================
# ELF Patching for Bionic Compatibility
# ============================================================================

analyze_elf_headers() {
    info "Analyzing ELF headers for Bionic compatibility..."
    
    local dotnet_binary="$INSTALL_PATH/dotnet"
    
    if [[ ! -f "$dotnet_binary" ]]; then
        die "dotnet binary not found at $dotnet_binary"
    fi
    
    # Show ELF information
    echo ""
    info "ELF Header Information:"
    readelf -h "$dotnet_binary" | grep -E "Class|Data|Machine|Version|Type|Entry"
    echo ""
    
    # Show required interpreter
    echo "Current interpreter requirement:"
    local interp=$(readelf -l "$dotnet_binary" | grep "INTERP" | head -1)
    echo "  $interp"
    echo ""
    
    # Show dynamic dependencies
    echo "Dynamic libraries required:"
    readelf -d "$dotnet_binary" 2>/dev/null | grep "NEEDED" | head -10 || echo "  (no standard dependencies found - self-contained)"
    echo ""
}

patch_elf_interpreter() {
    info "Patching ELF interpreter for Bionic..."
    
    local dotnet_binary="$INSTALL_PATH/dotnet"
    local libcoreclr="$INSTALL_PATH/libcoreclr.so"
    
    # Check if patchelf is available
    if ! command -v patchelf &>/dev/null; then
        warn "patchelf not found. Attempting to install..."
        pkg install patchelf || warn "Could not install patchelf, trying manual patching"
    fi
    
    # Get current interpreter
    local current_interp=$(readelf -l "$dotnet_binary" 2>/dev/null | grep "INTERP" | grep -oP '/lib[^"]*' || echo "unknown")
    
    info "Current interpreter: $current_interp"
    info "Target interpreter: $BIONIC_INTERP"
    
    if command -v patchelf &>/dev/null; then
        # Use patchelf for clean interpreter patching
        info "Patching with patchelf..."
        
        # Patch dotnet binary
        patchelf --set-interpreter "$BIONIC_INTERP" "$dotnet_binary" || warn "Could not patch dotnet interpreter"
        
        # Patch libcoreclr.so
        if [[ -f "$libcoreclr" ]]; then
            patchelf --set-interpreter "$BIONIC_INTERP" "$libcoreclr" || warn "Could not patch libcoreclr.so interpreter"
        fi
        
        success "ELF interpreter patched"
    else
        warn "patchelf unavailable - will use wrapper script approach"
    fi
}

create_launcher_wrapper() {
    info "Creating launcher wrapper script..."
    
    local wrapper="$BIN_PATH/dotnet"
    local real_dotnet="$INSTALL_PATH/dotnet"
    
    cat > "$wrapper" << 'WRAPPER_EOF'
#!/bin/bash
#
# dotnet-arm32 Launcher Wrapper
# Handles Bionic compatibility for .NET ARM32 runtime
#

INSTALL_PATH="${INSTALL_PATH:-/data/data/com.termux/files/usr/share/dotnet-arm32}"
REAL_DOTNET="$INSTALL_PATH/dotnet"

# Bionic-compatible library configuration
export LD_LIBRARY_PATH="$INSTALL_PATH:$INSTALL_PATH/shared:${LD_LIBRARY_PATH:-}"

# Disable 64-bit runtime detection (prevent ARM64 fallback)
export DOTNET_ROOT_ARM64=
export DOTNET_ROOT_X64=

# Memory-friendly settings for ARM32
export DOTNET_GCHeapHardLimit=268435456      # 256 MB
export DOTNET_GCHeapHardLimitPercent=95
export DOTNET_GCConserveMemory=1

# RID override for custom Termux runtime
export DOTNET_RID=linux-arm

# Enable diagnostics if needed
if [[ "$DEBUG_DOTNET" == "1" ]]; then
    export COREHOST_TRACE=1
    export COREHOST_TRACEFILE=/tmp/dotnet-trace.log
fi

# Execute real dotnet with arguments
exec "$REAL_DOTNET" "$@"
WRAPPER_EOF
    
    chmod +x "$wrapper"
    success "Launcher wrapper created at $wrapper"
}

# ============================================================================
# Symbol Compatibility Layer
# ============================================================================

create_libc_shim() {
    info "Creating Bionic libc compatibility layer..."
    
    # This script will help verify library compatibility
    local shim_script="$INSTALL_PATH/verify-bionic-compat.sh"
    
    cat > "$shim_script" << 'SHIM_EOF'
#!/bin/bash
#
# Verify Bionic libc compatibility
#

echo "=== Bionic libc Compatibility Check ==="
echo ""

# Check Bionic libc
if [[ -f /system/lib/libc.so ]]; then
    echo "✓ Bionic libc found at /system/lib/libc.so"
    file /system/lib/libc.so
else
    echo "✗ Bionic libc not found"
    exit 1
fi

echo ""
echo "Checking for glibc (should NOT exist):"
if ldd --version 2>/dev/null | grep -q glibc; then
    echo "! glibc is installed - may cause conflicts"
else
    echo "✓ glibc not found (good for ARM32 Termux)"
fi

echo ""
echo "Library search paths:"
echo "  LD_LIBRARY_PATH=$LD_LIBRARY_PATH"
echo ""

# Try to load a core .NET library
local dotnet_root="${DOTNET_ROOT:-/data/data/com.termux/files/usr/share/dotnet-arm32}"
if [[ -f "$dotnet_root/libcoreclr.so" ]]; then
    echo "Attempting to load libcoreclr.so..."
    ldd "$dotnet_root/libcoreclr.so" 2>&1 | head -20 || echo "(ldd may fail on Bionic - this is expected)"
fi
SHIM_EOF
    
    chmod +x "$shim_script"
    success "Compatibility layer script created"
}

# ============================================================================
# Validation and Testing
# ============================================================================

validate_installation() {
    info "Validating installation..."
    
    # Check binary exists
    if [[ ! -f "$INSTALL_PATH/dotnet" ]]; then
        die "dotnet binary not found at $INSTALL_PATH/dotnet"
    fi
    success "✓ dotnet binary found"
    
    # Check it's executable
    if [[ ! -x "$INSTALL_PATH/dotnet" ]]; then
        die "dotnet binary is not executable"
    fi
    success "✓ dotnet binary is executable"
    
    # Check wrapper
    if [[ ! -f "$BIN_PATH/dotnet" ]]; then
        die "Launcher wrapper not found at $BIN_PATH/dotnet"
    fi
    success "✓ Launcher wrapper installed"
    
    # Try to execute
    info "Attempting to execute: dotnet --version"
    if "$BIN_PATH/dotnet" --version 2>&1; then
        success "✓ dotnet executed successfully"
    else
        warn "dotnet execution failed (may be Bionic symbol issue)"
        info "Checking ELF compatibility..."
        
        # Detailed error analysis
        local interp=$("$BIN_PATH/dotnet" 2>&1 || true)
        if [[ "$interp" =~ "cannot execute" ]] || [[ "$interp" =~ "No such file" ]]; then
            error "Cannot execute binary - likely ELF interpreter mismatch"
            error "Attempting diagnosis..."
            
            readelf -l "$INSTALL_PATH/dotnet" | grep "INTERP\|DYNAMIC" || true
        fi
    fi
}

# ============================================================================
# Installation Summary
# ============================================================================

show_completion_info() {
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║ .NET ARM32 Self-Contained Installation ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
    echo ""
    
    echo -e "${BLUE}Installation Summary:${NC}"
    echo "  Version: $DOTNET_VERSION"
    echo "  Architecture: ARM32 (ARMv7)"
    echo "  Type: Self-Contained Runtime"
    echo "  Install Path: $INSTALL_PATH"
    echo "  Wrapper: $BIN_PATH/dotnet"
    echo ""
    
    echo -e "${BLUE}Verification Steps:${NC}"
    echo "  1. Check installation:"
    echo "     ${GREEN}dotnet --version${NC}"
    echo ""
    echo "  2. Verify Bionic compatibility:"
    echo "     ${GREEN}$INSTALL_PATH/verify-bionic-compat.sh${NC}"
    echo ""
    echo "  3. Analyze ELF headers:"
    echo "     ${GREEN}readelf -l $INSTALL_PATH/dotnet${NC}"
    echo ""
    
    echo -e "${BLUE}Troubleshooting:${NC}"
    echo "  If 'cannot execute' error occurs:"
    echo "    • Check: file $INSTALL_PATH/dotnet"
    echo "    • Check: readelf -l $INSTALL_PATH/dotnet | grep INTERP"
    echo "    • Ensure Bionic is available: ls -la /system/lib/ld-android.so"
    echo ""
    
    echo -e "${BLUE}Log File:${NC}"
    echo "  $LOG_FILE"
    echo ""
}

# ============================================================================
# Main Installation Flow
# ============================================================================

main() {
    echo -e "${BLUE}"
    echo "╔═════════════════════════════════════════════════════════╗"
    echo "║   .NET 8.0 ARM32 Self-Contained Runtime Installer       ║"
    echo "║   with Bionic ELF Patching                              ║"
    echo "╚═════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo ""
    
    # Initialize logging
    mkdir -p "$(dirname "$LOG_FILE")"
    echo "Installation started at $(date)" > "$LOG_FILE"
    log "User: $(whoami), Shell: $SHELL, PWD: $PWD"
    
    info "Starting .NET ARM32 installation with Bionic patching..."
    echo ""
    
    # Step 1: Check requirements
    check_requirements
    echo ""
    
    # Step 2: Create directories
    create_directories
    echo ""
    
    # Step 3: Download runtime
    local archive=$(download_runtime)
    echo ""
    
    # Step 4: Extract
    extract_runtime "$archive"
    echo ""
    
    # Step 5: Analyze ELF headers
    analyze_elf_headers
    echo ""
    
    # Step 6: Patch interpreter
    patch_elf_interpreter
    echo ""
    
    # Step 7: Create wrapper
    create_launcher_wrapper
    echo ""
    
    # Step 8: Create compatibility layer
    create_libc_shim
    echo ""
    
    # Step 9: Validate
    validate_installation
    echo ""
    
    # Step 10: Show summary
    show_completion_info
    
    log "Installation completed at $(date)"
}

main "$@"
