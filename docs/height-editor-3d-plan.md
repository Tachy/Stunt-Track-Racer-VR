# Höheneditor in 3D – Plan

Stand 2026-10-09. Ersetzt den Profilstreifen (`HeightProfile`) und die kleine 3D-Vorschau (`EditorPreview`) der Höhenstufe.

## Umsetzungsstand (2026-10-09: alle Phasen umgesetzt)

| Phase | Commit |
|---|---|
| 1 `HeightRibbon` + Tests | `f18487e` |
| 2 Durchsicht | `fef5498` |
| 3+4 `HeightEditor3D`, `EditorView`, `PlanNav` | `0280863` |
| 5 VR (`VrEditorHost`, Menüeintrag) | `1174a4d` |
| 6 Leistung | `765fc11` |

Abweichungen vom Plan:
- **Kein Physikkörper im Editor-Bau:** Strecke und Boden werden im Worker-Thread gebaut. Klicks auf die Fahrbahn trifft ein eigener Strahl-Dreieck-Test gegen die Fahrbahnstreifen statt eines Raycasts, und die Zugbrücke liegt im Editor flach als reines Mesh.
- **VR-Kamera wie am Desktop:** Auch in VR schaut die Kamera auf den Drehpunkt und neigt sich beim Umkreisen mit (eine erste Fassung hielt sie waagrecht, das Hoch/Runter wirkte dann wie eine Verschiebung). Der Kopf bewegt sich frei dazu (6DOF).
- **Bildschirmkugel statt Kopf-HUD:** Zeiger und Oberfläche liegen auf einer Kugel mit 2 m Radius um das Auge, 160° × 110° breit, 0,05° pro Pixel. Die Maus bewegt den Zeiger frei über diesen Bereich, der Strahl geht vom Auge durch den Zeiger. Die Kugel hängt fest am XR-Rig am Augpunkt des Sitzes (sie bewegt sich starr mit der Kamera); der Kopf bewegt und dreht sich frei darin (6DOF), der Strahl geht vom echten Auge durch den Zeigerpunkt auf der Kugel. Bedienelemente und Grundriss liegen im mittleren Bereich (1500 × 860 px), in der Höhenstufe ist der Rest durchsichtig. Eine erste Fassung mit flachem Panel vor dem Sitz (sprang, war zu groß, Zeiger gefangen) wurde so ersetzt.
- **Tests ohne Headset:** `--editor-vr-screen` zeigt das VR-Panel am Desktop.
- **Steigungsprüfung schneller** (`HeightSpline.segment_hermite`), bei gleichen Abtastpunkten und gleichen Ergebnissen.
- **Offen bleibt die Frage nach dem Profilstreifen** (siehe unten). Er ist entfernt.

## Ziel

- **Hauptansicht = 3D**, am Desktop und in VR. Oben links liegt ein **Navigationsfenster** mit dem Grundriss: rechte Maustaste verschiebt, das Mausrad zoomt, ein Klick wählt ein Streckenelement.
- **Höhen werden direkt in 3D bearbeitet.** Höhenlinie und Punkte liegen auf der gerenderten Fahrbahn. Ein Punkt wandert beim Ziehen auf der senkrechten „Höhenfläche“ über der Grundrisslinie und hat wie bisher zwei Freiheitsgrade: entlang der Strecke und in der Höhe. Die Fahrbahn folgt dem gezogenen Punkt 4-mal pro Sekunde.
- **Logik der Punkte unverändert:** `TrackEditorModel.add_point / move_point / delete_point / toggle_corner`, Wand-Snapping, Steigungsgrenze und Undo bleiben, wie sie sind.
- **Durchsicht:** Boden, Tunnelwände, Tunneldecke und Seitenwände von Einschnitten (Schluchten) werden nur im Editor mit 30 % Deckung gerendert.

## Entscheidungen (mit dem User geklärt)

| Frage | Entscheidung |
|---|---|
| Bedienung in VR | Maus und Tastatur. Der Mauszeiger ist ein 3D-Zeiger im Blickfeld, das Navigationsfenster ein schwebendes Panel oben links. |
| Kamera in VR | Wie am Desktop: Maßstab 1:1, die Kamera umkreist den Drehpunkt. Die Kopfbewegung kommt obendrauf. |
| Neuer Höhenpunkt | Doppelklick auf die Fahrbahn. Ein einfacher Klick wählt den Abschnitt als Drehpunkt. |

## Bedienung (Höhenstufe)

