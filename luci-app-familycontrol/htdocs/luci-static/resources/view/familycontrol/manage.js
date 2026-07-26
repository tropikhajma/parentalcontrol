'use strict';
'require form';
'require uci';
'require view';

return view.extend({
	load: function() {
		return uci.load('familycontrol');
	},

	render: function() {
		let map = new form.Map(
			'familycontrol',
			_('People & Devices'),
			_('Create people first, then assign each device to one person.')
		);

		let people = map.section(form.TypedSection, 'person', _('People'));
		people.anonymous = true;
		people.addremove = true;
		people.sortable = true;

		let personName = people.option(form.Value, 'name', _('Name'));
		personName.rmempty = false;

		let devices = map.section(form.TypedSection, 'device', _('Devices'));
		devices.anonymous = true;
		devices.addremove = true;
		devices.sortable = true;

		let deviceName = devices.option(form.Value, 'name', _('Device name'));
		deviceName.rmempty = false;

		let mac = devices.option(form.Value, 'mac', _('MAC address'));
		mac.rmempty = false;
		mac.datatype = 'macaddr';
		mac.placeholder = '00:11:22:33:44:55';

		let owner = devices.option(form.ListValue, 'person', _('Person'));
		owner.rmempty = false;

		uci.sections('familycontrol', 'person', person => {
			owner.value(person['.name'], person.name || person['.name']);
		});

		return map.render();
	}
});

