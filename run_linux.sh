#!/usr/bin/env bash
# Run on Linux with X11 backend to avoid Gdk-CRITICAL (gdk_device_get_source)
# when the cursor enters/leaves the window. On Wayland those warnings are harmless.
#
# If build fails with: Failed to find any of [ld.lld, ld] in .../snap/flutter/.../llvm-10/bin
# the Flutter snap ships an incomplete LLVM bin dir. Fix: install Flutter outside snap
# (git clone https://github.com/flutter/flutter.git + add .../flutter/bin to PATH), or see
# https://github.com/canonical/flutter-snap/issues/123
#
# flutter_secure_storage_linux needs libsecret headers at compile time.
if ! pkg-config --exists libsecret-1 2>/dev/null; then
  echo "Querya Linux build requires libsecret-1 (CMake: libsecret-1>=0.18.4)." >&2
  echo "Install development package, then retry:" >&2
  echo "  Debian/Ubuntu: sudo apt-get install libsecret-1-dev" >&2
  echo "  Fedora/RHEL:   sudo dnf install libsecret-devel" >&2
  echo "  Arch:          sudo pacman -S libsecret" >&2
  exit 1
fi

export GDK_BACKEND=x11
exec flutter run -d linux "$@"
