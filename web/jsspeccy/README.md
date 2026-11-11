# JSSpeccy 3 for ZX-PLC

[JSSpeccy 3](https://github.com/gasman/jsspeccy3) by Matt Westcott (GPL-3.0, see `COPYING`), version 3.2
(upstream commit `cf886f39c2a72752a0bd49568fef398b141c11f2`), built with the changes in `zxplc.patch`:

* **Kempston mouse** (option `kempstonMouse: true`):
  * ports 0xFADF buttons (active low: bit 0 right, bit 1 left), 0xFBDF X, 0xFFDF Y;
  * a click on the screen captures the mouse (pointer lock), Esc releases it.
* **Palette:** the standard colours (0xD7 / 0xFF) instead of JSSpeccy's own.

## Rebuilding

```
git clone https://github.com/gasman/jsspeccy3.git && cd jsspeccy3
git checkout cf886f39c2a72752a0bd49568fef398b141c11f2
git apply /path/to/zxplc.patch
npm ci
npm run build:core && npm run build:wasm:release
sed 's/^export default \[/module.exports = [/' webpack.config.js > webpack.config.cjs
NODE_OPTIONS=--openssl-legacy-provider npx webpack --config webpack.config.cjs
cp dist/jsspeccy/jsspeccy.js dist/jsspeccy/jsspeccy-worker.js dist/jsspeccy/jsspeccy-core.wasm /path/to/web/jsspeccy/
```

The `.cjs` config and the OpenSSL option are only needed with newer Node versions (the project pins
Node 16 in `.nvmrc`).
