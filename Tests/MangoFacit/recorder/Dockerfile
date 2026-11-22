# mango 0.18.5 built as its own repository has it, run headless, to record what mango does.
#   docker build -t mango-facit Tests/MangoFacit/recorder
# The mango source is mounted at /mango (read-only) and built at the pinned commit by build.sh.
FROM fedora:45

RUN dnf -y -q install \
        gcc meson ninja-build git pkgconf python3 \
        wayland-devel wayland-protocols-devel \
        wlroots-devel scenefx-devel libinput-devel libxkbcommon-devel \
        pcre2-devel pixman-devel cjson-devel pango-devel libdrm-devel \
        mesa-dri-drivers cpio \
    && dnf clean all

# The virtual keyboard and pointer protocols, from wlrctl's sources (wlroots installs no XML of them).
RUN mkdir -p /tool/protocol && cd /tmp && dnf -q download --source wlrctl \
    && rpm2cpio wlrctl-*.src.rpm | cpio -idm --quiet \
    && tar xzf wlrctl-*.tar.gz --strip-components=2 -C /tool/protocol --wildcards \
        '*/protocol/virtual-keyboard-unstable-v1.xml' '*/protocol/wlr-virtual-pointer-unstable-v1.xml' \
    && rm -rf /tmp/*

COPY facit-client.c facit-input.c build.sh record.py drm-shim.c /tool/
RUN gcc -shared -fPIC -I/usr/include/libdrm -o /tool/drm-shim.so /tool/drm-shim.c
