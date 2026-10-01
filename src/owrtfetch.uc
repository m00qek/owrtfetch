'use strict';

// A lightweight neofetch clone for OpenWrt. Reads /proc, sysfs and ubus directly, so a
// run starts no other process unless it has disks beyond the overlay or ubus is down.
//
// Three layers, each a function of the one before: collect() reads the system into
// plain data (what --json prints), summarize() turns the data into labelled lines, and
// render() lays those out beside the logo in 80 columns.

import { readfile, popen, glob } from 'fs';
import { connect } from 'ubus';

const USAGE = `Usage: owrtfetch [--json] [--utf8 | --ascii]

Prints the OpenWrt logo beside a summary of this system. Colours are left out when
NO_COLOR is set or the output is not a terminal. Characters beyond ASCII, such as the
degree sign, are used only when the locale (LC_ALL, LC_CTYPE or LANG) is UTF-8.

  --json      the summary's data as JSON instead
  --utf8      use UTF-8 characters whatever the locale
  --ascii     use only ASCII whatever the locale
  -h, --help  this help
`;

// Each colour by its use; 'added' and 'removed' are the styles a value's parts can ask for.
const COLORS = {
	blue: '\x1b[1;34m', gray: '\x1b[1;30m', reset: '\x1b[0m',
	added: '\x1b[1;32m', removed: '\x1b[1;31m',
};
const NO_COLORS = { blue: '', gray: '', reset: '', added: '', removed: '' };

// What the summary draws with, for a terminal that takes only ASCII (the default: a
// serial console often does) and for one that takes UTF-8. The logo is ASCII in both.
export const GLYPHS = {
	ascii: { rule: '-', ellipsis: '...', degree: 'C' },
	utf8: { rule: '─', ellipsis: '…', degree: '°C' },
};

// The logo, drawn in blue: how far each line is indented, and its art. render() pads
// every line, and the rows below the logo, to LOGO_WIDTH.
const LOGO = [
	[ 3, '_______' ],
	[ 2, '|       |.-----.-----.-----.' ],
	[ 2, '|   -   ||  _  |  -__|     |' ],
	[ 2, '|_______||   __|_____|__|__|' ],
	[ 11, '|__|' ],
	[ 3, '________        __' ],
	[ 2, '|  |  |  |.----.|  |_' ],
	[ 2, '|  |  |  ||   _||   _|' ],
	[ 2, '|________||__|  |____|' ],
];
const LOGO_WIDTH = 32;

// What a serial console gives, and the most a line takes.
const COLUMNS = 80;

// Mount points that are the firmware itself rather than a disk of their own.
const SYSTEM_MOUNTS = [ '/', '/rom', '/overlay' ];

// apk's database of what is installed: a block for each package, 'P:' naming it and
// 'V:' its version, then each directory it owns as an 'F:' line followed by 'R:' lines
// for the files in it, symlinks such as /bin/ash included.
const APK_DB = '/lib/apk/db/installed';

// ---- Data: what the system reports -------------------------------------------------

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

// ---- Lines: the data as labels and values ------------------------------------------

function plural(n, unit) {
	return `${n} ${unit}${n == 1 ? '' : 's'}`;
}

function percent(part, whole) {
	return whole > 0 ? int(part * 100.0 / whole + 0.5) : 0;
}

export function format_uptime(secs) {
	const d = int(secs / 86400), h = int(secs % 86400 / 3600), m = int(secs % 3600 / 60);

	return (d > 0 ? `${plural(d, 'day')}, ` : '') + (h > 0 ? `${plural(h, 'hour')}, ` : '') + plural(m, 'min');
};

// The size with one decimal in the largest unit that keeps it under 1024 once rounded:
// 1048575 KiB is 1.0GiB, not 1024.0MiB.
export function format_size(kib) {
	let size = kib * 1.0;

	for (let unit in [ 'KiB', 'MiB', 'GiB' ]) {
		const shown = sprintf('%.1f', size);
		if (+shown < 1024)
			return shown + unit;

		size /= 1024;
	}

	return sprintf('%.1fTiB', size);
};

