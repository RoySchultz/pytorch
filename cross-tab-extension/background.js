// Service Worker — manages bookmark-based tab sync

const FOLDER_TO_PHONE = '📱 Naar iPhone';  // 📱 Naar iPhone
const FOLDER_FROM_PHONE = '📲 Van iPhone'; // 📲 Van iPhone

async function findOrCreateFolder(name) {
  const results = await chrome.bookmarks.search({ title: name });
  const folder = results.find(r => !r.url);
  if (folder) return folder;
  return chrome.bookmarks.create({ parentId: '1', title: name });
}

async function pushTabs(tabs) {
  const folder = await findOrCreateFolder(FOLDER_TO_PHONE);

  const children = await chrome.bookmarks.getChildren(folder.id);
  await Promise.all(children.map(c => chrome.bookmarks.remove(c.id)));

  for (const tab of tabs) {
    const url = tab.url ?? '';
    if (!url.startsWith('http://') && !url.startsWith('https://')) continue;
    await chrome.bookmarks.create({
      parentId: folder.id,
      title: tab.title || url,
      url,
    });
  }
}

async function getFromPhone() {
  const folder = await findOrCreateFolder(FOLDER_FROM_PHONE);
  return chrome.bookmarks.getChildren(folder.id);
}

async function clearFromPhone() {
  const folder = await findOrCreateFolder(FOLDER_FROM_PHONE);
  const children = await chrome.bookmarks.getChildren(folder.id);
  await Promise.all(children.map(c => chrome.bookmarks.remove(c.id)));
}

chrome.runtime.onMessage.addListener((msg, _sender, sendResponse) => {
  async function handle() {
    switch (msg.type) {
      case 'PUSH_CURRENT': {
        const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
        await pushTabs([tab]);
        return { ok: true };
      }
      case 'PUSH_ALL': {
        const tabs = await chrome.tabs.query({ currentWindow: true });
        await pushTabs(tabs);
        return { ok: true };
      }
      case 'GET_FROM_PHONE': {
        const bookmarks = await getFromPhone();
        return { ok: true, bookmarks };
      }
      case 'OPEN_BOOKMARK': {
        await chrome.tabs.create({ url: msg.url });
        return { ok: true };
      }
      case 'OPEN_ALL_FROM_PHONE': {
        const bookmarks = await getFromPhone();
        for (const b of bookmarks) {
          if (b.url) await chrome.tabs.create({ url: b.url });
        }
        return { ok: true };
      }
      case 'CLEAR_FROM_PHONE': {
        await clearFromPhone();
        return { ok: true };
      }
      default:
        return { ok: false, error: 'Unknown message type' };
    }
  }

  handle().then(sendResponse).catch(e => sendResponse({ ok: false, error: e.message }));
  return true;
});
