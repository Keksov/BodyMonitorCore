# BodyMonitorCore

Target location for the extracted body-monitor core product.

Current ownership in this product:

- `cli`
- product-local Pascal vendor bindings under `cli/vendor`
- product-local Pascal helpers and stdio protocol under `cli/common`
- `server`
- body-monitor UI modules from `ui`

Runtime protocol notes:

- Compact runtime JSONL schema: `../MindWaveCore/server/RUNTIME_JSONL_SCHEMA.md`

The legacy `pas/MindReader` tree has been moved into the product-local CLI area and renamed to `BodyMonitor`.

UI composition contract:

- `ui/package.json` declares the source-level public entrypoints used by host products.
- The package root stays minimal and re-exports only `bodyMonitorModule` and `createBodyMonitorPlugin`; deeper access should go through declared subpath exports.
- `ui` exports `bodyMonitorModule` for route, settings-tab, and locale-message contributions.
- `ui` exports `createBodyMonitorPlugin` for runtime wiring; the host must provide both `ws` and `replay` adapters before rendering BodyMonitor pages.
- BodyMonitor owns its module-local navigation namespace, including `nav.monitoring`.
- Host shells such as MindWaveCore own only shell concerns like top-level navigation, archive/log pages, and app bootstrap.