// Memory and swap, in whole MiB as free(1) shows them.
function format_usage(u) {
	return sprintf('%dMiB / %dMiB (%d%%)', int(u.used_kib / 1024), int(u.total_kib / 1024),
		percent(u.used_kib, u.total_kib));
}

function format_disk(k) {
	return `${format_size(k.used_kib)} / ${format_size(k.total_kib)} (${percent(k.used_kib, k.total_kib)}%)` +
		(k.type ? ` - ${k.type}` : '');
}

// The count, then what changed since the image was flashed, each side left out when
// nothing changed that way: the added count highlighted as added, the removed as removed.
function format_packages(p) {
	if (p.total == null)
		return [ 'unknown' ];

	const changes = filter([
		p.added > 0 ? { text: `+${p.added}`, style: 'added' } : null,
		p.removed > 0 ? { text: `-${p.removed}`, style: 'removed' } : null,
	], c => c != null);

	if (!length(changes))
		return [ `${p.total} (apk)` ];

	return [
		`${p.total} (apk), `, changes[0],
		...(length(changes) > 1 ? [ ' and ', changes[1] ] : []),
		' since flashing',
	];
}

function format_os(o) {
	if (o.version == null)
		return o.name;

	return `${o.name} ${o.version}` + (o.arch ? ` ${o.arch}` : '') + (o.target ? ` (${o.target})` : '');
}

function format_shell(s) {
	return s ? join(' ', filter([ split(s.path, '/')[-1], s.version ], length)) : '';
}

function format_cpu(c, g) {
	return (c.name ? `${c.name} ` : '') + `(${c.cores})` +
		(c.max_mhz ? sprintf(' @ %.3fGHz', c.max_mhz / 1000.0) : '') +
		(c.temperature_c != null ? sprintf(' - %.1f%s', c.temperature_c, g.degree) : '');
}

const BANDS = { '2g': '2.4G', '5g': '5G', '6g': '6G', '60g': '60G' };

// The clients first, then band and channel, so a line wrapped at 80 columns keeps
// what matters most on the first row.
function format_wifi(w) {
	return join(', ', filter([
		w.mode && w.mode != 'ap' ? w.mode : null,
		w.clients != null ? plural(w.clients, 'client') : null,
		join(' ', filter([
			BANDS[w.band] ?? w.band,
			w.channel != null ? `ch ${w.channel}` : null,
			w.htmode,
		], length)),
	], length));
}

// A line for each address, so an IPv6 address fits in 80 columns, naming the device
// only where the interface's name does not already say it.
function format_networks(networks) {
	let out = [];
	for (let n in networks)
		for (let a in n.addresses)
			push(out, [ `Net (${n.interface})`, a + (n.device && n.device != n.interface ? ` - ${n.device}` : '') ]);

	return out;
}

// The data as the lines the summary shows, each a label and its value, written with the
// GLYPHS `g`. A value is a string, or a list of parts where some are to be highlighted
// (see render()); only Packages has one. Swap, which nearly no router has, shows only
// where there is some.
export function summarize(d, g) {
	return {
		user: d.user,
		hostname: d.hostname,
		fields: [
			[ 'OS', format_os(d.os) ],
			[ 'Host', d.host ?? 'Generic OpenWrt' ],
			[ 'Kernel', d.kernel ],
			[ 'Uptime', format_uptime(d.uptime_s) ],
			[ 'Load', join(', ', map(d.load, v => sprintf('%.2f', v))) ],
			[ 'Packages', format_packages(d.packages) ],
			[ 'Shell', format_shell(d.shell) ],
			[ 'CPU', format_cpu(d.cpu, g) ],
			[ 'Memory', format_usage(d.memory) ],
			...(d.swap.total_kib > 0 ? [ [ 'Swap', format_usage(d.swap) ] ] : []),
			...map(d.disks, k => [ `Disk (${k.mount})`, format_disk(k) ]),
			...format_networks(d.networks),
			...map(d.wifi, w => [ `Wi-Fi (${w.ssid ?? w.ifname})`, format_wifi(w) ]),
			...(d.dhcp_leases != null ? [ [ 'DHCP leases', `${d.dhcp_leases}` ] ] : []),
		],
	};
};