| Eingabe | Wirkung |
|---|---|
| Linksklick auf einen Punkt | wählt ihn (Drehpunkt) und zieht ihn |
| Linksklick auf die Fahrbahn | wählt den Abschnitt (Drehpunkt = Mitte des Abschnitts) |
| Doppelklick auf die Fahrbahn | neuer Punkt an dieser Stelle (Höhe auf der Kurve), sofort ziehbar |
| Rechtsklick auf einen Punkt | löscht ihn |
| Rechte Maustaste ziehen | umkreist den Drehpunkt |
| Mausrad | Abstand zum Drehpunkt |
| C / ↑ ↓ (Shift ×4) / B / Esc / Tab | wie bisher: Knick, Höhe, Zugbrücke, Undo, zurück zum Grundriss |
| Navigationsfenster | rechte Maustaste verschiebt, Rad zoomt, Linksklick wählt den Abschnitt |

Die Taste V entfällt, die 3D-Ansicht ist immer da.

## Architektur

### 1. `HeightRibbon` (neu, `scripts/editor/height_ribbon.gd`, class_name, ohne Autoloads → headless testbar)
Die Geometrie der Höhenfläche, gebaut aus einem `TrackPath`:
- `plan_at(x) -> [pos2d, tangent2d]`: Profil-x → Grundrisspunkt (über `path.px`, Loopings ausgenommen)
- `point_at(x, h) -> Vector3`: 3D-Position eines Profilpunkts (für Marker und Linie)
- `hit(ray_from, ray_dir, x_hint, window) -> [x, h]`: Schnitt des Mausstrahls mit der senkrechten Fläche über der Mittellinie. Gesucht wird nur im Fenster um `x_hint` (±80 m), damit der Punkt nicht auf eine kreuzende Strecke springt. Von mehreren Treffern gewinnt der mit x am nächsten an `x_hint`. Gibt es keinen Treffer (Strahl parallel zur Fläche), wird auf die Tangentialebene am Punkt projiziert.
- `x_of_sample(i)`: Fahrbahntreffer (Strahl gegen `RoadBody`) → Profil-x für Doppelklick und Abschnittswahl.

### 2. Durchsicht (`TrackNode`, `EnvironmentBuilder`, `MeshKit`)
- `MeshKit`: zweite Materialvariante mit `ALPHA` (blend_mix, depth_draw_never, ohne Schatten). Dafür `build_instance(alpha := 1.0)`.
- `TrackNode.build(path, see_through := false)`: Mit `see_through` landen Tunnelwände, Decke und Dachoberseite, Wände der Einschnitte (`_cut_wall`) und Portale in einem eigenen `MeshKit` mit Alpha 0,3. Fahrbahn, Randstreifen und Rampenwände bleiben deckend. Die Lampen entfallen im Editor.
- `EnvironmentBuilder.build(..., ground_alpha := 1.0)`: Boden mit 0,3 und ohne Bodenflecken; Kulisse und Himmel bleiben. Kollision unverändert.
- Ohne die Parameter ändert sich im Spiel nichts.

### 3. `HeightEditor3D` (neu, ersetzt `HeightProfile` und `EditorPreview`)
- **Welt** im Hauptbaum (nicht im SubViewport), damit VR einfach funktioniert: `TrackNode` mit Durchsicht, Umgebung und eine Overlay-Ebene.
- **Kamera** über das vorhandene XR-Rig: Jedes Frame wird `XrManager.set_base(orbit_pose)` gesetzt. Am Desktop wird das Freiumsehen mit der rechten Maustaste in `XrManager` für den Editor abgeschaltet (neues Flag `free_look`), weil die rechte Maustaste dort umkreist. Die Kamerafahrt zum neuen Drehpunkt (weich) kommt aus `EditorPreview`. Der Neigungsbereich reicht bis unter den Boden (Boden durchsichtig).
- **Overlay** (MeshKit/ImmediateMesh, unbeleuchtet, durch die Wände sichtbar mit reduzierter Deckung):
  - Höhenlinie: entlang der Mittellinie auf Spline-Höhe, 0,15 m über der Fahrbahn, gefärbt mit `HeightProfile.height_color`. Wände sind gelbe senkrechte Linien. Die Linie wird **jedes Frame** aus `model.points()` gerechnet und folgt dem gezogenen Punkt also sofort, nicht erst mit der Fahrbahn.
  - Punkte: Würfel, Ecken als Oktaeder, mit konstanter Bildschirmgröße. Farben wie bisher: weiß, gelb für den unteren Wandpunkt, hellblau für gewählt oder darüber.
  - Gewählter Abschnitt: rotes Band auf der Fahrbahn.
