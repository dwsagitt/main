# Pełna strategia Ichimoku — US30 H4 — BossaFX (MT5)

Niniejszy dokument opisuje kompletną, zautomatyzowaną strategię tradingową
opartą o wskaźnik **Ichimoku Kinko Hyo** dla indeksu **US30** (Dow Jones 30 CFD)
na interwale **H4**, dostępnego u brokera **BossaFX** w platformie **MetaTrader 5**.
Strategia używa **autolota** (procentowe ryzyko z equity konta), wielowarstwowych
filtrów trendu, dynamicznego SL/TP w oparciu o ATR + Kijun + Kumo oraz
trailingu po Kijun-sen.

Plik EA: [`MQL5/Experts/Ichimoku_US30_H4_BossaFX.mq5`](../MQL5/Experts/Ichimoku_US30_H4_BossaFX.mq5)

---

## 1. Założenia strategii

- Instrument: **US30** (CFD na Dow Jones Industrial Average)
- Broker: **BossaFX** (MT5). Symbol może mieć różne nazwy w Market Watch
  (`US30`, `US30.cash`, `DJI30`, `.US30`, `US30.pro` itp.) — patrz parametr
  `InpSymbol`.
- Interwał: **H4**
- Styl: **podążanie za trendem** (trend-following) na bazie sygnałów
  Ichimoku z wieloma filtrami potwierdzającymi.
- Frekwencja: kilka–kilkanaście transakcji w miesiącu (US30 H4 jest
  trendowy, ale Ichimoku z mocnymi filtrami filtruje większość fałszywek).
- Pozycjonowanie: maksymalnie **1 pozycja jednocześnie**, brak hedge
  (parametr).
