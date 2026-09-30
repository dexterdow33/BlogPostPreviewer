const { chromium } = require('playwright');
const fs = require('fs');
const S = process.argv[2] || __dirname, which = process.argv[3] || "new";
const strip = s => s.replace(/<!-- \/?wp:html -->/g, '');
const html = '<!doctype html><html><head><meta charset="utf-8"></head><body class="page-id-6462">' +
  strip(fs.readFileSync(S + '/archive-page-block0.sample.html', 'utf8')) + '<div>form</div>' +
  strip(fs.readFileSync(S + (which === 'new' ? '/archive-page-block2.html' : '/archive-page-block2.original.html'), 'utf8')) + '</body></html>';
const cap = s => ({ rendered: '<p>' + s + '</p>\n' });
function item(id, tag, title, date, mime) {
  return { id, date, title: { rendered: title }, caption: cap(tag), mime_type: mime || 'application/pdf',
           source_url: 'https://gsr.test/wp-content/uploads/f' + id, post: 0, media_details: { filesize: 2048 } };
}
const page1 = [
  item(9001, '[archive juris=NH tier=rsa series=New Hampshire Revised Statutes Annotated (RSA) agency=NH Revised Statutes Annotated (RSA) src=https://gc.nh.gov/rsa/html/vi/91-a/91-a-mrg.htm] Retrieved from gc.nh.gov on 2026-09-30.',
       'Chapter 91-A ACCESS TO GOVERNMENTAL RECORDS AND MEETINGS', '2026-09-30T10:00:00', 'text/plain'),
  item(9002, '[archive juris=NH tier=governor-press series=Governor&#8217;s press releases and statements agency=Office of the Governor date=2026-03-26 src=https://www.governor.nh.gov/news/x] Retrieved from www.governor.nh.gov on 2026-09-30.',
       'Governor Ayotte Issues Executive Order', '2026-09-30T10:00:00', 'text/plain'),
  item(9003, '[archive juris=US tier=federal-register series=Federal Register date=2026-09-28 src=https://www.federalregister.gov/d/2026-1]', 'A rule', '2026-09-30T10:00:00'),
  item(9004, 'no tag here', 'Untagged file', '2026-09-30T10:00:00'),
  item(9005, '[archive juris=NH tier=records agency=NH Department of Justice] Manual entry.', 'Manual record', '2026-09-20T10:00:00'),
  item(9006, '[archive tier=Bad Slug!! series=x]', 'Bad slug goes to records', '2026-09-20T10:00:00'),
];
const page2 = [ item(9101, '[archive juris=NH tier=rsa series=New Hampshire Revised Statutes Annotated (RSA)] ', 'Chapter 5 DEPARTMENT OF STATE', '2026-09-29T10:00:00', 'text/plain') ];
(async () => {
  const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const p = await b.newPage();
  const errs = []; p.on('pageerror', e => errs.push(e.message));
  await p.route('https://gsr.test/**', async r => {
    const u = new URL(r.request().url());
    if (u.pathname === '/archive/') return r.fulfill({ contentType: 'text/html', body: html });
    if (u.pathname === '/wp-json/wp/v2/media') {
      const t = u.searchParams.get('media_type'), pg = u.searchParams.get('page') || '1';
      const all = (pg === '1' ? page1 : page2).filter(m => (t === 'text') === m.mime_type.startsWith('text'));
      return r.fulfill({ contentType: 'application/json', headers: { 'X-WP-TotalPages': '2' }, body: JSON.stringify(all) });
    }
    if (u.pathname === '/wp-json/wp/v2/posts') return r.fulfill({ contentType: 'application/json', body: '[]' });
    return r.fulfill({ status: 404, body: '' });
  });
  await p.goto('https://gsr.test/archive/');
  await p.waitForTimeout(800);
  const res = await p.evaluate(() => {
    const q = s => [].slice.call(document.querySelectorAll(s));
    return {
      series: q('.gsa-series[data-tier]').map(s => s.getAttribute('data-tier') + ' | ' + s.querySelector('h2').textContent + ' | ' + s.querySelectorAll('.gsa-entry').length),
      buttons: q('[data-fg=tier] button').map(b => b.textContent),
      count: document.getElementById('gsa-n').textContent,
      stats: q('.gsa-ex').map(e => e.textContent.trim().replace(/\s+/g, ' ')),
      metas: q('.gsa-entry').filter(e => +e.getAttribute('data-id') > 9000).map(e => e.getAttribute('data-id') + ' ' + e.querySelector('.gsa-meta').textContent),
    };
  });
  console.log(JSON.stringify(res, null, 1));
  const btn = await p.$('[data-fg=tier] button[data-f=rsa]');
  if (btn) { await btn.click(); console.log('after RSA filter:', await p.$eval('#gsa-n', e => e.textContent),
    await p.$$eval('.gsa-series', xs => xs.filter(x => x.style.display !== 'none').map(x => x.getAttribute('data-tier')))); }
  console.log('errors:', errs);
  await b.close();
})();
