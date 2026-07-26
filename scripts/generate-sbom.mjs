// SPDX-License-Identifier: GPL-3.0-or-later

import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const makefile = readFileSync(resolve(root, 'luci-app-familycontrol/Makefile'), 'utf8');
const packageJson = JSON.parse(readFileSync(resolve(root, 'package.json'), 'utf8'));
const packageLock = JSON.parse(readFileSync(resolve(root, 'package-lock.json'), 'utf8'));

function makeValue(name) {
	const match = makefile.match(new RegExp(`^${name}:=(.+)$`, 'm'));
	if (!match)
		throw new Error(`Missing ${name} in luci-app-familycontrol/Makefile`);
	return match[1].trim();
}

function packageName(path) {
	const marker = 'node_modules/';
	const start = path.lastIndexOf(marker) + marker.length;
	return path.slice(start);
}

function npmRef(name, version) {
	const escapedName = name.startsWith('@')
		? `%40${name.slice(1)}`
		: name;
	return `pkg:npm/${escapedName}@${version}`;
}

function resolveDependencyPath(ownerPath, dependencyName) {
	let directory = ownerPath;

	while (true) {
		const candidate = directory
			? `${directory}/node_modules/${dependencyName}`
			: `node_modules/${dependencyName}`;
		if (packageLock.packages[candidate])
			return candidate;

		const marker = directory.lastIndexOf('/node_modules/');
		if (marker < 0)
			return `node_modules/${dependencyName}`;
		directory = directory.slice(0, marker);
	}
}

const version = `${makeValue('PKG_VERSION')}-r${makeValue('PKG_RELEASE')}`;
const rootRef = `pkg:generic/familycontrol@${version}`;
const runtimeNames = makeValue('LUCI_DEPENDS')
	.split(/\s+/)
	.map(value => value.replace(/^\+/, ''))
	.filter(Boolean)
	.sort();

const npmPackages = Object.entries(packageLock.packages)
	.filter(([ path ]) => path)
	.sort(([ left ], [ right ]) => left.localeCompare(right));
const componentsByRef = new Map();
const dependenciesByRef = new Map();

for (const [ path, entry ] of npmPackages) {
	const name = packageName(path);
	const ref = npmRef(name, entry.version);

	if (!componentsByRef.has(ref)) {
		const component = {
			'type': 'library',
			'bom-ref': ref,
			'name': name,
			'version': entry.version,
			'scope': 'optional',
			'purl': ref,
			'properties': [
				{ 'name': 'familycontrol:dependency-kind', 'value': 'development' }
			]
		};
		if (entry.license)
			component.licenses = [ { 'license': { 'id': entry.license } } ];
		if (entry.resolved)
			component.externalReferences = [ {
				'type': 'distribution',
				'url': entry.resolved
			} ];
		componentsByRef.set(ref, component);
	}

	const dependencyRefs = dependenciesByRef.get(ref) || new Set();
	for (const dependencyName of Object.keys(entry.dependencies || {})) {
		const dependencyPath = resolveDependencyPath(path, dependencyName);
		const dependency = packageLock.packages[dependencyPath];
		if (!dependency)
			throw new Error(`Cannot resolve ${dependencyName} from ${path}`);
		dependencyRefs.add(npmRef(dependencyName, dependency.version));
	}
	dependenciesByRef.set(ref, dependencyRefs);
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

const rootDependencies = [
	...Object.keys(packageJson.devDependencies || {}).map(name =>
		npmRef(name, packageLock.packages[`node_modules/${name}`].version)),
	...runtimeComponents.map(component => component['bom-ref'])
].sort();

const sbom = {
	'$schema': 'https://cyclonedx.org/schema/bom-1.5.schema.json',
	'bomFormat': 'CycloneDX',
	'specVersion': '1.5',
	'version': 1,
	'metadata': {
		'component': {
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
		}
	},
	'components': [
		...Array.from(componentsByRef.values())
			.sort((left, right) => left['bom-ref'].localeCompare(right['bom-ref'])),
		...runtimeComponents
	],
	'dependencies': [
		{
			'ref': rootRef,
			'dependsOn': rootDependencies
		},
		...Array.from(dependenciesByRef.entries()).map(([ ref, dependsOn ]) => ({
			'ref': ref,
			'dependsOn': Array.from(dependsOn).sort()
		})),
		...runtimeComponents.map(component => ({
			'ref': component['bom-ref'],
			'dependsOn': []
		}))
	].sort((left, right) => left.ref.localeCompare(right.ref))
};

const output = resolve(root, 'sbom/familycontrol.cdx.json');
mkdirSync(dirname(output), { recursive: true });
writeFileSync(output, `${JSON.stringify(sbom, null, 2)}\n`);
