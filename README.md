# arrmux — clon nativo de YAMS para PRoot Ubuntu ARM64

Stack *arr completo **sin Docker, sin systemd y sin TUN**: `supervisord` como
gestor de procesos y `wireproxy` (userspace) como "VPN" SOCKS5 en
`127.0.0.1:1080`. Pensado para correr dentro de `proot-distro` Ubuntu 22.04
(aarch64) en Android.

## Qué es

Un instalador + CLI que descarga y supervisa (modo simple por defecto):

| Servicio   | Puerto | URL                    |
|------------|--------|------------------------|
| wireproxy  | 1080   | socks5://127.0.0.1:1080|
| Jellyfin   | 8096   | http://127.0.0.1:8096  |
| qBittorrent| 8081   | http://127.0.0.1:8081  |

Modo full (`./install.sh --full`) añade: Sonarr 8989, Radarr 7878,
Prowlarr 9696, Bazarr 6767.

## Modo simple (por defecto)

```bash
git clone <este-repo> && cd reproductor
chmod +x install.sh bin/arrmux scripts/*.sh
./install.sh                    # solo storage + wireproxy + qbittorrent + jellyfin
# 1. Configura WireGuard: edita /etc/arrmux/wireproxy.conf
#    (o $HOME/.arrmux/etc/wireproxy.conf) con tus datos [Interface]/[Peer].
arrmux start wireproxy
arrmux vpn-check                 # la IP vía SOCKS5 debe diferir de la directa
arrmux start all                 # arranca jellyfin + qbittorrent
arrmux status
```

Nota: modo full con `--full` incluye *arr
(`./install.sh --full`; el CLI los gestiona con `arrmux --full status/...`).

## Diferencias vs YAMS (rogsme/yams)

YAMS orquesta contenedores Docker (Gluetun crea una interfaz TUN real y enruta
todo el tráfico del stack por la VPN con kill-switch a nivel de red).
Eso es imposible en PRoot (sin root real, sin TUN/TAP, sin iptables), así que:

- **Sin Gluetun/Docker** → `wireproxy` en userspace: solo expone un SOCKS5
  local. Solo el tráfico que *explícitamente* uses ese proxy va por la VPN
  (qBittorrent se configura para ello; los *arrindexers salen por red directa
  salvo que los configures con proxy).
- **Sin systemd** → `supervisord` (funciona sin PID 1, perfecto en PRoot).
- **Sin TUN** → no hay interfaz de red virtual ni enrutado a nivel de sistema.
- **Binarios nativos ARM64** en `/opt/arrmux/apps` (o `~/.arrmux/opt` sin
  root), datos en `/var/lib/arrmux` (o `~/.arrmux/data`).

## Requisitos

- Ubuntu 22.04 en `proot-distro`, arquitectura `aarch64` (`uname -m`).
- `apt install -y curl tar python3 python3-venv git supervisor qbittorrent-nox libicu70 sqlite3 libssl3 ca-certificates`
- qBittorrent viene de apt (`qbittorrent-nox`); el resto se descarga solo.

## Instalación paso a paso

```bash
git clone <este-repo> && cd reproductor
chmod +x install.sh bin/arrmux scripts/*.sh
./install.sh
# o con rutas no-root automáticas si no hay permiso en /opt:
#   ARRMUX_ROOT=~/.arrmux/opt DATA_ROOT=~/.arrmux/data
```

1. `install.sh` detecta arquitectura, comprueba dependencias, crea
   `/opt/arrmux` y `/var/lib/arrmux` (o fallback a `$HOME/.arrmux`),
   ejecuta los `scripts/`, instala las configs y el CLI.
2. **Configura WireGuard**: edita `/etc/arrmux/wireproxy.conf`
   (o `$HOME/.arrmux/etc/wireproxy.conf`) con tus datos `[Interface]` /
   `[Peer]` reales (el instalador deja una plantilla con `<...>`).
3. Arranca:

```bash
arrmux start wireproxy
arrmux vpn-check        # la IP vía SOCKS5 debe diferir de la directa
arrmux start all
arrmux status
```

## Configuración WireGuard (wireproxy)

Pide a tu proveedor un perfil WireGuard y traslada los campos a
`wireproxy.conf`:

```ini
[Interface]
PrivateKey = ...
Address = 10.x.x.x/32
DNS = 1.1.1.1

[Peer]
PublicKey = ...
AllowedIPs = 0.0.0.0/0
Endpoint = host:puerto
PersistentKeepalive = 25

[Socks5]
BindAddress = 127.0.0.1:1080
```

Luego `arrmux restart wireproxy && arrmux vpn-check`.

## Uso del CLI

```bash
arrmux install | start [all|SVC] | stop [all|SVC] | restart [all|SVC]
arrmux status                 # tabla RUNNING/STOPPED PID MEM URL
arrmux logs [SVC]             # tail -f de /var/log/arrmux/*.log
arrmux vpn-check              # IP directa vs IP vía SOCKS5
```

## Solución de problemas

- `supervisord no responde` → mira `$LOG_DIR/supervisord.log`; el socket vive
  en `$DATA_ROOT/supervisor.sock` (nunca en `/sdcard`).
- `vpn-check` dice que wireproxy no responde → revisa `logs wireproxy`;
  casi siempre es `wireproxy.conf` sin editar (plantilla con `<...>`).
- Sonarr/Radarr no arrancan → falta `libicu` (instala `libicu70`) o el
  tarball se descargó mal (borra `/opt/arrmux/apps/<svc>` y re-ejecuta).
- qBittorrent descarga con tu IP real → `arrmux stop qbittorrent`,
  re-ejecuta `install.sh` (regenera el proxy forzado) y arranca de nuevo.
  Verifica siempre con `vpn-check` antes de descargar.
- `ERROR ... bajo /sdcard` → mueve `DATA_ROOT` a almacenamiento interno.

## ⚠️ VIABILIDAD HONESTA (resumen)

Sin TUN real **no hay kill-switch de verdad** (si wireproxy cae, qBittorrent
usa un proxy muerto: falla cerrado en la práctica, pero sin garantía de
firewall — verifícalo parando wireproxy). Además: **SOCKS5 ≠ cifrado total**;
**DHT/UDP desactivado** (menos fuentes); **transcode SW lento** (direct-play);
**Doze/batería** puede matar PRoot; **FUSE corrompe sqlite** (DBs nunca en
`/sdcard`, el instalador aborta); **sin port-forward**; **.NET necesita
libicu** (modo full).

## Estructura

```text
install.sh  bin/arrmux  config/supervisor.conf  config/services/{wireproxy,jellyfin,qbittorrent}.conf
config/services/optional/{sonarr,radarr,prowlarr,bazarr}.conf  (perfil full)
scripts/install_arr.sh  scripts/setup_wireproxy.sh
scripts/setup_storage.sh  scripts/setup_qbittorrent.sh
```
