# Vault-Format von Organizer

Obsidian bleibt die einzige Quelle. Organizer liest normale Markdown-Dateien; alles ist ohne Organizer in Obsidian les- und bearbeitbar.

## Ordner

    <Vault>/
      <Bereich>/<Thema>/…   Bereiche: Uni, Arbeit, Freizeit (in den Einstellungen änderbar)
      _Organizer/Tasks.md          optional, zentrale Aufgaben (Phase 4)
      _Organizer/Roadmap/          ein Projekt pro Datei (Phase 6)

**Standard: Struktur aus Obsidian übernehmen.** Jeder Ordner auf oberster Ebene ist ein Bereich (außer `_Organizer`),
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
  heißt die Datei `<Titel> 2.md`. Organizer überschreibt beim Anlegen nie eine vorhandene Datei.
- **Bearbeiten:** Organizer ändert nur den Text unter dem Frontmatter. Der Frontmatter-Block und die Zeilenenden
  bleiben Byte für Byte erhalten. Gespeichert wird automatisch kurz nach dem Tippen, beim Notizwechsel
  und wenn Organizer in den Hintergrund geht.
- **Konflikte:** Vor jedem Speichern prüft Organizer, ob die Datei noch so aussieht wie beim Laden.
  Hat Obsidian sie geändert und gibt es in Organizer keine ungespeicherten Änderungen, übernimmt Organizer den neuen Stand.
  Andernfalls fragt Organizer, welche Version gelten soll.
- **Rückgängig (⌘Z)** nach dem Anlegen einer Notiz oder eines Themas legt sie in den Papierkorb. Sie ist dort wiederherstellbar.
- **Neuer Ordner (⌥⌘N, Rechtsklick „Neuer Unterordner“):** legt nur einen Ordner an. Ein Unterordner eines Bereichs ist ein Thema.

## Kalender (ab Phase 3)

Termine kommen aus dem Apple Kalender (EventKit) und bleiben dort. Organizer legt Termine nur an, wenn du es willst
(⌘N in der Kalenderansicht). Eine **Notiz zum Termin** bekommt zusätzlich im Frontmatter:

    termin: Vorlesung Data Science
    termin-datum: 2026-11-10T10:00

## Aufgaben (ab Phase 4)

Jede Zeile `- [ ] …` außerhalb von Codeblöcken ist eine Aufgabe – im Format des Obsidian-Plugins „Tasks“:

    - [ ] Hausarbeit Kapitel 2 schreiben ⏫ 📅 2026-11-20 #uni

| Teil | Bedeutung |
|---|---|
| `[ ]` `[x]` `[/]` `[-]` | offen, erledigt, in Arbeit, abgebrochen |
| 🔺 ⏫ 🔼 🔽 ⏬ | Priorität (höchste … niedrigste) |
| 📅 / ⏳ / 🛫 / ➕ / ✅ | fällig / geplant / Start / erstellt / erledigt am |
| 🔁 | Wiederholung (nur Anzeige) |

- **Bereich und Thema** kommen vom Speicherort der Notiz. Aufgaben in `_Organizer/Tasks.md` werden über Tags
  zugeordnet (`#uni` → Uni, `#data-science` → Thema „Data Science“).
- **Ändern** (abhaken, Datum, Priorität, Titel, löschen) betrifft immer genau eine Zeile. Organizer prüft vorher,
  dass die Zeile noch so in der Datei steht; sonst wird nichts geschrieben. Jede Änderung ist mit ⌘Z rückgängig zu machen.
- **Neue Aufgaben** landen je nach Einstellung in `_Organizer/Tasks.md` oder in `Aufgaben.md` im Bereichs- bzw. Themenordner.
- Im Kalender erscheinen fällige Aufgaben nur in Organizer, nicht im Apple Kalender.
