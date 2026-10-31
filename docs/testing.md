# Testing and certification boundary

Deterministic development suites target Redot `26.3.rc.1.official.704b10a8e`. Source-test results do not certify editor or exported-game compatibility.

| Suite | Coverage |
| --- | --- |
| `run_ms001.gd` | Full/minimal/malformed/offline payloads; secret stripping; baseline; overlap/reorder; restart; counters/resets; multiple streams; 50-item saturation; hash capacity/TTL |
| `run_core_suite.gd` | Contract/capabilities; URL policy; RRCH/1; redaction; command routing; session isolation; descriptor/vault lifecycle with mocks |
| `run_http_transport_suite.gd` | Single flight; status metadata; no redirects; cancellation; response limit; host/TLS validation |
| `run_integration_suite.gd` | Loopback client baseline/update/5xx/malformed/recovery/offline sequence and last-good-state behavior |
| `run_project_check.gd` | Script/scene resource loading |
| `run_up03.gd` | Last-observed TTL, bounded inactive collections, offline/live transitions, persistence write counts, JSON restart types, silent cancellation |
| `addons/redot-rumbler/tests/run_helper_export_paths.gd` | Helper source/runtime paths, export feature tags, and required engine APIs |
| `run_credential_helper_smoke.gd` | Real Windows Credential Manager ping/store/read/replace/delete |

The Linux binary is compiled with warnings as errors. Its `RRCH/1` ping and wrong-protocol paths are exercised in Ubuntu; without a graphical keyring it correctly returns `UNAVAILABLE`.

## Still required before `1.0.0`

- a controlled private Rumble API URL and live stream;
- current live/offline payload, ordering, cadence, and URL-reset behavior;
- low/high-volume chat with 50-item pressure;
- rant/follow/subscription/gift observations where feasible;
- Linux graphical Secret Service store/read/replace/delete/restart;
- Windows and Linux x86-64 exported-game runs and archive inspection.

Fixtures prove deterministic behavior but cannot certify source-invisible events or a mutable live service.
