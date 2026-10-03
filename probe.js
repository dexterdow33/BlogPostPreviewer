// Probe: live-site links + footer version, and every outside service the GSR Desk calls.
const fs = require('fs');
const D = JSON.parse(fs.readFileSync('desk_defaults.json', 'utf8'));
const ORIGIN = 'https://granitestatereport.com';
const UA_BROWSER = 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0 Safari/537.36';
const UA_WP = 'WordPress/6.8; https://granitestatereport.com';
async function get(url, opts = {}) {
  const t0 = Date.now(); const ctl = new AbortController(); const timer = setTimeout(() => ctl.abort(), opts.timeout || 15000);
  try {
    const r = await fetch(url, { redirect: 'follow', signal: ctl.signal, headers: { 'User-Agent': opts.ua || UA_BROWSER, ...(opts.headers || {}) } });
    const body = opts.body === false ? '' : await r.text();
    return { status: r.status, ms: Date.now() - t0, finalUrl: r.url, ct: r.headers.get('content-type'), acao: r.headers.get('access-control-allow-origin'), xfo: r.headers.get('x-frame-options'), csp: (r.headers.get('content-security-policy') || '').match(/frame-ancestors[^;]*/)?.[0] || null, bytes: body.length, body };
  } catch (e) { return { status: 0, ms: Date.now() - t0, error: String(e.name === 'AbortError' ? 'timeout' : e.message) }; }
  finally { clearTimeout(timer); }
}
const strip = (o) => { const { body, ...rest } = o; return rest; };
(async () => {
  const out = { at: new Date().toISOString(), site: {}, desk: {} };
  // ---- live site ----
  const home = await get(ORIGIN + '/');
  out.site.homeStatus = home.status;
  out.site.footerVersion = (home.body.match(/<!-- GSR footer (v\d+[^>]*)-->/) || [])[1] || null;
  const footer = (home.body.match(/<div class="gsr-footer">([\s\S]*?)<div class="gsr-footer-copy">/) || [])[1] || '';
  const groups = [...footer.matchAll(/<div class="gsr-footer-label">([^<]+)<\/div>\s*(?:<nav[^>]*>([\s\S]*?)<\/nav>|<p>)/g)].map(m => ({ label: m[1], links: [...(m[2] || '').matchAll(/<a href="([^"]+)">([^<]+)<\/a>/g)].map(x => ({ url: x[1], text: x[2] })) }));
  out.site.footerGroups = groups.map(g => ({ label: g.label, items: g.links.map(l => l.text) }));
  const ti = home.body.indexOf('>Tools</a>'); const tu = ti >= 0 ? home.body.indexOf('<ul', ti) : -1; const toolsMenu = tu >= 0 ? home.body.slice(tu, home.body.indexOf('</ul>', tu)) : '';
  const menuLinks = [...toolsMenu.matchAll(/<a href="([^"]+)">([^<]+)<\/a>/g)].map(x => ({ url: x[1], text: x[2] }));
  out.site.toolsMenu = menuLinks.map(l => l.text);
  const allLinks = new Map();
  for (const g of groups) for (const l of g.links) allLinks.set(l.url, l.text);
  for (const l of menuLinks) allLinks.set(l.url, l.text);
  for (const extra of ['https://granitestatereport.com/nh-bill-tracker/', 'https://granitestatereport.com/2026/09/29/gsr-tools/', 'https://granitestatereport.com/2026/09/17/record-room/', 'https://granitestatereport.com/subscribe/', 'https://granitestatereport.com/desk/']) allLinks.set(extra, allLinks.get(extra) || extra);
  out.site.links = [];
  for (const [url, text] of allLinks) { const r = await get(url, { body: true }); out.site.links.push({ text, url, status: r.status, finalUrl: r.finalUrl !== url ? r.finalUrl : undefined, ms: r.ms, title: (r.body || '').match(/<title>([^<]*)<\/title>/)?.[1] || null, error: r.error }); }
  // tracker data freshness
  const idx = await get('https://raw.githubusercontent.com/dexterdow33/BlogPostPreviewer/master/data/index.json');
  try { const j = JSON.parse(idx.body); out.site.trackerData = { generated_at: j.generated_at, fetched_at: j.fetched_at }; } catch (_) { out.site.trackerData = strip(idx); }
  // ---- desk outside services (browser-side) ----
  const H = { Origin: ORIGIN };
  out.desk.nws = strip(await get('https://api.weather.gov/alerts/active?area=NH', { headers: { ...H, Accept: 'application/geo+json' } }));
  out.desk.mastodon = await (async () => { const r = await get('https://mastodon.social/api/v1/timelines/tag/newhampshire?limit=20', { headers: H }); let n = null; try { n = JSON.parse(r.body).length; } catch (_) {} return { ...strip(r), items: n, sample: (r.body || '').slice(0, 160) }; })();
  out.desk.bluesky = [];
  for (const a of D.blueskyAccounts) { const r = await get(`https://public.api.bsky.app/xrpc/app.bsky.feed.getAuthorFeed?actor=${encodeURIComponent(a)}&limit=12&filter=posts_no_replies`, { headers: H }); let n = null; try { n = JSON.parse(r.body).feed.length; } catch (_) {} out.desk.bluesky.push({ kind: 'account', q: a, status: r.status, acao: r.acao, items: n, err: n === null ? (r.body || r.error || '').slice(0, 160) : undefined }); }
  for (const q of D.blueskyQueries) { const r = await get(`https://public.api.bsky.app/xrpc/app.bsky.feed.searchPosts?q=${encodeURIComponent(q)}&sort=latest&limit=15`, { headers: H }); let n = null; try { n = JSON.parse(r.body).posts.length; } catch (_) {} out.desk.bluesky.push({ kind: 'search', q, status: r.status, acao: r.acao, items: n, err: n === null ? (r.body || r.error || '').slice(0, 160) : undefined }); }
  // ---- desk feeds (WordPress fetches these server-side) ----
  out.desk.feeds = [];
  await Promise.all(D.feeds.map(async (f) => {
    const r = await get(f.url, { ua: UA_WP, timeout: 15000 });
    const items = r.body ? (r.body.match(/<item[\s>]/g) || []).length + (r.body.match(/<entry[\s>]/g) || []).length : 0;
    out.desk.feeds.push({ id: f.id, name: f.name, group: f.group, status: r.status, ms: r.ms, ct: r.ct, items, error: r.error, finalUrl: r.finalUrl !== f.url ? r.finalUrl : undefined });
  }));
  out.desk.feeds.sort((a, b) => a.id.localeCompare(b.id));

  // ---- candidate replacement sources ----
  const GN = (q) => 'https://news.google.com/rss/search?q=' + encodeURIComponent(q) + '&hl=en-US&gl=US&ceid=US:en';
  const cands = [
    ['gn-site-laconia', GN('site:laconiadailysun.com')], ['gn-site-keene', GN('site:keenesentinel.com')], ['gn-site-sentinelsource', GN('site:sentinelsource.com')],
    ['gn-site-conway', GN('site:conwaydailysun.com')], ['gn-site-eagletrib', GN('site:eagletribune.com')], ['gn-site-caledonian', GN('site:caledonianrecord.com')],
    ['gn-fbi-nh', GN('FBI "New Hampshire"')], ['gn-fbi-boston', GN('"FBI Boston"')], ['nhpr-new', 'https://www.nhpr.org/latest-from-nhpr-rss.rss'],
    ['usao-nh-rss', 'https://www.justice.gov/usao-nh/pr/rss.xml'], ['keene-direct', 'https://www.keenesentinel.com/search/?f=rss&t=article&l=25&s=start_time&sd=desc'],
  ];
  out.desk.candidates = [];
  await Promise.all(cands.map(async ([id, url]) => { const r = await get(url, { ua: UA_WP }); const items = r.body ? (r.body.match(/<item[\s>]/g) || []).length + (r.body.match(/<entry[\s>]/g) || []).length : 0; const first = (r.body || '').match(/<item>[\s\S]*?<title>([^<]*)<\/title>/)?.[1] || null; out.desk.candidates.push({ id, url, status: r.status, items, first, error: r.error }); }));
  out.desk.bskyAlt = [];
  for (const host of ['https://api.bsky.app', 'https://public.api.bsky.app', 'https://bsky.social']) { const r = await get(host + '/xrpc/app.bsky.feed.searchPosts?q=' + encodeURIComponent('"New Hampshire" police') + '&sort=latest&limit=5', { headers: H }); let n = null; try { n = JSON.parse(r.body).posts.length; } catch (_) {} out.desk.bskyAlt.push({ host, status: r.status, acao: r.acao, items: n, err: n === null ? (r.body || r.error || '').slice(0, 120) : undefined }); }
  // ---- scanner players ----
  out.desk.scanners = [];
  for (const s of D.scanners.slice(0, 3)) { const r = await get(`https://www.broadcastify.com/webPlayer/${s.id}`); const r2 = await get(`https://www.broadcastify.com/listen/feed/${s.id}`); out.desk.scanners.push({ id: s.id, webPlayer: { status: r.status, xfo: r.xfo, csp: r.csp, finalUrl: r.finalUrl }, feedPage: { status: r2.status, title: (r2.body || '').match(/<title>([^<]*)<\/title>/)?.[1] || null } }); }
  // ---- primary sources the sandbox cannot reach (saved raw for reading) ----
  out.sources = {};
  for (const [id, url] of [['rsa-91-A-4', 'https://gc.nh.gov/rsa/html/VI/91-A/91-A-4.htm'], ['rsa-91-A-mrg', 'https://gc.nh.gov/rsa/html/VI/91-A/91-A-mrg.htm'], ['nh-state-holidays', 'https://www.employeeportal.nh.gov/compensation-savings/state-holiday-schedule']]) {
    try { const ctl = new AbortController(); const t = setTimeout(() => ctl.abort(), 30000); const r = await fetch(url, { redirect: 'follow', signal: ctl.signal, headers: { 'User-Agent': UA_BROWSER } }); clearTimeout(t); const b = await r.text(); fs.writeFileSync(`${process.env.OUT}/source-${id}.html`, b); out.sources[id] = { status: r.status, finalUrl: r.url, bytes: b.length }; } catch (e) { out.sources[id] = { error: String(e) }; }
  }
  fs.writeFileSync(process.env.OUT + '/probe.json', JSON.stringify(out, null, 1));
  console.log('probe written');
})().catch(e => { console.error(e); process.exit(1); });
