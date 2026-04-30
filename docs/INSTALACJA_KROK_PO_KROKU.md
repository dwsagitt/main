# Instalacja krok-po-kroku — Ichimoku US30 H4 BossaFX

Ten dokument prowadzi Cię przez **całą procedurę** od zera do działającego backtestu, z zaznaczeniem **wszystkich miejsc, gdzie najczęściej się myli** (i jak to wykryć w 5 sekund).

## Krok 1 — Pobierz najnowszą wersję

### Wariant A: ręcznie

1. Otwórz w przeglądarce: <https://github.com/dwsagitt/main/blob/cursor/ichimoku-us30-h4-bossafx-6e41/MQL5/Experts/Ichimoku_US30_H4_BossaFX.mq5>
2. Kliknij **Raw** (przycisk prawej strony).
3. `Ctrl+S` → zapisz plik z **dokładnie taką samą nazwą**: `Ichimoku_US30_H4_BossaFX.mq5`.

### Wariant B: skrypt (zalecany)

Użyj `scripts/sync_to_mt5.bat` — opisany w `README.md` rozdział „Co potrafi EA".

## Krok 2 — Wgraj do MT5

1. W BossaFX MT5: **Plik → Otwórz katalog danych** (`Ctrl+Shift+D`).
2. Otworzy się Eksplorator. Wejdź do `MQL5\Experts\`.
3. Wklej plik `Ichimoku_US30_H4_BossaFX.mq5` **nadpisując** poprzedni.
4. Wgraj też pliki `.set` z `MQL5/Presets/` do katalogu `MQL5\Presets\` w MT5 (utwórz folder, jeśli go nie ma).

## Krok 3 — Skompiluj

1. **WAŻNE**: zamknij Tester strategii i zdejmij EA ze wszystkich wykresów (przeciągnij na pulpit lub prawym → Remove). Inaczej MT5 trzyma `.ex5` zablokowany i kompilacja po cichu nie zadziała.
2. Otwórz **MetaEditor** (F4 w MT5).
3. W drzewie po lewej rozwiń `Experts` → kliknij dwa razy `Ichimoku_US30_H4_BossaFX.mq5`.
4. **Sprawdź na samej górze pliku linijkę `#property version`** — musi być `"1.15"` (lub nowsza). Jeśli widzisz `"1.00"` — plik z Kroku 2 nie zastąpił poprzedniego (uprawnienia? otwarte EA?).
5. **F7** (Compile).
6. W panelu „Errors" na dole musi być `0 errors, 0 warnings`.
7. W Eksploratorze sprawdź plik `Ichimoku_US30_H4_BossaFX.ex5` w `MQL5\Experts\` — **data modyfikacji** musi być świeża (sprzed kilku sekund).

## Krok 4 — Test 5-sekundowy: czy MT5 widzi nową wersję

1. W MT5 → **F5** w panelu Nawigator (odświeża listę EA).
2. Przeciągnij EA na **dowolny** wykres (chwilowo).
3. W Journal (zakładka „Eksperci" pod oknem terminala) zobaczysz:
   ```
   ================================================================
     Ichimoku US30 H4 BossaFX  v1.15   uruchomiony na ..., TF=...
   ================================================================
   ```
4. Na samym wykresie w lewym górnym rogu pojawi się komentarz `[Ichimoku v1.15] TF=H4 OK` (lub czerwony backgrund jeśli zły TF).
5. **Jeżeli widzisz `v1.00` lub brak komentarza** — masz nadal starą `.ex5`. Wróć do Kroku 3.

## Krok 5 — Backtest

1. **Ctrl+R** → Tester strategii.
2. Zakładka **Settings**:
   - **Expert**: `Ichimoku_US30_H4_BossaFX`
   - **Symbol**: `US30` (lub jak BossaFX nazwał — `US30.cash`, `DJI30`, `.US30` — sprawdź w Market Watch).
   - **Period**: ⚠️ **H4** ⚠️ (NIE H1, NIE M30, NIE D1).
   - **Date**: minimum 2 lata do tyłu (np. 2024-01-01 do dziś).
   - **Modeling**: Every tick based on real ticks (lub Open prices only — szybsze, wystarcza dla EA na zamkniętej świecy).
   - **Optimization**: Disabled (na razie).
3. Zakładka **Inputs**:
   - Kliknij **Load** (dolna prawa) → wczytaj `Ichimoku_US30_H4_Balanced.set` z `MQL5\Presets\`.
   - **Sprawdź czy widzisz parametr `InpEnforceH4`** — jeśli nie ma, masz starą `.ex5` (wróć do Kroku 3).
4. Kliknij **Start**.

## Krok 6 — Walidacja wyniku

Dla preseta **Balanced** na US30 H4 (3 lata historii) oczekiwane proporcje:

| Metryka | Sensowny zakres |
|---|---|
| Liczba transakcji | 30-100 |
| Profit Factor | 1.3-1.8 |
| Win Trades % | 45-60% |
| Max DD | 5-15% |
| Sharpe | > 0.5 |

**Jeżeli zobaczysz**:
- 100+ transakcji + ujemny zysk + Sharpe < 0 → **najpewniej Period ≠ H4** (wróć do Kroku 5 ppkt 2).
- Identyczne liczby co poprzednio mimo zmienionych dat → **stara `.ex5`** (wróć do Kroku 3).

## Najczęstsze błędy

### „Liczby są dokładnie takie same co ostatnio"
Stara skompilowana `.ex5`. Sprawdź w Inputs Testera obecność parametru `InpEnforceH4` — jeśli nie ma, kompilacja nie nadpisała.

### „161 transakcji i ujemny wynik"
TF inny niż H4. Sprawdź zakładkę **Settings** Testera, pole **Period**.

### „EA nie startuje, INIT_FAILED w Journal"
W v1.15 to **celowe** zachowanie, gdy `InpEnforceH4=true` a Period ≠ H4. Zmień Period na H4 albo (jeśli świadomie chcesz testować inny TF) ustaw `InpEnforceH4=false`.

### „Brak presetów na liście Load"
Pliki `.set` muszą być w `MQL5\Presets\` w katalogu danych MT5 (Krok 2 ppkt 4). Po wgraniu może być potrzebny restart MT5.
