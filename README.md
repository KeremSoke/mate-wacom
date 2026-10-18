# MATE Graphics Tablet

A GTK 3/Vala graphics tablet settings window for MATE. Uses the `xsetwacom` utility to
read and apply X11 Wacom driver settings.

## Build and run

Requires GTK 3, GLib/GIO, Vala, Meson, `xsetwacom`, and `xrandr`.

```sh
meson setup build
meson compile -C build
./build/mate-wacom-properties
```

Install with `meson install -C build`. The desktop entry appears in MATE's
hardware settings and program requires an X11 session.
