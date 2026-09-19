#!/usr/bin/env bash
# arrmux — instala wireproxy (windtf/wireproxy) + plantilla wireproxy.conf.
# Idempotente: no sobrescribe la conf de usuario si ya existe.
set -euo pipefail

: "${ARRMUX_ROOT:=/opt/arrmux}"
: "${DATA_ROOT:=/var/lib/arrmux}"
: "${CONF_DIR:=/etc/arrmux}"

# --- Guardia de arquitectura (binario linux-arm64; PRoot). --force solo para tests. ---
FORCE=0
[[ "${1:-}" == "--force" || "${ARRMUX_FORCE:-0}" == "1" ]] && FORCE=1
ARCH="$(uname -m)"
case "${ARCH}" in
  aarch64|arm64) ASSET_PAT="linux_arm64.tar.gz" ;;
  *)
    echo "ERROR: arquitectura ${ARCH}; wireproxy debe ser linux_arm64 (PRoot)." >&2
    echo "Solo avisa en PRoot: permite --force para test en este host (o ARRMUX_FORCE=1)." >&2
    [[ "$FORCE" == "1" ]] || exit 1
    echo "AVISO (--force): se continúa en ${ARCH} solo para pruebas (sin descargar)." >&2
    ASSET_PAT="linux_arm64.tar.gz" ;;
esac

mkdir -p "$ARRMUX_ROOT/bin" "$DATA_ROOT/wireproxy" "$CONF_DIR"

# Idempotencia total ANTES de tocar red: si hay binario, se omite descarga.
if [[ -x "$ARRMUX_ROOT/bin/wireproxy" ]]; then
  echo "wireproxy: ya instalado, se omite descarga."
else
  WIREPROXY_REPO="windtf/wireproxy"
  # Última release vía API de GitHub (solo cuando falta el binario).
  echo "wireproxy: resolviendo última release de ${WIREPROXY_REPO}..."
  API_JSON="$(curl -fsSL --retry 3 --max-time 30 "https://api.github.com/repos/${WIREPROXY_REPO}/releases/latest")" \
    || { echo "ERROR: no se pudo consultar releases de ${WIREPROXY_REPO}. Revisa red/DNS." >&2; exit 1; }
  URL="$(echo "${API_JSON}" | grep -oiE '"browser_download_url": *"[^"]*'"${ASSET_PAT}"'[^"]*"' | head -n1 | cut -d'"' -f4)"
  [[ -n "${URL:-}" ]] || { echo "ERROR: ningún asset coincide con '${ASSET_PAT}'." >&2; exit 1; }
  echo "wireproxy: descargando ${URL}..."
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
