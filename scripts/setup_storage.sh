#!/usr/bin/env bash
# arrmux — storage: SOLO media puede vivir en /sdcard. Configs/DBs JAMÁS.
# Idempotente. Falla si DATA_ROOT está bajo /sdcard (FUSE corrompe sqlite).
set -euo pipefail

: "${DATA_ROOT:=/var/lib/arrmux}"
# MEDIA_ROOT configurable. Default: /storage/emulated/0/Media si existe, si no ~/media.
if [[ -z "${MEDIA_ROOT:-}" ]]; then
  if [[ -d "/storage/emulated/0" ]]; then
    MEDIA_ROOT="/storage/emulated/0/Media"
  else
    MEDIA_ROOT="$HOME/media"
  fi
fi
export MEDIA_ROOT

# --- Guardarraíl FUSE: configs/DBs nunca en /sdcard ---
case "$DATA_ROOT" in
  /sdcard*|/storage/*)
    echo "ERROR: DATA_ROOT='$DATA_ROOT' está bajo /sdcard o /storage (FUSE)." >&2
    echo "Los sqlite de *arr/qBittorrent se CORROMPEN en FUSE. Usa una ruta interna" >&2
    echo "(p. ej. /var/lib/arrmux o \$HOME/.arrmux/data)." >&2
    exit 1
    ;;
esac

mkdir -p "$MEDIA_ROOT"/{movies,tv,downloads}

# chmod solo en filesystem interno; en FUSE/sdcard falla y no es necesario.
if [[ "$MEDIA_ROOT" != /sdcard* && "$MEDIA_ROOT" != /storage/* ]]; then
  chmod 755 "$MEDIA_ROOT" "$MEDIA_ROOT"/movies "$MEDIA_ROOT"/tv "$MEDIA_ROOT"/downloads
else
  echo "AVISO: MEDIA_ROOT en FUSE ($MEDIA_ROOT): se omite chmod (no soportado)."
fi

echo "MEDIA_ROOT=$MEDIA_ROOT (movies/, tv/, downloads/ listos)"
