'use strict';

import { describe, it, assert } from 'utest';
import { render, fit, GLYPHS } from 'owrtfetch';
import { RESET, BLUE, GRAY, GREEN, RED, columns, visible } from 'owrtfetch_helpers';

const ASCII = GLYPHS.ascii, UTF8 = GLYPHS.utf8;

describe('render()', () => {
	it('puts the fields beside the logo, then the palette (ASCII)', () => {
		const info = {
			user: 'root',
			hostname: 'router',
			fields: map([ 'OS', 'Host', 'Kernel', 'Uptime', 'Packages', 'Shell', 'Terminal', 'CPU', 'Memory', 'Disk' ],
				l => [ l, lc(l) ]),
		};
		const row = (logo, label) => `${logo}${BLUE}${label}:${RESET} ${lc(label)}`;
		const pad = '                                ';

		assert.match(join('\n', [
			'',
			`   ${BLUE}_______${RESET}                      ${BLUE}root@router${RESET}`,
			`  ${BLUE}|       |.-----.-----.-----.${RESET}  ${GRAY}-----------${RESET}`,
			row(`  ${BLUE}|   -   ||  _  |  -__|     |${RESET}  `, 'OS'),
			row(`  ${BLUE}|_______||   __|_____|__|__|${RESET}  `, 'Host'),
			row(`           ${BLUE}|__|${RESET}                 `, 'Kernel'),
			row(`   ${BLUE}________        __${RESET}           `, 'Uptime'),
			row(`  ${BLUE}|  |  |  |.----.|  |_${RESET}         `, 'Packages'),
			row(`  ${BLUE}|  |  |  ||   _||   _|${RESET}        `, 'Shell'),
			row(`  ${BLUE}|________||__|  |____|${RESET}        `, 'Terminal'),
			row(pad, 'CPU'),
			row(pad, 'Memory'),
			row(pad, 'Disk'),
			'',
			pad + join('', map([ 40, 41, 42, 43, 44, 45, 46, 47 ], c => `\x1b[${c}m   ${RESET}`)),
			pad + join('', map([ 100, 101, 102, 103, 104, 105, 106, 107 ], c => `\x1b[${c}m   ${RESET}`)),
		]) + '\n', render(info, true, ASCII));
	});

	it('wraps a long value at spaces, aligned with where it starts', () => {
		const out = visible({ user: 'root', hostname: 'router', fields: [
			[ 'Host', 'Xiaomi Mi Router AX3000T (OpenWrt U-Boot layout) with a long name' ],
		] }, ASCII);

		assert.match('  |   -   ||  _  |  -__|     |  Host: Xiaomi Mi Router AX3000T (OpenWrt U-Boot', out[3]);
		assert.match('  |_______||   __|_____|__|__|        layout) with a long name', out[4]);
	});

	it('moves the fields after a wrapped one down, beside the next lines of the logo', () => {
		const out = visible({ user: 'root', hostname: 'router', fields: [
			[ 'Host', 'Xiaomi Mi Router AX3000T (OpenWrt U-Boot layout) with a long name' ],
			[ 'Kernel', '6.12.94' ],
		] }, ASCII);

		assert.match('           |__|                 Kernel: 6.12.94', out[5]);
	});

	it('counts a multibyte character as one column', () => {
		const value = 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx°';
		const out = visible({ user: 'root', hostname: 'router', fields: [ [ 'CPU', value ] ] }, ASCII);

		assert.match(`  |   -   ||  _  |  -__|     |  CPU: ${value}`, out[3]);
		assert.match(80, columns(out[3]));
	});

	it('counts a character of three or four bytes as one column', () => {
		const value = 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx家🙂';
		const out = visible({ user: 'root', hostname: 'router', fields: [ [ 'CPU', value ] ] }, ASCII);

		assert.match(`  |   -   ||  _  |  -__|     |  CPU: ${value}`, out[3]);
		assert.match(80, columns(out[3]));
		assert.match('', out[4], 'the value fits, so it takes no second row');
	});

	it('breaks a word longer than a line at the edge', () => {
		const out = visible({ user: 'root', hostname: 'router', fields: [
			[ 'Net (wan6)', '2001:0db8:5000:ee00:1111:2222:3333:4444:5555:6666:7777/128' ],
		] }, ASCII);

		assert.match('  |   -   ||  _  |  -__|     |  Net (wan6): 2001:0db8:5000:ee00:1111:2222:3333:4', out[3]);
		assert.match(80, columns(out[3]));
		assert.match('  |_______||   __|_____|__|__|              444:5555:6666:7777/128', out[4]);
	});

	it('puts a value below a label that leaves it too few columns', () => {
		const out = visible({ user: 'root', hostname: 'router', fields: [
			[ 'Wi-Fi (Casa da Vó Lurdinha e família 5G)', '5 clients, 5G ch 149 HE80' ],
		] }, ASCII);

		assert.match('  |   -   ||  _  |  -__|     |  Wi-Fi (Casa da Vó Lurdinha e família 5G):', out[3]);
		assert.match('  |_______||   __|_____|__|__|    5 clients, 5G ch 149 HE80', out[4]);
	});

	it('cuts only a label wider than a line, with … in UTF-8', () => {
		const out = visible({ user: 'root', hostname: 'router', fields: [
			[ 'Wi-Fi (An SSID of the thirty-two bytes allowed!!)', '1 client, 5G ch 36 HE80' ],
		] }, UTF8);

		assert.match('  |   -   ||  _  |  -__|     |  Wi-Fi (An SSID of the thirty-two bytes allowed!…', out[3]);
		assert.match(80, columns(out[3]));
		assert.match('  |_______||   __|_____|__|__|    1 client, 5G ch 36 HE80', out[4]);
	});

	it('cuts a label wider than a line with ... in ASCII', () => {
		const out = visible({ user: 'root', hostname: 'router', fields: [
			[ 'Wi-Fi (An SSID of the thirty-two bytes allowed!!)', '1 client, 5G ch 36 HE80' ],
		] }, ASCII);

		assert.match('  |   -   ||  _  |  -__|     |  Wi-Fi (An SSID of the thirty-two bytes allowe...', out[3]);
		assert.match(80, columns(out[3]));
		assert.match('  |_______||   __|_____|__|__|    1 client, 5G ch 36 HE80', out[4]);
	});

	it('underlines the title to its length with - in ASCII', () => {
		const out = split(render({ user: 'network', hostname: 'ap-1', fields: [] }, true, ASCII), '\n');

		assert.match(`  ${BLUE}|       |.-----.-----.-----.${RESET}  ${GRAY}------------${RESET}`, out[2]);
	});

	it('underlines the title to its length with ─ in UTF-8', () => {
		const out = split(render({ user: 'network', hostname: 'ap-1', fields: [] }, true, UTF8), '\n');

		assert.match(`  ${BLUE}|       |.-----.-----.-----.${RESET}  ${GRAY}────────────${RESET}`, out[2]);
	});

	it('cuts a title wider than a line, and its underline with it', () => {
		const info = { user: 'root', hostname: 'a-hostname-far-longer-than-anyone-would-give-a-router', fields: [] };

		assert.match('   _______                      root@a-hostname-far-longer-than-anyone-would-...', visible(info, ASCII)[1]);
		assert.match('  |       |.-----.-----.-----.  ------------------------------------------------', visible(info, ASCII)[2]);
		assert.match('   _______                      root@a-hostname-far-longer-than-anyone-would-gi…', visible(info, UTF8)[1]);
		assert.match(80, columns(visible(info, UTF8)[2]));
	});

	it('draws the same logo in both modes', () => {
		const info = { user: 'root', hostname: 'router', fields: map([ 1, 2, 3, 4, 5, 6, 7 ], () => [ 'x', 'y' ]) };

		assert.match(map(visible(info, ASCII), l => substr(l, 0, 32)), map(visible(info, UTF8), l => substr(l, 0, 32)));
	});
});

