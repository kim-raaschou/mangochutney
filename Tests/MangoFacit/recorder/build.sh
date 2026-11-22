#!/bin/sh
# Builds mango at the pinned commit and the test client into /build (a volume, kept between runs).
set -e
COMMIT=21f80a9   # mango 0.18.5, the version the port follows (CLAUDE.md)

if [ ! -x /build/mango/build/mango ] || [ "$(cat /build/commit 2>/dev/null)" != "$COMMIT" ]; then
    rm -rf /build/mango
    git clone -q /mango /build/mango
    git -C /build/mango checkout -q "$COMMIT"
    meson setup -Dxwayland=disabled /build/mango/build /build/mango >/dev/null
    ninja -C /build/mango/build >/dev/null
    echo "$COMMIT" > /build/commit
fi

if [ ! -x /build/facit-client ] || [ /tool/facit-client.c -nt /build/facit-client ]; then
    proto=$(pkg-config --variable=pkgdatadir wayland-protocols)/stable/xdg-shell/xdg-shell.xml
    wayland-scanner client-header "$proto" /build/xdg-shell-client-protocol.h
    wayland-scanner private-code "$proto" /build/xdg-shell-protocol.c
    gcc -O1 -I/build -o /build/facit-client /tool/facit-client.c /build/xdg-shell-protocol.c -lwayland-client
fi
