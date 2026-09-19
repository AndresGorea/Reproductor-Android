#!/usr/bin/env bash
# arrmux — instala wireproxy (windtf/wireproxy) + plantilla wireproxy.conf.
# Idempotente: no sobrescribe la conf de usuario si ya existe.
set -euo pipefail

: "${ARRMUX_ROOT:=/opt/arrmux}"
: "${DATA_ROOT:=/var/lib/arrmux}"
: "${CONF_DIR:=/etc/arrmux}"

WIREPROXY_VERSION="${WIREPROXY_VERSION:-v1.1.3}"
URL="https://github.com/windtf/wireproxy/releases/download/${WIREPROXY_VERSION}/wireproxy_linux_arm64.tar.gz"

ARCH="$(uname -m)"
if [[ "$ARCH" != "aarch64" && "$ARCH" != "arm64" ]]; then
  echo "ERROR: se requiere ARM64. Detectado: $ARCH" >&2
  exit 1
fi

mkdir -p "$ARRMUX_ROOT/bin" "$DATA_ROOT/wireproxy" "$(dirname "$CONF_DIR/wireproxy.conf" 2>/dev/null || echo "$CONF_DIR")"
mkdir -p "$CONF_DIR"

if [[ -x "$ARRMUX_ROOT/bin/wireproxy" ]]; then
  echo "wireproxy: ya instalado, se omite descarga."
else
  echo "wireproxy: descargando $WIREPROXY_VERSION..."
  TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
  if ! curl -fSL --retry 3 --max-time 120 -o "$TMP/wireproxy.tar.gz" "$URL"; then
    echo "ERROR: falló la descarga de wireproxy desde $URL" >&2
    exit 1
  fi
  tar -xzf "$TMP/wireproxy.tar.gz" -C "$TMP" \
    || { echo "ERROR: tarball de wireproxy corrupto." >&2; exit 1; }
  BIN_FOUND="$(find "$TMP" -name 'wireproxy' -type f | head -n1)"
  [[ -n "$BIN_FOUND" ]] || { echo "ERROR: tarball sin binario 'wireproxy'." >&2; exit 1; }
  cp -f "$BIN_FOUND" "$ARRMUX_ROOT/bin/wireproxy"
  chmod +x "$ARRMUX_ROOT/bin/wireproxy"
  trap - EXIT; rm -rf "$TMP"
  echo "wireproxy: instalado en $ARRMUX_ROOT/bin/wireproxy"
fi

if [[ -f "$CONF_DIR/wireproxy.conf" ]]; then
  echo "wireproxy.conf: existe, NO se sobrescribe (edítalo con tus datos [Peer])."
else
  cat > "$CONF_DIR/wireproxy.conf" <<'EOF'
# arrmux — plantilla wireproxy. SUSTITUYE los valores <...> con los de tu proveedor WireGuard.

[Interface]
PrivateKey = <TU_PRIVATE_KEY>
Address = <TU_IP_WG/32>
DNS = 1.1.1.1

[Peer]
PublicKey = <PUBLIC_KEY_SERVIDOR>
AllowedIPs = 0.0.0.0/0
Endpoint = <servidor:puerto>
PersistentKeepalive = 25

[Socks5]
BindAddress = 127.0.0.1:1080
EOF
  echo "wireproxy.conf: plantilla creada en $CONF_DIR/wireproxy.conf — EDÍTALA antes de 'arrmux start wireproxy'."
fi
