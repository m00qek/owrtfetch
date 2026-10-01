'use strict';

import { describe, it, afterEach, mock, assert } from 'utest';
import { readfile } from 'fs';
import { main, VERSION } from 'owrtfetch';
import { collect } from 'owrtfetch.collect';
import { ROUTER } from 'owrtfetch_fixtures';
import { on } from 'owrtfetch_helpers';

describe('main()', () => {
	afterEach(() => {
		mock.global.unpatch('fs');
		mock.global.unpatch('ubus');
	});

	const ESC = '\x1b[';

	it('prints the summary in colour to a terminal, with the palette', () => {
		const result = on(ROUTER, null, () => main([], { tty: true }));

		assert.match(0, result.code);
		assert.match(true, index(result.out, `${ESC}1;34m`) >= 0);
		assert.match(true, index(result.out, `${ESC}40m`) >= 0);
	});

	it('leaves out colour and the palette when the output is not a terminal', () => {
		const result = on(ROUTER, null, () => main([], { tty: false }));

		assert.match(-1, index(result.out, ESC));
		assert.match(true, index(result.out, '  |   -   ||  _  |  -__|     |  OS: OpenWrt 25.12.5') >= 0);
	});

	it('leaves out colour when NO_COLOR is set', () => {
		assert.match(-1, index(on(ROUTER, null, () => main([], { tty: true, no_color: '1' })).out, ESC));
	});

	it('keeps colour when NO_COLOR is empty', () => {
		assert.match(true, index(on(ROUTER, null, () => main([], { tty: true, no_color: '' })).out, ESC) >= 0);
	});

	it('prints the data as JSON with --json', () => {
		const result = on(ROUTER, null, () => main([ '--json' ], { tty: true }));

		assert.match(0, result.code);
		assert.match(on(ROUTER, null, collect), json(result.out));
	});

	// The usage patterns, as docopt writes them.
	const USAGE = 'Usage:\n' +
		'  owrtfetch [--json] [--utf8 | --ascii]\n' +
		'  owrtfetch -h | --help\n' +
		'  owrtfetch --version\n';

	it('prints its help with --help or -h, in docopt\'s grammar', () => {
		for (let flag in [ '--help', '-h' ]) {
			const result = main([ flag ], { tty: true });

			assert.match(0, result.code, flag);
			assert.match(0, index(result.out, 'owrtfetch: the OpenWrt logo beside a summary of this system.\n\n' + USAGE + '\nOptions:\n'), flag);
			for (let option in [ '--json', '--utf8', '--ascii', '-h --help', '--version' ])
				assert.match(true, match(result.out, regexp(`\n  ${option} +[A-Z]`)) != null, `${flag}: ${option}`);
		}
	});

	it('keeps its help within 80 columns', () => {
		assert.match([], filter(split(main([ '--help' ], {}).out, '\n'), l => length(l) > 80));
	});

	it('prints its version with --version', () => {
		assert.match({ code: 0, out: `owrtfetch ${VERSION}\n` }, main([ '--version' ], {}));
	});

	it('is the version the package Makefile releases', () => {
		const makefile = readfile('openwrt/owrtfetch/Makefile');

		assert.match(VERSION, match(makefile, /\nPKG_VERSION:=([^\n]+)/)?.[1]);
	});

	it('answers --help and --version wherever they appear, as docopt does', () => {
		assert.match(0, index(main([ '--json', '--nope', '--help' ], {}).out, 'owrtfetch: the OpenWrt logo'));
		assert.match(`owrtfetch ${VERSION}\n`, main([ '--nope', '--version' ], {}).out);
		assert.match(0, index(main([ '--version', '-h' ], {}).out, 'owrtfetch: the OpenWrt logo'));
	});

	// Which glyphs the plain summary of the router is written with: its CPU is at 47.2°C
	// and its title is underlined.
	function mode(args, env) {
		const out = on(ROUTER, null, () => main(args, { tty: false, ...env })).out;

		if (index(out, '47.2°C') >= 0 && index(out, '───') >= 0)
			return 'utf8';
		if (index(out, '47.2C') >= 0 && index(out, '---') >= 0 && match(out, /[\x80-\xff]/) == null)
			return 'ascii';

		return 'mixed';
	}

	it('writes ASCII without a locale', () => {
		assert.match('ascii', mode([], {}));
	});

	it('writes UTF-8 where the locale is UTF-8, however it is spelled', () => {
		for (let lang in [ 'en_US.UTF-8', 'C.UTF-8', 'de_DE.utf8', 'pt_BR.utf-8', 'C.Utf8' ])
			assert.match('utf8', mode([], { lang }), lang);
	});

	it('writes ASCII where the locale is not UTF-8', () => {
		for (let lang in [ 'C', 'POSIX', 'en_US.ISO-8859-1', 'en_US' ])
			assert.match('ascii', mode([], { lang }), lang);
	});

	it('takes LC_ALL over LC_CTYPE and LANG', () => {
		assert.match('ascii', mode([], { lc_all: 'C', lc_ctype: 'C.UTF-8', lang: 'C.UTF-8' }));
		assert.match('utf8', mode([], { lc_all: 'C.UTF-8', lc_ctype: 'C', lang: 'C' }));
	});

	it('takes LC_CTYPE over LANG', () => {
		assert.match('ascii', mode([], { lc_ctype: 'C', lang: 'C.UTF-8' }));
		assert.match('utf8', mode([], { lc_ctype: 'C.UTF-8', lang: 'C' }));
	});

	it('skips a locale variable that is set but empty', () => {
		assert.match('utf8', mode([], { lc_all: '', lc_ctype: '', lang: 'C.UTF-8' }));
		assert.match('utf8', mode([], { lc_all: '', lc_ctype: 'C.UTF-8', lang: 'C' }));
		assert.match('ascii', mode([], { lc_all: '', lc_ctype: '', lang: '' }));
	});

	it('writes UTF-8 with --utf8 whatever the locale', () => {
		assert.match('utf8', mode([ '--utf8' ], {}));
		assert.match('utf8', mode([ '--utf8' ], { lc_all: 'C' }));
	});

	it('writes ASCII with --ascii whatever the locale', () => {
		assert.match('ascii', mode([ '--ascii' ], { lang: 'C.UTF-8' }));
		assert.match('ascii', mode([ '--ascii' ], { lc_all: 'en_US.UTF-8' }));
	});

	it('takes the last of --utf8 and --ascii', () => {
		assert.match('ascii', mode([ '--utf8', '--ascii' ], { lang: 'C.UTF-8' }));
		assert.match('utf8', mode([ '--ascii', '--utf8' ], {}));
	});

	it('prints the same JSON in either mode', () => {
		const utf8 = on(ROUTER, null, () => main([ '--json', '--utf8' ], { tty: false })).out;
		const ascii = on(ROUTER, null, () => main([ '--json', '--ascii' ], { tty: false })).out;

		assert.match(utf8, ascii);
		assert.match(47.222, json(ascii).cpu.temperature_c);
	});

	it('refuses an unknown option with its usage', () => {
		const result = main([ '--jsno' ], { tty: true });

		assert.match(2, result.code);
		assert.match(null, result.out);
		assert.match("owrtfetch: unknown option '--jsno'\n\n" + USAGE, result.err);
	});
});
