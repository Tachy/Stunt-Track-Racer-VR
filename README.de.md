# Stunt Track Racer VR

[English](README.md) · **Deutsch**

VR-Stuntrennen auf erhöhten Strecken ohne Leitplanken für **Godot 4.7.2** (GDScript, OpenXR, Forward+).
Inspiriert von *Stunt Car Racer* (Geoff Crammond, MicroStyle, 1989). Ein eigenständiges Fanprojekt ohne Daten, Grafiken oder Code des Originals; nicht verbunden mit den Rechteinhabern.
Gesteuert wird mit einem Thrustmaster-Lenkrad samt Pedalen (getestet wird die Erkennung „Thrustmaster T80 (USB)“), Fallback ist die Tastatur.

## Starten

Das Spiel startet **entweder** in VR **oder** auf dem Desktop. Während des Spiels lässt sich nicht umschalten.

| Modus | Doppelklick | Befehl |
|---|---|---|
| **VR** | `Start-VR.cmd` | `"<Godot.exe>" --path "<Projektordner>"` |
| **Desktop** | `Start-Desktop.cmd` | `"<Godot.exe>" --xr-mode off --path "<Projektordner>" -- --no-xr` |

Die `.cmd`-Dateien lesen den Pfad der Godot-Exe aus `start.cfg`: Kopiere `start.cfg.example` nach `start.cfg` und trage dort den Pfad deiner Godot-4.7-Exe ein (`start.cfg` bleibt lokal, es liegt nicht im Repository).

- **VR:** Das Headset muss eingeschaltet und seine OpenXR-Software (z. B. Pimax, SteamVR) gestartet sein. Sonst erscheint ein Hinweis, und das Spiel beendet sich. Es gibt keinen stillen Wechsel auf den Desktop.
- **Desktop:** OpenXR wird gar nicht gestartet. Mit gedrückter rechter Maustaste und Ziehen sieht man sich um, F12 setzt den Blick zurück.

Alternativ: Projekt im Godot-Editor öffnen und F5 drücken. Das startet in VR. Für Desktop trägst du unter *Projekt → Projekteinstellungen → Editor → Run → Main Run Args* den Wert `--xr-mode off -- --no-xr` ein.

**Sprache:** Englisch ist Standard. Deutsch stellst du unter *Settings → Language* ein, die Wahl wird gespeichert.

**Beim ersten Start:** Menü → *Lenkrad kalibrieren*. Danach:

| Aktion | Lenkrad | Tastatur |
|---|---|---|
| Lenken / Menü wählen | Lenkrad drehen | Pfeil links/rechts bzw. hoch/runter |
| Gas / Menü OK | Gaspedal | Pfeil hoch, Enter |
| Bremse, Rückwärts (im Stand) / Menü zurück | Bremspedal | Pfeil runter, Esc |
| Boost | belegte Taste | Leertaste |
| Pause | belegte Zurück-Taste | Esc |
| Kran: Auto absetzen | Gas | Pfeil hoch / Enter |
| **VR zentrieren** | optional belegte Taste | **F12** |
| Screenshot | | F9 |
| FPS-Anzeige (vor dem Auge) | | F10 |

Hinweis: F12 kommt nur an, wenn das Godot-Fenster den Fokus hat. Ohne Force Feedback hat der Thrustmaster keine Rückstellkraft. In der Thrustmaster-Systemsteuerung sollte deshalb *Auto-Center: by the wheel* aktiv sein. Den dort eingestellten Lenkwinkel trägst du in den Einstellungen unter *Lenkradbereich* ein (Standard 900°). Die Lenkung ist **linear 1:1**: Lenkrad am Anschlag (bei 900° also ±450°) bedeutet Räder am Anschlag (*Max. Radeinschlag*, Standard 32°, ergibt eine Übersetzung von etwa 14:1 wie im echten Auto). Mit dem Lenkrad wird der Einschlag bei hohem Tempo nicht künstlich reduziert, das gilt nur für die Tastatur.

## Blickführung in VR

Die Grundblickrichtung folgt der Fahrtrichtung (Gieren) vollständig. Nicken und Rollen folgt sie nur zu einem einstellbaren Anteil (*Blick-Neigung*, Standard **50 %**), mit einer **Faltungsregel**:
- Bis ±90° folgt der Blick dem Anteil.
- Darüber nimmt der Anteil wieder ab. Über Kopf (Looping-Scheitel, Überschlag) ist der Blick waagerecht.

