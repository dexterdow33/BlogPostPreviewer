/* NH Bill Tracker - Granite State Report
   Vanilla JS, no build step. Reads data/index.json and data/nh_bills_<session>.json
   produced by scripts/fetch_nh_bills.py. All text is inserted with textContent. */
(() => {
  "use strict";

  // ------------------------------------------------------------------ config
  const GROUPS = [
    { key: "law",     label: "Became law",          codes: ["law", "veto_overridden"] },
    { key: "process", label: "In process / other",  codes: ["enrolled", "conference", "passed_chamber", "committee_report", "recommitted", "hearing", "in_committee", "unknown"] },
    { key: "parked",  label: "Parked",              codes: ["interim_study", "retained", "rereferred", "tabled"] },
    { key: "killed",  label: "Killed",              codes: ["killed", "died_on_table", "conference_failed", "nonconcurred", "returned_to_house"] },
    { key: "vetoed",  label: "Vetoed",              codes: ["vetoed", "veto_sustained"] },
  ];
  const GROUP_OF = {};
  GROUPS.forEach(g => g.codes.forEach(c => (GROUP_OF[c] = g.key)));
  const PARTY = { R: "R", D: "D", I: "I" };
  const who = (s) => {
    const r = (state.roster && state.roster[s.id]) || {};
    const party = s.party || r.party || "";
    const district = r.district ? (r.body === "S" ? "Dist. " + r.district : (r.county ? r.county + " " : "") + r.district) : "";
    return party ? `${s.name} (${PARTY[party] || party}${district ? ", " + district : ""})` : s.name;
  };
  const GROUP_LABEL = Object.fromEntries(GROUPS.map(g => [g.key, g.label]));
  const PAGE = 150;

  const metaBase = document.querySelector('meta[name="data-base"]');
  const BASES = [metaBase ? metaBase.content : "../data/", "data/", "./"];

  // ------------------------------------------------------------------ helpers
  const $ = (id) => document.getElementById(id);
  function el(tag, props, ...children) {
    const node = document.createElement(tag);
    if (props) {
      for (const [k, v] of Object.entries(props)) {
        if (v === null || v === undefined || v === false) continue;
        if (k === "class") node.className = v;
        else if (k === "text") node.textContent = v;
        else if (k === "html") throw new Error("innerHTML is not used");
        else if (k.startsWith("on") && typeof v === "function") node.addEventListener(k.slice(2).toLowerCase(), v);
        else if (k === "dataset") Object.assign(node.dataset, v);
        else node.setAttribute(k, v === true ? "" : String(v));
      }
    }
    for (const c of children.flat()) {
      if (c === null || c === undefined || c === false) continue;
      node.append(c instanceof Node ? c : document.createTextNode(String(c)));
    }
    return node;
  }
  const fmtInt = (n) => (n === null || n === undefined ? "" : Number(n).toLocaleString("en-US"));
  function fmtDate(iso) {
    if (!iso) return "";
    const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(iso);
    if (!m) return iso;
    const d = new Date(Date.UTC(+m[1], +m[2] - 1, +m[3]));
    return d.toLocaleDateString("en-US", { year: "numeric", month: "short", day: "numeric", timeZone: "UTC" });
  }
  function fmtStamp(iso) {
    if (!iso) return "";
    const d = new Date(iso);
    if (isNaN(d)) return iso;
    return d.toLocaleString("en-US", { year: "numeric", month: "short", day: "numeric", hour: "numeric", minute: "2-digit", timeZoneName: "short" });
  }
  const store = {
    get(k) { try { return localStorage.getItem(k); } catch { return null; } },
    set(k, v) { try { localStorage.setItem(k, v); } catch { /* per-viewer convenience only */ } },
  };
  async function loadJSON(name) {
    let lastErr;
    for (const b of BASES) {
      try {
        const r = await fetch(b + name, { cache: "no-store" });
        if (r.ok) return await r.json();
        lastErr = new Error(`${r.status} for ${b}${name}`);
      } catch (e) { lastErr = e; }
    }
    throw lastErr || new Error("Could not load " + name);
  }

  // ------------------------------------------------------------------ state
  const state = {
    index: null,
    payload: null,
    session: null,
    bills: [],
    view: [],
    byLabel: new Map(),
    roster: null,
    shown: PAGE,
    leadTab: null,
    filters: { q: "", chamber: "", group: "", beat: "", subject: "", sort: "number", rc: false },
    lastFocus: null,
  };

  // ------------------------------------------------------------------ boot
  async function boot() {
    try {
      state.index = await loadJSON("index.json");
    } catch (e) {
      $("loading").textContent = "The data files could not be loaded. If this page was just deployed, the first refresh job may not have run yet. Details: " + e.message;
      $("loading").className = "status-line err";
      return;
    }
    try { const lj = await loadJSON("legislators.json"); state.roster = lj.roster || null; } catch { state.roster = null; }
    const sessions = (state.index.sessions || []).slice().sort((a, b) => String(a.session).localeCompare(String(b.session)));
    if (!sessions.length) {
      $("loading").textContent = "The refresh job has not produced any session data yet.";
      return;
    }
    const sel = $("f-session");
    sessions.forEach(s => sel.append(el("option", { value: s.session, text: `${s.session} session (${fmtInt(s.bills)} bills)` })));
    const remembered = store.get("nhbt.session");
    const big = sessions.filter(s => s.bills >= 100);
    const def = (remembered && sessions.some(s => String(s.session) === remembered)) ? remembered : String((big.length ? big : sessions).slice(-1)[0].session);
    sel.value = def;
    restoreFilters();
    wireControls();
    await loadSession(def);
    const hashBill = billFromHash();
    if (hashBill) openBill(hashBill);
    window.addEventListener("hashchange", () => { const b = billFromHash(); if (b) openBill(b); else closeDrawer(false); });
    // Embedded in another page (an iframe): the parent sends its own #hash so deep links still open a bill,
    // and this frame reports the open bill back so the parent can update its address bar.
    window.addEventListener("message", (ev) => {
      const d = ev.data || {};
      if (d.nhbt !== "open" || typeof d.hash !== "string") return;
      const m = /^#([A-Za-z]{2,4}\d{1,5})$/.exec(d.hash);
      if (m) { const b = state.byLabel.get(m[1].toUpperCase()); if (b) openBill(b); }
    });
    if (window.parent !== window) { try { window.parent.postMessage({ nhbt: "ready" }, "*"); } catch { /* ignore */ } }
  }

  function billFromHash() {
    const m = /^#([A-Za-z]{2,4}\d{1,5})$/.exec(location.hash || "");
    if (!m) return null;
    return state.byLabel.get(m[1].toUpperCase()) || null;
  }

  async function loadSession(session) {
    $("loading").hidden = false;
    $("loading").className = "status-line";
    $("loading").textContent = `Loading the ${session} session…`;
    const s = (state.index.sessions || []).find(x => String(x.session) === String(session));
    try {
      state.payload = await loadJSON(s ? s.file : `nh_bills_${session}.json`);
    } catch (e) {
      $("loading").textContent = "Could not load this session: " + e.message;
      $("loading").className = "status-line err";
      return;
    }
    state.session = String(session);
    store.set("nhbt.session", state.session);
    state.bills = state.payload.bills || [];
    state.byLabel = new Map();
    for (const b of state.bills) {
      b.group = b.group || GROUP_OF[b.status] || "process";
      if (b.bill_id) state.byLabel.set(b.bill_id, b);
    }
    // subject filter options
    const subjSel = $("f-subject");
    const keepSubj = state.filters.subject;
    subjSel.replaceChildren(el("option", { value: "", text: "All subjects" }));
    const subjCounts = {};
    state.bills.forEach(b => { if (b.subject_code) subjCounts[b.subject_code] = (subjCounts[b.subject_code] || 0) + 1; });
    Object.entries(state.payload.subject_codes || {}).sort((a, b) => (subjCounts[b[0]] || 0) - (subjCounts[a[0]] || 0))
      .forEach(([code, label]) => subjSel.append(el("option", { value: code, text: `${label}${label !== code ? " · " + code : ""} (${fmtInt(subjCounts[code] || 0)})` })));
    subjSel.value = Object.prototype.hasOwnProperty.call(state.payload.subject_codes || {}, keepSubj) ? keepSubj : "";
    state.filters.subject = subjSel.value;
    const note = $("session-note");
    note.hidden = !state.payload.session_note;
    note.textContent = state.payload.session_note || "";
    // beat filter options
    const beatSel = $("f-beat");
    const keep = state.filters.beat;
    beatSel.replaceChildren(el("option", { value: "", text: "All beats" }));
    const beats = Object.entries((state.payload.story_leads && state.payload.story_leads.beats && state.payload.story_leads.beats.counts) || {});
    beats.forEach(([name, n]) => beatSel.append(el("option", { value: name, text: `${name} (${fmtInt(n)})` })));
    beatSel.value = beats.some(([n]) => n === keep) ? keep : "";
    state.filters.beat = beatSel.value;

    $("meta").replaceChildren(
      el("div", null, "Data refreshed ", el("strong", { text: fmtStamp(state.payload.generated_at) })),
      el("div", null, `${fmtInt(state.payload.counts.bills)} bills · ${fmtInt(state.payload.counts.actions)} docket actions · ${fmtInt(state.payload.counts.roll_calls)} roll calls`),
    );
    $("src-note").textContent = `This copy was generated ${fmtStamp(state.payload.generated_at)}.`;
    $("loading").hidden = true;
    ["kpis", "band", "table-section"].forEach(id => ($(id).hidden = false));
    state.shown = PAGE;
    apply();
  }

  // ------------------------------------------------------------------ controls
  function wireControls() {
    $("f-session").addEventListener("change", (e) => loadSession(e.target.value));
    $("f-q").addEventListener("input", debounce((e) => { state.filters.q = e.target.value.trim(); state.shown = PAGE; apply(); }, 120));
    $("f-chamber").addEventListener("change", (e) => { state.filters.chamber = e.target.value; state.shown = PAGE; apply(); });
    $("f-group").addEventListener("change", (e) => { state.filters.group = e.target.value; state.shown = PAGE; apply(); });
    $("f-beat").addEventListener("change", (e) => { state.filters.beat = e.target.value; state.shown = PAGE; apply(); });
    $("f-subject").addEventListener("change", (e) => { state.filters.subject = e.target.value; state.shown = PAGE; apply(); });
    $("f-sort").addEventListener("change", (e) => { state.filters.sort = e.target.value; apply(); });
    $("f-rc").addEventListener("change", (e) => { state.filters.rc = e.target.checked; state.shown = PAGE; apply(); });
    $("f-reset").addEventListener("click", () => {
      state.filters = { q: "", chamber: "", group: "", beat: "", subject: "", sort: "number", rc: false };
      $("f-q").value = ""; $("f-chamber").value = ""; $("f-group").value = ""; $("f-beat").value = ""; $("f-subject").value = ""; $("f-sort").value = "number"; $("f-rc").checked = false;
      state.shown = PAGE; apply();
    });
    $("stack-toggle").addEventListener("click", () => toggleTable("stack"));
    $("act-toggle").addEventListener("click", () => toggleTable("activity"));
    $("scrim").addEventListener("click", () => closeDrawer(true));
    document.addEventListener("keydown", (e) => { if (e.key === "Escape" && !$("drawer").hidden) closeDrawer(true); });
  }
  function restoreFilters() {
    try {
      const saved = JSON.parse(store.get("nhbt.filters") || "null");
      if (saved && typeof saved === "object") Object.assign(state.filters, saved);
    } catch { /* ignore */ }
    $("f-q").value = state.filters.q || "";
    $("f-chamber").value = state.filters.chamber || "";
    $("f-group").value = state.filters.group || "";
    $("f-sort").value = state.filters.sort || "number";
    $("f-rc").checked = !!state.filters.rc;
  }
  function debounce(fn, ms) { let t; return (...a) => { clearTimeout(t); t = setTimeout(() => fn(...a), ms); }; }
  function toggleTable(which) {
    const btn = $(which === "stack" ? "stack-toggle" : "act-toggle");
    const chart = $(which === "stack" ? "stack-chart" : "activity-chart");
    const table = $(which === "stack" ? "stack-table" : "activity-table");
    const showTable = table.hidden;
    table.hidden = !showTable; chart.hidden = showTable;
    btn.setAttribute("aria-pressed", String(showTable));
    btn.textContent = showTable ? "Chart" : "Table";
  }

  // ------------------------------------------------------------------ filtering
  function apply() {
    store.set("nhbt.filters", JSON.stringify(state.filters));
    const f = state.filters;
    const q = f.q.toLowerCase();
    const qBill = q.replace(/\s+/g, "").toUpperCase();
    state.view = state.bills.filter(b => {
      if (f.chamber && b.origin_chamber !== f.chamber) return false;
      if (f.group && b.group !== f.group) return false;
      if (f.beat && !(b.beats || []).includes(f.beat)) return false;
      if (f.subject && b.subject_code !== f.subject) return false;
      if (f.rc && !b.n_roll_calls) return false;
      if (q) {
        const hay = `${b.title} ${b.prime_sponsor} ${b.committee || ""} ${b.lsr_id} ${b.status_label} ${b.subject || ""} ${b.chapter ? "chapter " + b.chapter : ""} ${(b.sponsors || []).map(s => s.name).join(" ")}`.toLowerCase();
        if (!(b.bill_id && b.bill_id.startsWith(qBill)) && !hay.includes(q)) return false;
      }
      return true;
    });
    sortView();
    renderKPIs();
    renderStack();
    renderActivity();
    renderLeads();
    renderTable();
    const total = state.bills.length;
    $("count").textContent = state.view.length === total ? `${fmtInt(total)} bills` : `${fmtInt(state.view.length)} of ${fmtInt(total)} bills`;
  }
  function billNum(b) { const m = /(\d+)/.exec(b.bill_id || ""); return m ? +m[1] : 1e9; }
  function sortView() {
    const s = state.filters.sort;
    const v = state.view;
    if (s === "recent") v.sort((a, b) => (b.last_action_date || "").localeCompare(a.last_action_date || "") || billNum(a) - billNum(b));
    else if (s === "rollcalls") v.sort((a, b) => (b.n_roll_calls - a.n_roll_calls) || billNum(a) - billNum(b));
    else if (s === "margin") v.sort((a, b) => ((a.closest_margin ?? 1e9) - (b.closest_margin ?? 1e9)) || billNum(a) - billNum(b));
    else if (s === "title") v.sort((a, b) => a.title.localeCompare(b.title));
    else v.sort((a, b) => ((a.bill_id || "ZZZ").replace(/\d+/, "").localeCompare((b.bill_id || "ZZZ").replace(/\d+/, ""))) || billNum(a) - billNum(b));
  }

  // ------------------------------------------------------------------ KPIs
  function renderKPIs() {
    const v = state.view;
    const counts = Object.fromEntries(GROUPS.map(g => [g.key, 0]));
    let overrides = 0, sustained = 0, withRC = 0, upcoming = 0;
    for (const b of v) {
      counts[b.group]++;
      if (b.status === "veto_overridden") overrides++;
      if (b.status === "veto_sustained") sustained++;
      if (b.n_roll_calls) withRC++;
      if ((b.next_events || []).length) upcoming++;
    }
    const tiles = [
      tile("Bills in view", v.length, `${fmtInt(withRC)} with roll calls · ${fmtInt(upcoming)} with sessions scheduled`, null, true),
      tile("Became law", counts.law, overrides ? `${fmtInt(overrides)} by veto override` : "signed or allowed to become law", "law"),
      tile("Vetoed", counts.vetoed, sustained ? `${fmtInt(sustained)} vetoes sustained` : "veto stands unless overridden", "vetoed"),
      tile("Killed", counts.killed, "inexpedient to legislate or postponed", "killed"),
      tile("Parked", counts.parked, "interim study, retained, re-referred, tabled", "parked"),
      tile("In process / other", counts.process, "not yet at a final action, or unclassified", "process"),
    ];
    $("kpis").replaceChildren(...tiles);
  }
  function tile(label, value, sub, group, hero) {
    const t = el("div", { class: `tile${hero ? " hero" : ""}${group ? " has-swatch" : ""}` },
      el("div", { class: "label", text: label }),
      el("div", { class: "value", text: fmtInt(value) }),
      el("div", { class: "sub", text: sub }),
      group ? el("span", { class: "swatch", style: `background: var(--cat-${group})`, "aria-hidden": "true" }) : null,
    );
    if (group) {
      t.append(el("button", { class: "tile-btn", "aria-label": `Filter to ${label}`, onClick: () => {
        state.filters.group = state.filters.group === group ? "" : group; $("f-group").value = state.filters.group; state.shown = PAGE; apply();
      } }));
    }
    return t;
  }

  // ------------------------------------------------------------------ stacked bar
  function renderStack() {
    const v = state.view;
    const total = v.length || 1;
    const counts = Object.fromEntries(GROUPS.map(g => [g.key, 0]));
    v.forEach(b => counts[b.group]++);
    const bar = el("div", { class: "stack", role: "img", "aria-label": GROUPS.map(g => `${g.label}: ${counts[g.key]}`).join("; ") });
    GROUPS.forEach(g => {
      const n = counts[g.key];
      if (!n) return;
      const seg = el("div", { class: "seg", tabindex: "0", style: `flex: ${n} ${n} 0; background: var(--cat-${g.key})`, "aria-label": `${g.label}: ${n} bills (${Math.round(100 * n / total)}%)` });
      const show = (ev) => showTip(ev, [`${fmtInt(n)} bills`, g.label, `${Math.round(100 * n / total)}% of the bills in view`]);
      seg.addEventListener("pointermove", show); seg.addEventListener("focus", show);
      seg.addEventListener("pointerleave", hideTip); seg.addEventListener("blur", hideTip);
      bar.append(seg);
    });
    const legend = el("div", { class: "legend" }, GROUPS.map(g => el("span", { class: "k" }, el("i", { style: `background: var(--cat-${g.key})` }), `${g.label} `, el("b", { text: fmtInt(counts[g.key]) }))));
    $("stack-chart").replaceChildren(bar, legend);
    // table twin
    const t = el("table", { class: "tv" }, el("thead", null, el("tr", null, el("th", { text: "Outcome" }), el("th", { class: "num", text: "Bills" }), el("th", { class: "num", text: "Share" }))),
      el("tbody", null, GROUPS.map(g => el("tr", null, el("td", { text: g.label }), el("td", { class: "num", text: fmtInt(counts[g.key]) }), el("td", { class: "num", text: `${Math.round(100 * counts[g.key] / total)}%` })))));
    $("stack-table").replaceChildren(el("div", { class: "tv-wrap" }, t));
  }

  // ------------------------------------------------------------------ activity chart
  function renderActivity() {
    const v = state.view;
    const bins = new Map();
    let min = null, max = null;
    for (const b of v) for (const a of b.actions || []) {
      const d = a.date; if (!/^\d{4}-\d{2}-\d{2}$/.test(d)) continue;
      if (!min || d < min) min = d; if (!max || d > max) max = d;
    }
    const wrap = $("activity-chart");
    if (!min) { wrap.replaceChildren(el("div", { class: "empty", text: "No docket actions in view." })); $("activity-table").replaceChildren(); return; }
    // weekly bins (Monday start), fall back to monthly when the span is long
    const start = new Date(min + "T00:00:00Z"), end = new Date(max + "T00:00:00Z");
    const weeks = Math.ceil((end - start) / (7 * 864e5)) + 1;
    const monthly = weeks > 90;
    const keyOf = (d) => {
      const dt = new Date(d + "T00:00:00Z");
      if (monthly) return `${dt.getUTCFullYear()}-${String(dt.getUTCMonth() + 1).padStart(2, "0")}`;
      const day = (dt.getUTCDay() + 6) % 7; dt.setUTCDate(dt.getUTCDate() - day);
      return dt.toISOString().slice(0, 10);
    };
    for (const b of v) for (const a of b.actions || []) {
      if (!/^\d{4}-\d{2}-\d{2}$/.test(a.date)) continue;
      const k = keyOf(a.date); bins.set(k, (bins.get(k) || 0) + 1);
    }
    // fill gaps
    const keys = [];
    if (monthly) {
      const c = new Date(Date.UTC(start.getUTCFullYear(), start.getUTCMonth(), 1));
      while (c <= end) { keys.push(`${c.getUTCFullYear()}-${String(c.getUTCMonth() + 1).padStart(2, "0")}`); c.setUTCMonth(c.getUTCMonth() + 1); }
    } else {
      const c = new Date(keyOf(min) + "T00:00:00Z");
      while (c <= end) { keys.push(c.toISOString().slice(0, 10)); c.setUTCDate(c.getUTCDate() + 7); }
    }
    const values = keys.map(k => bins.get(k) || 0);
    const peak = Math.max(1, ...values);
    const W = 560, H = 190, padL = 38, padR = 8, padT = 10, padB = 28;
    const plotW = W - padL - padR, plotH = H - padT - padB;
    const slot = plotW / keys.length;
    const barW = Math.min(24, Math.max(2, slot - 2));
    const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
    svg.setAttribute("viewBox", `0 0 ${W} ${H}`); svg.setAttribute("class", "activity"); svg.setAttribute("role", "img");
    svg.setAttribute("aria-label", `Docket actions per ${monthly ? "month" : "week"}, ${fmtDate(min)} to ${fmtDate(max)}; peak ${fmtInt(peak)}.`);
    const ns = (tag, attrs) => { const n = document.createElementNS("http://www.w3.org/2000/svg", tag); for (const [k, val] of Object.entries(attrs)) n.setAttribute(k, val); return n; };
    const grid = ns("g", { class: "grid" });
    const ticks = niceTicks(peak);
    ticks.forEach(t => {
      const y = padT + plotH - (t / peak) * plotH;
      grid.append(ns("line", { x1: padL, x2: W - padR, y1: y, y2: y }));
      const label = ns("text", { x: padL - 6, y: y + 4, "text-anchor": "end" }); label.textContent = fmtInt(t); svg.append(label);
    });
    svg.append(grid);
    keys.forEach((k, i) => {
      const val = values[i];
      const h = (val / peak) * plotH;
      const x = padL + i * slot + (slot - barW) / 2;
      const y = padT + plotH - h;
      const r = Math.min(4, barW / 2, h);
      const path = ns("path", { class: "col", d: roundedTop(x, y, barW, h, r), tabindex: "0" });
      const lbl = monthly ? new Date(k + "-01T00:00:00Z").toLocaleDateString("en-US", { month: "short", year: "numeric", timeZone: "UTC" }) : `Week of ${fmtDate(k)}`;
      const show = (ev) => showTip(ev, [`${fmtInt(val)} actions`, lbl]);
      path.addEventListener("pointermove", show); path.addEventListener("focus", show);
      path.addEventListener("pointerleave", hideTip); path.addEventListener("blur", hideTip);
      svg.append(path);
      // x labels: every Nth
      const every = Math.max(1, Math.round(keys.length / 6));
      if (i % every === 0) {
        const t = ns("text", { x: x + barW / 2, y: H - 8, "text-anchor": "middle" });
        t.textContent = monthly ? new Date(k + "-01T00:00:00Z").toLocaleDateString("en-US", { month: "short", timeZone: "UTC" }) : new Date(k + "T00:00:00Z").toLocaleDateString("en-US", { month: "short", day: "numeric", timeZone: "UTC" });
        svg.append(t);
      }
    });
    wrap.replaceChildren(svg);
    const tbl = el("table", { class: "tv" }, el("thead", null, el("tr", null, el("th", { text: monthly ? "Month" : "Week of" }), el("th", { class: "num", text: "Actions" }))),
      el("tbody", null, keys.map((k, i) => el("tr", null, el("td", { text: monthly ? k : fmtDate(k) }), el("td", { class: "num", text: fmtInt(values[i]) })))));
    $("activity-table").replaceChildren(el("div", { class: "tv-wrap", style: "max-height: 220px; overflow: auto" }, tbl));
  }
  function roundedTop(x, y, w, h, r) {
    if (h <= 0) return "";
    if (r <= 0) return `M${x},${y}h${w}v${h}h${-w}Z`;
    return `M${x},${y + r}a${r},${r} 0 0 1 ${r},${-r}h${w - 2 * r}a${r},${r} 0 0 1 ${r},${r}v${h - r}h${-w}Z`;
  }
  function niceTicks(max) {
    const step = Math.pow(10, Math.floor(Math.log10(max || 1)));
    const cands = [step, step * 2, step * 5, step * 10].find(s => max / s <= 5) || step;
    const out = []; for (let t = 0; t <= max; t += cands) out.push(t);
    return out.length > 1 ? out : [0, max];
  }

  // ------------------------------------------------------------------ tooltip
  function showTip(ev, lines) {
    const tip = $("tip");
    tip.replaceChildren(el("b", { text: lines[0] }), ...lines.slice(1).map(l => el("div", { text: l })));
    tip.hidden = false;
    let x = 12, y = 12;
    if (ev && typeof ev.clientX === "number" && ev.clientX) { x = ev.clientX + 12; y = ev.clientY + 12; }
    else if (ev && ev.target && ev.target.getBoundingClientRect) { const r = ev.target.getBoundingClientRect(); x = r.left; y = r.bottom + 6; }
    const vw = window.innerWidth, vh = window.innerHeight;
    tip.style.left = Math.min(x, vw - tip.offsetWidth - 8) + "px";
    tip.style.top = Math.min(y, vh - tip.offsetHeight - 8) + "px";
  }
  function hideTip() { $("tip").hidden = true; }

  // ------------------------------------------------------------------ story leads
  const LEAD_ORDER = ["upcoming_events", "recent_activity", "vetoes", "close_votes", "party_line_votes", "died_in_other_chamber", "parked", "effective_soon", "most_roll_calls", "top_prime_sponsors", "attendance", "party_breakers"];
  const NO_BILL = new Set(["top_prime_sponsors", "attendance", "party_breakers"]);
  function renderLeads() {
    const leads = state.payload.story_leads || {};
    const tabs = $("lead-tabs"); const list = $("lead-list");
    const keys = LEAD_ORDER.filter(k => leads[k]);
    if (!keys.length) { tabs.replaceChildren(); list.replaceChildren(el("li", { class: "empty", text: "No story leads in this dataset." })); return; }
    if (!state.leadTab || !leads[state.leadTab]) state.leadTab = keys[0];
    const inView = new Set(state.view.map(b => b.bill_id));
    const rowsOf = (k) => leadRows(k, leads[k]).filter(r => !r.bill || inView.has(r.bill.replace(/\s+/g, "")) || NO_BILL.has(k));
    tabs.replaceChildren(...keys.map(k => {
      const rows = rowsOf(k);
      return el("button", { class: "tab", role: "tab", type: "button", "aria-selected": String(k === state.leadTab), onClick: () => { state.leadTab = k; renderLeads(); } },
        leads[k].title, el("span", { class: "n", text: fmtInt(rows.length) }));
    }));
    const lead = leads[state.leadTab];
    $("leads-why").textContent = lead.why || "";
    const rows = rowsOf(state.leadTab);
    if (!rows.length) { list.replaceChildren(el("li", { class: "empty", text: "Nothing in this category for the current filters." })); return; }
    list.replaceChildren(...rows.slice(0, 120).map(r => el("li", null,
      el("button", { type: "button", onClick: () => r.onClick ? r.onClick() : openBill(state.byLabel.get(r.bill.replace(/\s+/g, ""))) },
        el("span", { class: "bill", text: r.left }),
        el("span", { class: "t", text: r.title }),
        el("span", { class: "d" }, ...r.detail)))));
  }
  function leadRows(kind, lead) {
    const b = (x) => el("b", { text: x });
    switch (kind) {
      case "vetoes": return (lead.bills || []).map(x => {
        const v = x.veto || {}; const hv = v.house ? `House ${v.house.vote} ${v.house.result}` : ""; const sv = v.senate ? `Senate ${v.senate.vote} ${v.senate.result}` : "";
        return { bill: x.bill, left: x.bill, title: x.title, detail: [b(x.outcome), v.veto_date ? ` · vetoed ${fmtDate(v.veto_date)}` : "", hv ? ` · ${hv}` : "", sv ? ` · ${sv}` : ""] };
      });
      case "upcoming_events": return (lead.bills || []).map(x => ({ bill: x.bill, left: x.bill, title: x.title, detail: [b(`${fmtDate(x.next.date)} · ${x.next.kind}`), ` · ${x.next.text}`, ` · now: ${x.status}`] }));
      case "party_line_votes": return (lead.votes || []).map(x => ({ bill: x.bill, left: x.bill, title: x.title, detail: [b(`${x.chamber} ${x.yeas}–${x.nays}`), ` · ${splitText(x.party_split)} · ${fmtDate(x.date)} · ${x.motion}`] }));
      case "attendance": return (lead.legislators || []).map(x => ({ bill: null, left: `${x.not_voting} missed`, title: `${x.name} (${x.party}${x.district ? ", " + (x.chamber === "Senate" ? "Dist. " : (x.county ? x.county + " " : "")) + x.district : ""}) · ${x.chamber}`, detail: [b(`${x.not_voting_pct}% of ${x.roll_calls} roll calls not voting, not excused`), x.excused ? ` · ${x.excused} excused` : ""], onClick: () => searchFor(x.name) }));
      case "party_breakers": return (lead.legislators || []).map(x => ({ bill: null, left: `${x.against_party_pct}%`, title: `${x.name} (${x.party}${x.district ? ", " + (x.chamber === "Senate" ? "Dist. " : (x.county ? x.county + " " : "")) + x.district : ""}) · ${x.chamber}`, detail: [b(`${x.against_party} of ${x.party_votes} votes against the caucus majority`)], onClick: () => searchFor(x.name) }));
      case "close_votes": return (lead.votes || []).map(x => ({ bill: x.bill, left: x.bill, title: x.title, detail: [b(`${x.chamber} ${x.yeas}–${x.nays}`), ` (margin ${x.margin}) · ${splitText(x.party_split)} · ${fmtDate(x.date)} · ${x.motion} · now: ${x.status}`] }));
      case "parked": return (lead.bills || []).map(x => ({ bill: x.bill, left: x.bill, title: x.title, detail: [b(x.how), ` · ${fmtDate(x.date)}`, x.committee ? ` · ${x.committee}` : ""] }));
      case "effective_soon": return (lead.bills || []).map(x => ({ bill: x.bill, left: x.bill, title: x.title, detail: [b(`Effective ${fmtDate(x.effective)}`), x.chapter ? ` · Chapter ${x.chapter}` : ""] }));
      case "most_roll_calls": return (lead.bills || []).map(x => ({ bill: x.bill, left: x.bill, title: x.title, detail: [b(`${x.roll_calls} roll calls`), ` · ${x.status}`] }));
      case "died_in_other_chamber": return (lead.bills || []).map(x => ({ bill: x.bill, left: x.bill, title: x.title, detail: [b(`Passed ${x.origin}, ${x.how.toLowerCase()} in ${x.died_in}`), ` · ${fmtDate(x.date)}`] }));
      case "recent_activity": return (lead.bills || []).map(x => ({ bill: x.bill, left: x.bill, title: x.title, detail: [b(fmtDate(x.date)), ` · ${x.last_action}`] }));
      case "top_prime_sponsors": return (lead.sponsors || []).map(x => ({ bill: null, left: `${x.bills} bills`, title: `${x.name}${x.party ? " (" + x.party + ")" : ""}`, detail: [b(`${x.laws} became law`), ` · ${x.killed} killed`], onClick: () => searchFor(x.name) }));
      default: return [];
    }
  }
  function searchFor(text) { $("f-q").value = text; state.filters.q = text; state.shown = PAGE; apply(); window.scrollTo({ top: $("table-section").offsetTop - 120, behavior: "smooth" }); }
  function splitText(ps) {
    if (!ps) return "";
    return ["R", "D", "I"].filter(p => ps[p]).map(p => `${p} ${ps[p].yea}–${ps[p].nay}`).join(", ");
  }

  // ------------------------------------------------------------------ table
  function renderTable() {
    const body = $("bills-body");
    const rows = state.view.slice(0, state.shown);
    body.replaceChildren(...rows.map(b => el("tr", null,
      el("td", { class: "bill" }, el("button", { type: "button", text: b.bill_label || b.lsr_id, onClick: (e) => { state.lastFocus = e.currentTarget; openBill(b); } })),
      el("td", { class: "title" }, b.title || el("span", { class: "muted", text: "(title not in the current data dump)" }), b.subject ? el("span", { class: "subj", text: b.subject }) : null),
      el("td", { text: b.prime_sponsor || "" }),
      el("td", { text: b.committee || "" }),
      el("td", null, pill(b)),
      el("td", { class: "last" }, el("time", { datetime: b.last_action_date, text: fmtDate(b.last_action_date) }), b.last_action, (b.next_events || []).length ? el("span", { class: "next", text: `Next: ${fmtDate(b.next_events[0].date)} ${b.next_events[0].kind}` }) : null),
      el("td", { class: "num", text: b.n_roll_calls ? fmtInt(b.n_roll_calls) : "" }),
      el("td", { class: "num", text: b.closest_margin === null || b.closest_margin === undefined ? "" : fmtInt(b.closest_margin) }),
    )));
    $("table-title").textContent = `${state.session} bills`;
    const more = $("more");
    more.replaceChildren();
    if (state.view.length > state.shown) more.append(el("button", { class: "btn", type: "button", text: `Show ${fmtInt(Math.min(PAGE, state.view.length - state.shown))} more (${fmtInt(state.view.length - state.shown)} remaining)`, onClick: () => { state.shown += PAGE; renderTable(); } }));
  }
  function pill(b) { return el("span", { class: `pill g-${b.group}`, title: b.status_label }, el("i", { "aria-hidden": "true" }), b.status_label); }

  // ------------------------------------------------------------------ drawer
  function openBill(b) {
    if (!b) return;
    const d = $("drawer");
    const hooks = hooksFor(b);
    const lawBadge = b.chapter ? el("span", { class: "badge", text: `Chapter ${b.chapter}` }) : null;
    const eff = (b.effective_dates || []).length ? el("span", { class: "badge", text: `Effective ${b.effective_dates.map(fmtDate).join(", ")}` }) : null;
    d.replaceChildren(
      el("div", { class: "drawer-head" },
        el("div", null, el("div", { class: "id", text: `${b.bill_label || "No bill number"} · LSR ${b.lsr_id} · ${b.session} session` })),
        el("button", { class: "btn small", type: "button", id: "drawer-close", text: "Close", onClick: () => closeDrawer(true) })),
      el("h2", { id: "drawer-title", text: b.title || "(title not in the current data dump)" }),
      b.title_note ? el("div", { class: "why", text: `Title note from the General Court: ${b.title_note}` }) : null,
      el("div", { class: "badges" }, el("span", { class: "badge", text: b.bill_type }), el("span", { class: "badge", text: `${b.origin_chamber} bill` }), pill(b), lawBadge, eff,
        b.subject ? el("span", { class: "badge", text: `Subject: ${b.subject}${b.subject_code && b.subject !== b.subject_code ? " (" + b.subject_code + ")" : ""}` }) : null,
        b.bipartisan ? el("span", { class: "badge", text: "Bipartisan sponsors" }) : null,
        b.status === "unknown" ? el("span", { class: "badge warn", text: "No final action recorded; read the docket" }) : null),
      el("dl", { class: "kv" },
          kv("Prime sponsor", b.prime_sponsor ? `${b.prime_sponsor}${b.prime_party ? " (" + b.prime_party + ")" : ""}` : "not in data"),
          kv("Committees", [...(b.committees && b.committees.house || []).map(c => "House: " + c), ...(b.committees && b.committees.senate || []).map(c => "Senate: " + c)].join(" · ") || (b.committee || "not found")),
          kv("Decisive action", (b.status_detail && b.status_detail.decisive_action) || b.last_action || ""),
          kv("First action", fmtDate(b.first_action_date)),
          kv("Last action", `${fmtDate(b.last_action_date)} · ${b.last_action}`),
          kv("Status codes", b.status_codes && (b.status_codes.general || b.status_codes.house || b.status_codes.senate) ? `general ${b.status_codes.general || "–"} · House ${b.status_codes.house || "–"} · Senate ${b.status_codes.senate || "–"} (General Court codes, undocumented)` : "not in data"),
          kv("Beats", (b.beats || []).join(", ") || "none matched")),
      (b.next_events || []).length ? section("Scheduled from today forward", el("ol", { class: "docket" }, b.next_events.map(e => el("li", null, el("time", { datetime: e.date, text: fmtDate(e.date) }), el("span", { class: "ch", text: e.kind }), el("span", { class: "tx", text: e.text }))))) : null,
      vetoSection(b),
      section("Sponsors", (b.sponsors || []).length ? el("div", { class: "sponsors" }, b.sponsors.map(s => el("span", { class: `sp${s.primary ? " prime" : ""}`, text: `${s.primary ? "Prime · " : ""}${who(s)}` }))) : el("div", { class: "empty", text: "No sponsor rows in the data dump for this LSR." })),
      section(`Docket (${fmtInt((b.actions || []).length)} actions)`, (b.actions || []).length ? el("ol", { class: "docket" }, b.actions.map(a => el("li", null, el("time", { datetime: a.date, text: fmtDate(a.date) }), el("span", { class: "ch", text: a.chamber }), el("span", { class: "tx", text: a.text })))) : el("div", { class: "empty", text: "No docket actions recorded." })),
      section(`Roll calls (${fmtInt((b.roll_calls || []).length)})`, (b.roll_calls || []).length ? el("div", null, b.roll_calls.map(rollCall)) : el("div", { class: "empty", text: "No recorded roll calls. Voice and division votes are not in the roll-call file." })),
      section("Everything on the web about this bill", linkHub(b)),
      hooks.length ? section("Why this bill is in the story leads", el("ul", { class: "hooks" }, hooks.map(h => el("li", { text: h })))) : null,
      el("div", { class: "note", text: "Outcome labels are rule-based readings of the docket text; the \"decisive action\" line above is the docket entry the label came from. Confirm against the docket and the bill page before publishing." }),
      el("div", { style: "margin-top: 14px; display: flex; gap: 8px; flex-wrap: wrap" },
        el("button", { class: "btn small", type: "button", text: "Copy link to this bill", onClick: copyLink }),
        el("button", { class: "btn small", type: "button", text: "Copy citation", onClick: (e) => copyText(e, `${b.bill_label}, ${b.title} (${b.session} N.H. General Court), ${b.status_label.toLowerCase()}; last docket action ${fmtDate(b.last_action_date)}: ${b.last_action}. Source: gc.nh.gov bill status.`) })),
    );
    $("scrim").hidden = false; d.hidden = false;
    if (b.bill_id && location.hash !== "#" + b.bill_id) { try { history.replaceState(null, "", "#" + b.bill_id); } catch { /* srcdoc frames refuse */ } }
    if (b.bill_id && window.parent !== window) { try { window.parent.postMessage({ nhbt: "hash", hash: "#" + b.bill_id }, "*"); } catch { /* ignore */ } }
    document.body.style.overflow = "hidden";
    $("drawer-close").focus();
  }
  function closeDrawer(clearHash) {
    const d = $("drawer");
    if (d.hidden) return;
    d.hidden = true; $("scrim").hidden = true; document.body.style.overflow = "";
    if (clearHash && location.hash) { try { history.replaceState(null, "", location.pathname + location.search); } catch { /* srcdoc frames refuse */ } }
    if (clearHash && window.parent !== window) { try { window.parent.postMessage({ nhbt: "hash", hash: "" }, "*"); } catch { /* ignore */ } }
    if (state.lastFocus) { try { state.lastFocus.focus(); } catch { /* gone */ } }
  }
  function kv(k, v) { return [el("dt", { text: k }), el("dd", { text: v })]; }
  function vetoSection(b) {
    const v = b.status_detail && b.status_detail.veto;
    if (!v) return null;
    const rows = [];
    rows.push(el("li", null, el("time", { datetime: v.veto_date, text: fmtDate(v.veto_date) }), el("span", { class: "ch", text: "Governor" }), el("span", { class: "tx", text: "Vetoed" })));
    for (const side of ["house", "senate"]) {
      const r = v[side]; if (!r) continue;
      rows.push(el("li", null, el("time", { datetime: r.date, text: fmtDate(r.date) }), el("span", { class: "ch", text: side === "house" ? "House" : "Senate" }), el("span", { class: "tx", text: `Veto ${r.result}${r.vote ? " · roll call " + r.vote : ""}` })));
    }
    return section("Veto record", el("ol", { class: "docket" }, rows), el("div", { class: "why", text: "An override needs two-thirds in both chambers. A veto overridden in one chamber and sustained in the other stands." }));
  }
  function section(title, ...children) { return el("section", null, el("h3", { text: title }), ...children); }
  function rollCall(v) {
    const total = (v.yeas || 0) + (v.nays || 0);
    const margin = Math.abs((v.yeas || 0) - (v.nays || 0));
    const close = total && margin <= (v.body === "S" ? 3 : 12);
    return el("div", { class: `rc${close ? " close" : ""}` },
      el("div", { class: "rc-head" }, el("span", null, el("b", { text: `${v.chamber} roll call #${v.vote_num}` }), ` · ${fmtDate(v.date)}`), close ? el("span", { class: "badge warn", text: `Close vote: margin ${margin}` }) : null),
      el("div", { class: "motion", text: v.motion }),
      v.party_split && Object.keys(v.party_split).length ? el("div", { class: "motion", text: `By party: ${splitText(v.party_split)}${v.party_line ? " · party-line vote" : ""}` }) : null,
      el("div", { class: "tally", role: "img", "aria-label": `${v.yeas} yeas, ${v.nays} nays` }, el("div", { class: "y", style: `flex: ${v.yeas || 0} ${v.yeas || 0} 0` }), el("div", { class: "n", style: `flex: ${v.nays || 0} ${v.nays || 0} 0` })),
      el("div", { class: "nums" }, el("span", null, el("b", { text: fmtInt(v.yeas) }), " yeas"), el("span", null, el("b", { text: fmtInt(v.nays) }), " nays"), v.not_voting ? el("span", null, el("b", { text: fmtInt(v.not_voting) }), " not voting") : null, v.excused ? el("span", null, el("b", { text: fmtInt(v.excused) }), " excused") : null));
  }
  // Every link is a documented URL pattern filled with the bill's identifiers (see docs/METHODOLOGY.md).
  function buildLinks(b) {
    const s = b.session, bid = b.bill_id, label = b.bill_label || b.lsr_id;
    const q = encodeURIComponent(`"${label}" New Hampshire`), q2 = encodeURIComponent(label);
    const L = [];
    if (b.doc_id) {
      L.push({ kind: "official", label: "Bill status page (gc.nh.gov)", url: `https://gc.nh.gov/bill_Status/billinfo.aspx?id=${b.doc_id}&inflect=2` });
      L.push({ kind: "official", label: "Bill text, current version (PDF)", url: `https://gc.nh.gov/bill_Status/pdf.aspx?id=${b.doc_id}&q=billVersion` });
      L.push({ kind: "official", label: "Bill text (HTML, legacy viewer)", url: `https://gc.nh.gov/bill_status/legacy/bs2016/billText.aspx?sy=${s}&id=${b.doc_id}&txtFormat=html` });
    }
    L.push({ kind: "official", label: "Docket (legacy viewer)", url: `https://gc.nh.gov/bill_status/legacy/bs2016/bill_docket.aspx?lsr=${encodeURIComponent(b.lsr)}&sy=${s}&sortoption=&txtsessionyear=${s}` });
    L.push({ kind: "official", label: "Bill status search (gc.nh.gov)", url: "https://gc.nh.gov/bill_Status/advanced.aspx" });
    L.push({ kind: "official", label: "Governor's newsroom (veto messages, signings)", url: "https://www.governor.nh.gov/news-and-media" });
    if (bid) {
      L.push({ kind: "trackers", label: "LegiScan", url: `https://legiscan.com/NH/bill/${bid}/${s}` });
      L.push({ kind: "trackers", label: "Plural (Open States)", url: `https://open.pluralpolicy.com/nh/bills/${s}/${bid}/` });
    }
    L.push({ kind: "news", label: "Google News search", url: `https://news.google.com/search?q=${q}` });
    L.push({ kind: "news", label: "Google web search", url: `https://www.google.com/search?q=${q}` });
    L.push({ kind: "news", label: "DuckDuckGo search", url: `https://duckduckgo.com/?q=${q}` });
    L.push({ kind: "news", label: "New Hampshire Bulletin search", url: `https://newhampshirebulletin.com/?s=${q2}` });
    L.push({ kind: "news", label: "InDepthNH search", url: `https://indepthnh.org/?s=${q2}` });
    L.push({ kind: "news", label: "NHPR search", url: `https://www.nhpr.org/search?q=${q2}` });
    L.push({ kind: "news", label: "Granite State Report search", url: `https://granitestatereport.com/?s=${q2}` });
    return L;
  }
  function linkHub(b) {
    const kinds = [["official", "Official record (gc.nh.gov and the Governor)"], ["trackers", "Bill trackers"], ["news", "News and web searches"]];
    const wrap = el("div", { class: "links" });
    const links = buildLinks(b);
    kinds.forEach(([k, title]) => {
      const ls = links.filter(l => l.kind === k);
      if (!ls.length) return;
      wrap.append(el("h4", { text: title }), ...ls.map(l => el("a", { href: l.url, target: "_blank", rel: "noopener", text: l.label })));
    });
    if (!b.doc_id) wrap.append(el("div", { class: "why", style: "grid-column: 1 / -1", text: "No bill-page document id in the dump for this LSR (common for bills carried over from the prior year). The docket link works from the LSR number." }));
    return wrap;
  }
  function hooksFor(b) {
    const leads = state.payload.story_leads || {}; const out = [];
    const id = b.bill_label;
    for (const k of LEAD_ORDER) {
      const L = leads[k]; if (!L) continue;
      const arr = L.bills || L.votes || [];
      const hits = arr.filter(x => x.bill === id);
      if (hits.length) out.push(`${L.title}: ${L.why}`);
    }
    return out;
  }
  function copyLink(e) {
    // When embedded, a <meta name="canonical-base"> names the public page the link should point at.
    const canon = document.querySelector('meta[name="canonical-base"]');
    const base = canon && canon.content ? canon.content : location.origin + location.pathname + location.search;
    copyText(e, base + location.hash);
  }
  function copyText(e, text) {
    const btn = e.currentTarget; const old = btn.textContent;
    const done = (ok) => { btn.textContent = ok ? "Copied" : "Select and copy: " + text; setTimeout(() => (btn.textContent = old), ok ? 1500 : 6000); };
    if (navigator.clipboard && navigator.clipboard.writeText) navigator.clipboard.writeText(text).then(() => done(true), () => done(false));
    else done(false);
  }

  boot();
})();
