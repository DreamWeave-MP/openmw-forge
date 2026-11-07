FROM almalinux/9-base:9.5-20250519
# The 9.7 glibc 2.34 backport exports selected GLIBC_2.35 symbols that
# pre-backport EL9 installations lack. A dated base tag is not enough: DNF
# repositories float unless all AlmaLinux channels are pinned as well.
# The 9.5 vault predates this backport and contains GCC Toolset 13.
RUN rm -f /etc/yum.repos.d/*.repo \
    && printf '%s\n' \
      '[baseos]' 'name=AlmaLinux 9.5 BaseOS' 'baseurl=https://vault.almalinux.org/9.5/BaseOS/$basearch/os/' 'enabled=1' 'gpgcheck=1' 'gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-AlmaLinux-9' \
      '[appstream]' 'name=AlmaLinux 9.5 AppStream' 'baseurl=https://vault.almalinux.org/9.5/AppStream/$basearch/os/' 'enabled=1' 'gpgcheck=1' 'gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-AlmaLinux-9' \
      '[crb]' 'name=AlmaLinux 9.5 CRB' 'baseurl=https://vault.almalinux.org/9.5/CRB/$basearch/os/' 'enabled=0' 'gpgcheck=1' 'gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-AlmaLinux-9' \
      '[extras]' 'name=AlmaLinux 9.5 Extras' 'baseurl=https://vault.almalinux.org/9.5/extras/$basearch/os/' 'enabled=1' 'gpgcheck=1' 'gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-AlmaLinux-9' \
      > /etc/yum.repos.d/forge-almalinux-9.5.repo
# Preflight BEFORE provisioning the full C++ toolchain or building Autoconf.
# Some older EL9 glibc RPMs already define a GLIBC_2.35 version node.
# Version-node greps incorrectly reject those historical builds. Instead,
# reject *defined* exports of the specific RHEL 9.7 backported functions that
# introduced the portability regression. The SDK/release ABI scanner still
# rejects EVERY imported GLIBC version greater than 2.34, not just these names.
# nm is provided by binutils. The RPM identifiers are logged for diagnosis.
RUN dnf install -y binutils \
    && rpm -q glibc glibc-common \
    && nm -D --defined-only /lib64/libc.so.6 /lib64/ld-linux-x86-64.so.2 > /tmp/forge-glibc-exports.txt \
    && if grep -E '(^|[[:space:]])(__epoll_pwait2_time64|__memcmpeq|_dl_find_object|epoll_pwait2|posix_spawn_file_actions_addtcsetpgrp_np|posix_spawnattr_tcgetpgrp_np|posix_spawnattr_tcsetpgrp_np)@{1,2}GLIBC_2[.]35($|[[:space:]])' /tmp/forge-glibc-exports.txt; then \
         echo 'ERROR: builder libc exposes post-baseline GLIBC_2.35 function exports'; \
         exit 1; \
       fi \
    && rm /tmp/forge-glibc-exports.txt
# Build tooling belongs to the image layer, not every short-lived worker.
RUN dnf install -y epel-release dnf-plugins-core
RUN dnf config-manager --set-enabled crb
# AlmaLinux 9 ships curl-minimal; full curl conflicts with the base RPM.
RUN dnf install -y git tar gzip p7zip zip unzip curl-minimal gcc-toolset-13 cmake ninja-build ccache \
    perl autoconf autoconf-archive automake libtool nasm pkgconfig mesa-libGL-devel \
    mesa-libEGL-devel vulkan-loader-devel libXcursor-devel libX11-devel libXft-devel libXext-devel \
    libxkbcommon-devel libxkbcommon-x11 wayland-devel texinfo gettext-devel \
    kernel-headers python3 python3-pip make patch libstdc++ \
    libxcb xcb-util xcb-util-image xcb-util-keysyms xcb-util-wm \
    xcb-util-renderutil xcb-util-cursor && dnf clean all
# Verify again after all DNF transactions: later installs must not replace
# libc with the specific RHEL 9.7 GLIBC_2.35 backport exports.
RUN rpm -q glibc glibc-common \
    && nm -D --defined-only /lib64/libc.so.6 /lib64/ld-linux-x86-64.so.2 > /tmp/forge-glibc-exports.txt \
    && if grep -E '(^|[[:space:]])(__epoll_pwait2_time64|__memcmpeq|_dl_find_object|epoll_pwait2|posix_spawn_file_actions_addtcsetpgrp_np|posix_spawnattr_tcgetpgrp_np|posix_spawnattr_tcsetpgrp_np)@{1,2}GLIBC_2[.]35($|[[:space:]])' /tmp/forge-glibc-exports.txt; then \
         echo 'ERROR: C++ toolchain provisioning introduced post-baseline GLIBC_2.35 exports'; \
         exit 1; \
       fi \
    && rm /tmp/forge-glibc-exports.txt
# vcpkg requires Autoconf 2.72. Build it ONCE in the cached image rather than
# recompiling it in each disposable dependency worker. Verify before extraction.
RUN curl --fail --location --retry 3 -o /tmp/autoconf-2.72.tar.gz \
      https://ftp.gnu.org/gnu/autoconf/autoconf-2.72.tar.gz \
    && echo '3f71d459e2127ef2c98b37f11f5284f0c92318ad8d31c5b6034bed370adfe9f3d0f7a12f87e2efced06c11e2a159de4d4a292b751104e83daf11342f25ba9721  /tmp/autoconf-2.72.tar.gz' | sha512sum --check - \
    && tar xzf /tmp/autoconf-2.72.tar.gz -C /tmp \
    && cd /tmp/autoconf-2.72 && ./configure --prefix=/usr/local \
    && make -j2 && make install \
    && rm -rf /tmp/autoconf-2.72 /tmp/autoconf-2.72.tar.gz
