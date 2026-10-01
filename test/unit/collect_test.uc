'use strict';

import { describe, it, afterEach, mock, assert } from 'utest';
import { GLYPHS } from 'owrtfetch';
import { ROUTER, AP, ENV, NO_LISTS } from 'owrtfetch_fixtures';
import { collect_on, field, labels, overflowing } from 'owrtfetch_helpers';

// collect() reads through fs and ubus, both mocked strictly: a file, command or call the
// fixture does not hold fails the test.

describe('collect() on a router', () => {
	it('fits 80 columns written in ASCII too', () => {
		const info = collect_on(ROUTER, { glyphs: GLYPHS.ascii });

		assert.match([], overflowing(info, GLYPHS.ascii));
		assert.match('rk3568 (4) @ 1.992GHz - 47.2C', field(info, 'CPU'));
	});

	afterEach(() => {
		mock.global.unpatch('fs');
		mock.global.unpatch('ubus');
	});

	it('reads the data in plain units', () => {
		const data = collect_on(ROUTER).data;

		assert.match({ name: 'OpenWrt', version: '25.12.5', arch: 'aarch64', target: 'rockchip/armv8' }, data.os);
		assert.match(7008, data.uptime_s);
		assert.match([ 0.02, 0.05, 0.07 ], data.load);
		assert.match({ total: 4, image: 5, added: 2, removed: 3 }, data.packages);
		assert.match({ path: '/bin/ash', version: '1.37.0' }, data.shell);
		assert.match({ name: 'rk3568', cores: 4, max_mhz: 1992, temperature_c: 47.222 }, data.cpu);
		assert.match({ total_kib: 4029216, used_kib: 627900 }, data.memory);
		assert.match({ total_kib: 0, used_kib: 0 }, data.swap);
		assert.match([
			{ mount: '/overlay', type: 'f2fs', total_kib: 26206784, used_kib: 491880 },
			{ mount: '/mnt/data', type: 'ext4', total_kib: 30500276, used_kib: 671000 },
		], data.disks);
		assert.match([
			{ interface: 'lan', device: 'br-lan', addresses: [ '192.168.1.1/24', 'fd00:ab::1/64' ] },
			{ interface: 'vpn', device: 'vpn', addresses: [] },
			{ interface: 'wan', device: 'eth1', addresses: [ '198.51.100.19/20' ] },
			{ interface: 'wan6', device: 'eth1', addresses: [ '2001:0db8:5000:ee::e157/128' ] },
			{ interface: 'wg_mesh', device: 'wg_mesh', addresses: [ '10.200.224.11/32' ] },
		], data.networks);
		assert.match([], data.wifi);
		assert.match(2, data.dhcp_leases);
	});

	it('reads every field', () => {
		const info = collect_on(ROUTER);

		assert.match('root', info.user);
		assert.match('router', info.hostname);
		assert.match([], overflowing(info, GLYPHS.utf8));
		assert.match([
			[ 'OS', 'OpenWrt 25.12.5 aarch64 (rockchip/armv8)' ],
			[ 'Host', 'FriendlyElec NanoPi R5C' ],
			[ 'Kernel', '6.12.94' ],
			[ 'Uptime', '1 hour, 56 mins' ],
			[ 'Load', '0.02, 0.05, 0.07' ],
			[ 'Packages', [ '4 (apk), ', { text: '+2', style: 'added' }, ' and ', { text: '-3', style: 'removed' }, ' since flashing' ] ],
			[ 'Shell', 'ash 1.37.0' ],
			[ 'CPU', 'rk3568 (4) @ 1.992GHz - 47.2°C' ],
			[ 'Memory', '613MiB / 3934MiB (16%)' ],
			[ 'Disk (/overlay)', '480.4MiB / 25.0GiB (2%) - f2fs' ],
			[ 'Disk (/mnt/data)', '655.3MiB / 29.1GiB (2%) - ext4' ],
			[ 'Net (lan)', '192.168.1.1/24 - br-lan' ],
			[ 'Net (lan)', 'fd00:ab::1/64 - br-lan' ],
			[ 'Net (wan)', '198.51.100.19/20 - eth1' ],
			[ 'Net (wan6)', '2001:0db8:5000:ee::e157/128 - eth1' ],
			[ 'Net (wg_mesh)', '10.200.224.11/32' ],
			[ 'DHCP leases', '2' ],
		], info.fields);
	});

	it('reports unknown packages without package lists or a database', () => {
		const info = collect_on(ROUTER, { fs: { ...NO_LISTS, '/lib/apk/db/installed': null } });

		assert.match({ total: null, image: null, added: null, removed: null }, info.data.packages);
		assert.match([ 'unknown' ], field(info, 'Packages'));
	});

	it('counts the packages in the database where there are no lists', () => {
		const info = collect_on(ROUTER, { fs: NO_LISTS });

		assert.match({ total: 4, image: null, added: null, removed: null }, info.data.packages);
		assert.match([ '4 (apk)' ], field(info, 'Packages'));
	});

	it('counts the packages by their lists without the database', () => {
		const info = collect_on(ROUTER, { fs: { '/lib/apk/db/installed': null } });

		assert.match({ total: 4, image: 5, added: 2, removed: 3 }, info.data.packages);
		assert.match(null, info.data.shell.version);
	});

	it('takes the board from the device tree, without its NUL', () => {
		assert.match('FriendlyElec NanoPi R5C', field(collect_on(ROUTER, { fs: { '/tmp/sysinfo/model': null } }), 'Host'));
	});

	it('names a generic host without a board model', () => {
		const info = collect_on(ROUTER, { fs: { '/tmp/sysinfo/model': null, '/proc/device-tree/model': null } });

		assert.match('Generic OpenWrt', field(info, 'Host'));
	});

	it('names only the distribution without /etc/openwrt_release', () => {
		assert.match('OpenWrt', field(collect_on(ROUTER, { fs: { '/etc/openwrt_release': null } }), 'OS'));
	});

	it('names an x86 CPU by its model, without trademarks or its rated clock', () => {
		const info = collect_on(ROUTER, { fs: {
			'/proc/cpuinfo': 'processor\t: 0\nvendor_id\t: GenuineIntel\nmodel name\t: Intel(R) Core(TM)  i5-8250U CPU @ 1.60GHz\n',
			'/proc/device-tree/compatible': null,
		} });

		assert.match('Intel Core i5-8250U (1) @ 1.992GHz - 47.2°C', field(info, 'CPU'));
	});

	it('names a MIPS SoC by its system type without a device tree', () => {
		const info = collect_on(ROUTER, { fs: {
			'/proc/cpuinfo': 'system type\t\t: MediaTek MT7621 ver:1 eco:3\nmachine\t\t\t: Xiaomi\nprocessor\t\t: 0\n',
			'/proc/device-tree/compatible': null,
		} });

		assert.match('MediaTek MT7621 ver:1 eco:3 (1) @ 1.992GHz - 47.2°C', field(info, 'CPU'));
	});

	it('leaves out the frequency and temperature when the kernel has neither', () => {
		const info = collect_on(ROUTER, { fs: {
			'/sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq': null,
			'/sys/class/thermal/thermal_zone0/type': null,
			'/sys/class/thermal/thermal_zone0/temp': null,
		} });

		assert.match('rk3568 (4)', field(info, 'CPU'));
	});

	it('takes the temperature from the CPU zone when it is not the first', () => {
		const info = collect_on(ROUTER, { fs: {
			'/sys/class/thermal/thermal_zone0/type': 'gpu-thermal\n',
			'/sys/class/thermal/thermal_zone0/temp': '39000\n',
			'/sys/class/thermal/thermal_zone1/type': 'cpu-thermal\n',
			'/sys/class/thermal/thermal_zone1/temp': '51500\n',
		} });

		assert.match('rk3568 (4) @ 1.992GHz - 51.5°C', field(info, 'CPU'));
	});

	it('leaves out the kernel architecture where the kernel does not report it', () => {
		assert.match('OpenWrt 25.12.5 (rockchip/armv8)', field(collect_on(ROUTER, { fs: { '/proc/sys/kernel/arch': null } }), 'OS'));
	});

	it('moves on from a thermal zone it cannot read', () => {
		const info = collect_on(ROUTER, { fs: {
			'/sys/class/thermal/thermal_zone0/temp': '',
			'/sys/class/thermal/thermal_zone1/type': 'gpu-thermal\n',
			'/sys/class/thermal/thermal_zone1/temp': '41000\n',
		} });

		assert.match('rk3568 (4) @ 1.992GHz - 41.0°C', field(info, 'CPU'));
	});

	it('shows each disk once, leaving out bind mounts and repeat mounts', () => {
		const info = collect_on(ROUTER, { fs: {
			'/proc/self/mountinfo': ROUTER.fs['/proc/self/mountinfo'] +
				'41 21 179:1 /docker /opt/docker rw,relatime shared:21 - ext4 /dev/mmcblk0p1 rw\n' +
				'42 21 179:1 / /mnt/again rw,relatime shared:22 - ext4 /dev/mmcblk0p1 rw\n',
		} });

		assert.match([ 'Disk (/overlay)', 'Disk (/mnt/data)' ], filter(labels(info), l => index(l, 'Disk') == 0));
	});

	it('shows a disk whose mount point has a space', () => {
		const info = collect_on(ROUTER, {
			fs: {
				'/proc/self/mountinfo': ROUTER.fs['/proc/self/mountinfo'] +
					'43 21 8:1 / /mnt/usb\\040disk rw,relatime shared:23 - vfat /dev/sda1 rw\n',
			},
			commands: {
				"df -Pk '/mnt/data' '/mnt/usb disk' 2>/dev/null":
					'Filesystem           1024-blocks    Used Available Capacity Mounted on\n' +
					'/dev/mmcblk0p1        30500276    671000  28254596   2% /mnt/data\n' +
					'/dev/sda1              7806976   3903488   3903488  50% /mnt/usb disk\n',
			},
		});

		assert.match('3.7GiB / 7.4GiB (50%) - vfat', field(info, 'Disk (/mnt/usb disk)'));
	});

	it('shows no swap line without swap', () => {
		assert.match([], filter(labels(collect_on(ROUTER)), l => l == 'Swap'));
	});

	it('shows swap in use', () => {
		const info = collect_on(ROUTER, { fs: {
			'/proc/meminfo': 'MemTotal: 4029216 kB\nMemAvailable: 3401316 kB\nSwapTotal: 1048572 kB\nSwapFree: 786432 kB\n',
		} });

		assert.match('255MiB / 1023MiB (25%)', field(info, 'Swap'));
	});

	it('names the effective user', () => {
		const info = collect_on(ROUTER, { fs: { '/proc/self/status': 'Name:\tucode\nUid:\t0\t101\t0\t0\n' } });

		assert.match('network', info.user);
	});

	it('falls back to root for a user missing from /etc/passwd', () => {
		const info = collect_on(ROUTER, { fs: { '/proc/self/status': 'Name:\tucode\nUid:\t1000\t1000\t1000\t1000\n' } });

		assert.match('root', info.user);
	});

	it('names the shell with the version of the package that installed it', () => {
		const info = collect_on(ROUTER, {
			env: { ...ENV, SHELL: '/bin/bash' },
			fs: { '/lib/apk/db/installed': 'C:Q1\nP:bash\nV:5.3-r4\nF:bin\nR:bash\nR:rbash\nF:etc\nR:bash.bashrc\n' },
		});

		assert.match('bash 5.3', field(info, 'Shell'));
	});

	it('names only the shell when no package installed it', () => {
		assert.match('zsh', field(collect_on(ROUTER, { env: { ...ENV, SHELL: '/usr/local/bin/zsh' } }), 'Shell'));
	});

	it('leaves the shell empty when unset', () => {
		const info = collect_on(ROUTER, { env: {} });

		assert.match('', field(info, 'Shell'));
		assert.match(null, info.data.shell);
		assert.match(null, info.data.terminal);
	});

	it('keeps the terminal type in the data but not the summary', () => {
		const info = collect_on(ROUTER);

		assert.match('xterm-256color', info.data.terminal);
		assert.match([], filter(labels(info), l => l == 'Terminal'));
	});

	it('names the root filesystem as / where there is no overlay', () => {
		const info = collect_on(ROUTER, {
			fs: { '/proc/self/mountinfo': '21 1 8:2 / / rw,noatime shared:1 - ext4 /dev/sda2 rw\n' },
		});

		assert.match('480.4MiB / 25.0GiB (2%) - ext4', field(info, 'Disk (/)'));
	});

	it('shows no DHCP leases where dnsmasq keeps none', () => {
		assert.match(null, field(collect_on(ROUTER, { fs: { '/tmp/dhcp.leases': null } }), 'DHCP leases'));
	});

	it('asks df for every disk in one call when ubus is down, and shows no networks', () => {
		const info = collect_on(ROUTER, {
			ubus_down: true,
			commands: {
				"df -Pk '/overlay' '/mnt/data' 2>/dev/null":
					'Filesystem           1024-blocks    Used Available Capacity Mounted on\n' +
					'/dev/loop0            26206784    491880  25714904   2% /overlay\n' +
					'/dev/mmcblk0p1        30500276    671000  28254596   2% /mnt/data\n',
			},
		});

		assert.match('480.4MiB / 25.0GiB (2%) - f2fs', field(info, 'Disk (/overlay)'));
		assert.match('655.3MiB / 29.1GiB (2%) - ext4', field(info, 'Disk (/mnt/data)'));
		assert.match([], filter(labels(info), l => index(l, 'Net (') == 0));
	});

	it('shows no disks when neither ubus nor df answer', () => {
		const info = collect_on(ROUTER, { ubus_down: true, commands: { "df -Pk '/overlay' '/mnt/data' 2>/dev/null": '' } });

		assert.match([], filter(labels(info), l => index(l, 'Disk') == 0));
	});
});

