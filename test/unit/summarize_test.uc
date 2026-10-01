'use strict';

import { describe, it, assert } from 'utest';
import { summarize, format_size, format_uptime, GLYPHS } from 'owrtfetch';

// The data summarize() gets from a router with nothing optional: no disks beyond what
// a test adds, no networks, no Wi-Fi, no DHCP and no swap.
const DATA = {
	user: 'root',
	hostname: 'router',
	os: { name: 'OpenWrt', version: '25.12.5', arch: 'aarch64', target: 'rockchip/armv8' },
	host: 'FriendlyElec NanoPi R5C',
	kernel: '6.12.94',
	uptime_s: 7008,
	load: [ 0.02, 0.05, 0.0 ],
	packages: { total: 212, image: 180, added: 0, removed: 0 },
	shell: { path: '/bin/ash', version: '1.37.0' },
	terminal: 'xterm-256color',
	cpu: { name: 'rk3568', cores: 4, max_mhz: 1992, temperature_c: 47.222 },
	memory: { total_kib: 4029216, used_kib: 627900 },
	swap: { total_kib: 0, used_kib: 0 },
	disks: [],
	networks: [],
	wifi: [],
	dhcp_leases: null,
};

// These tests read the summary written for a UTF-8 terminal; what ASCII changes has
// tests of its own.
function fields(changes) {
	return summarize({ ...DATA, ...(changes ?? {}) }, GLYPHS.utf8).fields;
}

function value(changes, label) {
	return filter(fields(changes), f => f[0] == label)[0]?.[1];
}

function labels(changes) {
	return map(fields(changes), f => f[0]);
}

