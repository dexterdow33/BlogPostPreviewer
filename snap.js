// Photograph pages at desktop and phone width; save HTML, CSS and layout facts.
const { chromium } = require('playwright');
const fs = require('fs');
const OUT = process.env.OUT;
const targets = fs.readFileSync('targets.txt', 'utf8').split('\n').map(s => s.trim()).filter(s => s && !s.startsWith('#'));
(async () => {
  const browser = await chromium.launch();
  for (const url of targets) {
    const slug = url.replace(/^https?:\/\//, '').replace(/[^a-z0-9]+/gi, '_').replace(/_+$/, '').slice(0, 60) + (url.includes('#') ? '_deeplink' : '');
    for (const [name, vp, mobile] of [['desktop', { width: 1440, height: 900 }, false], ['mobile', { width: 390, height: 844 }, true]]) {
      const ctx = await browser.newContext({ viewport: vp, isMobile: mobile, hasTouch: mobile, deviceScaleFactor: 1 });
      const page = await ctx.newPage();
      const css = []; const log = [];
      page.on('console', m => log.push(`[${m.type()}] ${m.text()}`));
      page.on('pageerror', e => log.push(`[pageerror] ${e.message}`));
      page.on('requestfailed', r => log.push(`[failed] ${r.url()} ${r.failure() && r.failure().errorText}`));
      page.on('response', async r => { try { const ct = r.headers()['content-type'] || ''; if (name === 'desktop' && ct.includes('text/css')) css.push({ url: r.url(), body: await r.text() }); } catch (e) {} });
      let resp = null;
      try { resp = await page.goto(url, { waitUntil: 'networkidle', timeout: 90000 }); } catch (e) { log.push('[goto] ' + e.message); }
      if (resp) { log.push('[status] ' + resp.status()); if (name === 'desktop') { try { fs.writeFileSync(`${OUT}/${slug}-raw.html`, await resp.text()); } catch (e) { log.push('[raw] ' + e.message); } } }
      await page.waitForTimeout(9000);
      const geo = await page.evaluate(() => {
        const out = { bodyClass: document.body.className, docWidth: document.documentElement.clientWidth, scrollHeight: document.documentElement.scrollHeight };
        const wrap = document.querySelector('#gsr-nhbt-wrap') || document.querySelector('.gsr-article') || document.querySelector('.gsr-sub');
        const chain = []; let n = wrap;
        while (n && n !== document.documentElement && chain.length < 14) {
          const cs = getComputedStyle(n); const r = n.getBoundingClientRect();
          chain.push({ tag: n.tagName, id: n.id, cls: (n.className || '').toString().slice(0, 120), left: Math.round(r.left), width: Math.round(r.width), maxWidth: cs.maxWidth, padding: cs.padding, bg: cs.backgroundColor, overflow: cs.overflow });
          n = n.parentElement;
        }
        out.chain = chain;
        const f = document.getElementById('gsr-nhbt');
        if (f) {
          const r = f.getBoundingClientRect(); out.iframe = { top: Math.round(r.top + scrollY), width: Math.round(r.width), height: Math.round(r.height) };
          try { const d = f.contentDocument; out.inner = { ready: d.readyState, rows: d.querySelectorAll('#bill-list li.bill').length, open: (d.querySelector('li.bill.open') || {}).id || null, openTopInViewport: d.querySelector('li.bill.open') ? Math.round(r.top + d.querySelector('li.bill.open').getBoundingClientRect().top) : null, htmlClass: d.documentElement.className, loading: (d.getElementById('loading') || {}).textContent, loadingHidden: (d.getElementById('loading') || {}).hidden, summary: (d.getElementById('summary') || {}).textContent, stamp: (d.getElementById('stamp') || {}).textContent, tabs: d.querySelectorAll('#lead-tabs .tab').length, docW: d.documentElement.clientWidth, docH: d.documentElement.scrollHeight, bodyH: Math.ceil(d.body.getBoundingClientRect().height), innerOverflowX: d.documentElement.scrollWidth - d.documentElement.clientWidth }; out.pageOverflowX = document.documentElement.scrollWidth - document.documentElement.clientWidth; out.hash = location.hash; out.scrollY = Math.round(scrollY); } catch (e) { out.inner = 'no access: ' + e.message; }
        }
        out.bodyFont = getComputedStyle(document.body).fontFamily; out.bodyBg = getComputedStyle(document.body).backgroundColor;
        return out;
      });
      await page.screenshot({ path: `${OUT}/${slug}-${name}-fold.jpg`, type: 'jpeg', quality: 72 });
      await page.screenshot({ path: `${OUT}/${slug}-${name}-full.jpg`, type: 'jpeg', quality: 60, fullPage: true });
      if (url.includes('#')) { await page.screenshot({ path: `${OUT}/${slug}-${name}-deeplink.jpg`, type: 'jpeg', quality: 72 }); }
      else if (await page.$('#gsr-nhbt')) {
        await page.evaluate(() => window.scrollTo(0, document.getElementById('gsr-nhbt').getBoundingClientRect().top + scrollY - 120));
        await page.waitForTimeout(800);
        await page.screenshot({ path: `${OUT}/${slug}-${name}-tracker.jpg`, type: 'jpeg', quality: 72 });
        if (name === 'desktop') fs.writeFileSync(`${OUT}/${slug}-srcdoc.txt`, await page.evaluate(() => document.getElementById('gsr-nhbt').getAttribute('srcdoc')));
      }
      if (name === 'desktop') { fs.writeFileSync(`${OUT}/${slug}.html`, await page.content()); css.forEach((c, i) => fs.writeFileSync(`${OUT}/${slug}-css-${String(i).padStart(2, '0')}.css`, `/* ${c.url} */\n` + c.body)); }
      fs.writeFileSync(`${OUT}/${slug}-${name}-report.txt`, JSON.stringify(geo, null, 2) + '\n\n' + log.join('\n') + '\n');
      await ctx.close();
    }
  }
  await browser.close();
})().catch(e => { console.error(e); process.exit(1); });
