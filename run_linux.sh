#!/usr/bin/env bash
# Run on Linux with X11 backend to avoid Gdk-CRITICAL (gdk_device_get_source)
# when the cursor enters/leaves the window. On Wayland those warnings are harmless.
#
# If build fails with: Failed to find any of [ld.lld, ld] in .../snap/flutter/.../llvm-10/bin
# the Flutter snap ships an incomplete LLVM bin dir. Fix: install Flutter outside snap
# (git clone https://github.com/flutter/flutter.git + add .../flutter/bin to PATH), or see
# https://github.com/canonical/flutter-snap/issues/123
export GDK_BACKEND=x11
exec flutter run -d linux "$@"
