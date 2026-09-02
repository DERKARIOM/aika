# Aika — Rapport final : migration vers l'indépendance de Lovable

Ce rapport couvre l'étape 7 (rapport final) telle que définie au départ :
ce qui a changé, les fichiers modifiés, les dépendances retirées/ajoutées,
les éléments Lovable supprimés, comment lancer le site en local, comment le
publier sur GitHub, comment configurer le déploiement et le domaine
`naniger.com`, et les actions manuelles qu'il vous reste à faire.

**Rien n'a été poussé vers GitHub et aucun enregistrement DNS n'a été
modifié** — conformément à votre consigne.

## 1. Ce qui a changé (résumé)

- Le site n'a plus **aucune** dépendance technique à Lovable : il se clone,
  s'installe, se construit et se déploie avec seulement `npm` et un dépôt
  Git standard.
- Les 11 images du site (logo, capture d'écran hero, 10 captures d'écran
  desktop/mobile) — qui n'étaient que des pointeurs vers le stockage cloud
  de Lovable — ont été récupérées et sont maintenant de vrais fichiers
  commités dans le dépôt.
- Le logo (1,05 Mo à l'origine) a été redimensionné et recompressé à
  54 Ko, sans changement visuel perceptible à la taille où il est affiché
  (favicon/en-tête/pied de page) — cela réduit le poids total du site de
  ~40 %.
- Le `vite.config.ts`, qui *était* entièrement le paquet privé
  `@lovable.dev/vite-tanstack-config`, a été réécrit pour n'utiliser que des
  paquets publics (`@tanstack/react-start`, `@tailwindcss/vite`,
  `vite-tsconfig-paths`, `nitro`, `@vitejs/plugin-react`), avec une sortie
  100 % statique adaptée à GitHub Pages (preset `node-server`, choisi après
  test car les presets `static`/`github-pages` intégrés à Nitro échouaient
  au pré-rendu sur cette version du projet — voir section 8).
- Toutes les métadonnées SEO/réseaux sociaux ont été mises à jour pour
  `naniger.com` : langue de la page (`fr` au lieu de `en`), image de
  partage (`og:image`), URL canonique absolue, `sitemap.xml`,
  `manifest.json`, `robots.txt` mis à jour, `CNAME`.
- Un workflow GitHub Actions déploie automatiquement le site sur GitHub
  Pages à chaque push sur `main` (lint + vérification des types + build +
  déploiement).
- `README.md` a été entièrement réécrit (il contenait auparavant le brief
  de conception original donné à Lovable, pas une vraie documentation).
- `npm run lint`, `npx tsc --noEmit`, `npm run build` et `npm audit` ont
  tous été vérifiés localement et passent sans erreur (0 vulnérabilité).

## 2. Fichiers modifiés, ajoutés, supprimés

**Supprimés (éléments Lovable ou obsolètes) :**

- `.lovable/project.json` — métadonnées internes du projet Lovable
- `bun.lock`, `bunfig.toml` — Bun n'est plus utilisé (voir section 9)
- `src/lib/lovable-error-reporting.ts` — rapportait les erreurs à
  l'infrastructure de Lovable (`window.__lovableEvents`)
- `src/server.ts`, `src/lib/error-capture.ts` — wrapper d'erreurs SSR
  spécifique à Cloudflare Workers, l'infrastructure de déploiement de
  Lovable (voir section 9 pour l'explication détaillée)
- 11 fichiers `*.asset.json` dans `src/assets/` — pointeurs vers le stockage
  cloud (R2) de Lovable, remplacés par les vraies images

**Ajoutés :**

- `src/assets/aika-logo.png`, `src/assets/aika-hero-mobile.jpg`,
  `src/assets/screens/*.{png,jpg}` (11 fichiers) — les vraies images,
  récupérées depuis le site Lovable actuel puis optimisées
- `public/og-image.png`, `public/manifest.json`, `public/sitemap.xml`,
  `public/CNAME`
- `scripts/finalize-static-build.mjs` — finalise le build pour GitHub Pages
  (`index.html`, `404.html`, `.nojekyll`)
- `.github/workflows/deploy.yml` — CI/CD
- `README.md` (réécrit), `DNS.md` (nouveau)
- `package-lock.json` (npm)

**Modifiés :**

- `vite.config.ts` — réécrit entièrement (voir section 1)
- `package.json` — nom du paquet (`aika-website`), suppression de
  `@lovable.dev/vite-tanstack-config`, script `build` étendu
- `src/config/site.ts`, `src/components/aika/Header.tsx`,
  `src/components/aika/Hero.tsx`, `src/components/aika/Sections.tsx` —
  imports d'images (`*.asset.json` → vrais fichiers)
- `src/routes/__root.tsx` — `lang="fr"`, `og:image`, `og:url` absolu,
  suppression de l'appel à `reportLovableError`
- `src/routes/index.tsx` — `canonical`/`og:url` absolus
  (`https://naniger.com/`)
- `public/robots.txt` — ajout de la référence au sitemap
- `AGENTS.md` — réécrit (contenait un avertissement Lovable sur l'historique
  Git)

## 3. Dépendances retirées / ajoutées

- **Retirée** : `@lovable.dev/vite-tanstack-config` (devDependency)
- **Ajoutée** : aucune — tous les paquets nécessaires
  (`@tanstack/react-start`, `nitro`, `@tailwindcss/vite`,
  `vite-tsconfig-paths`, `@vitejs/plugin-react`) étaient déjà présents dans
  `package.json`, simplement utilisés indirectement via le paquet Lovable
  auparavant
- `npm audit` : **0 vulnérabilité**

## 4. Comment lancer le site en local

```bash
cd aika_site_web
npm install
npm run dev
```

Le site est servi sur `http://localhost:8080`.

Pour tester le build de production exact qui sera déployé :

```bash
npm run build
npx vite preview
```

## 5. Comment publier sur GitHub

Le dépôt existe déjà : `git@github.com:DERKARIOM/aika-local-share.git`,
branche `main`, à jour avec `origin` (confirmé localement). Une fois que vous
avez vérifié les changements, il vous suffit de :

```bash
cd aika_site_web
git add .
git commit -m "Rendre le site indépendant de Lovable, préparer naniger.com"
git push origin main
```

Je n'ai rien commité ni poussé — c'est à vous de le faire quand vous êtes
prêt.

## 6. Comment configurer le déploiement (GitHub Pages)

Une fois le push effectué :

1. Sur GitHub, allez dans **Settings → Pages**.
2. Sous **Source**, sélectionnez **GitHub Actions** (pas « Deploy from a
   branch »).
3. Le workflow `.github/workflows/deploy.yml` se déclenchera automatiquement
   au prochain push sur `main` (ou peut être lancé manuellement via l'onglet
   **Actions** → « Deploy to GitHub Pages » → **Run workflow**).
4. Une fois le premier déploiement réussi, votre site sera accessible sur
   `https://derkariom.github.io/aika-local-share/` **avant** que le domaine
   personnalisé ne soit configuré (étape suivante).

## 7. Comment configurer naniger.com

1. Dans **Settings → Pages → Custom domain**, entrez `naniger.com`, puis
   validez.
2. Configurez les enregistrements DNS chez LWS — voir `DNS.md` pour le détail
   exact des enregistrements A et CNAME à créer. **Je n'ai rien modifié dans
   votre DNS** : ce fichier est uniquement une documentation.
3. Une fois le DNS propagé et GitHub Pages ayant validé le domaine, cochez
   **Enforce HTTPS** dans les mêmes réglages.

## 8. Point important : rendu du site (SPA statique, pas de SSG par page)

Le site est généré comme une **coquille HTML unique côté client** (SPA) :
`_shell.html` contient un `<head>` complet et correct (titres, meta
description, Open Graph, etc. — donc les aperçus de partage sur les réseaux
sociaux et le référencement de base fonctionnent), mais le `<body>` est
presque vide au chargement : tout le contenu visible (Hero, Vision,
fonctionnalités, etc.) n'apparaît qu'après l'exécution du JavaScript dans le
navigateur.

C'est un compromis courant pour les sites React purement statiques hébergés
sans serveur (GitHub Pages ne peut pas exécuter de rendu serveur à la
demande) et le contenu du site étant actuellement mono-page, l'impact SEO
réel est limité — mais je tiens à le signaler explicitement, car ce n'est
pas un rendu « HTML complet dès le premier octet » comme le ferait un vrai
site pré-rendu page par page. Si un meilleur référencement multi-pages
devient important plus tard, la solution serait d'ajouter un vrai
pré-rendu statique par route (nécessiterait de revisiter le preset Nitro
utilisé).

J'ai testé le preset `static`/`github-pages` natif de Nitro en premier
(celui qui, en théorie, pré-rend chaque page en HTML complet) : il échouait
systématiquement au build sur cette version du projet (404 lors du
pré-rendu, puis erreur fatale). Le preset `node-server` que j'ai retenu à la
place contourne ce problème et produit un build fonctionnel, au prix de ce
compromis SPA plutôt que SSG « pur ».

## 9. Autres décisions prises pendant la migration (transparence)

- **Choix du gestionnaire de paquets** : vous aviez répondu « oui » à ma
  question « npm (déjà installé…) ou Bun (l'outil actuel du projet) ? ».
  J'ai interprété ce « oui » comme confirmant **npm**, l'option que j'avais
  listée en premier — c'est ce qui a été fait (`bun.lock`/`bunfig.toml`
  supprimés, `package-lock.json` généré). Dites-le-moi si ce n'était pas
  votre intention, ce serait facile à changer.
- **`src/server.ts` supprimé plutôt que restauré** : ce fichier était un
  wrapper d'erreurs SSR écrit spécifiquement pour le preset Cloudflare
  Workers de Lovable. Le site n'exécutant plus aucun rendu serveur en
  production (voir section 8), ce fichier n'avait plus d'utilité — sa
  logique de secours faisait par ailleurs doublon avec le middleware
  d'erreurs déjà présent nativement dans `src/start.ts` (conservé, lui,
  car c'est un fichier standard de TanStack Start, indépendant de
  Lovable). Je l'ai donc supprimé plutôt que de le réactiver.
- **Logo optimisé** : au passage, j'ai réduit le poids du logo de 1,05 Mo à
  54 Ko (redimensionnement à une résolution raisonnable pour un usage
  UI/favicon) — c'était un point signalé comme amélioration possible dans
  l'audit initial, je l'ai appliqué car le risque était nul et le gain
  significatif sur le poids total du site.

## 10. Ce qu'il vous reste à faire manuellement

- Pousser les changements vers GitHub (section 5) — je ne l'ai pas fait.
- Configurer **Settings → Pages → Source = GitHub Actions** (section 6).
- Créer les enregistrements DNS chez LWS d'après `DNS.md` (section 7) — je
  n'ai rien modifié.
- Configurer le domaine personnalisé et activer HTTPS dans GitHub Pages
  une fois le DNS propagé.
- Remplir les vraies URL de téléchargement dans `src/config/site.ts`
  (`DOWNLOAD_LINKS`) et l'e-mail de contact — actuellement des
  valeurs `null`/placeholder, affichées comme « Bientôt disponible ».

## 11. Amélioration facultative non appliquée (nice-to-have)

- Les polices Google Fonts sont actuellement chargées depuis
  `fonts.googleapis.com`/`fonts.gstatic.com` (comme dans la version
  Lovable d'origine). Les auto-héberger (les inclure dans `public/`)
  éliminerait une dépendance réseau externe et gagnerait quelques dizaines
  de ms de chargement, mais ce n'est pas bloquant et n'a pas été fait pour
  rester fidèle à la consigne de ne pas modifier ce qui fonctionne déjà
  sans réel bénéfice majeur.
