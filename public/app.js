"use strict";
const $ = (selector) => document.querySelector(selector);
const nativeAPI = window.webkit?.messageHandlers?.questlogAPI;
const native = Boolean(window.webkit?.messageHandlers?.questlog);
const I18N = globalThis.QuestlogI18n;
let languagePreference = localStorage.getItem("questlog.language") || "auto";
let language = I18N.resolve(languagePreference, navigator.language);
const t = (key, values) => I18N.translate(key, values, language);
const displayLocale = () => I18N.locale(language, navigator.language);
const reducedMotion = () => window.matchMedia("(prefers-reduced-motion: reduce)").matches;
let projectId = new URLSearchParams(location.search).get("project") || localStorage.getItem("questlog.project") || null;
let data = null;
let projects = [];
let filter = "all";
let loading = false;
let full = Boolean(nativeAPI) || new URLSearchParams(location.search).get("view") === "full";
let lastSignature = "";
let toastTimeout;
let connectionProvider = "codex";
let discoveryGeneration = 0;
let catalog = null;
let percentFrame = 0;
let displayedPercent = 0;
let percentProject = "";
let removalTarget = null;
let stageId = null;
let scopeChosen = false;
let suspendedScope = null;
const taskNotesOpen = new Set();
const workGroups = () => data?.groups ?? data?.milestones ?? [];
const modular = () => data?.groupKind === "module";
const countIsOne = (count) => new Intl.PluralRules(displayLocale()).select(count) === "one";
const workTaskCount = (count) => t(countIsOne(count) ? "workTaskCountOne" : "workTaskCount", {count});
const moduleCount = (count) => t(countIsOne(count) ? "moduleCountOne" : "moduleCount", {count});
let sourceProject = null;
let documentGeneration = 0;
let sourceGeneration = 0;
const noteOpen = new Map();
const dialogReturn = new WeakMap();
let resourceView = false;
const viewScroll = {tasks: 0, resources: 0};

function applyLanguage() {
  language = I18N.resolve(languagePreference, navigator.language);
  document.documentElement.lang = language === "zh" ? "zh-CN" : language;
  document.title = t("appTitle");
  $("#language-select").value = languagePreference;
  for (const [attribute, target] of [["data-i18n", null], ["data-i18n-label", "aria-label"], ["data-i18n-title", "title"], ["data-i18n-placeholder", "placeholder"]]) {
    document.querySelectorAll(`[${attribute}]`).forEach((element) => {
      const value = t(element.getAttribute(attribute));
      if (target) element.setAttribute(target, value); else element.textContent = value;
    });
  }
  $("#toggle-view").title = t(full ? "compact" : "expand");
  $("#toggle-view").setAttribute("aria-label", $("#toggle-view").title);
  renderSyncState();
  if (projects.length) renderProjects();
  if (data) { render(); updateReadTime(); }
  if (catalog) renderCatalog(catalog);
  document.querySelectorAll(".estimate-row").forEach((row) => row.querySelectorAll("input").forEach((input, index) => input.setAttribute("aria-label", t(index ? "maxHoursLabel" : "minHoursLabel", {id: row.dataset.task}))));
}
function showDialog(dialog, trigger = document.activeElement) {
  dialogReturn.set(dialog, trigger);
  $("#scope-picker").open = false;
  dialog.showModal();
  if (!reducedMotion()) dialog.animate([{opacity: 0, transform: "translateY(3px)"}, {opacity: 1, transform: "translateY(0)"}], {duration: 140, easing: "ease-out"});
}
function closeDialog(dialog) {
  if (!dialog.open) return Promise.resolve();
  if (reducedMotion()) { dialog.close(); return Promise.resolve(); }
  return dialog.animate([{opacity: 1, transform: "translateY(0) scale(1)"}, {opacity: 0, transform: "translateY(3px)"}], {duration: 120, easing: "ease-out"}).finished.then(() => dialog.close(), () => dialog.close());
}
function animatePage() {
  if (!reducedMotion()) $("#content").animate([{opacity: 0, transform: "translateY(2px)"}, {opacity: 1, transform: "translateY(0)"}], {duration: 150, easing: "cubic-bezier(.2,.7,.2,1)"});
}
function renderPercent(overall) {
  cancelAnimationFrame(percentFrame);
  if (!overall.total) { text("#percent", "—"); percentProject = data.id; displayedPercent = 0; return; }
  const startValue = percentProject === data.id ? displayedPercent : overall.percent;
  const target = overall.percent;
  percentProject = data.id;
  const number = document.createTextNode(String(Math.round(startValue)));
  $("#percent").replaceChildren(number, node("span", "", language === "fr" ? " %" : "%"));
  if (reducedMotion() || startValue === target) { number.textContent = String(target); displayedPercent = target; return; }
  const started = performance.now();
  function tick(now) {
    const progress = Math.min(1, (now - started) / 180);
    displayedPercent = startValue + (target - startValue) * (1 - (1 - progress) ** 3);
    number.textContent = String(Math.round(displayedPercent));
    if (progress < 1) percentFrame = requestAnimationFrame(tick);
  }
  percentFrame = requestAnimationFrame(tick);
}
function etaText(eta) {
  if (language === "zh") return {label: eta.label, detail: eta.detail};
  if (data.state === "no-plan") return {label: t("etaNoPlan"), detail: t("etaNoPlanDetail")};
  if (!data.overall.total) return {label: t("noMainChecklist"), detail: t("moduleMethod")};
  if (eta.complete) return {label: t("etaDone"), detail: t("etaDoneDetail")};
  if (!eta.available) return {label: t("etaUnknown"), detail: t("etaMissing", {count: eta.missing?.length || 0})};
  return {label: t("etaDays", {low: eta.days[0], high: eta.days[1]}), detail: t("etaDetail", {low: eta.hours[0], high: eta.hours[1], daily: data.hoursPerDay})};
}
function updateReadTime() {
  if (data) text("#last-read", t("lastRead", {time: new Date(data.checkedAt).toLocaleTimeString(displayLocale())}));
}

