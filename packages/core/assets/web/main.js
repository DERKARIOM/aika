'use strict';

/* ---------------------------------------------------------------------
 * Aika — web receive page
 *
 * All user-facing text lives in one place (TRANSLATIONS below) so that
 * adding a new language later only means adding one more key to this
 * object — no other code needs to change.
 * ------------------------------------------------------------------- */

var BASE_URL = '/api/localsend/v2';

var TRANSLATIONS = {
  fr: {
    title: 'Réception de fichiers',
    description: 'Téléchargez les fichiers partagés avec vous',
    waiting: 'En attente de réponse…',
    empty: 'Aucun fichier disponible pour le moment',
    filesLabel: 'Fichiers',
    totalSizeLabel: 'Taille totale',
    downloadAll: 'Tout télécharger',
    downloadOne: 'Télécharger {name}',
    downloadStarted: 'Téléchargement lancé',
    networkNote: 'Transfert local et sécurisé — vos fichiers restent sur votre réseau local',
    footer: 'Aika — Partage de fichiers rapide et sécurisé',
    enterPin: 'Entrez le code PIN',
    invalidPin: 'Code PIN invalide',
    tooManyAttempts: 'Trop de tentatives, réessayez plus tard',
    rejected: 'Le transfert a été refusé par l’expéditeur',
    errorGeneric: 'Une erreur est survenue ({status})',
    errorNetwork: 'Impossible de contacter l’expéditeur. Vérifiez que vous êtes sur le même réseau local.',
  },
  en: {
    title: 'Receive files',
    description: 'Download the files shared with you',
    waiting: 'Waiting for response…',
    empty: 'No files available right now',
    filesLabel: 'Files',
    totalSizeLabel: 'Total size',
    downloadAll: 'Download all',
    downloadOne: 'Download {name}',
    downloadStarted: 'Download started',
    networkNote: 'Local, secure transfer — your files stay on your local network',
    footer: 'Aika — Fast and secure file sharing',
    enterPin: 'Enter PIN',
    invalidPin: 'Invalid PIN',
    tooManyAttempts: 'Too many attempts, try again later',
    rejected: 'The transfer was rejected by the sender',
    errorGeneric: 'An error occurred ({status})',
    errorNetwork: 'Could not reach the sender. Make sure you are on the same local network.',
  },
};

var SUPPORTED_LANGS = ['fr', 'en'];
var DEFAULT_LANG = 'fr';

/* ---------------------------------------------------------------------
 * File type → icon category
 * ------------------------------------------------------------------- */

var EXTENSION_CATEGORIES = {
  image: ['png', 'jpg', 'jpeg', 'gif', 'bmp', 'webp', 'heic', 'heif', 'svg', 'tiff', 'tif', 'avif'],
  video: ['mp4', 'mov', 'avi', 'mkv', 'webm', 'm4v', 'wmv', 'flv', '3gp'],
  audio: ['mp3', 'wav', 'flac', 'aac', 'ogg', 'm4a', 'wma', 'opus'],
  archive: ['zip', 'rar', '7z', 'tar', 'gz', 'bz2', 'xz', 'tgz'],
  document: ['pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt', 'rtf', 'odt', 'ods', 'odp', 'csv', 'md', 'json', 'xml', 'html', 'htm'],
};

