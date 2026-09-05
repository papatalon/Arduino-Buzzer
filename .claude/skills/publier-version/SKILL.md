---
name: publier-version
description: Publier une nouvelle version de la console de l'animateur (app Flutter Windows) sur GitHub Releases et buzzer.sd6tools.net. À utiliser quand on demande de publier, livrer, sortir ou releaser une version, de faire un build de diffusion, ou de mettre à jour les notes de version.
---

# Publier une version

Sept étapes, dans cet ordre. Chacune peut échouer et se voir ; aucune ne
doit être sautée « parce que rien n'a changé de ce côté ».

## Ce qui rend cette procédure fragile

Trois choses se trompent en silence si on va trop vite.

**Le numéro de build.** C'est lui, et lui seul, qui décide si un poste voit
le bandeau de mise à jour. Oublier de l'incrémenter publie une version que
personne ne sera jamais invité à télécharger : l'app compare `build` et
n'annonce rien quand les deux sont égaux. Rien ne le signalera.

**L'adresse visée par le binaire.** Une version compilée pendant un essai
local peut viser `localhost`. Elle s'installe, se lance, et ne trouve aucun
banque de questions chez l'utilisateur. Vérification obligatoire à l'étape 4.

**Les notes de version.** Elles sont la seule chose que l'utilisateur lit
avant de télécharger, et le bandeau y renvoie par « Nouveautés ». Une
version publiée sans notes, ou avec les notes de la précédente, est pire
qu'une version sans bandeau.

## 1. Choisir la version

Dans `app/buzzer_companion/pubspec.yaml`, la ligne `version: X.Y.Z+N`.

- `X.Y.Z` est ce que l'utilisateur voit. Correctif, ajout, refonte.
- `+N` est le numéro de build. **Toujours +1 par rapport au précédent**,
  sans exception, même pour une correction minuscule.

Modifier avec `sed` ou l'outil d'édition, **jamais avec PowerShell** :
`Get-Content -Raw` lit en codepage ANSI sous PowerShell 5.1 et réécrire le
fichier double-encode tous les accents de ses commentaires.

```bash
cd app/buzzer_companion && sed -i 's/^version: .*/version: 1.1.0+2/' pubspec.yaml
```

## 2. Vérifier que tout passe

```bash
cd app/buzzer_companion && flutter analyze lib test tool && flutter test
```

Et si le firmware a changé depuis la dernière fois :

```bash
cd D:/dev/Arduino/Buzzer && arduino-cli compile --fqbn arduino:avr:mega --output-dir build .
```

Si `arduino-cli` échoue sur `unlinkat ... is a directory`, effacer le cache
de croquis (`AppData/Local/arduino/sketches/<hash>`) et relancer.

## 3. Régénérer le site

```bash
cd app/buzzer_companion && dart run tool/generate_questionnaires.dart
```

Écrit `site/`, dont `version.json` qui porte la nouvelle version et le
nouveau build. La page d'accueil lit la version dans `pubspec.yaml` et en
déduit le lien de téléchargement : rien à recopier à la main.

Vérifier que `site/version.json` porte bien le nouveau numéro de build.

**Cet ordre n'est pas négociable :** le générateur écrit aussi
`assets/questions/banque.json`, la copie embarquée qui sert quand il n'y a pas
de réseau. Construire le binaire avant de régénérer y enferme la banque de la
version précédente, et rien ne le signale : l'écran se remplit, avec les
questions d'avant. C'est ce que l'étape 7 vérifie.

## 4. Construire et vérifier le binaire

```bash
cd app/buzzer_companion && flutter build windows --release
```

Fermer l'application avant de construire, sinon l'éditeur de liens échoue
sur `LNK1168: impossible d'ouvrir buzzer_companion.exe`.

Puis **vérifier l'adresse embarquée**, qui est l'erreur la plus coûteuse :

```bash
grep -ao "https://[a-z0-9.-]*/" app/buzzer_companion/build/windows/x64/runner/Release/data/app.so | sort -u
```

Doit contenir `https://buzzer.sd6tools.net`. Si on y voit `localhost` ou une
adresse d'essai, la constante `kSiteUrl` de `lib/questionnaires/banque.dart`
a été laissée de travers : corriger et reconstruire.