Bei 50 % bleibt der Blick so immer innerhalb von ±45° zur Geradeaussicht, in Nick- und Rollrichtung, ohne Sprünge. Darauf setzt die Brille mit vollem 6DOF auf. **F12** macht die aktuelle Kopfposition zum Augpunkt im Sitz. Dabei werden nur Gierwinkel und Position übernommen, damit der Horizont nie schief steht. Der Wert wird gespeichert. Siehe `scripts/car/cockpit_math.gd` und `scripts/autoload/xr_manager.gd`.

## Fahrzeug, Physik, Licht

- **Aufbau wie im Original:** Die Kabine sitzt weit hinten. Davor liegt eine lange Nase mit offenem V-Motor (Kompressor, Krümmer). Die großen Vorderräder stehen frei, mit sichtbarer Doppelquerlenker-Aufhängung und Schraubenfedern, die mit der Physik ein- und ausfedern. Beim Abheben senken sich die Räder träge aus.
- **Physik:** Jolt mit 120 Hz und Interpolation. Raycast-Federbeine pro Rad (Federweg 0,5 m), Querstabilisatoren, Schlupf-Reifenmodell. Gravitation 9,81 m/s². Alle Zeiten laufen in Echtzeit. In der Luft richtet sich das Auto entlang der Flugparabel aus: Die Nase zeigt in Richtung des Geschwindigkeitsvektors, das Auto rollt nicht, und die Neigung ist auf ±60° begrenzt (Parameter `air_align_*` in `car_tuning.gd`).
- **Maße:** Radstand 2,9 m, Spur 1,96 m, Raddurchmesser vorn 0,84 m und hinten 0,96 m, 900 kg, Augpunkt etwa 1,75 m über der Fahrbahn. Strecken: 10 m breit, 5–30 m hoch, Kurvenradien 50–60 m, Sprünge über 10–30 m, Rundenlängen 870–1900 m.
- **Licht:** Die Sonne ist ein gerichtetes Licht mit parallelen Strahlen aus unendlicher Entfernung und wirft Schatten (in den Einstellungen abschaltbar). Diffuses Himmelslicht hält den Schatten hell genug. Flat-Shading, keine Glanzlichter.
- **Leistung** (gemessen mit `--vr-bench`: zwei Augen in Pimax-Auflösung 5692×4220 und 5194×4220, MSAA 4x, Schatten an): etwa 3,3 ms GPU-Zeit pro Frame für beide Augen auf der RTX 4090, also etwa 300 FPS GPU-Limit. 90 Hz brauchen weniger als 11,1 ms.

## Spielinhalt

- **Loop and Jump** (nur Übungsfahrt): eine Acht mit **Unterführung** an der Kreuzung (der obere Ast läuft auf einem Brückendeck mit Dicke, der untere fährt darunter durch), dazu **zwei Loopings**, ein Sprung und Steilkurven. Loopings sind bis zur senkrechten Tangente mit Mauer bis zum Boden gebaut, im Überkopf-Teil als gebogene Fahrbahnplatte.

- **8 Strecken**, frei nachgebaut (keine Originaldaten). Div 4: First Flight, Camel Back · Div 3: Mega Ramp, Stone Hopper · Div 2: Big Dipper, The Tower · Div 1: Bridge Run (mit Zugbrücke), Ski Flyer
- **Grand Tour** (nur Übungsfahrt, 3,7 km): alle Elemente in einer Runde – Kamelbuckel, zwei Sprünge, eine Grube, die Zugbrücke, ein Looping und ein 400 m langer **Tunnel** mit überhöhter S-Kurve, der 17 m unter der Startgeraden durchführt. Ein Tunnel entsteht überall, wo die Fahrbahn unter den Boden abtaucht: zuerst ein offener Einschnitt mit Stützmauern, dann ein Portal und eine beleuchtete rechteckige Röhre, die Kurven und Querneigung mitmacht.
- **Erhöhte Strecken ohne Leitplanken.** Wer herunterfällt, wird vom **Kran** zurückgesetzt. Auch der Start erfolgt am Kran („DROP START“).
- **Schaden:** Ein Riss wandert über den Überrollbügel, schwere Treffer schlagen Löcher. Die Löcher bleiben die ganze Saison und verstärken weiteren Schaden. Ist der Riss voll, ist der Wagen Schrott.
- **Boost**, begrenzt pro Rennen. 3 Runden, 1 gegen 1. Gegner-KI mit 11 Fahrern und deren Eigenheiten (drängeln, blockieren, am Rand fahren, Wheelies).
- **Liga** mit 4 Divisionen à 3 Fahrer, Auf- und Abstieg. Nach dem Sieg in Division 1 folgt die Super League.
- Prozeduraler Motorsound, Effekte, Retro-Pixelschrift. Oberfläche auf Englisch und Deutsch. Es werden keine externen Assets benötigt.

