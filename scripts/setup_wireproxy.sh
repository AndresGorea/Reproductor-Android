#!/usr/bin/env bash
# setup_wireproxy.sh — instala windtf/wireproxy (userspace, sin TUN) y plantilla WireGuard.
set -euo pipefail

ARRMUX_ROOT="/opt/arrmux"
ARRMUX_ETC="/etc/arrmux"
ARRMUX_DATA="/var/lib/arrmux"
BIN_DIR="${ARRMUX_ROOT}/bin"
WIREPROXY_BIN="${BIN_DIR}/wireproxy"
WG_CONF="${ARRMUX_ETC}/wireproxy.conf"
TMP_DIR="/tmp/arrmux-dl"

log()  { echo "[setup_wireproxy] $*"; }
warn() { echo "[setup_wireproxy] ADVERTENCIA: $*" >&2; }
die()  { echo "[setup_wireproxy] ERROR: $*" >&2; exit 1; }

command -v curl >/dev/null 2>&1 || die "falta 'curl'. Instala con: apt install curl"
command -v tar >/dev/null 2>&1 || die "falta 'tar'."

mkdir -p "${BIN_DIR}" "${ARRMUX_ETC}" "${ARRMUX_DATA}/wireproxy" "${ARRMUX_DATA}/qbittorrent" "${TMP_DIR}"

ARCH="$(uname -m)"
case "${ARCH}" in
  aarch64|arm64) ASSET_PAT="linux_arm64.tar.gz" ;;
  x86_64) warn "x86_64 detectado (desarrollo); se descargará binario linux amd64."; ASSET_PAT="linux_amd64.tar.gz" ;;
  *) warn "Arquitectura ${ARCH} no reconocida; se intenta linux_arm64."; ASSET_PAT="linux_arm64.tar.gz" ;;
esac

if [ -x "${WIREPROXY_BIN}" ]; then
  log "wireproxy ya instalado en ${WIREPROXY_BIN} ($("${WIREPROXY_BIN}" --help 2>&1 | head -n1 || true)). Re-descargando para actualizar..."
fi

log "Resolviendo última release de windtf/wireproxy..."
JSON="$(curl -fsSL --max-time 30 https://api.github.com/repos/windtf/wireproxy/releases/latest)" || \
  die "No se pudo consultar releases de wireproxy (https://github.com/windtf/wireproxy/releases). Revisa red."
URL="$(echo "${JSON}" | grep -oiE '"browser_download_url": *"[^"]*'"${ASSET_PAT}"'[^"]*"' | head -n1 | cut -d'"' -f4)"
[ -n "${URL:-}" ] || die "Ningún asset coincide con '${ASSET_PAT}'."
log "Descargando ${URL} ..."
TARBALL="${TMP_DIR}/wireproxy.tar.gz"
curl -fSL --max-time 120 -o "${TARBALL}" "${URL}" || die "Falló la descarga de wireproxy."
tar -xzf "${TARBALL}" -C "${TMP_DIR}" || die "No se pudo extraer ${TARBALL}."
# El tarball contiene el binario 'wireproxy' en la raíz.
FOUND="$(find "${TMP_DIR}" -maxdepth 2 -name wireproxy -type f | head -n1)"
[ -n "${FOUND:-}" ] || die "El tarball no contiene el binario wireproxy."
install -m 0755 "${FOUND}" "${WIREPROXY_BIN}" || die "No se pudo instalar en ${WIREPROXY_BIN}."
rm -f "${TARBALL}"
log "wireproxy OK -> ${WIREPROXY_BIN}"

# --- Plantilla wireproxy.conf (NO sobrescribir) ---
if [ -f "${WG_CONF}" ]; then
  log "${WG_CONF} ya existe; no se sobrescribe. Edítalo con tus credenciales."
else
  log "Generando plantilla ${WG_CONF} ..."
  cat > "${WG_CONF}" <<'EOF'
# arrmux wireproxy — pega aquí los valores de tu .conf de Mullvad/ProtonVPN (WireGuard).
# Cómo obtenerlo:
#   Mullvad: https://mullvad.net -> WireGuard configuration -> genera clave y descarga .conf
#   ProtonVPN: cuenta -> Downloads -> WireGuard configuration
# Copia PrivateKey, Address, PublicKey, Endpoint y AllowedIPs a las secciones [Interface]/[Peer].
# wireproxy expone SOCKS5 en 127.0.0.1:1080 para qBittorrent (sin TUN/TAP/iptables).

[Interface]
PrivateKey = REEMPLAZAR_CON_TU_PRIVATE_KEY
Address = 10.x.x.x/32
DNS = 1.1.1.1

[Peer]
PublicKey = REEMPLAZAR_CON_PUBLIC_KEY_DEL_SERVIDOR
Endpoint = <servidor>.mullvad.net:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25

[Socks5]
BindAddress = 127.0.0.1:1080
EOF
  chmod 600 "${WG_CONF}"
  log "Plantilla creada en ${WG_CONF} (modo 600). Edítala antes de arrancar wireproxy."
fi

# --- Forzar qBittorrent a usar el proxy SOCKS5 ---
QBIT_CONF="${ARRMUX_DATA}/qbittorrent/qBittorrent/config/qBittorrent.conf"
if [ -f "${QBIT_CONF}" ]; then
  log "Ajustando proxy SOCKS5 en ${QBIT_CONF} (qBittorrent debe estar detenido)..."
  if grep -q "^\[Preferences\]" "${QBIT_CONF}"; then
    for kv in "Connection\ProxyType=2" "Connection\Proxy\IP=127.0.0.1" "Connection\Proxy\Port=1080" "Connection\Proxy\PeerConnections=true" "Connection\Proxy\HostnameLookup=true"; do
      key="${kv%%=*}"; val="${kv#*=}"
      if grep -q "^${key}=" "${QBIT_CONF}"; then
        sed -i "s|^${key}=.*|${key}=${val}|" "${QBIT_CONF}"
      else
        # Insertar bajo [Preferences]
        awk -v k="${key}=${val}" '{print} /^\[Preferences\]$/ {print k; added=1} END{}' "${QBIT_CONF}" > "${QBIT_CONF}.tmp" && mv "${QBIT_CONF}.tmp" "${QBIT_CONF}"
      fi
    done
    log "Proxy SOCKS5 configurado en ${QBIT_CONF}."
  else
    warn "${QBIT_CONF} no tiene sección [Preferences]; configúralo manual: Preferences -> Connection -> Proxy Server SOCKS5 127.0.0.1:1080."
  fi
else
  warn "Aún no existe ${QBIT_CONF} (se crea al primer arranque de qBittorrent)."
fi

cat <<'MSG'
[setup_wireproxy] MANUAL qBittorrent (si el ajuste automático no aplicó):
  1. Abre qBittorrent WebUI (http://<IP>:8081) -> Tools/Preferences -> Connection.
  2. Proxy Server: Type=SOCKS5, Host=127.0.0.1, Port=1080.
  3. Marca "Use proxy for peer connections" y "Use proxy for hostname lookup".
  4. Guarda. Todo el tráfico (tracker + peers) sale por el túnel WireGuard.
  5. Verifica con: arrmux vpn-check
MSG
log "OK."
