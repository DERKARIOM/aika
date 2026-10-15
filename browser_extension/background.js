// Aika – Téléchargements (Manifest V3 service worker).
//
// When a download starts in the browser, it is paused and its final link
// (after the browser followed the redirections) is offered to Aika through
// its local receiver on 127.0.0.1. If Aika accepts it, the browser's copy is
// cancelled; otherwise (Aika closed, link refused, file needing the browser
// session...) the browser simply continues. A download is never lost.
//
// Privacy: only the link, the file name and the size are sent, and only to
// this computer. Cookies, page contents and history are never read.

const BRIDGE = 'http://127.0.0.1:53319';
const DEFAULTS = { enabled: true, token: '', minSizeMb: 1, includeIncognito: false };

async function getSettings() {
  return { ...DEFAULTS, ...(await chrome.storage.local.get(DEFAULTS)) };
}

/** Calls Aika's local receiver. Never throws: status 0 = Aika unreachable. */
async function callAika(path, { method = 'GET', token, body, timeoutMs = 30000 } = {}) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await fetch(BRIDGE + path, {
      method,
      headers: {
        'X-Aika-Token': token || '',
        ...(body ? { 'Content-Type': 'application/json' } : {}),
      },
      body: body ? JSON.stringify(body) : undefined,
      credentials: 'omit',
      cache: 'no-store',
      signal: controller.signal,
    });
    let json = {};
    try {
      json = await response.json();
    } catch (_) {
      // Empty or non-JSON answer.
    }
    return { status: response.status, json };
  } catch (_) {
    return { status: 0, json: { error: 'unreachable' } };
  } finally {
    clearTimeout(timer);
  }
}

function flashBadge(text, color) {
  chrome.action.setBadgeBackgroundColor({ color });
  chrome.action.setBadgeText({ text });
  setTimeout(() => chrome.action.setBadgeText({ text: '' }), 4000);
}

async function remember(result) {
  await chrome.storage.local.set({ lastResult: { ...result, at: Date.now() } });
}

async function takeOver(item) {
  const settings = await getSettings();
  if (!settings.enabled || !settings.token) return;
  // Our own fallback downloads, private windows (unless allowed), finished items.
  if (item.byExtensionId === chrome.runtime.id) return;
  if (item.incognito && !settings.includeIncognito) return;
  if (item.state && item.state !== 'in_progress') return;

  const url = item.finalUrl || item.url;
  // blob:, data:, file: links only exist inside the browser.
  if (!/^https?:\/\//i.test(url)) return;

  const size = item.totalBytes > 0 ? item.totalBytes : item.fileSize > 0 ? item.fileSize : null;
  if (size !== null && size < settings.minSizeMb * 1024 * 1024) return;

  try {
    await chrome.downloads.pause(item.id);
  } catch (_) {
    return; // Already finished or not pausable: leave it to the browser.
  }

  const fileName = item.filename ? item.filename.split(/[\\/]/).pop() : '';
  const answer = await callAika('/aika/download', {
    method: 'POST',
    token: settings.token,
    body: { url, fileName: fileName || undefined, size: size ?? undefined },
  });

  if (answer.status === 202) {
    await chrome.downloads.cancel(item.id).catch(() => {});
    await chrome.downloads.erase({ id: item.id }).catch(() => {});
    flashBadge('✓', '#1D9E75');
    await remember({ ok: true, fileName: answer.json.fileName || fileName });
    return;
  }

  // Aika did not take it: the browser continues as usual.
  try {
    await chrome.downloads.resume(item.id);
  } catch (_) {
    await chrome.downloads.cancel(item.id).catch(() => {});
    await chrome.downloads.download({ url }).catch(() => {});
  }
  if (answer.status === 401) flashBadge('!', '#C62828');
  await remember({ ok: false, reason: answer.json.error || (answer.status === 0 ? 'unreachable' : String(answer.status)) });
}

chrome.downloads.onCreated.addListener((item) => {
  takeOver(item).catch(() => {});
});

// Used by the popup to check the connection with the code being typed.
chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (message && message.type === 'ping') {
    callAika('/aika/ping', { token: message.token, timeoutMs: 5000 }).then(sendResponse);
    return true; // Answer asynchronously.
  }
  return false;
});
