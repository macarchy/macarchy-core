# Apparence automatique — suivre le soleil depuis le Control Center

Date : 2026-09-02
Statut : validé, en implémentation

## Pourquoi

macOS a un troisième réglage d'apparence, « Auto », qui passe du clair au
sombre au coucher du soleil. Sur cette machine, la moitié existe déjà :

- `omarchy-auto-appearance` (bash, `style/`) bascule Apple Glass ↔ Apple
  Glass Light sur une fenêtre horaire fixe lue dans
  `~/.config/omarchy/auto-appearance.conf`. Son timer systemd est installé mais
  **désactivé** — il ne se pilote que depuis un terminal.
- `macos-dynamic-wallpaper` contient le calcul NOAA de lever/coucher et lit
  latitude/longitude dans `~/.config/omarchy/dynamic-wallpaper.json`.
  L'aquarium lit les mêmes coordonnées. Elles valent aujourd'hui Paris.
- Le module Affichage du Control Center offre « Sombre / Claire » et sa page
  avertit que « l'apparence automatique peut reprendre la main » — sans
  permettre de l'activer.

Il manque : un mode solaire pour le script, un seul endroit qui répond « à
quelle heure le soleil se couche ici », et une interface qui active le tout.

## Ce qu'on construit

Trois choses, toutes dans `omarchy-mac` :

1. **`omarchy-sun`** — un outil qui imprime lever et coucher du jour pour la
   position partagée.
2. **`omarchy-auto-appearance` en mode solaire** — il demande la fenêtre à
   `omarchy-sun` au lieu de la lire dans son conf.
3. **« Auto » dans Affichage** — une troisième pill, une phrase d'état, et un
   bouton « Détecter » qui corrige la position par géolocalisation IP.

Hors périmètre, à dessein : un décalage configurable autour du coucher, le
choix Soleil / Horaires dans l'interface (les horaires restent dans le conf),
une géolocalisation continue, et la refonte du fond d'écran dynamique pour
qu'il consomme `omarchy-sun` (il garde sa copie du calcul).

## `omarchy-sun`

Python 3, sans dépendance, installé dans `~/.local/bin` depuis `style/`.

```
omarchy-sun [--lat N --lon N] [--date YYYY-MM-DD] [--json]
```

- Sans `--lat/--lon`, lit `latitude` et `longitude` dans
  `~/.config/omarchy/dynamic-wallpaper.json`. Fichier absent ou champs
  manquants : message sur stderr, code 2.
