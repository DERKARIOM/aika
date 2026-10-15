// Popup of "Aika – Téléchargements": status, pairing code and options.

const fr = (chrome.i18n.getUILanguage() || navigator.language || 'en').toLowerCase().startsWith('fr');
const T = fr
  ? {
      subtitle: 'Téléchargements repris par Aika',
      checking: 'Recherche d’Aika…',
      ok: 'Connecté à Aika',
      unreachable: 'Aika introuvable : lancez Aika puis activez Options → Intégration navigateur.',
      badToken: 'Code d’appairage incorrect.',
      noToken: 'Saisissez le code d’appairage affiché dans Aika.',
      enabled: 'Reprendre les téléchargements dans Aika',
      token: 'Code d’appairage',
      save: 'Enregistrer',
      hintToken: 'Dans Aika : Télécharger depuis un lien → Options → Intégration navigateur.',
      minSize: 'Taille minimale',
      mb: 'Mo (les petits fichiers restent dans le navigateur)',
      incognito: 'Aussi en navigation privée',
      lastOk: (name) => `Dernier fichier repris par Aika : ${name}`,
      lastKo: (reason) => `Dernier téléchargement laissé au navigateur (${reason}).`,
      reasons: {
        unreachable: 'Aika fermée',
        token: 'code incorrect',
        webPageWithoutMedia: 'pas un fichier',
        requiresAuth: 'connexion au site nécessaire',
        notFound: 'fichier introuvable',
        unsupportedPlatform: 'site non pris en charge',
        localAddress: 'adresse locale',
        notEnoughSpace: 'espace insuffisant',
        timeout: 'pas de réponse',
      },
    }
  : {
      subtitle: 'Downloads taken over by Aika',
      checking: 'Looking for Aika…',
      ok: 'Connected to Aika',
      unreachable: 'Aika not found: start Aika, then turn on Options → Browser integration.',
      badToken: 'Wrong pairing code.',
      noToken: 'Type the pairing code shown in Aika.',
      enabled: 'Take over downloads in Aika',
      token: 'Pairing code',
      save: 'Save',
      hintToken: 'In Aika: Download from a link → Options → Browser integration.',
      minSize: 'Minimum size',
      mb: 'MB (small files stay in the browser)',
      incognito: 'Also in private windows',
      lastOk: (name) => `Last file taken over by Aika: ${name}`,
      lastKo: (reason) => `Last download left to the browser (${reason}).`,
      reasons: {
        unreachable: 'Aika closed',
        token: 'wrong code',
        webPageWithoutMedia: 'not a file',
        requiresAuth: 'site sign-in needed',
        notFound: 'file not found',
        unsupportedPlatform: 'site not supported',
        localAddress: 'local address',
        notEnoughSpace: 'not enough space',
        timeout: 'no answer',
      },
    };

const $ = (id) => document.getElementById(id);
const DEFAULTS = { enabled: true, token: '', minSizeMb: 1, includeIncognito: false, lastResult: null };

function setText(id, text) {
  $(id).textContent = text;
}

function showStatus(kind, text) {
  $('status').className = `status ${kind}`;
  setText('status-text', text);
}

async function checkConnection(token) {
  if (!token) {
    showStatus('warn', T.noToken);
    return;
  }
  showStatus('checking', T.checking);
  const answer = await chrome.runtime.sendMessage({ type: 'ping', token });
  if (answer && answer.status === 200) showStatus('ok', T.ok);
  else if (answer && answer.status === 401) showStatus('error', T.badToken);
  else showStatus('error', T.unreachable);
}

function showLast(result) {
  if (!result) return;
  const reason = T.reasons[result.reason] || result.reason || '';
  setText('last', result.ok ? T.lastOk(result.fileName || '') : T.lastKo(reason));
}

async function init() {
  setText('subtitle', T.subtitle);
  setText('label-enabled', T.enabled);
  setText('label-token', T.token);
  setText('save', T.save);
  setText('hint-token', T.hintToken);
  setText('label-min', T.minSize);
  setText('unit-mb', T.mb);
  setText('label-incognito', T.incognito);

  const settings = { ...DEFAULTS, ...(await chrome.storage.local.get(DEFAULTS)) };
  $('enabled').checked = settings.enabled;
  $('token').value = settings.token;
  $('min-size').value = settings.minSizeMb;
  $('incognito').checked = settings.includeIncognito;
  showLast(settings.lastResult);

  $('enabled').addEventListener('change', () => chrome.storage.local.set({ enabled: $('enabled').checked }));
  $('incognito').addEventListener('change', () => chrome.storage.local.set({ includeIncognito: $('incognito').checked }));
  $('min-size').addEventListener('change', () => {
    const value = Math.max(0, Math.min(10000, Math.round(Number($('min-size').value) || 0)));
    $('min-size').value = value;
    chrome.storage.local.set({ minSizeMb: value });
  });
  const save = async () => {
    const token = $('token').value.trim().toUpperCase();
    $('token').value = token;
    await chrome.storage.local.set({ token });
    await checkConnection(token);
  };
  $('save').addEventListener('click', save);
  $('token').addEventListener('keydown', (e) => {
    if (e.key === 'Enter') save();
  });

  await checkConnection(settings.token);
}

init();
