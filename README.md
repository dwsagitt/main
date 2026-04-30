# Ichimoku US30 H4 — BossaFX (MT5)

Pełna, gotowa do uruchomienia strategia tradingowa oparta o **Ichimoku Kinko Hyo**
dla indeksu **US30** (Dow Jones 30 CFD) na interwale **H4**, dla brokera
**BossaFX** w platformie **MetaTrader 5**, z wbudowanym **autolotem**
(procentowe ryzyko z equity).

## Zawartość repozytorium

- [`MQL5/Experts/Ichimoku_US30_H4_BossaFX.mq5`](MQL5/Experts/Ichimoku_US30_H4_BossaFX.mq5) — Expert Advisor (kompilowalny w MetaEditor 5).
- [`docs/STRATEGIA.md`](docs/STRATEGIA.md) — pełna dokumentacja strategii: warunki wejścia, SL/TP, autolot, filtry, parametry.

## Co potrafi EA (v1.10)

- **Dwa tryby wejścia**:
  - **TK Cross** — świeże przecięcie Tenkan/Kijun nad/pod chmurą (start trendu).
  - **Pullback bounce** — wejścia na korektach do Tenkan-sen lub Kijun-sen
    w potwierdzonym trendzie (kontynuacja trendu — łapie sygnały, których
    nie generuje sam TK Cross).
- **Filtr nachylenia (slope)** Tenkan/Kijun — wymusza, by Kijun (i opcjonalnie
  Tenkan) miały właściwy kierunek (długi → KS rośnie, short → KS spada).
- Pełen zestaw klasycznych filtrów Ichimoku:
  - cena vs chmura (Kumo),
  - filtr Kijun-sen,
  - filtr Chikou Span (close[1] vs close[27]),
  - filtr przyszłej chmury (projekcja Senkou A vs B 26 świec do przodu).
- **Decyzje na zamknięciu świecy H4**.
- **Dynamiczny SL/TP**: najszerszy z (ATR×2, za Kijun, za przeciwnym brzegiem Kumo) + bufor; TP wg Risk:Reward (domyślnie 1:2).
- **Autolot** — pozycja liczona z equity, % ryzyka i dystansu SL.
- **Częściowy TP po 1R** (50% wolumenu) + **runner** z trailingiem.
- **Break-Even po 1R** z lockiem zysku.
- **Dwustopniowy trailing**: po **Tenkan-sen** (ciaśniejszy, opcjonalny po
  częściowym TP) i po **Kijun-sen** (bazowy).
- **Wyjścia awaryjne** na odwrotnym TK Cross lub powrocie ceny do/za chmurę.
- **Cooldown po stracie** (N świec H4 pauzy).
- Filtry **spreadu**, **sesji**, **blokady piątkowej**, **max pozycji**, hedge off.
- Zgodność z brokerem **BossaFX** — wybór symbolu przez parametr (US30 / US30.cash / DJI30 / .US30 itp.).

## Instalacja w MT5 (BossaFX)

1. Skopiuj plik `MQL5/Experts/Ichimoku_US30_H4_BossaFX.mq5` do katalogu
   danych MT5: w platformie wybierz `Plik → Otwórz katalog danych`,
   następnie wklej plik do `MQL5/Experts/`.
2. Otwórz **MetaEditor** (F4) → znajdź EA w drzewie po lewej → **Compile**
   (F7). Powinno powstać `.ex5` bez ostrzeżeń.
3. W MT5 odśwież listę EA (F5 w oknie Nawigator) i przeciągnij EA na
   wykres **US30, H4**.
4. W zakładce **Common**: zaznacz „Allow Algo Trading".
5. W zakładce **Inputs** dostosuj parametry — w szczególności:
   - `InpSymbol` — wpisz dokładną nazwę symbolu z Market Watch (BossaFX
     używa różnych konwencji w zależności od typu konta; sprawdź `Ctrl+U`).
     Pozostawienie pola pustego użyje symbolu bieżącego wykresu.
   - `InpRiskPercent` — % equity na transakcję (domyślnie **1.0%**).
   - `InpMaxSpreadPoints` — maksymalny dopuszczalny spread (sprawdź typowy
     spread US30 u BossaFX i daj 2–3× więcej jako bufor).
6. Włącz globalny tryb **Algo Trading** (przycisk na pasku narzędzi).

## Backtest

1. `Ctrl+R` → Tester strategii.
2. EA: `Ichimoku_US30_H4_BossaFX`, Symbol: US30 z Twojego Market Watch, TF: H4.
3. Model: **Every tick based on real ticks** (zalecane).
4. Zakres: minimum 3 lata danych historycznych.

Szczegółowe ustawienia, opis logiki sygnałów oraz tabela parametrów
znajdują się w [`docs/STRATEGIA.md`](docs/STRATEGIA.md).

## Zastrzeżenie

Strategia ma charakter edukacyjny. Handel CFD na indeksach wiąże się z
wysokim ryzykiem utraty kapitału. Przed uruchomieniem na rachunku
rzeczywistym przetestuj EA przez minimum 4–6 tygodni na **rachunku demo
BossaFX**. Autor i Cursor nie ponoszą odpowiedzialności za straty
finansowe wynikające z użycia tego kodu.
