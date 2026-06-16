// Live-reload server for front hot-reload (source mode).
// Watches the web-apps sources and tells the browser to reload on save.
// Uses POLLING: inotify events do not cross the Windows<->WSL boundary reliably,
// so we detect changes by polling mtimes.
const livereload = require('livereload');

// Polling cost: chokidar in polling mode stat()s every watched file on each tick, and
// web-apps/apps holds ~20k files. So we (a) poll at 1s rather than 500ms — halving the
// stat load on the WSL/9p mount — and (b) exclude heavy trees that are never hand-edited
// during UI iteration (third-party vendor bundles, minified files, source maps, build
// output). "save -> reload" stays ~1-2s. Lower `interval` only if you have spare CPU.
const server = livereload.createServer({
  port: 35729,
  delay: 200,
  // chokidar in polling mode (reliable for files edited from Windows/\\wsl.localhost)
  usePolling: true,
  interval: 1000,
  binaryInterval: 2000,
  exts: ['js', 'template', 'less', 'css', 'json', 'html', 'svg'],
  exclusions: [/node_modules/, /\.git/, /build\/deploy/, /\/vendor\//, /\.min\.js$/, /\.map$/],
});

server.watch('/develop/web-apps/apps');
console.log('[livereload] watching /develop/web-apps/apps (polling 1000ms) on :35729');

// Optional: auto-reload on sdkjs (document engine) changes.
// Works reliably on Linux native. On WSL/Windows the polling cross-boundary
// (\\wsl.localhost\ → ext4) is unreliable — changes may not be detected there,
// so use Ctrl+Shift+R manually in that case.
// After uncommenting, restart the server: make front-prod && make front-dev-live
// NOTE: if your change ADDS or REMOVES SDK files, re-run `make sdkjs-dev` regardless.
// server.watch('/develop/sdkjs');
// console.log('[livereload] also watching /develop/sdkjs');

// Visible log of every detected change (confirms polling works).
if (server.watcher && server.watcher.on) {
  server.watcher.on('change', function (f) { console.log('[livereload] change:', f); });
}
