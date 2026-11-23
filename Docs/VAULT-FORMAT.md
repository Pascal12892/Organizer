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
| 🔁 | Wiederholung, z. B. `🔁 every week` (siehe unten) |

- **Bereich und Thema** kommen vom Speicherort der Notiz. Aufgaben in `_Organizer/Tasks.md` werden über Tags
  zugeordnet (`#uni` → Uni, `#data-science` → Thema „Data Science“).
- **Ändern** (abhaken, Datum, Priorität, Titel, löschen) betrifft immer genau eine Zeile. Organizer prüft vorher,
  dass die Zeile noch so in der Datei steht; sonst wird nichts geschrieben. Jede Änderung ist mit ⌘Z rückgängig zu machen.
- **Neue Aufgaben** landen je nach Einstellung in `_Organizer/Tasks.md` oder in `Aufgaben.md` im Bereichs- bzw. Themenordner.
- Im Kalender erscheinen fällige Aufgaben nur in Organizer, nicht im Apple Kalender.

### Wiederholungen

Organizer versteht die Regeln des Tasks-Plugins (englisch, damit Obsidian sie weiter erkennt):
`every day`, `every 3 days`, `every weekday`, `every Monday`, `every week on Monday, Thursday`, `every 2 weeks`,
`every month`, `every month on the 15th`, `every month on the last`, `every year`, jeweils optional mit `when done`.
Im Kontextmenü einer Aufgabe gibt es dafür „Wiederholen“.

Beim Abhaken (in Organizer, im Board, in Apple Erinnerungen oder über Claude) passiert dasselbe wie im Tasks-Plugin:

    - [ ] Wäsche 🔁 every week 📅 2026-11-27 #haushalt
    - [x] Wäsche 🔁 every week 📅 2026-11-20 #haushalt ✅ 2026-11-21

- Die neue Zeile kommt **direkt über** die erledigte. Fällig, geplant und Start verschieben sich um denselben Abstand.
- `when done` rechnet vom Tag des Abhakens statt vom Fälligkeitsdatum.
- Erledigt-Datum und Block-ID (`^id`) werden nicht übernommen, ein Erstellt-Datum (➕) wird auf heute gesetzt.
- Hat die Aufgabe kein Datum, bekommt die Wiederholung eine Fälligkeit ab heute.
- Unbekannte Regeln bleiben stehen; die Aufgabe wird dann nur abgehakt.
- ⌘Z nimmt Abhaken und neue Zeile in einem Schritt zurück.

## Mac-Ordner pro Thema (ab Phase 5)

Verknüpfte Ordner stehen in der Übersichtsnotiz des Themas, `<Bereich>/<Thema>/_index.md`:

    ---
    bereich: Uni
    thema: Statistik
    ordner:
      - /Users/pascal/Desktop/Statistik Übungen
    ---

- Organizer ändert dabei nur die Zeilen der Eigenschaft `ordner`; fehlt `_index.md`, wird sie angelegt.
- Die Zugriffsrechte (Security-Scoped Bookmarks) speichert Organizer nur in seinen Einstellungen. Steht ein Pfad im
  Frontmatter, für den Organizer noch keine Erlaubnis hat (z. B. nach einer Neuinstallation), zeigt er „Zugriff erlauben …“.
- Verknüpfen und Entfernen lässt sich mit ⌘Z rückgängig machen. Die Ordner auf dem Mac selbst werden nie verändert.

## Roadmap (ab Phase 6)

Ein Projekt pro Datei in `_Organizer/Roadmap/`. Projektdaten im Frontmatter, Meilensteine als `##`-Überschriften
mit Inline-Feldern (Dataview-kompatibel), Aufgaben darunter:

    ---
    bereich: Uni
    start: 2026-10-15
    ende: 2027-03-31
    status: in Arbeit
    farbe: blue
    ---
    # Bachelorarbeit

    ## Literaturrecherche
    start:: 2026-10-15
    ende:: 2026-11-15
    status:: in Arbeit

    - [x] Quellen sammeln
    - [ ] Exposé schreiben 📅 2026-11-14

- **Status:** geplant, in Arbeit, erledigt, pausiert (englische Begriffe werden auch erkannt).
- **Fortschritt** = erledigte Aufgaben unter der Überschrift (abgebrochene zählen nicht); ohne Aufgaben zählt der Status.
- **Ändern** in Organizer (verschieben, Datum, Status, neue Aufgabe, neuer Meilenstein) betrifft nur die jeweiligen Zeilen
  und lässt sich mit ⌘Z rückgängig machen.

## Abgleich mit Apple Erinnerungen (optional)

Einschalten unter Einstellungen › Aufgaben. Markdown bleibt die Quelle:

- Offene Aufgaben **mit Datum** erscheinen in Erinnerungen-Listen „Organizer – <Bereich>“ (bzw. „Organizer“ ohne Bereich).
  Die Erinnerung verlinkt auf die Notiz in Obsidian.
- **Abhaken, Titel oder Datum ändern** in Erinnerungen ändert genau die eine Markdown-Zeile (wie beim Abhaken in Organizer).
- **Neue Erinnerungen** in diesen Listen werden zu Aufgaben in `_Organizer/Tasks.md` (mit Bereichs-Tag).
- **Konflikt** (beide Seiten seit dem letzten Abgleich geändert): Die Markdown-Zeile gewinnt.
- **Löschen** einer Erinnerung lässt die Aufgabe unangetastet; sie bekommt erst wieder eine Erinnerung, wenn sich die Zeile ändert.
  Wird die Aufgabe im Vault gelöscht, entfernt Organizer die gespiegelte Erinnerung.
- Welche Erinnerung zu welcher Zeile gehört, speichert Organizer in seinem eigenen Ordner – die Notizen bleiben frei von IDs.
- Uhrzeiten an Erinnerungen werden nicht übernommen (das Tasks-Format kennt nur Tage).
