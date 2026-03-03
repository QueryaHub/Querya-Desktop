#!/usr/bin/env bash
# Run on Linux with X11 backend to avoid Gdk-CRITICAL (gdk_device_get_source)
# when the cursor enters/leaves the window. On Wayland those warnings are harmless.
export GDK_BACKEND=x11
exec flutter run -d linux "$@"
