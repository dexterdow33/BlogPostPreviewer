#!/usr/bin/env python3
"""
build_wp_embed.py - build the WordPress "Custom HTML" block that embeds the NH Bill
Tracker on granitestatereport.com/nh-bill-tracker/.

    python3 scripts/build_wp_embed.py <commit-sha> > /tmp/nh-bill-tracker-block.html

The block wraps an <iframe srcdoc="..."> holding nh-bills/index.html. Inside it,
style.css and app.js load from jsDelivr pinned to <commit-sha> (with statically.io
as a fallback CDN), and the data loads from raw.githubusercontent.com on master,
so nightly refreshes appear without touching the page. When nh-bills/ changes,
rebuild with the new commit sha and paste the block into the page (Custom HTML
block), then add a line to the page's version log.

The GSR wrapper markup (masthead, intro, notes) lives in site/wp-page-head.html
and site/wp-page-tail.html.
"""
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
DATA = "https://raw.githubusercontent.com/dexterdow33/BlogPostPreviewer/master/data/"
CANON = "https://granitestatereport.com/nh-bill-tracker/"


def build(sha: str) -> str:
    html = (ROOT / "nh-bills" / "index.html").read_text()
    cdn = f"https://cdn.jsdelivr.net/gh/dexterdow33/BlogPostPreviewer@{sha}/nh-bills/"
    cdn2 = f"https://cdn.statically.io/gh/dexterdow33/BlogPostPreviewer/{sha}/nh-bills/"
    fail = ("var l=document.getElementById('loading');if(l){l.classList.add('err');"
            "l.textContent='The tracker script could not load. Open the project on GitHub: github.com/dexterdow33/BlogPostPreviewer';}")
    swaps = [
        # Mark the document as embedded before any CSS applies, so the standalone
        # masthead and colophon never flash inside the WordPress page.
        ('<html lang="en">', '<html lang="en" class="embed">'),
        ('<meta name="data-base" content="../data/">',
         f'<meta name="data-base" content="{DATA}">\n  <meta name="canonical-base" content="{CANON}">'),
        ('<link rel="stylesheet" href="style.css">',
         f'<link rel="stylesheet" href="{cdn}style.css" onerror="this.onerror=null;this.href=\'{cdn2}style.css\'">'),
        ('<script src="app.js"></script>',
         f"<script src=\"{cdn}app.js\" onerror=\"var s=document.createElement('script');s.src='{cdn2}app.js';"
         f"s.onerror=function(){{{fail}}};document.head.appendChild(s)\"></script>"),
    ]
    inner = html
    for old, new in swaps:
        assert old in inner, f"index.html marker not found: {old}"
        inner = inner.replace(old, new)
    # srcdoc is an HTML attribute value: escape & first, then quotes and angle
    # brackets. WordPress mangles a raw "<" inside an attribute (fixed by hand in
    # page v1.0.1), so all four are escaped.
    srcdoc = (inner.replace("&", "&amp;").replace('"', "&quot;")
              .replace("<", "&lt;").replace(">", "&gt;"))
    head = (ROOT / "site" / "wp-page-head.html").read_text()
    tail = (ROOT / "site" / "wp-page-tail.html").read_text()
    # Host side of the postMessage bridge in nh-bills/app.js: the tracker reports
    # its height (the host sizes the iframe so the page scrolls as one document),
    # asks the host to scroll to an opened bill (offset for the sticky site
    # header), mirrors the bill hash into the page URL, and receives "open" for
    # deep links such as /nh-bill-tracker/#HB2026. The host says "hello" once it is
    # listening (and again when the frame loads), because on a heavy page the
    # tracker can finish before this script runs; the tracker answers with its
    # height and "ready".
    bridge = """<script>
(function () {
  var f = document.getElementById("gsr-nhbt");
  if (!f) return;
  var ready = false;
  function send() { if (ready && f.contentWindow && location.hash) f.contentWindow.postMessage({ nhbt: "open", hash: location.hash }, "*"); }
  window.addEventListener("message", function (ev) {
    if (ev.source !== f.contentWindow) return;
    var d = ev.data || {};
    if (d.nhbt === "ready") { ready = true; send(); }
    else if (d.nhbt === "height" && d.h > 0) { f.style.setProperty("height", Math.ceil(d.h) + "px", "important"); }
    else if (d.nhbt === "scroll" && typeof d.y === "number") {
      var top = f.getBoundingClientRect().top + window.pageYOffset + d.y - 110;
      window.scrollTo({ top: Math.max(0, top), behavior: "smooth" });
    }
    else if (d.nhbt === "hash" && typeof d.hash === "string") { try { history.replaceState(null, "", location.pathname + location.search + d.hash); } catch (e) {} }
  });
  window.addEventListener("hashchange", send);
  function hello() { try { f.contentWindow.postMessage({ nhbt: "hello" }, "*"); } catch (e) {} }
  hello();
  f.addEventListener("load", hello);
})();
</script>
<!-- /wp:html -->"""
    frame = ('<iframe id="gsr-nhbt" title="NH Bill Tracker" loading="eager" scrolling="no" '
             f'referrerpolicy="no-referrer" style="height:1400px" srcdoc="{srcdoc}"></iframe>')
    return head + frame + tail + bridge


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("usage: build_wp_embed.py <commit-sha>")
    sys.stdout.write(build(sys.argv[1]))