describe('collect() on an access point', () => {
	it('fits 80 columns written in ASCII too', () => {
		assert.match([], overflowing(collect_on(AP, { glyphs: GLYPHS.ascii }), GLYPHS.ascii));
	});

	afterEach(() => {
		mock.global.unpatch('fs');
		mock.global.unpatch('ubus');
	});

	it('reads each SSID as data', () => {
		const data = collect_on(AP).data;

		assert.match([
			{ ssid: 'Attic', ifname: 'phy0-ap0', mode: 'ap', band: '2g', channel: 11, htmode: 'HE20', clients: 1 },
			{ ssid: 'OpenWrt5G', ifname: 'phy1-ap0', mode: 'ap', band: '5g', channel: 149, htmode: 'HE80', clients: 0 },
			{ ssid: 'Living Room 5', ifname: 'phy1-ap1', mode: 'ap', band: '5g', channel: 149, htmode: 'HE80', clients: 2 },
		], data.wifi);
		assert.match(null, data.dhcp_leases);
		assert.match({ total: 4, image: null, added: null, removed: null }, data.packages);
	});

	it('reads every field', () => {
		const info = collect_on(AP);

		assert.match('ap', info.hostname);
		assert.match([], overflowing(info, GLYPHS.utf8));
		assert.match([
			[ 'OS', 'OpenWrt 25.12.5 aarch64 (mediatek/filogic)' ],
			[ 'Host', 'YunCore AX835' ],
			[ 'Kernel', '6.12.94' ],
			[ 'Uptime', '1 hour, 56 mins' ],
			[ 'Load', '0.02, 0.05, 0.07' ],
			[ 'Packages', [ '4 (apk)' ] ],
			[ 'Shell', 'ash 1.37.0' ],
			[ 'CPU', 'mt7981 (2) - 62.2°C' ],
			[ 'Memory', '105MiB / 233MiB (45%)' ],
			[ 'Disk (/overlay)', '516.0KiB / 1.6MiB (31%) - jffs2' ],
			[ 'Net (upstream)', '10.100.11.10/24 - vlan-mgmt' ],
			[ 'Wi-Fi (Attic)', '1 client, 2.4G ch 11 HE20' ],
			[ 'Wi-Fi (OpenWrt5G)', '0 clients, 5G ch 149 HE80' ],
			[ 'Wi-Fi (Living Room 5)', '2 clients, 5G ch 149 HE80' ],
		], info.fields);
	});

	it('takes the channel the radio is on over a configured auto', () => {
		assert.match('0 clients, 5G ch 149 HE80', field(collect_on(AP), 'Wi-Fi (OpenWrt5G)'));
	});

	it('asks iwinfo about an interface hostapd does not run', () => {
		const info = collect_on(AP, { ubus: {
			'hostapd.phy1-ap0:get_status': () => null,
			'hostapd.phy1-ap0:get_clients': () => null,
			'iwinfo:info': (args) => args.device == 'phy1-ap0' ? { frequency: 5180, channel: 36, htmode: 'HE40' } : null,
		} });

		assert.match('5G ch 36 HE40', field(info, 'Wi-Fi (OpenWrt5G)'));
	});

	it('shows the configured band and channel when neither hostapd nor iwinfo answer', () => {
		const info = collect_on(AP, { ubus: {
			'hostapd.phy1-ap0:get_status': () => null,
			'iwinfo:info': () => null,
		} });

		assert.match('0 clients, 5G ch auto HE80', field(info, 'Wi-Fi (OpenWrt5G)'));
	});

	it('leaves out the client count when hostapd does not answer', () => {
		const info = collect_on(AP, { ubus: { 'hostapd.phy0-ap0:get_clients': () => null } });

		assert.match('2.4G ch 11 HE20', field(info, 'Wi-Fi (Attic)'));
	});

	it('names the mode of an interface that is not an access point', () => {
		const info = collect_on(AP, { ubus: {
			'network.wireless:status': {
				radio_5G: { up: true, config: { band: '5g', channel: '36' },
					interfaces: [ { ifname: 'phy1-sta0', config: { ssid: 'Upstream', mode: 'sta' } } ] },
			},
			'hostapd.phy1-sta0:get_status': () => null,
			'iwinfo:info': { frequency: 5180, channel: 36, htmode: 'HE80' },
			'hostapd.phy1-sta0:get_clients': () => null,
		} });

		assert.match('sta, 5G ch 36 HE80', field(info, 'Wi-Fi (Upstream)'));
	});
});
