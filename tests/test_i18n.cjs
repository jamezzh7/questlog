const assert = require("node:assert/strict");
const {readFileSync} = require("node:fs");
const path = require("node:path");
const {test} = require("node:test");
const vm = require("node:vm");
const root = path.join(__dirname, "..");
const context = vm.createContext({});
vm.runInContext(readFileSync(path.join(root, "public/i18n.js"), "utf8"), context);
const i18n = context.QuestlogI18n;

test("explicit language wins and system language has a predictable fallback", () => {
  for (const locale of ["zh-CN", "zh-Hant-TW", "zh", "ZH-hans"]) assert.equal(i18n.resolve("auto", locale), "zh");
  for (const locale of ["fr-CA", "fr-FR", "fr", "FR_ca"]) assert.equal(i18n.resolve("auto", locale), "fr");
  for (const locale of ["en-CA", "ja-JP", ""]) assert.equal(i18n.resolve("auto", locale), "en");
  assert.equal(i18n.resolve("en", "zh-CN"), "en");
  assert.equal(i18n.resolve("zh", "en-US"), "zh");
  assert.equal(i18n.resolve("fr", "zh-CN"), "fr");
  assert.equal(i18n.resolve("en", "fr-CA"), "en");
});

test("all declared UI keys have three translations with matching variables", () => {
  const html = readFileSync(path.join(root, "public/index.html"), "utf8");
  const app = readFileSync(path.join(root, "public/app.js"), "utf8");
  const usedKeys = [...html.matchAll(/data-i18n(?:-label|-title|-placeholder)?="(\w+)"/g), ...app.matchAll(/\bt\("(\w+)"/g)].map(match => match[1]);
  for (const key of usedKeys) assert.ok(i18n.strings[key], `Missing key: ${key}`);
  for (const [key, pair] of Object.entries(i18n.strings)) {
    assert.equal(pair.length, 3, key);
    assert.ok(pair.every(value => typeof value === "string" && value.length), key);
    const placeholders = value => [...value.matchAll(/\{(\w+)\}/g)].map(match => match[1]).sort();
    assert.deepEqual(placeholders(pair[0]), placeholders(pair[1]), `${key}: variable mismatch`);
    assert.deepEqual(placeholders(pair[0]), placeholders(pair[2]), `${key}: French variable mismatch`);
    const values = Object.fromEntries(placeholders(pair[0]).map(name => [name, 7]));
    for (const locale of ["zh", "en", "fr"]) assert.doesNotMatch(i18n.translate(key, values, locale), /\{\w+\}/, key);
  }
});

test("French dates and numeric estimates use the requested locale", () => {
  assert.equal(i18n.locale("fr", "fr-CA"), "fr-CA");
  assert.equal(i18n.locale("fr", "FR_ca"), "FR-ca");
  assert.equal(i18n.locale("fr", "en-CA"), "fr-FR");
  assert.equal(i18n.number(1.5, "fr"), "1,5");
  assert.equal(i18n.translate("etaDays", {low: 1.5, high: 3}, "fr"), "≈ 1,5–3 jours ouvrés");
  assert.equal(i18n.translate("progressValue", {done: 7, total: 15, percent: 47}, "fr"), "7 sur 15 terminées (47 %)");
  const date = new Date("2026-10-20T12:00:00Z").toLocaleDateString(i18n.locale("fr"), {timeZone: "UTC"});
  assert.equal(date, "20/10/2026");
});

test("all known app errors have French translations and unknown source text stays intact", () => {
  for (const [source, translations] of Object.entries(i18n.errors)) {
    assert.equal(translations.length, 2, source);
    assert.ok(translations.every(value => typeof value === "string" && value.length), source);
    assert.equal(i18n.error(source, "fr"), translations[1]);
    assert.doesNotMatch(i18n.error(source, "fr"), /[\u3400-\u9fff]/);
    assert.equal(i18n.error(source, "zh"), source);
  }
  assert.equal(i18n.error("项目不存在", "fr"), "Projet introuvable.");
  assert.equal(i18n.error("Original project diagnostic", "fr"), "Original project diagnostic");
  assert.match(readFileSync(path.join(root, "public/index.html"), "utf8"), /<option value="fr">Français<\/option>/);
});

test("progress and estimate values survive localization", () => {
  assert.equal(i18n.translate("progressValue", {done: 7, total: 15, percent: 47}, "en"), "7 of 15 complete (47%)");
  assert.equal(i18n.translate("etaDays", {low: 1.5, high: 3}, "en"), "~1.5–3 workdays");
  assert.equal(i18n.translate("remaining", {count: 0}, "zh"), "剩余主验收任务：0 项");
  assert.equal(i18n.error("项目不存在", "en"), "Project not found.");
  assert.equal(i18n.error("项目不存在", "zh"), "项目不存在");
});
