# OpenTelemetry metrics

Family Control can send a small aggregate metrics batch to Grafana Cloud using
OTLP/HTTP JSON. Telemetry is disabled by default and does not affect access
control when Grafana or the internet is unavailable.

The implementation deliberately avoids Grafana Alloy or a full OpenTelemetry
Collector on the router. A one-minute batch from one constrained device is the
low-volume case for which Grafana Cloud supports OTLP JSON. A collector remains
the preferred option if an always-on LAN server is introduced later.

## Privacy boundary

The exporter never sends:

- person names or identifiers;
- MAC addresses;
- IP addresses or DHCP hostnames;
- requested domains, URLs, DNS queries, or traffic destinations;
- credentials or ubus sessions; or
- UCI configuration values.

The only metric attributes are bounded values such as `pause`/`resume`,
`ok`/`error`, the `/overlay` mountpoint, and OpenTelemetry service metadata.
Do not add person or device identifiers as metric attributes: each distinct
attribute set creates another time series and exports household metadata.

## Metric catalog

| Metric | Type | Meaning |
| --- | --- | --- |
| `familycontrol.people` | Gauge | Configured people. |
| `familycontrol.devices` | Gauge | Configured devices. |
| `familycontrol.devices.connected` | Gauge | Unique valid MACs in current DHCP leases. No MAC is exported. |
| `familycontrol.people.paused` | Gauge | People whose desired state is paused. |
| `familycontrol.enforcement.expected_rules` | Gauge | Firewall rules required by current paused state. |
| `familycontrol.enforcement.actual_rules` | Gauge | Existing `familycontrol_*` firewall rules. |
| `familycontrol.enforcement.drift` | Gauge | `1` when expected rule names/MAC sets differ from firewall UCI. |
| `familycontrol.action.count` | Cumulative counter | Pause/resume attempts labelled by action and result. |
| `familycontrol.action.duration` | Cumulative histogram | End-to-end pause/resume duration, including firewall reload. |
| `familycontrol.firewall.reload.failures` | Cumulative counter | Failed firewall reload attempts. |
| `familycontrol.telemetry.export.failures` | Cumulative counter | Failed Grafana exports since boot. |
| `familycontrol.telemetry.last_success.age` | Gauge | Seconds since the last successful export. |
| `system.uptime` | Gauge | Router uptime in seconds. |
| `system.memory.utilization` | Gauge | Used fraction of router memory. |
| `system.filesystem.utilization` | Gauge | Used fraction of `/overlay`. |
| `system.cpu.load_average.1m` | Gauge | One-minute router load average. |

The `system.*` names follow OpenTelemetry system metric conventions where an
applicable convention exists. Grafana converts periods in OTLP metric names to
underscores when storing them in its Prometheus-compatible metrics backend.

Action counters live in `/tmp/familycontrol-telemetry.json`. They reset after a
router reboot, which is valid for cumulative OpenTelemetry metrics because the
reported start time also changes to the current boot time. No telemetry counter
causes flash writes.

## Router components

All project-authored router files are committed in the package:

```text
/etc/config/familycontrol_telemetry
/etc/init.d/familycontrol-telemetry
/usr/libexec/familycontrol-otel-payload
/usr/sbin/familycontrol-otel-export
/usr/sbin/familycontrol-otel-loop
```

The procd service runs only when telemetry is enabled. It exports immediately,
then waits for the configured interval. The minimum accepted interval is 30
seconds and the default is 60 seconds.

Exports have a ten-second timeout and no retry queue. A failed batch is dropped,
the in-memory failure counter is incremented, and access-control operations
continue normally.

## Grafana Cloud credentials

In Grafana Cloud, open **OpenTelemetry → Configure** and create a narrowly
scoped access-policy token with only `metrics:write`. Record:

```text
OTLP endpoint
OTLP instance ID / username
Access-policy token
```

The token is write-only telemetry authority. It should not grant Grafana
administration, dashboard editing, logs, or traces.

Configure the router over SSH. Replace the placeholders locally; never paste
the resulting commands into an issue, log, or committed script:

```sh
uci set familycontrol_telemetry.main.endpoint='https://YOUR-OTLP-ENDPOINT/otlp'
uci set familycontrol_telemetry.main.instance_id='YOUR-INSTANCE-ID'
uci set familycontrol_telemetry.main.api_token='YOUR-METRICS-WRITE-TOKEN'
uci set familycontrol_telemetry.main.interval='60'
uci set familycontrol_telemetry.main.enabled='1'
uci commit familycontrol_telemetry
chmod 0600 /etc/config/familycontrol_telemetry
/etc/init.d/familycontrol-telemetry restart
```

The endpoint may include `/otlp`; the exporter appends `/v1/metrics`. A complete
endpoint ending in `/v1/metrics` is also accepted.

The access token is read into a mode `0600` temporary wget configuration so it
does not appear in the process command line. Temporary payload and credential
files are removed after every attempt.

## Dashboard

Import [grafana/familycontrol-dashboard.json](../grafana/familycontrol-dashboard.json)
through **Dashboards → New → Import** and select the Grafana Cloud Prometheus
data source.

Grafana's OTLP-to-Prometheus translation can add unit or counter suffixes
depending on the stack translation strategy. If a panel is empty, use Explore
to find the translated name and adjust the query. The common translation
replaces `.` with `_`.

Recommended alerts:

- `familycontrol_enforcement_drift == 1` for two export intervals;
- telemetry last-success age greater than five minutes;
- any increase in firewall reload failures;
- memory utilization above 90% for ten minutes;
- overlay utilization above 85%; and
- no `system_uptime` series for five minutes.

## Safe diagnostics

These commands do not print the token:

```sh
/etc/init.d/familycontrol-telemetry enabled
/etc/init.d/familycontrol-telemetry running
logread -e familycontrol-telemetry
/usr/libexec/familycontrol-otel-payload | jsonfilter \
	-e '@.resourceMetrics[0].scopeMetrics[0].metrics[*].name'
```

Do not run `uci show familycontrol_telemetry`, include the configuration in a
support archive, or dump the procd service environment.

Disable export without deleting the configuration:

```sh
uci set familycontrol_telemetry.main.enabled='0'
uci commit familycontrol_telemetry
/etc/init.d/familycontrol-telemetry stop
```

Rotate the Grafana token immediately if it appears in output or source control.

## References

- [Grafana Cloud OTLP format considerations](https://grafana.com/docs/grafana-cloud/send-data/otlp/otlp-format-considerations/)
- [Grafana Cloud OTLP authentication example](https://grafana.com/docs/grafana-cloud/send-data/alloy/reference/components/otelcol/otelcol.exporter.otlphttp/)
- [OpenTelemetry Protocol specification](https://opentelemetry.io/docs/specs/otlp/)
- [OpenTelemetry system metric conventions](https://opentelemetry.io/docs/specs/semconv/system/system-metrics/)
