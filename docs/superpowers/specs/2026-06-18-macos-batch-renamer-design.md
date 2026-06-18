# Specyfikacja: macOS Batch Renamer

**Data:** 2026-06-18
**Status:** Projekt zatwierdzony (brainstorming) — gotowy do planu implementacji
**Inspiracja:** plugin „Renamer" z menedżera plików Salamander (`salamander-main/src/plugins/renamer/`)

---

## 1. Cel i kontekst

Natywne narzędzie macOS do wsadowej zmiany nazw plików, działające na podobnej zasadzie co plugin Renamer w Salamandrze: użytkownik zaznacza pliki, z menu kontekstowego (prawy przycisk) wybiera komendę, otwiera się czytelne okno pozwalające zbudować regułę zmiany nazw przy użyciu **zmiennych** i pokazujące **na żywo nowe nazwy** przed zatwierdzeniem.

### Dwa wejścia do aplikacji
1. **Finder Sync Extension** — pozycja „Zmień nazwy…" w menu kontekstowym Findera na zaznaczonych plikach.
2. **Samodzielna aplikacja** — okno z **drag‑and‑drop** zaznaczonych plików.

---

## 2. Cele i nie‑cele

### Cele (v1 — „mocne MVP")
- Szablon nowej nazwy ze zmiennymi `{token}`.
- Szukaj‑i‑zamień: zwykły tekst **oraz** wyrażenia regularne (z grupami `$1`).
- Konwersja wielkości liter (osobno nazwa i rozszerzenie) + usuwanie znaków diakrytycznych.
- Podgląd na żywo z kolumnami Stara → Nowa nazwa.
- Wykrywanie kolizji i walidacja nazw (twarde błędy vs ostrzeżenia).
- Bezpieczne wykonanie (cykle, zmiana samej wielkości liter) i **cofnięcie ostatniej operacji** w sesji.
- Pamiętanie ostatnich ustawień między uruchomieniami.

### Nie‑cele (v1 — świadomie odłożone)
- Tryb ręcznej edycji linia‑po‑linii.
- Presety / zapisywane wzorce / pełna historia wielu wpisów.
- Rekurencja podkatalogów.
- Metadane EXIF/zdjęciowe.
- Trwała (wielopoziomowa, międzysesyjna) historia undo.
- Integracja z systemowym Cofnij (Cmd+Z) w Finderze.

---

## 3. Decyzje produktowe (z brainstormingu)

| Decyzja | Wybór |
|---|---|
| Integracja z menu kontekstowym | Finder Sync Extension + samodzielna app z drag‑and‑drop |
| Dystrybucja | Developer ID (DMG) + notaryzacja Apple |
| Sandbox | App **bez** sandboxu; rozszerzenie Findera **sandboxowane** (wymóg systemu) |
| Paradygmat UI | Wariant A: jeden szablon „Nowa nazwa" + panele szukaj‑zamień i wielkość liter |
| Składnia zmiennych | `{token}` / `{token:argument}` |
| Undo | „Cofnij ostatnią" w obrębie sesji |
| Język/stack | Swift + SwiftUI (app), AppKit (rozszerzenie), Swift Package (rdzeń) |

---

## 4. Architektura

Jeden projekt Xcode, trzy cele + wspólny pakiet.

```
RenamerCore (Swift Package, bez UI, w 100% testowalny)
        ▲                         ▲
        │                         │
Renamer.app (SwiftUI,     RenamerFinderExtension.appex
 bez sandboxu)             (Finder Sync, sandboxowane)
```

### 4.1 `RenamerCore` — rdzeń logiki (bez UI)
Czysty, deterministyczny, w pełni pokryty testami. Komponenty:

