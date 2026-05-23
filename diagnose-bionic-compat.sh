#!/bin/bash
#
# Bionic ARM32 .NET Compatibility Diagnostic Tool
# Detects ELF interpreter issues and symbol mismatches
#

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${BLUE}[*]${NC} $*"; }
success() { echo -e "${GREEN}[✓]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
error() { echo -e "${RED}[✗]${NC} $*"; }

diagnose_elf() {
    local binary=$1
    
    if [[ ! -f "$binary" ]]; then
        error "File not found: $binary"
        return 1
    fi
    
    echo ""
    info "ELF Analysis: $(basename "$binary")"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # File type
    echo ""
    info "File Type:"
    file "$binary"
    
    # ELF headers
    echo ""
    info "ELF Header:"
    readelf -h "$binary" 2>/dev/null | grep -E "Class|Data|Machine|Version|Type|Entry" || warn "readelf failed"
    
    # Interpreter
    echo ""
    info "ELF Interpreter (required by binary):"
    local interp=$(readelf -l "$binary" 2>/dev/null | grep "INTERP" | grep -oP '\[.*\]' || echo "NONE")
    echo "  $interp"
    
    # Check if interpreter exists
    local interp_path=$(readelf -l "$binary" 2>/dev/null | grep "INTERP" | grep -oP '/[^"]*' || echo "")
    if [[ -n "$interp_path" ]]; then
        echo ""
        info "Interpreter availability:"
        if [[ -f "$interp_path" ]]; then
            success "Found at $interp_path"
        else
            error "NOT FOUND at $interp_path"
            error "This is why the binary cannot execute!"
        fi
    fi
    
    # Dynamic library dependencies
    echo ""
    info "Dynamic Library Dependencies:"
    readelf -d "$binary" 2>/dev/null | grep "NEEDED" | head -20 || echo "  (self-contained or statically linked)"
}

diagnose_system() {
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  System Environment Diagnostics        ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
    
    # Architecture
    echo ""
    info "Architecture:"
    uname -m
    
    # Kernel version
    echo ""
    info "Kernel Version:"
    uname -r
    
    # OS detection
    echo ""
    info "Operating System:"
    if [[ -f /proc/version ]]; then
        grep "Linux" /proc/version | head -1
    else
        echo "Unknown"
    fi
    
    # Termux detection
    echo ""
    info "Termux Detection:"
    if [[ -n "${TERMUX_PREFIX:-}" ]]; then
        success "TERMUX_PREFIX=$TERMUX_PREFIX"
    elif [[ -d /data/data/com.termux ]]; then
        success "Termux environment detected"
    else
        warn "Not in Termux (standard Linux)"
    fi
    
    # libc type
    echo ""
    info "C Library (libc):"
    if [[ -f /system/lib/libc.so ]]; then
        success "Bionic detected at /system/lib/libc.so"
        file /system/lib/libc.so | head -1
    elif ldd --version 2>/dev/null | grep -q glibc; then
        success "glibc detected"
        ldd --version | head -1
    elif ldd --version 2>/dev/null | grep -q musl; then
        success "musl detected"
        ldd --version | head -1
    else
        warn "Could not determine libc type"
    fi
}

diagnose_interpreters() {
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  Available ELF Interpreters            ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
    
    echo ""
    info "glibc interpreters (for standard Linux):"
    ls -la /lib/ld-*.so* 2>/dev/null | sed 's/^/  /' || echo "  ❌ NOT FOUND"
    
    echo ""
    info "Bionic interpreter (for Android/Termux):"
    ls -la /system/lib/ld-android.so* 2>/dev/null | sed 's/^/  /' || echo "  ❌ NOT FOUND"
    
    echo ""
    info "musl interpreter (Alpine/embedded):"
    ls -la /lib/ld-musl* 2>/dev/null | sed 's/^/  /' || echo "  ❌ NOT FOUND"
}

diagnose_dotnet() {
    local dotnet_paths=(
        "/data/data/com.termux/files/usr/share/dotnet-arm32/dotnet"
        "/usr/local/share/dotnet-arm32/dotnet"
        "/usr/share/dotnet/dotnet"
        "$(command -v dotnet 2>/dev/null || echo '')"
    )
    
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  .NET Runtime Analysis                 ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
    
    for path in "${dotnet_paths[@]}"; do
        if [[ -n "$path" && -f "$path" ]]; then
            diagnose_elf "$path"
        fi
    done
    
    # Try to execute
    echo ""
    info "Runtime Execution Test:"
    if command -v dotnet &>/dev/null; then
        if dotnet --version 2>&1; then
            success "dotnet executable and functional"
        else
            error "dotnet found but execution failed"
        fi
    else
        warn "dotnet not found in PATH"
    fi
}

show_summary() {
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  Diagnostic Summary                    ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
    echo ""
    
    echo -e "${YELLOW}Key Questions:${NC}"
    echo ""
    
    echo "1. Is this ARM32 architecture?"
    if uname -m | grep -q "armv7\|arm"; then
        echo -e "   ${GREEN}✓ YES${NC}"
    else
        echo -e "   ${RED}✗ NO${NC}"
    fi
    
    echo ""
    echo "2. Is this Termux or standard Linux?"
    if [[ -f /system/lib/libc.so ]]; then
        echo -e "   ${GREEN}Bionic (Termux/Android)${NC}"
    elif ldd --version 2>/dev/null | grep -q glibc; then
        echo -e "   ${GREEN}glibc (Standard Linux)${NC}"
    else
        echo -e "   ${YELLOW}Unknown${NC}"
    fi
    
    echo ""
    echo "3. Are required interpreters available?"
    if [[ -f /system/lib/ld-android.so ]]; then
        echo -e "   ${GREEN}✓ Bionic available${NC}"
    fi
    if [[ -f /lib/ld-linux-armhf.so.3 ]]; then
        echo -e "   ${GREEN}✓ glibc ARM32 available${NC}"
    fi
    if ! [[ -f /system/lib/ld-android.so ]] && ! [[ -f /lib/ld-linux-armhf.so.3 ]]; then
        echo -e "   ${RED}✗ No compatible interpreters${NC}"
    fi
    
    echo ""
    echo "4. Can .NET runtime execute?"
    if command -v dotnet &>/dev/null && dotnet --version &>/dev/null; then
        echo -e "   ${GREEN}✓ YES${NC}"
    else
        echo -e "   ${RED}✗ NO${NC}"
    fi
}

main() {
    echo -e "${BLUE}"
    echo "╔═════════════════════════════════════════════════════════╗"
    echo "║   ARM32 .NET Bionic Compatibility Diagnostic             ║"
    echo "╚═════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    diagnose_system
    diagnose_interpreters
    diagnose_dotnet
    show_summary
    
    echo ""
    echo -e "${BLUE}Documentation:${NC}"
    echo "  https://github.com/rianalwis0v0-a11y/dotnet-termux"
    echo ""
}

main "$@"
