// plugin-sources.mjs — which plugins the session the runner starts will load,
// said from the two places they come from. Pure functions, no I/O;
// route-agent.mjs calls them to write its startup log.
//
// A session loads plugins from two sources at once:
//   by path     every sub-directory of the plugin directory that carries a
//               plugin manifest, handed to the SDK as `plugins`
//   installed   every id the project's resolved settings enable
//               (`enabledPlugins`, "<name>@<marketplace>": true)
// A name in both runs from the path copy; the installed copy of that name is
// read but does not run. An empty plugin directory therefore does not mean a
// session without plugins, and the log says so.

export function pluginName(id) {
  const s = String(id);
  const at = s.indexOf("@");
  return at < 0 ? s : s.slice(0, at);
}

// pathLoaded: the names (directory basenames) loaded by path.
// enabledPlugins: the `enabledPlugins` map of the resolved settings, or nothing.
export function pluginSources(pathLoaded, enabledPlugins) {
  const path = [...new Set((pathLoaded || []).map(String))].sort();
  const enabled = enabledPlugins && typeof enabledPlugins === "object" ? enabledPlugins : {};
  const installed = Object.keys(enabled).filter((id) => enabled[id] === true).sort();
  const names = new Set(path);
  const overridden = [...new Set(installed.map(pluginName).filter((n) => names.has(n)))].sort();
  return { path, installed, overridden };
}

const list = (items) => (items.length ? items.join(", ") : "none");

export function pluginSourceLines(sources, pluginDir) {
  return [
    `plugins by path (${pluginDir}; ${sources.path.length}): ${list(sources.path)}`,
    `plugins installed (enabledPlugins in the project settings; ${sources.installed.length}): ${list(sources.installed)}`,
    `plugins in both (${sources.overridden.length}; the path copy overrides the installed one): ${list(sources.overridden)}`,
  ];
}