- Calcule lever et coucher du **jour civil local** demandé (défaut : aujourd'hui)
  avec l'équation NOAA déjà en service dans `macos-dynamic-wallpaper`
  (altitude −0,833°), précise à la minute.
- Sortie texte, deux lignes en heure locale :

  ```
  sunrise 06:52
  sunset  20:14
  ```

  Sortie `--json` : `{"sunrise": "06:52", "sunset": "20:14", "state": "normal",
  "latitude": 50.46, "longitude": 4.45}`.
- Nuit polaire / soleil de minuit : `state` vaut `down` ou `up`, les deux
  heures sont absentes (`null` en JSON, lignes omises en texte). Code 0.

Le calcul est une fonction pure `solar_pair(lat, lon, when_utc, altitude)`
testable sans fichier ni horloge.

## `omarchy-auto-appearance`

Reste en bash. Le conf gagne une clé :

```bash
MODE=solar        # solar (défaut) | schedule
LIGHT_FROM=07:00  # mode schedule seulement
LIGHT_UNTIL=20:00
```

- `MODE=schedule` : comportement actuel, inchangé.
- `MODE=solar` : `from`/`until` viennent de `omarchy-sun`. Si `state` est
  `up`, on veut le thème clair ; `down`, le sombre. Si `omarchy-sun` échoue
  (pas de position, python absent), le script écrit une ligne sur stderr et
  **sort sans rien changer** — jamais de retour silencieux aux horaires
  fixes, qui ferait croire que le mode solaire fonctionne.
- Les deux garde-fous existants restent tels quels : ne rien faire si le thème
  actif n'est pas un Apple Glass, ne rien faire si le bon thème est déjà posé.
- Nouvelle sous-commande `status`, une ligne parsable pour le Control Center :

  ```
  mode=solar enabled=yes want=dark sunrise=06:52 sunset=20:14
  ```

  `enabled` reflète `systemctl --user is-enabled omarchy-auto-appearance.timer`.
  En mode `schedule`, `sunrise`/`sunset` sont remplacés par `from`/`until`.

Le timer passe de `*:0/15` à `*:0/5`, aligné sur `macos-dynamic-wallpaper.timer`,
pour que la bascule suive le coucher à cinq minutes près. `OnBootSec=1min` et
`Persistent=true` restent.

`install.sh` n'active plus le timer à chaque exécution : il l'active **seulement
si l'unité n'était pas encore installée**. Une fois que l'utilisateur a choisi
Sombre ou Claire depuis le Control Center, réinstaller ne doit pas rallumer
Auto derrière son dos.

## L'état « Auto »

Il n'existe qu'à un endroit : **le timer est enabled**. Ni le conf ni le
Control Center ne stockent de troisième valeur.

- Choisir Auto : `systemctl --user enable --now omarchy-auto-appearance.timer`.
  `--now` démarre le timer, dont `OnBootSec`/`Persistent` déclenchent le
  service dans la minute ; pour ne pas attendre, le module lance aussi
  `omarchy-auto-appearance` directement. Le thème se corrige donc tout de
  suite.
- Choisir Sombre ou Claire : `systemctl --user disable --now` le timer, puis
  `omarchy-theme-set` le thème voulu.
- Le tile « Apparence » de l'accueil garde son geste (un tap inverse le thème)
  et **sort du mode auto** en le faisant, comme macOS quand on choisit
  explicitement. Il ne propose pas d'entrer en auto — c'est le rôle de la page.

Le script conserve son garde-fou « thème non Apple Glass → ne rien faire » :
avec un thème tiers actif et le timer enabled, la pill montre Auto mais rien
ne bouge. C'est voulu et déjà documenté dans le script ; la phrase d'état le
dit (« En attente : le thème actif n'est pas Apple Glass. »).

## Interface — module Affichage, section Apparence

```
Apparence
[ Sombre ] [ Claire ] [ Auto ]
Suit le soleil — lever 06:52, coucher 20:14.
Position 50.46, 4.45                       [ Détecter ]
```

- **Pill** `PillRow` à trois options. Valeur : `auto` si le timer est enabled,
  sinon `light`/`dark` selon `theme.name`.
- **Phrase d'état** (caption, 55 %) :
  - auto, mode solaire : « Suit le soleil — lever 06:52, coucher 20:14. »
  - auto, mode schedule : « Claire de 07:00 à 20:00, sombre le reste du temps. »
  - auto, thème tiers actif : « En attente : le thème actif n'est pas Apple Glass. »
  - auto, `omarchy-sun` en échec : « Position inconnue — appuie sur Détecter. »
  - pas auto : « L'apparence automatique est désactivée. »
- **Ligne position** : « Position 50.46, 4.45 » (deux décimales) et un bouton
  bordé « Détecter ». Pendant la requête le bouton dit « … » et se désactive ;
  en échec réseau la phrase devient « Détection impossible — hors ligne ? » et
  la position précédente reste.
- **Résumé de la ligne d'accueil** : « Auto · Sombre » ou « Auto · Clair » quand
  le timer tourne, sinon l'actuel « Sombre · auto <ALS> ». Le mot « auto » de
  l'ALS y devient ambigu ; la ligne devient « Sombre · luminosité <ALS> ».

### Détecter

Un script, pas du QML : **`omarchy-locate`** (bash, `style/`), pour que la
même détection serve au terminal et à l'aquarium.

- `curl -fsS --max-time 5 http://ip-api.com/json/?fields=status,lat,lon,city`.
  Pas de clé, 45 requêtes/minute, largement assez pour un bouton.
- Succès : réécrit `latitude`/`longitude` dans `dynamic-wallpaper.json` avec
  `jq` (les autres clés intactes, écriture atomique via fichier temporaire
  puis `mv`), imprime `lat lon city`, code 0. Puis relance
  `omarchy-auto-appearance` pour que le thème suive la nouvelle position.
- Échec : rien n'est écrit, message sur stderr, code 1.
- L'aquarium ne relit pas le JSON à chaud ; il le fera à son prochain
  démarrage (changement de thème). Le fond d'écran dynamique le relit à son
  prochain tick. Aucun des deux n'a besoin d'être prévenu.

Première utilisation : je lance `omarchy-locate` moi-même pour remplacer Paris
par la position réelle.

### Sondes du module

Le module suit le schéma existant (sondes seulement page visible, une fois à
l'ouverture du panneau pour le résumé) :

- `omarchy-auto-appearance status` remplace la lecture directe de `theme.name`
  pour tout ce qui concerne l'apparence — une seule ligne donne mode, enabled,
  lever, coucher. `theme.name` reste lu pour savoir quel thème est posé.
- Position : `jq -r '"\(.latitude) \(.longitude)"' dynamic-wallpaper.json`.

Aucune écriture dans `~/.config/omarchy/plugins/` à l'exécution (le shell les
surveille) ; `dynamic-wallpaper.json` et `auto-appearance.conf` sont hors de
ce dossier.

## Fichiers

Nouveaux :

- `style/omarchy-sun`
- `style/omarchy-locate`
- `examples/omarchy.auto-appearance.conf` — le conf commenté (`MODE`, horaires) ;
  aujourd'hui il n'existe que sur cette machine, pas dans le repo.
- `tests/test_omarchy_sun.py` — unittest, importe le script par `importlib`.
- `tests/test_auto_appearance.sh` — le script bash sous un `PATH` qui contient
  un faux `omarchy-sun`, un faux `omarchy` et un faux `systemctl`, avec l'heure
  injectée par une variable `AUTO_APPEARANCE_NOW=HH:MM` (lue seulement si
  définie) ; couvre schedule, solar, fenêtre qui chevauche minuit, `up`/`down`,
  échec de `omarchy-sun`, thème tiers.

Modifiés :

- `style/omarchy-auto-appearance` — `MODE`, `status`, échec explicite.
- `systemd/omarchy-auto-appearance.timer` — cadence 5 min.
- `install.sh` — activation du timer à la première installation seulement.
- `shell-plugins/macarchy.control-center/modules/Display.qml` — pill à trois
  options, phrase d'état, ligne position, résumé.
- `shell-plugins/macarchy.control-center/BarWidget.qml` — le tile Apparence
  désactive le timer avant de poser le thème.
- `README.md` — les deux nouveaux outils dans le tableau `style/`, la ligne
  d'auto-appearance mentionne le soleil.
- `agents/skills/omarchy-asahi/SKILL.md` — `dynamic-wallpaper.json` est aussi
  la position du thème ; `omarchy-locate` la corrige.

## Risques

- **`systemctl enable` depuis quickshell.** `Quickshell.execDetached` hérite
  de la session utilisateur ; `systemctl --user` y trouve `XDG_RUNTIME_DIR`.
  Vérifié par le fait que `omarchy-als daemon` est déjà lancé de la même façon.
- **Coût d'un `omarchy theme set`.** Il redémarre les terminaux. Le garde-fou
  « déjà le bon thème » et la cadence 5 min limitent ça à deux bascules par
  jour ; Détecter en provoque au plus une de plus.
- **ip-api.com en HTTP.** Le service ne fait pas de HTTPS en gratuit. On ne lui
  envoie rien, et une réponse falsifiée ne peut au pire que décaler une heure
  de bascule. Acceptable pour un bouton pressé à la main.
- **Le timer enabled avant cette version** : sur cette machine il est
  désactivé, donc le premier état visible sera « Sombre » ou « Claire », pas
  Auto. Cohérent.

## Vérification

1. `python3 -m unittest discover tests` et `bash tests/test_auto_appearance.sh`
   passent.
2. Lint QML avec le harnais habituel (voir la mémoire `qml-lint-harness`).
3. `./install.sh`, puis `omarchy restart shell` (jamais dans la même commande
   que l'écriture dans `plugins/`).
4. `omarchy-sun` imprime des heures plausibles pour la Belgique début
   septembre (lever vers 06:55, coucher vers 20:15 CEST).
5. `omarchy-shell macarchy.control-center page display` + `grim` : la pill à
   trois options, la phrase, la ligne position.
6. Choisir Auto → `systemctl --user is-enabled omarchy-auto-appearance.timer`
   dit `enabled` et le thème est celui attendu pour l'heure. Choisir Sombre →
   `disabled`, thème sombre. Tap sur le tile Apparence en mode Auto → timer
   `disabled`.
7. Détecter → `dynamic-wallpaper.json` porte la position réelle, les autres
   clés sont intactes (`jq` diff), la phrase montre les nouvelles heures.
