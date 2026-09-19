#!/usr/bin/env bash
# arrmux — descarga idempotente de *arr + Jellyfin + Bazarr (linux-arm64).
# No re-descarga si el binario ya existe. Aborta con diagnóstico si falla curl/tar.
set -euo pipefail

: "${ARRMUX_ROOT:=/opt/arrmux}"
: "${DATA_ROOT:=/var/lib/arrmux}"

ARCH="$(uname -m)"
case "${ARCH}" in
  aarch64|arm64) echo "Arquitectura ${ARCH} (ARM64) — objetivo soportado." ;;
  *) echo "ADVERTENCIA: arquitectura ${ARCH}; se esperaba aarch64 (Snapdragon 8 Gen 2)." >&2
     echo "Se continúa igualmente (útil en x86_64 para desarrollo)." >&2 ;;
esac

# Dependencias de runtime típicas en Ubuntu 22.04 (aviso, no instalación forzada).
for lib in libicu sqlite3 libssl3 ca-certificates; do
  if ! dpkg -s "$lib" >/dev/null 2>&1; then
    echo "AVISO: paquete '$lib' no instalado. .NET/Jellyfin pueden fallar." >&2
    echo "       Instala con: apt install -y libicu70 sqlite3 libssl3 ca-certificates" >&2
  fi
done

mkdir -p "$ARRMUX_ROOT/apps" "$DATA_ROOT/.dotnet" "$DATA_ROOT"/{sonarr,radarr,prowlarr,jellyfin,bazarr}
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# $1=nombre $2=url $3=subdir_en_apps $4=binario_testigo
fetch_tarball() {
  local name="$1" url="$2" subdir="$3" witness="$4"
  if [[ -x "$ARRMUX_ROOT/apps/$subdir/$witness" ]]; then
    echo "$name: ya instalado, se omite descarga."
    return 0
  fi
  echo "$name: descargando..."
  if ! curl -fSL --retry 3 --max-time 300 -o "$TMP/$name.tar.gz" "$url"; then
    echo "ERROR: falló la descarga de $name desde $url" >&2
    echo "       Revisa tu conexión (¿wireproxy activo interfiriendo?) y re-ejecuta install.sh." >&2
    exit 1
  fi
  if ! tar -xzf "$TMP/$name.tar.gz" -C "$TMP"; then
    echo "ERROR: tarball de $name corrupto o no es gzip válido." >&2
    exit 1
  fi
  # El tarball extrae una carpeta única; moverla a apps/<subdir>.
  local extracted
  extracted="$(find "$TMP" -mindepth 1 -maxdepth 1 -type d | head -n1)"
  rm -rf "$ARRMUX_ROOT/apps/$subdir"
  mv "$extracted" "$ARRMUX_ROOT/apps/$subdir"
  chmod +x "$ARRMUX_ROOT/apps/$subdir/$witness" 2>/dev/null || true
  echo "$name: instalado en $ARRMUX_ROOT/apps/$subdir"
}

fetch_tarball "Sonarr" \
  "https://services.sonarr.tv/v1/download/main/latest?version=4&os=linux&arch=arm64" \
  "sonarr" "Sonarr"

fetch_tarball "Radarr" \
  "https://services.radarr.video/v1/download/main/latest?version=5&os=linux&arch=arm64" \
  "radarr" "Radarr"

fetch_tarball "Prowlarr" \
  "https://prowlarr.servarr.com/v1/update/master/updatefile?os=linux&runtime=netcore&arch=arm64" \
  "prowlarr" "Prowlarr"

# --- Jellyfin portable arm64: se resuelve el último stable desde el índice ---
if [[ -x "$ARRMUX_ROOT/apps/jellyfin/jellyfin" ]]; then
  echo "Jellyfin: ya instalado, se omite descarga."
else
  echo "Jellyfin: resolviendo última versión estable arm64..."
  INDEX="$(curl -fSL --retry 3 --max-time 60 https://repo.jellyfin.org/files/server/linux/latest-stable/arm64/)" \
    || { echo "ERROR: no se pudo listar https://repo.jellyfin.org/files/server/linux/latest-stable/arm64/" >&2; exit 1; }
  JELLY_TAR="$(grep -oE 'href="jellyfin_[0-9][^"]*linux-arm64\.tar\.gz"' <<<"$INDEX" | head -n1 | cut -d'"' -f2)" \
    || { echo "ERROR: no se encontró tarball jellyfin_*_linux-arm64.tar.gz en el índice." >&2; exit 1; }
  [[ -n "$JELLY_TAR" ]] || { echo "ERROR: índice de Jellyfin sin tarball arm64 reconocible." >&2; exit 1; }
  fetch_tarball "Jellyfin" \
    "https://repo.jellyfin.org/files/server/linux/latest-stable/arm64/$JELLY_TAR" \
    "jellyfin" "jellyfin"
fi

# --- Bazarr: git clone + venv (idempotente) ---
if [[ -x "$ARRMUX_ROOT/apps/bazarr/bazarr.py" && -x "$ARRMUX_ROOT/bazarr-venv/bin/python" ]]; then
  echo "Bazarr: ya instalado, se omite."
else
  command -v git >/dev/null 2>&1 || { echo "ERROR: falta 'git' (apt install -y git) para clonar Bazarr." >&2; exit 1; }
  if [[ -d "$ARRMUX_ROOT/apps/bazarr/.git" ]]; then
    echo "Bazarr: repo existe, actualizando..."
    git -C "$ARRMUX_ROOT/apps/bazarr" pull --ff-only || echo "AVISO: git pull falló, se conserva copia local."
  else
    rm -rf "$ARRMUX_ROOT/apps/bazarr"
    git clone --depth 1 https://github.com/morpheus65535/bazarr.git "$ARRMUX_ROOT/apps/bazarr" \
      || { echo "ERROR: git clone de Bazarr falló." >&2; exit 1; }
  fi
  if [[ ! -x "$ARRMUX_ROOT/bazarr-venv/bin/python" ]]; then
    python3 -m venv "$ARRMUX_ROOT/bazarr-venv" || { echo "ERROR: no se pudo crear venv (¿falta python3-venv?)." >&2; exit 1; }
  fi
  "$ARRMUX_ROOT/bazarr-venv/bin/pip" install --upgrade pip
  "$ARRMUX_ROOT/bazarr-venv/bin/pip" install -r "$ARRMUX_ROOT/apps/bazarr/requirements.txt" \
    || { echo "ERROR: pip install de Bazarr falló." >&2; exit 1; }
  echo "Bazarr: instalado."
fi

echo "Todos los *arr listos."
