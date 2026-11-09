---
bereich: Uni
thema: Data Science
erstellt: 2026-11-09T14:30
tags: [uni, data-science]
---
# Lineare Regression

Die **Methode der kleinsten Quadrate** minimiert die Summe der *quadrierten* Residuen. Siehe auch [[Formelsammlung]] und `numpy.polyfit`.

## Annahmen

1. Linearität
2. Unabhängige Fehler
3. Homoskedastizität

- [ ] Kapitel 2 lesen 📅 2026-11-20 #uni
- [x] Folien herunterladen

> Alle Modelle sind falsch, aber manche sind nützlich.

| Größe | Symbol |
|---|---|
| Steigung | β₁ |
| Achsenabschnitt | β₀ |

```python
import numpy as np
b1, b0 = np.polyfit(x, y, 1)
```
