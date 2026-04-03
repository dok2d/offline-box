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

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DEPS_DIR="$REPO_ROOT/deps"

ERRORS=0
WARNINGS=()

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

warn() {
    WARNINGS+=("$1")
    echo -e "  ${YELLOW}[WARN]${NC} $1"
}

fail() {
    ERRORS=$((ERRORS + 1))
    echo -e "  ${RED}[FAIL]${NC} $1"
}

ok() {
    echo -e "  ${GREEN}[ok]${NC} $1"
}

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
SEARXNG_GIT_REF=$(get_var "$REPO_ROOT/ansible/roles/services/searxng/defaults/main.yml" "searxng_git_ref")
PAPERLESS_NGX_VERSION=$(get_var "$REPO_ROOT/ansible/roles/services/paperless-ngx/defaults/main.yml" "paperless_ngx_version")
JELLYFIN_VERSION=$(get_var "$REPO_ROOT/ansible/roles/services/jellyfin/defaults/main.yml" "jellyfin_version")
OSM_MBTILES_URL=$(get_var "$REPO_ROOT/ansible/roles/services/openstreetmap/defaults/main.yml" "openstreetmap_mbtiles_url")

ARCH="${ARCH:-amd64}"

download() {
    local url="$1" dest="$2"
    if [ -f "$dest" ]; then
        ok "$(basename "$dest") already exists"
        return 0
    fi
    echo "  [download] $url"
    mkdir -p "$(dirname "$dest")"
    local http_code
    http_code=$(curl -SL --retry 3 --retry-delay 5 -o "$dest" -w '%{http_code}' "$url" 2>/dev/null) || true
    if [ -f "$dest" ] && [ -s "$dest" ] && [[ "$http_code" =~ ^2 ]]; then
        ok "$(basename "$dest") (HTTP $http_code)"
        return 0
    else
        rm -f "$dest"
        fail "HTTP $http_code — $url"
        return 1
    fi
}

save_image() {
    local img="$1" dest="$2"
    echo "  [pull+save] $img"
    mkdir -p "$(dirname "$dest")"
    if command -v skopeo >/dev/null 2>&1; then
        if skopeo copy "docker://$img" "docker-archive:$dest:$img" 2>/dev/null; then
            ok "$img"
            return 0
        fi
    elif command -v podman >/dev/null 2>&1; then
        if podman pull "$img" 2>/dev/null && podman save -o "$dest" "$img" 2>/dev/null; then
            ok "$img"
            return 0
        fi
    elif command -v docker >/dev/null 2>&1; then
        if docker pull "$img" 2>/dev/null && docker save -o "$dest" "$img" 2>/dev/null; then
            ok "$img"
            return 0
        fi
    else
        fail "skopeo/podman/docker not found, cannot save $img"
        return 1
    fi
    rm -f "$dest"
    fail "could not pull/save $img"
    return 1
}

# Clone a git repo (shallow, single branch). Reusable for pip-installable projects.
clone_repo() {
    local url="$1" ref="$2" dest="$3"
    if [ -d "$dest" ]; then
        ok "$(basename "$dest") already cloned"
        return 0
    fi
    echo "  [git clone] $url (ref: $ref)"
    mkdir -p "$(dirname "$dest")"
    if git clone --depth 1 --single-branch --branch "$ref" "$url" "$dest" 2>/dev/null; then
        ok "$(basename "$dest") (ref: $ref)"
        return 0
    else
        rm -rf "$dest"
        fail "git clone failed — $url (ref: $ref)"
        return 1
    fi
}

download_pip_with_deps() {
    local dest_dir="$1"
    shift
    mkdir -p "$dest_dir"
    echo "  [pip download] $* (with dependencies)"
    if pip download --dest "$dest_dir" "$@" 2>/dev/null; then
        ok "pip packages: $*"
    elif python3 -m pip download --dest "$dest_dir" "$@" 2>/dev/null; then
        ok "pip packages: $*"
    else
        fail "pip download failed for: $* (install python3-pip)"
    fi
}

# Download npm package tarball directly from registry (no npm required)
download_npm_tarball() {
    local pkg="$1" version="$2" dest="$3"
    local url="https://registry.npmjs.org/${pkg}/-/${pkg}-${version}.tgz"
    download "$url" "$dest"
}

# ── Container base images ─────────────────────────────────────────

dl_images() {
    echo "==> Container base images"
    for img in "docker.io/library/debian:13-slim" "docker.io/library/ubuntu:22.04"; do
        local fname
        fname=$(echo "$img" | sed 's|[/:]|_|g').tar
        local dest="$DEPS_DIR/images/$fname"
        if [ -f "$dest" ]; then
            ok "$fname already exists"
            continue
        fi
        save_image "$img" "$dest" || true
    done
}

# ── Ansible Galaxy collection ─────────────────────────────────────

