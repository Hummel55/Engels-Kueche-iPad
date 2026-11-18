# Engels Küche – iPad Air (iOS 12.5.7)

Native iPad-Hülle für den bereits auf dem Lenovo betriebenen Küchenserver. Die App zeigt die vorhandene Küchenoberfläche an und soll die echte Bildschirmhelligkeit, Tag-/Nachtzeiten sowie die Frontkamera für Rezeptscans steuern.

**Status:** Quellprojekt vorbereitet; der erste echte iOS-Build und Gerätetest stehen aus. Bitte noch nicht als fertig getestete App betrachten.

## App bauen (kostenlos über GitHub Actions)
1. Die Dateien aus dem entpackten Projekt `Engels_Kueche_Native_iPad_V1` **in das Stammverzeichnis dieses Repositorys** hochladen (Ordner `EngelsKueche`, `EngelsKueche.xcodeproj` und bei Bedarf `Lenovo-Integration`). **Nicht** den übergeordneten Ordner als zusätzliche Ebene hochladen.
2. Unter **Actions** den Workflow **Engels Küche iPad IPA (iOS 12)** öffnen.
3. Über **Run workflow** den Build starten.
4. Wenn der Build erfolgreich ist, unter **Artifacts** die ZIP herunterladen. Darin befindet sich die `.ipa`.

Die App ist für ein jailbroken iPad Air 1 mit AppSync gedacht, nicht für eine reguläre App-Store-Installation. Für die erste Installation muss der Jailbreak aktiv sein. Keine Rezepte oder Zugangsdaten in dieses öffentliche Repository hochladen.

## Noch offen
- Kompilierung auf dem GitHub-macOS-Runner und eventuelle Compilerkorrekturen
- Installation und Funktionstest auf iOS 12.5.7
- Verbindung mit der tatsächlichen Lenovo-Adresse, Kamera, OCR und Helligkeitssteuerung
