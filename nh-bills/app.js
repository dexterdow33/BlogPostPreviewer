/* NH Bill Tracker - Granite State Report
   Vanilla JS, no build step. Reads data/index.json, data/legislators.json and
   data/nh_bills_<session>.json from scripts/fetch_nh_bills.py.
   All text goes in with textContent.

   Embedded on granitestatereport.com in an <iframe srcdoc>, the page reports
   its height to the host (so the iframe grows and the host page scrolls),
   asks the host to scroll when a bill opens, and trades #hash deep links. The
   host's "hello" asks for the current height and readiness again. */
(() => {
  "use strict";

  // ------------------------------------------------------------------ config
  // Order matters: this is the validated color order of the outcome bar.
  const GROUPS = [
    { key: "law",     label: "Became law",       codes: ["law", "veto_overridden"] },
    { key: "process", label: "Still in process", codes: ["enrolled", "conference", "passed_chamber", "committee_report", "recommitted", "hearing", "in_committee", "unknown"] },
    { key: "parked",  label: "Parked",           codes: ["interim_study", "retained", "rereferred", "tabled"] },
    { key: "killed",  label: "Killed",           codes: ["killed", "died_on_table", "conference_failed", "nonconcurred", "returned_to_house"] },
    { key: "vetoed",  label: "Vetoed",           codes: ["vetoed", "veto_sustained"] },
  ];
  const GROUP_OF = {};
  GROUPS.forEach(g => g.codes.forEach(c => (GROUP_OF[c] = g.key)));
  const GROUP_LABEL = Object.fromEntries(GROUPS.map(g => [g.key, g.label]));
  const SHORT = {
    law: "Became law", veto_overridden: "Law over veto", veto_sustained: "Veto stood", vetoed: "Vetoed",
    enrolled: "Enrolled", conference: "In conference", conference_failed: "Died in conference", recommitted: "Recommitted",
    nonconcurred: "Died on nonconcurrence", returned_to_house: "Returned to House", died_on_table: "Died on table",
    interim_study: "Interim study", retained: "Retained", rereferred: "Re-referred", tabled: "Tabled", killed: "Killed",
    passed_chamber: "Passed a chamber", committee_report: "Committee reported", hearing: "Hearing set",
    in_committee: "In committee", unknown: "No final action",
  };
  const PAGE = 25;
  const EMBED = window.parent !== window;
  if (EMBED) document.documentElement.classList.add("embed");

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
        else if (k.startsWith("on") && typeof v === "function") node.addEventListener(k.slice(2).toLowerCase(), v);
        else node.setAttribute(k, v === true ? "" : String(v));
      }
    }
    for (const c of children.flat(Infinity)) {
      if (c === null || c === undefined || c === false || c === "") continue;
      node.append(c instanceof Node ? c : document.createTextNode(String(c)));
    }
    return node;
  }
  const svg = (tag, attrs) => { const n = document.createElementNS("http://www.w3.org/2000/svg", tag); for (const [k, v] of Object.entries(attrs || {})) n.setAttribute(k, v); return n; };
  const fmtInt = (n) => (n === null || n === undefined ? "" : Number(n).toLocaleString("en-US"));
  const cap = (s) => (s ? s.charAt(0).toUpperCase() + s.slice(1) : "");
  function fmtDate(iso, short) {
    const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(iso || "");
    if (!m) return iso || "";
    const d = new Date(Date.UTC(+m[1], +m[2] - 1, +m[3]));
    return d.toLocaleDateString("en-US", short ? { month: "short", day: "numeric", timeZone: "UTC" } : { year: "numeric", month: "short", day: "numeric", timeZone: "UTC" });
  }
  function fmtStamp(iso) {
    const d = new Date(iso);
    if (isNaN(d)) return iso || "";
    return d.toLocaleString("en-US", { month: "long", day: "numeric", year: "numeric", hour: "numeric", minute: "2-digit", timeZone: "America/New_York" }) + " ET";
  }
  const store = {
    get(k) { try { return localStorage.getItem(k); } catch { return null; } },
    set(k, v) { try { localStorage.setItem(k, v); } catch { /* per-viewer convenience only */ } },
  };
  async function loadJSON(name) {
    let lastErr;
    for (const b of BASES) {
      try {
        const r = await fetch(b + name, { cache: "no-cache" });
        if (r.ok) return await r.json();
        lastErr = new Error(`${r.status} for ${b}${name}`);
      } catch (e) { lastErr = e; }
    }
    throw lastErr || new Error("Could not load " + name);
  }
  const debounce = (fn, ms) => { let t; return (...a) => { clearTimeout(t); t = setTimeout(() => fn(...a), ms); }; };
  const billKey = (b) => (b.bill_id || ("LSR" + b.lsr_id)).replace(/[^A-Za-z0-9]/g, "");

  // ------------------------------------------------------------------ host bridge
  let lastH = 0, lastActW = 0;
  // Redraw the weekly chart when its width changes enough to matter (phone rotation).
  window.addEventListener("resize", debounce(() => {
    const g = document.querySelector(".glance");
    if (state.bills && state.bills.length && g && Math.abs(Math.min(760, g.clientWidth) - lastActW) > 24) { renderActivity(); postHeight(); }
  }, 150));
  function postHeight() {
    if (!EMBED) return;
    const h = Math.ceil(document.body.getBoundingClientRect().height);
    if (Math.abs(h - lastH) > 1) { lastH = h; try { parent.postMessage({ nhbt: "height", h }, "*"); } catch { /* ignore */ } }
  }
  if (EMBED && "ResizeObserver" in window) new ResizeObserver(postHeight).observe(document.body);
  // Handshake: on a heavy host page the tracker can finish drawing before the
  // host's listener exists, so the host says "hello" once it listens and the
  // tracker answers with its current height and, once booted, "ready".
  let booted = false;
  if (EMBED) window.addEventListener("message", (ev) => {
    if (ev.source !== parent || !ev.data || ev.data.nhbt !== "hello") return;
    lastH = 0; postHeight();
    if (booted) { try { parent.postMessage({ nhbt: "ready" }, "*"); } catch { /* ignore */ } }
  });
  function reveal(node) {
    if (!node) return;
    const y = node.getBoundingClientRect().top + window.scrollY;
    if (EMBED) { postHeight(); try { parent.postMessage({ nhbt: "scroll", y }, "*"); } catch { /* ignore */ } }
    else window.scrollTo({ top: Math.max(0, y - 16), behavior: matchMedia("(prefers-reduced-motion: reduce)").matches ? "auto" : "smooth" });
  }
  function setHash(h) {
    try { history.replaceState(null, "", location.pathname + location.search + h); } catch { /* srcdoc frames refuse */ }
    if (EMBED) { try { parent.postMessage({ nhbt: "hash", hash: h }, "*"); } catch { /* ignore */ } }
  }

  // ------------------------------------------------------------------ state
  const state = {
    index: null, payload: null, session: null, bills: [], view: [], byKey: new Map(), roster: null,
    shown: PAGE, openKey: null, leadTab: null, leadAll: false,
    filters: { q: "", chamber: "", group: "", beat: "", subject: "", sort: "number", rc: false },
  };

  // ------------------------------------------------------------------ boot
  async function boot() {
    wireControls();
    try {
      state.index = await loadJSON("index.json");
    } catch (e) {
      $("loading").textContent = "The bill data could not be loaded. Try again in a minute. Details: " + e.message;
      $("loading").classList.add("err");
      postHeight();
      return;
    }
    try { state.roster = (await loadJSON("legislators.json")).roster || null; } catch { state.roster = null; }
    const sessions = (state.index.sessions || []).slice().sort((a, b) => String(a.session).localeCompare(String(b.session)));
    if (!sessions.length) { $("loading").textContent = "The nightly refresh has not produced any session data yet."; return; }
    const sel = $("f-session");
    sessions.forEach(s => sel.append(el("option", { value: s.session, text: `${s.session} session` })));
    const full = sessions.filter(s => s.with_title === undefined || s.with_title > 0);
    const remembered = store.get("nhbt.session");
    const def = (remembered && sessions.some(s => String(s.session) === remembered)) ? remembered : String((full.length ? full : sessions).slice(-1)[0].session);
    sel.value = def;
    await loadSession(def);
    const target = keyFromHash(location.hash);
    if (target) openByKey(target, true);
    window.addEventListener("hashchange", () => { const k = keyFromHash(location.hash); if (k) openByKey(k, true); });
    window.addEventListener("message", (ev) => {
      const d = ev.data || {};
      if (d.nhbt === "open" && typeof d.hash === "string") { const k = keyFromHash(d.hash); if (k) openByKey(k, true); }
    });
    booted = true;
    if (EMBED) { try { parent.postMessage({ nhbt: "ready" }, "*"); } catch { /* ignore */ } }
  }
  const keyFromHash = (h) => { const m = /^#([A-Za-z]{2,5}\d{1,5})$/.exec(h || ""); return m ? m[1].toUpperCase() : null; };

  async function loadSession(session) {
    $("loading").hidden = false;
    $("loading").classList.remove("err");
    $("loading").textContent = `Loading the ${session} session…`;
    const s = (state.index.sessions || []).find(x => String(x.session) === String(session));
    try {
      state.payload = await loadJSON(s ? s.file : `nh_bills_${session}.json`);
    } catch (e) {
      $("loading").textContent = "This session could not be loaded. Details: " + e.message;
      $("loading").classList.add("err");
      return;
    }
    state.session = String(session);
    store.set("nhbt.session", state.session);
    state.bills = state.payload.bills || [];
    state.byKey = new Map();
    for (const b of state.bills) { b.group = b.group || GROUP_OF[b.status] || "process"; state.byKey.set(billKey(b), b); }
    fillSelect($("f-beat"), "All topics", Object.entries((state.payload.story_leads && state.payload.story_leads.beats && state.payload.story_leads.beats.counts) || {}).map(([k, n]) => [k, `${k} (${fmtInt(n)})`]), "beat");
    const subjCounts = {};
    state.bills.forEach(b => { if (b.subject_code) subjCounts[b.subject_code] = (subjCounts[b.subject_code] || 0) + 1; });
    fillSelect($("f-subject"), "All subjects", Object.entries(state.payload.subject_codes || {}).sort((a, b) => (subjCounts[b[0]] || 0) - (subjCounts[a[0]] || 0)).map(([c, l]) => [c, `${l}${l !== c ? " (" + c + ")" : ""} · ${fmtInt(subjCounts[c] || 0)}`]), "subject");
    const note = $("session-note");
    note.hidden = !state.payload.session_note;
    note.textContent = state.payload.session_note || "";
    $("glance-h").textContent = `The ${state.session} session at a glance`;
    // Show when the General Court's files were pulled, not when this copy was
    // rebuilt: a daytime rebuild reads files saved at the last nightly pull.
    const pulled = state.payload.fetched_at || (state.index && state.index.fetched_at);
    $("stamp").textContent = pulled
      ? `Data pulled from the New Hampshire General Court ${fmtStamp(pulled)}.`
      : `Data from the New Hampshire General Court's last nightly pull. This copy was built ${fmtStamp(state.payload.generated_at)}.`;
    const src = $("src-note"); if (src) src.textContent = `This copy was built ${fmtStamp(state.payload.generated_at)}${pulled ? ` from files pulled ${fmtStamp(pulled)}` : ""}.`;
    $("loading").hidden = true;
    ["summary", "figures", "outcome-bar", "activity"].forEach(id => ($(id).hidden = false));
    $("leads").hidden = false; $("finder").hidden = false;
    state.shown = PAGE; state.openKey = null; state.leadAll = false;
    renderGlance();
    renderActivity();
    apply();
  }
  function fillSelect(sel, allLabel, pairs, key) {
    const keep = state.filters[key];
    sel.replaceChildren(el("option", { value: "", text: allLabel }), ...pairs.map(([v, t]) => el("option", { value: v, text: t })));
    sel.value = pairs.some(([v]) => v === keep) ? keep : "";
    state.filters[key] = sel.value;
  }

  // ------------------------------------------------------------------ controls
  function wireControls() {
    $("f-session").addEventListener("change", (e) => loadSession(e.target.value));
    $("f-q").addEventListener("input", debounce((e) => { state.filters.q = e.target.value.trim(); resetPaging(); apply(); }, 140));
    $("f-sort").addEventListener("change", (e) => { state.filters.sort = e.target.value; apply(); });
    $("f-chamber").addEventListener("change", (e) => { state.filters.chamber = e.target.value; resetPaging(); apply(); });
    $("f-beat").addEventListener("change", (e) => { state.filters.beat = e.target.value; resetPaging(); apply(); });
    $("f-subject").addEventListener("change", (e) => { state.filters.subject = e.target.value; resetPaging(); apply(); });
    $("f-rc").addEventListener("change", (e) => { state.filters.rc = e.target.checked; resetPaging(); apply(); });
    $("f-reset").addEventListener("click", () => {
      state.filters = { q: "", chamber: "", group: "", beat: "", subject: "", sort: state.filters.sort, rc: false };
      $("f-q").value = ""; $("f-chamber").value = ""; $("f-beat").value = ""; $("f-subject").value = ""; $("f-rc").checked = false;
      resetPaging(); apply();
    });
    $("filters-toggle").addEventListener("click", (e) => {
      const open = $("filters").hidden;
      $("filters").hidden = !open;
      e.currentTarget.setAttribute("aria-expanded", String(open));
      e.currentTarget.textContent = open ? "Fewer filters" : "More filters";
    });
    $("act-toggle").addEventListener("click", (e) => {
      const showTable = $("activity-table").hidden;
      $("activity-table").hidden = !showTable; $("activity-chart").hidden = showTable;
      e.currentTarget.setAttribute("aria-pressed", String(showTable));
      e.currentTarget.textContent = showTable ? "View as chart" : "View as table";
    });
    $("lead-more").addEventListener("click", () => { state.leadAll = !state.leadAll; renderLeads(); });
  }
  function resetPaging() { state.shown = PAGE; state.openKey = null; }
  function setGroup(g, scroll) {
    state.filters.group = state.filters.group === g ? "" : g;
    resetPaging(); apply();
    if (scroll) reveal($("finder"));
  }

  // ------------------------------------------------------------------ filtering
  function matches(b, f, skipGroup) {
    if (f.chamber && b.origin_chamber !== f.chamber) return false;
    if (!skipGroup && f.group && b.group !== f.group) return false;
    if (f.beat && !(b.beats || []).includes(f.beat)) return false;
    if (f.subject && b.subject_code !== f.subject) return false;
    if (f.rc && !b.n_roll_calls) return false;
    if (f.q) {
      const q = f.q.toLowerCase();
      const qBill = f.q.replace(/\s+/g, "").toUpperCase();
      if (b.bill_id && b.bill_id === qBill) return true;
      if (b.bill_id && /^[A-Z]+\d+$/.test(qBill) && b.bill_id.startsWith(qBill)) return true;
      const hay = `${b.title} ${b.prime_sponsor} ${b.committee || ""} ${b.lsr_id} ${b.status_label} ${b.subject || ""} ${b.chapter ? "chapter " + b.chapter : ""} ${(b.sponsors || []).map(s => s.name).join(" ")}`.toLowerCase();
      if (!hay.includes(q)) return false;
    }
    return true;
  }
  function apply() {
    const f = state.filters;
    state.view = state.bills.filter(b => matches(b, f, false));
    sortView();
    renderFigurePressed();
    renderChips();
    renderLeads();
    renderList();
    postHeight();
  }
  const billNum = (b) => { const m = /(\d+)/.exec(b.bill_id || ""); return m ? +m[1] : 1e9; };
  function sortView() {
    const s = state.filters.sort, v = state.view;
    const byNum = (a, b) => ((a.bill_id || "ZZZ").replace(/\d+/, "").localeCompare((b.bill_id || "ZZZ").replace(/\d+/, ""))) || billNum(a) - billNum(b);
    if (s === "recent") v.sort((a, b) => (b.last_action_date || "").localeCompare(a.last_action_date || "") || byNum(a, b));
    else if (s === "rollcalls") v.sort((a, b) => (b.n_roll_calls - a.n_roll_calls) || byNum(a, b));
    else if (s === "margin") v.sort((a, b) => ((a.closest_margin ?? 1e9) - (b.closest_margin ?? 1e9)) || byNum(a, b));
    else if (s === "title") v.sort((a, b) => a.title.localeCompare(b.title));
    else v.sort(byNum);
  }

  // ------------------------------------------------------------------ glance
  function groupCounts(list) {
    const c = Object.fromEntries(GROUPS.map(g => [g.key, 0]));
    list.forEach(b => c[b.group]++);
    return c;
  }
  function renderGlance() {
    const all = state.bills, c = groupCounts(all);
    const overrides = all.filter(b => b.status === "veto_overridden").length;
    const upcoming = all.filter(b => (b.next_events || []).length).length;
    const summary = $("summary");
    if (state.payload.session_note) {
      summary.replaceChildren(`The ${state.session} file holds `, el("b", { text: fmtInt(all.length) }), " bills that finished in that session, rebuilt from the docket.");
    } else {
      summary.replaceChildren(
        "Of ", el("b", { text: fmtInt(all.length) }), ` bills and resolutions in the ${state.session} session, `,
        el("b", { text: fmtInt(c.law) }), " became law and ", el("b", { text: fmtInt(c.killed) }), " were killed. ",
        ...(c.vetoed ? [el("b", { text: fmtInt(c.vetoed) }), c.vetoed === 1 ? " veto stood" : " vetoes stood", ...(overrides ? [", and lawmakers overrode ", el("b", { text: fmtInt(overrides) }), " more. "] : [". "])] : []),
        ...(upcoming ? [el("b", { text: fmtInt(upcoming) }), upcoming === 1 ? " bill has committee work on the calendar." : " bills have committee work on the calendar."] : [])
      );
    }
    const subs = {
      law: overrides ? `${fmtInt(overrides)} over a veto` : "signed or enacted",
      process: "no final action in the docket file",
      parked: "interim study or tabled",
      killed: "voted down or died",
      vetoed: "veto stood",
    };
    $("figures").replaceChildren(...GROUPS.map(g => el("button", {
      class: "fig", type: "button", "data-g": g.key, "aria-pressed": "false",
      "aria-label": `${g.label}: ${fmtInt(c[g.key])} bills. Show them.`, onClick: () => setGroup(g.key, true),
    }, el("span", { class: `fig-key k-${g.key}`, "aria-hidden": "true" }), el("span", { class: "fig-n", text: fmtInt(c[g.key]) }), el("span", { class: "fig-l", text: g.label }), el("span", { class: "fig-s", text: subs[g.key] }))));
    const total = all.length || 1;
    const bar = el("div", { class: "bar", role: "img", "aria-label": GROUPS.map(g => `${g.label} ${c[g.key]}`).join(", ") });
    GROUPS.forEach(g => {
      if (!c[g.key]) return;
      const seg = el("div", { class: `seg k-${g.key}`, tabindex: "0", style: `flex:${c[g.key]} ${c[g.key]} 0` });
      const show = (ev) => showTip(ev, [`${fmtInt(c[g.key])} bills`, `${g.label} · ${Math.round(100 * c[g.key] / total)}%`]);
      seg.addEventListener("pointermove", show); seg.addEventListener("focus", show);
      seg.addEventListener("pointerleave", hideTip); seg.addEventListener("blur", hideTip);
      bar.append(seg);
    });
    $("outcome-bar").replaceChildren(bar);
  }
  function renderFigurePressed() {
    document.querySelectorAll(".fig").forEach(n => n.setAttribute("aria-pressed", String(n.dataset.g === state.filters.group)));
  }

  // ------------------------------------------------------------------ activity chart
  function renderActivity() {
    const bins = new Map();
    let min = null, max = null;
    for (const b of state.bills) for (const a of b.actions || []) {
      if (!/^\d{4}-\d{2}-\d{2}$/.test(a.date)) continue;
      if (!min || a.date < min) min = a.date;
      if (!max || a.date > max) max = a.date;
    }
    if (!min) { $("activity").hidden = true; return; }
    const weekOf = (d) => { const dt = new Date(d + "T00:00:00Z"); dt.setUTCDate(dt.getUTCDate() - ((dt.getUTCDay() + 6) % 7)); return dt.toISOString().slice(0, 10); };
    for (const b of state.bills) for (const a of b.actions || []) { if (/^\d{4}-\d{2}-\d{2}$/.test(a.date)) { const k = weekOf(a.date); bins.set(k, (bins.get(k) || 0) + 1); } }
    const keys = []; const end = new Date(max + "T00:00:00Z");
    for (const c = new Date(weekOf(min) + "T00:00:00Z"); c <= end; c.setUTCDate(c.getUTCDate() + 7)) keys.push(c.toISOString().slice(0, 10));
    const vals = keys.map(k => bins.get(k) || 0);
    const peak = Math.max(1, ...vals);
    // Draw at the chart's real width so the 11px labels stay 11px on a phone.
    const W = Math.round(Math.min(760, Math.max(280, document.querySelector(".glance").clientWidth || 760))), H = 96, padT = 16, padB = 20;
    lastActW = W;
    const plotH = H - padT - padB, slot = W / keys.length, bw = Math.max(1.5, Math.min(12, slot - 2));
    const s = svg("svg", { viewBox: `0 0 ${W} ${H}`, class: "act-svg", role: "img", "aria-label": `Docket entries per week, ${fmtDate(min)} to ${fmtDate(max)}. Busiest week: ${fmtInt(peak)} entries.` });
    s.append(svg("line", { class: "axis", x1: 0, x2: W, y1: padT + plotH + .5, y2: padT + plotH + .5 }));
    let lastMonth = "";
    const marks = [];
    keys.forEach((k, i) => {
      const v = vals[i], h = Math.max(v ? 1.5 : 0, (v / peak) * plotH), x = i * slot + (slot - bw) / 2, y = padT + plotH - h;
      if (h > 0) {
        const r = Math.min(2, bw / 2, h);
        const p = svg("path", { class: "col", tabindex: "0", d: `M${x},${y + r}a${r},${r} 0 0 1 ${r},${-r}h${bw - 2 * r}a${r},${r} 0 0 1 ${r},${r}v${h - r}h${-bw}Z` });
        const show = (ev) => showTip(ev, [`${fmtInt(v)} entries`, `Week of ${fmtDate(k)}`]);
        p.addEventListener("pointermove", show); p.addEventListener("focus", show);
        p.addEventListener("pointerleave", hideTip); p.addEventListener("blur", hideTip);
        s.append(p);
      }
      const mo = k.slice(0, 7);
      if (mo !== lastMonth) { lastMonth = mo; marks.push({ x: i * slot, d: new Date(k + "T00:00:00Z") }); }
    });
    // Month labels: every other month on wide screens, fewer on narrow ones, never
    // closer than GAP pixels. The first label carries the year, as does each January.
    const GAP = 46, every = W < 520 ? 3 : 2;
    let cand = marks.filter((m, i) => i === 0 || m.d.getUTCMonth() % every === 0);
    if (cand.length > 1 && cand[1].x - cand[0].x < GAP) cand = cand.slice(1);
    let lastX = -Infinity;
    cand.forEach((m, i) => {
      if (m.x - lastX < GAP || m.x > W - 30) return;
      lastX = m.x;
      const t = svg("text", { x: m.x, y: H - 4 });
      t.textContent = m.d.toLocaleDateString("en-US", { month: "short", year: i === 0 || m.d.getUTCMonth() === 0 ? "2-digit" : undefined, timeZone: "UTC" }).replace(" ", " ’");
      s.append(t);
    });
    const pi = vals.indexOf(peak);
    const pt = svg("text", { x: Math.min(W - 70, pi * slot + slot / 2 + 6), y: 11 }); pt.textContent = `Peak ${fmtInt(peak)}`; s.append(pt);
    $("activity-chart").replaceChildren(s);
    $("activity-table").replaceChildren(el("div", { class: "tv-wrap" }, el("table", { class: "tv" },
      el("thead", null, el("tr", null, el("th", { text: "Week of" }), el("th", { class: "num", text: "Docket entries" }))),
      el("tbody", null, keys.map((k, i) => el("tr", null, el("td", { text: fmtDate(k) }), el("td", { class: "num", text: fmtInt(vals[i]) })))))));
  }

  // ------------------------------------------------------------------ tooltip
  function showTip(ev, lines) {
    const tip = $("tip");
    tip.replaceChildren(el("b", { text: lines[0] }), ...lines.slice(1).map(l => el("div", { text: l })));
    tip.hidden = false;
    let x, y;
    if (ev && ev.clientX) { x = ev.clientX + 14; y = ev.clientY + 14; }
    else { const r = ev.target.getBoundingClientRect(); x = r.left; y = r.bottom + 8; }
    tip.style.left = Math.max(8, Math.min(x, window.innerWidth - tip.offsetWidth - 8)) + "px";
    tip.style.top = Math.max(8, Math.min(y, window.innerHeight - tip.offsetHeight - 8)) + "px";
  }
  function hideTip() { $("tip").hidden = true; }

  // ------------------------------------------------------------------ leads
  const LEADS = [
    ["upcoming_events", "On the calendar"], ["recent_activity", "Moved lately"], ["vetoes", "Vetoes"],
    ["close_votes", "Close votes"], ["party_line_votes", "Party-line votes"], ["died_in_other_chamber", "Died in the other chamber"],
    ["effective_soon", "Taking effect"], ["parked", "Parked"], ["most_roll_calls", "Most contested"],
    ["top_prime_sponsors", "Top filers"], ["attendance", "Missed votes"], ["party_breakers", "Broke with party"],
  ];
  const NO_BILL = new Set(["top_prime_sponsors", "attendance", "party_breakers"]);
  // What each lead list is, in plain words, for the public page. (The data file's own
  // "why" notes are newsroom pitch lines and stay out of the page.) `n` is the length
  // of the list, `lead.total` the full count before the pipeline capped the list.
  const cut = (lead, n, what) => lead.total && lead.total > n ? ` The list shows the ${what} ${fmtInt(n)} of ${fmtInt(lead.total)}.` : "";
  const PUBLIC_WHY = {
    upcoming_events: () => "Committee sessions the docket lists from today forward, soonest first. Most are for bills sent to interim study.",
    recent_activity: (lead, n) => "Bills with a docket entry in the last 45 days, newest first." + cut(lead, n, "latest"),
    vetoes: () => "Every bill vetoed this session and what each chamber did next. An override needs two-thirds in both chambers.",
    close_votes: (lead, n) => "Roll calls decided by 12 votes or fewer in the House, or 3 or fewer in the Senate, closest first." + cut(lead, n, "closest"),
    party_line_votes: (lead, n) => "Roll calls where at least 60 percent of Republicans voted one way and at least 60 percent of Democrats voted the other, newest first." + cut(lead, n, "latest"),
    died_in_other_chamber: () => "Bills that passed the chamber where they started, then were killed or parked in the other chamber.",
    effective_soon: () => "Laws with an effective date from 30 days ago through the next 150 days, soonest first. One law can appear once for each date its sections take effect.",
    parked: () => "Bills sent to interim study, retained, re-referred, or tabled, with no final vote on record.",
    most_roll_calls: () => "The 30 bills with the most recorded roll calls.",
    top_prime_sponsors: () => "The 30 legislators who were prime sponsor on the most bills, with how many became law and how many were killed. Select a name to see those bills.",
    attendance: () => "The 40 members with the most roll calls marked \u201cnot voting, not excused,\u201d the General Court's own label, among members with at least 20 roll calls. A member marked absent on every vote may have resigned or the seat may have been vacant. Check the clerk's record before citing anyone.",
    party_breakers: () => "The 40 members who most often voted against the majority of their own caucus, among members with at least 30 such votes. A caucus majority counts only when at least 60 percent of its members voted the same way.",
  };
  function renderLeads() {
    const leads = (state.payload && state.payload.story_leads) || {};
    const keys = LEADS.filter(([k]) => leads[k]);
    if (!keys.length) { $("leads").hidden = true; return; }
    if (!state.leadTab || !leads[state.leadTab]) state.leadTab = keys[0][0];
    // Leads follow the outcome, chamber, and topic filters but not the search box,
    // so opening a bill from a lead (which searches for it) keeps the lead list.
    const noText = { ...state.filters, q: "" };
    const inView = new Set(state.bills.filter(b => matches(b, noText, false)).map(b => b.bill_id));
    const rowsOf = (k) => leadRows(k, leads[k]).filter(r => !r.bill || inView.has(r.bill.replace(/\s+/g, "")) || NO_BILL.has(k));
    const tabRow = $("lead-tabs"), keepX = tabRow.scrollLeft;
    tabRow.replaceChildren(...keys.map(([k, label]) => el("button", {
      class: "tab", role: "tab", type: "button", "aria-selected": String(k === state.leadTab),
      onClick: () => { state.leadTab = k; state.leadAll = false; renderLeads(); postHeight(); },
    }, label, el("span", { class: "n", text: fmtInt(rowsOf(k).length) }))));
    tabRow.scrollLeft = keepX;
    const lead = leads[state.leadTab];
    const full = leadRows(state.leadTab, lead).length;
    $("leads-why").textContent = PUBLIC_WHY[state.leadTab] ? PUBLIC_WHY[state.leadTab](lead, full) : (lead.why || "");
    const rows = rowsOf(state.leadTab);
    const limit = state.leadAll ? 200 : 6;
    const list = $("lead-list");
    if (!rows.length) list.replaceChildren(el("li", null, el("p", { class: "empty", text: "Nothing here for the current filters." })));
    else list.replaceChildren(...rows.slice(0, limit).map(r => el("li", null, el("button", { class: "lead", type: "button", onClick: r.onClick || (() => openByKey(r.bill.replace(/\s+/g, ""), true)) },
      el("span", { class: "lead-key", text: r.left }), el("span", { class: "lead-title", text: cap(r.title) }), el("span", { class: "lead-meta" }, ...r.detail), el("span", { class: "chev", "aria-hidden": "true", text: "›" })))));
    const more = $("lead-more");
    more.hidden = rows.length <= 6;
    more.textContent = state.leadAll ? "Show fewer" : `Show all ${fmtInt(Math.min(rows.length, 200))}`;
  }
  function leadRows(kind, lead) {
    const b = (x) => el("b", { text: x });
    const who2 = (x) => `${x.name} (${x.party}${x.district ? ", " + (x.chamber === "Senate" ? "Dist. " : (x.county ? x.county + " " : "")) + x.district : ""})`;
    switch (kind) {
      case "upcoming_events": return (lead.bills || []).map(x => ({ bill: x.bill, left: x.bill, title: x.title, detail: [b(`${fmtDate(x.next.date)} · ${x.next.kind}`), ` · now in ${x.status.toLowerCase()}`] }));
      case "recent_activity": return (lead.bills || []).map(x => ({ bill: x.bill, left: x.bill, title: x.title, detail: [b(fmtDate(x.date)), ` · ${x.last_action}`] }));
      case "vetoes": return (lead.bills || []).map(x => {
        const v = x.veto || {}; const bits = [];
        if (v.house) bits.push(`House ${v.house.result === "overridden" ? "overrode" : "sustained"} ${v.house.vote}`);
        if (v.senate) bits.push(`Senate ${v.senate.result === "overridden" ? "overrode" : "sustained"} ${v.senate.vote}`);
        return { bill: x.bill, left: x.bill, title: x.title, detail: [b(x.outcome.startsWith("Vetoed; override succeeded") ? "Became law over the veto" : x.outcome.includes("sustained") ? "Veto stood" : "Vetoed"), v.veto_date ? ` · vetoed ${fmtDate(v.veto_date)}` : "", bits.length ? ` · ${bits.join(", ")}` : ""] };
      });
      case "close_votes": return (lead.votes || []).map(x => ({ bill: x.bill, left: x.bill, title: x.title, detail: [b(`${x.chamber} ${x.yeas}–${x.nays}`), ` on ${x.motion.toLowerCase()} · ${fmtDate(x.date)}`, splitText(x.party_split) ? ` · ${splitText(x.party_split)}` : ""] }));
      case "party_line_votes": return (lead.votes || []).map(x => ({ bill: x.bill, left: x.bill, title: x.title, detail: [b(`${x.chamber} ${x.yeas}–${x.nays}`), ` · ${splitText(x.party_split)} · ${fmtDate(x.date)}`] }));
      case "died_in_other_chamber": return (lead.bills || []).map(x => ({ bill: x.bill, left: x.bill, title: x.title, detail: [b(`Passed the ${x.origin}`), `, ${x.how.toLowerCase()} in the ${x.died_in} · ${fmtDate(x.date)}`] }));
      case "effective_soon": return (lead.bills || []).map(x => ({ bill: x.bill, left: x.bill, title: x.title, detail: [b(`Takes effect ${fmtDate(x.effective)}`), x.chapter ? ` · Chapter ${x.chapter}` : ""] }));
      case "parked": return (lead.bills || []).map(x => ({ bill: x.bill, left: x.bill, title: x.title, detail: [b(x.how), ` · ${fmtDate(x.date)}`, x.committee ? ` · ${x.committee}` : ""] }));
      case "most_roll_calls": return (lead.bills || []).map(x => ({ bill: x.bill, left: x.bill, title: x.title, detail: [b(`${x.roll_calls} roll calls`), ` · ${x.status}`] }));
      case "top_prime_sponsors": return (lead.sponsors || []).map(x => ({ bill: null, left: `${x.bills} bills`, title: `${x.name}${x.party ? " (" + x.party + ")" : ""}`, detail: [b(`${x.laws} became law`), ` · ${x.killed} killed`], onClick: () => searchFor(x.name) }));
      case "attendance": return (lead.legislators || []).map(x => ({ bill: null, left: `${x.not_voting} of ${x.roll_calls}`, title: `${who2(x)}, ${x.chamber}`, detail: [b(`${x.not_voting_pct}% of roll calls marked “not voting, not excused”`), x.excused ? ` · ${x.excused} excused` : ""], onClick: () => searchFor(x.name) }));
      case "party_breakers": return (lead.legislators || []).map(x => ({ bill: null, left: `${x.against_party_pct}%`, title: `${who2(x)}, ${x.chamber}`, detail: [b(`${x.against_party} of ${x.party_votes} votes`), " against the caucus majority"], onClick: () => searchFor(x.name) }));
      default: return [];
    }
  }
  function splitText(ps) { return ps ? ["R", "D", "I"].filter(p => ps[p]).map(p => `${p} ${ps[p].yea}–${ps[p].nay}`).join(", ") : ""; }
  function searchFor(text) { $("f-q").value = text; state.filters.q = text; state.filters.group = ""; resetPaging(); apply(); reveal($("finder")); }

  // ------------------------------------------------------------------ chips
  function renderChips() {
    const base = state.bills.filter(b => matches(b, state.filters, true));
    const c = groupCounts(base);
    const chip = (key, label, n) => el("button", { class: "chip", type: "button", "aria-pressed": String(state.filters.group === key), onClick: () => { state.filters.group = key; resetPaging(); apply(); } },
      key ? el("i", { class: `k-${key}`, "aria-hidden": "true" }) : null, label, el("span", { class: "n", text: fmtInt(n) }));
    $("chips").replaceChildren(chip("", "All", base.length), ...GROUPS.map(g => chip(g.key, g.label, c[g.key])));
  }

  // ------------------------------------------------------------------ list
  const sponsorOf = (s) => {
    const r = (state.roster && state.roster[s.id]) || {};
    const party = s.party || r.party || "";
    const title = r.body === "S" ? "Sen." : r.body === "H" ? "Rep." : "";
    const place = r.district ? (r.body === "S" ? `District ${r.district}` : `${r.county ? r.county + " " : ""}${r.district}`) : "";
    return { name: `${title ? title + " " : ""}${s.name}`, tag: [party, place].filter(Boolean).join(", ") };
  };
  function renderList() {
    const f = state.filters, total = state.bills.length, n = state.view.length;
    const bits = [f.group ? GROUP_LABEL[f.group].toLowerCase() : "", f.q ? `matching “${f.q}”` : ""].filter(Boolean);
    $("count").replaceChildren(el("b", { text: fmtInt(n) }), n === total ? ` bills` : ` of ${fmtInt(total)} bills`, bits.length ? ` · ${bits.join(", ")}` : "");
    const list = $("bill-list");
    if (!n) {
      list.replaceChildren(el("li", null, el("p", { class: "empty", text: "No bills match. Try fewer words, or clear the filters." })));
      $("more").replaceChildren();
      return;
    }
    list.replaceChildren(...state.view.slice(0, state.shown).map(billRow));
    const left = n - state.shown;
    $("more").replaceChildren(left > 0 ? el("button", { class: "btn", type: "button", onClick: () => { state.shown += PAGE; renderList(); postHeight(); } }, `Show ${fmtInt(Math.min(PAGE, left))} more`, el("span", { style: "font-weight:400;opacity:.75", text: ` of ${fmtInt(left)} left` })) : "");
  }
  function billRow(b) {
    const k = billKey(b), open = state.openKey === k;
    const prime = (b.sponsors || []).find(s => s.primary) || (b.sponsors || [])[0];
    const sp = prime ? sponsorOf(prime) : null;
    const meta = [sp ? `${sp.name}${sp.tag ? " (" + sp.tag + ")" : ""}` : "", b.committee || ""].filter(Boolean).join(" · ");
    const head = el("button", { class: "bill-head", type: "button", "aria-expanded": String(open), "aria-controls": "d-" + k, onClick: () => toggleBill(b) },
      el("span", { class: "bill-id" }, b.bill_label || b.lsr_id, el("small", { text: b.origin_chamber === "Senate" ? "Senate" : b.origin_chamber === "House" ? "House" : "" })),
      el("span", { class: "bill-main" }, el("span", { class: "bill-title", text: cap(b.title) || "(title not in the current data)" }), meta ? el("span", { class: "bill-meta", text: meta }) : null),
      el("span", { class: "bill-status" }, pill(b), b.last_action_date ? el("span", { class: "when", text: fmtDate(b.last_action_date) }) : null));
    const li = el("li", { class: `bill${open ? " open" : ""}`, id: "bill-" + k }, head);
    if (open) li.append(detail(b));
    return li;
  }
  function pill(b) { return el("span", { class: `pill g-${b.group}`, title: b.status_label }, el("i", { "aria-hidden": "true" }), SHORT[b.status] || b.status_label); }
  function toggleBill(b) {
    const k = billKey(b);
    state.openKey = state.openKey === k ? null : k;
    renderList();
    setHash(state.openKey ? "#" + k : "");
    postHeight();
    if (state.openKey) {
      const li = $("bill-" + k);
      const r = li && li.getBoundingClientRect();
      if (EMBED || (r && (r.top < 0 || r.top > window.innerHeight * .6))) reveal(li);
    }
  }
  function openByKey(k, scroll) {
    const b = state.byKey.get(k);
    if (!b) return;
    let idx = state.view.indexOf(b);
    // A bill outside the rows on screen is shown by searching for its number,
    // not by drawing every row above it (HB 2026 would mean 800 rows).
    if (idx < 0 || idx >= state.shown) {
      state.filters = { q: b.bill_label || b.bill_id, chamber: "", group: "", beat: "", subject: "", sort: state.filters.sort, rc: false };
      $("f-q").value = state.filters.q; $("f-chamber").value = ""; $("f-beat").value = ""; $("f-subject").value = ""; $("f-rc").checked = false;
      state.view = state.bills.filter(x => matches(x, state.filters, false)); sortView();
      idx = state.view.indexOf(b);
    }
    if (idx >= state.shown) state.shown = idx + 1;
    state.openKey = k;
    renderFigurePressed(); renderChips(); renderLeads(); renderList();
    setHash("#" + k);
    postHeight();
    if (scroll) requestAnimationFrame(() => reveal($("bill-" + k)));
  }

  // ------------------------------------------------------------------ detail
  function detail(b) {
    const d = el("div", { class: "detail", id: "d-" + billKey(b) });
    d.append(el("div", { class: "d-status" }, pill(b), el("span", { class: "d-status-text", text: b.status_label }),
      b.last_action_date ? el("span", { class: "d-status-when", text: `as of ${fmtDate(b.last_action_date)}` }) : null));
    const veto = b.status_detail && b.status_detail.veto;
    if (veto) {
      const steps = [el("li", { class: "no", text: `Vetoed ${fmtDate(veto.veto_date)}` })];
      for (const side of ["house", "senate"]) {
        const r = veto[side]; if (!r) continue;
        steps.push(el("li", { class: r.result === "overridden" ? "ok" : "no", text: `${side === "house" ? "House" : "Senate"} ${r.result === "overridden" ? "overrode" : "sustained"}${r.vote ? " " + r.vote.replace("-", "–") : ""}, ${fmtDate(r.date)}` }));
      }
      d.append(el("div", { class: "d-callout" }, el("b", { text: "Veto record. " }), "An override needs two-thirds in both chambers.", el("ul", { class: "steps" }, steps)));
    }
    if (b.chapter || (b.effective_dates || []).length) {
      d.append(el("div", { class: "d-callout" }, b.chapter ? el("b", { text: `Chapter ${b.chapter}. ` }) : null,
        (b.effective_dates || []).length ? `Takes effect ${b.effective_dates.map(x => fmtDate(x)).join("; ")}.` + (b.effective_dates.length > 1 ? " Different sections start on different dates; read the chaptered text." : "") : ""));
    }
    if ((b.next_events || []).length) {
      const e = b.next_events[0];
      d.append(el("div", { class: "d-callout" }, el("b", { text: `Scheduled ${fmtDate(e.date)}. ` }), e.text));
    }
    // The docket file sometimes stops at a committee report while the bill table
    // records later floor action. Say so instead of implying the bill is pending.
    if (b.group === "process") {
      const dts = b.dates || {};
      const floor = [["House", dts.house_last_floor], ["Senate", dts.senate_last_floor]].filter(([, x]) => x && x > (b.last_action_date || "")).sort((a, z) => (a[1] < z[1] ? 1 : -1))[0];
      d.append(el("div", { class: "d-callout" }, el("b", { text: "No final action in the docket file. " }),
        floor ? `The General Court's bill table records ${floor[0]} floor action on ${fmtDate(floor[1])}, after the last docket entry here, but not what happened. ` : "",
        b.doc_id ? "Check the official bill page before describing this bill as pending." : "Check the docket on gc.nh.gov before describing this bill as pending."));
    }
    const links = buildLinks(b);
    const primary = links.filter(l => l.primary);
    d.append(el("div", { class: "d-actions" }, primary.map((l, i) => el("a", { class: `btn small${i === 0 ? " solid" : ""}`, href: l.url, target: "_blank", rel: "noopener", text: l.label })),
      el("button", { class: "btn small", type: "button", text: "Copy link", onClick: copyLink })));

    const sp = b.sponsors || [];
    const primes = sp.filter(s => s.primary), cos = sp.filter(s => !s.primary);
    const nameOf = (s) => { const x = sponsorOf(s); return `${x.name}${x.tag ? " (" + x.tag + ")" : ""}`; };
    const coNode = cos.length ? cosponsorNode(cos, nameOf) : "None listed";
    const committees = [...((b.committees && b.committees.house) || []).map(c => "House " + c), ...((b.committees && b.committees.senate) || []).map(c => "Senate " + c)].join(", ") || b.committee || "Not in the data";
    const facts = [
      ["Prime sponsor", primes.length ? primes.map(nameOf).join("; ") : "Not in the data"],
      ["Cosponsors", coNode],
      ["Committees", committees],
      ["Subject", b.subject ? `${b.subject}${b.subject_code && b.subject !== b.subject_code ? " (" + b.subject_code + ")" : ""}` : ""],
      ["Filed as", `${b.bill_type} · LSR ${b.lsr_id}`],
      ["First action", fmtDate(b.first_action_date)],
    ].filter(([, v]) => v);
    d.append(el("dl", { class: "d-grid" }, facts.map(([k, v]) => [el("dt", { text: k }), el("dd", null, v)])));

    const acts = b.actions || [];
    if (acts.length) {
      const tl = el("ol", { class: "timeline" });
      const decisive = b.status_detail && b.status_detail.decisive_action;
      const fill = (all) => {
        const rows = all ? acts : acts.slice(-6);
        tl.replaceChildren(...rows.map(a => el("li", { class: a.text === decisive || /vetoed|signed by|chapter \d+|enacted in accordance/i.test(a.text) ? "key" : "" },
          el("time", { datetime: a.date, text: fmtDate(a.date) }), el("span", { class: "ch", text: a.chamber }), el("span", { class: "tx", text: a.text }))));
      };
      fill(false);
      const toggle = acts.length > 6 ? el("button", { class: "text-btn", type: "button", style: "margin-top:8px", text: `Show all ${acts.length} docket entries` }) : null;
      if (toggle) toggle.addEventListener("click", () => { const all = toggle.dataset.all !== "1"; toggle.dataset.all = all ? "1" : ""; fill(all); toggle.textContent = all ? "Show the latest six" : `Show all ${acts.length} docket entries`; postHeight(); });
      d.append(el("h3", { class: "d-h", text: acts.length > 6 ? `Docket · latest of ${acts.length}` : "Docket" }), tl, toggle);
    }
    if ((b.roll_calls || []).length) d.append(el("h3", { class: "d-h", text: `Recorded votes · ${b.roll_calls.length}` }), ...b.roll_calls.map(rollCall));
    else d.append(el("h3", { class: "d-h", text: "Recorded votes" }), el("p", { class: "empty", style: "padding:0", text: "No roll call on record. Voice and division votes are not recorded by name." }));

    const other = links.filter(l => !l.primary);
    d.append(el("h3", { class: "d-h", text: "Elsewhere" }), el("div", { class: "elsewhere" }, other.map(l => el("a", { href: l.url, target: "_blank", rel: "noopener", text: l.label }))));
    const decisive = (b.status_detail && b.status_detail.decisive_action) || b.last_action;
    d.append(el("div", { class: "d-foot" },
      el("span", null, "Outcome read from the docket entry ", el("q", { text: decisive }), ". Check the docket before quoting."),
      el("button", { class: "text-btn", type: "button", text: "Copy citation", onClick: (e) => copyText(e, `${b.bill_label}, ${cap(b.title)} (${b.session} N.H. General Court), ${b.status_label.toLowerCase()}; last docket action ${fmtDate(b.last_action_date)}: ${b.last_action}. Source: gc.nh.gov bill status.`) })));
    return d;
  }
  function cosponsorNode(cos, nameOf) {
    const span = el("span", { class: "sponsor-list" });
    const fill = (all) => {
      const names = cos.map(nameOf);
      span.replaceChildren(all || names.length <= 6 ? names.join("; ") : names.slice(0, 6).join("; ") + "; ");
      if (!all && names.length > 6) span.append(el("button", { class: "text-btn", type: "button", text: `and ${names.length - 6} more`, onClick: () => { fill(true); postHeight(); } }));
    };
    fill(false);
    return span;
  }
  function rollCall(v) {
    const margin = Math.abs((v.yeas || 0) - (v.nays || 0));
    const close = (v.yeas + v.nays) && margin <= (v.body === "S" ? 3 : 12);
    const split = splitText(v.party_split);
    return el("div", { class: "rc" },
      el("div", { class: "rc-top" }, el("span", null, el("b", { text: `${v.chamber} · ${fmtDate(v.date)}` }), ` · ${v.motion}`), close ? el("span", { class: "rc-close", text: `Decided by ${margin}` }) : null),
      el("div", { class: "tally", role: "img", "aria-label": `${v.yeas} yea, ${v.nays} nay` }, el("div", { class: "y", style: `flex:${v.yeas || 0} ${v.yeas || 0} 0` }), el("div", { class: "n", style: `flex:${v.nays || 0} ${v.nays || 0} 0` })),
      el("div", { class: "rc-nums" }, el("span", { class: "ky" }, el("b", { text: fmtInt(v.yeas) }), " yea"), el("span", { class: "kn" }, el("b", { text: fmtInt(v.nays) }), " nay"),
        v.not_voting ? el("span", { text: `${fmtInt(v.not_voting)} not voting` }) : null, v.excused ? el("span", { text: `${fmtInt(v.excused)} excused` }) : null,
        split ? el("span", { text: `By party: ${split}${v.party_line ? " (party line)" : ""}` }) : null));
  }
  // Documented URL patterns filled with the bill's own identifiers (docs/METHODOLOGY.md).
  function buildLinks(b) {
    const s = b.session, bid = b.bill_id, label = b.bill_label || b.lsr_id;
    const q = encodeURIComponent(`"${label}" New Hampshire`), q2 = encodeURIComponent(label);
    const L = [];
    if (b.doc_id) {
      L.push({ primary: true, label: "Read the bill (PDF)", url: `https://gc.nh.gov/bill_Status/pdf.aspx?id=${b.doc_id}&q=billVersion` });
      L.push({ primary: true, label: "Official bill page", url: `https://gc.nh.gov/bill_Status/billinfo.aspx?id=${b.doc_id}&inflect=2` });
    }
    L.push({ primary: true, label: "Docket", url: `https://gc.nh.gov/bill_status/legacy/bs2016/bill_docket.aspx?lsr=${encodeURIComponent(b.lsr)}&sy=${s}&sortoption=&txtsessionyear=${s}` });
    if (b.doc_id) L.push({ label: "Bill text (HTML)", url: `https://gc.nh.gov/bill_status/legacy/bs2016/billText.aspx?sy=${s}&id=${b.doc_id}&txtFormat=html` });
    if (bid) { L.push({ label: "LegiScan", url: `https://legiscan.com/NH/bill/${bid}/${s}` }); L.push({ label: "Plural", url: `https://open.pluralpolicy.com/nh/bills/${s}/${bid}/` }); }
    L.push({ label: "Governor's newsroom", url: "https://www.governor.nh.gov/news-and-media" });
    L.push({ label: "Google News", url: `https://news.google.com/search?q=${q}` });
    L.push({ label: "New Hampshire Bulletin", url: `https://newhampshirebulletin.com/?s=${q2}` });
    L.push({ label: "InDepthNH", url: `https://indepthnh.org/?s=${q2}` });
    L.push({ label: "NHPR", url: `https://www.nhpr.org/search?q=${q2}` });
    L.push({ label: "Granite State Report", url: `https://granitestatereport.com/?s=${q2}` });
    return L;
  }
  function copyLink(e) {
    const canon = document.querySelector('meta[name="canonical-base"]');
    const base = canon && canon.content ? canon.content : location.origin + location.pathname + location.search;
    copyText(e, base + (state.openKey ? "#" + state.openKey : ""));
  }
  function copyText(e, text) {
    const btn = e.currentTarget, old = btn.textContent;
    const done = (ok) => { btn.textContent = ok ? "Copied" : "Copy failed; select the text"; setTimeout(() => (btn.textContent = old), 1800); };
    if (navigator.clipboard && navigator.clipboard.writeText) navigator.clipboard.writeText(text).then(() => done(true), () => done(false));
    else done(false);
  }

  boot();
})();
