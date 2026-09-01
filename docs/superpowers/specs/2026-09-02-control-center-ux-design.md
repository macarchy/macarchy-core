# Control Center — refonte UX et architecture par modules

Date : 2026-09-02
Statut : validé, en implémentation

## Pourquoi

Le Control Center (`macarchy.control-center`) est un fichier de 1826 lignes qui
possède tout : ses propres contrôles, et la totalité d'une page Jarvis
(état, âme, apparence du poisson, automatismes, mémoire, suggestions).

Trois défauts, dans l'ordre où ils se voient :

1. **Aucune hiérarchie.** Huit tuiles de surface identique : « Ne pas déranger »,
   pressé plusieurs fois par jour, a exactement le même poids que « Limite de
   charge », pressée une fois par mois.
2. **Rien n'est *glanceable*.** On ouvre ce panneau pour *regarder* autant que
   pour cliquer, et la batterie — la chose qu'on vient regarder — est la plus
   petite ligne, en gris, tout en bas.
3. **Ça se lit comme une liste de réglages.** Six filets de séparation, une
   colonne uniforme de rectangles, un titre qui occupe une bande pour nommer
   ce qu'on vient d'ouvrir.

Et une cause structurelle : **la page Jarvis n'a rien à faire là**. Elle
appartient à `macarchy.jarvis`, le plugin qui possède déjà la mascotte et le
service. Tant qu'elle est câblée dans le Control Center, il n'y a pas de
deuxième page possible — chaque nouvelle idée est une rustine de plus dans le
même fichier.

## Ce qu'on construit

Un **contrat d'extension** dont la refonte visuelle est le premier client :
le Control Center devient une coquille qui découvre, charge et héberge des
modules ; ses propres pages sont écrites contre le même contrat que celles
des plugins tiers.

## Le contrat

### Manifeste

Un plugin existant devient hôte de module sans rien perdre :

```json
{
  "kinds": ["service", "control-center-module"],
  "entryPoints": {
    "service": "Service.qml",
    "controlCenterModule": "ControlCenterModule.qml"
  },
  "controlCenterModule": { "apiVersion": 1, "order": 30 }
}
```

Ce que la mécanique Omarchy permet, vérifié dans les sources du shell :

- `PluginRegistry.validateManifest` **ne restreint pas** les valeurs de
  `kinds` — il exige un tableau non vide. Un kind maison passe la validation.
- Les boucles de chargement de `shell.qml` ne cherchent que `bar-widget`,
  `panel`/`overlay`/`menu` et `service` : `control-center-module` est
  **ignoré par le shell**, donc libre pour nous.
- `PluginRegistry.entryPointUrl(manifest, kind)` résout n'importe quelle clé
  d'`entryPoints`, avec le contrôle anti-évasion de chemin déjà en place.
- `bar.shell.pluginRegistry` est atteignable depuis un BarWidget, avec
  `pluginsChanged()` pour la réactivité et `isEnabled(id)` qui respecte
  l'activation par `shell.json`.

### Interface QML

`ControlCenterModule.qml` est un `Item` sans rendu propre :

```qml
Item {
  // injecté par le Control Center
  property var  bar: null           // → bar.shell pour les services in-process
  property var  manifest: null
  property bool panelOpen: false    // le panneau est ouvert
  property bool pageShowing: false  // MA page est à l'écran

  // lu par le Control Center pour la ligne d'accueil
  property string title: ""
  property string glyph: ""
  property string summary: ""       // ligne d'état
  property bool   active: false     // position de l'interrupteur
  property bool   hasToggle: false
  property bool   alert: false      // badge urgent
  property int    order: 50
  signal toggled()

  property Component page: null     // instanciée à la navigation
}
```

Le Control Center ne lit **rien d'autre**. Ajouter une propriété au contrat
impose de bumper `apiVersion` ; un module qui déclare une version majeure
supérieure est refusé et affiche une ligne d'erreur au lieu de rien.

