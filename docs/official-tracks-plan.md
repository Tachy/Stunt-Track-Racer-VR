# Offizielle Strecken und Release-Build – Plan

Stand 2026-10-09.

## Ziel

Es gibt drei Arten von Strecken:

| Art | Heute | Künftig |
|---|---|---|
| 1. Liga (8 Strecken) | fest im Code (`TrackLibrary.TRACKS`) | **offiziell**: Datei im Repo, im Spiel und im Server eingebaut |
| 2. Erweiterte Release-Strecken (Grand Tour, Loop and Jump, künftig mehr) | fest im Code | **offiziell**, wie Art 1 |
| 3. Eigene Strecken der Spieler | `user://tracks/*.json` | unverändert (online geht die Definition mit) |

- Die offiziellen Strecken lassen sich als „Admin“ im Streckeneditor laden, feintunen und speichern.
- Online fahren beide Spieler immer die **offizielle Fassung vom Server**. Lokal geänderte Dateien wirken online nie.

Grenze: Das Spiel ist quelloffen, die Autos laufen client-autoritativ. Wer den Client umbaut, kann auch die Physik manipulieren. Das Ziel ist, dass geänderte Strecken*dateien* online keine Wirkung haben. Eine Manipulation erfordert dann denselben Aufwand wie jeder andere Cheat.

## 1. Offizielle Strecken als Dateien

- **Quelle:** eine einzige, `server/official/<id>.json` im Editor-Format (`pieces`, `heights`, `start`, ... plus `def`). Die Datei liegt im Server-Modul, damit `go:embed` sie ohne Kopierschritt findet. Godot liest sie als `res://server/official/<id>.json`. Der Export muss `server/official/*.json` mitnehmen (Export-Filter).
- **Metadaten** bleiben pro Strecke erhalten: Name, Theme, Startbasis, Boost-Werte, Division, Liga oder erweitert. Der Editor überschreibt sie beim Speichern nicht mehr mit Standardwerten.
- **Reihenfolge und Zuordnung:** Liga-Reihenfolge, Divisionen und alte Kennungen bleiben im Code (`ORDER`, `DIVISION_TRACKS`, `LEGACY_IDS`), nur die Streckendaten kommen aus den Dateien.
- **Laden:** `TrackLibrary.TRACKS` (Konstante) wird zu einem einmal geladenen Verzeichnis. `get_def()`, Menü, Liga und Tests lesen weiter darüber.

## 2. Einmalige Umrechnung (Konverter)

Die heutigen Strecken haben Höhen pro Stück (`h`, Profile, `bump`) und Gruben aus drei kurzen steilen Stücken. Der Editor arbeitet mit einer Höhenkurve und Wänden. Der Konverter (Headless-Skript, einmal):

1. Er baut jede Strecke mit dem alten Verfahren (`TrackPath`).
2. Er setzt Kurvenpunkte an Stückenden, Buckelspitzen und Profilknicken. Gruben und Schanzenkanten werden echte Wände (gelber Fußpunkt).
3. Er vergleicht Meter für Meter alt und neu und ergänzt Punkte, wo es mehr als 0,2 m abweicht.
4. Er schreibt die Dateien und einen **Abweichungsbericht** pro Strecke: größte Abweichung, Gruben und Wände, Länge. Der Bericht geht an dich, bevor etwas in der Liga landet.

Grundriss, Kurven (auch Radien und Winkel außerhalb des Katalogs), Querneigung und Flags werden 1:1 übernommen.

## 3. Editor-Lücken schließen

- Kurven außerhalb des Katalogs und ihre feste Querneigung bleiben beim Laden und Speichern erhalten. Neu gesetzt wird weiter nur aus dem Katalog.
- `no_crane` bleibt erhalten und wird mit der Taste **N** am markierten Abschnitt umgeschaltet. Im Plan und in 3D wird es angezeigt.
- `gap` (Lücke in der Bahn, nötig für Grand Tour und Loop and Jump) bleibt erhalten, Taste **G**. Bisher löscht der Editor beide Flags beim Laden.
- Die Metadaten (siehe 1) stehen im Admin-Modus in einer kleinen Zeile: Theme, Boost, Basis.