var ICON_PATHS = {
  image:
    '<rect x="3" y="4" width="18" height="16" rx="2"/>' +
    '<circle cx="8.5" cy="9.5" r="1.6"/>' +
    '<path d="M21 16l-5.5-5.5a1.5 1.5 0 0 0-2.1 0L5 19"/>',
  video:
    '<rect x="2.5" y="6" width="14" height="12" rx="2"/>' +
    '<path d="M16.5 10.5l5-2.8v8.6l-5-2.8"/>',
  audio:
    '<path d="M9 18V6l10-2v12"/>' +
    '<circle cx="6.5" cy="18" r="2.5"/>' +
    '<circle cx="16.5" cy="16" r="2.5"/>',
  archive:
    '<rect x="3.5" y="4" width="17" height="16" rx="2"/>' +
    '<path d="M12 4v16" stroke-dasharray="2 2"/>' +
    '<rect x="10.5" y="8" width="3" height="2.4"/>' +
    '<rect x="10.5" y="12.4" width="3" height="2.4"/>',
  document:
    '<path d="M6 3h9l4 4v14a1 1 0 0 1-1 1H6a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1Z"/>' +
    '<path d="M14 3v5h5"/>' +
    '<path d="M8.5 13h7"/>' +
    '<path d="M8.5 16.5h7"/>',
  other:
    '<path d="M6 3h9l4 4v14a1 1 0 0 1-1 1H6a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1Z"/>' +
    '<path d="M14 3v5h5"/>',
};

function fileCategory(fileName) {
  var dot = fileName.lastIndexOf('.');
  if (dot === -1 || dot === fileName.length - 1) {
    return 'other';
  }
  var ext = fileName.slice(dot + 1).toLowerCase();
  for (var category in EXTENSION_CATEGORIES) {
    if (EXTENSION_CATEGORIES[category].indexOf(ext) !== -1) {
      return category;
    }
  }
  return 'other';
}

function fileExtension(fileName) {
  var dot = fileName.lastIndexOf('.');
  if (dot === -1 || dot === fileName.length - 1) {
    return '';
  }
  return fileName.slice(dot + 1).toUpperCase();
}

/* ---------------------------------------------------------------------
 * i18n helpers
 * ------------------------------------------------------------------- */

var currentLang = DEFAULT_LANG;

function detectInitialLang() {
  try {
    var stored = localStorage.getItem('aika-lang');
    if (stored && SUPPORTED_LANGS.indexOf(stored) !== -1) {
      return stored;
    }
  } catch (e) {
    /* localStorage unavailable (private mode, etc.) — fall back below */
  }
  var browserLang = (navigator.language || '').slice(0, 2).toLowerCase();
  return SUPPORTED_LANGS.indexOf(browserLang) !== -1 ? browserLang : DEFAULT_LANG;
}

function t(key, vars) {
  var dict = TRANSLATIONS[currentLang] || TRANSLATIONS[DEFAULT_LANG];
  var text = dict[key] || TRANSLATIONS[DEFAULT_LANG][key] || key;
  if (vars) {
    for (var name in vars) {
      text = text.replace('{' + name + '}', vars[name]);
    }
  }
  return text;
}

function applyStaticTranslations() {
  document.documentElement.lang = currentLang;
  var nodes = document.querySelectorAll('[data-i18n]');
  for (var i = 0; i < nodes.length; i++) {
    var key = nodes[i].getAttribute('data-i18n');
    nodes[i].textContent = t(key);
  }
  var buttons = document.querySelectorAll('.lang-btn');
  for (var j = 0; j < buttons.length; j++) {
    buttons[j].setAttribute('aria-pressed', buttons[j].getAttribute('data-lang') === currentLang ? 'true' : 'false');
  }
}

function setLang(lang) {
  if (SUPPORTED_LANGS.indexOf(lang) === -1 || lang === currentLang) {
    return;
  }
  currentLang = lang;
  try {
    localStorage.setItem('aika-lang', lang);
  } catch (e) {
    /* ignore — persistence is a convenience, not a requirement */
  }
  applyStaticTranslations();
  if (lastKnownFiles) {
    renderFiles(lastKnownFiles);
  }
}

/* ---------------------------------------------------------------------
 * Networking (unchanged API surface: /api/localsend/v2/*)
 * ------------------------------------------------------------------- */

var sessionId = null;
try {
  sessionId = sessionStorage.getItem('sessionId');
} catch (e) {
  sessionId = null;
}