- **`RenameTemplate`** — parser tekstu szablonu na sekwencję segmentów (tekst literalny + tokeny). Token = nazwa + opcjonalne argumenty.
- **`TemplateEvaluator`** — dla danego pliku i indeksu liczy ciąg wynikowy z segmentów.
- **`FindReplace`** — zwykły tekst (dosłownie) lub regex (`NSRegularExpression`, ICU); w trybie regex zamiana wspiera grupy `$1…$n`.
- **`CaseTransformer`** — `none / lower / upper / title`; opcjonalne `stripDiacritics` (przez `folding`/Unicode).
- **`RenamePlan`** — dla listy plików + konfiguracji liczy `[RenameRow]` (stara ścieżka, nowa nazwa, status, komunikat).
- **`CollisionDetector`** — wykrywa duplikaty docelowe, niedozwolone znaki, puste nazwy, nadpisania istniejących plików; ustala status każdego wiersza.
- **`RenameExecutor`** — wykonuje operacje na `FileManager`, porządkuje zależności, obsługuje cykle i zmiany samej wielkości liter przez nazwę tymczasową; produkuje `UndoBatch`.
- **`UndoBatch`** — rekordy `(from, to)` w kolejności umożliwiającej odwrócenie.

### 4.2 `Renamer.app` — interfejs (SwiftUI, bez sandboxu)
- Okno główne wg makiety (sekcja 6).
- Drop‑zone na pliki (drag‑and‑drop) + „Otwórz…".
- Reaktywne, **debounce'owane** przeliczanie podglądu przy każdej zmianie wejść.
- Przyciski „Zmień nazwy" i „Cofnij ostatnią".
- Odbiór listy plików od rozszerzenia (schemat URL + plik handoff).
- Brak sandboxu → operacje na ścieżkach wprost, bez security‑scoped bookmarks.

### 4.3 `RenamerFinderExtension.appex` — Finder Sync (sandboxowane)
- `FIFinderSync` z pozycją menu „Zmień nazwy…" (`menu(for: .contextualMenuForItems)`).
- Monitoruje szeroko (katalog domowy + podłączone woluminy), aby menu pojawiało się wszędzie tam, gdzie użytkownik pracuje.
- Po kliknięciu: zbiera `selectedItemURLs()`, zapisuje listę ścieżek do pliku handoff i otwiera aplikację przez `renamer://open?handoff=<id>`.

### 4.4 Przepływ handoff (rozszerzenie → app)
1. Rozszerzenie tworzy plik handoff (np. `~/Library/Application Support/Renamer/handoff/<uuid>.json`) z listą ścieżek.
2. Otwiera `renamer://open?handoff=<uuid>` (`NSWorkspace.open`).
3. App (bez sandboxu) odczytuje plik, ładuje pliki do listy, usuwa plik handoff.

> Uwaga: katalog handoff musi być dostępny dla sandboxowanego rozszerzenia — użyjemy współdzielonego kontenera **App Group** dla zapisu, a app czyta z niego. (Do potwierdzenia w implementacji: App Group + Developer ID.)

---

## 5. Silnik zmiany nazw — szczegóły

### 5.1 Kolejność przetwarzania (potok)
Dla każdego pliku, w kolejności:
1. **Baza** = ewaluacja szablonu „Nowa nazwa". Jeśli pole puste → baza = oryginalna nazwa pliku (z rozszerzeniem). Pozwala to używać samego szukaj‑zamień bez pisania szablonu.
2. **Szukaj‑zamień** na wyniku (tekst lub regex).
3. **Konwersja wielkości liter** — osobno część nazwy i część rozszerzenia (rozdzielane po ostatniej kropce); opcjonalne usunięcie diakrytyków.

### 5.2 Gramatyka tokenów
Składnia: `{nazwa}` lub `{nazwa:argument}`. Literalny `{` zapisujemy jako `{{`, literalny `}` jako `}}`.

| Token | Znaczenie | Argument |
|---|---|---|
| `{name}` | oryginalna nazwa **bez** rozszerzenia | `:upper` `:lower` `:title`, fragment `:a-b` |
| `{ext}` | rozszerzenie bez kropki | jak wyżej |
| `{counter}` / `{counter:001}` | licznik; liczba zer = szerokość (padding zerami) | pełna forma: `:start=,step=,digits=,base=` |
| `{date}` / `{date:yyyy-MM-dd}` | data modyfikacji pliku, format ICU `DateFormatter` | wzorzec ICU |
| `{time}` / `{time:HH-mm-ss}` | czas modyfikacji pliku | wzorzec ICU |
| `{parent}` | nazwa folderu nadrzędnego | `:upper/lower/title`, fragment |
| `{name:1-5}` | fragment znaków 1–5 (1‑indeksowane; ujemne = od końca) | — |

