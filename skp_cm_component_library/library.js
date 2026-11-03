// SKP CM Component Library — window (spec §4.3 layout A + update spec §5). Ruby calls the window.* functions below.
(function () {
  var ALL = '';
  var CHANGED = '\u0001changed'; // pseudo category "ใหม่/อัปเดต"
  var BLANK = 'data:image/gif;base64,R0lGODlhAQABAAAAACH5BAEKAAEALAAAAAABAAEAAAICTAEAOw==';
  var BADGE = { 'new': 'ใหม่', updated: 'อัปเดต' };
  var state = { index: null, baseUrl: '', category: ALL, query: '', changes: {} };
  var $ = function (id) { return document.getElementById(id); };

  function call(name) {
    var args = Array.prototype.slice.call(arguments, 1);
    try {
      sketchup[name].apply(sketchup, args);
    } catch (e) {
      showMessage('ติดต่อ SketchUp ไม่ได้: ' + e.message, true);
    }
  }

  // text: message; button: { label, action } or null
  function showMessage(text, isError, button) {
    $('body').hidden = true;
    $('notices').hidden = true;
    $('message').hidden = false;
    $('message').className = 'message' + (isError ? ' error' : '');
    $('message-text').textContent = text;
    var btn = $('message-btn');
    btn.hidden = !button;
    if (button) {
      btn.textContent = button.label;
      btn.onclick = function () { call(button.action); };
    }
  }

  function el(tag, cls, text) {
    var e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text != null) e.textContent = text;
    return e;
  }

  function setStatus(text, warn) {
    $('status').textContent = text || '';
    $('status').className = warn ? 'warn' : '';
  }

  function matches(item) {
    if (state.category === CHANGED) {
      if (!state.changes[item.code]) return false;
    } else if (state.category !== ALL && item.category !== state.category) {
      return false;
    }
    var q = state.query;
    return !q || item.code.toLowerCase().indexOf(q) >= 0 || (item.name || '').toLowerCase().indexOf(q) >= 0;
  }

  function catButton(cat, label, count) {
    var b = el('button', 'cat' + (cat === state.category ? ' on' : '') + (cat === CHANGED ? ' changed' : ''));
    b.appendChild(el('span', null, label));
    b.appendChild(el('span', 'n', String(count)));
    b.onclick = function () { state.category = cat; render(); };
    return b;
  }

  function renderCats() {
    var nav = $('cats');
    nav.textContent = '';
    var counts = {};
    state.index.items.forEach(function (i) { counts[i.category] = (counts[i.category] || 0) + 1; });
    nav.appendChild(catButton(ALL, 'ทั้งหมด', state.index.items.length));
    var changed = Object.keys(state.changes).length;
    if (changed) nav.appendChild(catButton(CHANGED, 'ใหม่/อัปเดต', changed));
    state.index.categories.forEach(function (cat) { nav.appendChild(catButton(cat, cat, counts[cat] || 0)); });
  }

  function renderGrid() {
    var grid = $('grid');
    grid.textContent = '';
    var shown = state.index.items.filter(matches);
    shown.forEach(function (item) {
      var t = el('button', 'tile');
      t.title = item.code + ' — ' + (item.name || '');
      t.dataset.code = item.code;
      var img = el('img', 'thumb');
      img.alt = '';
      img.loading = 'lazy';
      img.src = state.baseUrl + '/' + item.version + '/thumbs/' + encodeURIComponent(item.file) + '.png';
      img.onerror = function () { img.onerror = null; img.src = BLANK; }; // offline / missing → empty frame
      t.appendChild(img);
      var change = state.changes[item.code];
      if (change) t.appendChild(el('span', 'badge ' + change, BADGE[change]));
      t.appendChild(el('div', 'code', item.code));
      t.appendChild(el('div', 'name', item.name || ''));
      t.onclick = function () {
        if (t.classList.contains('loading')) return;
        t.classList.add('loading');
        call('place', item.code);
      };
      grid.appendChild(t);
    });
    if (!shown.length) grid.appendChild(el('div', 'name', 'ไม่พบ component ที่ตรงกับคำค้น'));
  }

  function render() {
    if (state.category === CHANGED && !Object.keys(state.changes).length) state.category = ALL;
    renderCats();
    renderGrid();
  }

  function renderChanges() {
    var counts = { 'new': 0, updated: 0 };
    Object.keys(state.changes).forEach(function (c) { counts[state.changes[c]]++; });
    $('changes').hidden = !(counts['new'] + counts.updated);
    $('changes-text').textContent = 'component ใหม่ ' + counts['new'] + ' · อัปเดต ' + counts.updated;
    $('notices').hidden = $('changes').hidden && $('outdated').hidden;
  }

  window.showAuth = function (status, missingMessage) {
    if (!status.hub) return showMessage(missingMessage, true);
    if (!status.logged_in) {
      return showMessage('ต้อง login SKP CM Extensions Hub ก่อนใช้งาน', false, { label: 'Login', action: 'login' });
    }
    if (!state.index) showMessage('กำลังโหลดรายการ…');
  };

  window.showIndex = function (index, offline, baseUrl, changes) {
    state.index = index;
    state.baseUrl = baseUrl;
    state.changes = changes || {};
    if (state.category !== ALL && state.category !== CHANGED && index.categories.indexOf(state.category) < 0) {
      state.category = ALL;
    }
    $('message').hidden = true;
    $('body').hidden = false;
    var d = new Date(index.published_at);
    $('updated').textContent = 'Library อัปเดต ' + (isNaN(d) ? index.published_at : d.toLocaleDateString('th-TH'));
    setStatus(offline ? 'offline — ใช้รายการที่เก็บไว้' : '', offline);
    renderChanges();
    render();
  };

  window.showChanges = function (changes) {
    state.changes = changes || {};
    renderChanges();
    if (state.index) render();
  };

  // outdated: { code: [definition names] } in the active model
  window.showOutdated = function (outdated) {
    var codes = Object.keys(outdated || {});
    $('outdated').hidden = !codes.length;
    var list = codes.slice(0, 6).join(', ') + (codes.length > 6 ? ' …และอีก ' + (codes.length - 6) : '');
    $('outdated-text').textContent = 'ไฟล์นี้มี component เวอร์ชันเก่า ' + codes.length + ' ตัว: ' + list;
    $('update-btn').disabled = false;
    $('notices').hidden = $('changes').hidden && $('outdated').hidden;
  };

  window.updateDone = function (ok, message) {
    $('update-btn').disabled = false;
    $('update-btn').textContent = 'อัปเดตในงาน';
    setStatus(message, !ok);
  };

  window.showError = function (message) {
    if (state.index) return setStatus(message, true);
    showMessage(message, true, { label: 'ลองใหม่', action: 'refresh' });
  };

  window.placeDone = function (code, ok, message) {
    var tiles = document.querySelectorAll('.tile.loading');
    for (var i = 0; i < tiles.length; i++) {
      if (tiles[i].dataset.code === code) tiles[i].classList.remove('loading');
    }
    setStatus(ok ? '' : message, !ok);
  };

  $('search').addEventListener('input', function (e) {
    state.query = e.target.value.trim().toLowerCase();
    if (state.index) renderGrid();
  });
  $('refresh').onclick = function () { call('refresh'); };
  $('update-btn').onclick = function () {
    $('update-btn').disabled = true;
    $('update-btn').textContent = 'กำลังอัปเดต…';
    call('update');
  };
  $('ack-btn').onclick = function () { call('ack'); };
  call('ready');
})();
