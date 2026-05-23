# ARM32 Bionic .NET Patching Guide

## Quick Start (5 minutes)

```bash
# 1. Download and patch all at once
bash patch-arm32-advanced.sh

# 2. Verify it works
dotnet --version

# Done!
```

---

## What These Scripts Do

### `quick-install.sh` - Minimal Setup
- ✅ Download Microsoft .NET 8.0.11 ARM32 self-contained
- ✅ Extract to `/data/data/com.termux/files/usr/share/dotnet-arm32`
- ✅ Create simple wrapper in `/bin/dotnet`
- ⏱️ **Time**: ~5 minutes

**Use this if**: You just want it to work, no complexity.

```bash
bash quick-install.sh
```

---

### `patch-arm32-advanced.sh` - Full Patching
- ✅ Download + extract self-contained runtime
- ✅ **Patch ELF interpreter** with `patchelf` (glibc → Bionic)
- ✅ Create Bionic compatibility layer
- ✅ Generate diagnostics report
- ⏱️ **Time**: ~10 minutes

**Use this if**: You want the most compatible, well-tested setup.

```bash
bash patch-arm32-advanced.sh
```

---

### `patch-elf-interpreter.sh` - Manual Patching
Standalone utility for patching individual binaries.

**Dry run (see what would happen):**
```bash
./patch-elf-interpreter.sh --dry-run /path/to/dotnet
```

**Patch a binary:**
```bash
./patch-elf-interpreter.sh /data/data/com.termux/files/usr/share/dotnet-arm32/dotnet
```

**Verify patch worked:**
```bash
./patch-elf-interpreter.sh --verify /path/to/dotnet
```

**Restore from backup:**
```bash
./patch-elf-interpreter.sh --restore /path/to/dotnet.bak
```

---

## Understanding the Patching

### Why It's Needed

.NET binaries from Microsoft are compiled for **glibc** (GNU C Library):
```
readelf -l /path/to/dotnet | grep INTERP
  INTERP         0x....... 0x........
  [Requesting program interpreter: /lib/ld-linux-armhf.so.3]
```

But **Termux ARM32 uses Bionic** (Android's C library):
```
ls -la /system/lib/ld-android.so
-rwxr-xr-x 1 root root 145768 ... /system/lib/ld-android.so
```

**File `/lib/ld-linux-armhf.so.3` doesn't exist on Android.**

### The Patch

Changes the ELF interpreter requirement from glibc to Bionic:

**Before:**
```
[Requesting program interpreter: /lib/ld-linux-armhf.so.3]
```

**After (patched):**
```
[Requesting program interpreter: /system/lib/ld-android.so]
```

Now the binary can load using Bionic.

---

## Installation Paths

### Default Termux
```
Install Dir:  /data/data/com.termux/files/usr/share/dotnet-arm32
Binary:       /data/data/com.termux/files/usr/bin/dotnet
Libraries:    (self-contained in install dir)
```

### Standard Linux (no Termux)
```
Install Dir:  /usr/local/share/dotnet-arm32
Binary:       /usr/local/bin/dotnet
```

---

## What's in the Self-Contained Runtime

These files are included:

```
dotnet-arm32/
├── dotnet                    # Main executable (patched)
├── libcoreclr.so            # .NET runtime library
├── libhostfxr.so.8          # Host FX resolver
├── libhostpolicy.so.8       # Host policy
├── shared/
│   └── Microsoft.NETCore.App/
│       └── 8.0.11/          # Runtime dependencies
└── packs/                    # SDK packs (if SDK installed)
```

**Total size**: ~150-200 MB (self-contained, no external deps)

---

## Verifying the Installation

### Check binary is executable
```bash
file /data/data/com.termux/files/usr/share/dotnet-arm32/dotnet
# Output should be: ELF 32-bit LSB executable, ARM, EABI5
```

### Check ELF interpreter
```bash
readelf -l /data/data/com.termux/files/usr/share/dotnet-arm32/dotnet | grep INTERP
# Should show: /system/lib/ld-android.so
```

### Run it
```bash
dotnet --version
# Should output: 8.0.11
```

### Full system info
```bash
dotnet --info
# Shows runtime, SDK, and environment details
```

---

## Troubleshooting

### "cannot execute binary file"
This means the ELF interpreter is wrong or missing.

**Check:**
```bash
readelf -l /path/to/dotnet | grep INTERP
```

**If it shows `/lib/ld-linux-armhf.so.3`**: Patch wasn't applied.
- Run: `patch-elf-interpreter.sh /path/to/dotnet`

**If it shows `/system/lib/ld-android.so`** but still fails:
- Check Bionic exists: `ls -la /system/lib/ld-android.so`
- Check library path: `echo $LD_LIBRARY_PATH`

### "undefined symbol" errors
Some glibc symbols may not exist in Bionic.

**Workaround**: Use the wrapper script which sets library paths:
```bash
# The wrapper handles this automatically
dotnet --version
```

### Memory errors on ARM32
ARM32 has limited memory. Set limits:

```bash
export DOTNET_GCHeapHardLimit=268435456  # 256 MB
export DOTNET_GCHeapHardLimitPercent=95
dotnet myapp.dll
```

---

## Diagnostics

### Full diagnostic report
After installation, a report is generated at:
```
/data/data/com.termux/files/usr/share/dotnet-arm32/DIAGNOSTICS.txt
```

View it:
```bash
cat /data/data/com.termux/files/usr/share/dotnet-arm32/DIAGNOSTICS.txt
```

### Manual diagnostics
```bash
# 1. Check architecture
uname -m
# Output: armv7l (or similar ARM32)

# 2. Check Bionic
file /system/lib/libc.so
# Output: ELF 32-bit LSB shared object

# 3. Check dotnet binary
file $( which dotnet)
# Output: ELF 32-bit LSB executable, ARM

# 4. Check ELF headers
readelf -h $(which dotnet) | grep Machine
# Output: Machine: ARM

# 5. Try execution with diagnostics
COREHOST_TRACE=1 dotnet --version 2>&1 | head -20
```

---

## Advanced Usage

### Custom installation path
```bash
export TERMUX_PREFIX=/custom/path
bash patch-arm32-advanced.sh
```

### Patch without automatic wrapper
```bash
# Just extract and patch, manually manage paths
tar -xzf dotnet-runtime-8.0.11-linux-arm.tar.gz -C /custom/install
patch-elf-interpreter.sh /custom/install/dotnet
```

### Patch multiple binaries
```bash
for binary in /custom/install/*.so*; do
    patch-elf-interpreter.sh "$binary"
done
```

---

## Next Steps

### Create a .NET app
```bash
dotnet new console -n HelloApp
cd HelloApp
dotnet run
```

### Publish a self-contained app
```bash
dotnet publish -c Release -o output --self-contained
```

### Use Mono instead (lighter alternative)
```bash
pkg install mono
mono app.exe
```

---

## Support

- **GitHub**: https://github.com/rianalwis0v0-a11y/dotnet-termux
- **Issues**: https://github.com/rianalwis0v0-a11y/dotnet-termux/issues
- **Termux Wiki**: https://wiki.termux.com/

---

## References

- [.NET on ARM32](https://github.com/dotnet/runtime)
- [Bionic libc](https://android.googlesource.com/platform/bionic/)
- [patchelf tool](https://github.com/NixOS/patchelf)
- [ELF format](https://en.wikipedia.org/wiki/Executable_and_Linkable_Format)
