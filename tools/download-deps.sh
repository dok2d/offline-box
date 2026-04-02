#!/usr/bin/env bash
# download-deps.sh — Pre-download all binary dependencies for offline builds.
#
# Usage:
#   ./tools/download-deps.sh              # download all deps
#   ./tools/download-deps.sh nexus gitea  # download specific services only
#
# Dependencies are saved to deps/<service>/ relative to the repo root.
# After downloading, set offline_mode: true in ansible/group_vars/all.yml
# to build containers from local files instead of fetching from the internet.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DEPS_DIR="$REPO_ROOT/deps"

# Source versions from ansible defaults (parse YAML simply)
get_var() {
    local file="$1" key="$2"
    grep "^${key}:" "$file" | head -1 | sed 's/^[^:]*:[[:space:]]*//' | tr -d '"' | tr -d "'"
}

# Parse YAML list values (e.g. kiwix_zim_urls)
get_list_var() {
    local file="$1" key="$2"
    sed -n "/^${key}:/,/^[^ ]/p" "$file" | grep '^\s*-' | sed 's/^\s*-\s*//' | tr -d '"' | tr -d "'"
}

# Service versions
NEXUS_VERSION=$(get_var "$REPO_ROOT/ansible/roles/services/nexus/defaults/main.yml" "nexus_version")
NEXTCLOUD_VERSION=$(get_var "$REPO_ROOT/ansible/roles/services/nextcloud/defaults/main.yml" "nextcloud_version")
GITEA_VERSION=$(get_var "$REPO_ROOT/ansible/roles/services/gitea/defaults/main.yml" "gitea_version")
VAULTWARDEN_VERSION=$(get_var "$REPO_ROOT/ansible/roles/services/vaultwarden/defaults/main.yml" "vaultwarden_version")
SYNCTHING_VERSION=$(get_var "$REPO_ROOT/ansible/roles/services/syncthing/defaults/main.yml" "syncthing_version")
OPENCLOUD_VERSION=$(get_var "$REPO_ROOT/ansible/roles/services/opencloud/defaults/main.yml" "opencloud_version")
MATTERMOST_VERSION=$(get_var "$REPO_ROOT/ansible/roles/services/mattermost/defaults/main.yml" "mattermost_version")
DENDRITE_VERSION=$(get_var "$REPO_ROOT/ansible/roles/services/dendrite/defaults/main.yml" "dendrite_version")
BBB_VERSION=$(get_var "$REPO_ROOT/ansible/roles/services/bigbluebutton/defaults/main.yml" "bigbluebutton_version")
TILESERVER_VERSION=$(get_var "$REPO_ROOT/ansible/roles/services/openstreetmap/defaults/main.yml" "tileserver_gl_version")
CALIBRE_WEB_VERSION=$(get_var "$REPO_ROOT/ansible/roles/services/calibre-web/defaults/main.yml" "calibre_web_version")
SEARXNG_VERSION=$(get_var "$REPO_ROOT/ansible/roles/services/searxng/defaults/main.yml" "searxng_version")
PAPERLESS_NGX_VERSION=$(get_var "$REPO_ROOT/ansible/roles/services/paperless-ngx/defaults/main.yml" "paperless_ngx_version")
JELLYFIN_VERSION=$(get_var "$REPO_ROOT/ansible/roles/services/jellyfin/defaults/main.yml" "jellyfin_version")
OSM_MBTILES_URL=$(get_var "$REPO_ROOT/ansible/roles/services/openstreetmap/defaults/main.yml" "openstreetmap_mbtiles_url")

ARCH="${ARCH:-amd64}"

download() {
    local url="$1" dest="$2"
    if [ -f "$dest" ]; then
        echo "  [skip] $(basename "$dest") already exists"
        return 0
    fi
    echo "  [download] $url"
    mkdir -p "$(dirname "$dest")"
    curl -fSL --retry 3 --retry-delay 5 -o "$dest" "$url"
}

save_image() {
    local img="$1" dest="$2"
    echo "  [pull+save] $img"
    mkdir -p "$(dirname "$dest")"
    if command -v skopeo >/dev/null 2>&1; then
        skopeo copy "docker://$img" "docker-archive:$dest:$img"
    elif command -v podman >/dev/null 2>&1; then
        podman pull "$img" && podman save -o "$dest" "$img"
    elif command -v docker >/dev/null 2>&1; then
        docker pull "$img" && docker save -o "$dest" "$img"
    else
        echo "  [error] skopeo/podman/docker not found, cannot save $img"
        return 1
    fi
}