var queryParams = new URLSearchParams(location.search);
var queryPin = queryParams.get('pin');
var lastKnownFiles = null;

function fetchJson(url, method) {
  return fetch(url, { method: method }).then(function (response) {
    return response.json().catch(function () {
      return null;
    }).then(function (body) {
      return { status: response.status, body: body };
    });
  });
}

function showState(id) {
  var ids = ['loading-state', 'empty-state', 'error-state', 'files-section'];
  for (var i = 0; i < ids.length; i++) {
    var el = document.getElementById(ids[i]);
    if (el) {
      el.hidden = ids[i] !== id;
    }
  }
}

function showBanner(message) {
  var banner = document.getElementById('status-banner');
  if (!message) {
    banner.hidden = true;
    banner.textContent = '';
    return;
  }
  banner.hidden = false;
  banner.innerHTML =
    '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' +
    '<circle cx="12" cy="12" r="9"/><path d="M12 8v5"/><path d="M12 16h.01"/></svg>' +
    '<span></span>';
  banner.querySelector('span').textContent = message;
}

function firstRequestFiles() {
  showState('loading-state');
  var url = BASE_URL + '/prepare-download';
  var params = [];
  if (sessionId) {
    params.push('sessionId=' + encodeURIComponent(sessionId));
  }
  if (queryPin) {
    params.push('pin=' + encodeURIComponent(queryPin));
  }
  if (params.length) {
    url += '?' + params.join('&');
  }

  fetchJson(url, 'POST').then(handleResponse).catch(function () {
    showState('error-state');
    document.getElementById('error-text').textContent = t('errorNetwork');
  });
}

function handleResponse(result) {
  if (result.status === 401) {
    promptForPin(true);
    return;
  }
  if (result.status === 403) {
    showState('error-state');
    document.getElementById('error-text').textContent = t('rejected');
    return;
  }
  if (result.status === 429) {
    showState('error-state');
    document.getElementById('error-text').textContent = t('tooManyAttempts');
    return;
  }
  if (result.status !== 200 || !result.body) {
    showState('error-state');
    document.getElementById('error-text').textContent = t('errorGeneric', { status: result.status });
    return;
  }
  handleSuccess(result.body);
}

function promptForPin(firstAttempt) {
  var message = t('enterPin') + (firstAttempt ? '' : '\n' + t('invalidPin'));
  var pin = window.prompt(message);
  if (!pin) {
    showState('error-state');
    document.getElementById('error-text').textContent = t('invalidPin');
    return;
  }

  fetchJson(BASE_URL + '/prepare-download?pin=' + encodeURIComponent(pin), 'POST').then(function (result) {
    if (result.status === 401) {
      promptForPin(false);
      return;
    }
    handleResponse(result);
  });
}

function handleSuccess(data) {
  sessionId = data.sessionId;
  try {
    sessionStorage.setItem('sessionId', sessionId);
  } catch (e) {
    /* ignore */
  }
  showBanner(null);
  renderFiles(data.files);
}

/* ---------------------------------------------------------------------
 * Rendering
 * ------------------------------------------------------------------- */

function formatBytes(bytes) {
  if (bytes < 1024) {
    return bytes + ' B';
  } else if (bytes < 1024 * 1024) {
    return (bytes / 1024).toFixed(1) + ' KB';
  } else if (bytes < 1024 * 1024 * 1024) {
    return (bytes / (1024 * 1024)).toFixed(1) + ' MB';
  } else {
    return (bytes / (1024 * 1024 * 1024)).toFixed(1) + ' GB';
  }
}

