'use strict';

// A lightweight neofetch clone for OpenWrt. Reads /proc, sysfs and ubus directly, so a
// run starts no other process unless it has disks beyond the overlay or ubus is down.
//
// Three layers, each a function of the one before and a module of its own:
// owrtfetch.collect reads the system into plain data (what --json prints),
// owrtfetch.summarize turns the data into labelled lines, and owrtfetch.render lays
// those out beside the logo in 80 columns. This module is the command line: it reads
// the arguments and the environment, and it alone imports the layers.

import { collect } from 'owrtfetch.collect';
import { summarize } from 'owrtfetch.summarize';
import { render, GLYPHS } from 'owrtfetch.render';

const USAGE = `Usage: owrtfetch [--json] [--utf8 | --ascii]

Prints the OpenWrt logo beside a summary of this system. Colours are left out when
NO_COLOR is set or the output is not a terminal. Characters beyond ASCII, such as the
degree sign, are used only when the locale (LC_ALL, LC_CTYPE or LANG) is UTF-8.

  --json      the summary's data as JSON instead
  --utf8      use UTF-8 characters whatever the locale
  --ascii     use only ASCII whatever the locale
  -h, --help  this help
`;

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