dl_ansible() {
    echo "==> Ansible Galaxy collection: containers.podman"
    local dest="$DEPS_DIR/ansible"
    mkdir -p "$dest"
    if ls "$dest"/containers-podman-*.tar.gz >/dev/null 2>&1; then
        ok "containers.podman already downloaded"
    else
        echo "  [download] containers.podman collection"
        if ansible-galaxy collection download -r "$REPO_ROOT/ansible/requirements.yml" -p "$dest" 2>/dev/null; then
            ok "containers.podman"
        else
            fail "ansible-galaxy download failed (install ansible)"
        fi
    fi
}

# ── Data files (large, optional) ──────────────────────────────────

dl_kiwix() {
    echo "==> Kiwix ZIM files"
    local dest="$DEPS_DIR/kiwix"
    local urls
    urls=$(get_list_var "$REPO_ROOT/ansible/roles/services/kiwix/defaults/main.yml" "kiwix_zim_urls")
    if [ -z "$urls" ]; then
        warn "no ZIM URLs configured"
        return 0
    fi
    while IFS= read -r url; do
        [ -z "$url" ] && continue
        download "$url" "$dest/$(basename "$url")" || true
    done <<< "$urls"
}

dl_openstreetmap() {
    echo "==> OpenStreetMap (tileserver-gl-light $TILESERVER_VERSION + MBTiles)"
    download_npm_tarball "tileserver-gl-light" "$TILESERVER_VERSION" \
        "$DEPS_DIR/openstreetmap/tileserver-gl-light-${TILESERVER_VERSION}.tgz" || true
    if [ -n "${OSM_MBTILES_URL:-}" ]; then
        download "$OSM_MBTILES_URL" "$DEPS_DIR/openstreetmap/$(basename "$OSM_MBTILES_URL")" || true
    else
        warn "openstreetmap_mbtiles_url is empty — set it in defaults or place .mbtiles manually"
    fi
}

# ── Service download functions ────────────────────────────────────

dl_nexus() {
    echo "==> Nexus $NEXUS_VERSION"
    download "https://download.sonatype.com/nexus/3/nexus-${NEXUS_VERSION}-linux-x86_64.tar.gz" \
        "$DEPS_DIR/nexus/nexus-${NEXUS_VERSION}-linux-x86_64.tar.gz" || true
}

dl_nextcloud() {
    echo "==> Nextcloud $NEXTCLOUD_VERSION"
    download "https://download.nextcloud.com/server/releases/nextcloud-${NEXTCLOUD_VERSION}.tar.bz2" \
        "$DEPS_DIR/nextcloud/nextcloud-${NEXTCLOUD_VERSION}.tar.bz2" || true
}

dl_gitea() {
    echo "==> Gitea $GITEA_VERSION"
    download "https://dl.gitea.com/gitea/${GITEA_VERSION}/gitea-${GITEA_VERSION}-linux-${ARCH}" \
        "$DEPS_DIR/gitea/gitea-${GITEA_VERSION}-linux-${ARCH}" || true
}

dl_vaultwarden() {
    echo "==> Vaultwarden $VAULTWARDEN_VERSION (Docker image)"
    local img="docker.io/vaultwarden/server:${VAULTWARDEN_VERSION}"
    local dest="$DEPS_DIR/images/vaultwarden_server_${VAULTWARDEN_VERSION}.tar"
    if [ -f "$dest" ]; then
        ok "$(basename "$dest") already exists"
        return 0
    fi
    save_image "$img" "$dest" || true
}

dl_syncthing() {
    echo "==> Syncthing $SYNCTHING_VERSION"
    download "https://github.com/syncthing/syncthing/releases/download/v${SYNCTHING_VERSION}/syncthing-linux-${ARCH}-v${SYNCTHING_VERSION}.tar.gz" \
        "$DEPS_DIR/syncthing/syncthing-linux-${ARCH}-v${SYNCTHING_VERSION}.tar.gz" || true
}

dl_opencloud() {
    echo "==> OpenCloud $OPENCLOUD_VERSION"
    download "https://github.com/opencloud-eu/opencloud/releases/download/v${OPENCLOUD_VERSION}/opencloud-${OPENCLOUD_VERSION}-linux-amd64" \
        "$DEPS_DIR/opencloud/opencloud-${OPENCLOUD_VERSION}-linux-amd64" || true
}

dl_mattermost() {
    echo "==> Mattermost $MATTERMOST_VERSION"
    download "https://releases.mattermost.com/${MATTERMOST_VERSION}/mattermost-${MATTERMOST_VERSION}-linux-${ARCH}.tar.gz" \
        "$DEPS_DIR/mattermost/mattermost-${MATTERMOST_VERSION}-linux-${ARCH}.tar.gz" || true
}

dl_dendrite() {
    echo "==> Dendrite $DENDRITE_VERSION (Docker image)"
    local img="docker.io/matrixdotorg/dendrite-monolith:v${DENDRITE_VERSION}"
    local dest="$DEPS_DIR/images/dendrite-monolith_v${DENDRITE_VERSION}.tar"
    if [ -f "$dest" ]; then
        ok "$(basename "$dest") already exists"
        return 0
    fi
    save_image "$img" "$dest" || true
}

