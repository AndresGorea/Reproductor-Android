#!/usr/bin/env bash
# install.sh — instalador maestro de arrmux (idempotente: re-ejecutar = update/repair sin borrar datos).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARRMUX_ROOT="/opt/arrmux"
ARRMUX_ETC="/etc/arrmux"
ARRMUX_DATA="/var/lib/arrmux"
ARRMUX_LOG="/var/log/arrmux"
SERVICES_DIR="${ARRMUX_ETC}/services"

log()  { echo "[install] $*"; }
warn() { echo "[install] ADVERTENCIA: $*" >&2; }
die()  { echo "[install] ERROR: $*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "Ejecuta como root (o sudo): necesita escribir en /opt /etc /var y apt."

# --- 1. Dependencias ---
log "Comprobando dependencias: curl tar python3-venv supervisor..."
MISSING=""
for pkg in curl tar python3 git; do
  command -v "$pkg" >/dev/null 2>&1 || MISSING="${MISSING} ${pkg}"
done
if ! python3 -c "import venv" 2>/dev/null; then
  MISSING="${MISSING} python3-venv"
fi
if ! command -v supervisord >/dev/null 2>&1; then
  MISSING="${MISSING} supervisor"
fi
if [ -n "${MISSING}" ]; then
  warn "Faltan:${MISSING}"
  echo "[install] Instala con: apt update && apt install -y curl tar git python3 python3-venv supervisor qbittorrent-nox"
  die "Instala las dependencias y re-ejecuta ./install.sh"
fi
command -v qbittorrent-nox >/dev/null 2>&1 || \
  warn "qbittorrent-nox no encontrado. Instala con: apt install -y qbittorrent-nox"

# --- 2. Directorios base ---
log "Creando ${ARRMUX_ROOT} ${ARRMUX_ETC} ${ARRMUX_DATA} ${ARRMUX_LOG}..."
mkdir -p "${ARRMUX_ROOT}/bin" "${ARRMUX_ETC}" "${SERVICES_DIR}" \
         "${ARRMUX_DATA}" "${ARRMUX_LOG}" \
         "${ARRMUX_ETC}/jellyfin" "${ARRMUX_DATA}/jellyfin/data"

# --- 3. Sub-instaladores ---
log "== storage =="
bash "${SCRIPT_DIR}/scripts/setup_storage.sh"
log "== Servarr + Bazarr =="
bash "${SCRIPT_DIR}/scripts/install_arr.sh"
log "== wireproxy =="
bash "${SCRIPT_DIR}/scripts/setup_wireproxy.sh"

# --- 4. Jellyfin: repo APT, fallback tarball ---
if command -v jellyfin >/dev/null 2>&1 || [ -x /usr/bin/jellyfin ]; then
  log "Jellyfin ya instalado: $(jellyfin --version 2>&1 | head -n1 || true)"
else
  log "Instalando Jellyfin (repo APT https://repo.jellyfin.org/debian)..."
  if curl -fsSL --max-time 20 https://repo.jellyfin.org/debian/jellyfin_team.gpg.key -o /tmp/jellyfin.gpg 2>/dev/null; then
    mkdir -p /etc/apt/keyrings
    gpg --dearmor --yes -o /etc/apt/keyrings/jellyfin.gpg /tmp/jellyfin.gpg 2>/dev/null || warn "gpg dearmor falló."
    UBUNTU_CODENAME="$(lsb_release -cs 2>/dev/null || echo jammy)"
    echo "deb [signed-by=/etc/apt/keyrings/jellyfin.gpg arch=arm64] https://repo.jellyfin.org/debian ${UBUNTU_CODENAME} main" \
      > /etc/apt/sources.list.d/jellyfin.list
    if apt-get update -o Acquire::Retries=2 && apt-get install -y jellyfin; then
      log "Jellyfin instalado vía APT."
    else
      warn "APT de Jellyfin falló; instala manualmente el tarball arm64 desde https://repo.jellyfin.org/?path=/server/deb/stable."
    fi
    rm -f /tmp/jellyfin.gpg
  else
    warn "Sin acceso a https://repo.jellyfin.org/debian."
    warn "Fallback manual: descarga el tarball arm64/server estable desde https://repo.jellyfin.org/?path=/server/deb/stable"
    warn "y extráelo con jellyfin --datadir ${ARRMUX_DATA}/jellyfin/data --configdir ${ARRMUX_ETC}/jellyfin."
  fi
fi

# --- 5. qBittorrent-nox vía apt ---
if ! command -v qbittorrent-nox >/dev/null 2>&1; then
  log "Instalando qbittorrent-nox vía apt..."
  apt-get update -o Acquire::Retries=2 && apt-get install -y qbittorrent-nox || \
    die "No se pudo instalar qbittorrent-nox. Ejecuta: apt install -y qbittorrent-nox"
fi

# --- 6. Copiar configs supervisor ---
log "Instalando configs supervisor en ${SERVICES_DIR}..."
cp -f "${SCRIPT_DIR}/config/supervisor.conf" "${ARRMUX_ETC}/supervisor.conf"
cp -f "${SCRIPT_DIR}"/config/services/*.conf "${SERVICES_DIR}/"
# Compat: algunos tutoriales miran /etc/supervisor/conf.d/
if [ -d /etc/supervisor/conf.d ]; then
  printf '[include]\nfiles=%s/*.conf\n' "${SERVICES_DIR}" > /etc/supervisor/conf.d/arrmux.conf
  log "Include registrado en /etc/supervisor/conf.d/arrmux.conf"
fi
chmod 644 "${ARRMUX_ETC}/supervisor.conf" "${SERVICES_DIR}"/*.conf

# --- 7. CLI arrmux ---
log "Instalando CLI en /usr/local/bin/arrmux..."
install -m 0755 "${SCRIPT_DIR}/bin/arrmux" /usr/local/bin/arrmux

# --- 8. Permisos (datos preservados, nunca rm -rf de DATA) ---
log "Ajustando permisos (sin borrar datos)..."
chmod 600 "${ARRMUX_ETC}/wireproxy.conf" 2>/dev/null || true

IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
[ -n "${IP:-}" ] || IP="<IP-PRoot>"

cat <<EOF
[install] ============================================
[install]  arrmux instalado / reparado correctamente
[install] ============================================
  Jellyfin      http://${IP}:8096
  qBittorrent   http://${IP}:8081
  Sonarr        http://${IP}:8989
  Radarr        http://${IP}:7878
  Prowlarr      http://${IP}:9696
  Bazarr        http://${IP}:6767
  wireproxy     socks5h://127.0.0.1:1080

  1. Edita ${ARRMUX_ETC}/wireproxy.conf con tu .conf WireGuard.
  2. Arranca: arrmux start all && arrmux status
  3. Verifica VPN: arrmux vpn-check
  Re-ejecuta ./install.sh para actualizar/reparar (no borra ${ARRMUX_DATA}).
EOF
