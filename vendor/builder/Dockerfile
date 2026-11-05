
FROM almalinux/9-base:9.6-20251117
# AlmaLinux 9.7 backported GLIBC_2.35 symbols while still identifying as
# glibc 2.34. Build against the older 9.6 ABI to support the whole EL9 family.
# The base image tag alone does not pin DNF: the default repositories float.
# Keep BaseOS, AppStream, CRB and Extras on the same historical snapshot.
RUN rm -f /etc/yum.repos.d/*.repo \
    && printf '%s\n' \
      '[baseos]' 'name=AlmaLinux 9.6 BaseOS' 'baseurl=https://vault.almalinux.org/9.6/BaseOS/$basearch/os/' 'enabled=1' 'gpgcheck=1' 'gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-AlmaLinux-9' \
      '[appstream]' 'name=AlmaLinux 9.6 AppStream' 'baseurl=https://vault.almalinux.org/9.6/AppStream/$basearch/os/' 'enabled=1' 'gpgcheck=1' 'gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-AlmaLinux-9' \
      '[crb]' 'name=AlmaLinux 9.6 CRB' 'baseurl=https://vault.almalinux.org/9.6/CRB/$basearch/os/' 'enabled=0' 'gpgcheck=1' 'gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-AlmaLinux-9' \
      '[extras]' 'name=AlmaLinux 9.6 Extras' 'baseurl=https://vault.almalinux.org/9.6/extras/$basearch/os/' 'enabled=1' 'gpgcheck=1' 'gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-AlmaLinux-9' \
      > /etc/yum.repos.d/forge-almalinux-9.6.repo
# Build tooling belongs to the image layer, not every short-lived worker.
RUN dnf install -y epel-release dnf-plugins-core
RUN dnf config-manager --set-enabled crb
# AlmaLinux 9 ships curl-minimal; full curl conflicts with the base RPM.
RUN dnf install -y git tar gzip p7zip zip unzip curl-minimal gcc-toolset-13 cmake ninja-build ccache \
    perl autoconf autoconf-archive automake libtool nasm pkgconfig mesa-libGL-devel \
    mesa-libEGL-devel libXcursor-devel libX11-devel libXft-devel libXext-devel \
    libxkbcommon-devel libxkbcommon-x11 wayland-devel texinfo gettext-devel \
    kernel-headers python3 python3-pip make binutils patch libstdc++ \
    libxcb xcb-util xcb-util-image xcb-util-keysyms xcb-util-wm \
    xcb-util-renderutil xcb-util-cursor && dnf clean all
# Fail the image build if repository drift reintroduces the newer glibc ABI.
RUN readelf --version-info /lib64/libc.so.6 > /tmp/forge-glibc-versions.txt \
    && ! grep -q 'GLIBC_2.35' /tmp/forge-glibc-versions.txt \
    && rm /tmp/forge-glibc-versions.txt
# vcpkg requires Autoconf 2.72. Build it ONCE in the cached image rather than
# recompiling it in each disposable dependency worker. Verify before extraction.
RUN curl --fail --location --retry 3 -o /tmp/autoconf-2.72.tar.gz \
      https://ftp.gnu.org/gnu/autoconf/autoconf-2.72.tar.gz \
    && echo '3f71d459e2127ef2c98b37f11f5284f0c92318ad8d31c5b6034bed370adfe9f3d0f7a12f87e2efced06c11e2a159de4d4a292b751104e83daf11342f25ba9721  /tmp/autoconf-2.72.tar.gz' | sha512sum --check - \
    && tar xzf /tmp/autoconf-2.72.tar.gz -C /tmp \
    && cd /tmp/autoconf-2.72 && ./configure --prefix=/usr/local \
    && make -j2 && make install \
    && rm -rf /tmp/autoconf-2.72 /tmp/autoconf-2.72.tar.gz
