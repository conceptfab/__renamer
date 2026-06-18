# Specyfikacja: Renamer v2 — 4 nowe funkcje

**Data:** 2026-06-19
**Status:** Projekt zatwierdzony (brainstorming) — gotowy do planu implementacji
**Bazuje na:** zaimplementowanym MVP (`RenamerCore/` + `Renamer/`), spec `2026-06-18-macos-batch-renamer-design.md`

---

## 1. Cel

Dodać do istniejącej aplikacji cztery funkcje:

1. **Potwierdzenie operacji** — czytelny komunikat sukcesu/błędu po zmianie nazw.
2. **Chroń rozszerzenie pliku** — reguły nie zmieniają rozszerzenia (domyślnie włączone).
3. **Presety** — zapisane schematy konfiguracji (dodaj / usuń / zmień nazwę).
4. **Pomocniki Szukaj/Zamień** — wstawianie wyrażeń regex w „Szukaj" oraz zmiennych w „Zamień".

---

## 2. Stan obecny (punkt wyjścia)

Z analizy kodu:

- **`RenamerCore/`** — Swift Package z silnikiem. Pipeline w `PlanBuilder.proposedName(for:index:config:)`: `szablon → szukaj-zamień (FindReplace.apply) → wielkość liter (osobno nazwa/ext przez NameComponents)`.
- **`Renamer/`** — aplikacja SwiftUI, `RenameSession: ObservableObject` (@MainActor, `@Published`), wstrzykiwana przez `.environmentObject`. Pliki: `RenamerApp`, `RenameSession`, `ContentView`, `ControlsPanel`, `PreviewTable`, `FooterBar`, `DropZoneView`, `SettingsStore`.
- **Potwierdzenie dziś:** tylko `statusMessage` w stopce (łatwe do przeoczenia). `apply(overwrite:)` ustawia tekst sukcesu/błędu i nagrywa `undoBatch`.
- **Rozszerzenie pliku:** zawsze przetwarzane; brak pojęcia blokady.
- **Trwałość:** `SettingsStore` zapisuje bieżącą konfigurację w `UserDefaults` (klucze `renamer.*`). Brak presetów.
- **Tryb szukania:** checkbox „Regex" (`isRegex: Bool`). Replacement jest dosłowny (regex obsługuje `$1`).
- **Wstawianie zmiennych:** dostępne dla pola „Nowa nazwa"; nie ma go dla „Zamień".
- **Testy:** `swift test` w `RenamerCore` (13 plików). Aplikacja nie ma testów (target wykonywalny).
- **Język:** polskie napisy inline (bez `Localizable.strings`).

---

## 3. Decyzje (z brainstormingu)

