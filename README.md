# Engels Küche – native iPad-App

Zielgerät: **iPad Air (1. Generation) mit iOS 12.5.7**, Chimera-Jailbreak, AppSync und Filza.

Die App soll das vorhandene Küchentool auf dem Lenovo im Vollbild anzeigen und native Einstellungen für echte Bildschirmhelligkeit, Tag/Nacht-Steuerung und Frontkamera bereitstellen.

## iPad-App über GitHub Actions bauen

**Kein Mac, kein iTunes und kein kostenpflichtiges Apple-Developer-Konto nötig.**

1. [Actions öffnen](https://github.com/Hummel55/Engels-Kueche-iPad/actions/workflows/ios12-ipa.yml)
2. Workflow **Engels Küche iPad IPA (iOS 12)** auswählen.
3. Auf **Run workflow** klicken, Branch `main` beibehalten und bestätigen.
4. Das Ergebnis im neuen Durchlauf prüfen.
5. Nach einem erfolgreichen Build unter **Artifacts** die Datei **EngelsKueche-iPad-iOS12-IPA** herunterladen. In der ZIP befindet sich die `.ipa`.

Der erste Workflow-Lauf entpackt zunächst den bereits hochgeladenen Projektstand (`bootstrap/source.00.b64` bis `source.03.b64`) und versucht, die **normalen Quellcodedateien dauerhaft ins Repository zu übernehmen**. Danach kompiliert er die App mit Xcode. Das Archiv wird vor dem Entpacken mit SHA-256 geprüft.

### Status

- GitHub-Projekt und Workflow: **vorbereitet**
- Quellarchiv: **hochgeladen und mit Prüfsummen kontrolliert**
- iOS-Kompilierung: **noch nicht ausgeführt**
- Funktion auf dem tatsächlichen iPad: **noch nicht getestet**

Fehler beim ersten Build können zusätzliche Codekorrekturen erforderlich machen.

### Sicherheit und Daten

Das Repository ist **öffentlich**. Hier stehen App-Quellcode und Beispieladressen, aber keine Rezeptdatenbank, keine Kalenderpasswörter oder gespeicherten Rezepte.

Die Küche bleibt weiterhin auf dem Lenovo. Nach Installation der IPA auf dem iPad die tatsächliche Lenovo-Küchenadresse in den nativen Einstellungen eintragen (z. B. `http://192.168.178.xxx:8091/`). Die Beispiel-IP ist nicht die ermittelte Adresse deines Geräts.

Ein vollständiger iPad-Neustart kann eine erneute Aktivierung des Chimera-Jailbreaks erfordern. Die IPA wird für ein jailbroken Gerät mit AppSync gebaut, nicht für den regulären App Store.
