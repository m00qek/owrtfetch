'use strict';

import { describe, assert, prop, gen } from 'utest';
import { popen } from 'fs';
import { shell_quote } from 'owrtfetch.collect';
import { format_size, format_uptime } from 'owrtfetch.summarize';
import { render, GLYPHS } from 'owrtfetch.render';
import { columns, visible } from 'owrtfetch_helpers';

// Text with the characters a summary carries: letters, digits, punctuation, spaces
// (runs of them, too) and characters of two, three and four bytes.
function text(min_len, max_len) {
	return gen.map(gen.array(gen.elements('a', 'Z', '0', '9', ' ', ' ', ' ', '-', '/', '.', ':', '(', ')', 'ó', '°', 'ç', '家', '🙂'),
		{ min_len, max_len }), cs => join('', cs));
}

// A value made of parts: plain text and text to highlight as added or removed.
function parts() {
	return gen.array(gen.oneof(text(0, 20), gen.record({ text: text(1, 16), style: gen.elements('added', 'removed') })),
		{ max_len: 6 });
}

function plain(value) {
	return join('', map(value, p => type(p) == 'object' ? p.text : p));
}

// The text coloured as `style` across the rendering, without spaces, which wrapping drops.
const CODES = { added: '\x1b\\[1;32m', removed: '\x1b\\[1;31m' };
function coloured(out, style) {
	return replace(join('', map(match(out, regexp(`${CODES[style]}([^\x1b]*)\x1b\\[0m`, 'g')) ?? [], m => m[1])), / /g, '');
}

// The logo's columns of each line render() prints without colour.
const PLAIN_LOGO = map(split(render({ user: 'u', hostname: 'h', fields: map([ 1, 2, 3, 4, 5, 6, 7, 8 ], () => [ 'x', '' ]) }, false, GLYPHS.ascii), '\n'),
	l => substr(l, 0, 32));

// The layout's properties, for the glyphs named `name`: both modes must keep them.
function render_properties(name) {
	const g = GLYPHS[name];

	prop(`render() keeps every line within 80 columns, beside its logo line (${name})`,
		gen.array(gen.tuple(text(1, 60), text(0, 140)), { max_len: 14 }),
		(fields, ctx) => {
			ctx.classify('a label wider than a line', length(filter(fields, f => columns(f[0]) > 47)));
			const out = visible({ user: 'root', hostname: 'router', fields }, g);

			for (let i, line in out)
				assert.match(true, columns(line) <= 80, `line ${i} takes ${columns(line)} columns: ${line}`);

			// The rows run from the title to the blank line before the palette.
			for (let i = 1; i < 10 && out[i] != ''; i++)
				assert.match(PLAIN_LOGO[i], substr(out[i], 0, 32));
		});

	prop(`render() wraps a value without losing any of it (${name})`,
		gen.tuple(text(1, 30), text(0, 200)),
		(f) => {
			const out = visible({ user: 'root', hostname: 'router', fields: [ f ] }, g);
			let rows = [];
			for (let i = 3; i < length(out) && out[i] != ''; i++)
				push(rows, substr(out[i], 32));

			const shown = substr(join('', rows), length(`${f[0]}:`));
			assert.match(replace(f[1], / /g, ''), replace(shown, / /g, ''));
		});

	prop(`render() lays out highlighted parts as their plain text (${name})`,
		gen.tuple(text(1, 60), parts()),
		(f, ctx) => {
			ctx.classify('highlighted', length(filter(f[1], p => type(p) == 'object')));
			ctx.classify('value below its label', columns(f[0]) > 30);
			const as_parts = { user: 'root', hostname: 'router', fields: [ f ] };
			const as_text = { user: 'root', hostname: 'router', fields: [ [ f[0], plain(f[1]) ] ] };

			assert.match(visible(as_text, g), visible(as_parts, g));
			assert.match(render(as_text, false, g), render(as_parts, false, g));
		});

	prop(`render() colours all of each highlighted part, and only it (${name})`,
		gen.tuple(text(1, 60), parts()),
		(f) => {
			const out = render({ user: 'root', hostname: 'router', fields: [ f ] }, true, g);

			for (let style in [ 'added', 'removed' ])
				assert.match(replace(join('', map(filter(f[1], p => p?.style == style), p => p.text)), / /g, ''),
					coloured(out, style), style);
		});

	prop(`render() keeps a value that fits beside its label on one row (${name})`,
		gen.tuple(text(1, 12), text(0, 34)),
		(f, ctx) => {
			ctx.classify('multibyte', length(f[1]) != columns(f[1]));
			const out = visible({ user: 'root', hostname: 'router', fields: [ f ] }, g);

			assert.match('', out[4], `${f[0]}: ${f[1]}`);
		});
}

describe('properties', () => {
	prop('format_size() gives one decimal under 1024 of its unit, but for the largest',
		gen.int(0, 1 << 42),
		(kib, ctx) => {
			ctx.classify('KiB', kib < 1024);
			ctx.classify('near a unit boundary', kib % 1048576 > 1047552 || (kib % 1024) > 1000);

			const m = match(format_size(kib), /^([0-9]+)\.[0-9](KiB|MiB|GiB|TiB)$/);
			assert.match(true, m != null, `${kib} KiB gave ${format_size(kib)}`);
			assert.match(true, m[2] == 'TiB' || +m[1] < 1024, `${kib} KiB gave ${format_size(kib)}`);
		});

	prop('format_uptime() reads back as the seconds, to the minute',
		gen.int(0, 400 * 86400),
		(secs) => {
			const text = format_uptime(secs);
			const d = +(match(text, /([0-9]+) days?/)?.[1] ?? 0);
			const h = +(match(text, /([0-9]+) hours?/)?.[1] ?? 0);
			const m = +match(text, /([0-9]+) mins?$/)[1];

			assert.match(secs - secs % 60, d * 86400 + h * 3600 + m * 60, text);
			assert.match(true, h < 24 && m < 60, text);
			assert.match(null, match(text, /(^|, )1 [a-z]+s(,|$)|(^|, )(0|[2-9][0-9]*|1[0-9]+) (day|hour|min)(,|$)/), text);
		});

	render_properties('ascii');
	render_properties('utf8');

	prop('shell_quote() hands the shell exactly the string',
		gen.ascii({ min_len: 0, max_len: 40 }),
		(s) => {
			const p = popen(`printf '%s' ${shell_quote(s)}`);
			const got = p.read('all');
			p.close();

			assert.match(s, got);
		}, { runs: 50 });
});