## Online (1 gegen 1)

Zwei Spieler fahren über das Internet gegeneinander, verbunden über einen kleinen Server (`server/`, Go, wenige MB, keine Physik). Jedes Spiel rechnet sein eigenes Auto und sendet dessen Zustand 30-mal pro Sekunde (36 Byte pro Paket, etwa 2,2 KB/s). Das Gegnerauto ist eine vollwertige physikalische Kopie, die zum empfangenen Zustand gezogen wird. Der Server bringt die nächsten zwei suchenden Spieler zusammen, legt den gemeinsamen Drop-Zeitpunkt fest und entscheidet über den Sieg. Protokoll: `docs/net-protocol.md`.

- Name, Autofarbe und Serveradresse werden im MULTIPLAYER-Menü eingetragen (über die Tastatur oder Zeichen für Zeichen mit dem Lenkrad). Die Adresse ist `host` oder `host:port`; ohne Port gilt 27015. Der Server selbst braucht keine Konfiguration.
- Server starten: `go run ./server -v` (in `server/`), oder `docker build -t stunt-racer-server server/` und `docker run -d -p 27015:27015/udp stunt-racer-server`, oder die systemd-Unit in `server/deploy/`. Es muss nur UDP-Port 27015 offen sein. Schritt für Schritt: `docs/server-install.de.md`.
- Test ohne Menü: `-- --track=camel_back --online=127.0.0.1:27015 --name=ANN --autopilot` in zwei Instanzen (ohne `--fixed-fps`, weil das Netz Echtzeit braucht). Mit `-sim-latency 80ms -sim-loss 0.03` simuliert der Server eine schlechte Leitung; `go test ./...` in `server/` testet den Server.

## Entwicklung / Tests

```
set G="<Pfad>\Godot_v4.7.2-stable_win64_console.exe"
%G% --headless --xr-mode off --path . --import
%G% --headless --xr-mode off --path . --script res://tests/run_tests.gd
%G% --headless --xr-mode off --fixed-fps 120 --path . -- --track=ski_flyer --opponent=5 --autopilot --debug --quit-after=200
```

Kommandozeilen-Optionen stehen nach `--`, siehe `scripts/main.gd`: `--track=<id>`, `--opponent=<0..10>`, `--super`, `--autopilot`, `--no-xr`, `--menu=<screen>`, `--joydump`, `--debug`, `--chase` (Kamera hinter dem Auto), `--fps`, `--vr-bench`, `--render-scale=<x>`, `--screenshot=<s>`, `--quit-after=<s>`, `--lang=<en|de>`, `--online=<host[:port]>`, `--name=<name>`, `--car-photos`.

Das Fahrverhalten wird zentral in `scripts/car/car_tuning.gd` eingestellt, die Strecken in `scripts/track/track_library.gd`.

Benutzerdaten liegen unter `%APPDATA%\Godot\app_userdata\Stunt Track Racer VR\`: `settings.cfg`, `input.cfg`, `save.json`, `logs\`, `screenshots\`.

## Lizenz und Herkunft

- Code, Strecken, 3D-Modelle (prozedural erzeugt), Sounds (synthetisiert) und Pixelschrift: eigene Arbeit, **MIT-Lizenz** (siehe `LICENSE`).
- `icon.svg` ist das Godot-Standardsymbol (Godot Engine, CC BY 4.0) und kann durch ein eigenes ersetzt werden.
- `openxr_action_map.tres` ist Godots Standard-Aktionsbelegung für OpenXR.
- Spielidee und Mechaniken sind von *Stunt Car Racer* (1989) inspiriert. Es werden keine Daten, Grafiken, Sounds oder Code des Originals verwendet.

## Entstehung

Das Spiel ist im Dialog mit einem KI-Assistenten (Claude Code) entstanden: Recherche zum Original, Architektur, gesamter GDScript-Code, Streckenentwürfe (mit einem kleinen Python-Löser für geschlossene Rundkurse) und Tests. Geprüft wurde mit automatischen Tests (`tests/run_tests.gd`), simulierten Rennen im Headless-Modus (Autopilot gegen KI) und Screenshots. Das eigentliche Fahrgefühl in VR und mit Lenkrad wurde vom Menschen beurteilt.