// ---- Layout: the lines beside the logo, in 80 columns ------------------------------

// The columns a string takes: one for each UTF-8 character, so its length without the
// bytes that continue one (0x80-0xBF). A loop over ord() did the same at about 7 µs a
// byte on a router's CPU, and render() measures every word it wraps.
function width(s) {
	return length(replace(s, /[\x80-\xbf]/g, ''));
}

// The string's first `n` columns, and the rest.
function split_at(s, n) {
	let count = 0;
	for (let i = 0; i < length(s); i++)
		if ((ord(s, i) & 0xC0) != 0x80 && count++ == n)
			return [ substr(s, 0, i), substr(s, i) ];

	return [ s, '' ];
}

// The string cut to `cols` columns, ending in `ellipsis` when anything is left out. With
// fewer columns than the ellipsis takes, as '...' can, the ellipsis alone is cut to fit.
// Exported for its tests: render() never has so few columns.
export function fit(s, cols, ellipsis) {
	if (cols < 1)
		return '';
	if (width(s) <= cols)
		return s;

	const e = width(ellipsis);
	if (cols < e)
		return split_at(ellipsis, cols)[0];

	return split_at(s, cols - e)[0] + ellipsis;
};

// The string in lines of at most `cols` columns, broken at spaces, and inside a word
// only when the word is longer than a line. The line's width is kept as it grows, so
// each word is measured once.
function wrap(s, cols) {
	let lines = [], line = '', used = 0;

	for (let word in split(s, ' ')) {
		const w = width(word);
		if (line != '' && used + 1 + w <= cols) {
			line += ' ' + word;
			used += 1 + w;
			continue;
		}

		if (line != '')
			push(lines, line);

		line = word;
		used = w;
		while (used > cols) {
			const parts = split_at(line, cols);
			push(lines, parts[0]);
			line = parts[1];
			used -= cols;
		}
	}
	push(lines, line);

	return lines;
}

// Runs of spaces are cut from this rather than built a character at a time; no line is
// wider than COLUMNS.
const BLANKS = sprintf('%80s', '');

function spaces(cols) {
	return substr(BLANKS, 0, cols);
}

// A line of `glyph` `cols` columns long. The glyph may take several bytes, as '─' does,
// so the line is the spaces with each one replaced, not a cut from a longer line.
function rule(cols, glyph) {
	return replace(spaces(cols), / /g, glyph);
}

// A value's text: a string, or a list of parts, each a string or { text, style }.
function plain(value) {
	return type(value) == 'array' ? join('', map(value, p => type(p) == 'object' ? p.text : p)) : value;
}

// Where in plain(value) its highlighted parts lie, as byte offsets, in order.
function marks(value) {
	let out = [], at = 0;

	for (let p in type(value) == 'array' ? value : []) {
		const text = type(p) == 'object' ? p.text : p;
		if (type(p) == 'object' && p.style)
			push(out, { from: at, to: at + length(text), style: p.style });
		at += length(text);
	}

	return out;
}

// The rows wrap() cut from `text`, with the marked parts put back in the colours `c`.
// The rows are pieces of the text in order, with only spaces dropped between them, so
// each is found where the one before ended; a part cut across rows is coloured on each.
// Colour is applied after wrapping so escape codes never count as columns.
function restyle(text, rows, spans, c) {
	if (!length(spans))
		return rows;

	let out = [], at = 0;
	for (let row in rows) {
		while (substr(text, at, length(row)) != row && substr(text, at, 1) == ' ')
			at++;

		const end = at + length(row);
		let line = '', pos = at;
		for (let m in spans) {
			const from = max(m.from, pos), to = min(m.to, end);
			if (from >= to)
				continue;

			line += substr(text, pos, from - pos) + c[m.style] + substr(text, from, to - from) + c.reset;
			pos = to;
		}
		push(out, line + substr(text, pos, end - pos));
		at = end;
	}

	return out;
}

// Fewest columns a value is wrapped into beside its label; a longer label puts it below.
const MIN_VALUE = 16;
// How far a value put below its label is indented.
const HANGING = 2;