| Temat | Decyzja |
|---|---|
| Potwierdzenie | Baner sukcesu (auto-znika, z „Cofnij") + okno modalne z listą przy błędach |
| Blokada rozszerzenia — domyślnie | WŁĄCZONA (rdzeń neutralny `false`, aplikacja `true`) |
| Semantyka blokady | odetnij oryginalne rozszerzenie → przetwarzaj tylko nazwę → doklej oryginalne; szukaj-zamień ignoruje rozszerzenie |
| Presety | tylko własne (start pusty); dodaj / usuń / zmień nazwę; preset = pełna konfiguracja |
| Wildcardy | odrzucone (redundantne z regex) |
| Tryb szukania | przełącznik 2-stanowy: Zwykły tekst / Regex |
| Pomocnik „Szukaj" | menu „Wstaw wyrażenie" (wzorce regex) + ściągawka |
| Pomocnik „Zamień" | menu „+ Wstaw" ze zmiennymi (jak „Nowa nazwa") + grupy `$1` w trybie regex |
| Tokeny w „Zamień" | rozwijane per-plik przed wykonaniem zamiany |

---

## 4. Funkcja #1 — Potwierdzenie operacji

### Model (aplikacja)
W `RenameSession` dodać:
```swift
struct SuccessBanner: Equatable { let count: Int; let canUndo: Bool }
struct FailureReport: Identifiable, Equatable {
    let id = UUID()
    let successCount: Int
    let failures: [FailureLine]      // (name, message)
}
struct FailureLine: Identifiable, Equatable { let id = UUID(); let name: String; let message: String }

@Published var successBanner: SuccessBanner?
@Published var failureReport: FailureReport?
```

### Logika w `apply(overwrite:)`
- Po `engine.apply(...)`:
  - `result.failures.isEmpty` → `successBanner = SuccessBanner(count: toApply.count, canUndo: true)`; uruchom auto-ukrycie po ~4 s (anulowalne `Task`, czyszczone przy nowej operacji).
  - inaczej → `failureReport = FailureReport(successCount: udane, failures: mapuj result.failures)`; baner nie pokazuje się.
- `catch` → `failureReport` z jednym wpisem (komunikat błędu).
- `statusMessage` aktualizowany jak dziś (zostaje jako dyskretny status).

### Widoki
- `ResultBanner` — overlay u góry `ContentView` (animowany `transition(.move(.top).combined(with:.opacity))`), z ✓, liczbą, „Cofnij" (woła `undoLast()`), „✕" (czyści baner).
- `FailureReportSheet` — `.sheet(item: $session.failureReport)`: przewijalna lista `failures`, nagłówek „Zmieniono N · Błędy M", przycisk „OK" czyszczący raport.
- Auto-ukrycie banera: gdy `successBanner` ustawiony, `Task` śpi 4 s i zeruje (przerywany przy kolejnym `apply`/`undo`).

---

## 5. Funkcja #2 — Chroń rozszerzenie pliku

### Rdzeń
- `RenameConfig` zyskuje pole `lockExtension: Bool`; init z domyślnym `false`:
  ```swift
  public init(template: String, find: FindReplace, nameCase: CaseMode,
              extCase: CaseMode, stripDiacritics: Bool, lockExtension: Bool = false)
  ```
  (domyślny argument zachowuje zgodność z istniejącymi wywołaniami i testami)

### Pipeline `PlanBuilder.proposedName`
- **`lockExtension == false`** — bez zmian (obecne zachowanie).
- **`lockExtension == true`:**
  1. `originalExt = item.ext`, `originalHadDot = NameComponents(fullName: item.fullName).hadDot`
  2. `workingBase`:
     - szablon pusty → `item.baseName`
     - szablon niepusty → `NameComponents(fullName: evaluate(szablon)).base` (odetnij rozszerzenie wyprodukowane przez szablon)
  3. szukaj-zamień działa na `workingBase` (nigdy na rozszerzeniu)
  4. `newBase = CaseTransformer.apply(replaced, mode: nameCase, stripDiacritics:)`
  5. wynik = `NameComponents(base: newBase, ext: originalExt, hadDot: originalHadDot).fullName`
- Konsekwencja: `extCase` nie ma wpływu przy włączonej blokadzie; chronione jest **ostatnie** rozszerzenie (zgodnie z `NameComponents`).

### Aplikacja
- `RenameSession`: `@Published var lockExtension: Bool = true`; przekazywane do `RenameConfig` w `rebuildPlanNow()`.
- `SettingsStore.Snapshot` + klucz `renamer.lockExtension` (domyślnie `true`).
- `ControlsPanel`: przełącznik „Chroń rozszerzenie pliku"; gdy włączony, lista „wielkość rozszerzenia" (`extCase`) jest `.disabled(true)`.

---

## 6. Funkcja #3 — Presety

### Rdzeń (domena + operacje)
- `Codable` dla: `CaseMode` (enum String — dodać do listy protokołów), `FindReplace` (struct prosty), `RenameConfig`.
- Nowy typ:
  ```swift
  public struct Preset: Identifiable, Codable, Equatable {
      public let id: UUID
      public var name: String
      public var config: RenameConfig
      public init(id: UUID = UUID(), name: String, config: RenameConfig)
  }
  ```
  > Uwaga: `id: UUID = UUID()` używa losowości — dopuszczalne w kodzie aplikacji/rdzenia w runtime; testy konstruują `Preset` z jawnym `id`.
- Czyste operacje (zwracają nową tablicę, w pełni testowalne):
  ```swift
  public enum PresetManager {
      public static func add(_ preset: Preset, to presets: [Preset]) -> [Preset]
      public static func delete(id: UUID, from presets: [Preset]) -> [Preset]
      public static func rename(id: UUID, to name: String, in presets: [Preset]) -> [Preset]
  }
  ```

### Aplikacja (trwałość + wiązanie)
- `PresetStore` — zapis/odczyt `[Preset]` jako JSON w `UserDefaults` (klucz `renamer.presets`), wzorzec jak `SettingsStore`.
- `RenameSession`:
  - `@Published var presets: [Preset] = []`, `@Published var selectedPresetID: UUID?`
  - `var currentConfig: RenameConfig { get }` (z bieżących pól) i `func apply(config: RenameConfig)` (ustawia pola + rebuild + persist).
  - metody: `applyPreset(_:)`, `saveCurrentAsPreset(name:)`, `deletePreset(id:)`, `renamePreset(id:to:)` — używają `PresetManager` + `PresetStore`.
  - presety ładowane w `init()`.

### UI
- W `ControlsPanel` (góra) pasek presetów: `Menu`/`Picker` „Schemat ▾" (wybór = `applyPreset`) + menu zarządzania („Zapisz jako…", „Zmień nazwę…", „Usuń").
- Nazwa presetu: `.alert` z `TextField` (SwiftUI) dla „Zapisz jako…" i „Zmień nazwę…".

---

## 7. Funkcja #4 — Pomocniki Szukaj/Zamień

### Tryb szukania
- Zamiana checkboxa „Regex" na przełącznik 2-stanowy (segmentowany `Picker`): **Zwykły tekst / Regex**. Mapuje na istniejące `isRegex: Bool` w `FindReplace` (bez nowego pola; enum w UI → `isRegex`).

### Pole „Szukaj" — pomocnik regex
- Przycisk/menu „Wstaw wyrażenie ▾" wstawiające wzorce w miejscu kursora: `.` (dowolny znak), `.*` (dowolny ciąg), `\d` (cyfra), `\w` (znak słowa), `\s` (odstęp), `(…)` (grupa), `^` (początek), `$` (koniec), `[…]` (zbiór).
- Jednolinijkowa ściągawka pod polem (widoczna w trybie Regex).

### Pole „Zamień" — wstawianie zmiennych
- Menu „+ Wstaw ▾" ze zmiennymi: `{name}`, `{ext}`, `{counter:001}`, `{date:yyyy-MM-dd}`, `{time:HH-mm-ss}`, `{parent}` — analogicznie do „Nowa nazwa".
- W trybie Regex dodatkowo grupy `$1`, `$2`, `$3`.
- Komponent `VariableInsertMenu` wydzielony i współdzielony przez „Nowa nazwa" i „Zamień" (po przejrzeniu `ControlsPanel` przy implementacji: wydzielić istniejący lub stworzyć nowy).

### Zmiana w silniku — tokeny w „Zamień"
- W `PlanBuilder.proposedName`, **przed** wykonaniem zamiany, pole replacement jest rozwijane jak mini-szablon per-plik:
  ```swift
  let expandedReplacement = try evaluator.evaluate(
      TemplateParser.parse(config.find.replacement), item: item, index: index)
  let effectiveFind = FindReplace(search: config.find.search,
                                  replacement: expandedReplacement,
                                  isRegex: config.find.isRegex,
                                  caseSensitive: config.find.caseSensitive)
  ```
  Następnie `effectiveFind.apply(to:)`.
- `TemplateEvaluator` przetwarza tylko `{…}` (oraz `{{`/`}}`), więc `$1` w trybie regex przechodzi nietknięte do `NSRegularExpression`.
- Pusty replacement → `parse` zwraca `[]` → `""` (bez zmian zachowania).
- Błędny token w replacement (np. `{bogus}`) → wyjątek → wiersz oznaczony błędem (jak dziś dla błędnego szablonu).
- **Znana granica (udokumentowana):** token zwracający literalny `$` (np. nazwa pliku `cena$5`) w trybie regex może zostać zinterpretowany jako odwołanie do grupy. Akceptowalne w v2; obejście — tryb Zwykły tekst.

### API `FindReplace`
Bez zmian (nadal `search/replacement/isRegex/caseSensitive`). Rozwijanie tokenów odbywa się w `PlanBuilder`, nie w `FindReplace`.

---

## 8. Pliki — co powstaje / co się zmienia

### RenamerCore
- Modyfikacja: `RenameConfig.swift` (`lockExtension` + `Codable`), `FindReplace.swift` (`Codable`), `CaseTransformer.swift` (`CaseMode: Codable`), `PlanBuilder.swift` (blokada rozszerzenia + rozwijanie replacement).
- Nowe: `Preset.swift`, `PresetManager.swift`.
- Testy: `LockExtensionTests.swift`, `ReplaceTokensTests.swift`, `CodableTests.swift`, `PresetManagerTests.swift` (oraz uzupełnienia w `PipelineTests`).

### Renamer (aplikacja)
- Modyfikacja: `RenameSession.swift` (stan + metody #1/#2/#3/#4), `ControlsPanel.swift` (tryb, pomocniki, blokada, pasek presetów), `ContentView.swift` (overlay banera + sheet błędów), `SettingsStore.swift` (`lockExtension`), `FooterBar.swift` (drobne).
- Nowe: `PresetStore.swift`, `ResultBanner.swift`, `FailureReportSheet.swift`, `VariableInsertMenu.swift` (współdzielony), `RegexHelperMenu.swift`.

---

## 9. Strategia testów
- **Rdzeń (TDD, `swift test`):**
  - blokada rozszerzenia: szablon pusty / niepusty (z `.{ext}` w szablonie), z szukaj-zamień (w tym regex próbujący dotknąć rozszerzenia), plik bez rozszerzenia, dotfile;
  - rozwijanie tokenów w „Zamień": `{counter:001}` daje kolejne numery; współistnienie `{counter}` i `$1` w trybie regex; pusty replacement; błędny token;
  - `Codable` round-trip dla `RenameConfig`/`FindReplace`/`Preset`;
  - `PresetManager` add/delete/rename (w tym usuwanie nieistniejącego id, zmiana nazwy nieistniejącego id → bez zmian).
- **Aplikacja (brak harnessu UI — ręczna weryfikacja `swift run Renamer`):**
  - baner po sukcesie znika sam i ma „Cofnij"; okno błędów przy wymuszonej kolizji;
  - blokada rozszerzenia ON dezaktywuje `extCase` i chroni `.jpg`;
  - presety: zapisz jako / zastosuj / zmień nazwę / usuń, trwałość po restarcie;
  - menu „Wstaw wyrażenie" (Szukaj) i „+ Wstaw" (Zamień) wstawiają w miejscu kursora; `{counter}` w „Zamień" numeruje w podglądzie.
  - każda zmiana w aplikacji weryfikowana `swift build`.

---

## 10. Ryzyka / do potwierdzenia w implementacji
- Czy „Nowa nazwa" ma już komponent wstawiania zmiennych do wydzielenia, czy trzeba go stworzyć (sprawdzić `ControlsPanel.swift`).
- `Preset` jest w rdzeniu, ale `PresetStore` (UserDefaults) w aplikacji — granica czysta; rdzeń bez zależności od `UserDefaults`.
- Edge `$` z tokenu w trybie regex — udokumentowane ograniczenie, nie blokuje v2.

---

## 11. Poza zakresem (na później)
Aktualizacja zawartości presetu „w miejscu" (na razie usuń+dodaj lub zmiana nazwy), import/eksport presetów, wbudowane presety startowe, lokalizacja na inne języki, Finder Sync Extension (osobny plan).
