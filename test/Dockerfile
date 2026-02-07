FROM alpine:3.21

RUN apk add --no-cache \
    bash bats coreutils iproute2 procps \
    transmission-daemon transmission-remote \
    util-linux net-tools curl busybox-extras grep sed

# Install bats-support + bats-assert libraries
RUN mkdir -p /opt/bats-libs && \
    wget -qO- https://github.com/bats-core/bats-support/archive/refs/tags/v0.3.0.tar.gz | tar xz -C /opt/bats-libs && \
    wget -qO- https://github.com/bats-core/bats-assert/archive/refs/tags/v2.1.0.tar.gz | tar xz -C /opt/bats-libs

# Copy production scripts to OpenWrt-expected paths
RUN mkdir -p /etc/hotplug.d/iface
COPY scripts/transmission-watchdog.sh /etc/transmission-watchdog.sh
COPY scripts/99-transmission-vpn      /etc/hotplug.d/iface/99-transmission-vpn
COPY scripts/transmission-diag.sh     /etc/transmission-diag.sh
RUN chmod +x /etc/transmission-watchdog.sh /etc/hotplug.d/iface/99-transmission-vpn /etc/transmission-diag.sh

# Patch RPC address for container testing (router IP → localhost)
RUN sed -i 's/192\.168\.8\.1:9091/127.0.0.1:9091/g' \
    /etc/transmission-watchdog.sh \
    /etc/hotplug.d/iface/99-transmission-vpn \
    /etc/transmission-diag.sh

# Rename real transmission-remote so the wrapper can delegate to it
RUN mv /usr/bin/transmission-remote /usr/bin/transmission-remote-real 2>/dev/null || true

# Copy mock tools and install under their real command names
COPY test/helpers/mock-uci.sh       /usr/local/bin/uci
COPY test/helpers/mock-nft.sh       /usr/local/bin/nft
COPY test/helpers/mock-logger.sh    /usr/local/bin/logger
COPY test/helpers/mock-logread.sh   /usr/local/bin/logread
COPY test/helpers/mock-ping.sh      /usr/local/bin/ping
COPY test/helpers/mock-crontab.sh   /usr/local/bin/crontab
COPY test/helpers/mock-netstat.sh   /usr/local/bin/netstat
COPY test/helpers/init-transmission.sh          /etc/init.d/transmission
COPY test/helpers/transmission-remote-wrapper.sh /usr/local/bin/transmission-remote
RUN chmod +x /usr/local/bin/* /etc/init.d/transmission

# Handle pgrep truncation: OpenWrt truncates process names to 15 chars
# (transmission-da), but Alpine uses the full binary name. Create a symlink
# so pgrep -x transmission-da matches.
RUN ln -sf /usr/bin/transmission-daemon /usr/bin/transmission-da

# Ensure PATH prefers /usr/local/bin (our mocks shadow real tools)
ENV PATH="/usr/local/bin:$PATH"

# Set up minimal Transmission config
RUN mkdir -p /etc/transmission /tmp/transmission && \
    echo '{"rpc-bind-address":"127.0.0.1","rpc-port":9091,"rpc-authentication-required":false,"download-dir":"/tmp/transmission"}' \
    > /etc/transmission/settings.json

# Copy test suite
COPY test/helpers/setup.bash /opt/test/helpers/setup.bash
COPY test/fixtures           /opt/test/fixtures
COPY test/tests              /opt/test/tests

WORKDIR /opt/test
ENTRYPOINT ["bats", "--tap", "tests/"]
