'use strict';

// The data layer: reads the running system into plain data, what --json prints. Sizes
// are in KiB, times in seconds, temperatures in °C, and what cannot be read is null.
// It is the only layer that touches the system, so the only one that imports fs and
// ubus; it imports nothing else.

import { readfile, popen, glob } from 'fs';
import { connect } from 'ubus';

// Mount points that are the firmware itself rather than a disk of their own.
const SYSTEM_MOUNTS = [ '/', '/rom', '/overlay' ];

// apk's database of what is installed: a block for each package, 'P:' naming it and
// 'V:' its version, then each directory it owns as an 'F:' line followed by 'R:' lines
// for the files in it, symlinks such as /bin/ash included.
const APK_DB = '/lib/apk/db/installed';

// A file's contents without surrounding whitespace, or '' when it cannot be read.
// Device-tree strings end in a NUL; cut there. trim() drops one only as a quirk of its C
// implementation, and a NUL in trim()'s or replace()'s arguments ends the argument early.
function read(path) {
	return trim(split(readfile(path) ?? '', '\0')[0]);
}

function lines(path) {
	return split(read(path), '\n');
}

function count_lines(text, prefix) {
	return length(filter(split(text, '\n'), l => index(l, prefix) == 0));
}

// The value of a 'key: value' line, as in /proc/cpuinfo. `key` goes into the pattern
// as it is, so it must not hold regex syntax; every caller passes a literal.
function field_of(text, key) {
	return match(text, regexp(`(^|\n)${key}[ \t]*:[ \t]*([^\n]*)`))?.[2];
}

// The effective user's name; minimal images may lack 'id' and 'whoami'.
function username() {
	const uid = match(read('/proc/self/status'), /\nUid:\t[0-9]+\t([0-9]+)/)?.[1];

	for (let line in lines('/etc/passwd')) {
		const f = split(line, ':');
		if (f[2] === uid)
			return f[0];
	}

	return 'root';
}

function os() {
	const release = read('/etc/openwrt_release');

	return {
		name: 'OpenWrt',
		version: match(release, /DISTRIB_RELEASE='([^']*)'/)?.[1],
		arch: read('/proc/sys/kernel/arch') || null,
		target: match(release, /DISTRIB_TARGET='([^']*)'/)?.[1],
	};
}

function host() {
	return read('/tmp/sysinfo/model') || read('/proc/device-tree/model') || null;
}

function load() {
	return map(slice(split(read('/proc/loadavg'), ' '), 0, 3), v => +v);
}

// The packages installed under `root`: OpenWrt keeps a lib/apk/packages/<name>.list for
// each, in the image under /rom as well as live. glob() lists them in C, in about 2 ms on
// a router; splitting the two databases for their 'P:' names took about 10.
function package_lists(root) {
	return glob(`${root}/lib/apk/packages/*.list`) ?? [];
}

// How many packages are installed and, on an image with the firmware's own set under
// /rom, how many it had and how many the live system has added and removed since. Where
// there are no lists, the database's 'P:' lines give the count alone.
function packages(db) {
	const live = package_lists('');
	const rom = length(live) ? package_lists('/rom') : [];

	if (!length(rom))
		return {
			total: length(live) || (db == null ? null : length(split(db, '\nP:')) - 1 + (substr(db, 0, 2) == 'P:' ? 1 : 0)),
			image: null,
			added: null,
			removed: null,
		};

	let in_image = {}, added = 0;
	for (let p in rom)
		in_image[substr(p, 4)] = true;
	for (let p in live)
		if (!in_image[p])
			added++;

	// Names are unique, so what the image had and still has is all that was not added.
	return { total: length(live), image: length(rom), added, removed: length(rom) - (length(live) - added) };
}

// The version of the package that installed `path`, without apk's '-r' release. A file
// of that name elsewhere, such as busybox's in lib/upgrade/keep.d, belongs to its own
// directory's 'F:' line.
function package_version(db, path) {
	const slash = rindex(path, '/');
	if (db == null || slash < 0)
		return null;

	const dir = substr(path, 1, slash - 1), needle = `\nR:${substr(path, slash + 1)}\n`;
	for (let offset = 0, at = index(db, needle); at >= 0; at = index(substr(db, offset), needle)) {
		at += offset;
		const head = substr(db, 0, at);
		const f = rindex(head, '\nF:') + 3;
		if (f >= 3 && substr(db, f, index(substr(db, f), '\n')) == dir) {
			const start = rindex(head, '\n\n') + 2;
			const version = match(substr(db, start, at - start), /(^|\n)V:([^\n]*)/)?.[2];
			return version != null ? replace(version, /-r[0-9]+$/, '') : null;
		}
		offset = at + 1;
	}

	return null;
}