dl_bigbluebutton() {
    echo "==> BigBlueButton $BBB_VERSION"
    local deb_url="https://ubuntu.bigbluebutton.org/focal-270/pool/main/b/bbb-web/bbb-web_${BBB_VERSION}-65_amd64.deb"
    local deb_dest="$DEPS_DIR/bigbluebutton/bbb-web.deb"
    local war_dest="$DEPS_DIR/bigbluebutton/bbb-web.war"

    if [ -f "$war_dest" ]; then
        ok "bbb-web.war already exists"
    else
        download "$deb_url" "$deb_dest" || true
        if [ -f "$deb_dest" ]; then
            echo "  [extract] bbb-web.war from .deb"
            local tmpdir
            tmpdir=$(mktemp -d)
            dpkg-deb -x "$deb_dest" "$tmpdir" 2>/dev/null
            local war
            war=$(find "$tmpdir" -name "bigbluebutton.war" -o -name "bbb-web.war" 2>/dev/null | head -1)
            if [ -z "$war" ]; then
                # bbb-web extracts to a directory, not a single WAR
                war=$(find "$tmpdir" -path "*/bbb-web/WEB-INF" -printf "%h\n" 2>/dev/null | head -1)
            fi
            if [ -n "$war" ] && [ -e "$war" ]; then
                cp -a "$war" "$war_dest"
                ok "bbb-web.war extracted"
            else
                # Copy whole bbb-web directory as fallback
                local webdir
                webdir=$(find "$tmpdir" -type d -name "bbb-web" | head -1)
                if [ -n "$webdir" ]; then
                    cp -a "$webdir" "$DEPS_DIR/bigbluebutton/bbb-web"
                    ok "bbb-web directory extracted from .deb"
                else
                    fail "could not find bbb-web.war in .deb"
                fi
            fi
            rm -rf "$tmpdir" "$deb_dest"
        fi
    fi

    # etherpad-lite is published as ep_etherpad-lite on npm
    download_npm_tarball "ep_etherpad-lite" "1.8.14" \
        "$DEPS_DIR/bigbluebutton/ep_etherpad-lite-1.8.14.tgz" || true
}

dl_jellyfin() {
    echo "==> Jellyfin $JELLYFIN_VERSION (GPG key)"
    download "https://repo.jellyfin.org/jellyfin_team.gpg.key" \
        "$DEPS_DIR/jellyfin/jellyfin_team.gpg.key" || true
}

dl_calibre_web() {
    echo "==> Calibre-web $CALIBRE_WEB_VERSION"
    download_pip_with_deps "$DEPS_DIR/calibre-web" "calibreweb==${CALIBRE_WEB_VERSION}" || true
}

dl_searxng() {
    echo "==> SearXNG (git: $SEARXNG_GIT_REF)"
    clone_repo "https://github.com/searxng/searxng.git" "$SEARXNG_GIT_REF" \
        "$DEPS_DIR/searxng/searxng-src" || true
}

dl_paperless_ngx() {
    echo "==> Paperless-NGX $PAPERLESS_NGX_VERSION"
    clone_repo "https://github.com/paperless-ngx/paperless-ngx.git" "v${PAPERLESS_NGX_VERSION}" \
        "$DEPS_DIR/paperless-ngx/paperless-ngx-src" || true
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
        fail "Unknown service: $svc (available: ${ALL_SERVICES[*]})"
        echo ""
    fi
done

echo "===================================="

if [ ${#WARNINGS[@]} -gt 0 ]; then
    echo ""
    echo -e "${YELLOW}Warnings (${#WARNINGS[@]}):${NC}"
    for w in "${WARNINGS[@]}"; do
        echo -e "  ${YELLOW}!${NC} $w"
    done
fi

if [ "$ERRORS" -gt 0 ]; then
    echo ""
    echo -e "${RED}>>> $ERRORS download(s) FAILED. Review errors above. <<<${NC}"
    echo ""
    echo "To prepare for offline deployment:"
    echo "  1. Fix failed downloads and re-run the script"
    echo "  2. Load base images:   podman load -i deps/images/docker.io_library_debian_13-slim.tar"
    echo "  3. Install collection: ansible-galaxy collection install deps/ansible/containers-podman-*.tar.gz"
    echo "  4. Set offline_mode: true in ansible/group_vars/all.yml"
    exit 1
else
    echo ""
    echo -e "${GREEN}All downloads completed successfully.${NC}"
    echo ""
    echo "To prepare for offline deployment:"
    echo "  1. Load base images:   podman load -i deps/images/docker.io_library_debian_13-slim.tar"
    echo "  2. Install collection: ansible-galaxy collection install deps/ansible/containers-podman-*.tar.gz"
    echo "  3. Set offline_mode: true in ansible/group_vars/all.yml"
fi
