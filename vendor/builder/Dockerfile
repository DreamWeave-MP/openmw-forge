
FROM almalinux:9
# Build tooling belongs to the image layer, not every short-lived worker.
RUN dnf install -y epel-release dnf-plugins-core
RUN dnf config-manager --set-enabled crb
RUN dnf install -y git tar gzip p7zip zip unzip curl gcc-toolset-13 cmake ninja-build ccache \
    perl autoconf autoconf-archive automake libtool nasm pkgconfig mesa-libGL-devel \
    mesa-libEGL-devel libXcursor-devel libX11-devel libXft-devel libXext-devel \
    libxkbcommon-devel libxkbcommon-x11 wayland-devel texinfo gettext-devel \
    kernel-headers python3 python3-pip make binutils patch libstdc++ \
    libxcb xcb-util xcb-util-image xcb-util-keysyms xcb-util-wm \
    xcb-util-renderutil xcb-util-cursor && dnf clean all
# vcpkg requires Autoconf 2.72. Build it ONCE in the cached image rather than
# recompiling it in each disposable dependency worker. Verify before extraction.
RUN curl --fail --location --retry 3 -o /tmp/autoconf-2.72.tar.gz \
      https://ftp.gnu.org/gnu/autoconf/autoconf-2.72.tar.gz \
    && echo '3f71d459e2127ef2c98b37f11f5284f0c92318ad8d31c5b6034bed370adfe9f3d0f7a12f87e2efced06c11e2a159de4d4a292b751104e83daf11342f25ba9721  /tmp/autoconf-2.72.tar.gz' | sha512sum --check - \
    && tar xzf /tmp/autoconf-2.72.tar.gz -C /tmp \
    && cd /tmp/autoconf-2.72 && ./configure --prefix=/usr/local \
    && make -j2 && make install \
    && rm -rf /tmp/autoconf-2.72 /tmp/autoconf-2.72.tar.gz
