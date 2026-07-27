// SPDX-License-Identifier: GPL-3.0-or-later

'use strict';

const ZERO_SESSION = '00000000000000000000000000000000';
const MAC_PATTERN = /^[0-9A-F]{2}(:[0-9A-F]{2}){5}$/;
let session = sessionStorage.getItem('familycontrol-session');
let requestId = 0;
let config = {};
let candidates = [];

const $ = id => document.getElementById(id);

async function rpc(object, method, args = {}, token = session || ZERO_SESSION) {
	const response = await fetch('/ubus', {
		method: 'POST',
		headers: { 'Content-Type': 'application/json' },
		body: JSON.stringify({
			jsonrpc: '2.0',
			id: ++requestId,
			method: 'call',
			params: [ token, object, method, args ]
		})
	});
	const body = await response.json();
	if (body.error)
		throw new Error(body.error.message || 'Request failed');
	if (!body.result || body.result[0] !== 0)
		throw new Error(body.result?.[1]?.message || 'Access denied');
	return body.result[1] || {};
}

function showError(message, login = false) {
	const node = $(login ? 'login-error' : 'error');
	node.textContent = message;
	node.classList.toggle('hidden', !message);
}

function showLogin() {
	$('app').classList.add('hidden');
	$('login').classList.remove('hidden');
}

function escapeHtml(value) {
	return String(value).replace(/[&<>"']/g, c => ({
		'&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'
	})[c]);
}

async function load() {
	const [status, discovered] = await Promise.all([
		rpc('familycontrol', 'status'),
		rpc('familycontrol', 'devices')
	]);
	candidates = discovered.devices || [];
	config = {};
	for (const person of status.people || []) {
		config[person.id] = {
			'.name': person.id,
			'.type': 'person',
			name: person.name,
			paused: person.paused ? '1' : '0'
		};
		for (const device of person.devices || [])
			config[device.id] = {
				'.name': device.id,
				'.type': 'device',
				name: device.name,
				mac: device.mac,
				person: person.id
			};
	}
	render(status.people || []);
}

function render(people) {
	const devices = Object.values(config).filter(s => s['.type'] === 'device');
	$('people').innerHTML = people.length ? people.map(person => {
		const owned = devices.filter(device => device.person === person.id);
		return `<article class="card">
			<div class="row">
				<div>
					<h2>${escapeHtml(person.name)}</h2>
					<p class="meta"><span class="${person.paused ? 'paused' : 'online'}">${person.paused ? 'Paused' : 'Online'}</span>
					· ${owned.length} ${owned.length === 1 ? 'device' : 'devices'}</p>
				</div>
				<button data-action="pause" data-id="${person.id}" data-paused="${!person.paused}"
					${owned.length ? '' : 'disabled'}>${person.paused ? 'Resume' : 'Pause'}</button>
			</div>
			${owned.map(device => `<div class="card">
				<strong>${escapeHtml(device.name || device.mac)}</strong>
				<div class="meta">${escapeHtml(device.mac)}</div>
				<div class="actions">
					<button class="secondary" data-action="edit-device" data-id="${device['.name']}">Edit</button>
					<button class="danger" data-action="delete-device" data-id="${device['.name']}">Remove</button>
				</div>
			</div>`).join('')}
			<div class="actions">
				<button class="secondary" data-action="add-device" data-id="${person.id}">Add device</button>
				<button class="secondary" data-action="edit-person" data-id="${person.id}">Rename</button>
				<button class="danger" data-action="delete-person" data-id="${person.id}">Delete</button>
			</div>
		</article>`;
	}).join('') : '<div class="card empty">No people yet. Add someone to get started.</div>';
}

async function mutateAndReload(method, args) {
	await rpc('familycontrol', method, args);
	await load();
}

$('login-form').addEventListener('submit', async event => {
	event.preventDefault();
	showError('', true);
	try {
		const result = await rpc('session', 'login', {
			username: $('username').value,
			password: $('password').value
		}, ZERO_SESSION);
		session = result.ubus_rpc_session;
		sessionStorage.setItem('familycontrol-session', session);
		$('login').classList.add('hidden');
		$('app').classList.remove('hidden');
		await load();
	}
	catch (error) {
		showError(error.message, true);
	}
});

$('logout').addEventListener('click', async () => {
	try { await rpc('session', 'destroy', {}); } catch (_) {}
	sessionStorage.removeItem('familycontrol-session');
	session = null;
	showLogin();
});

