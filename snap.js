// Photograph pages at desktop and phone width; save HTML, CSS and layout facts.
const { chromium } = require('playwright');
const fs = require('fs');
const OUT = process.env.OUT;
const targets = fs.readFileSync('targets.txt', 'utf8').split('\n').map(s => s.trim()).filter(s => s && !s.startsWith('#'));
(async () => {
  const browser = await chromium.launch();
  for (const url of targets) {
    const slug = url.replace(/^https?:\/\//, '').replace(/[^a-z0-9]+/gi, '_').replace(/_+$/, '').slice(0, 60);
    for (const [name, vp, mobile] of [['desktop', { width: 1440, height: 900 }, false], ['mobile', { width: 390, height: 844 }, true]]) {
      const ctx = await browser.newContext({ viewport: vp, isMobile: mobile, hasTouch: mobile, deviceScaleFactor: 1 });
      const page = await ctx.newPage();
      const css = []; const log = [];
      page.on('console', m => log.push(`[${m.type()}] ${m.text()}`));
      page.on('pageerror', e => log.push(`[pageerror] ${e.message}`));
      page.on('requestfailed', r => log.push(`[failed] ${r.url()} ${r.failure() && r.failure().errorText}`));
      page.on('response', async r => { try { const ct = r.headers()['content-type'] || ''; if (name === 'desktop' && ct.includes('text/css')) css.push({ url: r.url(), body: await r.text() }); } catch (e) {} });
      try { await page.goto(url, { waitUntil: 'networkidle', timeout: 90000 }); } catch (e) { log.push('[goto] ' + e.message); }
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
          try { const d = f.contentDocument; out.inner = { ready: d.readyState, rows: d.querySelectorAll('#bills-body tr, .bill-row').length, loading: (d.getElementById('loading') || {}).textContent, meta: (d.getElementById('meta') || {}).textContent, docW: d.documentElement.clientWidth, docH: d.documentElement.scrollHeight }; } catch (e) { out.inner = 'no access: ' + e.message; }
        }
        out.bodyFont = getComputedStyle(document.body).fontFamily; out.bodyBg = getComputedStyle(document.body).backgroundColor;
        return out;
      });
      await page.screenshot({ path: `${OUT}/${slug}-${name}-fold.jpg`, type: 'jpeg', quality: 72 });
      await page.screenshot({ path: `${OUT}/${slug}-${name}-full.jpg`, type: 'jpeg', quality: 60, fullPage: true });
      const el = await page.$('#gsr-nhbt-wrap');
      if (el) { await el.scrollIntoViewIfNeeded(); await page.waitForTimeout(800); await el.screenshot({ path: `${OUT}/${slug}-${name}-embed.jpg`, type: 'jpeg', quality: 72 }); }
      if (name === 'desktop') { fs.writeFileSync(`${OUT}/${slug}.html`, await page.content()); css.forEach((c, i) => fs.writeFileSync(`${OUT}/${slug}-css-${String(i).padStart(2, '0')}.css`, `/* ${c.url} */\n` + c.body)); }
      fs.writeFileSync(`${OUT}/${slug}-${name}-report.txt`, JSON.stringify(geo, null, 2) + '\n\n' + log.join('\n') + '\n');
      await ctx.close();
    }
  }
  await browser.close();
})().catch(e => { console.error(e); process.exit(1); });
