'use strict';

// Running collect() and render() against the fixtures, and reading what they give.

import { mock } from 'utest';
import { collect, summarize, render, GLYPHS } from 'owrtfetch';
import { ENV } from 'owrtfetch_fixtures';

export const RESET = '\x1b[0m';
export const BLUE  = '\x1b[1;34m';
export const GRAY  = '\x1b[1;30m';
export const GREEN = '\x1b[1;32m';
export const RED   = '\x1b[1;31m';

// fn() on `box`, with `opts.fs` and `opts.ubus` laid over its files and ubus objects: a
// null file is absent. `opts.ubus_down` makes connect() fail.
export function on(box, opts, fn) {
	const env = opts?.env ?? ENV;
	let result;

	mock.global.patch('fs', {
		strict: true,
		data: { ...box.fs, ...(opts?.fs ?? {}) },
		commands: { ...box.commands, ...(opts?.commands ?? {}) },
	});
	mock.global.patch('ubus', opts?.ubus_down
		? { behavior: { connect: () => null } }
		: { strict: true, data: { ...box.ubus, ...(opts?.ubus ?? {}) } });
	mock.inject_builtin('getenv', (name) => env[name], () => { result = fn(); });

	return result;
};

// The summary of `box`, and the data it comes from. The summary is written for a UTF-8
// terminal unless `opts.glyphs` names another set.
export function collect_on(box, opts) {
	const data = on(box, opts, collect);

	return { ...summarize(data, opts?.glyphs ?? GLYPHS.utf8), data };
};

export function field(info, label) {
	return filter(info.fields, f => f[0] == label)[0]?.[1];
};

export function labels(info) {
	return map(info.fields, f => f[0]);
};

export function columns(s) {
	let n = 0;
	for (let i = 0; i < length(s); i++)
		if ((ord(s, i) & 0xC0) != 0x80)
			n++;

	return n;
};

// The lines render() prints with the GLYPHS `g`, as the terminal shows them.
export function visible(info, g) {
	return split(replace(render(info, true, g), regexp('\x1b\\[[0-9;]*m', 'g'), ''), '\n');
};

// Lines past 80 columns, or with something cut to fit them.
export function overflowing(info, g) {
	return filter(visible(info, g), l => columns(l) > 80 || index(l, g.ellipsis) >= 0);
};
