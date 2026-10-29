# Vanilla Terraria dedicated server.
#
# TERRARIA_VERSION: "latest" or a release number such as 1449 or 1.4.4.9.
# TARGETARCH is supplied by Docker: amd64 runs Re-Logic's bundled native binary,
# arm64 runs TerrariaServer.exe under Mono.

FROM debian:trixie-slim AS download

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl unzip \
 && rm -rf /var/lib/apt/lists/*

ARG TERRARIA_VERSION=latest

# Fetched on every build; the layers below are only rebuilt when this list changes
# (i.e. when a new release comes out) or TERRARIA_VERSION changes.
ADD https://terraria.org/api/get/dedicated-servers-names /tmp/servers.json

RUN set -eu; \
    version="$(echo "$TERRARIA_VERSION" | tr -d '.')"; \
    if [ "$version" = "latest" ]; then \
        version="$(grep -o 'terraria-server-[0-9]*\.zip' /tmp/servers.json | head -n1 | tr -dc '0-9')"; \
        [ -n "$version" ] || { echo "ERROR: could not determine the latest Terraria version" >&2; exit 1; }; \
    fi; \
    echo "Downloading Terraria dedicated server $version"; \
    curl -fsSL -o /tmp/server.zip \
        "https://terraria.org/api/download/pc-dedicated-server/terraria-server-${version}.zip" \
    || { echo "ERROR: Terraria server version '$TERRARIA_VERSION' could not be downloaded - check the version number" >&2; exit 1; }; \
    unzip -q /tmp/server.zip -d /tmp/server; \
    mv /tmp/server/*/Linux /opt/terraria; \
    echo "$version" > /opt/terraria/VERSION


FROM debian:trixie-slim

ARG TARGETARCH

COPY --from=download /opt/terraria /opt/terraria

RUN set -eu; \
    case "$TARGETARCH" in \
    amd64) \
        chmod +x /opt/terraria/TerrariaServer.bin.x86_64 ;; \
    arm64) \
        apt-get update; \
        apt-get install -y --no-install-recommends \
            mono-runtime \
            libmono-i18n-west4.0-cil \
            libmono-posix4.0-cil \
            libmono-security4.0-cil \
            libmono-system-configuration4.0-cil \
            libmono-system-core4.0-cil \
            libmono-system-data4.0-cil \
            libmono-system-drawing4.0-cil \
            libmono-system-numerics4.0-cil \
            libmono-system-runtime-serialization4.0-cil \
            libmono-system-security4.0-cil \
            libmono-system-windows-forms4.0-cil \
            libmono-system-xml-linq4.0-cil \
            libmono-system-xml4.0-cil \
            libmono-windowsbase4.0-cil; \
        rm -rf /var/lib/apt/lists/*; \
        # Use the system Mono's framework instead of the x86_64 bundle.
        cd /opt/terraria; \
        rm -rf lib64 mscorlib.dll System*.dll Mono.*.dll I18N*.dll WindowsBase.dll \
               monoconfig monomachineconfig TerrariaServer TerrariaServer.bin.x86_64 ;; \
    *) \
        echo "ERROR: unsupported architecture '$TARGETARCH' (supported: amd64, arm64)" >&2; \
        exit 1 ;; \
    esac

COPY --chmod=755 entrypoint.sh /usr/local/bin/entrypoint.sh
COPY --chmod=755 console /usr/local/bin/console

EXPOSE 7777/tcp
VOLUME ["/data"]

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
