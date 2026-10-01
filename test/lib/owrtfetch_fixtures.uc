'use strict';

// Two real boxes, as their files, commands and ubus objects read: the shapes every
// collect() test lays its changes over.

// A NanoPi R5C routing on 25.12: VLANs, WireGuard, a data disk and DHCP.
export const ROUTER = {
	fs: {
		'/proc/self/status': 'Name:\tucode\nUmask:\t0022\nUid:\t0\t0\t0\t0\nGid:\t0\t0\t0\t0\n',
		'/etc/passwd': 'root:x:0:0:root:/root:/bin/ash\nnetwork:x:101:101:network:/var:/bin/false\n',
		'/proc/sys/kernel/hostname': 'router\n',
		'/etc/openwrt_release': "DISTRIB_ID='OpenWrt'\nDISTRIB_RELEASE='25.12.5'\nDISTRIB_TARGET='rockchip/armv8'\n",
		'/proc/sys/kernel/arch': 'aarch64\n',
		'/tmp/sysinfo/model': 'FriendlyElec NanoPi R5C\n',
		'/proc/device-tree/model': 'FriendlyElec NanoPi R5C\0',
		'/proc/device-tree/compatible': 'friendlyarm,nanopi-r5c\0rockchip,rk3568\0',
		'/proc/sys/kernel/osrelease': '6.12.94\n',
		'/proc/uptime': '7008.53 27012.10\n',
		'/proc/loadavg': '0.02 0.05 0.07 1/226 16626\n',
		// Another package's file named 'ash' comes first, so the lookup must check directories.
		'/lib/apk/db/installed': 'C:Q1a\nP:base-files\nV:1690-r3\nF:usr/share/completions\nR:ash\n\n' +
			'C:Q1b\nP:busybox\nV:1.37.0-r6\nF:bin\nR:ash\nR:busybox\nR:sh\nF:lib/upgrade/keep.d\nR:busybox\n\n' +
			'C:Q1c\nP:ucode\nV:2026.01.16~85922056-r1\nF:usr/bin\nR:ucode\n\n' +
			'C:Q1d\nP:adblock\nV:4.2.2-r1\nF:etc/init.d\nR:adblock\n',
		// A list for each package, live and in the image: since flashing, ucode and adblock
		// were added and dnsmasq, odhcpd-ipv6only and ppp removed. Only .list files count.
		'/lib/apk/packages/base-files.list': '',
		'/lib/apk/packages/busybox.list': '',
		'/lib/apk/packages/busybox.conffiles': '',
		'/lib/apk/packages/ucode.list': '',
		'/lib/apk/packages/adblock.list': '',
		'/rom/lib/apk/packages/base-files.list': '',
		'/rom/lib/apk/packages/busybox.list': '',
		'/rom/lib/apk/packages/dnsmasq.list': '',
		'/rom/lib/apk/packages/dnsmasq.conffiles': '',
		'/rom/lib/apk/packages/odhcpd-ipv6only.list': '',
		'/rom/lib/apk/packages/ppp.list': '',
		'/proc/cpuinfo': 'processor\t: 0\nBogoMIPS\t: 48.00\n\nprocessor\t: 1\n\nprocessor\t: 2\n\nprocessor\t: 3\n',
		'/sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq': '1992000\n',
		'/sys/class/thermal/thermal_zone0/type': 'cpu-thermal\n',
		'/sys/class/thermal/thermal_zone0/temp': '47222\n',
		'/proc/meminfo': 'MemTotal:        4029216 kB\nMemFree:         2676148 kB\nMemAvailable:    3401316 kB\n' +
			'SwapTotal:             0 kB\nSwapFree:              0 kB\n',
		'/proc/self/mountinfo': '16 21 31:3 / /rom ro,relatime shared:1 - squashfs /dev/root ro,errors=continue\n' +
			'17 21 0:4 / /proc rw,nosuid,nodev,noexec,noatime shared:2 - proc proc rw\n' +
			'20 21 7:0 / /overlay rw,noatime shared:5 - f2fs /dev/loop0 rw,lazytime\n' +
			'21 1 0:20 / / rw,noatime shared:6 - overlay overlayfs:/overlay rw,lowerdir=/,upperdir=/overlay/upper\n' +
			'23 21 0:21 / /tmp rw,nosuid,nodev,noatime shared:8 - tmpfs tmpfs rw\n' +
			'40 21 179:1 / /mnt/data rw,relatime shared:20 - ext4 /dev/mmcblk0p1 rw\n',
		'/tmp/dhcp.leases': '1790844456 02:00:00:00:00:01 10.100.13.101 Watch *\n' +
			'1790844434 02:00:00:00:00:02 10.100.13.102 iPad *\n',
	},
	commands: {
		"df -Pk '/mnt/data' 2>/dev/null":
			'Filesystem           1024-blocks    Used Available Capacity Mounted on\n' +
			'/dev/mmcblk0p1        30500276    671000  28254596   2% /mnt/data\n',
	},
	ubus: {
		'system:info': { root: { total: 26206784, used: 491880 } },
		'network.interface:dump': { interface: [
			{ interface: 'guest', up: false, l3_device: 'vlan-guest', proto: 'static',
				'ipv4-address': [ { address: '172.16.100.1', mask: 24 } ] },
			{ interface: 'lan', up: true, l3_device: 'br-lan', device: 'br-lan', proto: 'static',
				'ipv4-address': [ { address: '192.168.1.1', mask: 24 } ],
				'ipv6-address': [ { address: 'fd00:ab::1', mask: 64 } ] },
			{ interface: 'loopback', up: true, l3_device: 'lo', proto: 'static',
				'ipv4-address': [ { address: '127.0.0.1', mask: 8 } ] },
			{ interface: 'vpn', up: true, l3_device: 'vpn', proto: 'wireguard', 'ipv4-address': [] },
			{ interface: 'wan', up: true, l3_device: 'eth1', device: 'eth1', proto: 'dhcp',
				'ipv4-address': [ { address: '198.51.100.19', mask: 20 } ], 'ipv6-address': [] },
			{ interface: 'wan6', up: true, l3_device: 'eth1', device: 'eth1', proto: 'dhcpv6',
				'ipv4-address': [], 'ipv6-address': [ { address: '2001:0db8:5000:ee::e157', mask: 128 } ] },
			{ interface: 'wg_mesh', up: true, l3_device: 'wg_mesh', proto: 'wireguard',
				'ipv4-address': [ { address: '10.200.224.11', mask: 32 } ] },
		] },
		'network.wireless:status': () => null,
	},
};