function shell(db) {
	const path = getenv('SHELL');

	return path ? { path, version: package_version(db, path) } : null;
}

// x86 names its CPU in /proc/cpuinfo, trademarks and the rated clock aside. Elsewhere the
// SoC is the device tree's most generic compatible string, 'rockchip,rk3568' after
// 'friendlyarm,nanopi-r5c'.
function cpu_name(cpuinfo) {
	const model = field_of(cpuinfo, 'model name');
	if (model)
		return trim(replace(replace(model, /\((R|TM|tm)\)| CPU| @ [0-9.]+ *GHz/g, ''), /[ \t]+/g, ' '));

	const compatible = filter(split(readfile('/proc/device-tree/compatible') ?? '', '\0'), length);
	if (length(compatible))
		return split(compatible[-1], ',')[-1];

	return field_of(cpuinfo, 'system type');
}

// In °C, from the first thermal zone named for the CPU that can be read, else any other.
function temperature() {
	const zones = sort(glob('/sys/class/thermal/thermal_zone*/temp') ?? []);
	const is_cpu = z => index(read(replace(z, /temp$/, 'type')), 'cpu') >= 0;

	for (let z in [ ...filter(zones, is_cpu), ...filter(zones, z => !is_cpu(z)) ]) {
		const millidegrees = read(z);
		if (millidegrees)
			return +millidegrees / 1000.0;
	}

	return null;
}

function cpu() {
	const cpuinfo = read('/proc/cpuinfo');
	const khz = read('/sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq');

	return {
		name: cpu_name(cpuinfo),
		cores: count_lines(cpuinfo, 'processor'),
		max_mhz: khz ? int(+khz / 1000) : null,
		temperature_c: temperature(),
	};
}

function meminfo_kib(meminfo, key) {
	return +match(meminfo, regexp(`${key}:[ \t]+([0-9]+)`))?.[1];
}

function usage_of(meminfo, total_key, free_key) {
	const total = meminfo_kib(meminfo, total_key);

	return { total_kib: total, used_kib: total - meminfo_kib(meminfo, free_key) };
}

// The kernel escapes spaces and the like in mount points as octal: '/mnt/usb\040disk'.
function unescape(path) {
	return replace(path, /\\([0-7][0-7][0-7])/g, (m, o) =>
		chr(+substr(o, 0, 1) * 64 + +substr(o, 1, 1) * 8 + +substr(o, 2, 1)));
}

// Each filesystem once, where it is mounted whole: bind mounts of a subtree and repeat
// mounts of a device are left out.
function mounts() {
	let seen = {}, out = [];

	for (let line in lines('/proc/self/mountinfo')) {
		const halves = split(line, ' - ');
		const f = split(halves[0], ' '), g = split(halves[1] ?? '', ' ');
		if (length(f) < 5 || length(g) < 2 || f[3] != '/' || seen[f[2]])
			continue;

		seen[f[2]] = true;
		push(out, { dev: g[1], dir: unescape(f[4]), type: g[0] });
	}

	return out;
}