- Decyzje są podejmowane wyłącznie na **zamkniętej świecy H4** (logika
  „one decision per bar" — eliminuje powtórzone sygnały intra-bar).

## 2. Składniki Ichimoku

Klasyczne wartości **9 / 26 / 52 / 26**:

- **Tenkan-sen** (9): średnia z (max H, min L) z 9 świec — krótkoterminowy moment.
- **Kijun-sen** (26): średnia z (max H, min L) z 26 świec — bazowa linia trendu.
- **Senkou Span A**: (Tenkan + Kijun) / 2, przesunięte 26 świec do przodu.
- **Senkou Span B** (52): średnia z (max H, min L) z 52 świec, przesunięta o 26.
- **Chikou Span**: cena zamknięcia, przesunięta 26 świec wstecz.
- **Kumo** (chmura): obszar między Senkou A a Senkou B.

## 3. Warunki wejścia (LONG / SHORT)

EA podejmuje decyzję dopiero po **zamknięciu świecy H4** i obsługuje
**dwa tryby wejścia** (oba można niezależnie włączać/wyłączać):

### 3.0 Wspólny zestaw filtrów trendu (obowiązuje w obu trybach)

Wszystkie poniższe muszą być spełnione (każdy można wyłączyć parametrem):

- **Cena zamknięcia [1] powyżej / poniżej Kumo** (`Senkou A`, `Senkou B`).
- **Cena vs Kijun-sen** po właściwej stronie (`InpUseKijunFilter`).
- **Chikou Span**: `close[1] > close[1+26]` (long) / odwrotnie (short)
  (`InpUseChikouFilter`).
- **Przyszła chmura zgodna z kierunkiem**: projekcja `Senkou A` vs `Senkou B`
  26 świec do przodu (`InpUseFutureKumoFilter`).
- **Slope filter** — *odpowiedź na obserwację, że "KS i TS nie spadał"*:
  - dla LONG: Kijun-sen i/lub Tenkan-sen muszą **rosnąć** w ciągu ostatnich
    `InpSlopeLookback` świec (domyślnie 3),
  - dla SHORT: muszą **spadać**.
  - `InpRequireKijunSlope = true` (domyślnie) — Kijun musi mieć właściwe
    nachylenie. To kluczowy filtr, eliminujący wejścia w bok.
  - `InpRequireTenkanSlope = false` (domyślnie) — Tenkan może być płaski.
- Filtry rynkowe: spread ≤ `InpMaxSpreadPoints`, sesja, brak blokady piątkowej,
  brak cooldownu po stracie.

### 3.1 Tryb 1: TK Cross (`InpEnableTKCrossEntry`)

Klasyczne wejście na **świeżym przecięciu Tenkan/Kijun**:

- **Świeży byczy/niedźwiedzi TK Cross** w ciągu ostatnich
  `InpTKCrossLookback` świec (domyślnie 5).
- **Mocny TK Cross** (`InpStrongTKCrossOnly`): obie linie TK po właściwej
  stronie chmury (powyżej całej Kumo dla LONG / poniżej dla SHORT).

Tryb dobry na **starty trendu** po wyjściu z konsolidacji/przebiciu chmury.
Ograniczenie: **w trwającym trendzie nie ma już świeżego TK Cross**, więc nie
łapie kontynuacji (stąd Tryb 2).

### 3.2 Tryb 2: Pullback bounce (`InpEnablePullbackEntry`) — *NOWY*

**Wejścia w trakcie trendu na korektach do Tenkan-sen/Kijun-sen.** To było
brakujące ogniwo — sygnał, którego oczekiwałeś na wykresie, gdy cena cofała
do TS/KS, a TS i KS nie spadały (cały czas rosły).

Warunki dodatkowe ponad sekcję 3.0:

- Cała struktura trendu potwierdzona: **TS po właściwej stronie KS** i **obie
  linie po właściwej stronie chmury** (silna struktura trendu).
- **Dotknięcie linii** (`InpPullbackOnTenkan` lub `InpPullbackOnKijun`)
  w ciągu ostatnich `InpPullbackLookback` świec (domyślnie 6):
  - LONG: `low[i] ≤ Tenkan/Kijun + InpPullbackTouchTolATR × ATR`,
  - SHORT: `high[i] ≥ Tenkan/Kijun − InpPullbackTouchTolATR × ATR`.
- **Świeca potwierdzająca [1]**:
  - LONG: `close[1] > Tenkan/Kijun[1]` **i** `close[1] > close[2]`
    (świeca odbiciowa zamykająca się ponad linią),
  - SHORT: lustrzanie.

Pullback do **Tenkan-sen** = częstsze, ciasne wejścia w mocnych trendach.
Pullback do **Kijun-sen** = rzadsze, głębsze korekty, większe RR.

## 4. Stop-Loss i Take-Profit

EA wybiera **najbardziej konserwatywny** SL spośród trzech kandydatów
(plus bufor `InpSLBufferPoints`):

- **SL ATR**: `cena − ATR(14) × 2.0` (LONG) / `cena + ATR(14) × 2.0` (SHORT).
- **SL Kijun**: za Kijun-sen (jeżeli `InpUseKijunSL = true`).
- **SL Kumo**: za przeciwnym brzegiem chmury (jeżeli `InpUseCloudSL = true`).

Ostatecznie wybierany jest SL **najdalszy od ceny** (najszerszy stop), aby
nie wybijać się na szumie. Następnie wymuszany jest minimalny dystans
SL (`InpMinStopPoints` oraz brokerowy `SYMBOL_TRADE_STOPS_LEVEL`).

**Take-Profit**: liczony jako wielokrotność dystansu SL, wg `InpRR`
(domyślnie **1:2**).

## 5. Zarządzanie pozycją

Kolejność operacji na każdym ticku (ale z `IsNewBarH4` dla logiki czasowej):

1. **Częściowy TP** (`InpUsePartialTP`, domyślnie ON): po osiągnięciu
   `InpPartialTPAtR × R` (domyślnie 1R) zamykane jest `InpPartialTPPercent`
   wolumenu (domyślnie 50%). Zostaje "runner" na resztę ruchu.
2. **Break-Even**: po osiągnięciu `InpBreakEvenAtR × R` (domyślnie 1R)
   SL przesuwany na poziom otwarcia + `InpBreakEvenOffsetPt` punktów (lock zysku).
3. **Trailing po Tenkan-sen** (`InpUseTenkanTrailing`, domyślnie OFF):
   ciaśniejszy trailing, włączany opcjonalnie **dopiero po częściowym TP**
   (`InpTenkanTrailAfterPartial`). Świetny do "runnerów" w mocnych trendach.
4. **Trailing po Kijun-sen** (`InpUseKijunTrailing`, domyślnie ON):
   bazowy trailing trendowy z buforem `InpKijunTrailBuffer`. SL przesuwa się
   tylko w kierunku zysku.
5. **Wyjścia awaryjne**:
   - odwrotny TK Cross (`InpExitOnTKCross`),
   - powrót ceny zamknięcia do/za chmurę (`InpExitOnCloudBreak`).

### Cooldown po stracie

`InpCooldownBarsAfterLoss` (domyślnie 2 świece H4) — po stratnej transakcji
EA pauzuje przez N świec. Chroni przed serią szybkich powtórnych wejść w tym
samym kierunku, gdy rynek właśnie się odwrócił.

## 6. AUTOLOT — wyliczanie wielkości pozycji

Wielkość pozycji liczona jest **dynamicznie** dla każdej transakcji w oparciu o:

- `InpRiskPercent` — % equity konta przeznaczony na ryzyko (domyślnie 1.0%).
- Dystans SL w punktach (`slDistancePoints`).
- Wartość 1 punktu na 1 lot dla danego instrumentu w walucie konta:
  `tickValue × point / tickSize` (poprawne dla CFD na indeksy, gdzie
  `tickSize ≠ point`).

Wzór:

```
ryzykoMoney = equity × InpRiskPercent / 100
lot = ryzykoMoney / (slDistancePoints × wartość1pktNa1Lot)
```

Wynik jest normalizowany do kroku wolumenu brokera (`SYMBOL_VOLUME_STEP`),
ograniczony do `[VOLUME_MIN, VOLUME_MAX]` oraz `[InpMinLot, InpMaxLot]`.
Dodatkowo można nałożyć **twardy cap ryzyka w walucie konta** (`InpMaxRiskCapEUR`).

Jeżeli `InpUseAutoLot = false`, używany jest stały lot `InpFixedLot`.

## 7. Filtry rynkowe

- **Spread**: maksymalny dozwolony spread w punktach (`InpMaxSpreadPoints`).
  Domyślnie 80 pkt (~ 0.8 pkt cenowego). BossaFX ma na US30 spready typu
  1.5–3 pkt cenowych w godzinach handlu (1 pkt cenowy = 100 pt na większości
  konfiguracji), więc wartość należy dostroić po sprawdzeniu specyfikacji
  symbolu w Market Watch (Ctrl+U → Specyfikacja).
- **Sesja**: opcjonalne ograniczenie godzinowe (godziny serwera). Domyślnie
  wyłączone — Ichimoku pracuje na świecach, więc pora jest mniej istotna,
  ale można zawęzić handel do nakładki sesji EU/US (np. 13:00–22:00 czasu
  serwera dla brokerów EET/EEST).
- **Blokada piątkowa**: brak nowych wejść po `InpFridayCloseHour` w piątek
  (domyślnie 20:00) — chroni przed luką weekendową.

## 8. Backtest — rekomendowana procedura

1. W terminalu MT5 → **Tester strategii** (Ctrl+R).
2. Wybierz EA `Ichimoku_US30_H4_BossaFX`.
3. Symbol: nazwa US30 z Twojego Market Watch (BossaFX).
4. Interwał: **H4**.
5. Model: **Każdy tick na bazie rzeczywistych ticków** (zalecane) lub
   **Tylko ceny otwarcia** (szybciej, dla wstępnego sweepu — strategia
   działa na zamkniętych świecach, więc wynik jest reprezentatywny).
6. Okres: minimum 3 lata (US30 ma cykle byk/niedźwiedź — 2018–2026 daje
   pełny obraz).
7. Optymalizacja parametrów (sugerowane zakresy):
   - `InpATRMultSL`: 1.5–3.0 (krok 0.25)
   - `InpRR`: 1.5–3.0 (krok 0.5)
   - `InpKijun`: 22–30 (krok 2)
   - `InpRiskPercent`: 0.5–2.0 (krok 0.25)

## 9. Ograniczenia i ryzyka

- **Slippage i luki**: US30 potrafi otworzyć w niedzielę z luką po
  niespodziankach makro. Pozycja zostanie zamknięta po SL z poślizgiem
  (CFD bez gwarantowanego SL).
- **Spready zmienne**: poza godzinami płynności (np. 23:00–01:00
  serwera) spread potrafi być kilkukrotnie szerszy. Filtr spreadu
  chroni przed wejściami w takim oknie.
- **Slippage przy newsach**: NFP, CPI, decyzje FOMC. Dla bezpieczeństwa
  można dodać kalendarz makro (poza zakresem domyślnej wersji EA).
- **Backtest ≠ live**: zawsze testuj minimum 4–6 tygodni na koncie demo
  BossaFX przed uruchomieniem na realu.

## 10. Parametry — lista skrócona

### Tryby wejścia

| Parametr | Domyślnie | Opis |
|---|---|---|
| `InpEnableTKCrossEntry` | `true` | Tryb 1: TK Cross |
| `InpEnablePullbackEntry` | `true` | Tryb 2: Pullback do TS/KS |
| `InpPullbackOnTenkan` | `true` | Pullback do Tenkan |
| `InpPullbackOnKijun` | `true` | Pullback do Kijun |
| `InpPullbackLookback` | `6` | Lookback świec dla dotknięcia |
| `InpPullbackTouchTolATR` | `0.25` | Tolerancja dotknięcia (× ATR) |

### Filtry trendu

| Parametr | Domyślnie | Opis |
|---|---|---|
| `InpUseChikouFilter` | `true` | filtr Chikou |
| `InpUseFutureKumoFilter` | `true` | zgodność przyszłej chmury |
| `InpUseKijunFilter` | `true` | cena vs Kijun |
| `InpRequireTKCross` | `true` | wymagaj TK Cross (tryb 1) |
| `InpTKCrossLookback` | `5` | lookback dla TK Cross |
| `InpStrongTKCrossOnly` | `true` | TK Cross po właściwej stronie chmury |
| `InpUseSlopeFilter` | `true` | **Filtr nachylenia TS/KS** |
| `InpSlopeLookback` | `3` | Lookback świec dla slope |
| `InpRequireKijunSlope` | `true` | KS musi mieć właściwy kierunek |
| `InpRequireTenkanSlope` | `false` | TS musi mieć właściwy kierunek |

### Ryzyko / SL/TP

| Parametr | Domyślnie | Opis |
|---|---|---|
| `InpUseAutoLot` | `true` | autolot |
| `InpRiskPercent` | `1.0` | % equity na ryzyko |
| `InpATRMultSL` | `2.0` | mnożnik ATR dla SL |
| `InpRR` | `2.0` | Risk:Reward |
| `InpUseKijunSL` / `InpUseCloudSL` | `true` | dodatkowe kandydaty SL |

### Trailing i wyjścia

| Parametr | Domyślnie | Opis |
|---|---|---|
| `InpUsePartialTP` | `true` | częściowy TP po 1R |
| `InpPartialTPAtR` | `1.0` | przy ilu R |
| `InpPartialTPPercent` | `50.0` | % wolumenu zamykanego |
| `InpUseBreakEven` | `true` | BE po 1R |
| `InpUseKijunTrailing` | `true` | trailing po Kijun |
| `InpUseTenkanTrailing` | `false` | trailing po Tenkan (ciaśniejszy) |
| `InpTenkanTrailAfterPartial` | `true` | Tenkan-trailing po częściowym TP |
| `InpExitOnTKCross` | `true` | exit na odwrotnym TK |
| `InpExitOnCloudBreak` | `true` | exit za chmurą |
| `InpCooldownBarsAfterLoss` | `2` | pauza po stracie (świece H4) |

## 11. Diagnostyka — DLACZEGO EA nie wszedł w danym miejscu

W wersji **1.11** dodano tryb diagnostyczny:

| Parametr | Domyślnie | Opis |
|---|---|---|
| `InpVerboseDiagnostics` | `false` | Loguj w Journal/Experts dlaczego sygnał został odrzucony |
| `InpDrawSignalArrows` | `false` | Rysuj zielone/czerwone strzałki dla **zaakceptowanych** sygnałów |
| `InpDrawRejectedDots` | `false` | Rysuj szare krzyżyki dla setupów odrzuconych po przejściu filtrów bazowych |

### Jak używać

1. Włącz `InpVerboseDiagnostics = true` (i opcjonalnie `InpDrawRejectedDots = true`).
2. Uruchom **Tester strategii** w trybie wizualnym albo nałóż EA na wykres.
3. Po każdej zamkniętej świecy H4 EA wypisuje w **Journal** zakładce Tester /
   Experts dokładnie powód odrzucenia, np.:

```
[2026.02.18 04:00] LONG odrzucony: PriceVsCloud (close=46123 Kumo[46500..47100])
[2026.02.20 12:00] SHORT odrzucony: Chikou (close[1]=46500 vs close[27]=46300)
[2026.03.05 08:00] LONG [PB_TENKAN]: brak dotkniecia/potwierdzenia TS (lookback=6, tol=0.25ATR)
[2026.03.10 16:00] SHORT [PB_KIJUN]: brak dotkniecia/potwierdzenia KS (lookback=6, tol=0.25ATR)
```

### Najczęstsze powody odrzucenia (i jak je „rozluźnić")

| Powód w Journalu | Co zrobić |
|---|---|
| `Slope (...)` | Zmniejsz `InpSlopeLookback` z 3 → 2 lub wyłącz `InpRequireKijunSlope` |
| `FutureKumo` | Wyłącz `InpUseFutureKumoFilter` — bardzo restrykcyjny w bocznym rynku |
| `Chikou` | Wyłącz `InpUseChikouFilter` (pozbywasz się pewności momentum) |
| `[TKCROSS]: brak swiezego TK Cross` | Zwiększ `InpTKCrossLookback` z 5 → 8 lub polegaj na trybie pullback |
| `[PB]: trend nie potwierdzony` | Cena wraca do/do chmury — to **dobre** odrzucenie, nie ruszać |
| `[PB_TENKAN]: brak dotkniecia` | Zwiększ `InpPullbackTouchTolATR` z 0.25 → 0.5 lub `InpPullbackLookback` 6 → 10 |

### Wizualizacja na wykresie

Włącz `InpDrawSignalArrows = true`:
- **Zielona strzałka w górę** = zaakceptowany sygnał LONG (z etykietą TKCROSS / PB_TENKAN / PB_KIJUN)
- **Czerwona strzałka w dół** = zaakceptowany sygnał SHORT
- **Szary krzyżyk** (gdy `InpDrawRejectedDots = true`) = setup miał poprawne filtry bazowe, ale brakło konkretnego trigera

To pozwala zobaczyć **na wykresie**, gdzie EA „prawie wszedł", i porównać z miejscami, w których oczekiwałeś wejścia.

## 12. Co dodano w wersji 1.10

W odpowiedzi na obserwację z backtestu (US30 H4, sierpień–listopad 2025,
zysk netto +869 / +8.69%, 29 transakcji, 55% Profit Trades, 1.52 PF):

- **Drugi tryb wejścia (Pullback bounce)** — łapie kontynuacje trendu, gdy
  cena cofa do Tenkan-sen lub Kijun-sen (odpowiedź na "dlaczego nie otworzył
  transakcji w zaznaczonych miejscach").
- **Filtr nachylenia (slope)** Tenkan/Kijun — bezpośrednia odpowiedź na
  obserwację "KS i TS nie spadał": teraz EA wymaga, by Kijun (i opcjonalnie
  Tenkan) miały właściwy kierunek nachylenia.
- **Częściowy TP po 1R** + **trailing po Tenkan-sen** dla "runnera" w mocnych
  trendach (lepsze wyciskanie z trendu, mniejszy drawdown).
- **Cooldown po stracie** — chroni przed kaskadami stratnych wejść.
- **One-position-per-bar** dotyczy teraz tylko TK Cross — pullback może
  pojawić się tuż po zamknięciu poprzedniej pozycji.
