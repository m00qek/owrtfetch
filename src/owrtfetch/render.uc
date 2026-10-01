'use strict';

// The layout layer: lays labelled lines out beside the logo in 80 columns, wrapping
// long values, and owns how the summary is drawn: the logo, the colours, and the
// GLYPHS for ASCII and UTF-8 terminals. It is pure and imports nothing.

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
