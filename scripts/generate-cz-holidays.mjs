// SPDX-License-Identifier: GPL-3.0-or-later

import { mkdirSync, writeFileSync } from 'node:fs';
import { URL } from 'node:url';

const fixed = [
	[ 1, 1 ], [ 5, 1 ], [ 5, 8 ], [ 7, 5 ], [ 7, 6 ],
	[ 9, 28 ], [ 10, 28 ], [ 11, 17 ], [ 12, 24 ], [ 12, 25 ], [ 12, 26 ]
];

function easterSunday(year) {
	const a = year % 19;
	const b = Math.floor(year / 100);
	const c = year % 100;
	const d = Math.floor(b / 4);
	const e = b % 4;
	const f = Math.floor((b + 8) / 25);
	const g = Math.floor((b - f + 1) / 3);
	const h = (19 * a + b - d - g + 15) % 30;
	const i = Math.floor(c / 4);
	const k = c % 4;
	const l = (32 + 2 * e + 2 * i - h - k) % 7;
	const m = Math.floor((a + 11 * h + 22 * l) / 451);
	const month = Math.floor((h + l - 7 * m + 114) / 31);
	const day = ((h + l - 7 * m + 114) % 31) + 1;
	return new Date(Date.UTC(year, month - 1, day));
}

function iso(date) {
	return date.toISOString().slice(0, 10);
}

const dates = [];
for (let year = 2026; year <= 2035; year++) {
	for (const [ month, day ] of fixed)
		dates.push(`${year}-${String(month).padStart(2, '0')}-${String(day).padStart(2, '0')}`);

	const easter = easterSunday(year);
	const goodFriday = new Date(easter);
	goodFriday.setUTCDate(easter.getUTCDate() - 2);
	const easterMonday = new Date(easter);
	easterMonday.setUTCDate(easter.getUTCDate() + 1);
	dates.push(iso(goodFriday), iso(easterMonday));
}

dates.sort();
const output = new URL(
	'../luci-app-familycontrol/root/usr/share/familycontrol/cz-holidays-2026-2035.txt',
	import.meta.url
);
mkdirSync(new URL('.', output), { recursive: true });
writeFileSync(output, `${dates.join('\n')}\n`);