describe('render() with highlighted parts', () => {
	const PACKAGES = [ '212 (apk), ', { text: '+41', style: 'added' }, ' and ', { text: '-7', style: 'removed' }, ' since flashing' ];
	const LOGO_2 = `  ${BLUE}|   -   ||  _  |  -__|     |${RESET}  `;
	const LOGO_3 = `  ${BLUE}|_______||   __|_____|__|__|${RESET}  `;

	function rows(value, color) {
		return split(render({ user: 'root', hostname: 'router', fields: [ [ 'Packages', value ] ] }, color, ASCII), '\n');
	}

	it('colours each highlighted part in colour', () => {
		assert.match(`${LOGO_2}${BLUE}Packages:${RESET} 212 (apk), ${GREEN}+41${RESET} and ${RED}-7${RESET} since flashing`, rows(PACKAGES, true)[3]);
	});

	it('writes the parts plain without colour', () => {
		assert.match('  |   -   ||  _  |  -__|     |  Packages: 212 (apk), +41 and -7 since flashing', rows(PACKAGES, false)[3]);
	});

	it('colours each piece of a part wrapped across rows', () => {
		const out = rows([ 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxx ', { text: 'aaaa bbbb cccc dddd', style: 'added' } ], true);

		assert.match(`${LOGO_2}${BLUE}Packages:${RESET} xxxxxxxxxxxxxxxxxxxxxxxxxxxxxx ${GREEN}aaaa${RESET}`, out[3]);
		assert.match(`${LOGO_3}          ${GREEN}bbbb cccc dddd${RESET}`, out[4]);
	});

	it('colours each piece of a part broken inside a word', () => {
		const out = rows([ { text: 'yyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy', style: 'removed' } ], true);

		assert.match(`${LOGO_2}${BLUE}Packages:${RESET} ${RED}yyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy${RESET}`, out[3]);
		assert.match(`${LOGO_3}          ${RED}yyyyyyy${RESET}`, out[4]);
	});

	it('colours the parts of a value put below a long label', () => {
		const out = split(render({ user: 'root', hostname: 'router', fields: [
			[ 'Packages (a label long enough to push the value down)', [ '212 (apk), ', { text: '+41', style: 'added' } ] ],
		] }, true, ASCII), '\n');

		assert.match(`${LOGO_3}  212 (apk), ${GREEN}+41${RESET}`, out[4]);
	});

	it('lays out a list of parts as the string they make', () => {
		assert.match(rows('212 (apk), +41 and -7 since flashing', true), rows([ '212 (apk), +41 ', 'and -7 since flashing' ], true));
	});
});

describe('fit()', () => {
	it('leaves a string that fits as it is', () => {
		assert.match('abcde', fit('abcde', 5, ASCII.ellipsis));
		assert.match('ááááá', fit('ááááá', 5, UTF8.ellipsis));
	});

	it('keeps three columns for the ASCII ellipsis', () => {
		assert.match('ab...', fit('abcdefgh', 5, ASCII.ellipsis));
		assert.match('á...', fit('ááááá', 4, ASCII.ellipsis));
	});

	it('keeps one column for the UTF-8 ellipsis', () => {
		assert.match('abcd…', fit('abcdefgh', 5, UTF8.ellipsis));
	});

	it('cuts the ellipsis itself when there are fewer columns than it takes', () => {
		assert.match('...', fit('abcdefgh', 3, ASCII.ellipsis));
		assert.match('..', fit('abcdefgh', 2, ASCII.ellipsis));
		assert.match('.', fit('abcdefgh', 1, ASCII.ellipsis));
		assert.match('…', fit('abcdefgh', 1, UTF8.ellipsis));
	});

	it('gives nothing in no columns', () => {
		assert.match('', fit('abcdefgh', 0, ASCII.ellipsis));
		assert.match('', fit('abcdefgh', -1, UTF8.ellipsis));
	});
});
