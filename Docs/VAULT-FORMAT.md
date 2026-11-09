# Vault-Format von Hub

Obsidian bleibt die einzige Quelle. Hub liest normale Markdown-Dateien; alles ist ohne Hub in Obsidian les- und bearbeitbar.

## Ordner

    <Vault>/
      <Bereich>/<Thema>/…   Bereiche: Uni, Arbeit, Freizeit (in den Einstellungen änderbar)
      _Hub/Tasks.md          optional, zentrale Aufgaben (Phase 4)
      _Hub/Roadmap/          ein Projekt pro Datei (Phase 6)

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