- **Picking:** Punkte im Bildraum (Abstand < 10 px zur projizierten Position), Fahrbahn per Raycast gegen `RoadBody`.
- **Ziehen:** `HeightRibbon.hit()` liefert (x, h). Der Klickversatz wird wie bisher gemerkt, damit der Punkt nicht springt. Dann `model.move_point(i, x, h, false, snap)` mit `snap = max(WALL_SNAP, Meter pro 10 px am Punkt)`, die 3D-Entsprechung der heutigen Pixelregel. Neu gebaut wird mit `PREVIEW_RATE = 4`. Beim Loslassen folgen der vollständige Neubau, `problems()` und die Infozeile. Kostet der Neubau in VR mehr als etwa 8 ms, wird er in den `WorkerThreadPool` verlagert und das Mesh nur ausgetauscht.
- **Problemstellen** (Kreuzung zu niedrig, zu steil): rote bzw. orange Ringe in 3D und im Navigationsfenster.

### 4. `PlanNav` (neu): Navigationsfenster
- Control mit dem nach Höhe gefärbten Grundriss. Der Code kommt aus `TrackEditor._draw_heights()` hierher.
- Eigener Zoom und eigenes Verschieben, eingezeichnet sind Kameraposition und Blickrichtung.
- Am Desktop ein Control oben links (etwa 30 % × 35 %). In VR rendert es in einen SubViewport auf einem Quad, das am Kopf hängt (wie `Panel3D`, oben links im Blickfeld).

### 5. VR
- **3D-Mauszeiger:** Die Maus ist gefangen, ihre Relativbewegung schiebt einen Zeiger auf einer Kugel um den Kopf (fester Abstand, z. B. 2 m). Der Strahl vom Kopf durch den Zeiger ersetzt `project_ray_*`. Trifft er das Navigationspanel, werden die Klicks als InputEvents in dessen SubViewport weitergereicht.
- Info- und Statuszeile sowie die Leiste oben (Speichern, Probefahrt, Grundriss usw.) liegen als Panel unter dem Navigationsfenster.
- Der **Grundriss-Editor** erscheint in VR auf einer großen virtuellen Leinwand (SubViewport auf einem Quad) und wird mit demselben Zeiger bedient. Erst damit ist der Editor im VR-Menü sinnvoll freizugeben (`menu.gd`: `"desktop": true` fällt weg).

### 6. `TrackEditor`
- In der Höhenstufe werden `HeightEditor3D` und `PlanNav` erzeugt, die 2D-Zeichnung des Plans entfällt. `_profile` und `_preview_box` fallen weg.
- `--editor-heights` (Debug, Screenshots) öffnet direkt die neue Ansicht.
- Die Kopfzeilen-Doku und `lang.gd` (Statustexte) werden angepasst.

## Phasen

1. **`HeightRibbon` + Tests:** x↔Grundriss, Strahlschnitt in Geraden, Kurven und an Kreuzungen (Fenster), Doppelklick-x.
2. **Durchsicht:** MeshKit-Alpha, `see_through`, Boden-Alpha. Screenshot eines Tunnels.
3. **`HeightEditor3D` am Desktop:** Kamera, Overlay, Picking, Ziehen mit 4-Hz-Neubau, Tasten. Danach `HeightProfile` und `EditorPreview` entfernen.
4. **`PlanNav`:** Navigationsfenster mit Kamerasymbol.
5. **VR:** 3D-Zeiger, Panels, Grundriss-Leinwand, Menüeintrag in VR.
6. **Feinschliff:** Leistung des Neubaus in VR, Texte, Doku.

Jede Phase endet lauffähig und mit einem eigenen `feat:`-Commit.

## Prüfung

- Headless-Tests (`tests/run_tests.gd`): Die bestehenden Höhentests bleiben unverändert grün, weil die Modell-Logik nicht angefasst wird. Neue Tests decken `HeightRibbon` und die Snap-Umrechnung ab.
- Screenshots über `--rendering-driver vulkan -- --no-xr --editor=<name> --editor-heights --screenshot=…`: Tunnel durchsichtig, Linie und Punkte auf der Fahrbahn, Navigationsfenster.
- VR (Pimax) testest du selbst: Zeiger, Ziehen, Umkreisen, Bildrate beim Neubau.

## Offene Punkte für später

- Den Profilstreifen als optionales, einklappbares Hilfsfenster behalten? (Bisher ist das nicht vorgesehen.)