function node(tag, className, text) {
  const element = document.createElement(tag);
  if (className) element.className = className;
  if (text !== undefined) element.textContent = text;
  return element;
}
function text(selector, value) { $(selector).textContent = value; }
function nativeAction(action) { window.webkit?.messageHandlers?.questlog?.postMessage(action); }
// Measure the actual layout so native drag targets never cover translated controls.
if (native) {
  let dragFrame = 0;
  let lastDragRegions = "";
  const rectangles = (selector) => [...document.querySelectorAll(selector)].map((element) => {
    const rect = element.getBoundingClientRect();
    return [rect.x, rect.y, rect.width, rect.height];
  }).filter((rect) => rect[2] > 0 && rect[3] > 0);
  const updateDragRegions = () => {
    cancelAnimationFrame(dragFrame);
    dragFrame = requestAnimationFrame(() => {
      const blocked = !full || Boolean(document.querySelector("dialog[open]"));
      const message = {action: "window-drag-regions", regions: blocked ? [] : rectangles("[data-window-drag]"), excluded: blocked ? [] : rectangles("[data-window-no-drag]")};
      const signature = JSON.stringify(message);
      if (signature !== lastDragRegions) { lastDragRegions = signature; nativeAction(message); }
    });
  };
  const resizeObserver = new ResizeObserver(updateDragRegions);
  document.querySelectorAll("[data-window-drag], [data-window-no-drag]").forEach((element) => resizeObserver.observe(element));
  const modalObserver = new MutationObserver(updateDragRegions);
  document.querySelectorAll("dialog").forEach((dialog) => modalObserver.observe(dialog, {attributes: true, attributeFilter: ["open"]}));
  window.addEventListener("resize", updateDragRegions);
  updateDragRegions();
}
function setView(expanded) {
  full = expanded;
  document.body.classList.toggle("compact", !full);
  $("#toggle-view").title = t(full ? "compact" : "expand");
  $("#toggle-view").setAttribute("aria-label", $("#toggle-view").title);
  if (native) nativeAction(full ? "expand" : "compact");
  const url = new URL(location.href);
  url.searchParams.set("view", full ? "full" : "mini");
  if (!nativeAPI) history.replaceState(null, "", url);
}
document.body.classList.toggle("native", native);
setView(full);
$("#toggle-view").addEventListener("click", () => setView(!full));
$("#mini-expand").addEventListener("click", () => setView(true));
$("#quit").addEventListener("click", () => nativeAction("quit"));
$("#privacy").addEventListener("click", async (event) => {
  await closeDialog($("#settings-dialog")); showDialog($("#privacy-dialog"), $("#settings"));
});
$("#privacy-online").addEventListener("click", () => api("/api/privacy/open", {}).catch((failure) => error(failure.message)));
$("#reset-permissions").addEventListener("click", async () => {
  try { const result = await api("/api/permissions/reset", {}); if (!result.cancelled) { await closeDialog($("#settings-dialog")); lastSignature = ""; await refresh(); } }
  catch (failure) { error(failure.message); }
});
if (nativeAPI) { $("#privacy").hidden = false; $("#reset-permissions").hidden = false; }
$("#settings").addEventListener("click", (event) => showDialog($("#settings-dialog"), event.currentTarget));
function setResourceView(show, focus = false) {
  viewScroll[resourceView ? "resources" : "tasks"] = $("main").scrollTop;
  resourceView = show;
  $("#resources-view").hidden = !show;
  $("#tasks-view").hidden = show;
  $("#content").classList.toggle("resources-open", show);
  $("#show-resources").setAttribute("aria-pressed", String(show));
  $("#scope-picker").open = false;
  $("main").scrollTop = viewScroll[show ? "resources" : "tasks"];
  if (focus) $(show ? "#back-tasks" : "#scope-picker summary").focus({preventScroll: true});
}
$("#show-resources").addEventListener("click", () => setResourceView(!resourceView));
$("#back-tasks").addEventListener("click", () => setResourceView(false, true));
document.addEventListener("click", (event) => {
  if (!$("#scope-picker").contains(event.target)) $("#scope-picker").open = false;
});
document.addEventListener("keydown", (event) => {
  if (event.key === "Escape" && $("#scope-picker").open) {
    event.preventDefault(); $("#scope-picker").open = false; $("#scope-picker summary").focus();
  }
});
function fitScopeMenu() {
  const picker = $("#scope-picker");
  if (!picker.open) return;
  const rect = picker.querySelector("summary").getBoundingClientRect();
  const below = innerHeight - rect.bottom - 16;
  const above = rect.top - 16;
  const upward = below < 180 && above > below;
  picker.classList.toggle("opens-up", upward);
  $("#milestones").style.maxHeight = `${Math.max(60, Math.min(350, (upward ? above : below) - 80))}px`;
}
$("#scope-picker").addEventListener("toggle", fitScopeMenu);
window.addEventListener("resize", fitScopeMenu);
document.querySelectorAll("dialog").forEach((dialog) => dialog.addEventListener("close", () => {
  const trigger = dialogReturn.get(dialog);
  if (trigger?.isConnected && !trigger.closest("[hidden]")) trigger.focus({preventScroll: true});
  else $(resourceView ? "#back-tasks" : "#scope-picker summary").focus({preventScroll: true});
}));

