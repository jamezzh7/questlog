"use strict";
(() => {
  const system = window.matchMedia("(prefers-color-scheme: dark)");
  let preference = "auto";
  function render() {
    const theme = preference === "auto" ? (system.matches ? "dark" : "light") : preference;
    document.documentElement.dataset.appearance = preference;
    document.documentElement.dataset.theme = theme;
    document.documentElement.style.colorScheme = theme;
  }
  function apply(value) {
    preference = ["auto", "light", "dark"].includes(value) ? value : "auto";
    render();
  }
  system.addEventListener("change", render);
  globalThis.QuestlogAppearance = {apply};
  // Native config takes priority over the cache before the first paint.
  apply(window.questlogAppearancePreference ?? localStorage.getItem("questlog.appearance"));
})();