download_pip_with_deps() {
    local dest_dir="$1"
    shift
    mkdir -p "$dest_dir"
    echo "  [pip download] $* (with dependencies)"
    pip download --dest "$dest_dir" "$@" 2>/dev/null || \
    python3 -m pip download --dest "$dest_dir" "$@" 2>/dev/null || \
    echo "  [warn] pip download failed for: $* (install python3-pip to download pip packages)"
}

download_npm_package() {
    local dest_dir="$1" pkg="$2"
    mkdir -p "$dest_dir"
    echo "  [npm pack] $pkg"
    (cd "$dest_dir" && npm pack "$pkg" 2>/dev/null) || \
    echo "  [warn] npm pack failed for: $pkg (install npm to download npm packages)"
}

# ── Container base images ─────────────────────────────────────────

dl_images() {
    echo "==> Container base images"
    for img in "docker.io/library/debian:13-slim" "docker.io/library/ubuntu:22.04"; do
        local fname
        fname=$(echo "$img" | sed 's|[/:]|_|g').tar
        local dest="$DEPS_DIR/images/$fname"
        if [ -f "$dest" ]; then
            echo "  [skip] $fname already exists"
            continue
        fi
        save_image "$img" "$dest"
    done
}

# ── Ansible Galaxy collection ─────────────────────────────────────

dl_ansible() {
    echo "==> Ansible Galaxy collection: containers.podman"
    local dest="$DEPS_DIR/ansible"
    mkdir -p "$dest"
    if ls "$dest"/containers-podman-*.tar.gz >/dev/null 2>&1; then
        echo "  [skip] containers.podman already downloaded"
    else
        echo "  [download] containers.podman collection"
        ansible-galaxy collection download -r "$REPO_ROOT/ansible/requirements.yml" -p "$dest" 2>/dev/null || \
        echo "  [warn] ansible-galaxy download failed (install ansible to download collections)"
    fi
}

# ── Data files (large, optional) ──────────────────────────────────

dl_kiwix() {
    echo "==> Kiwix ZIM files"
    local dest="$DEPS_DIR/kiwix"
    local urls
    urls=$(get_list_var "$REPO_ROOT/ansible/roles/services/kiwix/defaults/main.yml" "kiwix_zim_urls")
    if [ -z "$urls" ]; then
        echo "  [skip] no ZIM URLs configured"
        return 0
    fi
    while IFS= read -r url; do
        [ -z "$url" ] && continue
        download "$url" "$dest/$(basename "$url")"
    done <<< "$urls"
}

dl_openstreetmap() {
    echo "==> OpenStreetMap (tileserver-gl-light $TILESERVER_VERSION + MBTiles)"
    download_npm_package "$DEPS_DIR/openstreetmap" "tileserver-gl-light@${TILESERVER_VERSION}"
    if [ -n "${OSM_MBTILES_URL:-}" ]; then
        download "$OSM_MBTILES_URL" "$DEPS_DIR/openstreetmap/$(basename "$OSM_MBTILES_URL")"
    fi
}

# ── Service download functions ────────────────────────────────────

dl_nexus() {
    echo "==> Nexus $NEXUS_VERSION"
    download "https://download.sonatype.com/nexus/3/nexus-${NEXUS_VERSION}-unix.tar.gz" \
        "$DEPS_DIR/nexus/nexus-${NEXUS_VERSION}-unix.tar.gz"
}

dl_nextcloud() {
    echo "==> Nextcloud $NEXTCLOUD_VERSION"
    download "https://download.nextcloud.com/server/releases/nextcloud-${NEXTCLOUD_VERSION}.tar.bz2" \
        "$DEPS_DIR/nextcloud/nextcloud-${NEXTCLOUD_VERSION}.tar.bz2"
}

dl_gitea() {
    echo "==> Gitea $GITEA_VERSION"
    download "https://dl.gitea.com/gitea/${GITEA_VERSION}/gitea-${GITEA_VERSION}-linux-${ARCH}" \
        "$DEPS_DIR/gitea/gitea-${GITEA_VERSION}-linux-${ARCH}"
}

dl_vaultwarden() {
    echo "==> Vaultwarden $VAULTWARDEN_VERSION (Docker image)"
    local img="docker.io/vaultwarden/server:${VAULTWARDEN_VERSION}"
    local dest="$DEPS_DIR/images/vaultwarden_server_${VAULTWARDEN_VERSION}.tar"
    if [ -f "$dest" ]; then
        echo "  [skip] $(basename "$dest") already exists"
        return 0
    fi
    save_image "$img" "$dest"
}

