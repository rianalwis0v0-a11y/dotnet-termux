# dotnet-termux Version Strategy

## .NET Version Selection: 8.0.11

### Why .NET 8.0.11?

#### ✅ Advantages

1. **Long-Term Support (LTS)**
   - Support extends to November 2028
   - Stable, production-ready
   - Regular security updates

2. **ARM32 Support**
   - Official .NET 8 includes ARM32 (ARMv7) binaries
   - Well-tested on Linux ARM32
   - Proven compatibility

3. **Modern .NET Features**
   - LINQ improvements
   - System.Text.Json enhancements
   - Performance optimizations
   - C# 12 language features

4. **Termux Compatibility**
   - glibc and musl support
   - Standard Linux syscalls
   - No Bionic libc dependency

5. **Large Ecosystem**
   - Extensive NuGet package support
   - Community knowledge and examples
   - Framework maturity

#### ⚠️ Limitations

1. **ARM32 Deprecation**
   - .NET 9 may reduce ARM32 support
   - Future versions may not target ARM32
   - This is the last mainstream .NET with guaranteed ARM32 support

2. **Not Latest**
   - .NET 9 is newer (but less ARM32 support)
   - .NET 6 is older but also LTS

### Version Numbering

```
8.0.11
│││└─ Patch version (bug fixes, security patches)
││└── Minor version (feature additions)
│└─── Major version (breaking changes)
```

- **8**: Major version
- **0**: Minor version (release line)
- **11**: Patch version (latest patch as of May 2026)

### ARM32 Compatibility Matrix

| .NET Version | ARM32 Support | LTS | Notes |
|---|---|---|---|
| 6.0.x | ✅ Yes | ✅ Yes | Older, still supported |
| **8.0.11** | ✅ Yes | ✅ Yes | **RECOMMENDED** |
| 9.0.x | ⚠️ Limited | ❌ No | Reduced ARM32 support |
| 10.0+ | ❌ No | - | ARM32 support dropped |

## All Components Are ARM32-Optimized

### Runtime (libcoreclr.so)

- **Binary**: ARM32 native
- **Optimization**: Thumb-2 instruction set
- **Features**: NEON support when available
- **Size**: ~65 MB compressed, ~180 MB uncompressed

### hostfxr (Framework Discovery)

- **Binary**: ARM32 native
- **Size**: ~3 MB
- **Function**: Locates and initializes runtime
- **Termux Patches**: Path handling, environment setup

### hostpolicy (Assembly Resolution)

- **Binary**: ARM32 native
- **Size**: ~2 MB
- **Function**: Resolves dependencies
- **Termux Patches**: Termux-specific probing paths

### SDK Tools (dotnet CLI)

- **Binaries**: All ARM32 native
- **Components**:
  - `dotnet`: Main launcher (wrapper script)
  - `Roslyn`: C# compiler (managed, runs on CoreCLR)
  - `MSBuild`: Build system (managed, runs on CoreCLR)
  - Template engines: Managed code

### Dependencies (ARM32 versions)

| Dependency | Purpose | ARM32 Build |
|---|---|---|
| libunwind | Stack unwinding | arm-linux-gnueabihf |
| libcurl | HTTP operations | arm-linux-gnueabihf |
| libssl | TLS/SSL | arm-linux-gnueabihf |
| libz | Compression | arm-linux-gnueabihf |
| libicu | Unicode support | arm-linux-gnueabihf |

## Installation Size Estimates

### Runtime Only
```
.NET 8.0.11 Runtime (ARM32):
  - libcoreclr.so:        ~65 MB (compressed)
  - hostfxr:              ~3 MB
  - hostpolicy:           ~2 MB
  - System libraries:      ~200 MB (uncompressed)
  - Dependencies:          ~30 MB
  ────────────────────────────
  Total:                  ~300 MB
```

### SDK Only
```
.NET 8.0.11 SDK (ARM32):
  - Runtime (above):      ~300 MB
  - dotnet CLI:           ~50 MB
  - Roslyn compiler:      ~300 MB
  - MSBuild:              ~150 MB
  - SDK libraries:        ~200 MB
  ────────────────────────────
  Total:                  ~1.0 GB
```

### Runtime + SDK (Recommended)
```
.NET 8.0.11 Full (ARM32):
  - Deduplicated:         ~1.1 GB
  ────────────────────────────
  Total:                  ~1.1 GB
```

## Installation Approach

### Interactive Selection (install.sh)

The `install.sh` script offers three options:

1. **Runtime Only** (300 MB)
   - Best for: Running pre-built applications
   - Commands: `dotnet app.dll`
   - Use case: Production servers

2. **SDK Only** (800 MB)
   - Best for: Development without runtime
   - Commands: `dotnet build`, `dotnet publish`
   - Warning: Runtime must be installed separately
   - Use case: Rare, not recommended

3. **Runtime + SDK** (1.1 GB) - **RECOMMENDED**
   - Best for: Full development environment
   - Commands: All dotnet commands
   - Use case: Development machines

## Version Update Strategy

### Point Release Updates (e.g., 8.0.11 → 8.0.12)
- Security patches
- Bug fixes
- No breaking changes
- Drop-in replacement
- Recommended: **Always apply**

### Minor Updates (e.g., 8.0.x → 8.1.x)
- Feature additions
- No breaking changes
- Backward compatible
- Recommended: **Opt-in**

### Major Updates (e.g., 8.x → 9.x)
- Breaking changes possible
- New major features
- ARM32 support may vary
- Recommended: **Plan carefully**

## Future Considerations

### .NET 9+ ARM32 Support

- ARM32 support in .NET 9 is reduced
- Consider this: **Last mainstream .NET with full ARM32 support**
- Community may maintain ARM32 builds after official support ends
- Mono fallback available for older ARM32 devices

### Migration Path

If ARM32 support is dropped in future .NET versions:

1. **Option A**: Stay on .NET 8 LTS (supported until Nov 2028)
2. **Option B**: Use Mono runtime (FOSS alternative)
3. **Option C**: Upgrade to ARM64-capable device

## Verification

To verify your installation:

```bash
# Check .NET version
dotnet --version
# Output: 8.0.11

# Check architecture
dotnet --info
# Output should show: ARM, linux-arm-termux

# List runtimes
dotnet --list-runtimes
# Output: Microsoft.NETCore.App 8.0.11 [/data/data/com.termux/files/usr/share/dotnet]

# Verify ARM32 optimization
file $(which dotnet)
# Output: ARM 32-bit executable (not 64-bit)
```

## Support Lifecycle

```
.NET 8.0 Support Timeline:

Nov 2023 ├─ Release
         │
Jul 2024 ├─ .NET 8.0.7 (security updates begin)
         │
May 2026 ├─ .NET 8.0.11 ◄─── (YOU ARE HERE)
         │
Nov 2026 ├─ Support Reduced
         │
Nov 2028 ├─ End of Support
         │
```

This project will continue supporting .NET 8 ARM32 after Microsoft's official support ends.
