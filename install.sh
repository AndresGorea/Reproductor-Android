#!/usr/bin/env bash
# arrmux — instalador maestro (YAMS nativo para PRoot Ubuntu ARM64)
# Idempotente: seguro re-ejecutar. Sin Docker/systemd/TUN.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR"

# --- Detección de arquitectura ---
ARCH="$(uname -m)"
if [[ "$ARCH" != "aarch64" && "$ARCH" != "arm64" ]]; then
  echo "ERROR: arrmux requiere ARM64 (aarch64). Detectado: $ARCH" >&2
  exit 1
fi

# --- Dependencias mínimas ---
for cmd in curl tar python3; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "ERROR: falta dependencia '$cmd'. Instala con: apt update && apt install -y curl tar python3 python3-venv" >&2
    exit 1
  fi
done
if ! python3 -m venv --help >/dev/null 2>&1; then
  echo "ERROR: falta python3-venv. Instala con: apt install -y python3-venv" >&2
  exit 1
fi
if ! command -v supervisord >/dev/null 2>&1 && ! python3 -c "import supervisor" 2>/dev/null; then
  echo "ERROR: falta supervisord. Instala con: apt install -y supervisor  (o pip install supervisor)" >&2
  exit 1
fi

# --- Rutas: sistema si hay permiso, fallback a $HOME ---
if [[ -w /opt && -w /var/lib && -w /var/log && -w /usr/local/bin ]] 2>/dev/null \
   && mkdir -p /opt/arrmux /var/lib/arrmux /var/log/arrmux 2>/dev/null; then
  export ARRMUX_ROOT="/opt/arrmux"
  export DATA_ROOT="/var/lib/arrmux"
  export LOG_DIR="/var/log/arrmux"
  export CONF_DIR="/etc/arrmux"
  BIN_DIR="/usr/local/bin"
else
  export ARRMUX_ROOT="$HOME/.arrmux/opt"
  export DATA_ROOT="$HOME/.arrmux/data"
  export LOG_DIR="$HOME/.arrmux/log"
  export CONF_DIR="$HOME/.arrmux/etc"
  BIN_DIR="$HOME/.local/bin"
fi
export MEDIA_ROOT="${MEDIA_ROOT:-}"

echo "ARRMUX_ROOT=$ARRMUX_ROOT"
echo "DATA_ROOT=$DATA_ROOT"
echo "LOG_DIR=$LOG_DIR"
echo "CONF_DIR=$CONF_DIR"
echo "BIN_DIR=$BIN_DIR"

mkdir -p "$ARRMUX_ROOT" "$ARRMUX_ROOT/bin" "$ARRMUX_ROOT/apps" \
         "$DATA_ROOT" "$LOG_DIR" "$CONF_DIR" "$CONF_DIR/services" "$BIN_DIR"

# --- Sub-scripts (idempotentes) ---
bash "$REPO_ROOT/scripts/setup_storage.sh"
bash "$REPO_ROOT/scripts/setup_wireproxy.sh"
bash "$REPO_ROOT/scripts/install_arr.sh"
bash "$REPO_ROOT/scripts/setup_qbittorrent.sh"

# --- Instalar configs de supervisord (plantillas con sustitución de rutas) ---
# Las plantillas usan @@ARRMUX_ROOT@@, @@DATA_ROOT@@, @@LOG_DIR@@, @@CONF_DIR@@.
for tpl in "$REPO_ROOT"/config/services/*.conf; do
  name="$(basename "$tpl")"
  sed -e "s|@@ARRMUX_ROOT@@|$ARRMUX_ROOT|g" \
      -e "s|@@DATA_ROOT@@|$DATA_ROOT|g" \
      -e "s|@@LOG_DIR@@|$LOG_DIR|g" \
      -e "s|@@CONF_DIR@@|$CONF_DIR|g" \
      "$tpl" > "$CONF_DIR/services/$name"
done
sed -e "s|@@ARRMUX_ROOT@@|$ARRMUX_ROOT|g" \
    -e "s|@@DATA_ROOT@@|$DATA_ROOT|g" \
    -e "s|@@LOG_DIR@@|$LOG_DIR|g" \
    -e "s|@@CONF_DIR@@|$CONF_DIR|g" \
    "$REPO_ROOT/config/supervisor.conf" > "$CONF_DIR/supervisor.conf"

# --- Instalar CLI ---
cp -f "$REPO_ROOT/bin/arrmux" "$BIN_DIR/arrmux"
chmod +x "$BIN_DIR/arrmux"

echo ""
echo "Instalación completa."
echo "  CLI:      $BIN_DIR/arrmux  (asegúrate de tenerlo en PATH)"
echo "  Config:   $CONF_DIR/supervisor.conf"
echo "  Siguiente: edita $CONF_DIR/wireproxy.conf con tus datos [Peer] y ejecuta: arrmux start"