### Ce que la coquille prend en charge

- **Le coût.** Les modules ne sont instanciés qu'à la première ouverture du
  panneau, pas au démarrage du shell. `panelOpen` / `pageShowing` sont les
  seuls interrupteurs de sondage.
- **Le défilement.** La coquille possède le `Flickable` et le `WheelHandler`.
  Hyprland applique `input:touchpad:scroll_factor = 0.4` et Qt applique le
  `pixelDelta` au 1:1 : un `Flickable` nu est inutilisable sur ce trackpad.
  Le piège est résolu **une fois, dans la coquille** ; une page de module est
  du contenu, pas un défileur.
- **Les pannes.** Chaque module vit derrière son `Loader`. `status === Error`
  laisse une ligne en état urgent portant l'`errorString`, jamais un panneau
  cassé.
- **Les composants.** `qs.Ui` est un vrai module QML (`qmldir`), importable
  depuis n'importe quel plugin : un module n'emprunte **rien** au Control
  Center pour composer sa page.

### État : décentralisé, sondage exclusif

Chaque module sonde ce qu'il affiche ; le Control Center sonde ce qu'il
affiche. Deux `Process` peuvent donc lire le même sysfs — mais **jamais en
même temps** : les sondes du cœur sont conditionnées à `route === "main"`,
celles d'un module à son `pageShowing` (ou `panelOpen` pour sa seule ligne
de résumé). On échange une poignée de lignes dupliquées contre une frontière
de plugin réellement étanche ; c'est le bon sens du marché à une frontière
d'extension.

## L'accueil

```
╭──────────────────────────────╮
│  ╭───╮   80 %                │  coiffe (batterie)
│  │ ◕ │   Branchée · plafond  │
│  ╰───╯   à 80 %              │
│                              │
│   DND    Nuit   Thème  Micro │  8 tuiles, 4 colonnes
│   Aqua  Veille  Auto  Charge │
│                              │
│  ☀ ▇▇▇▇▇▇▇░░░░░░░░░░░░       │  écran
│  ♪ ▇▇▇▇▇▇▇▇▇▇▇▇▇░░░░░        │  son
│     Haut-parleurs MacBook    │
│                              │
│  ▤  Titre — Artiste  ⏮ ⏸ ⏭   │  si lecture
│                              │
│  Wi-Fi      Proximus  ●━   › │  lignes
│  Bluetooth  1 appareil ●━  › │
│  Affichage  Écran 40 %     › │  ← module interne
│  Système    Aquarium…      › │  ← module interne
│  Jarvis     Complice ●     › │  ← module externe
╰──────────────────────────────╯
```

Décisions :

- **Largeur 380** (contre 340) : ~88px par tuile, le badge de 28px et son
  label respirent, les lignes d'état tronquent moins.
- **Zéro filet de séparation.** Le groupement passe par les respirations et
  par la forme propre de chaque bloc. Les six hairlines sont ce qui faisait
  « liste de réglages ».
- **La batterie prend la tête**, avec un anneau de charge. `timeToEmpty`
  existe dans Quickshell mais UPower ne publie aucune ligne « time to » sur
  cette machine (batterie macsmc paresseuse, état `pending-charge` permanent
  sous le plafond 80 %) : l'autonomie s'affiche **si** elle est là, sinon la
  phrase d'état prend sa place.
- **Le titre « Control Center » disparaît.**
- **Les huit tuiles restent**, en icône + petit label. La luminosité
  automatique garde ses trois états : badge plein = actif, **anneau** =
  en pause, neutre = éteint. Les phrases qui n'entrent plus sous l'icône
  remontent là où elles ont du sens (« plafonnée à 80 % » est déjà dans la
  coiffe, « en pause » sur la page Affichage).
- **Le rétroéclairage clavier descend** sur la page Affichage : l'ALS le
  pilote la plupart du temps.