function escapeHtml(text) {
  if (text === null || text === undefined) {
    return '';
  }
  var map = { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#039;' };
  return String(text).replace(/[&<>"']/g, function (m) {
    return map[m];
  });
}

function downloadIconSvg() {
  return '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' +
    '<path d="M12 4v11"/><path d="M8 11l4 4 4-4"/><path d="M5 19h14"/></svg>';
}

function checkIconSvg() {
  return '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' +
    '<path d="M4 12.5l5 5L20 7"/></svg>';
}

function renderFiles(files) {
  lastKnownFiles = files;
  var fileIds = Object.keys(files);

  document.getElementById('files-count').textContent = String(fileIds.length);

  var totalSize = 0;
  for (var i = 0; i < fileIds.length; i++) {
    totalSize += files[fileIds[i]].size || 0;
  }
  document.getElementById('total-size').textContent = formatBytes(totalSize);

  if (fileIds.length === 0) {
    showState('empty-state');
    return;
  }

  var grid = document.getElementById('file-grid');
  grid.innerHTML = '';
  grid.classList.toggle('single-file', fileIds.length === 1);

  for (var j = 0; j < fileIds.length; j++) {
    grid.appendChild(buildFileCard(fileIds[j], files[fileIds[j]]));
  }

  var downloadAllBtn = document.getElementById('download-all-btn');
  downloadAllBtn.hidden = fileIds.length <= 1;
  downloadAllBtn.onclick = function () {
    downloadAll(fileIds, files);
  };

  showState('files-section');
}

function buildFileCard(fileId, file) {
  var category = fileCategory(file.fileName);
  var card = document.createElement('div');
  card.className = 'file-card';
  card.setAttribute('data-file-id', fileId);

  card.innerHTML =
    '<div class="file-icon" aria-hidden="true">' +
    '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round">' +
    ICON_PATHS[category] +
    '</svg></div>' +
    '<div class="file-info">' +
    '<p class="file-name"></p>' +
    '<p class="file-meta"><span class="file-ext"></span><span>·</span><span class="file-size"></span></p>' +
    '</div>' +
    '<button type="button" class="file-download-btn">' + downloadIconSvg() + '</button>';

  card.querySelector('.file-name').textContent = file.fileName;
  card.querySelector('.file-name').title = file.fileName;
  card.querySelector('.file-ext').textContent = fileExtension(file.fileName) || category;
  card.querySelector('.file-size').textContent = formatBytes(file.size);

  var btn = card.querySelector('.file-download-btn');
  btn.setAttribute('aria-label', t('downloadOne', { name: file.fileName }));
  btn.addEventListener('click', function () {
    triggerDownload(fileId, file.fileName);
    markDownloading(card, btn);
  });

  return card;
}

function triggerDownload(fileId, fileName) {
  var url = BASE_URL + '/download?sessionId=' + encodeURIComponent(sessionId) + '&fileId=' + encodeURIComponent(fileId);
  var a = document.createElement('a');
  a.href = url;
  a.download = fileName;
  a.rel = 'noopener';
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
}

function markDownloading(card, btn) {
  card.classList.add('is-done');
  btn.innerHTML = checkIconSvg();
  btn.setAttribute('aria-label', t('downloadStarted'));
}

function downloadAll(fileIds, files) {
  fileIds.forEach(function (fileId, index) {
    setTimeout(function () {
      triggerDownload(fileId, files[fileId].fileName);
      var card = document.querySelector('.file-card[data-file-id="' + CSS.escape(fileId) + '"]');
      if (card) {
        markDownloading(card, card.querySelector('.file-download-btn'));
      }
    }, index * 350);
  });
}

/* ---------------------------------------------------------------------
 * Bootstrap
 * ------------------------------------------------------------------- */

function initLangSwitch() {
  var buttons = document.querySelectorAll('.lang-btn');
  for (var i = 0; i < buttons.length; i++) {
    buttons[i].addEventListener('click', function (event) {
      setLang(event.currentTarget.getAttribute('data-lang'));
    });
  }
}

function init() {
  currentLang = detectInitialLang();
  applyStaticTranslations();
  initLangSwitch();
  firstRequestFiles();
}

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', init);
} else {
  init();
}