**Fragment (substring):** forma `a-b`, gdzie `a`/`b` są 1‑indeksowane i mogą być ujemne (liczone od końca). `{name:2-4}` → znaki 2..4. `{name:3-}` → od znaku 3 do końca. `{name:-3--1}` lub skrót `{name:-3}` → ostatnie 3 znaki.

**Łączenie argumentów:** w v1 token przyjmuje **jeden** argument — albo wielkość liter (`:upper`), albo fragment (`:2-4`), nie oba naraz. Łączenie (`{name:upper:1-5}`) to świadome rozszerzenie poza v1.

### 5.3 Licznik — szczegóły
- `start` (domyślnie 1), `step` (domyślnie 1), `digits` (szerokość, padding zerami; domyślnie z liczby zer w skrócie `001`), `base` (`d` dziesiętny / `x` hex małe / `X` hex wielkie; domyślnie `d`).
- Numeruje w **kolejności wyświetlania** listy (sortowanie wpływa na numerację).
- Konfigurator (mały popover) ustawia start/krok/cyfry i wstawia gotowy token.

### 5.4 Daty
- Format ICU przez `DateFormatter`. Konfigurator daty podpowiada kilka gotowych wzorców (`yyyy-MM-dd`, `yyyyMMdd`, `dd.MM.yyyy`) i pozwala wpisać własny.
- Źródło: data **modyfikacji** pliku (v1). (Data utworzenia = ewentualne rozszerzenie.)

### 5.5 Regex
- Silnik: `NSRegularExpression` (ICU).
- Zamiana: szablon z `$1…$n` (grupy), `$0` = całe dopasowanie, `$$` = literalny `$`.
- Opcje: rozróżnianie wielkości liter (checkbox). Globalna zamiana (wszystkie wystąpienia) domyślnie.
- Błędny wzorzec regex → komunikat w pasku statusu, podgląd pokazuje stan błędu (bez wywalania UI).

### 5.6 Konwersja wielkości liter
- Tryby: `bez zmian`, `małe litery`, `WIELKIE LITERY`, `Każde Słowo` (title — wielka po granicy nie‑alfanumerycznej).
- Osobno dla nazwy i dla rozszerzenia.
- Opcja „usuń znaki diakrytyczne" (np. `ł→l`, `é→e`) przez Unicode folding.

---

## 6. Specyfikacja UI (wariant A)

Okno (resizowalne), od góry:

1. **Pasek tytułu** — „Zmień nazwy" + licznik „N plików · M problemów".
2. **Sekcja kontroli** (panel):
   - **Nowa nazwa** — pole edycyjne renderujące tokeny jako kolorowe „pigułki" (edytowalne jak tekst), z prawej przycisk **„+ Wstaw ▾"**.
   - Menu „+ Wstaw" — lista zmiennych; pozycje z „…" (Licznik, Data, Czas, Fragment) otwierają mały konfigurator i wstawiają gotowy token.
   - **Szukaj** / **Zamień** — dwa pola; checkboxy „Wyrażenie regularne", „Rozróżniaj wielkość".
   - **Wielkość** — dwa dropdowny (Nazwa / Rozszerzenie) + checkbox „usuń znaki diakrytyczne".
