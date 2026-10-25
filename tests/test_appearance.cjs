const assert = require("node:assert/strict");
const {readFileSync} = require("node:fs");
const path = require("node:path");
const {test} = require("node:test");
const vm = require("node:vm");

function launch({dark = false, saved = null, native} = {}) {
  const system = {matches: dark, addEventListener: (_, handler) => { system.change = handler; }};
  const root = {dataset: {}, style: {}};
  const context = vm.createContext({
    window: {matchMedia: () => system, questlogAppearancePreference: native},
    document: {documentElement: root}, localStorage: {getItem: () => saved}
  });
  vm.runInContext(readFileSync(path.join(__dirname, "../public/appearance.js"), "utf8"), context);
  return {root, system, apply: context.QuestlogAppearance.apply};
}

test("system default follows live system changes", () => {
  const {root, system} = launch();
  assert.equal(root.dataset.appearance, "auto");
  assert.equal(root.dataset.theme, "light");
  system.matches = true; system.change();
  assert.equal(root.dataset.theme, "dark");
  assert.equal(root.style.colorScheme, "dark");
});

test("explicit appearances override the system; switching back resumes following", () => {
  const {root, system, apply} = launch({dark: true});
  apply("light"); system.change();
  assert.equal(root.dataset.theme, "light");
  apply("dark"); system.matches = false; system.change();
  assert.equal(root.dataset.theme, "dark");
  apply("auto");
  assert.equal(root.dataset.theme, "light");
  system.matches = true; system.change();
  assert.equal(root.dataset.theme, "dark");
});

test("native config overrides stale cache before first paint", () => {
  assert.equal(launch({saved: "dark", native: "light"}).root.dataset.theme, "light");
  assert.equal(launch({dark: true, saved: "light", native: "auto"}).root.dataset.theme, "dark");
  assert.equal(launch({saved: "dark"}).root.dataset.theme, "dark");
});

test("unknown saved values safely follow the system", () => {
  assert.equal(launch({dark: true, saved: "invalid"}).root.dataset.theme, "dark");
});
