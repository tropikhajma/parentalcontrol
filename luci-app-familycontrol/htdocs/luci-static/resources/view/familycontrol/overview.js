// SPDX-License-Identifier: GPL-3.0-or-later

'use strict';
'require dom';
'require rpc';
'require ui';
'require view';

const callStatus = rpc.declare({
	object: 'familycontrol',
	method: 'status',
	expect: {}
});

const callSetPaused = rpc.declare({
	object: 'familycontrol',
	method: 'set_paused',
	params: [ 'person', 'paused' ],
	expect: {}
});

function styles() {
	return E('style', {}, `
		.fc-shell { max-width: 52rem; margin: 0 auto; }
		.fc-heading { margin-bottom: 1.25rem; }
		.fc-heading h2 { margin-bottom: .35rem; }
		.fc-grid { display: grid; gap: .85rem; }
		.fc-card {
			display: grid;
			grid-template-columns: minmax(0, 1fr) auto;
			align-items: center;
			gap: 1rem;
			padding: 1.1rem;
			border: 1px solid var(--border-color-medium, #d8d8d8);
			border-radius: .85rem;
			background: var(--background-color-high, #fff);
			box-shadow: 0 1px 3px rgba(0, 0, 0, .06);
		}
		.fc-card h3 { margin: 0 0 .3rem; font-size: 1.15rem; }
		.fc-meta { margin: 0; color: var(--text-color-secondary, #666); }
		.fc-state { font-weight: 600; }
		.fc-state-paused { color: #b42318; }
		.fc-state-online { color: #18794e; }
		.fc-action {
			min-width: 7.5rem;
			min-height: 3rem;
			border-radius: .65rem;
			font-size: 1rem;
			font-weight: 600;
		}
		.fc-empty {
			padding: 2rem 1rem;
			text-align: center;
			border: 1px dashed var(--border-color-medium, #bbb);
			border-radius: .85rem;
		}
		@media (max-width: 480px) {
			.fc-card { grid-template-columns: 1fr; }
			.fc-action { width: 100%; }
		}
	`);
}

function personCard(view, person) {
	const count = person.devices.length;
	const stateClass = person.paused ? 'fc-state-paused' : 'fc-state-online';
	const stateText = person.paused ? _('Paused') : _('Online');

	return E('article', { 'class': 'fc-card' }, [
		E('div', {}, [
			E('h3', {}, person.name),
			E('p', { 'class': 'fc-meta' }, [
				E('span', { 'class': `fc-state ${stateClass}` }, stateText),
				' · ',
				N_(count, '%d device', '%d devices').format(count)
			])
		]),
		E('button', {
			'class': person.paused
				? 'btn cbi-button-positive fc-action'
				: 'btn cbi-button-negative fc-action',
			'disabled': count === 0 ? true : null,
			'click': ui.createHandlerFn(view, () => view.setPaused(person, !person.paused))
		}, person.paused ? _('Resume') : _('Pause'))
	]);
}

return view.extend({
	load: function() {
		return callStatus();
	},

	setPaused: function(person, paused) {
		return callSetPaused(person.id, paused).then(result => {
			if (!result.ok)
				throw new Error(result.message || _('Unable to update access'));

			ui.addNotification(null, E('p', {},
				paused
					? _('%s is now paused.').format(person.name)
					: _('%s is back online.').format(person.name)
			));

			return this.load().then(data => {
				dom.content(document.querySelector('.fc-content'), this.people(data));
			});
		}).catch(error => {
			ui.addNotification(_('Access change failed'), E('p', {}, error.message), 'error');
		});
	},

	people: function(data) {
		if (!data.ok)
			return E('div', { 'class': 'alert-message error' },
				data.message || _('Unable to load family controls.'));

		if (!data.people.length)
			return E('div', { 'class': 'fc-empty' }, [
				E('h3', {}, _('No people yet')),
				E('p', {}, _('Add a person and assign their devices in the Family Control app.')),
				E('a', {
					'class': 'btn cbi-button-action',
					'href': '/family/'
				}, _('Add people'))
			]);

		return E('div', { 'class': 'fc-grid' },
			data.people.map(person => personCard(this, person)));
	},

	render: function(data) {
		return E('div', { 'class': 'fc-shell' }, [
			styles(),
			E('div', { 'class': 'fc-heading' }, [
				E('h2', {}, _('Family Control')),
				E('p', {}, _('Pause or resume internet access for all of a person’s devices.'))
			]),
			E('div', { 'class': 'fc-content' }, this.people(data))
		]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
