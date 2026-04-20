<p align="center">
  <img src="docs/icon.png" width="96" height="96" alt="FSKitBridge">
</p>

<h1 align="center">FSKitBridge</h1>

A minimal host app + FSKit extension that connects macOS FSKit to a non-Swift file system backend over a local
socket.

> **Requires macOS 15.4+**

## Why FSKitBridge?

Apple introduced **FSKit** to replace kernel file system kexts with a safer, user-space model. But FSKit’s public API is
**Swift-centric**, while production file systems often live where strong memory-safety (Rust), legacy codebases (C/C++),
or ecosystem libraries (Go/Python) already exist. Without a bridge, teams face a false choice: rewrite everything in
Swift or skip FSKit. **FSKitBridge** removes that barrier.

> Swift where you must, your language where you want.

## Who should use this?

- **File system developers** who want to target macOS FSKit while keeping the core file system engine in
  **Rust/C/C++/Go/Python**.
- Teams **migrating from legacy kext-based stacks** and seeking a clean, testable user-space boundary.

> [`fskit-rs`](https://github.com/debox-network/fskit-rs): Rust crate for the protocol and socket layer — use it to
> build your Rust backend or as a reference for implementations in other languages.

## Architecture

<p align="center">
  <img src="docs/arch.svg" width="760" height="570" alt="Architecture Diagram">
</p>

### How it works

- **macOS**
    - **PlugInKit / ExtensionKit (PKD):** Discovers the embedded FSKit extension inside your host app, handles
      _election_ (which copy is active), launches the extension process when needed, and manages its lifecycle.
    - **FSKit host (VFS side):** System component that issues file system operations (lookup, read/write, enumerate, set
      attributes, etc.) to your extension over XPC.

- **FSKitBridge.app**
    - **UI / enablement only (Host):** Packages the extension. It’s not on the file system I/O path; it’s mainly for
      install/first-run enablement.
    - **FSKitExt.appex — sandboxed (AppeX):** The FSKit module (an ExtensionKit app extension) running as a **separate
      process** at runtime.
        - **FSUnaryFileSystem + Operations (FSOps):** Swift implementation of the FSKit protocols. Each VFS operation
          invoked by macOS is received here.

- **Backend (separate user process)**
    - **Custom.app — user process:** Your actual file system engine (e.g., Rust/Python/etc.). It exposes a TCP localhost
      service speaking a length-delimited Protobuf protocol.

- **Registration / enablement flow**
    - **Host → PKD:** On install/first launch, PlugInKit discovers the embedded extension and performs _election_. This
      makes your FSKit module available to the system.

- **Runtime IPC paths**
    - **VFS ⇄ FSOps via XPC:** At mount/runtime, macOS (FSKit host) calls your extension over XPC. This is the official
      FSKit path for all file system operations.
    - **FSOps ⇄ Backend via TCP (localhost):** The extension forwards operations to your backend over TCP using Protobuf
      and receives results/errors in reply.

- **Lifecycle management**
    - **PKD → AppeX:** PlugInKit/ExtensionKit launches, monitors, and (re)starts the extension as needed. The appex is
      **not** running inside the host app process.

> **Design choice:** TCP (localhost) allows a signed appex to talk to an unsigned backend without an App Group — unlike
> UNIX sockets, it doesn’t require a shared writable path.

## The wire contract: `protocol.proto`

- **Purpose:** a stable, language-neutral RPC schema between FSKitExt and your backend.
- **Contents:** request/response messages for common file system operations, attribute structures, error codes mapped to
  POSIX `errno`.
- **Framing:** `u32` length (network byte order) + protobuf bytes.

> Any language with protobuf support can be your backend.

## What’s in this repository?

- **FSKitBridge.app** — Host app  
  Purpose: bundle/ship the FSKit extension.

- **FSKitExt.appex** — FSKit module (ExtensionKit)  
  Implements FSKit operations and proxies them to the backend over a local socket.

> Both live in **this single repo** and are built together. The appex is inside the host app at
`FSKitBridge.app/Contents/Extensions/FSKitExt.appex`.

## How to use

### 1. Use it as-is

Download the ready-made app from [`Releases`](https://github.com/debox-network/FSKitBridge/releases) and install it.

#### Defaults

- **FSKit type:** `fskitbridge` (must match `mount -F -t fskitbridge …`)
- **TCP port:** `35367`

### 2. Customize file system type or port

Use the app as a template.

#### Edit `Info.plist` (appex target)

- **FSKit type:** set `FSFileSystemType`, `FSPersonalities → FSKitExtPersonality → FSName`, and `FSShortName` to
  `"yourfs"`.
- **TCP port:** set `Configuration → serverPort` to `"12345"` (a custom key consumed by the appex).

#### Rebuild & sign

- Build the app + appex in Xcode with your signing identities.
- Notarize for distribution.

### 3. Install

```bash
# Path to the built FSKitBridge.app you want to install.
APP="/path/to/FSKitBridge.app"

# Replace any existing installed copy.
rm -rf /Applications/FSKitBridge.app

# Copy the app bundle into the system Applications directory.
ditto "$APP" /Applications/FSKitBridge.app

# Clear quarantine only if the attribute is present.
if xattr -p com.apple.quarantine /Applications/FSKitBridge.app >/dev/null 2>&1; then
  xattr -dr com.apple.quarantine /Applications/FSKitBridge.app
fi

# Register the host app and embedded FSKit extension.
lsregister -f -R /Applications/FSKitBridge.app
pluginkit -a /Applications/FSKitBridge.app/Contents/Extensions/FSKitExt.appex
pluginkit -e use -p com.apple.fskit.fsmodule -i network.debox.fskitbridge.fskitext

# List all registered FSKit modules for verification.
pluginkit -m -Dvv -p com.apple.fskit.fsmodule
```

### 4. Enable extension

System Settings → General → Login Items & Extensions → **File System Extensions** → enable **fskitbridge**.

### 5. Run backend

Start your backend server on `127.0.0.1:35367` (or your configured port) before mounting.

### 6. Mount

```bash
# Ensure the mountpoint exists (sudo because /Volumes is system-owned).
sudo mkdir -p /Volumes/MyFS

# Create a sparse 1 MiB raw disk image.
mkfile -n 1m /tmp/fskitbridge.dmg

# Attach the image as a raw, *unmounted* device and capture the /dev/diskN path from hdiutil's output.
DEVICE=$(hdiutil attach -imagekey diskimage-class=CRawDiskImage -nomount /tmp/fskitbridge.dmg)

# Mount the file system using the type onto the mount point, passing the raw device we just attached.
mount -F -t fskitbridge "$DEVICE" /Volumes/MyFS

# Optional: show what got mounted for verification.
mount | grep "/Volumes/MyFS"
```

- **Mount point:** avoid TCC-protected folders (Documents/Desktop/Downloads). Prefer `/Volumes/<Name>`.
- **Ownership:** FSKit mounts run with `noowners`.

### 7. Unmount

```bash
# Force-unmount the file system from the mount point (ignore busy warnings).
umount -f /Volumes/MyFS

# Detach the virtual device created by hdiutil (frees the /dev/diskN handle).
hdiutil detach "$DEVICE"

# Delete the raw disk image.
rm -f /tmp/fskitbridge.dmg
```

### 8. Uninstall

```bash
# Best-effort unregister the embedded extension and host app.
pluginkit -r /Applications/FSKitBridge.app/Contents/Extensions/FSKitExt.appex || true
lsregister -u /Applications/FSKitBridge.app || true

# Remove the installed app bundle.
rm -rf /Applications/FSKitBridge.app

# Optional cleanup for local experiments.
rm -rf "$HOME/Library/Containers/network.debox.fskitbridge" \
       "$HOME/Library/Containers/network.debox.fskitbridge.fskitext" \
       "$HOME/Library/Application Scripts/network.debox.fskitbridge.fskitext"
```

## Tests

You can test your file system implementation using the **fstest** suite from the **secfs.test** collection (our fork
includes FSKit glue, so the suite can target your FSKit extension directly).

- **Repo & suite:** [`secfs.test`](https://github.com/debox-network/secfs.test), suite **fstest**
- **About fstest:** a port of FreeBSD **pjdfstest** for macOS/Linux

### Clone & build

```bash
git clone https://github.com/debox-network/secfs.test
cd secfs.test/fstest/fstest
make
```

### Configure

Edit the test config (e.g., `fstest/tests/conf`):

```ini
# Known file systems: UFS, ZFS, ext3, ext4, ntfs-3g, xfs, btrfs, glusterfs, HFS+, secfs, cgofuse, fskit
fs="fskit"    # target FSKit

# Feature flags (1 = supported, 0 = not supported)
fifo=0        # Set to 0. FSKit does not support FIFOs (named pipes).
hardlink=0    # FS-dependent. Set to 1 only if your backend implements hard links.
ownership=0   # Set to 0. FSKit extensions are mounted with 'noowners', so POSIX uid/gid ownership isn’t enforced.
xattr=0       # FS-dependent. Set to 1 only if your backend implements extended attributes.
```

### Run tests

```bash
cd /path/to/file/system/you/want/to/test/
sudo prove -r /path/to/fstest/
```

### Logs

`FSKitExt.appex` runs as a separate, system-managed process (launched by PlugInKit/ExtensionKit), so stdout/stderr from
the appex **won’t appear in your terminal**. Use Apple’s **Unified Logging** instead.

#### Live logs

```bash
log stream --info --debug --style syslog --predicate 'subsystem == "FSKitExt"'
```

#### Historical logs (last hour)

```bash
log show --last 1h --style syslog --predicate 'subsystem == "FSKitExt"'
```

#### Tips

- In Swift, log with Unified Logging so the predicate matches:
  ```swift
  import os
  let log = Logger(subsystem: "FSKitExt", category: "Volume")
  log.debug("mounted %{public}@", fsName)
  ```

- Your backend (Rust/others) is a normal user process — its stdout/stderr will appear in your terminal; this section is
  specifically about the appex.

## License

This project is dual-licensed under Apache-2.0 and MIT:

- Apache License, Version 2.0 — [`LICENSE-APACHE`](./LICENSE-APACHE)
- MIT License — [`LICENSE-MIT`](./LICENSE-MIT)

**Contributions:** Unless you explicitly state otherwise, any contribution intentionally submitted for inclusion in the
work shall be dual-licensed as above, without additional terms or conditions.
