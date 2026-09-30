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
    inner = html.replace('<meta name="data-base" content="../data/">',
                         f'<meta name="data-base" content="{DATA}">\n  <meta name="canonical-base" content="{CANON}">')
    inner = inner.replace('<link rel="stylesheet" href="style.css">',
                          f'<link rel="stylesheet" href="{cdn}style.css" onerror="this.onerror=null;this.href=\'{cdn2}style.css\'">')
    inner = inner.replace('<script src="app.js"></script>',
                          f"<script src=\"{cdn}app.js\" onerror=\"var s=document.createElement('script');s.src='{cdn2}app.js';"
                          "s.onerror=function(){var l=document.getElementById('loading');if(l){l.className='status-line err';"
                          "l.textContent='The tracker script could not load. Open the project on GitHub: github.com/dexterdow33/BlogPostPreviewer';}};"
                          "document.head.appendChild(s)\"></script>")
    inner = inner.replace('<a href="https://github.com/dexterdow33/BlogPostPreviewer" rel="noopener">GitHub</a>',
                          '<a href="https://github.com/dexterdow33/BlogPostPreviewer" rel="noopener" target="_blank">GitHub</a>')
    inner = inner.replace('<a href="https://granitestatereport.com" rel="noopener">granitestatereport.com</a>',
                          '<a href="https://granitestatereport.com" rel="noopener" target="_top">granitestatereport.com</a>')
    assert cdn in inner and cdn2 in inner and DATA in inner, "index.html markers not found"
    srcdoc = inner.replace("&", "&amp;").replace('"', "&quot;")
    head = (ROOT / "site" / "wp-page-head.html").read_text()
    tail = (ROOT / "site" / "wp-page-tail.html").read_text()
    bridge = """<script>
(function () {
  var f = document.getElementById("gsr-nhbt");
  if (!f) return;
  var ready = false;
  function send() { if (ready && f.contentWindow && location.hash) f.contentWindow.postMessage({ nhbt: "open", hash: location.hash }, "*"); }
  window.addEventListener("message", function (ev) {
    var d = ev.data || {};
    if (d.nhbt === "ready") { ready = true; send(); }
    if (d.nhbt === "hash" && typeof d.hash === "string") { try { history.replaceState(null, "", location.pathname + location.search + d.hash); } catch (e) {} }
  });
  window.addEventListener("hashchange", send);
})();
</script>
<!-- /wp:html -->"""
    return head + f'<iframe id="gsr-nhbt" title="NH Bill Tracker" loading="eager" referrerpolicy="no-referrer" srcdoc="{srcdoc}"></iframe>' + tail + bridge


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("usage: build_wp_embed.py <commit-sha>")
    sys.stdout.write(build(sys.argv[1]))