const CLIENT = {};

// A YunCore AX835 access point: two radios, three SSIDs, a small jffs2 overlay.
export const AP = {
	fs: {
		...ROUTER.fs,
		'/proc/sys/kernel/hostname': 'ap\n',
		'/etc/openwrt_release': "DISTRIB_ID='OpenWrt'\nDISTRIB_RELEASE='25.12.5'\nDISTRIB_TARGET='mediatek/filogic'\n",
		'/tmp/sysinfo/model': 'YunCore AX835\n',
		'/proc/device-tree/compatible': 'yuncore,ax835\0mediatek,mt7981\0',
		'/proc/cpuinfo': 'processor\t: 0\nBogoMIPS\t: 26.00\n\nprocessor\t: 1\n',
		'/sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq': null,
		'/sys/class/thermal/thermal_zone0/temp': '62224\n',
		'/proc/meminfo': 'MemTotal:         239572 kB\nMemAvailable:     131572 kB\n' +
			'SwapTotal:             0 kB\nSwapFree:              0 kB\n',
		'/proc/self/mountinfo': '16 21 31:2 / /rom ro,relatime shared:1 - squashfs /dev/root ro\n' +
			'20 21 31:7 / /overlay rw,noatime shared:5 - jffs2 /dev/mtdblock7 rw\n' +
			'21 1 0:20 / / rw,noatime shared:6 - overlay overlayfs:/overlay rw\n',
		// No package lists under /rom, as on an image without one.
		'/rom/lib/apk/packages/base-files.list': null,
		'/rom/lib/apk/packages/busybox.list': null,
		'/rom/lib/apk/packages/dnsmasq.list': null,
		'/rom/lib/apk/packages/dnsmasq.conffiles': null,
		'/rom/lib/apk/packages/odhcpd-ipv6only.list': null,
		'/rom/lib/apk/packages/ppp.list': null,
		'/tmp/dhcp.leases': null,
	},
	commands: {},
	ubus: {
		'system:info': { root: { total: 1664, used: 516 } },
		'network.interface:dump': { interface: [
			{ interface: 'main', up: true, l3_device: 'vlan-main', proto: 'none', 'ipv4-address': [] },
			{ interface: 'upstream', up: true, l3_device: 'vlan-mgmt', proto: 'dhcp',
				'ipv4-address': [ { address: '10.100.11.10', mask: 24 } ] },
		] },
		'network.wireless:status': {
			radio_2G: { up: true, config: { band: '2g', channel: '11', htmode: 'HE20' },
				interfaces: [ { ifname: 'phy0-ap0', config: { ssid: 'Attic', mode: 'ap' } } ] },
			radio_5G: { up: true, config: { band: '5g', channel: 'auto', htmode: 'HE80' },
				interfaces: [
					{ ifname: 'phy1-ap0', config: { ssid: 'OpenWrt5G', mode: 'ap' } },
					{ ifname: 'phy1-ap1', config: { ssid: 'Living Room 5', mode: 'ap' } },
				] },
			radio_6G: { up: false, config: { band: '6g' }, interfaces: [] },
		},
		'hostapd.phy0-ap0:get_status': { freq: 2462, channel: 11, ssid: 'Attic', status: 'ENABLED' },
		'hostapd.phy1-ap0:get_status': { freq: 5745, channel: 149, ssid: 'OpenWrt5G', status: 'ENABLED' },
		'hostapd.phy1-ap1:get_status': { freq: 5745, channel: 149, ssid: 'Living Room 5', status: 'ENABLED' },
		'hostapd.phy0-ap0:get_clients': { clients: { 'aa:00:00:00:00:01': CLIENT } },
		'hostapd.phy1-ap0:get_clients': { clients: {} },
		'hostapd.phy1-ap1:get_clients': { clients: { 'aa:00:00:00:00:02': CLIENT, 'aa:00:00:00:00:03': CLIENT } },
	},
};

// The router with no live package lists, to lay over its files.
export const NO_LISTS = {
	'/lib/apk/packages/base-files.list': null,
	'/lib/apk/packages/busybox.list': null,
	'/lib/apk/packages/ucode.list': null,
	'/lib/apk/packages/adblock.list': null,
};

export const ENV = { SHELL: '/bin/ash', TERM: 'xterm-256color' };