async function api(path, body) {
  if (nativeAPI) {
    const response = await nativeAPI.postMessage({path, ...(body === undefined ? {} : {body})});
    if (response.status < 200 || response.status >= 300) throw Object.assign(new Error(I18N.error(response.body?.error || t("requestFailed", {status: response.status}), language)), {status: response.status});
    return response.body;
  }
  const response = await fetch(path, body ? {method: "POST", headers: {"Content-Type": "application/json"}, body: JSON.stringify(body)} : {});
  const result = await response.json();
  if (!response.ok) throw new Error(I18N.error(result.error || t("requestFailed", {status: response.status}), language));
  return result;
}
function toast(message) {
  clearTimeout(toastTimeout);
  text("#toast", message); $("#toast").hidden = false;
  toastTimeout = setTimeout(() => { $("#toast").hidden = true; }, 2500);
}
function error(message) {
  text("#error", message); $("#error").hidden = false;
  renderSyncState();
}
function renderSyncState() {
  const failed = !$("#error").hidden;
  const needsAccess = nativeAPI && !$("#authorize-project").hidden;
  text("#sync-state", t(needsAccess ? "accessRequired" : failed ? "syncFailed" : "syncing"));
  $("#sync-state").classList.toggle("sync-error", failed);
}
function shortTitle(title) { return title.trim(); }
async function selectProject(identity) {
  projectId = identity || null;
  if (projectId) localStorage.setItem("questlog.project", projectId); else localStorage.removeItem("questlog.project");
  const url = new URL(location.href);
  if (projectId) url.searchParams.set("project", projectId); else url.searchParams.delete("project");
  if (!nativeAPI) history.replaceState(null, "", url);
  lastSignature = ""; data = null;
  stageId = null; scopeChosen = false; suspendedScope = null; taskNotesOpen.clear(); filter = "all"; $("#task-search").value = ""; noteOpen.clear();
  setResourceView(false); viewScroll.tasks = 0; viewScroll.resources = 0;
  cancelAnimationFrame(percentFrame);
  $("#content").hidden = true; $("#error").hidden = true;
  $("#repair-source").hidden = true;
  $("#loading").hidden = !projectId; $("#empty-state").hidden = Boolean(projectId);
  $("main").scrollTo({top: 0});
  renderProjects();
  if (projectId) await refresh();
}
function renderProjects() {
  const focusedEntry = document.activeElement?.closest(".project-entry");
  const focusedProject = focusedEntry?.dataset.project;
  const focusedRemove = document.activeElement?.classList.contains("remove-project");
  if (native) nativeAction(`project:${projectId || ""}`);
  $("#projects").replaceChildren(...projects.map((project) => {
    const entry = node("div", "project-entry"); entry.dataset.project = project.id;
    const button = node("button", `project-button${project.id === projectId ? " active" : ""}`);
    button.title = project.name;
    const icon = node("span", "symbol icon-project"); icon.setAttribute("aria-hidden", "true");
    button.append(icon, node("span", "project-name", project.name));
    if (project.id === projectId) button.setAttribute("aria-current", "page");
    button.addEventListener("click", () => {
      if (project.id === projectId) return;
      selectProject(project.id);
    });
    const remove = node("button", "remove-project");
    const close = node("span", "symbol icon-close"); close.setAttribute("aria-hidden", "true"); remove.append(close);
    remove.type = "button"; remove.title = t("removeNamed", {name: project.name});
    remove.setAttribute("aria-label", remove.title); remove.setAttribute("aria-haspopup", "dialog"); remove.setAttribute("aria-controls", "remove-dialog");
    remove.addEventListener("click", () => {
      if ($("#confirm-remove").disabled) return;
      removalTarget = project;
      text("#remove-name", t("removeName", {name: project.name}));
      $("#remove-error").hidden = true;
      showDialog($("#remove-dialog"), remove);
    });
    entry.append(button, remove);
    return entry;
  }));
  if (focusedProject) {
    const entry = [...document.querySelectorAll(".project-entry")].find((item) => item.dataset.project === focusedProject);
    entry?.querySelector(focusedRemove ? ".remove-project" : ".project-button")?.focus({preventScroll: true});
  }
}
function selectStage(identity) {
  stageId = identity;
  scopeChosen = true;
  suspendedScope = null;
  $("#task-search").value = "";
  renderTasks(); renderMilestones();
  $("#scope-picker").open = false;
  $("#scope-picker summary").focus({preventScroll: true});
}
function renderTasks() {
  const groups = workGroups();
  if (modular() && suspendedScope && (suspendedScope === "work" || groups.some((item) => item.id === suspendedScope))) {
    stageId = suspendedScope; suspendedScope = null;
  }
  const stage = groups.find((item) => item.id === stageId);
  if (stageId && !stage && (!modular() || stageId !== "work") && data.warnings?.length) suspendedScope = stageId;
  if (modular() && (!data.overall.total && stageId === null || stageId && stageId !== "work" && !stage)) stageId = "work";
  const allWork = modular() && stageId === "work";
  if (!stage && !allWork) stageId = null;
  const workScope = modular() && Boolean(stage || allWork);
  const scope = allWork ? groups.flatMap((item) => item.tasks) : stage ? stage.tasks : data.primary;
  const query = $("#task-search").value.trim().toLocaleLowerCase();
  const items = scope.filter((task) => (filter === "all" || (filter === "done" ? task.done === true : task.done !== true)) && `${task.id} ${task.title} ${task.groupTitle || ""} ${task.statusText || ""} ${task.dependency || ""}`.toLocaleLowerCase().includes(query));
  text("#task-heading", stage ? shortTitle(stage.title) : allWork ? t("moduleTasks") : t("mainChecklist"));
  text("#task-total", workScope ? workTaskCount(scope.length) : scope.length ? `${scope.filter((task) => task.done).length}/${scope.length}` : "");
  text("#task-scope", t(data.state === "no-plan" ? "noPlanScope" : workScope ? "moduleScope" : stage ? data.milestonesSeparate ? "separateScope" : "includedScope" : "mainScope"));
  $("#task-search").disabled = !scope.length;
  let lastGroup = null;
  const rows = [];
  for (const task of items) {
    if (allWork && task.groupId !== lastGroup) {
      const heading = node("div", "work-group-heading", task.groupTitle);
      heading.setAttribute("role", "heading"); heading.setAttribute("aria-level", "3"); rows.push(heading);
      lastGroup = task.groupId;
    }
    const row = node("div", `task-row ${task.status}${workScope ? " work-task" : ""}`);
    row.title = t("sourceLine", {file: task.file || data.tasksFile, line: task.line});
    row.setAttribute("role", "listitem");
    const status = workScope ? task.status === "pending" && task.statusText ? task.statusText : t(`workStatus_${task.status}`) : t(task.done ? "done" : task.dependency ? "dependency" : task.status === "blocked" ? "blocked" : "todo");
    const state = node("span", "task-state");
    const blocked = workScope ? ["blocked", "deferred"].includes(task.status) : task.dependency || task.status === "blocked";
    const icon = node("span", `symbol icon-${task.done ? "done" : blocked ? "blocked" : "pending"}`);
    icon.setAttribute("aria-hidden", "true"); state.append(icon, node("span", "sr-only", status));
    row.append(state, node("span", "task-id", /^(line-|heading-)/.test(task.id) ? "" : task.id));
    const content = node("div"); content.append(node("div", "task-title", task.title));
    if (workScope) {
      const stateText = task.statusText || status;
      content.append(node("p", "task-metadata", task.priority && !stateText.includes(task.priority) ? `${task.priority} · ${stateText}` : stateText));
      if (task.notes?.length) {
        const detail = node("details", "task-notes");
        const key = `${task.groupId}:${task.id}`;
        detail.open = taskNotesOpen.has(key);
        detail.append(node("summary", "", t("taskNotes")));
        for (const note of task.notes) {
          const paragraph = node("p"); paragraph.append(node("strong", "", `${note.label}${language === "zh" ? "：" : language === "fr" ? " : " : ": "}`), document.createTextNode(note.text)); detail.append(paragraph);
        }
        const source = node("button", "text-button", t("readDocument")); source.type = "button";
        source.addEventListener("click", () => readDocument(task.file, source)); detail.append(source);
        detail.addEventListener("toggle", () => { if (detail.open) taskNotesOpen.add(key); else taskNotesOpen.delete(key); });
        content.append(detail);
      }
    } else if (!task.done && task.dependency) content.append(node("p", "dependency-text", task.dependency));
    else if (task.status === "blocked") content.append(node("p", "dependency-text", t("blocked")));
    row.append(content);
    rows.push(row);
  }
  $("#task-list").replaceChildren(...rows);
  if (!items.length) $("#task-list").append(node("p", "empty-tasks", t(data.state === "no-plan" ? "emptyPlan" : "emptyTasks")));
  document.querySelectorAll("[data-filter]").forEach((button) => { button.classList.toggle("active", button.dataset.filter === filter); button.setAttribute("aria-pressed", String(button.dataset.filter === filter)); });
}
function renderMilestones() {
  const selected = document.activeElement?.dataset.stage;
  const scroll = $("#milestones").scrollTop;
  const main = node("button", `milestone-row main-scope${stageId === null ? " selected" : ""}`);
  main.type = "button"; main.dataset.stage = "main"; main.setAttribute("aria-pressed", String(stageId === null));
  main.setAttribute("aria-label", `${t("mainChecklist")} · ${data.overall.done}/${data.overall.total}`);
  main.append(node("span", "milestone-name", t("mainChecklist")), node("span", "milestone-count", `${data.overall.done}/${data.overall.total}`));
  main.addEventListener("click", () => selectStage(null));
  const all = node("button", `milestone-row${stageId === "work" ? " selected" : ""}`);
  all.type = "button"; all.dataset.stage = "work"; all.setAttribute("aria-pressed", String(stageId === "work"));
  all.append(node("span", "milestone-name", t("moduleTasks")), node("span", "milestone-count", workTaskCount(data.work?.taskCount || 0)));
  all.addEventListener("click", () => selectStage("work"));
  $("#milestones").replaceChildren(...(modular() ? [all] : []), ...(data.overall.total ? [main] : []), ...workGroups().map((milestone) => {
    const active = modular() ? milestone.active : milestone.id === data.current?.id;
    const row = node("button", `milestone-row${stageId === milestone.id ? " selected" : ""}`);
    row.type = "button"; row.dataset.stage = milestone.id; row.setAttribute("aria-pressed", String(stageId === milestone.id));
    const count = modular() ? workTaskCount(milestone.total) : `${milestone.done}/${milestone.total}`;
    row.setAttribute("aria-label", `${milestone.title} · ${count}${active ? ` · ${t(modular() ? "workStatus_in_progress" : "currentStage")}` : ""}`);
    const name = node("span", "milestone-name", milestone.title.replace(/^持续实施及/, ""));
    if (active) name.append(node("span", "current-stage-label", t(modular() ? "workStatus_in_progress" : "currentStage")));
    row.append(name, node("span", "milestone-count", count));
    row.addEventListener("click", () => selectStage(milestone.id));
    return row;
  }));
  if (selected) [...document.querySelectorAll("[data-stage]")].find((item) => item.dataset.stage === selected)?.focus({preventScroll: true});
  $("#milestones").scrollTop = scroll;
  fitScopeMenu();
}
async function readDocument(file, trigger) {
  const generation = ++documentGeneration;
  const selected = projectId;
  text("#document-title", file); text("#document-text", t("reading"));
  showDialog($("#document-dialog"), trigger);
  try {
    const result = await api(`/api/document?project=${encodeURIComponent(selected)}&file=${encodeURIComponent(file)}`);
    if (generation === documentGeneration) { text("#document-text", result.text); $("#document-text").scrollTop = 0; }
  } catch (failure) { if (generation === documentGeneration) text("#document-text", failure.message); }
}
function renderContext() {
  $("#project-notes").replaceChildren(...data.context.map((document, index) => {
    const detail = node("details", "project-note");
    detail.open = noteOpen.get(document.file) ?? (index === 0 && data.state === "no-plan");
    const heading = node("summary");
    const labels = node("span"); labels.append(node("strong", "", document.title), node("small", "", document.file));
    const chevron = node("span", "symbol icon-chevron"); chevron.setAttribute("aria-hidden", "true");
    heading.append(labels, chevron);
    const body = node("div", "note-body"); body.append(node("p", "", document.text));
    const footer = node("div", "note-footer");
    const read = node("button", "text-button", t("readDocument")); read.type = "button";
    read.addEventListener("click", () => readDocument(document.file, read));
    footer.append(node("small", "", t("modified", {date: new Date(document.modified * 1000).toLocaleString(displayLocale())})), read);
    body.append(footer); detail.append(heading, body);
    detail.addEventListener("toggle", () => noteOpen.set(document.file, detail.open));
    return detail;
  }));
  if (!data.context.length) $("#project-notes").append(node("p", "context-empty", t("noContext")));
}
function render() {
  const {overall, current, next, eta} = data;
  const localizedEta = etaText(eta);
  text("#project-title", data.name); text("#mini-name", data.name);
  text("#mini-eta", localizedEta.label);
  $("#mini-eta").title = localizedEta.detail;
  renderPercent(overall);
  text("#overall-count", overall.total ? `${overall.done} / ${overall.total}` : t("noChecklist"));
  const bar = $("#overall-bar");
  bar.setAttribute("role", overall.total ? "progressbar" : "img");
  bar.setAttribute("aria-label", t(overall.total ? "progressLabel" : "waiting"));
  if (overall.total) bar.setAttribute("aria-valuenow", overall.percent); else bar.removeAttribute("aria-valuenow");
  bar.setAttribute("aria-valuetext", overall.total ? t("progressValue", overall) : t("noProgress"));
  requestAnimationFrame(() => { $(".bar-fill").style.width = `${overall.percent}%`; });
  $("#content").classList.toggle("no-plan", data.state === "no-plan");
  text("#active-source", data.tasksFile || t("choosePlan"));
  $("#choose-source").title = data.tasksFile || t("choosePlan");
  text("#method", t(data.state === "no-plan" ? "noPlanMethod" : modular() ? "moduleMethod" : data.milestonesSeparate ? "method" : "groupedMethod"));
  text("#current-kind", t(modular() ? current ? "currentModule" : "workStructure" : data.groupKind === "section" ? "currentGroup" : "currentLevel"));
  text("#current-title", current ? shortTitle(current.title) : modular() ? moduleCount(data.work.groupCount) : t(overall.total ? "mainChecklist" : "waiting"));
  text("#phase-count", modular() ? workTaskCount(current?.total ?? data.work.taskCount) : current ? `${current.done} / ${current.total}` : overall.total ? `${overall.done} / ${overall.total}` : "—");
  $(".current-summary").hidden = !current && !modular();
  $("#view-current").hidden = !current && !modular();
  text("#next-kind", t(data.nextKind === "ready" ? "plannedNext" : data.nextKind === "active" ? "activeTask" : "next"));
  text("#next-task", next ? `${/^(line-|heading-)/.test(next.id) ? "" : `${next.id} · `}${next.title}` : t(data.state === "no-plan" ? "nextNoPlan" : modular() ? "noReadyTask" : "checklistComplete"));
  text("#mini-current", modular() ? moduleCount(data.work.groupCount) : current ? current.title.replace(/^持续实施及/, "") : next?.title || t(data.state === "no-plan" ? "waiting" : "completeShort"));
  text("#mini-phase-count", modular() ? workTaskCount(data.work.taskCount) : current ? `${current.done}/${current.total}` : "");
  text("#work-warning", (data.warnings || []).map((item) => `${item.file} · ${I18N.error(item.message, language)}`).join(language === "zh" ? "；" : "; "));
  $("#work-warning").hidden = !data.warnings?.length;
  text("#eta-label", localizedEta.label);
  $("#eta-label").title = localizedEta.detail;
  $("#eta-label").setAttribute("aria-description", localizedEta.detail);
  $("#estimate").disabled = overall.done === overall.total;
  renderTasks();
  renderMilestones(); renderContext();
  text("#dependency-count", t("dependencies", {count: data.dependencies}));
  $("#dependency-note").hidden = !data.dependencies;
  $("#sources").replaceChildren(...data.sources.map((source) => {
    const item = node("div", "source-file", source.file);
    item.title = source.path;
    item.append(node("small", "", t("modified", {date: new Date(source.modified * 1000).toLocaleString(displayLocale())})));
    const read = node("button", "text-button", t("readDocument")); read.addEventListener("click", () => readDocument(source.file, read)); item.append(read);
    return item;
  }));
  $("#activity").replaceChildren(...data.activity.map((commit) => {
    const row = node("div", "commit-row");
    row.append(node("code", "", commit.commit), document.createTextNode(commit.title));
    row.title = new Date(commit.date).toLocaleString(displayLocale());
    return row;
  }));
  if (!data.activity.length) $("#activity").append(node("p", "empty-tasks", t("noCommits")));
}
async function refresh(manual = false) {
  if (loading || !projectId) return;
  loading = true;
  if (manual) $("#refresh").classList.add("is-loading");
  const selected = projectId;
  try {
    const result = await api(`/api/progress?project=${encodeURIComponent(selected)}`);
    if (projectId !== selected) return;
    const signature = JSON.stringify([result.revision, result.sources, result.primary, result.eta, result.activity, result.context, result.warnings, result.groups]);
    const firstPaint = !data || data.id !== result.id;
    const changed = data && data.revision !== result.revision;
    $("#authorize-project").hidden = true;
    data = result;
    if (modular() && !scopeChosen) stageId = "work";
    if (firstPaint && data.state === "no-plan") setResourceView(true);
    if (signature !== lastSignature) { render(); lastSignature = signature; }
    updateReadTime();
    $("#error").hidden = true; $("#loading").hidden = true; $("#content").hidden = false;
    $("#repair-source").hidden = true;
    renderSyncState();
    if (firstPaint) animatePage();
    if (changed) toast(t("updated"));
    else if (manual) toast(t("refreshed"));
  } catch (failure) { if (projectId === selected) {
    if (failure.status === 403) { data = null; lastSignature = ""; $("#content").hidden = true; }
    error(t("readFailed", {error: failure.message})); $("#authorize-project").hidden = !nativeAPI || failure.status !== 403;
    $("#loading").hidden = true; $("#repair-source").hidden = failure.status === 403; renderSyncState();
  } }
  finally { loading = false; $("#refresh").classList.remove("is-loading"); if (selected !== projectId) refresh(); }
}
$("#refresh").addEventListener("click", () => refresh(true));
document.querySelectorAll("[data-filter]").forEach((button) => button.addEventListener("click", () => { filter = button.dataset.filter; renderTasks(); }));
$("#task-search").addEventListener("input", () => { if (data) renderTasks(); });
$("#view-current").addEventListener("click", () => { if (modular()) selectStage(data.current?.id || "work"); else if (data?.current) selectStage(data.current.id); });
document.querySelectorAll(".close-dialog").forEach((button) => button.addEventListener("click", () => closeDialog(button.closest("dialog"))));
function selectConnectionProvider(provider) {
  connectionProvider = provider;
  discoveryGeneration++;
  $("#project-form").hidden = provider !== "manual";
  $("#discovery-section").hidden = provider === "manual";
  $("#connection-error").hidden = true;
  document.querySelectorAll("[data-provider]").forEach((button) => {
    button.classList.toggle("active", button.dataset.provider === provider);
    button.setAttribute("aria-pressed", String(button.dataset.provider === provider));
  });
  if (provider !== "manual") loadCatalog();
}
async function loadCatalog() {
  const generation = ++discoveryGeneration;
  catalog = null;
  text("#catalog-status", t("catalogReading"));
  $("#project-catalog").replaceChildren();
  $("#connection-error").hidden = true;
  try {
    const result = await api(`/api/discovery?provider=${connectionProvider}`);
    if (generation !== discoveryGeneration) return;
    catalog = result;
    renderCatalog(result);
  } catch (failure) {
    if (generation !== discoveryGeneration) return;
    text("#catalog-status", t("catalogUnavailable"));
    text("#connection-error", failure.message); $("#connection-error").hidden = false;
  }
}
async function authorizeRegistry() {
  try {
    const result = await api("/api/permissions/registry", {provider: connectionProvider});
    if (!result.cancelled) await loadCatalog();
  } catch (failure) { text("#connection-error", failure.message); $("#connection-error").hidden = false; }
}
function renderCatalog(result) {
    $("#choose-registry").hidden = !nativeAPI;
    if (result.needsPermission) {
      text("#catalog-status", t("registryPermission"));
      $("#project-catalog").replaceChildren();
      return;
    }
    text("#catalog-status", result.projects.length ? t("catalogCount", {count: result.projects.length}) : t("catalogEmpty"));
    $("#project-catalog").replaceChildren(...result.projects.map((project, index) => {
      const row = node("button", "catalog-project"); row.type = "button";
      row.disabled = !project.available;
      row.setAttribute("aria-label", `${project.name} · ${t(project.connectedId ? "switch" : "connect")}`);
      const icon = node("span", "symbol icon-project"); icon.setAttribute("aria-hidden", "true");
      const info = node("span", "catalog-info");
      info.append(node("strong", "", project.name), node("span", "catalog-path", project.root),
                  node("span", "catalog-plan", !project.available ? t("removed") : project.requiresAuthorization ? t("authorizeConnect") : project.connectedId ? t("connected") : project.tasksFile ? t("detectedPlan", {file: project.tasksFile}) : t("noPlanConnect")));
      row.append(icon, info, node("span", "catalog-action", t(project.connectedId ? "switch" : "connect")));
      row.addEventListener("click", () => connectCatalogProject(project, row));
      return row;
    }));
}
async function connectCatalogProject(project, button) {
  button.disabled = true;
  $("#connection-error").hidden = true;
  try {
    const result = await api("/api/connections", {provider: connectionProvider, project: project.id});
    projects = (await api("/api/projects")).projects;
    await closeDialog($("#project-dialog")); await selectProject(result.id);
    toast(t(result.awaitingPlan ? "waitingToast" : result.alreadyConnected ? "switched" : "connectedToast"));
  } catch (failure) {
    text("#connection-error", failure.message); $("#connection-error").hidden = false;
  } finally { button.disabled = false; }
}
document.querySelectorAll("[data-provider]").forEach((button) => button.addEventListener("click", () => selectConnectionProvider(button.dataset.provider)));
$("#refresh-catalog").addEventListener("click", loadCatalog);
$("#choose-registry").addEventListener("click", authorizeRegistry);
$("#choose-folder").addEventListener("click", async () => {
  try {
    const result = await api("/api/permissions/folder", {});
    if (result.cancelled) return;
    const form = $("#project-form"); form.elements.root.value = result.root;
    if (!form.elements.name.value.trim()) form.elements.name.value = result.root.split("/").filter(Boolean).pop() || "Project";
    form.querySelector(".form-error").textContent = "";
  } catch (failure) { $("#project-form .form-error").textContent = failure.message; }
});
$("#authorize-project").addEventListener("click", async () => {
  try {
    const result = await api("/api/permissions/project", {project: projectId});
    if (!result.cancelled) { nativeAction("projects-changed"); await refresh(true); }
  } catch (failure) { error(failure.message); }
});
if (nativeAPI) {
  $("#folder-picker-row").hidden = false;
  const input = $("#project-form [name=root]"); input.readOnly = true;
  input.previousElementSibling.dataset.i18n = "projectFolder";
  input.dataset.i18nPlaceholder = "chooseFolderHint";
}
function openConnectionDialog(event) {
  if ($("#project-dialog").open) return;
  $("#project-form .form-error").textContent = "";
  $("#add-project").classList.add("is-open");
  $("#add-project").setAttribute("aria-expanded", "true");
  showDialog($("#project-dialog"), event?.currentTarget || $("#add-project")); selectConnectionProvider("codex");
}
$("#add-project").addEventListener("click", openConnectionDialog);
$("#empty-connect").addEventListener("click", openConnectionDialog);
$("#project-dialog").addEventListener("close", () => {
  $("#add-project").classList.remove("is-open");
  $("#add-project").setAttribute("aria-expanded", "false");
});
$("#project-form").addEventListener("submit", async (event) => {
  event.preventDefault(); const form = event.currentTarget; const submit = form.querySelector("[type=submit]"); submit.disabled = true;
  try {
    const result = await api("/api/projects", Object.fromEntries(new FormData(form)));
    projects = (await api("/api/projects")).projects;
    await closeDialog($("#project-dialog")); await selectProject(result.id); toast(t("connectedToast"));
  } catch (failure) { form.querySelector(".form-error").textContent = failure.message; }
  finally { submit.disabled = false; }
});
$("#estimate").addEventListener("click", (event) => {
  $("#estimate-form .form-error").textContent = "";
  $("#estimate-rows").replaceChildren(...data.primary.filter((task) => !task.done).map((task) => {
    const row = node("div", "estimate-row"); row.dataset.task = task.id;
    row.append(node("span", "", `${task.id} · ${task.title}`));
    for (let index = 0; index < 2; index++) {
      const input = node("input"); input.type = "number"; input.min = "0"; input.max = "10000"; input.step = "0.1";
      input.setAttribute("aria-label", t(index ? "maxHoursLabel" : "minHoursLabel", {id: task.id}));
      input.value = data.estimates[task.id]?.[index] ?? ""; row.append(input);
    }
    return row;
  }));
  $("[name=hoursPerDay]").value = data.hoursPerDay;
  showDialog($("#estimate-dialog"), event.currentTarget);
});
$("#estimate-form").addEventListener("submit", async (event) => {
  event.preventDefault(); const form = event.currentTarget; const submit = form.querySelector("[type=submit]");
  const estimates = {};
  for (const row of document.querySelectorAll(".estimate-row")) {
    const inputs = [...row.querySelectorAll("input")];
    if (inputs.every((input) => input.value === "")) continue;
    if (inputs.some((input) => input.value === "")) { form.querySelector(".form-error").textContent = t("estimateIncomplete"); return; }
    estimates[row.dataset.task] = inputs.map((input) => Number(input.value));
  }
  submit.disabled = true;
  try {
    await api("/api/estimates", {project: projectId, estimates, hoursPerDay: Number(form.elements.hoursPerDay.value)});
    await closeDialog($("#estimate-dialog")); await refresh(); toast(t("estimateSaved"));
  } catch (failure) { form.querySelector(".form-error").textContent = failure.message; }
  finally { submit.disabled = false; }
});
async function openSourceDialog(event) {
  if (!projectId) return;
  const generation = ++sourceGeneration;
  sourceProject = projectId;
  $("#source-form .form-error").textContent = "";
  $("#source-path").value = data?.tasksFile || "";
  $("#source-options").replaceChildren(node("p", "", t("reading")));
  const trigger = event?.currentTarget;
  showDialog($("#source-dialog"), trigger?.id === "scope-source" ? $("#scope-picker summary") : trigger || $("#choose-source"));
  try {
    const result = await api(`/api/sources?project=${encodeURIComponent(sourceProject)}`);
    if (generation !== sourceGeneration || !$("#source-dialog").open) return;
    if (!$("#source-path").value) $("#source-path").value = result.selected || "";
    $("#source-options").replaceChildren(...result.choices.map((choice) => {
      const button = node("button", "source-option"); button.type = "button";
      button.classList.toggle("active", choice.file === result.selected);
      button.setAttribute("aria-pressed", String(choice.file === result.selected));
      button.append(node("strong", "", choice.file), node("small", "", choice.total ? t("planCount", choice) : workTaskCount(choice.workTasks || 0)));
      button.addEventListener("click", () => {
        $("#source-path").value = choice.file;
        document.querySelectorAll(".source-option").forEach((option) => { option.classList.toggle("active", option === button); option.setAttribute("aria-pressed", String(option === button)); });
      });
      return button;
    }));
    if (!result.choices.length) $("#source-options").append(node("p", "", t("noPlansFound")));
  } catch (failure) {
    if (generation === sourceGeneration) { $("#source-options").replaceChildren(); $("#source-form .form-error").textContent = failure.message; }
  }
}
$("#choose-source").addEventListener("click", openSourceDialog);
$("#scope-source").addEventListener("click", openSourceDialog);
$("#repair-source").addEventListener("click", openSourceDialog);
$("#source-dialog").addEventListener("close", () => { sourceGeneration++; sourceProject = null; });
$("#source-form").addEventListener("submit", async (event) => {
  event.preventDefault();
  const submit = event.currentTarget.querySelector("[type=submit]"); submit.disabled = true;
  const selected = sourceProject;
  try {
    await api("/api/sources", {project: selected, file: $("#source-path").value});
    await closeDialog($("#source-dialog"));
    if (selected === projectId) { stageId = null; scopeChosen = false; suspendedScope = null; taskNotesOpen.clear(); filter = "all"; $("#task-search").value = ""; lastSignature = ""; await refresh(); }
    nativeAction("projects-changed"); toast(t("planSelected"));
  } catch (failure) { $("#source-form .form-error").textContent = failure.message; }
  finally { submit.disabled = false; }
});
$("#document-dialog").addEventListener("close", () => { documentGeneration++; });
async function start() {
  try {
    const [preferences, projectList] = await Promise.all([api("/api/preferences"), api("/api/projects")]);
    languagePreference = preferences.language;
    applyLanguage();
    projects = projectList.projects;
    await selectProject(projects.some((project) => project.id === projectId) ? projectId : projects[0]?.id);
  } catch (failure) { error(failure.message); $("#loading").hidden = true; }
}
$("#cancel-remove").addEventListener("click", () => closeDialog($("#remove-dialog")));
$("#remove-dialog").addEventListener("close", () => { removalTarget = null; });
$("#confirm-remove").addEventListener("click", async (event) => {
  const target = removalTarget;
  if (!target || event.currentTarget.disabled) return;
  const submit = event.currentTarget; submit.disabled = true;
  const index = projects.findIndex((project) => project.id === target.id);
  try {
    const result = await api("/api/projects/remove", {project: target.id});
    projects = result.projects;
    await closeDialog($("#remove-dialog"));
    if (projectId === target.id) await selectProject(projects[Math.min(index, projects.length - 1)]?.id);
    else { renderProjects(); if (data) render(); }
    nativeAction("projects-changed");
    const selected = [...document.querySelectorAll(".project-entry")].find((entry) => entry.dataset.project === projectId);
    (selected?.querySelector(".project-button") || $("#add-project")).focus({preventScroll: true});
    toast(t("projectRemoved", {name: target.name}));
  } catch (failure) {
    text("#remove-error", failure.message); $("#remove-error").hidden = false;
    if (!$("#remove-dialog").open) error(failure.message);
  } finally { submit.disabled = false; }
});
$("#language-select").addEventListener("change", async (event) => {
  const selection = event.target.value;
  event.target.disabled = true;
  try {
    await api("/api/preferences", {language: selection});
    languagePreference = selection;
    localStorage.setItem("questlog.language", selection);
    applyLanguage(); toast(t("languageSaved"));
    nativeAction(`language:${selection}`);
  } catch (failure) { event.target.value = languagePreference; error(failure.message); }
  finally { event.target.disabled = false; }
});
applyLanguage();
if (native) {
  window.questlogNavigate = async (action, identity) => {
    for (const dialog of document.querySelectorAll("dialog[open]")) await closeDialog(dialog);
    if (action === "project") await selectProject(projects.find((project) => project.id === identity)?.id || projects[0]?.id);
    else if (action === "connect") $("#add-project").click();
    else if (action === "settings") $("#settings").click();
  };
}
start().then(() => nativeAction("details-ready"));
setInterval(() => { if (projectId) refresh(); }, 5000);