- **Wi-Fi, Bluetooth et le son ne sont pas des modules.** Ils pointent vers
  `omarchy.network` / `omarchy.bluetooth` / `omarchy.audio`, qui existent.
  Réimplémenter un sélecteur de réseau serait du travail à jeter.
- **Tout en français.** L'accueil était le dernier îlot anglais.

## Les pages

### Affichage (module interne)
Rétroéclairage clavier, luminosité automatique avec ses trois états expliqués,
veilleuse (night light), apparence claire/sombre.

### Système (module interne)
Batterie et limite de charge (avec la phrase complète), veille prolongée,
aquarium.

### Jarvis (module externe, dans `macarchy.jarvis`)

Principe : **le vivant en haut, les décisions ensuite, les réglages repliés.**

```
╭──────────────────────────────╮
│ ‹  Jarvis              ●━    │  en-tête + mascotte
│ ● Au repos       Cerveau ok  │  LA CONVERSATION
│ « quelle heure il est »      │
│ → Il est minuit vingt.       │
│ [ Écris à Jarvis…          ] │
│  [ Rêver ]  [ Nouvelle conv ]│  actions
│  Suggestions · 2             │  BOÎTE DE RÉCEPTION
│  ┌ 31 août ─────────────────┐│
│  │ Brancher la langue sur…  ││
│  │ [ Confier ]  [ Rejeter ] ││
│  └──────────────────────────┘│
│ › Âme            Complice·fr │  replis, résumé
│ › Automatismes   Silence 23h │  sur la ligne
│ › Apparence      Babel·jaune │
│ › Mémoire        2 leçons    │
╰──────────────────────────────╯
```

≈ 470px replié contre ~1530px aujourd'hui, et rien à plus d'un clic.

- **Les suggestions remontent en deuxième position.** C'est le seul bloc qui
  réclame une décision, et il était en dernier, derrière 1200px de réglages.
  Une boîte de réception qu'il faut faire défiler pour trouver n'en est pas une.
- **L'apparence du poisson descend dans un repli** : cinq rangées de pastilles
  pour un réglage qu'on fait une fois occupaient autant que tout l'état vivant.
- **« Rêver » et « Nouvelle conversation » deviennent des boutons bordés** —
  aujourd'hui du texte centré nu, qui ne se lit pas comme cliquable.
- **Les huit `Repeater` de pastilles deviennent des `ButtonGroup`** (`qs.Ui`) :
  la raggedness vient du `Layout.fillWidth` posé sur des labels inégaux.

## IPC

`jarvis()` se généralise en **`page(id)`** : navigation scriptable vers
n'importe quel module. Rien d'externe n'appelait `jarvis` (vérifié : seuls
`swipeLeft`/`swipeRight` sont câblés dans `input.lua`), mais l'alias est
conservé. C'est aussi le seul moyen de vérifier une page par capture d'écran :
cette machine n'a ni pointeur ni défilement synthétiques.

## Risques

| Risque | Traitement |
|---|---|
| Le rechargement à chaud sert du QML périmé ; redémarrer le shell juste après une écriture dans `plugins/` déclenche un use-after-free Quickshell (upstream #956) | Écrire dans le dépôt → `cp` → laisser retomber → `omarchy restart shell`. Jamais l'inverse. |
| Un module qui travaille dans son `Component.onCompleted` bloque la première ouverture | Règle du contrat : rien de bloquant à la construction |
| `timeToEmpty` vaut 0 sur cette machine | Repli sur la phrase d'état |
| `macarchy.jarvis` gagne un kind | Déjà dans `plugins[]` et déjà de kind `service` : aucune règle d'activation ne change |

## Vérification

Chaque page est ouverte par IPC (`page <id>`) puis capturée avec `grim`, après
`omarchy restart shell`. Les quatre transitions de la grammaire de swipe sont
rejouées (`swipeLeft`/`swipeRight` × panneau ouvert/fermé).