describe('summarize()', () => {
	it('lays out the lines every box has, in order', () => {
		assert.match([
			[ 'OS', 'OpenWrt 25.12.5 aarch64 (rockchip/armv8)' ],
			[ 'Host', 'FriendlyElec NanoPi R5C' ],
			[ 'Kernel', '6.12.94' ],
			[ 'Uptime', '1 hour, 56 mins' ],
			[ 'Load', '0.02, 0.05, 0.00' ],
			[ 'Packages', [ '212 (apk)' ] ],
			[ 'Shell', 'ash 1.37.0' ],
			[ 'CPU', 'rk3568 (4) @ 1.992GHz - 47.2°C' ],
			[ 'Memory', '613MiB / 3934MiB (16%)' ],
		], fields());
	});

	it('names the device only where it differs from the interface', () => {
		const networks = [
			{ interface: 'wan', device: 'eth1', addresses: [ '198.51.100.19/20' ] },
			{ interface: 'wg_mesh', device: 'wg_mesh', addresses: [ '10.200.224.11/32' ] },
		];

		assert.match('198.51.100.19/20 - eth1', value({ networks }, 'Net (wan)'));
		assert.match('10.200.224.11/32', value({ networks }, 'Net (wg_mesh)'));
	});

	it('gives each address a line of its own, and none to an interface without one', () => {
		const networks = [
			{ interface: 'lan', device: 'br-lan', addresses: [ '192.168.1.1/24', 'fd00:ab::1/64' ] },
			{ interface: 'vpn', device: 'vpn', addresses: [] },
		];

		assert.match([
			[ 'Net (lan)', '192.168.1.1/24 - br-lan' ],
			[ 'Net (lan)', 'fd00:ab::1/64 - br-lan' ],
		], filter(fields({ networks }), f => index(f[0], 'Net') == 0));
	});

	it('puts the client count before the band and channel', () => {
		const wifi = [ { ssid: 'Casa', ifname: 'phy1-ap0', mode: 'ap', band: '5g', channel: 149, htmode: 'HE80', clients: 2 } ];

		assert.match('2 clients, 5G ch 149 HE80', value({ wifi }, 'Wi-Fi (Casa)'));
	});

	it('names a Wi-Fi interface that is not an access point by its mode, first', () => {
		const wifi = [ { ssid: 'Up', ifname: 'phy1-sta0', mode: 'sta', band: '5g', channel: 36, htmode: null, clients: null } ];

		assert.match('sta, 5G ch 36', value({ wifi }, 'Wi-Fi (Up)'));
	});

	it('labels an SSID-less interface by its name', () => {
		const wifi = [ { ssid: null, ifname: 'phy0-mesh0', mode: 'mesh', band: '2g', channel: 1, htmode: 'HT20', clients: null } ];

		assert.match('mesh, 2.4G ch 1 HT20', value({ wifi }, 'Wi-Fi (phy0-mesh0)'));
	});

	it('shows swap only where there is some', () => {
		assert.match([], filter(labels(), l => l == 'Swap'));
		assert.match('255MiB / 1023MiB (25%)', value({ swap: { total_kib: 1048572, used_kib: 262140 } }, 'Swap'));
	});

	it('labels each disk by its mount point', () => {
		const disks = [
			{ mount: '/overlay', type: 'jffs2', total_kib: 1664, used_kib: 516 },
			{ mount: '/', type: 'ext4', total_kib: 26206784, used_kib: 491880 },
			{ mount: '/mnt/usb', type: null, total_kib: 7806976, used_kib: 3903488 },
		];

		assert.match([
			[ 'Disk (/overlay)', '516.0KiB / 1.6MiB (31%) - jffs2' ],
			[ 'Disk (/)', '480.4MiB / 25.0GiB (2%) - ext4' ],
			[ 'Disk (/mnt/usb)', '3.7GiB / 7.4GiB (50%)' ],
		], filter(fields({ disks }), f => index(f[0], 'Disk') == 0));
	});

	it('shows packages added and removed since flashing, each highlighted', () => {
		assert.match([ '212 (apk), ', { text: '+41', style: 'added' }, ' and ', { text: '-7', style: 'removed' }, ' since flashing' ],
			value({ packages: { total: 212, image: 178, added: 41, removed: 7 } }, 'Packages'));
	});

	it('leaves out the side where nothing changed', () => {
		assert.match([ '183 (apk), ', { text: '+3', style: 'added' }, ' since flashing' ],
			value({ packages: { total: 183, image: 180, added: 3, removed: 0 } }, 'Packages'));
		assert.match([ '175 (apk), ', { text: '-5', style: 'removed' }, ' since flashing' ],
			value({ packages: { total: 175, image: 180, added: 0, removed: 5 } }, 'Packages'));
	});

	it('shows the count alone when nothing changed, or what changed is unknown', () => {
		assert.match([ '180 (apk)' ], value({ packages: { total: 180, image: 180, added: 0, removed: 0 } }, 'Packages'));
		assert.match([ '180 (apk)' ], value({ packages: { total: 180, image: null, added: null, removed: null } }, 'Packages'));
	});

	it('reports unknown packages where there is no count', () => {
		assert.match([ 'unknown' ], value({ packages: { total: null, image: null, added: null, removed: null } }, 'Packages'));
	});

	it('names a generic host where the board has no model', () => {
		assert.match('Generic OpenWrt', value({ host: null }, 'Host'));
	});

	it('names only the distribution where the release is unknown', () => {
		assert.match('OpenWrt', value({ os: { name: 'OpenWrt', version: null, arch: 'aarch64', target: null } }, 'OS'));
	});

	it('names only the shell where no package installed it, and nothing without one', () => {
		assert.match('zsh', value({ shell: { path: '/usr/local/bin/zsh', version: null } }, 'Shell'));
		assert.match('', value({ shell: null }, 'Shell'));
	});

	it('shows DHCP leases only where dnsmasq keeps them', () => {
		assert.match([], filter(labels(), l => l == 'DHCP leases'));
		assert.match('0', value({ dhcp_leases: 0 }, 'DHCP leases'));
	});

	it('writes the temperature without a degree sign in ASCII, and changes nothing else', () => {
		const ascii = summarize(DATA, GLYPHS.ascii).fields, utf8 = fields();

		assert.match([ 'CPU', 'rk3568 (4) @ 1.992GHz - 47.2C' ], filter(ascii, f => f[0] == 'CPU')[0]);
		assert.match([ 'CPU', 'rk3568 (4) @ 1.992GHz - 47.2°C' ], filter(utf8, f => f[0] == 'CPU')[0]);
		assert.match(filter(utf8, f => f[0] != 'CPU'), filter(ascii, f => f[0] != 'CPU'));
	});

	it('leaves the terminal type to the data', () => {
		assert.match([], filter(labels(), l => l == 'Terminal'));
	});
});

describe('format_uptime()', () => {
	it('shows minutes alone under an hour', () => {
		assert.match('0 mins', format_uptime(59));
		assert.match('1 min', format_uptime(60));
		assert.match('59 mins', format_uptime(3599));
	});

	it('adds hours from one hour', () => {
		assert.match('1 hour, 0 mins', format_uptime(3600));
		assert.match('2 hours, 1 min', format_uptime(7260));
	});

	it('adds days from one day, and skips zero hours', () => {
		assert.match('1 day, 0 mins', format_uptime(86400));
		assert.match('2 days, 3 hours, 4 mins', format_uptime(2 * 86400 + 3 * 3600 + 4 * 60));
	});
});

describe('format_size()', () => {
	it('keeps KiB below one MiB', () => {
		assert.match('1023.0KiB', format_size(1023));
	});

	it('switches to MiB at 1024 KiB', () => {
		assert.match('1.0MiB', format_size(1024));
	});

	it('switches to GiB at 1048576 KiB', () => {
		assert.match('1.0GiB', format_size(1048576));
	});

	it('moves up a unit when rounding would reach 1024', () => {
		assert.match('1.0MiB', format_size(1023.96));
		assert.match('1.0GiB', format_size(1048575));
		assert.match('1.0TiB', format_size(1073689396));
	});

	it('shows disks past 1024 GiB in TiB', () => {
		assert.match('1.8TiB', format_size(1953514584));
	});
});
