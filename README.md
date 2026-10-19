# VGAGlitch

Simuliert ein kaputtes VGA-Kabel bzw. einen zickenden Beamer: Bluescreen, „Kein Signal“, zerreißendes und rollendes Bild, fehlende Farbkanäle, Geisterbilder, weiße Störstreifen und Funkeln. Welcher Effekt kommt und wann, ist jedes Mal zufällig.

## Download

Fertige Apps (Intel und Apple Silicon, ab macOS 13) liegen in `dist/`: `VGAGlitch.zip` und `VGAGlitch2.zip`. Entpacken und nach `/Programme` ziehen.

Die Apps sind nicht von Apple notarisiert, deshalb blockiert macOS den ersten Start. Entweder Rechtsklick auf die App → **Öffnen** → **Öffnen**, oder im Terminal:

```bash
xattr -dr com.apple.quarantine /Applications/VGAGlitch2.app
```

## Bauen

```bash
./build.sh
```

Ergebnis: `build/VGAGlitch.app` und `build/VGAGlitch2.app`. Am besten nach `/Programme` ziehen und von dort starten.

## VGAGlitch2

Wie VGAGlitch, plus:

- **Bildschirme** (Menü): „Nur Beamer“ oder „Laptop + Beamer“. Mit „Laptop + Beamer“ glitcht auch der eingebaute Bildschirm, auch ganz ohne Beamer.
- **Bargeld-Umfrage**: Solange die Störungen laufen, poppt oben rechts ab und zu Hansjörg Stützle mit „BARGELD ABSCHAFFEN?“ auf. Die Buttons sind klickbar (die Präsentation behält dabei den Fokus): „NEIN …“ bedankt sich und verschwindet, „JA …“ ist die falsche Antwort. Ohne Klick verschwindet sie nach 8–14 s von selbst. Wie oft sie kommt, hängt an der Intensität.
- **⌃⌥⌘B**: Umfrage sofort zeigen. Im Menü lässt sich das zufällige Einblenden abschalten.

Beide Apps nutzen ⌃⌥⌘G, also immer nur eine davon laufen lassen. Die Bildschirmaufnahme-Berechtigung braucht VGAGlitch2 separat (`tccutil reset ScreenCapture local.vgaglitch2`).

## Bedienung

Die Störungen laufen **nur auf Beamern bzw. externen Bildschirmen**, der eingebaute Laptop-Bildschirm bleibt sauber. Bei Bildschirmspiegelung ist das Bild auf Laptop und Beamer dasselbe, dann sieht man die Störung auf beiden. Ist kein Beamer angeschlossen, passiert nichts. Wird er während des Betriebs angesteckt, geht es dort automatisch los.

| Aktion | Wirkung |
|---|---|
| **⌃⌥⌘G** (Ctrl+Option+Cmd+G) | Störungen starten |
| **⌃⌥⌘G 3 Sekunden halten** | Störungen stoppen |
| ⌃⌥⌘G kurz drücken, während aktiv | sofort ein extra heftiger Glitch (im Menü umstellbar auf „stoppt sofort“) |

Das Menüleisten-Symbol (Monitor) bietet außerdem:

- **Intensität**: Leicht, Mittel, Heftig (wie oft und wie stark)
- **„Kein Signal“-Meldung**: Deutsch, English oder aus
- **Symbol ausblenden**: Die App läuft unsichtbar weiter. Zum Zurückholen öffnest du die App einfach noch einmal.

## Berechtigung „Bildschirmaufnahme“

Damit das echte Bild verzerrt werden kann (Zittern, Rollen, Farbverlust), braucht die App einmalig die Berechtigung unter **Systemeinstellungen → Datenschutz & Sicherheit → Bildschirm- & Systemaudioaufnahme**. Nach dem Erlauben muss die App neu gestartet werden.

Ohne Berechtigung laufen nur die Overlay-Effekte (Blau, Schwarz, Rauschen, weiße Streifen).

Wichtig: Der Build wird ad-hoc signiert. **Nach jedem Neubauen** erkennt macOS die App nicht wieder. Dann so zurücksetzen und neu erlauben:

```bash
tccutil reset ScreenCapture local.vgaglitch
```

(Oder mit fester Signatur bauen: `SIGN_IDENTITY="Apple Development: …" ./build.sh`)

## Gut zu wissen

- Solange die Störungen aktiv sind, zeigt macOS in der Menüleiste das lila Symbol für Bildschirmaufnahme. In einer Vollbild-Präsentation ist die Menüleiste ausgeblendet.
- Der Mauszeiger bleibt immer sichtbar (macOS zeichnet ihn über alles).
- Die Effekte laufen auch über Vollbild-Apps wie Keynote und PowerPoint.

## Entwickler-Optionen

```bash
# Vorschaubilder aller Effekte und Episoden rendern (ohne Bildschirmaufnahme)
build/VGAGlitch.app/Contents/MacOS/VGAGlitch --render-test /tmp/vga-preview

# direkt starten / 10 s laufen lassen und beenden, mit Statistik
build/VGAGlitch.app/Contents/MacOS/VGAGlitch --start
VGAGLITCH_DEBUG=1 build/VGAGlitch.app/Contents/MacOS/VGAGlitch --smoke 10
```

Aufbau: `Sources/Poll.swift` (Bargeld-Umfrage, nur in VGAGlitch2 via `-D VGAGLITCH2`), `Sources/Effects.swift` (Effekte und Episoden), `Scheduler.swift` (Zufall und Timing), `Shader.swift` (Metal-Shader), `ScreenCapturer.swift` (ScreenCaptureKit), `Overlay.swift` (Fenster je Bildschirm), `AppDelegate.swift` (Tastenkürzel und Menü).
