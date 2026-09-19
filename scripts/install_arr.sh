#!/usr/bin/env bash
# install_arr.sh — descarga Servarr ARM64 + Bazarr (idempotente, update-safe).
set -euo pipefail

ARRMUX_ROOT="/opt/arrmux"
ARRMUX_DATA="/var/lib/arrmux"
ARRMUX_LOG="/var/log/arrmux"
TMP_DIR="/tmp/arrmux-dl"

log()  { echo "[install_arr] $*"; }
warn() { echo "[install_arr] ADVERTENCIA: $*" >&2; }
die()  { echo "[install_arr] ERROR: $*" >&2; exit 1; }

command -v curl >/dev/null 2>&1 || die "falta 'curl'. Instala con: apt install curl"
command -v tar >/dev/null 2>&1 || die "falta 'tar'. Instala con: apt install tar"
command -v python3 >/dev/null 2>&1 || die "falta 'python3'. Instala con: apt install python3"
command -v git >/dev/null 2>&1 || die "falta 'git'. Instala con: apt install git"

ARCH="$(uname -m)"
case "${ARCH}" in
  aarch64|arm64) log "Arquitectura ${ARCH} (ARM64) — objetivo soportado." ;;
  x86_64) warn "Arquitectura ${ARCH}: solo para desarrollo. En el teléfono debe ser aarch64 (Snapdragon 8 Gen 2)." ;;
  *) warn "Arquitectura ${ARCH} no probada; se intenta igualmente con binarios arm64." ;;
esac

mkdir -p "${ARRMUX_ROOT}" "${TMP_DIR}"

# Descarga la última release de GitHub cuyo asset case-insensitive coincida con $2.
download_github_latest() {
  local repo="$1"       # p.ej. Sonarr/Sonarr
  local pattern="$2"    # p.ej. linux-core-arm64.tar.gz
  local dest_tar="$3"

  log "Resolviendo última release de ${repo} (patrón: ${pattern})..."
  local api_url="https://api.github.com/repos/${repo}/releases/latest"
  local json
  json="$(curl -fsSL --max-time 30 "${api_url}")" || die "No se pudo consultar ${api_url}. Revisa red/DNS."
  local url
  url="$(echo "${json}" | grep -oiE '"browser_download_url": *"[^"]*'"${pattern}"'[^"]*"' | head -n1 | cut -d'"' -f4)"
  [ -n "${url:-}" ] || die "Ningún asset de ${repo} coincide con '${pattern}'. Respuesta parcial: $(echo "${json}" | head -c 300)"
  log "Descargando ${url} ..."
  curl -fSL --max-time 300 -o "${dest_tar}" "${url}" || die "Falló la descarga de ${url}."
  log "Guardado en ${dest_tar}"
}

install_servapp() {
  local repo="$1"    # Sonarr/Sonarr
  local app="$2"     # sonarr (minúsculas, dir destino)
  local App="$3"     # Sonarr (nombre binario/carpeta mayúsculas)
  local pattern="$4" # linux-core-arm64.tar.gz

  local dest_dir="${ARRMUX_ROOT}/${app}"
  local tarball="${TMP_DIR}/${app}-latest.tar.gz"
  download_github_latest "${repo}" "${pattern}" "${tarball}"
  log "Instalando ${App} en ${dest_dir} (datos intactos en ${ARRMUX_DATA}/${app})..."
  mkdir -p "${dest_dir}" "${ARRMUX_DATA}/${app}"
  # Extraer a staging y mover: evita mezclar versiones viejas.
  local stage="${TMP_DIR}/${app}-stage"
  rm -rf "${stage}"
  mkdir -p "${stage}"
  tar -xzf "${tarball}" -C "${stage}" || die "No se pudo extraer ${tarball}."
  # Los tarballs Servarr contienen una carpeta ${App}/ con el binario dentro.
  if [ -d "${stage}/${App}" ]; then
    rm -rf "${dest_dir:?}/"*
    cp -a "${stage}/${App}/." "${dest_dir}/" || die "No se pudo copiar ${App} a ${dest_dir}."
  else
    # Fallback: volcar contenido del stage tal cual.
    warn "${tarball} no contiene carpeta ${App}/; copiando contenido tal cual."
    cp -a "${stage}/." "${dest_dir}/" || die "No se pudo copiar ${App} a ${dest_dir}."
  fi
  chmod +x "${dest_dir}/${App}" 2>/dev/null || warn "No se pudo dar +x a ${dest_dir}/${App}."
  rm -rf "${stage}" "${tarball}"
  log "${App} OK -> ${dest_dir}/${App}"
}

install_servapp "Sonarr/Sonarr" "sonarr" "Sonarr" "linux-core-arm64.tar.gz"
install_servapp "Radarr/Radarr" "radarr" "Radarr" "linux-core-arm64.tar.gz"
install_servapp "Prowlarr/Prowlarr" "prowlarr" "Prowlarr" "linux-core-arm64.tar.gz"

# --- Bazarr: git + venv (lento la primera vez en el teléfono) ---
BAZARR_DIR="${ARRMUX_ROOT}/bazarr"
VENV_DIR="${ARRMUX_ROOT}/bazarr-venv"
if [ -d "${BAZARR_DIR}/.git" ]; then
  log "Bazarr ya clonado; actualizando (git pull)..."
  git -C "${BAZARR_DIR}" pull --ff-only || warn "git pull de Bazarr falló; se conserva la copia local."
else
  if [ -e "${BAZARR_DIR}" ] && [ ! -d "${BAZARR_DIR}/.git" ]; then
    warn "${BAZARR_DIR} existe sin .git; se conserva y no se clona."
  else
    log "Clonando Bazarr..."
    git clone --depth 1 https://github.com/morpheus65535/bazarr.git "${BAZARR_DIR}" || \
      die "No se pudo clonar Bazarr. Revisa red."
  fi
fi

if [ ! -x "${VENV_DIR}/bin/python" ]; then
  log "Creando venv en ${VENV_DIR}..."
  python3 -m venv "${VENV_DIR}" || die "Falló 'python3 -m venv'. Instala con: apt install python3-venv"
else
  log "venv ya existe en ${VENV_DIR}; reutilizando."
fi
log "Instalando requirements de Bazarr (puede tardar varios minutos en ARM)..."
"${VENV_DIR}/bin/pip" install --upgrade pip || warn "No se pudo actualizar pip."
"${VENV_DIR}/bin/pip" install -r "${BAZARR_DIR}/requirements.txt" || \
  die "Falló pip install de Bazarr. Revisa el log de pip."
mkdir -p "${ARRMUX_DATA}/bazarr"

log "OK. Servarr + Bazarr instalados/actualizados sin tocar datos."