3. **Tabela podglądu** — kolumny **Stara nazwa** → **Nowa nazwa**; sortowanie po kliknięciu nagłówka (domyślnie po starej nazwie); ikony statusu: ⚠ ostrzeżenie, ⛔ błąd; wiersze błędne podświetlone.
4. **Stopka** — pasek statusu („23 gotowe · 1 kolizja"), przyciski **„Cofnij ostatnią"** i **„Zmień nazwy"** (primary; nieaktywny gdy są twarde błędy).

Stan pusty (brak plików): widoczny duży drop‑zone „Przeciągnij pliki tutaj" + przycisk „Otwórz…".

---

## 7. Podgląd, kolizje i walidacja

Status każdego wiersza wyliczany przez `CollisionDetector`:

| Status | Warunek | Efekt |
|---|---|---|
| ⛔ błąd | duplikat docelowej nazwy (porównanie zależne od wielkości liter wg APFS) | blokuje „Zmień nazwy" |
| ⛔ błąd | niedozwolony znak (`/`, `:`) lub pusta nazwa | blokuje „Zmień nazwy" |
| ⚠ ostrzeżenie | docelowa nazwa już istnieje na dysku (nadpisanie) | nie blokuje; potwierdzenie przy Apply |
| ✓ ok | brak problemów | — |

- Przeliczanie **debounce'owane** (np. 150 ms) po każdej zmianie wejść.
- Wykrywanie duplikatów: grupowanie po pełnej ścieżce docelowej.

---

## 8. Wykonanie i undo

### 8.1 Wykonanie (`RenameExecutor`)
- Buduje listę operacji (from → to).
- **Cykle** (A→B, B→A) i **zmiana samej wielkości liter** (`foto.jpg`→`FOTO.JPG` na case‑insensitive APFS): realizowane przez nazwę tymczasową (krok pośredni).
- Błąd pojedynczej operacji **nie przerywa** całości: plik oznaczany jako nieprzemianowany, na końcu raport „udało się N, błędy: M (lista)".
- Nadpisania (jeśli były ⚠) — zbiorcze potwierdzenie przed startem.

### 8.2 Undo (w sesji)
- Po udanej operacji `UndoBatch` trzymany w pamięci aplikacji.
- „Cofnij ostatnią" odwraca operacje w odwrotnej kolejności zależności.
- Po zamknięciu aplikacji undo znika (świadome ograniczenie v1).

---

## 9. Trwałość danych
- `UserDefaults`: ostatni szablon, ostatnie wartości szukaj‑zamień, ustawienia wielkości liter, ustawienia licznika — przywracane przy starcie.
- Brak bazy/presetów w v1.

---

## 10. Dystrybucja i uprawnienia
- **Developer ID** + notaryzacja, paczka **DMG**.
- App: bez sandboxu (pełny dostęp do plików).
- Rozszerzenie: sandboxowane (wymóg App Extension); App Group do współdzielenia pliku handoff.
- Onboarding: aplikacja informuje, że trzeba raz włączyć rozszerzenie w **Ustawienia systemowe → Ogólne → Elementy logowania i rozszerzenia → Rozszerzenia Findera**.

---

## 11. Strategia testów
Cały rdzeń `RenamerCore` pokryty XCTest:
- parser szablonu (tokeny, escapowanie `{{`/`}}`, błędne tokeny),
- ewaluacja: `{name}`, `{ext}`, `{parent}`, fragmenty, wielkość liter,
- licznik: start/krok/cyfry/base, kolejność wg sortowania,
- daty/czas: formaty ICU,
- szukaj‑zamień: tekst i regex z grupami `$1`, błędny wzorzec,
- konwersja wielkości liter + diakrytyki,
- kolizje: duplikaty, niedozwolone znaki, puste nazwy, nadpisania,
- wykonanie: cykle, zmiana samej wielkości liter, błąd pojedynczego pliku,
- undo: odwrócenie batcha (w tym z krokami tymczasowymi).

UI cienkie; testy UI minimalne (smoke). Logika nie zależy od UI.

---

## 12. Ryzyka / do potwierdzenia w implementacji
- **Menu Finder Sync** pojawia się tylko w monitorowanych katalogach — strategia „monitoruj dom + woluminy" do weryfikacji na bieżącym macOS.
- **App Group + Developer ID + niesandboxowana app** — potwierdzić, że odczyt pliku handoff z kontenera App Group działa, gdy zapisuje sandboxowane rozszerzenie, a czyta niesandboxowana app. (Alternatywa: przekazanie ścieżek w samym URL‑u lub przez katalog tymczasowy o znanej lokalizacji.)
- **Edytor tokenów jako „pigułki"** w SwiftUI — wymaga niestandardowego pola; fallback: zwykłe pole tekstowe z podświetlaniem tokenów.

---

## 13. Przyszłe rozszerzenia (poza v1)
Tryb ręcznej edycji, presety/historia, rekurencja podkatalogów, metadane EXIF, trwałe wielopoziomowe undo, integracja z Cofnij w Finderze, dodatkowe tokeny (data utworzenia, rozmiar, ścieżka względna).
