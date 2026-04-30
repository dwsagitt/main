# Ichimoku US30 H4 — BossaFX (MT5)

Pełna, gotowa do uruchomienia strategia tradingowa oparta o **Ichimoku Kinko Hyo**
dla indeksu **US30** (Dow Jones 30 CFD) na interwale **H4**, dla brokera
**BossaFX** w platformie **MetaTrader 5**, z wbudowanym **autolotem**
(procentowe ryzyko z equity).

## Zawartość repozytorium

- [`MQL5/Experts/Ichimoku_US30_H4_BossaFX.mq5`](MQL5/Experts/Ichimoku_US30_H4_BossaFX.mq5) — Expert Advisor (kompilowalny w MetaEditor 5).
- [`docs/STRATEGIA.md`](docs/STRATEGIA.md) — pełna dokumentacja strategii: warunki wejścia, SL/TP, autolot, filtry, parametry.

## Co potrafi EA (v1.16)

> **Nowość v1.16** — naprawa fundamentu po post-mortem defaults v1.14:
> - `InpEnablePullbackEntry=false` w defaults (była `true` — generowała sieczkę w boku).
> - **Filtr ADX** dla pullbacka (default `InpADXMinForPullback=22`) — pullback tylko w potwierdzonym trendzie, nie w boku.
> - **`InpSlopeMinATRMove=0.15`** — slope KS musi się zmienić o min 15% ATR (nie tylko `>= 0`).
> - **Strong Momentum Exit** zaostrzony: 2 świece pod rząd, tylko na zamknięciu, tylko gdy pozycja na plusie (defaults).
> - Presety zaktualizowane: **Conservative** = pure TK Cross (jak v1.00 logic), **Balanced** = z ADX-pullback, **Aggressive** = wszystko ON.
> - Sekcja 11.D w `docs/STRATEGIA.md`: post-mortem z tabelą porównań i workflowem rekomendowanym.

## Co potrafi EA (v1.15)

> **Nowość v1.15** — bullet-proof guardrail i wyświetlanie wersji:
> - **Komentarz na wykresie**: `[Ichimoku v1.15] TF=H4 OK` po starcie EA. Jeśli go nie widzisz, masz starą `.ex5`.
> - **Baner w Journal** przy starcie z numerem wersji.
> - **Hard-block w `OnTick`** (niezależnie od `OnInit`) — gdy TF ≠ H4 i `InpEnforceH4=true`, EA nigdy nie zawiera transakcji.
> - **`docs/INSTALACJA_KROK_PO_KROKU.md`** — pełna checklist od pobrania do pierwszego backtestu, z testem 5-sekundowym diagnozy „starej `.ex5`" i „złego Period".
>
> **Jeśli widzisz dziwne liczby/sieczkę — najpierw sprawdź `docs/INSTALACJA_KROK_PO_KROKU.md`**.

## Co potrafi EA (v1.14)

> **Nowość v1.14** — guardrail przeciwko najczęstszym błędom uruchomienia:
> - **`InpEnforceH4=true`** (domyślnie): EA NIE handluje na innym TF niż H4 (alert + INIT_FAILED).
> - Walidacja `InpLowerTF < H4` (nie pozwala by LowerTF był równy lub wyższy od H4).
> - Złagodzony preset Aggressive — `InpUseChikouFilter` i `InpStrongTKCrossOnly` zostają **włączone**, agresywność = więcej okazji, nie gorsza jakość.
> - Sekcja 11.C w `docs/STRATEGIA.md`: FAQ trzech najczęstszych błędów (sieczka na H1, agresywny preset, stara `.ex5`).

## Co potrafi EA (v1.13)

> **Nowość v1.13** — narzędzia do optymalizacji:
> - **`OnTester()`** z robust fitness function (PF, Recovery, Sharpe, kara za skrajne winrate / małą liczbę transakcji). Tester w trybie „Custom max".
> - **4 presety .set** w `MQL5/Presets/`: Conservative, Balanced (rekomendowany), Aggressive, Optimize (flagi `Z=1` na 8 parametrach).
> - **`scripts/sync_to_mt5.bat`** — auto-pull z GitHub + kopia EA + presetów + kompilacja przez `metaeditor64.exe`.
> - Sekcja 11.B w `docs/STRATEGIA.md`: workflow walk-forward, co optymalizować, sanity check.

## Co potrafi EA (v1.12)

> **Nowość v1.12** — odpowiedź na opóźnienie Ichimoku H4:
> - **Strong Momentum Exit**: silny counter-bar (>=1.5×ATR z dużym ciałem) zamyka pozycję natychmiast (np. impuls 19.03).
> - **Lower-TF (H1) reverse TK Cross**: drugi handle Ichimoku na H1; szybszy EXIT 4× przed sygnałem H4.
> - **Lower-TF Early Entry** (opt-in): wczesne wejście, gdy H4 potwierdza trend, a H1 daje TK Cross.
>
> **v1.11**: tryb **diagnostyczny** (`InpVerboseDiagnostics=true`) — Journal pokazuje powód odrzucenia sygnału + opcjonalne strzałki na wykresie.
>
> Patrz `docs/STRATEGIA.md` rozdziały 11.A i 11.


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
