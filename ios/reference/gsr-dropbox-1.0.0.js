/* GSR Drop Box 1.0.0 · Granite State Report
   Drop, paste or pick files of any type (2 GB each, 50 at a time). They upload in 4 MB pieces
   to the site's own storage while the visitor reads, so Send is instant. Nothing is required. */
(function () {
  'use strict';
  var API = (window.GSRDB && window.GSRDB.api) || '/wp-json/gsr-drop/v1/';

  function q(api, path, params) {
    var u = api + path, sep = u.indexOf('?') >= 0 ? '&' : '?';
    if (params) u += sep + Object.keys(params).map(function (k) { return k + '=' + encodeURIComponent(params[k]); }).join('&');
    return u;
  }
  function human(b) {
    var u = ['bytes', 'KB', 'MB', 'GB'], i = 0;
    while (b >= 1024 && i < 3) { b /= 1024; i++; }
    return (i ? b.toFixed(1) : b) + ' ' + u[i];
  }
  function sleep(ms) { return new Promise(function (r) { setTimeout(r, ms); }); }
  function postJSON(url, data) {
    return fetch(url, { method: 'POST', credentials: 'omit', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(data || {}) })
      .then(function (r) { return r.json().catch(function () { return {}; }).then(function (j) { if (!r.ok) { var e = new Error(j.message || ('Server said ' + r.status)); e.status = r.status; throw e; } return j; }); });
  }
  function isEditable(el) {
    if (!el) return false;
    var t = (el.tagName || '').toLowerCase();
    return t === 'textarea' || (t === 'input' && !/^(checkbox|radio|button|submit|file)$/i.test(el.type)) || el.isContentEditable;
  }

  function Box(root) {
    this.root = root;
    this.form = root.getAttribute('data-form');
    this.zone = root.querySelector('.gsrdb-zone');
    this.input = root.querySelector('.gsrdb-input');
    this.list = root.querySelector('.gsrdb-list');
    this.main = root.querySelector('.gsrdb-main');
    this.send = root.querySelector('.gsrdb-send');
    this.status = root.querySelector('.gsrdb-status');
    this.items = [];
    this.token = null;
    this.starting = null;
    this.limits = { chunk: 4194304, maxFile: 2147483648, maxFiles: 50, maxTotal: 10737418240 };
    this.active = 0;
    this.sending = false;
    this.bind();
    this.refresh();
  }

  Box.prototype.say = function (msg, bad) {
    this.status.textContent = msg || '';
    this.status.className = 'gsrdb-status' + (bad ? ' is-bad' : '');
  };

  Box.prototype.session = function () {
    var self = this;
    if (this.token) return Promise.resolve(this.token);
    if (!this.starting) {
      var hp = this.root.querySelector('.gsrdb-website');
      this.starting = postJSON(q(API, 'start'), { form: this.form, website: hp ? hp.value : '' }).then(function (j) {
        self.token = j.token;
        self.limits = { chunk: j.chunk, maxFile: j.maxFile, maxFiles: j.maxFiles, maxTotal: j.maxTotal };
        return j.token;
      }, function (e) { self.starting = null; throw e; });
    }
    return this.starting;
  };

  Box.prototype.live = function () { return this.items.filter(function (it) { return !it.removed && it.state !== 'error'; }); };

  Box.prototype.add = function (files) {
    var self = this, added = 0;
    Array.prototype.forEach.call(files || [], function (file) {
      if (!file) return;
      var live = self.live();
      var total = live.reduce(function (s, it) { return s + it.file.size; }, 0);
      var it = { file: file, sent: 0, id: null, state: 'queued', removed: false };
      if (live.length >= self.limits.maxFiles) { it.state = 'error'; it.err = 'Over the 50-file limit for one send. Send these, then the rest.'; }
      else if (file.size > self.limits.maxFile) { it.state = 'error'; it.err = 'Larger than 2 GB. Use a share link or mail it on a drive.'; }
      else if (total + file.size > self.limits.maxTotal) { it.state = 'error'; it.err = 'Would put this send over 10 GB. Send these first.'; }
      self.items.push(it);
      self.row(it);
      if (it.state !== 'error') added++;
    });
    if (added) { this.say(''); this.pump(); }
    this.refresh();
    return added;
  };

  Box.prototype.row = function (it) {
    var self = this, li = document.createElement('li');
    li.className = 'gsrdb-item';
    li.innerHTML = '<span class="gsrdb-name"></span><span class="gsrdb-meta"></span><span class="gsrdb-bar"><span></span></span><button type="button" class="gsrdb-x" aria-label="Remove">&times;</button>';
    li.querySelector('.gsrdb-name').textContent = it.file.name || 'pasted-file';
    li.querySelector('.gsrdb-x').addEventListener('click', function () { self.remove(it); });
    it.li = li;
    this.list.appendChild(li);
    this.paint(it);
  };

  Box.prototype.paint = function (it) {
    if (!it.li) return;
    var meta = it.li.querySelector('.gsrdb-meta'), bar = it.li.querySelector('.gsrdb-bar span');
    var pct = it.file.size ? Math.floor(100 * it.sent / it.file.size) : 100;
    it.li.className = 'gsrdb-item is-' + it.state;
    bar.style.width = (it.state === 'done' ? 100 : pct) + '%';
    var size = human(it.file.size);
    meta.textContent = it.state === 'error' ? (size + ' · ' + it.err)
      : it.state === 'done' ? (size + ' · Uploaded')
      : it.state === 'uploading' ? (size + ' · ' + pct + '%')
      : it.state === 'retry' ? (size + ' · Connection hiccup, retrying')
      : (size + ' · Waiting');
  };

  Box.prototype.remove = function (it) {
    it.removed = true;
    if (it.li) it.li.parentNode.removeChild(it.li);
    if (it.id !== null && this.token) postJSON(q(API, 'remove'), { token: this.token, file: it.id }).catch(function () {});
    this.refresh();
  };

  Box.prototype.pump = function () {
    var self = this;
    while (this.active < 2) {
      var next = this.items.filter(function (it) { return !it.removed && it.state === 'queued'; })[0];
      if (!next) break;
      this.active++;
      next.state = 'uploading';
      this.paint(next);
      this.upload(next).then(function () {}, function () {}).then(function () { self.active--; self.refresh(); self.pump(); });
    }
  };

  Box.prototype.upload = function (it) {
    var self = this;
    return this.session().then(function (token) {
      return postJSON(q(API, 'add'), { token: token, name: it.file.name || 'pasted-file', size: it.file.size, type: it.file.type || '' }).then(function (j) {
        it.id = j.id;
        return self.chunks(it, token);
      });
    }).then(function () {
      if (it.removed) return;
      it.state = 'done'; self.paint(it);
    }, function (e) {
      if (it.removed) return;
      it.state = 'error'; it.err = (e && e.message) || 'Upload failed.'; self.paint(it);
    });
  };

  Box.prototype.chunks = function (it, token) {
    var self = this, size = it.file.size, tries = 0;
    function step() {
      if (it.removed) return Promise.resolve();
      if (it.sent >= size && size > 0) return Promise.resolve();
      if (size === 0) return Promise.resolve();
      var end = Math.min(size, it.sent + self.limits.chunk);
      var url = q(API, 'chunk', { token: token, file: it.id, offset: it.sent });
      return fetch(url, { method: 'POST', credentials: 'omit', headers: { 'Content-Type': 'application/octet-stream' }, body: it.file.slice(it.sent, end) })
        .then(function (r) {
          return r.json().catch(function () { return {}; }).then(function (j) {
            if (r.status === 409 && typeof j.received === 'number') { it.sent = j.received; return step(); }
            if (!r.ok) {
              var e = new Error(j.message || ('Server said ' + r.status)); e.status = r.status;
              if (r.status >= 500 && r.status !== 507) throw e; /* retryable */
              e.fatal = true; throw e;
            }
            tries = 0;
            if (it.state === 'retry') it.state = 'uploading';
            it.sent = j.received; self.paint(it); self.refresh();
            return step();
          });
        })
        .catch(function (e) {
          if (e && e.fatal) throw e;
          if (++tries > 8) throw new Error('The connection kept dropping. Try again, or use a share link.');
          it.state = 'retry'; self.paint(it);
          return sleep(Math.min(30000, 1000 * Math.pow(2, tries))).then(step);
        });
    }
    return step();
  };

  Box.prototype.fields = function () {
    var out = {};
    Array.prototype.forEach.call(this.root.querySelectorAll('[data-k]'), function (el) {
      out[el.getAttribute('data-k')] = el.type === 'checkbox' ? el.checked : el.value;
    });
    return out;
  };

  Box.prototype.hasText = function () {
    if (this.main.value.trim()) return true;
    return Array.prototype.some.call(this.root.querySelectorAll('[data-k]'), function (el) {
      return el.type !== 'checkbox' && el.tagName !== 'SELECT' && el.value.trim();
    });
  };

  Box.prototype.refresh = function () {
    var live = this.live();
    var pending = live.filter(function (it) { return it.state !== 'done'; });
    this.send.disabled = this.sending || (!live.length && !this.hasText());
    if (this.sending) return;
    if (pending.length) {
      var tot = 0, got = 0;
      live.forEach(function (it) { tot += it.file.size; got += Math.min(it.sent, it.file.size); });
      this.send.setAttribute('data-wait', tot ? Math.floor(100 * got / tot) + '%' : '');
    } else this.send.removeAttribute('data-wait');
  };

  Box.prototype.submit = function () {
    var self = this;
    if (this.sending) return;
    this.sending = true;
    this.send.disabled = true;
    var label = this.send.textContent;
    function wait() {
      var live = self.live(), pend = live.filter(function (it) { return it.state !== 'done'; });
      if (!pend.length) return Promise.resolve();
      var tot = 0, got = 0;
      live.forEach(function (it) { tot += it.file.size; got += Math.min(it.sent, it.file.size); });
      self.say('Finishing uploads: ' + (tot ? Math.floor(100 * got / tot) : 100) + '%. Keep this page open.');
      return sleep(700).then(wait);
    }
    var bad = this.items.filter(function (it) { return !it.removed && it.state === 'error'; });
    wait().then(function () { return self.session(); }).then(function (token) {
      self.say('Sending…');
      return postJSON(q(API, 'finish'), { token: token, main: self.main.value, fields: self.fields() });
    }).then(function () {
      self.root.classList.add('is-sent');
      var n = self.live().length;
      self.root.innerHTML = '<div class="gsrdb-done"><p class="gsrdb-zone-big">Sent. Thank you.</p><p>' +
        (n ? n + ' file' + (n === 1 ? '' : 's') + ' and your note reached the editor.' : 'Your message reached the editor.') +
        (bad.length ? ' ' + bad.length + ' file' + (bad.length === 1 ? '' : 's') + ' could not be sent; see the note above it.' : '') +
        ' Nothing is published without being checked first.</p><p><a href="" class="gsrdb-again">Send something else</a></p></div>';
      window.removeEventListener('beforeunload', self.unload);
    }, function (e) {
      self.sending = false;
      self.send.textContent = label;
      self.refresh();
      if (e && e.status === 410) { self.token = null; self.starting = null; }
      self.say((e && e.message) || 'Could not send. Check your connection and press the button again.', true);
    });
  };

  Box.prototype.walk = function (entries) {
    /* Folders dropped from a desktop: read every file inside. */
    var files = [];
    function readEntry(entry) {
      if (!entry) return Promise.resolve();
      if (entry.isFile) return new Promise(function (res) { entry.file(function (f) { files.push(f); res(); }, function () { res(); }); });
      if (entry.isDirectory) {
        var reader = entry.createReader(), all = [];
        return new Promise(function (res) {
          (function more() {
            reader.readEntries(function (batch) {
              if (!batch.length) { Promise.all(all.map(readEntry)).then(res); return; }
              all = all.concat(Array.prototype.slice.call(batch)); more();
            }, function () { res(); });
          })();
        });
      }
      return Promise.resolve();
    }
    return Promise.all(entries.map(readEntry)).then(function () { return files; });
  };

  Box.prototype.fromDrop = function (dt) {
    var self = this;
    var items = dt.items ? Array.prototype.slice.call(dt.items) : [];
    var entries = items.map(function (i) { return i.webkitGetAsEntry ? i.webkitGetAsEntry() : null; }).filter(Boolean);
    if (entries.length && entries.some(function (e) { return e.isDirectory; })) {
      this.walk(entries).then(function (files) { self.add(files); });
    } else if (dt.files && dt.files.length) {
      this.add(dt.files);
    } else {
      var text = dt.getData && dt.getData('text');
      if (text) { this.main.value += (this.main.value ? '\n\n' : '') + text; this.refresh(); }
    }
  };

  Box.prototype.bind = function () {
    var self = this;
    this.unload = function (e) {
      if (self.live().some(function (it) { return it.state !== 'done'; }) || (self.sending)) { e.preventDefault(); e.returnValue = ''; }
    };
    window.addEventListener('beforeunload', this.unload);

    this.zone.addEventListener('click', function (e) { if (e.target !== self.input) self.input.click(); });
    this.zone.addEventListener('keydown', function (e) { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); self.input.click(); } });
    this.input.addEventListener('change', function () { self.add(self.input.files); self.input.value = ''; });
    this.send.addEventListener('click', function () { self.submit(); });
    this.root.addEventListener('input', function () { self.refresh(); });
    this.root.addEventListener('change', function () { self.refresh(); });
    this.root.addEventListener('click', function (e) {
      if (e.target && e.target.classList && e.target.classList.contains('gsrdb-again')) { e.preventDefault(); window.location.reload(); }
    });

    /* Drop anywhere on the page */
    var overlay = document.createElement('div'), depth = 0;
    overlay.className = 'gsrdb-overlay';
    overlay.innerHTML = '<div>Drop it here.<small>It goes straight into the box.</small></div>';
    document.body.appendChild(overlay);
    function hasFiles(e) {
      var t = e.dataTransfer && e.dataTransfer.types;
      if (!t) return false;
      for (var i = 0; i < t.length; i++) if (t[i] === 'Files') return true;
      return false;
    }
    document.addEventListener('dragenter', function (e) { if (!hasFiles(e)) return; depth++; overlay.classList.add('is-on'); self.zone.classList.add('is-over'); });
    document.addEventListener('dragleave', function (e) { if (!hasFiles(e)) return; depth = Math.max(0, depth - 1); if (!depth) { overlay.classList.remove('is-on'); self.zone.classList.remove('is-over'); } });
    document.addEventListener('dragover', function (e) { if (hasFiles(e)) e.preventDefault(); });
    document.addEventListener('drop', function (e) {
      if (!hasFiles(e)) return;
      e.preventDefault();
      depth = 0; overlay.classList.remove('is-on'); self.zone.classList.remove('is-over');
      self.fromDrop(e.dataTransfer);
      self.scrollIn();
    });

    /* Paste anywhere on the page: files go into the box; text goes into the big text box. */
    document.addEventListener('paste', function (e) {
      var cd = e.clipboardData;
      if (!cd) return;
      var files = cd.files && cd.files.length ? Array.prototype.slice.call(cd.files) : [];
      if (!files.length && cd.items) {
        Array.prototype.forEach.call(cd.items, function (i) { if (i.kind === 'file') { var f = i.getAsFile(); if (f) files.push(f); } });
      }
      if (files.length) {
        e.preventDefault();
        files = files.map(function (f, n) {
          if (f.name && f.name !== 'image.png') return f;
          var ext = (f.type.split('/')[1] || 'bin').replace('jpeg', 'jpg');
          try { return new File([f], 'pasted-' + new Date().toISOString().replace(/[:.]/g, '-') + (n ? '-' + n : '') + '.' + ext, { type: f.type }); } catch (x) { return f; }
        });
        self.add(files);
        self.scrollIn();
        return;
      }
      if (isEditable(document.activeElement)) return; /* normal paste into a box they clicked */
      var text = cd.getData('text/plain');
      if (text) {
        e.preventDefault();
        self.main.value += (self.main.value ? '\n\n' : '') + text;
        self.refresh();
        self.scrollIn();
        self.say('Pasted into the box. Press ' + self.send.textContent + ' when you are ready.');
      }
    });

    this.carry();
  };

  Box.prototype.scrollIn = function () {
    var r = this.root.getBoundingClientRect();
    if (r.top > window.innerHeight || r.bottom < 0) this.root.scrollIntoView({ behavior: 'smooth', block: 'start' });
  };

  /* Files stashed in this browser by other pages of the site (database "gsr-drop") are picked up here. */
  Box.prototype.carry = function () {
    var self = this;
    if (!('indexedDB' in window) || !indexedDB.databases) return;
    indexedDB.databases().then(function (dbs) {
      if (!dbs.some(function (d) { return d.name === 'gsr-drop'; })) return;
      var r = indexedDB.open('gsr-drop', 1);
      r.onsuccess = function () {
        var db = r.result;
        if (!db.objectStoreNames.contains('files')) return;
        var rq = db.transaction('files', 'readonly').objectStore('files').getAll();
        rq.onsuccess = function () {
          var rows = rq.result || [];
          if (!rows.length) return;
          var files = rows.map(function (x) { return (x instanceof File) ? x : new File([x.blob], x.name || 'file', { type: x.type || '' }); });
          self.add(files);
          db.transaction('files', 'readwrite').objectStore('files').clear();
          self.say('Carried ' + files.length + ' file' + (files.length === 1 ? '' : 's') + ' over from the page you dropped on.');
        };
      };
    }).catch(function () {});
  };

  function boot() {
    Array.prototype.forEach.call(document.querySelectorAll('.gsrdb[data-form]'), function (el) {
      if (!el.__gsrdb) el.__gsrdb = new Box(el);
    });
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot); else boot();
})();