dl_syncthing() {
    echo "==> Syncthing $SYNCTHING_VERSION"
    download "https://github.com/syncthing/syncthing/releases/download/v${SYNCTHING_VERSION}/syncthing-linux-${ARCH}-v${SYNCTHING_VERSION}.tar.gz" \
        "$DEPS_DIR/syncthing/syncthing-linux-${ARCH}-v${SYNCTHING_VERSION}.tar.gz"
}

dl_opencloud() {
    echo "==> OpenCloud $OPENCLOUD_VERSION"
    download "https://github.com/opencloud-eu/opencloud/releases/download/v${OPENCLOUD_VERSION}/opencloud-${OPENCLOUD_VERSION}-linux-amd64" \
        "$DEPS_DIR/opencloud/opencloud-${OPENCLOUD_VERSION}-linux-amd64"
}

dl_mattermost() {
    echo "==> Mattermost $MATTERMOST_VERSION"
    download "https://releases.mattermost.com/${MATTERMOST_VERSION}/mattermost-${MATTERMOST_VERSION}-linux-${ARCH}.tar.gz" \
        "$DEPS_DIR/mattermost/mattermost-${MATTERMOST_VERSION}-linux-${ARCH}.tar.gz"
}

dl_dendrite() {
    echo "==> Dendrite $DENDRITE_VERSION (Docker image)"
    local img="docker.io/matrixdotorg/dendrite-monolith:v${DENDRITE_VERSION}"
    local dest="$DEPS_DIR/images/dendrite-monolith_v${DENDRITE_VERSION}.tar"
    if [ -f "$dest" ]; then
        echo "  [skip] $(basename "$dest") already exists"
        return 0
    fi
    save_image "$img" "$dest"
}

dl_bigbluebutton() {
    echo "==> BigBlueButton $BBB_VERSION"
    download "https://github.com/bigbluebutton/bigbluebutton/releases/download/v${BBB_VERSION}.0/bbb-web.war" \
        "$DEPS_DIR/bigbluebutton/bbb-web.war"
    echo "  [npm pack] etherpad-lite"
    download_npm_package "$DEPS_DIR/bigbluebutton" "etherpad-lite"
}

dl_jellyfin() {
    echo "==> Jellyfin $JELLYFIN_VERSION (GPG key)"
    download "https://repo.jellyfin.org/jellyfin_team.gpg.key" \
        "$DEPS_DIR/jellyfin/jellyfin_team.gpg.key"
}

dl_calibre_web() {
    echo "==> Calibre-web $CALIBRE_WEB_VERSION"
    download_pip_with_deps "$DEPS_DIR/calibre-web" "calibreweb==${CALIBRE_WEB_VERSION}"
}

dl_searxng() {
    echo "==> SearXNG $SEARXNG_VERSION"
    download_pip_with_deps "$DEPS_DIR/searxng" "searxng==${SEARXNG_VERSION}"
}

dl_paperless_ngx() {
    echo "==> Paperless-NGX $PAPERLESS_NGX_VERSION"
    download_pip_with_deps "$DEPS_DIR/paperless-ngx" "paperless-ngx==${PAPERLESS_NGX_VERSION}" "gunicorn" "uvicorn"
}

# ── Main ──────────────────────────────────────────────────────────

ALL_SERVICES=(
    images ansible
    nexus nextcloud gitea vaultwarden syncthing opencloud
    mattermost dendrite bigbluebutton jellyfin openstreetmap
    kiwix calibre_web searxng paperless_ngx
)

# Determine which services to download
if [ $# -eq 0 ]; then
    SERVICES=("${ALL_SERVICES[@]}")
else
    SERVICES=("$@")
fi

echo "Offline Box — Dependency Downloader"
echo "===================================="
echo "Target directory: $DEPS_DIR"
echo "Architecture: $ARCH"
echo ""

for svc in "${SERVICES[@]}"; do
    # Normalize service names (allow both - and _)
    func_name="dl_$(echo "$svc" | tr '-' '_')"
    if declare -f "$func_name" > /dev/null 2>&1; then
        $func_name
        echo ""
    else
        echo "[error] Unknown service: $svc"
        echo "Available services: ${ALL_SERVICES[*]}"
        exit 1
    fi
done

echo "===================================="
echo "To prepare for offline deployment:"
echo "  1. Load base images:  podman load -i deps/images/docker.io_library_debian_13-slim.tar"
echo "  2. Install collection: ansible-galaxy collection install deps/ansible/containers-podman-*.tar.gz"
echo "  3. Set offline_mode: true in ansible/group_vars/all.yml"
echo ""
echo "Done!"
