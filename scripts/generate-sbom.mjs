// SPDX-License-Identifier: GPL-3.0-or-later

import { execFileSync } from 'node:child_process';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const makefile = readFileSync(resolve(root, 'luci-app-familycontrol/Makefile'), 'utf8');
const packageJson = JSON.parse(readFileSync(resolve(root, 'package.json'), 'utf8'));

function makeValue(name) {
	const match = makefile.match(new RegExp(`^${name}:=(.+)$`, 'm'));
	if (!match)
		throw new Error(`Missing ${name} in luci-app-familycontrol/Makefile`);
	return match[1].trim();
}

const version = `${makeValue('PKG_VERSION')}-r${makeValue('PKG_RELEASE')}`;
const runtimeNames = makeValue('LUCI_DEPENDS')
	.split(/\s+/)
	.map(value => value.replace(/^\+/, ''))
	.filter(Boolean)
	.sort();

const npmSbom = JSON.parse(execFileSync(
	'npm',
	[ 'sbom', '--sbom-format=cyclonedx' ],
	{ cwd: root, encoding: 'utf8' }
));

delete npmSbom.serialNumber;
delete npmSbom.metadata.timestamp;
npmSbom.metadata.tools = npmSbom.metadata.tools || {};

const rootRef = `pkg:generic/familycontrol@${version}`;
npmSbom.metadata.component = {
	'type': 'application',
	'bom-ref': rootRef,
	'name': 'familycontrol',
	'version': version,
	'licenses': [ { 'license': { 'id': packageJson.license } } ],
	'purl': rootRef,
	'externalReferences': [ {
		'type': 'vcs',
		'url': 'https://github.com/tropikhajma/parentalcontrol'
	} ]
};

for (const component of npmSbom.components || []) {
	component.scope = 'optional';
	component.properties = [
		...(component.properties || []),
		{ 'name': 'familycontrol:dependency-kind', 'value': 'development' }
	];
}

const runtimeComponents = runtimeNames.map(name => ({
	'type': 'library',
	'bom-ref': `openwrt:package:${name}`,
	'name': name,
	'scope': 'required',
	'properties': [
		{ 'name': 'familycontrol:dependency-kind', 'value': 'runtime' },
		{ 'name': 'familycontrol:version-status', 'value': 'resolved-by-openwrt-apk' }
	]
}));
npmSbom.components = [ ...(npmSbom.components || []), ...runtimeComponents ];

const npmRootRef = `${packageJson.name}@${packageJson.version}`;
const npmRootDependency = (npmSbom.dependencies || [])
	.find(dependency => dependency.ref === npmRootRef);
const developmentRefs = npmRootDependency?.dependsOn || [];
npmSbom.dependencies = (npmSbom.dependencies || [])
	.filter(dependency => dependency.ref !== npmRootRef);
npmSbom.dependencies.push({
	'ref': rootRef,
	'dependsOn': [
		...developmentRefs,
		...runtimeComponents.map(component => component['bom-ref'])
	].sort()
});
npmSbom.dependencies.push(...runtimeComponents.map(component => ({
	'ref': component['bom-ref'],
	'dependsOn': []
})));
npmSbom.dependencies.sort((left, right) => left.ref.localeCompare(right.ref));

const output = resolve(root, 'sbom/familycontrol.cdx.json');
mkdirSync(dirname(output), { recursive: true });
writeFileSync(output, `${JSON.stringify(npmSbom, null, 2)}\n`);
