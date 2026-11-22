# mango 0.18.5 built as its own repository has it, run headless, to record what mango does.
#   docker build -t mango-facit Tests/MangoFacit/recorder
# The mango source is mounted at /mango (read-only) and built at the pinned commit by build.sh.
FROM fedora:45

RUN dnf -y -q install \
        gcc meson ninja-build git pkgconf python3 \
        wayland-devel wayland-protocols-devel \
        wlroots-devel scenefx-devel libinput-devel libxkbcommon-devel \
        pcre2-devel pixman-devel cjson-devel pango-devel libdrm-devel \
        mesa-dri-drivers \
    && dnf clean all

COPY facit-client.c build.sh record.py drm-shim.c /tool/
RUN gcc -shared -fPIC -I/usr/include/libdrm -o /tool/drm-shim.so /tool/drm-shim.c
