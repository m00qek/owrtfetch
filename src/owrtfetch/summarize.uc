'use strict';

// The lines layer: turns the data collect() returns into labelled lines, each value a
// string or, where some of it is to be highlighted, a list of parts. It is pure: it
// imports nothing, and the glyphs it writes with are passed in.

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