## 4. Admin-Modus

- **Start:** `--admin` (bzw. `Start-Admin.cmd`), nur beim Lauf aus dem Projektordner. Im exportierten Spiel ist `res://` schreibgeschützt, dort ist der Modus aus.
- **Laden:** „LADEN …“ zeigt dann zusätzlich die offiziellen Strecken (markiert).
- **Speichern:** Eine offizielle Strecke wird zurück nach `server/official/<id>.json` geschrieben, also ins Repo. Du committest wie gewohnt. Offiziell, auch online, wird die Änderung erst mit dem nächsten Release.
- **Ohne `--admin`:** Offizielle Strecken lassen sich laden, aber nur als **Kopie** in die eigenen Strecken speichern (Art 3).

## 5. Server liefert die offiziellen Strecken

- **Einbetten:** Der Server bettet `official/*.json` per `go:embed` ein (komprimiert wie heutige TRACK-Teile).
- **Ausliefern:** Bei MATCH für eine offizielle Kennung schickt der Server **beiden** Spielern die Definition als TRACK-Teile (wie heute die geteilte Strecke an den zweiten Spieler).
- **Sicherheitslücke schließen:** Uploads (TRACK vor OFFER/JOIN) werden nur für `custom/...` angenommen. Für offizielle Kennungen verwirft der Server sie. Heute leitet er sie weiter: Ein umgebauter Client könnte eine veränderte `camel_back` hochladen, und der Gegner würde sie fahren.
- **Client:** Online baut er eine offizielle Strecke aus den vom Server empfangenen Daten, nie aus der lokalen Datei. Fehlen sie (alter Server), nimmt er übergangsweise die lokale und schreibt es ins Log.
- **Protokoll:** Die Doku (`docs/net-protocol.md`) beschreibt das. Es braucht keinen neuen Pakettyp, TRACK gibt es schon. Die Grenze von 16 × 1000 Bytes komprimiert reicht für die größte Strecke (wird geprüft).

## 6. Absicherung (Tests)

- Die vorhandenen Strecken-Tests (Runde geschlossen, Liga-Merkmale, keine ungewollten Kreuzungen, Gruben) laufen gegen die Dateien.
- Ein neuer Test prüft, dass die umgerechneten Strecken höchstens 0,2 m vom alten Stand abweichen. Er läuft einmal zur Umrechnung und bleibt danach als Doku stehen bzw. wird entfernt.
- Go-Tests prüfen: Der Server liefert für offizielle Kennungen seine Fassung an beide, verwirft fremde Uploads dafür und reicht `custom/`-Strecken weiter wie bisher.
- Die eingebetteten Dateien sind dieselben wie im Spiel (eine Quelle, also automatisch).

## 7. Release-Build mit `/build`

Ziel: Ein Befehl `/build` in Claude Code erzeugt die Windows-Exe und bringt sie zusammen mit dem Release von release-please auf GitHub. Die Version steht dabei überall gleich: im Quellcode, im Spiel, in der Exe und im Release-Tag.

### Version im Quellcode (release-please)
- Neue Datei `scripts/core/version.gd`: `const VERSION := "0.1.0" # x-release-please-version`.
- `release-please-config.json` bekommt `extra-files` mit dieser Datei. Der Release-PR setzt dann die neue Version im Code mit, parallel zu `CHANGELOG.md` und dem Manifest.
- `project.godot` bekommt die Version nicht als Marker, weil der Godot-Editor die Datei beim Speichern neu schreibt und Kommentare verliert. Das Build-Skript setzt `application/config/version` und die Dateiversion der Exe aus `version.gd`.
- Das Hauptmenü zeigt die Version an (unten klein), die Online-Anmeldung schickt sie mit (Logs, später Versionsprüfung).

### Export
- `export_presets.cfg` (im Repo) mit der Voreinstellung „Windows Desktop“:
  - OpenXR an, PCK in die Exe eingebettet, Symbol aus `icon.svg`;
  - Filter nimmt `server/official/*.json` mit, nicht aber `tests/`, `docs/`, `server/*.go`.
