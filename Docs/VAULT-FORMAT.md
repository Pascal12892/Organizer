# Vault-Format von Hub

Obsidian bleibt die einzige Quelle. Hub liest normale Markdown-Dateien; alles ist ohne Hub in Obsidian les- und bearbeitbar.

## Ordner

    <Vault>/
      <Bereich>/<Thema>/…   Bereiche: Uni, Arbeit, Freizeit (in den Einstellungen änderbar)
      _Hub/Tasks.md          optional, zentrale Aufgaben (Phase 4)
      _Hub/Roadmap/          ein Projekt pro Datei (Phase 6)

**Standard: Struktur aus Obsidian übernehmen.** Jeder Ordner auf oberster Ebene ist ein Bereich (außer `_Hub`),
seine Unterordner sind Themen. Die Seitenleiste zeigt den ganzen Ordnerbaum, beliebig tief.
In den Einstellungen lässt sich stattdessen eine feste Liste von Bereichen pflegen.

Ordner und Dateien mit `.` am Anfang (`.obsidian`, `.trash`) werden ignoriert.

## Bereich und Thema einer Notiz

1. **Speicherort gewinnt:** `Uni/Data Science/x.md` → Bereich `Uni`, Thema `Data Science`.
   Tiefere Unterordner gehören zum Thema der zweiten Ebene.
2. Nur für Notizen außerhalb der Bereichsordner gelten `bereich:` und `thema:` aus dem Frontmatter.

## Frontmatter

    ---
    bereich: Uni
    thema: Data Science
    erstellt: 2026-11-09T14:30
    tags: [uni, data-science]
    ---

Unterstützt: `key: wert`, `key: [a, b]`, Blocklisten (`- a`), Anführungszeichen.
Verschachtelte Strukturen werden übersprungen. Nicht lesbare Zeilen erscheinen als Hinweis in der App.

## Tags

Aus `tags:` im Frontmatter und `#tag` im Text (nicht in Code, nicht reine Zahlen).

## Links

`[[Notiz]]`, `[[Ordner/Notiz|Alias]]` und `[[Notiz#Abschnitt]]` sind in der Vorschau anklickbar.
Aufgelöst wird wie in Obsidian: zuerst über den Pfad, dann über den Dateinamen.

## Schreiben (ab Phase 2)

- **Neue Notiz:** `<Bereich>/<Thema>/<Titel>.md` mit dem Frontmatter oben. Gibt es den Namen schon,
  heißt die Datei `<Titel> 2.md`. Hub überschreibt beim Anlegen nie eine vorhandene Datei.
- **Bearbeiten:** Hub ändert nur den Text unter dem Frontmatter. Der Frontmatter-Block und die Zeilenenden
  bleiben Byte für Byte erhalten. Gespeichert wird automatisch kurz nach dem Tippen, beim Notizwechsel
  und wenn Hub in den Hintergrund geht.
- **Konflikte:** Vor jedem Speichern prüft Hub, ob die Datei noch so aussieht wie beim Laden.
  Hat Obsidian sie geändert und gibt es in Hub keine ungespeicherten Änderungen, übernimmt Hub den neuen Stand.
  Andernfalls fragt Hub, welche Version gelten soll.
- **Rückgängig (⌘Z)** nach dem Anlegen einer Notiz oder eines Themas legt sie in den Papierkorb. Sie ist dort wiederherstellbar.
- **Neuer Ordner (⌥⌘N, Rechtsklick „Neuer Unterordner“):** legt nur einen Ordner an. Ein Unterordner eines Bereichs ist ein Thema.