// Exported only for its property test: it is what keeps a mount point from being run
// as a command by df's shell.
export function shell_quote(s) {
	return "'" + replace(s, /'/g, "'\\''") + "'";
};

// Usage in KiB of each mount point, by mount point. ucode's fs has no statvfs().
function df(dirs) {
	let usage = {};
	if (!length(dirs))
		return usage;

	const p = popen(`df -Pk ${join(' ', map(dirs, shell_quote))} 2>/dev/null`);
	if (!p)
		return usage;

	for (let line in slice(split(p.read('all') ?? '', '\n'), 1)) {
		const f = match(line, /^[^ \t]+[ \t]+([0-9]+)[ \t]+([0-9]+)[ \t]+[^ \t]+[ \t]+[^ \t]+[ \t]+(.+)$/);
		if (f)
			usage[f[3]] = { total: +f[1], used: +f[2] };
	}
	p.close();

	return usage;
}

// The firmware's writable space where it is mounted, /overlay on a squashfs image and /
// on one without an overlay, then each disk mounted beside it. procd reports the first
// in KiB; the rest, and the first without ubus, come from df.
function disks(bus) {
	const all = mounts();
	const root = filter(all, m => m.dir == '/overlay')[0] ?? filter(all, m => m.dir == '/')[0];
	const root_dir = root?.dir ?? '/overlay';
	const extra = filter(all, m => index(m.dev, '/dev/') == 0 && index(SYSTEM_MOUNTS, m.dir) < 0);
	const procd = bus?.call('system', 'info')?.root;
	const usage = df([ ...(procd ? [] : [ root_dir ]), ...map(extra, m => m.dir) ]);

	let out = [];
	for (let d in [
		{ mount: root_dir, type: root?.type, usage: procd ?? usage[root_dir] },
		...map(extra, m => ({ mount: m.dir, type: m.type, usage: usage[m.dir] })),
	])
		if (d.usage)
			push(out, { mount: d.mount, type: d.type, total_kib: d.usage.total, used_kib: d.usage.used });

	return out;
}

// Each logical interface that is up, as netifd names it, with its addresses.
function networks(bus) {
	let out = [];

	for (let i in bus?.call('network.interface', 'dump')?.interface ?? []) {
		if (!i.up || i.interface == 'loopback')
			continue;

		push(out, {
			interface: i.interface,
			device: i.l3_device ?? i.device,
			addresses: map([ ...(i['ipv4-address'] ?? []), ...(i['ipv6-address'] ?? []) ], a => `${a.address}/${a.mask}`),
		});
	}

	return out;
}

// OpenWrt's name for the band: from the frequency the radio is on, else as configured.
function band(mhz, configured) {
	if (mhz)
		return mhz < 3000 ? '2g' : mhz < 5925 ? '5g' : mhz < 7200 ? '6g' : '60g';

	return configured;
}

// Each SSID on a radio that is up: its band and channel as the radio is on them, else
// as configured, and the clients hostapd has associated. hostapd answers in well under
// a millisecond and iwinfo takes about 15, so iwinfo is asked only about interfaces
// hostapd does not run, such as a station's.
function wifi(bus) {
	let out = [];

	for (let name, radio in bus?.call('network.wireless', 'status') ?? {}) {
		if (!radio.up)
			continue;

		for (let iface in radio.interfaces ?? []) {
			if (!iface.ifname)
				continue;

			const hostapd = `hostapd.${iface.ifname}`;
			const live = bus.call(hostapd, 'get_status') ?? bus.call('iwinfo', 'info', { device: iface.ifname }) ?? {};
			const clients = bus.call(hostapd, 'get_clients')?.clients;

			push(out, {
				ssid: iface.config?.ssid,
				ifname: iface.ifname,
				mode: iface.config?.mode,
				band: band(live.freq ?? live.frequency, radio.config?.band),
				channel: live.channel ?? radio.config?.channel,
				htmode: live.htmode ?? radio.config?.htmode,
				clients: clients != null ? length(clients) : null,
			});
		}
	}

	return out;
}

// dnsmasq's leases; boxes that serve no DHCP have no file.
function leases() {
	const text = readfile('/tmp/dhcp.leases');

	return text == null ? null : length(filter(split(text, '\n'), length));
}

// The running system, as data: sizes in KiB, times in seconds, temperatures in °C. What
// cannot be read is null.
export function collect() {
	// A daemon that hangs must not hold the summary for ubus's default 30 seconds.
	const bus = connect(null, 3);
	const meminfo = read('/proc/meminfo');
	const db = readfile(APK_DB);

	return {
		user: username(),
		hostname: read('/proc/sys/kernel/hostname'),
		os: os(),
		host: host(),
		kernel: read('/proc/sys/kernel/osrelease'),
		uptime_s: int(+split(read('/proc/uptime'), ' ')[0]),
		load: load(),
		packages: packages(db),
		shell: shell(db),
		terminal: getenv('TERM'),
		cpu: cpu(),
		memory: usage_of(meminfo, 'MemTotal', 'MemAvailable'),
		swap: usage_of(meminfo, 'SwapTotal', 'SwapFree'),
		disks: disks(bus),
		networks: networks(bus),
		wifi: wifi(bus),
		dhcp_leases: leases(),
	};
};