- `tools/build.ps1`:
  1. prüft, ob die Export-Templates für Godot 4.7.2 installiert sind; fehlen sie, lädt es sie einmalig herunter und installiert sie;
  2. lässt die Tests laufen (Abbruch bei Fehlern);
  3. exportiert headless nach `build/StuntTrackRacerVR.exe`;
  4. packt `StuntTrackRacerVR-<version>-windows.zip` mit der Exe sowie `Start-VR.cmd` und `Start-Desktop.cmd` (beide rufen dann die Exe auf, VR bzw. `--xr-mode off -- --no-xr`), `README` und `LICENSE`;
  5. baut den **Installer** (siehe unten).
- `build/` steht in `.gitignore`.

### Installer (Inno Setup)
- `tools/installer.iss` (Inno Setup 6). Das Build-Skript ruft `iscc` mit der Version auf. Fehlt Inno Setup, installiert es das einmalig über `winget install JRSoftware.InnoSetup`.
- Ergebnis: `StuntTrackRacerVR-<version>-setup.exe`.
- **Installation** nach `%LOCALAPPDATA%\\Programs\\Stunt Track Racer VR`, ohne Administratorrechte.
- **Startmenü:** „Stunt Track Racer VR“ (VR) und „Stunt Track Racer VR (Desktop)“, optional ein Desktop-Symbol.
- **Deinstallation** über „Apps & Features“, mit Version und Herausgeber.
- **Updates:** Ein neuer Installer installiert über die alte Version (feste AppId). Spielstände, Einstellungen und eigene Strecken liegen in `%APPDATA%` und bleiben erhalten.
- **Ohne Code-Signatur:** SmartScreen meldet „Unbekannter Herausgeber“. Eine Signatur lässt sich später im Build-Skript nachrüsten (`signtool`).
- **Am Release** hängen dann der Installer (für die meisten) und die ZIP (ohne Installation) sowie wie bisher das Server-Binary.

### Der Befehl `/build` (`.claude/commands/build.md`)
1. **Release-PR suchen:** Er sucht den offenen Release-PR von release-please und liest dessen Version. Ohne offenen PR baut er nur lokal (Testbuild mit Version `x.y.z-dev`) und hört auf.
2. **Bauen:** Er baut mit dieser Version (`tools/build.ps1 -Version x.y.z`) und lässt dich die Exe kurz testen. Du bestätigst.
3. **Release auslösen:** Er merged den Release-PR (`gh pr merge`). release-please legt in der CI Tag und Release an, der vorhandene Job hängt das Server-Binary an.
4. **Exe anhängen:** Er wartet auf das Release und hängt die ZIP-Datei an (`gh release upload`).

Damit entsteht ein Release nur über `/build`, und Release, Version im Code, Server-Binary und Exe gehören immer zusammen.

### Alternative: Exe in der CI bauen
Ein zweiter CI-Job (wie `server-binary`) lädt Godot und die Templates herunter und exportiert die Exe auf GitHub selbst. Vorteil: reproduzierbar, ohne lokalen Schritt. Nachteile: jeder Release lädt rund 1 GB Templates, und du hast vor dem Veröffentlichen keine Gelegenheit, die Exe in VR zu testen. `/build` wäre dann nur noch der lokale Testbuild plus Merge.

## Reihenfolge

1. Dateien und Laden (`TrackLibrary`), noch mit den alten Daten 1:1 im neuen Format (Höhen pro Stück). Tests grün, Spiel unverändert.
2. Editor: Flags, Kurven außerhalb des Katalogs, Metadaten, Admin-Modus.
3. Konverter und Abweichungsbericht, Umstellung auf Höhenkurven. **Halt: Bericht an dich.**
4. Server: Einbetten, Ausliefern, Uploads absichern. Client: Server-Fassung nutzen. Go- und GDScript-Tests.
5. Release-Build: Version im Code, Export-Voreinstellung, `tools/build.ps1`, `/build`. Dieser Schritt hängt von den anderen nicht ab und kann auch zuerst kommen.

Jeder Schritt bekommt einen eigenen Commit (`feat:`/`fix:`).