## 5. Empaqueter

```powershell
$rel = "D:\dev\Arduino\Buzzer\app\buzzer_companion\build\windows\x64\runner\Release"
Compress-Archive -Path "$rel\*" -DestinationPath "$env:TEMP\buzzer-console-1.1.0-windows.zip" -CompressionLevel Optimal
```

Le nom du fichier doit correspondre **exactement** à celui que la page
d'accueil calcule, `buzzer-console-<version>-windows.zip`. Sinon le bouton
Télécharger mène à un 404.

Rappel : l'archive ne va **jamais** dans le dépôt. 18 Mo par version, sans
compression delta possible, resteraient dans l'historique pour toujours.

## 6. Publier la version sur GitHub, avec de vraies notes

Les notes de version sont **la seule chose que l'utilisateur lit avant de
télécharger**, et le bandeau de mise à jour y renvoie par « Nouveautés ».
Elles ne sont pas une formalité de fin de procédure.

### D'abord, retrouver ce qui a changé

Le vrai risque n'est pas d'oublier d'écrire les notes, c'est de ne plus
savoir quoi y mettre. La matière est dans le dépôt :

```bash
git log v1.0.0..HEAD --oneline          # remplacer par le tag precedent
git diff v1.0.0..HEAD --stat | tail -5
```

Si le firmware a bougé, il faut le dire, parce que l'utilisateur devra
reflasher :

```bash
git log v1.0.0..HEAD --oneline -- "*.ino" "*.cpp" "*.h"
```

### Ensuite, traduire

**Ne jamais coller la liste des commits.** Un message de commit explique un
changement à quelqu'un qui lit le code ; les notes expliquent une différence
à quelqu'un qui anime une soirée. « Corrige le decalage d'indices des
assignations de sons » devient « Les sons des buzzers changent maintenant à
chaque démarrage. »

Écarter tout ce qui ne se voit pas de l'extérieur : remaniements, tests,
corrections d'outillage. S'il ne reste rien de visible, le dire simplement
plutôt que d'étoffer.

### La structure, reprise de la v1.0.0

```markdown
Une phrase sur ce que cette version apporte.

## Nouveautés
- Ce qui change pour l'animateur, un point par changement visible.

## Corrections
- Seulement ce qui se voyait. Un bogue que personne n'a rencontre n'a pas
  sa place ici.

## Installation
Seulement si elle change. Sinon, ne pas repeter la v1.0.0.

## À savoir
Ce qui pourrait surprendre ou bloquer : reflash du firmware necessaire,
reglage remis a zero, comportement qui change.
```

### Publier

```bash
gh release create v1.1.0 "<chemin du zip>#Console de l'animateur, Windows 64 bits" \
  --title "Console de l'animateur 1.1.0" --notes-file -
```

Puis relire la page publiée : `gh release view v1.1.0`. Des notes vides, ou
celles de la version précédente, sont pires qu'une version sans bandeau.

## 7. Pousser le site

```bash
git add -A && git commit && git push origin main
```

Cloudflare Pages redéploie tout seul. Attendre, puis **vérifier pour de
vrai** :

```bash
cd app/buzzer_companion && dart run tool/verify_banque.dart
curl -s https://buzzer.sd6tools.net/version.json
curl -sIL -o /dev/null -w "%{http_code}\n" <lien de telechargement de la page>
```

Les trois doivent passer : banque cohérente, `version.json` au nouveau
build, lien de téléchargement qui répond 200.

## Vérifier le bandeau, si on veut en être sûr

Le bandeau ne s'affiche que si le build publié dépasse le build local. Pour
le voir sans publier de fausse version : construire l'app avec un build
inférieur à celui publié, lancer, regarder, puis remettre le vrai numéro et
reconstruire.

L'app écrit ce qu'elle a décidé sur sa sortie standard :

```
VersionCheck : locale 1.0.0 build "1" lu comme 1
VersionCheck : publiee 1.1.0 build 2, fermee -1, bandeau=true
```

Sous Windows, la capture d'écran depuis une session non interactive échoue :
demander à l'opérateur de regarder plutôt que de tenter une capture.
