// Tests for plugin-sources.mjs. Run with:
//   node --test plugins/agentic-core/shared/runner/plugin-sources.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";
import { pluginName, pluginSourceLines, pluginSources } from "./plugin-sources.mjs";

const ENABLED = {
  "core@local-marketplace": true,
  "pack-a@local-marketplace": true,
  "pack-b@local-marketplace": false,
};

test("an installed id is reduced to its plugin name", () => {
  assert.equal(pluginName("pack-a@local-marketplace"), "pack-a");
  assert.equal(pluginName("bare-name"), "bare-name");
});

test("an empty plugin directory still reports what the project settings bring", () => {
  const s = pluginSources([], ENABLED);
  assert.deepEqual(s.path, []);
  assert.deepEqual(s.installed, ["core@local-marketplace", "pack-a@local-marketplace"]);
  assert.deepEqual(s.overridden, []);
});

test("a disabled or absent enabledPlugins entry is not an installed plugin", () => {
  assert.deepEqual(pluginSources([], ENABLED).installed.filter((id) => id.startsWith("pack-b")), []);
  assert.deepEqual(pluginSources(["core"], undefined).installed, []);
  assert.deepEqual(pluginSources(["core"], null).installed, []);
  assert.deepEqual(pluginSources(["core"], "not an object").installed, []);
});

test("a name loaded by path and installed is reported as overridden, by name", () => {
  const s = pluginSources(["pack-a", "core", "pack-c"], ENABLED);
  assert.deepEqual(s.path, ["core", "pack-a", "pack-c"]);
  assert.deepEqual(s.overridden, ["core", "pack-a"]);
});

test("a path-loaded name with no installed counterpart is in the path set only", () => {
  const s = pluginSources(["pack-c"], ENABLED);
  assert.deepEqual(s.path, ["pack-c"]);
  assert.deepEqual(s.overridden, []);
});

test("the log lines name both sources and the override, with none where a set is empty", () => {
  const lines = pluginSourceLines(pluginSources(["pack-a", "pack-c"], ENABLED), "/w/plugins");
  assert.deepEqual(lines, [
    "plugins by path (/w/plugins; 2): pack-a, pack-c",
    "plugins installed (enabledPlugins in the project settings; 2): core@local-marketplace, pack-a@local-marketplace",
    "plugins in both (1; the path copy overrides the installed one): pack-a",
  ]);
  const empty = pluginSourceLines(pluginSources([], {}), "/w/empty");
  assert.deepEqual(empty, [
    "plugins by path (/w/empty; 0): none",
    "plugins installed (enabledPlugins in the project settings; 0): none",
    "plugins in both (0; the path copy overrides the installed one): none",
  ]);
});

test("the decision is pure: its inputs are not changed", () => {
  const names = ["pack-c", "pack-a"];
  const enabled = { ...ENABLED };
  pluginSources(names, enabled);
  assert.deepEqual(names, ["pack-c", "pack-a"]);
  assert.deepEqual(enabled, ENABLED);
});
