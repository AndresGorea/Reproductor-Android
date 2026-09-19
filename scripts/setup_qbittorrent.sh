#!/usr/bin/env bash
# arrmux — genera qBittorrent.conf con proxy SOCKS5 forzado a wireproxy.
# Idempotente (no sobrescribe valores ya correctos) y SOLO con qbittorrent parado.
set -euo pipefail

: "${DATA_ROOT:=/var/lib/arrmux}"

CONF_FILE="$DATA_ROOT/qbittorrent/qBittorrent/config/qBittorrent.conf"

# No tocar config con el demonio corriendo (sobreescribiría al salir).
if pgrep -f "qbittorrent-nox" >/dev/null 2>&1; then
  echo "ERROR: qbittorrent está corriendo. Páralo primero: arrmux stop qbittorrent" >&2
  exit 1
fi

mkdir -p "$(dirname "$CONF_FILE")"
touch "$CONF_FILE"

# Fija clave=valor dentro de la sección [Preferences], creando la sección si falta.
set_pref() {
  local key="$1" val="$2"
  if grep -q "^\[Preferences\]" "$CONF_FILE"; then
    if grep -q "^$key=" "$CONF_FILE"; then
      sed -i "s|^$key=.*|$key=$val|" "$CONF_FILE"
    else
      sed -i "/^\[Preferences\]/a $key=$val" "$CONF_FILE"
    fi
  else
    printf '\n[Preferences]\n%s=%s\n' "$key" "$val" >> "$CONF_FILE"
  fi
}

set_pref "Connection\\ProxyType" "2"            # 2 = SOCKS5
set_pref "Connection\\Proxy\\IP" "127.0.0.1"
set_pref "Connection\\Proxy\\Port" "1080"
set_pref "Connection\\ProxyPeerConnections" "true"
set_pref "Connection\\BTProtocol" "0"           # 0 = TCP (sin uTP/UDP: no pasa por SOCKS5)
set_pref "Connection\\UPnP" "false"
set_pref "Connection\\DHT" "false"
set_pref "Connection\\PeX" "false"
set_pref "Connection\\LSD" "false"

echo "qBittorrent.conf actualizado en $CONF_FILE (proxy SOCKS5 127.0.0.1:1080, DHT/PeX/LSD/UPnP off)"