// The rows a field takes in `room` columns. Its value follows the label and wraps
// aligned with itself; after a label that leaves it too few columns, it starts on the
// next row instead. Only a label wider than `room` is cut.
function field_rows(f, room, c, g) {
	const label = `${f[0]}:`;
	const text = plain(f[1]), spans = marks(f[1]);
	const beside = room - width(label) - 1;

	if (beside >= MIN_VALUE) {
		const lines = restyle(text, wrap(text, beside), spans, c);
		return [
			`${c.blue}${label}${c.reset} ${lines[0]}`,
			...map(slice(lines, 1), l => spaces(width(label) + 1) + l),
		];
	}

	return [
		`${c.blue}${fit(label, room, g.ellipsis)}${c.reset}`,
		...(text == '' ? [] : map(restyle(text, wrap(text, room - HANGING), spans, c), l => spaces(HANGING) + l)),
	];
}

// The logo's line beside row `i`, LOGO_WIDTH wide; blank past the logo's end.
function logo_line(i, c) {
	const l = LOGO[i];
	if (!l)
		return spaces(LOGO_WIDTH);

	return `${spaces(l[0])}${c.blue}${l[1]}${c.reset}${spaces(LOGO_WIDTH - l[0] - width(l[1]))}`;
}

// The summary as the terminal shows it: the logo beside the fields, then a palette of
// the terminal's colours, drawn with the GLYPHS `g`. No line takes more than COLUMNS.
// Without colour, the palette, which would be blank, is left out.
export function render(info, color, g) {
	const c = color ? COLORS : NO_COLORS;
	const room = COLUMNS - LOGO_WIDTH;
	const title = fit(`${info.user}@${info.hostname}`, room, g.ellipsis);
	let rows = [ `${c.blue}${title}${c.reset}`, `${c.gray}${rule(width(title), g.rule)}${c.reset}` ];

	for (let f in info.fields)
		push(rows, ...field_rows(f, room, c, g));

	let out = [ '', ...map(rows, (r, i) => logo_line(i, c) + r) ];

	if (color) {
		push(out, '');
		for (let codes in [ [ 40, 47 ], [ 100, 107 ] ]) {
			let line = spaces(LOGO_WIDTH);
			for (let n = codes[0]; n <= codes[1]; n++)
				line += `\x1b[${n}m   ${c.reset}`;
			push(out, line);
		}
	}

	return join('\n', out) + '\n';
};

// ---- Command line ------------------------------------------------------------------

// Whether the locale is UTF-8, in POSIX's order: LC_ALL, then LC_CTYPE, then LANG, each
// only when set to something. 'C.UTF-8', 'en_US.UTF-8' and 'de_DE.utf8' all are.
function utf8_locale(env) {
	const locale = env?.lc_all || env?.lc_ctype || env?.lang;

	return match(locale ?? '', /utf-?8/i) != null;
}

// The command line, `owrtfetch [--json] [--utf8 | --ascii]`, as the exit code and what
// goes to stdout and stderr. `env.tty` says whether stdout is a terminal; `env.no_color`
// is NO_COLOR, which turns colour off when set to anything but ''; `env.lc_all`,
// `env.lc_ctype` and `env.lang` are the locale variables, which --utf8 and --ascii
// override, the last given winning.
export function main(args, env) {
	let json = false, utf8 = null;

	for (let a in args) {
		if (a == '--json')
			json = true;
		else if (a == '--utf8')
			utf8 = true;
		else if (a == '--ascii')
			utf8 = false;
		else if (a == '-h' || a == '--help')
			return { code: 0, out: USAGE };
		else
			return { code: 2, err: `owrtfetch: unknown option '${a}'\n\n${USAGE}` };
	}

	const data = collect();
	if (json)
		return { code: 0, out: sprintf('%.J\n', data) };

	const g = (utf8 ?? utf8_locale(env)) ? GLYPHS.utf8 : GLYPHS.ascii;

	return { code: 0, out: render(summarize(data, g), env?.tty && !env?.no_color, g) };
};
