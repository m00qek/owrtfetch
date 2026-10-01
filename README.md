# owrtfetch

A neofetch-like summary for OpenWrt routers, written in [ucode](https://github.com/jow-/ucode).
It shows what a router is running on and doing: SoC and temperature, memory, disks, the
addresses of each network, each SSID with its clients, and DHCP leases.

```
   _______                      root@router
  |       |.-----.-----.-----.  -----------
  |   -   ||  _  |  -__|     |  OS: OpenWrt 25.12.5 aarch64 (mediatek/filogic)
  |_______||   __|_____|__|__|  Host: Cudy WR3000 v1
           |__|                 Kernel: 6.12.94
   ________        __           Uptime: 2 days, 4 hours, 12 mins
  |  |  |  |.----.|  |_         Load: 0.08, 0.05, 0.01
  |  |  |  ||   _||   _|        Packages: 158 (apk), +12 and -2 since flashing
  |________||__|  |____|        Shell: ash 1.37.0
                                CPU: mt7981 (2) - 58.3C
                                Memory: 106MiB / 233MiB (45%)
                                Disk (/overlay): 3.1MiB / 88.4MiB (4%) - ubifs
                                Net (lan): 192.168.1.1/24 - br-lan
                                Net (wan): 198.51.100.19/24 - wan
                                Wi-Fi (OpenWrt): 4 clients, 2.4G ch 6 HE20
                                Wi-Fi (OpenWrt5G): 2 clients, 5G ch 36 HE80
                                DHCP leases: 6
```

- **Small:** an 11 KB package (24 KiB installed) that runs in about 50 ms, depending only on
  `ucode`, `ucode-mod-fs` and `ucode-mod-ubus`, which every stock image already has.
- **Fits any console:** lines never pass 80 columns; long values wrap under themselves.
- **Plain when it should be:** no colour when piped or when `NO_COLOR` is set, and ASCII
  unless the locale is UTF-8 (then `─` and `°C`).
- **Scriptable:** `owrtfetch --json` prints the same data, in plain units, as JSON;
  `packages` there also counts what the image had and what was added and removed since.

Requires OpenWrt 25.12 or later. The package is architecture-independent (`noarch`).

## Install

From the [packages.ucode.dev](https://github.com/m00qek/packages.ucode.dev) feed, which
signs its packages, so apk verifies them and `apk upgrade` keeps owrtfetch current:

```sh
# Trust the feed's signing key, and add the feed
wget -O /etc/apk/keys/packages.ucode.dev.pem \
  https://m00qek.github.io/packages.ucode.dev/25.12/feed.pub.pem
echo "https://m00qek.github.io/packages.ucode.dev/25.12" \
  >> /etc/apk/repositories.d/customfeeds.list

apk update
apk add owrtfetch
```

Or download the `.apk` from the [latest release](../../releases/latest), copy it to the
router, and install it unverified:

```sh
apk add --allow-untrusted owrtfetch-0.1.0-r1.apk
```

## Usage

```
owrtfetch [--json] [--utf8 | --ascii]
```

To show it at login, run it from a file in `/etc/profile.d/`, only for interactive shells
so scripts running `sh -l` don't get the logo in their output:

```sh
case $- in *i*) owrtfetch ;; esac
```

## Development

Needs Docker.

```sh
make test      # unit and property tests with utest, in an OpenWrt 25.12 container
make package   # builds bin/owrtfetch-<version>.apk with the OpenWrt SDK
```

After tagging a release, `make feed-makefile VERSION=<version> OUT=<feed>/owrtfetch/Makefile`
writes the Makefile for the [packages.ucode.dev](https://github.com/m00qek/packages.ucode.dev)
feed from the release tarball.

The code is in four modules, one for each layer: `src/owrtfetch/collect.uc` reads the
system into data, `src/owrtfetch/summarize.uc` turns it into labelled lines,
`src/owrtfetch/render.uc` lays them out beside the logo, and `src/owrtfetch.uc` handles
the command line. Only `collect.uc` touches the system.

## License

MIT, see [LICENSE](LICENSE).
