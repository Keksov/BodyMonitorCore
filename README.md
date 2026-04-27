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
