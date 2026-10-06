'use strict';

/* ---------------------------------------------------------------------
 * Aika — web share page (bidirectional exchange)
 *
 * The page lets a browser on the local network:
 *   1. download the files shared by the host (download API), and
 *   2. upload its own files to the host through the same link.
 *
 * Uploads reuse the LocalSend v2 upload pipeline of the host:
 *   POST /api/localsend/v2/web/prepare-upload?sessionId=…  (announce a batch)
 *   POST /api/localsend/v2/upload?sessionId&fileId&token   (stream one file)
 *   POST /api/localsend/v2/cancel?sessionId=…              (abort a batch)
 * Files are streamed by the browser straight from disk (XHR with a File
 * body), so even very large files are never loaded into memory.
 *
 * All user-facing text lives in TRANSLATIONS below: adding a language only
 * means adding one more key to this object.
 * ------------------------------------------------------------------- */

var BASE_URL = '/api/localsend/v2';

var TRANSLATIONS = {
  fr: {
    title: 'Échange de fichiers',
    description: 'Téléchargez les fichiers partagés et envoyez les vôtres',
    waiting: 'En attente de réponse…',
    empty: 'Aucun fichier disponible pour le moment',
    availableTitle: 'Fichiers disponibles',
    filesLabel: 'Fichiers',
    totalSizeLabel: 'Taille totale',
    downloadAll: 'Tout télécharger',
    downloadOne: 'Télécharger {name}',
    downloadStarted: 'Téléchargement lancé',
    uploadTitle: 'Envoyer des fichiers',
    dropHint: 'Glissez-déposez vos fichiers ici',
    pickFiles: 'Choisir des fichiers',
    uploadNote: 'Les fichiers sont envoyés directement à l’appareil hôte, sur votre réseau local.',
    cancelAll: 'Tout annuler',
    summaryActive: 'Envoi en cours — {done}/{total} fichier(s)',
    summaryDone: 'Envoi terminé — {done}/{total} fichier(s)',
    summaryDetail: '{sent} sur {size} · {percent} %',
    statusQueued: 'En attente',
    statusWaitingHost: 'En file d’attente',
    statusUploading: 'En cours',
    statusDone: 'Terminé',
    statusError: 'Erreur',
    statusCancelled: 'Annulé',
    hostBusy: 'L’hôte reçoit déjà des fichiers, envoi dès qu’il est disponible…',
    errNetwork: 'Connexion interrompue. Vérifiez le réseau puis réessayez.',
    errDiskFull: 'Espace de stockage insuffisant sur l’appareil hôte.',
    errTooLarge: 'Fichier trop volumineux pour l’appareil hôte.',
    errInvalidName: 'Nom de fichier invalide.',
    errRejected: 'L’hôte n’autorise pas l’envoi de fichiers.',
    errSession: 'Session expirée. Rechargez la page.',
    errGeneric: 'L’envoi a échoué ({status}).',
    retry: 'Réessayer',
    cancel: 'Annuler',
    remove: 'Retirer',
    sentTitle: 'Fichiers envoyés',
    sentEmpty: 'Les fichiers que vous envoyez apparaîtront ici.',
    sentAt: 'Envoyé à {time}',
    clearSent: 'Effacer la liste',
    leaveWarning: 'Des fichiers sont en cours d’envoi. Quitter la page interrompra l’envoi.',
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
    title: 'File exchange',
    description: 'Download the shared files and send your own',
    waiting: 'Waiting for response…',
    empty: 'No files available right now',
    availableTitle: 'Available files',
    filesLabel: 'Files',
    totalSizeLabel: 'Total size',
    downloadAll: 'Download all',
    downloadOne: 'Download {name}',
    downloadStarted: 'Download started',
    uploadTitle: 'Send files',
    dropHint: 'Drag and drop your files here',
    pickFiles: 'Choose files',
    uploadNote: 'Files are sent directly to the host device, over your local network.',
    cancelAll: 'Cancel all',
    summaryActive: 'Sending — {done}/{total} file(s)',
    summaryDone: 'Done — {done}/{total} file(s)',
    summaryDetail: '{sent} of {size} · {percent} %',
    statusQueued: 'Pending',
    statusWaitingHost: 'Queued',
    statusUploading: 'Sending',
    statusDone: 'Done',
    statusError: 'Error',
    statusCancelled: 'Cancelled',
    hostBusy: 'The host is already receiving files, sending as soon as it is available…',
    errNetwork: 'Connection interrupted. Check the network and try again.',
    errDiskFull: 'Not enough storage space on the host device.',
    errTooLarge: 'File too large for the host device.',
    errInvalidName: 'Invalid file name.',
    errRejected: 'The host does not accept uploads.',
    errSession: 'Session expired. Reload the page.',
    errGeneric: 'Upload failed ({status}).',
    retry: 'Retry',
    cancel: 'Cancel',
    remove: 'Remove',
    sentTitle: 'Sent files',
    sentEmpty: 'The files you send will appear here.',
    sentAt: 'Sent at {time}',
    clearSent: 'Clear list',
    leaveWarning: 'Files are being sent. Leaving the page will interrupt the upload.',
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

/* Upload limits — mirror the server-side validation (web.rs). */
var MAX_BATCH_FILES = 50; // small batches let several devices take turns
var MAX_FILE_NAME_BYTES = 255;
var BUSY_RETRY_MIN_MS = 1000;
var BUSY_RETRY_MAX_MS = 5000;
var SENT_STORAGE_KEY = 'aika-sent-files';
var MAX_SENT_ENTRIES = 200;

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

function fileIconHtml(fileName) {
  return '<div class="file-icon" aria-hidden="true">' +
    '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round">' +
    ICON_PATHS[fileCategory(fileName)] +
    '</svg></div>';
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
  for (var i = 0; i < uploads.length; i++) {
    updateUploadRow(uploads[i]);
  }
  renderUploadSummary();
  renderSent();
}

/* ---------------------------------------------------------------------
 * Networking: download session (unchanged API: /api/localsend/v2/*)
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

function fetchJson(url, method, body) {
  var options = { method: method };
  if (body !== undefined) {
    options.headers = { 'Content-Type': 'application/json' };
    options.body = JSON.stringify(body);
  }
  return fetch(url, options).then(function (response) {
    return response.json().catch(function () {
      return null;
    }).then(function (json) {
      return { status: response.status, body: json };
    });
  });
}

function showState(id) {
  var ids = ['loading-state', 'error-state', 'exchange'];
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

function showError(message) {
  showState('error-state');
  document.getElementById('error-text').textContent = message;
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
    showError(t('errorNetwork'));
  });
}

function handleResponse(result) {
  if (result.status === 401) {
    promptForPin(true);
    return;
  }
  if (result.status === 403) {
    showError(t('rejected'));
    return;
  }
  if (result.status === 429) {
    showError(t('tooManyAttempts'));
    return;
  }
  if (result.status !== 200 || !result.body) {
    showError(t('errorGeneric', { status: result.status }));
    return;
  }
  handleSuccess(result.body);
}

function promptForPin(firstAttempt) {
  var message = t('enterPin') + (firstAttempt ? '' : '\n' + t('invalidPin'));
  var pin = window.prompt(message);
  if (!pin) {
    showError(t('invalidPin'));
    return;
  }

  fetchJson(BASE_URL + '/prepare-download?pin=' + encodeURIComponent(pin), 'POST').then(function (result) {
    if (result.status === 401) {
      promptForPin(false);
      return;
    }
    handleResponse(result);
  }).catch(function () {
    showError(t('errorNetwork'));
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
  renderFiles(data.files || {});
  renderSent();
  showState('exchange');
}

/* ---------------------------------------------------------------------
 * Rendering helpers
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

function svgIcon(paths, strokeWidth) {
  return '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="' + (strokeWidth || 2) +
    '" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' + paths + '</svg>';
}

function downloadIconSvg() {
  return svgIcon('<path d="M12 4v11"/><path d="M8 11l4 4 4-4"/><path d="M5 19h14"/>');
}

function checkIconSvg() {
  return svgIcon('<path d="M4 12.5l5 5L20 7"/>', 2.2);
}

function closeIconSvg() {
  return svgIcon('<path d="M6 6l12 12"/><path d="M18 6L6 18"/>');
}

function retryIconSvg() {
  return svgIcon('<path d="M20 11a8 8 0 1 0-2.3 5.7"/><path d="M20 5v6h-6"/>');
}

/* ---------------------------------------------------------------------
 * 1. Available files (download)
 * ------------------------------------------------------------------- */

function renderFiles(files) {
  lastKnownFiles = files;
  var fileIds = Object.keys(files);

  document.getElementById('files-count').textContent = String(fileIds.length);

  var totalSize = 0;
  for (var i = 0; i < fileIds.length; i++) {
    totalSize += files[fileIds[i]].size || 0;
  }
  document.getElementById('total-size').textContent = formatBytes(totalSize);

  var grid = document.getElementById('file-grid');
  grid.innerHTML = '';
  grid.classList.toggle('single-file', fileIds.length === 1);

  var isEmpty = fileIds.length === 0;
  document.getElementById('files-empty').hidden = !isEmpty;
  document.getElementById('files-summary').hidden = isEmpty;

  for (var j = 0; j < fileIds.length; j++) {
    grid.appendChild(buildFileCard(fileIds[j], files[fileIds[j]]));
  }

  var downloadAllBtn = document.getElementById('download-all-btn');
  downloadAllBtn.hidden = fileIds.length <= 1;
  downloadAllBtn.onclick = function () {
    downloadAll(fileIds, files);
  };
}

function buildFileCard(fileId, file) {
  var category = fileCategory(file.fileName);
  var card = document.createElement('div');
  card.className = 'file-card';
  card.setAttribute('data-file-id', fileId);

  card.innerHTML =
    fileIconHtml(file.fileName) +
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
 * 2. Upload engine
 *
 * Every selected file becomes an upload item:
 *   queued → (waiting: host busy) → uploading → done | error | cancelled
 * Queued items are announced in batches (one host upload session per
 * batch); the files of a batch are then streamed one after the other.
 * ------------------------------------------------------------------- */

var uploads = [];
var uploadCounter = 0;
var pumping = false;
var activeBatch = null; // { sessionId, items, xhr }
var busyRetryMs = BUSY_RETRY_MIN_MS;
var renderScheduled = false;

function newUploadId() {
  uploadCounter += 1;
  return 'w' + Date.now().toString(36) + uploadCounter.toString(36) + Math.random().toString(36).slice(2, 8);
}

/** Mirrors `is_valid_upload_file_name` of the server. */
function isValidFileName(name) {
  if (!name || !name.trim() || name === '.' || name === '..') {
    return false;
  }
  if (/[\/\\\u0000-\u001f\u007f]/.test(name)) {
    return false;
  }
  return new TextEncoder().encode(name).length <= MAX_FILE_NAME_BYTES;
}

function addFiles(fileList) {
  if (!fileList || !fileList.length) {
    return;
  }
  for (var i = 0; i < fileList.length; i++) {
    var file = fileList[i];
    var item = {
      id: newUploadId(),
      file: file,
      status: 'queued',
      loaded: 0,
      errorKey: null,
      errorVars: null,
      xhr: null,
      row: null,
    };
    if (!isValidFileName(file.name)) {
      item.status = 'error';
      item.errorKey = 'errInvalidName';
    }
    uploads.push(item);
    document.getElementById('upload-list').appendChild(buildUploadRow(item));
    updateUploadRow(item);
  }
  renderUploadSummary();
  pump();
}

function setItemError(item, errorKey, errorVars) {
  item.status = 'error';
  item.errorKey = errorKey;
  item.errorVars = errorVars || null;
  item.xhr = null;
  updateUploadRow(item);
}

/** Maps an HTTP status of the host to a user-facing error. */
function errorKeyForStatus(status, body) {
  if (status === 0) {
    return 'errNetwork';
  }
  if (status === 507) {
    return 'errDiskFull';
  }
  if (status === 413) {
    return 'errTooLarge';
  }
  if (status === 422) {
    return 'errInvalidName';
  }
  if (status === 403) {
    var message = body && body.message ? String(body.message) : '';
    return message.indexOf('sessionId') !== -1 ? 'errSession' : 'errRejected';
  }
  return 'errGeneric';
}

function pump() {
  if (pumping) {
    return;
  }
  var batch = [];
  for (var i = 0; i < uploads.length && batch.length < MAX_BATCH_FILES; i++) {
    if (uploads[i].status === 'queued' || uploads[i].status === 'waiting') {
      batch.push(uploads[i]);
    }
  }
  if (!batch.length) {
    return;
  }
  pumping = true;
  startBatch(batch);
}

function finishPump() {
  pumping = false;
  activeBatch = null;
  renderUploadSummary();
  pump();
}

function startBatch(batch) {
  var files = {};
  for (var i = 0; i < batch.length; i++) {
    var file = batch[i].file;
    files[batch[i].id] = {
      id: batch[i].id,
      fileName: file.name,
      size: file.size,
      fileType: file.type || 'application/octet-stream',
      modified: file.lastModified ? new Date(file.lastModified).toISOString() : null,
    };
  }

  var url = BASE_URL + '/web/prepare-upload?sessionId=' + encodeURIComponent(sessionId);
  fetchJson(url, 'POST', { files: files }).then(function (result) {
    // Items cancelled while the host was deciding are skipped below.
    if (result.status === 409) {
      // Another device (or a regular Aika transfer) is using the host:
      // wait and try again, with a gentle backoff.
      for (var w = 0; w < batch.length; w++) {
        if (batch[w].status === 'queued' || batch[w].status === 'waiting') {
          batch[w].status = 'waiting';
          updateUploadRow(batch[w]);
        }
      }
      showBanner(t('hostBusy'));
      var delay = busyRetryMs;
      busyRetryMs = Math.min(busyRetryMs * 1.5, BUSY_RETRY_MAX_MS);
      setTimeout(finishPump, delay);
      return;
    }
    busyRetryMs = BUSY_RETRY_MIN_MS;
    showBanner(null);

    if (result.status !== 200 || !result.body || !result.body.files) {
      var errorKey = result.status === 204 ? 'errRejected' : errorKeyForStatus(result.status, result.body);
      for (var e = 0; e < batch.length; e++) {
        if (batch[e].status !== 'cancelled') {
          setItemError(batch[e], errorKey, { status: result.status });
        }
      }
      finishPump();
      return;
    }

    activeBatch = { sessionId: result.body.sessionId, items: batch, xhr: null };
    uploadSequentially(result.body.sessionId, result.body.files, batch, 0, false);
  }).catch(function () {
    for (var n = 0; n < batch.length; n++) {
      if (batch[n].status !== 'cancelled') {
        setItemError(batch[n], 'errNetwork');
      }
    }
    finishPump();
  });
}

function uploadSequentially(uploadSessionId, tokens, batch, index, skippedAny) {
  if (index >= batch.length) {
    if (skippedAny) {
      // Some announced files were never sent: free the host's session slot
      // right away instead of leaving it waiting for them.
      cancelUploadSession(uploadSessionId);
    }
    finishPump();
    return;
  }

  var item = batch[index];
  var token = tokens[item.id];
  if (item.status === 'cancelled' || !token) {
    if (!token && item.status !== 'cancelled') {
      setItemError(item, 'errRejected');
    }
    uploadSequentially(uploadSessionId, tokens, batch, index + 1, true);
    return;
  }

  item.status = 'uploading';
  item.loaded = 0;
  item.errorKey = null;
  updateUploadRow(item);

  var xhr = new XMLHttpRequest();
  item.xhr = xhr;
  if (activeBatch) {
    activeBatch.xhr = xhr;
  }
  xhr.open(
    'POST',
    BASE_URL + '/upload?sessionId=' + encodeURIComponent(uploadSessionId) +
      '&fileId=' + encodeURIComponent(item.id) +
      '&token=' + encodeURIComponent(token)
  );
  xhr.upload.onprogress = function (event) {
    if (event.lengthComputable) {
      item.loaded = event.loaded;
      scheduleProgressRender();
    }
  };
  xhr.onload = function () {
    item.xhr = null;
    if (xhr.status === 200) {
      item.status = 'done';
      item.loaded = item.file.size;
      updateUploadRow(item);
      addSent(item.file.name, item.file.size);
    } else {
      var body = null;
      try {
        body = JSON.parse(xhr.responseText);
      } catch (e) {
        body = null;
      }
      setItemError(item, errorKeyForStatus(xhr.status, body), { status: xhr.status });
    }
    renderUploadSummary();
    uploadSequentially(uploadSessionId, tokens, batch, index + 1, skippedAny);
  };
  xhr.onerror = function () {
    setItemError(item, 'errNetwork');
    renderUploadSummary();
    uploadSequentially(uploadSessionId, tokens, batch, index + 1, skippedAny);
  };
  xhr.onabort = function () {
    item.xhr = null;
    item.status = 'cancelled';
    updateUploadRow(item);
    renderUploadSummary();
    uploadSequentially(uploadSessionId, tokens, batch, index + 1, skippedAny);
  };
  // The File is streamed from disk by the browser: never read into memory.
  xhr.send(item.file);
}

function cancelUploadSession(uploadSessionId) {
  fetch(BASE_URL + '/cancel?sessionId=' + encodeURIComponent(uploadSessionId), { method: 'POST' }).catch(function () {
    /* best effort: the host frees the slot when the batch completes anyway */
  });
}

function cancelItem(item) {
  if (item.status === 'uploading' && item.xhr) {
    item.xhr.abort(); // onabort marks it cancelled and continues the batch
    return;
  }
  if (item.status === 'queued' || item.status === 'waiting') {
    item.status = 'cancelled';
    updateUploadRow(item);
    renderUploadSummary();
  }
}

function retryItem(item) {
  if (item.status !== 'error' && item.status !== 'cancelled') {
    return;
  }
  if (!isValidFileName(item.file.name)) {
    return;
  }
  item.status = 'queued';
  item.loaded = 0;
  item.errorKey = null;
  updateUploadRow(item);
  renderUploadSummary();
  pump();
}

function removeItem(item) {
  if (item.status === 'uploading' || item.status === 'queued' || item.status === 'waiting') {
    return;
  }
  var index = uploads.indexOf(item);
  if (index !== -1) {
    uploads.splice(index, 1);
  }
  if (item.row && item.row.parentNode) {
    item.row.parentNode.removeChild(item.row);
  }
  renderUploadSummary();
}

function cancelAll() {
  for (var i = 0; i < uploads.length; i++) {
    if (uploads[i].status === 'queued' || uploads[i].status === 'waiting') {
      uploads[i].status = 'cancelled';
      updateUploadRow(uploads[i]);
    }
  }
  for (var j = 0; j < uploads.length; j++) {
    if (uploads[j].status === 'uploading') {
      cancelItem(uploads[j]);
    }
  }
  renderUploadSummary();
}

function isUploading() {
  for (var i = 0; i < uploads.length; i++) {
    var status = uploads[i].status;
    if (status === 'uploading' || status === 'queued' || status === 'waiting') {
      return true;
    }
  }
  return false;
}

/* ---------------------------------------------------------------------
 * 2b. Upload rendering (rows are built once and updated in place)
 * ------------------------------------------------------------------- */

function buildUploadRow(item) {
  var row = document.createElement('div');
  row.className = 'upload-row';
  row.innerHTML =
    '<div class="upload-row-main">' +
    fileIconHtml(item.file.name) +
    '<div class="file-info">' +
    '<p class="file-name"></p>' +
    '<p class="file-meta"><span class="status-chip"></span><span class="file-size"></span></p>' +
    '</div>' +
    '<button type="button" class="icon-btn row-action"></button>' +
    '</div>' +
    '<div class="progress"><div class="progress-bar"></div></div>' +
    '<p class="row-error" hidden></p>';
  row.querySelector('.file-name').textContent = item.file.name;
  row.querySelector('.file-name').title = item.file.name;
  row.querySelector('.row-action').addEventListener('click', function () {
    if (item.status === 'error' || item.status === 'cancelled') {
      if (isValidFileName(item.file.name)) {
        retryItem(item);
      } else {
        removeItem(item);
      }
    } else if (item.status === 'done') {
      removeItem(item);
    } else {
      cancelItem(item);
    }
  });
  item.row = row;
  return row;
}

function statusLabel(item) {
  switch (item.status) {
    case 'queued':
      return t('statusQueued');
    case 'waiting':
      return t('statusWaitingHost');
    case 'uploading':
      return t('statusUploading');
    case 'done':
      return t('statusDone');
    case 'cancelled':
      return t('statusCancelled');
    default:
      return t('statusError');
  }
}

function itemPercent(item) {
  if (item.status === 'done') {
    return 100;
  }
  if (!item.file.size) {
    return 0;
  }
  return Math.min(100, Math.floor((item.loaded / item.file.size) * 100));
}

function updateUploadRow(item) {
  var row = item.row;
  if (!row) {
    return;
  }
  var chip = row.querySelector('.status-chip');
  var chipStatus = item.status === 'waiting' ? 'queued' : item.status;
  chip.setAttribute('data-status', chipStatus);
  chip.textContent = statusLabel(item) + (item.status === 'uploading' ? ' · ' + itemPercent(item) + ' %' : '');

  var sizeText = item.status === 'uploading'
    ? formatBytes(item.loaded) + ' / ' + formatBytes(item.file.size)
    : formatBytes(item.file.size);
  row.querySelector('.file-size').textContent = sizeText;

  var progress = row.querySelector('.progress');
  progress.hidden = item.status === 'error' || item.status === 'cancelled' || item.status === 'done';
  progress.classList.toggle('is-indeterminate', item.status === 'waiting');
  progress.querySelector('.progress-bar').style.width = itemPercent(item) + '%';

  var errorEl = row.querySelector('.row-error');
  if (item.status === 'error' && item.errorKey) {
    errorEl.hidden = false;
    errorEl.textContent = t(item.errorKey, item.errorVars);
  } else {
    errorEl.hidden = true;
  }

  var action = row.querySelector('.row-action');
  var canRetry = (item.status === 'error' || item.status === 'cancelled') && isValidFileName(item.file.name);
  if (canRetry) {
    action.innerHTML = retryIconSvg();
    action.setAttribute('aria-label', t('retry'));
    action.title = t('retry');
  } else if (item.status === 'done' || item.status === 'error' || item.status === 'cancelled') {
    action.innerHTML = closeIconSvg();
    action.setAttribute('aria-label', t('remove'));
    action.title = t('remove');
  } else {
    action.innerHTML = closeIconSvg();
    action.setAttribute('aria-label', t('cancel'));
    action.title = t('cancel');
  }
}

/** Coalesces progress events into at most one DOM update per frame. */
function scheduleProgressRender() {
  if (renderScheduled) {
    return;
  }
  renderScheduled = true;
  window.requestAnimationFrame(function () {
    renderScheduled = false;
    for (var i = 0; i < uploads.length; i++) {
      if (uploads[i].status === 'uploading') {
        updateUploadRow(uploads[i]);
      }
    }
    renderUploadSummary();
  });
}

function renderUploadSummary() {
  var summary = document.getElementById('upload-summary');
  var total = 0;
  var done = 0;
  var totalBytes = 0;
  var sentBytes = 0;
  var hasError = false;
  for (var i = 0; i < uploads.length; i++) {
    var item = uploads[i];
    if (item.status === 'cancelled') {
      continue;
    }
    total += 1;
    totalBytes += item.file.size;
    if (item.status === 'done') {
      done += 1;
      sentBytes += item.file.size;
    } else if (item.status === 'uploading') {
      sentBytes += item.loaded;
    } else if (item.status === 'error') {
      hasError = true;
    }
  }

  summary.hidden = uploads.length === 0;
  if (summary.hidden) {
    return;
  }

  var active = isUploading();
  var percent = totalBytes > 0 ? Math.floor((sentBytes / totalBytes) * 100) : (total > 0 && done === total ? 100 : 0);
  document.getElementById('upload-summary-text').textContent =
    t(active ? 'summaryActive' : 'summaryDone', { done: done, total: total });
  document.getElementById('upload-summary-detail').textContent =
    t('summaryDetail', { sent: formatBytes(sentBytes), size: formatBytes(totalBytes), percent: percent });
  var progress = document.getElementById('global-progress');
  progress.classList.toggle('is-error', !active && hasError);
  progress.querySelector('.progress-bar').style.width = percent + '%';
  document.getElementById('cancel-all-btn').hidden = !active;
}

/* ---------------------------------------------------------------------
 * 3. Sent files (kept for this browser tab, survives a reload)
 * ------------------------------------------------------------------- */

var sentFiles = loadSent();

function loadSent() {
  try {
    var raw = sessionStorage.getItem(SENT_STORAGE_KEY);
    var parsed = raw ? JSON.parse(raw) : [];
    return Array.isArray(parsed) ? parsed : [];
  } catch (e) {
    return [];
  }
}

function saveSent() {
  try {
    sessionStorage.setItem(SENT_STORAGE_KEY, JSON.stringify(sentFiles));
  } catch (e) {
    /* ignore — the list still works for this page view */
  }
}

function addSent(name, size) {
  sentFiles.unshift({ name: name, size: size, time: Date.now() });
  if (sentFiles.length > MAX_SENT_ENTRIES) {
    sentFiles.length = MAX_SENT_ENTRIES;
  }
  saveSent();
  renderSent();
}

function renderSent() {
  var list = document.getElementById('sent-list');
  list.innerHTML = '';
  document.getElementById('sent-count').textContent = String(sentFiles.length);
  document.getElementById('sent-empty').hidden = sentFiles.length > 0;
  document.getElementById('clear-sent-btn').hidden = sentFiles.length === 0;

  for (var i = 0; i < sentFiles.length; i++) {
    var entry = sentFiles[i];
    var row = document.createElement('div');
    row.className = 'file-card sent-row';
    row.innerHTML =
      fileIconHtml(entry.name) +
      '<div class="file-info">' +
      '<p class="file-name"></p>' +
      '<p class="file-meta"><span class="file-size"></span><span>·</span><span class="sent-time"></span></p>' +
      '</div>';
    row.querySelector('.file-name').textContent = entry.name;
    row.querySelector('.file-name').title = entry.name;
    row.querySelector('.file-size').textContent = formatBytes(entry.size);
    var time = new Date(entry.time).toLocaleTimeString(currentLang, { hour: '2-digit', minute: '2-digit' });
    row.querySelector('.sent-time').textContent = t('sentAt', { time: time });
    list.appendChild(row);
  }
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

function initUpload() {
  var input = document.getElementById('file-input');
  var zone = document.getElementById('drop-zone');

  document.getElementById('pick-files-btn').addEventListener('click', function () {
    input.click();
  });
  input.addEventListener('change', function () {
    addFiles(input.files);
    input.value = ''; // allow selecting the same file again
  });

  var dragDepth = 0;
  zone.addEventListener('dragenter', function (event) {
    event.preventDefault();
    dragDepth += 1;
    zone.classList.add('is-dragover');
  });
  zone.addEventListener('dragover', function (event) {
    event.preventDefault();
    if (event.dataTransfer) {
      event.dataTransfer.dropEffect = 'copy';
    }
  });
  zone.addEventListener('dragleave', function () {
    dragDepth = Math.max(0, dragDepth - 1);
    if (dragDepth === 0) {
      zone.classList.remove('is-dragover');
    }
  });
  zone.addEventListener('drop', function (event) {
    event.preventDefault();
    dragDepth = 0;
    zone.classList.remove('is-dragover');
    if (event.dataTransfer && event.dataTransfer.files) {
      addFiles(event.dataTransfer.files);
    }
  });
  // Dropping outside the zone must not navigate away from the page.
  window.addEventListener('dragover', function (event) {
    event.preventDefault();
  });
  window.addEventListener('drop', function (event) {
    event.preventDefault();
  });

  document.getElementById('cancel-all-btn').addEventListener('click', cancelAll);
  document.getElementById('clear-sent-btn').addEventListener('click', function () {
    sentFiles = [];
    saveSent();
    renderSent();
  });

  window.addEventListener('beforeunload', function (event) {
    if (isUploading()) {
      event.preventDefault();
      event.returnValue = t('leaveWarning');
      return t('leaveWarning');
    }
    return undefined;
  });
}

function init() {
  currentLang = detectInitialLang();
  applyStaticTranslations();
  initLangSwitch();
  initUpload();
  firstRequestFiles();
}

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', init);
} else {
  init();
}
