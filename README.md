# arrmux — YAMS sin Docker para PRoot Ubuntu ARM64

Equivalente a [YAMS](https://github.com/rogsme/yams) (Jellyfin + qBittorrent + Sonarr + Radarr + Prowlarr + Bazarr + VPN)
pero **sin Docker**, pensado para correr dentro de **PRoot Ubuntu ARM64** en un Galaxy S23 (Snapdragon 8 Gen 2) bajo Termux.

- Sin Docker/Podman, sin systemd → **supervisord + supervisorctl**.
- Sin TUN/TAP/iptables (imposibles en PRoot sin root) → **wireproxy** (userspace WireGuard) expone **SOCKS5 127.0.0.1:1080** y qBittorrent rutea el 100% por ahí.
- SQLite/binarios/config en FS interno PRoot (`/opt/arrmux`, `/etc/arrmux`, `/var/lib/arrmux/<svc>`, `/var/log/arrmux/`). **Solo los medios** viven en almacenamiento Android (`/storage/emulated/0/Media/{movies,tv,downloads}` o `/srv/media` como symlink).

## Diferencias vs YAMS

| YAMS (original) | arrmux (este proyecto) | Por qué |
|---|---|---|
| Docker + docker-compose | Binarios nativos linux-arm64 gestionados por supervisord | No hay Docker en PRoot/Termux |
| Gluetun (VPN, necesita TUN + iptables) | wireproxy SOCKS5 `127.0.0.1:1080` (userspace WireGuard) | PRoot no expone `/dev/net/tun` ni permite iptables |
| systemd (`systemctl`) | `supervisord` + `supervisorctl -c /etc/arrmux/supervisor.conf` | Sin PID 1 systemd en PRoot |
| Volúmenes Docker | `/var/lib/arrmux/<svc>` (datos), `/srv/media` → Android (solo medios) | FUSE de Android corrompe SQLite/sockets |
| `yams` CLI (docker) | `arrmux` CLI (supervisorctl + curl) | Mismos verbos: start/stop/restart/status/logs/vpn-check |

## Requisitos (dentro del PRoot Ubuntu)

```bash
apt update && apt install -y curl tar git python3 python3-venv supervisor qbittorrent-nox
```

- Ubuntu 22.04+ aarch64 bajo `proot-distro` o Termux PRoot.
- `uname -m` debe dar `aarch64` (en x86_64 solo desarrollo: los scripts avisan pero continúan).
- ~2 GB libres (Bazarr venv + Servarr + Jellyfin).
- ffmpeg opcional para Jellyfin (transcoding solo software, ver límites).

## Quickstart

```bash
git clone <este-repo> /opt/arrmux-src && cd /opt/arrmux-src
chmod +x install.sh scripts/*.sh bin/arrmux
sudo ./install.sh
# 1. Edita /etc/arrmux/wireproxy.conf con tu .conf WireGuard (ver abajo)
sudo arrmux start all
sudo arrmux status
sudo arrmux vpn-check
```

Re-ejecutar `./install.sh` = **update/repair**: re-descarga Servarr/wireproxy, reinstala configs supervisor y CLI, **sin borrar** `/var/lib/arrmux`.

## Configuración VPN paso a paso (Mullvad / ProtonVPN)

1. Consigue un `.conf` WireGuard:
   - **Mullvad**: https://mullvad.net → WireGuard configuration → genera clave → descarga `.conf`.
   - **ProtonVPN**: cuenta → Downloads → WireGuard configuration.
2. Copia los valores a `/etc/arrmux/wireproxy.conf`:
   ```ini
   [Interface]
   PrivateKey = <tu PrivateKey>
   Address = 10.x.x.x/32
   DNS = 1.1.1.1
   [Peer]
   PublicKey = <PublicKey del servidor>
   Endpoint = <servidor>.mullvad.net:51820
   AllowedIPs = 0.0.0.0/0
   PersistentKeepalive = 25
   [Socks5]
   BindAddress = 127.0.0.1:1080
   ```
3. `arrmux restart wireproxy && arrmux vpn-check` → debe decir **OK** con IPs distintas.
4. qBittorrent: `setup_wireproxy.sh` ya intenta fijar SOCKS5 en `qBittorrent.conf`. Si no aplicó: WebUI → Preferences → Connection → Proxy **SOCKS5 127.0.0.1:1080** + marcar *Use proxy for peer connections* y *hostname lookup*.
5. `arrmux restart qbittorrent`.

## Puertos / URLs

| Servicio | Puerto | URL |
|---|---|---|
| Jellyfin | 8096 | http://\<IP-PRoot\>:8096 |
| qBittorrent | 8081 | http://\<IP-PRoot\>:8081 |
| Sonarr | 8989 | http://\<IP-PRoot\>:8989 |
| Radarr | 7878 | http://\<IP-PRoot\>:7878 |
| Prowlarr | 9696 | http://\<IP-PRoot\>:9696 |
| Bazarr | 6767 | http://\<IP-PRoot\>:6767 |
| wireproxy | 1080 | socks5h://127.0.0.1:1080 |

`install.sh` imprime esta tabla con la IP detectada al final.

## Comandos `arrmux`

```
arrmux install            # re-ejecuta ../install.sh
arrmux start [all|svc]    # supervisord -c ... si no corre + supervisorctl start
arrmux stop [all|svc]
arrmux restart [all|svc]
arrmux status             # tabla SERVICIO|ESTADO|PID|MEM|URL
arrmux logs <svc>         # tail -f /var/log/arrmux/<svc>.log
arrmux vpn-check          # IP directa vs IP vía SOCKS5; OK si difieren
arrmux --help
```

## Layout en disco

```
/opt/arrmux/{sonarr,radarr,prowlarr,bazarr,bazarr-venv,bin/wireproxy}
/etc/arrmux/{supervisor.conf,services/*.conf,wireproxy.conf,jellyfin/}
/var/lib/arrmux/<servicio>/     # DBs y estado (FS interno, nunca FUSE)
/var/log/arrmux/*.log
/srv/media -> /storage/emulated/0/Media/{movies,tv,downloads}  # solo medios
```

## Solución de problemas

- **FUSE + SQLite**: nunca pongas `*.db`, sockets o `config.xml` bajo `/storage` o `/sdcard`. Síntoma: `database is locked / disk I/O error`. Fix: datos en `/var/lib/arrmux`, solo medios en Android.
- **TUN ausente** (`/dev/net/tun: No such device`): esperado en PRoot. Por eso existe wireproxy; no intentes Gluetun/OpenVPN-TUN.
- **OOM en Snapdragon**: baja límites de Bazarr/Sonarr, desactiva transcoding HW en Jellyfin, usa `autorestart=true` (ya configurado) y vigila con `arrmux status` (columna MEM).
- **Autostart**: sin systemd. Opciones: app **Termux:Boot** (`~/.termux/boot/start-arrmux.sh` con `proot-distro login ubuntu -- arrmux start all`) o `proot-distro login` + `@reboot`-like vía script manual. Ejemplo Termux:Boot:
  ```sh
  #!/data/data/com.termux/files/usr/bin/sh
  proot-distro login ubuntu -- /usr/local/bin/arrmux start all
  ```
- **ffmpeg / transcoding**: `apt install jellyfin-ffmpeg` si existe para tu release; si no, ffmpeg genérico. Solo software (sin HW OMX/MediaCodec en PRoot) → prefiere **Direct Play**.

## Viabilidad (honesto)

| Componente | Estado | Nota |
|---|---|---|
| Jellyfin APT (repo.jellyfin.org/debian) | ✅ viable | Repo oficial con arm64; fallback a tarball documentado en `install.sh` |
| qbittorrent-nox apt | ✅ viable | Disponible en Ubuntu arm64; WebUI :8081 |
| Sonarr/Radarr/Prowlarr tarballs `linux-core-arm64` | ✅ viables | `.NET` embebido, sin dependencias; `--data` por servicio |
| Bazarr git + venv | ⚠️ viable pero lento | `pip install -r requirements.txt` tarda varios minutos en el teléfono la primera vez |
| wireproxy userspace | ✅ viable | Sin TUN/iptables; SOCKS5 :1080 verificado con `vpn-check` |
| Transcoding HW | ❌ no | Sin acceso GPU/MediaCodec desde PRoot → solo software/Direct Play |
| Port-forward VPN / seeding entrante | ❌ sin root | Solo conexiones salientes por SOCKS5; ratio limitado |
| Batería/temperatura | ⚠️ | Carga sostenida drena y calienta; úsalo con cargador y límites |

## Límites conocidos

Sin Docker, sin systemd, sin TUN/TAP/iptables. Sin transcoding por hardware. Sin port-forward de la VPN (sin root no hay NAT). La batería del S23 sufre con indexados largos: programa scans de noche.
