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

EA otwiera pozycję dopiero po **zamknięciu świecy H4**, gdy spełnione są
**wszystkie** poniższe warunki (każdy filtr można wyłączyć w parametrach):

### 3.1 LONG (BUY)
1. **Cena zamknięcia świecy 1 powyżej Kumo** (Senkou A i Senkou B).
2. **Świeży byczy TK Cross** (Tenkan przecina Kijun w górę) w ciągu
   ostatnich `InpTKCrossLookback` świec (domyślnie 5). Jeżeli filtr wyłączony —
   wystarczy `Tenkan > Kijun`.
3. **Mocny TK Cross**: przecięcie nastąpiło **ponad chmurą** (najsłabsza
   z linii TK > górna krawędź Kumo) — opcjonalne (`InpStrongTKCrossOnly`).
4. **Cena > Kijun-sen** (filtr trendu).
5. **Chikou Span > cena 26 świec wstecz** (potwierdzenie momentum).
6. **Przyszła chmura bycza**: projekcja `Senkou A > Senkou B` 26 świec do przodu
   (liczona klasycznie z aktualnych Tenkan/Kijun oraz max/min 52 świec).
7. Spread ≤ `InpMaxSpreadPoints`, sesja aktywna, brak blokady piątkowej.

### 3.2 SHORT (SELL)
Lustrzane warunki:
1. Cena < Kumo.
2. Świeży **niedźwiedzi TK Cross**.
3. Mocny TK Cross **pod chmurą**.
4. Cena < Kijun-sen.
5. Chikou Span < cena 26 świec wstecz.
6. Przyszła chmura niedźwiedzia (`Senkou A < Senkou B`).
7. Filtry rynkowe j.w.

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

- **Break-Even**: po osiągnięciu `InpBreakEvenAtR × R` (domyślnie 1R)
  SL przesuwany na poziom otwarcia + `InpBreakEvenOffsetPt` punktów (lock zysku).
- **Trailing po Kijun-sen**: SL podążający za Kijun-sen z buforem
  `InpKijunTrailBuffer`. SL podnosimy/obniżamy tylko, gdy nowy poziom jest
  bardziej konserwatywny (BUY: wyżej; SELL: niżej).
- **Wyjście awaryjne**:
  - odwrotny TK Cross (`InpExitOnTKCross`),
  - powrót ceny zamknięcia do/za chmurę (`InpExitOnCloudBreak`).

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

| Parametr | Domyślnie | Opis |
|---|---|---|
| `InpSymbol` | `""` | nazwa symbolu (puste = wykres) |
| `InpMagic` | `30040026` | unikalny magic dla EA |
| `InpTenkan / InpKijun / InpSenkouB` | `9 / 26 / 52` | klasyczne Ichimoku |
| `InpUseChikouFilter` | `true` | filtr Chikou |
| `InpUseFutureKumoFilter` | `true` | zgodność przyszłej chmury |
| `InpUseKijunFilter` | `true` | cena vs Kijun |
| `InpRequireTKCross` | `true` | wymagaj TK Cross |
| `InpStrongTKCrossOnly` | `true` | TK Cross po właściwej stronie chmury |
| `InpUseAutoLot` | `true` | autolot |
| `InpRiskPercent` | `1.0` | % equity na ryzyko |
| `InpATRMultSL` | `2.0` | mnożnik ATR dla SL |
| `InpRR` | `2.0` | Risk:Reward |
| `InpUseKijunTrailing` | `true` | trailing po Kijun |
| `InpUseBreakEven` | `true` | BE po 1R |
| `InpExitOnTKCross` | `true` | exit na odwrotnym TK |
| `InpExitOnCloudBreak` | `true` | exit za chmurą |