$('add-person').addEventListener('click', () => {
	$('person-title').textContent = 'Add person';
	$('person-id').value = '';
	$('person-name').value = '';
	$('person-dialog').showModal();
});

document.querySelectorAll('.cancel').forEach(button =>
	button.addEventListener('click', () => button.closest('dialog').close()));

$('person-form').addEventListener('submit', async event => {
	event.preventDefault();
	const id = $('person-id').value;
	try {
		await mutateAndReload('save_person', {
			person: id,
			name: $('person-name').value
		});
		$('person-dialog').close();
	} catch (error) { showError(error.message); }
});

$('device-form').addEventListener('submit', async event => {
	event.preventDefault();
	const choice = $('device-choice').value;
	const mac = (choice === 'manual' ? $('device-mac').value : choice).trim().toUpperCase();
	if (!MAC_PATTERN.test(mac)) {
		showError('Enter a valid MAC address.');
		return;
	}
	const id = $('device-id').value;
	try {
		await mutateAndReload('save_device', {
			device: id,
			name: $('device-name').value,
			mac,
			person: $('device-person').value
		});
		$('device-dialog').close();
	} catch (error) { showError(error.message); }
});

function populateDeviceChoices(currentMac = '') {
	const select = $('device-choice');
	const normalizedCurrent = currentMac.toUpperCase();
	const available = candidates.filter(device =>
		!device.assigned_person || device.mac === normalizedCurrent);

	select.innerHTML = [
		'<option value="">Choose a connected device…</option>',
		...available.map(device => {
			const label = [
				device.hostname || 'Unknown device',
				device.ip,
				device.mac
			].filter(Boolean).join(' · ');
			return `<option value="${escapeHtml(device.mac)}">${escapeHtml(label)}</option>`;
		}),
		'<option value="manual">Enter a MAC address manually…</option>'
	].join('');

	if (normalizedCurrent && !available.some(device => device.mac === normalizedCurrent)) {
		select.insertAdjacentHTML('beforeend',
			`<option value="${escapeHtml(normalizedCurrent)}">${escapeHtml(normalizedCurrent)} · saved device</option>`);
	}

	select.value = normalizedCurrent || '';
	$('manual-mac-fields').classList.add('hidden');
}

$('device-choice').addEventListener('change', () => {
	const selected = candidates.find(device => device.mac === $('device-choice').value);
	const manual = $('device-choice').value === 'manual';
	$('manual-mac-fields').classList.toggle('hidden', !manual);
	$('device-mac').required = manual;

	if (selected && !$('device-name').value)
		$('device-name').value = selected.hostname || selected.ip || '';
});

$('people').addEventListener('click', async event => {
	const button = event.target.closest('button[data-action]');
	if (!button) return;
	const { action, id } = button.dataset;
	showError('');
	try {
		if (action === 'pause') {
			await rpc('familycontrol', 'set_paused', {
				person: id, paused: button.dataset.paused === 'true'
			});
			await load();
		}
		else if (action === 'add-device') {
			$('device-title').textContent = 'Add device';
			$('device-id').value = '';
			$('device-person').value = id;
			$('device-name').value = '';
			$('device-mac').value = '';
			populateDeviceChoices();
			$('device-dialog').showModal();
		}
		else if (action === 'edit-device') {
			const device = config[id];
			$('device-title').textContent = 'Edit device';
			$('device-id').value = id;
			$('device-person').value = device.person;
			$('device-name').value = device.name || '';
			$('device-mac').value = device.mac || '';
			populateDeviceChoices(device.mac || '');
			$('device-dialog').showModal();
		}
		else if (action === 'edit-person') {
			$('person-title').textContent = 'Rename person';
			$('person-id').value = id;
			$('person-name').value = config[id].name || '';
			$('person-dialog').showModal();
		}
		else if (action === 'delete-device' && confirm('Remove this device?'))
			await mutateAndReload('delete_device', { device: id });
		else if (action === 'delete-person' && confirm('Delete this person and their devices?'))
			await mutateAndReload('delete_person', { person: id });
	}
	catch (error) { showError(error.message); }
});

(async () => {
	if (!session) return showLogin();
	try {
		$('app').classList.remove('hidden');
		await load();
	}
	catch (_) {
		sessionStorage.removeItem('familycontrol-session');
		session = null;
		showLogin();
	}
})();
