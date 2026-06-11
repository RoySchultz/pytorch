function send(msg) {
  return new Promise(resolve => chrome.runtime.sendMessage(msg, resolve));
}

function showStatus(el, text, type) {
  el.textContent = text;
  el.className = `status show ${type}`;
  setTimeout(() => { el.className = 'status'; }, 3000);
}

function renderBookmarks(bookmarks) {
  const list = document.getElementById('bookmarkList');

  if (!bookmarks.length) {
    list.innerHTML = `
      <div class="empty">
        Geen tabbladen van iPhone gevonden.<br>
        Sla een pagina op in Chrome iOS<br>
        in de map <strong>"📲 Van iPhone"</strong>.
      </div>`;
    return;
  }

  list.innerHTML = bookmarks.map(b => `
    <div class="bookmark-item">
      <div class="bm-info">
        <div class="bm-title" title="${escHtml(b.title)}">${escHtml(b.title || 'Zonder titel')}</div>
        <div class="bm-url"  title="${escHtml(b.url)}">${escHtml(b.url)}</div>
      </div>
      <button class="btn-open" data-url="${escHtml(b.url)}">Open</button>
    </div>
  `).join('');

  list.querySelectorAll('.btn-open').forEach(btn => {
    btn.addEventListener('click', () => send({ type: 'OPEN_BOOKMARK', url: btn.dataset.url }));
  });
}

function escHtml(str) {
  return (str ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/"/g, '&quot;');
}

async function loadFromPhone() {
  const result = await send({ type: 'GET_FROM_PHONE' });
  if (result?.ok) renderBookmarks(result.bookmarks);
}

document.getElementById('pushCurrent').addEventListener('click', async () => {
  const statusEl = document.getElementById('pushStatus');
  const res = await send({ type: 'PUSH_CURRENT' });
  if (res?.ok) {
    showStatus(statusEl, '✓ Tab geplaatst in bladwijzermap "📱 Naar iPhone"', 'success');
  } else {
    showStatus(statusEl, '✗ ' + (res?.error ?? 'Onbekende fout'), 'error');
  }
});

document.getElementById('pushAll').addEventListener('click', async () => {
  const statusEl = document.getElementById('pushStatus');
  const res = await send({ type: 'PUSH_ALL' });
  if (res?.ok) {
    showStatus(statusEl, '✓ Alle tabs geplaatst in "📱 Naar iPhone"', 'success');
  } else {
    showStatus(statusEl, '✗ ' + (res?.error ?? 'Onbekende fout'), 'error');
  }
});

document.getElementById('openAll').addEventListener('click', async () => {
  const res = await send({ type: 'OPEN_ALL_FROM_PHONE' });
  if (res?.ok) await loadFromPhone();
});

document.getElementById('refresh').addEventListener('click', loadFromPhone);

document.getElementById('clearAll').addEventListener('click', async () => {
  await send({ type: 'CLEAR_FROM_PHONE' });
  await loadFromPhone();
});

loadFromPhone();
