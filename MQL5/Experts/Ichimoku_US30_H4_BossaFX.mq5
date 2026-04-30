//+------------------------------------------------------------------+
//|                              Ichimoku_US30_H4_BossaFX.mq5        |
//|                              Strategia Ichimoku Kinko Hyo        |
//|                              Instrument: US30 (DJIA CFD)         |
//|                              Timeframe : H4                      |
//|                              Broker    : BossaFX (MT5)           |
//|                              Autor     : Cursor Cloud Agent      |
//+------------------------------------------------------------------+
#property copyright "Cursor Cloud Agent - 2026"
#property link      "https://bossafx.pl"
#property version   "1.10"
#property strict
#property description "Pełna strategia Ichimoku dla US30 H4 (BossaFX) z autolotem"

#include <Trade/Trade.mqh>
#include <Trade/SymbolInfo.mqh>
#include <Trade/PositionInfo.mqh>
#include <Trade/AccountInfo.mqh>

CTrade          trade;
CSymbolInfo     sym;
CPositionInfo   pos;
CAccountInfo    acc;

//==================================================================
// PARAMETRY WEJŚCIOWE
//==================================================================
input group "=== Symbol i Magic ==="
input string  InpSymbol            = "";              // Symbol (puste = bieżący wykres). BossaFX: US30, US30.cash, DJI30, .US30 itp.
input long    InpMagic             = 30040026;        // Magic number EA
input string  InpComment           = "Ichimoku_H4";   // Komentarz transakcji

input group "=== Parametry Ichimoku (klasyczne 9/26/52) ==="
input int     InpTenkan            = 9;               // Tenkan-sen
input int     InpKijun             = 26;              // Kijun-sen
input int     InpSenkouB           = 52;              // Senkou Span B
input int     InpChikouShift       = 26;              // Przesunięcie Chikou (i Kumo)

input group "=== Tryby wejścia ==="
input bool    InpEnableTKCrossEntry = true;           // [Tryb 1] Wejście na świeżym TK Cross (breakout)
input bool    InpEnablePullbackEntry = true;          // [Tryb 2] Wejście na pullbacku do TS/KS w trendzie
input bool    InpPullbackOnTenkan  = true;            //   Pullback do Tenkan-sen (krótkie korekty)
input bool    InpPullbackOnKijun   = true;            //   Pullback do Kijun-sen (głębsze korekty)
input int     InpPullbackLookback  = 6;               //   Ile świec wstecz szukamy dotknięcia TS/KS
input double  InpPullbackTouchTolATR = 0.25;          //   Tolerancja dotknięcia (× ATR), 0.25 = blisko TS/KS

input group "=== Filtry trendu ==="
input bool    InpUseChikouFilter   = true;            // Wymagaj potwierdzenia Chikou Span
input bool    InpUseFutureKumoFilter = true;          // Wymagaj zgodności przyszłej chmury (Senkou A vs B)
input bool    InpUseKijunFilter    = true;            // Cena musi być po właściwej stronie Kijun-sen
input bool    InpRequireTKCross    = true;            // [TK Cross] Wymagaj świeżego przecięcia Tenkan/Kijun
input int     InpTKCrossLookback   = 5;               // [TK Cross] Ile świec wstecz akceptujemy świeży TK Cross
input bool    InpStrongTKCrossOnly = true;            // [TK Cross] Tylko mocne TK Cross (przecięcie ponad/pod chmurą)
input bool    InpUseSlopeFilter    = true;            // Wymagaj zgodnego nachylenia Tenkan/Kijun (KS/TS nie spadają w longu)
input int     InpSlopeLookback     = 3;               // O ile świec wstecz porównujemy slope TS/KS
input bool    InpRequireKijunSlope = true;            // Wymagaj nachylenia Kijun (kluczowe dla trendu)
input bool    InpRequireTenkanSlope = false;          // Wymagaj nachylenia Tenkan (rygorystyczne)

input group "=== Filtry rynkowe ==="
input bool    InpUseSpreadFilter   = true;            // Filtr maksymalnego spreadu
input int     InpMaxSpreadPoints   = 80;              // Max spread w punktach (US30 ~ 1.5-3 pkt cenowych = ~150-300 pt)
input bool    InpUseSessionFilter  = false;           // Handluj tylko w wybranych godzinach
input int     InpSessionStartHour  = 8;               // Start sesji (godzina serwera)
input int     InpSessionEndHour    = 22;              // Koniec sesji (godzina serwera)
input bool    InpAvoidFridayClose  = true;            // Nie otwieraj nowych w piątek po 20:00
input int     InpFridayCloseHour   = 20;              // Godzina blokady wejść w piątek

input group "=== Zarządzanie ryzykiem (AUTOLOT) ==="
input bool    InpUseAutoLot        = true;            // Włącz autolot (procent salda na ryzyko)
input double  InpRiskPercent       = 1.0;             // Ryzyko na transakcję [%] z equity
input double  InpFixedLot          = 0.10;            // Stały lot gdy autolot wyłączony
input double  InpMaxLot            = 5.0;             // Górne ograniczenie wielkości pozycji
input double  InpMinLot            = 0.0;             // Dolne (0 = z brokera)
input double  InpMaxRiskCapEUR     = 0.0;             // Twardy cap ryzyka w walucie konta (0 = brak)

input group "=== Stop Loss / Take Profit ==="
input ENUM_TIMEFRAMES InpATRTimeframe = PERIOD_H4;    // TF dla ATR
input int     InpATRPeriod         = 14;              // Okres ATR
input double  InpATRMultSL         = 2.0;             // Mnożnik ATR dla SL
input double  InpRR                = 2.0;             // Risk:Reward dla TP
input bool    InpUseKijunSL        = true;            // SL także za Kijun-sen (wybiera dalszy z (Kijun, ATR))
input bool    InpUseCloudSL        = true;            // SL także za przeciwnym brzegiem Kumo (wybiera dalszy)
input int     InpSLBufferPoints    = 50;              // Bufor SL w punktach (poza poziomem)
input int     InpMinStopPoints     = 200;             // Minimalna odległość SL od ceny (US30: 200 pkt = ~2 pkt cenowe)

input group "=== Trailing i wyjścia ==="
input bool    InpUseKijunTrailing  = true;            // Trailing po Kijun-sen (dalszy)
input int     InpKijunTrailBuffer  = 100;             // Bufor trailingu (punkty) za Kijun
input bool    InpUseTenkanTrailing = false;           // Trailing po Tenkan-sen (ciaśniejszy, w mocnym trendzie)
input int     InpTenkanTrailBuffer = 50;              // Bufor trailingu (punkty) za Tenkan
input bool    InpTenkanTrailAfterPartial = true;      // Włącz Tenkan-trailing dopiero po częściowym TP
input bool    InpExitOnTKCross     = true;            // Zamknij gdy odwrotny TK Cross
input bool    InpExitOnCloudBreak  = true;            // Zamknij gdy cena wraca do/za chmurę
input bool    InpUseBreakEven      = true;            // Przesuń SL na BE po osiągnięciu R
input double  InpBreakEvenAtR      = 1.0;             // Po ilu R uruchomić BE (1.0 = po pierwszym R)
input int     InpBreakEvenOffsetPt = 30;              // Offset BE w punktach (lock zysku)
input bool    InpUsePartialTP      = true;            // Częściowy TP (zamknij część na 1R)
input double  InpPartialTPAtR      = 1.0;             // Przy ilu R wykonać częściowy TP
input double  InpPartialTPPercent  = 50.0;            // % wolumenu zamykanego przy częściowym TP

input group "=== Ograniczenia handlu ==="
input int     InpMaxPositions      = 1;               // Max otwartych pozycji EA na symbolu
input bool    InpOnePositionPerBar = true;            // Tylko 1 sygnał na słupek (dotyczy TK-Cross; pullbacki re-enter dozwolone)
input bool    InpAllowHedge        = false;           // Zezwól na pozycje przeciwne (hedge)
input int     InpSlippagePoints    = 30;              // Maks. poślizg [pkt]
input int     InpCooldownBarsAfterLoss = 2;           // Cooldown w słupkach po stratnej transakcji (0 = brak)

//==================================================================
// ZMIENNE GLOBALNE
//==================================================================
int      ichi_handle = INVALID_HANDLE;
int      atr_handle  = INVALID_HANDLE;
string   gSymbol     = "";
datetime gLastBarTime = 0;
datetime gLastTKCrossBar = 0;        // ostatni słupek z wejściem na TK-Cross (one-per-bar)
datetime gLastClosedTradeBar = 0;    // słupek na którym zamknięta została ostatnia pozycja EA
double   gLastClosedTradeProfit = 0; // wynik (waluta) ostatnio zamkniętej pozycji
ulong    gPartialDoneTickets[];      // tickety, dla których wykonano już częściowy TP

#define IDX_TENKAN  0
#define IDX_KIJUN   1
#define IDX_SENKOUA 2
#define IDX_SENKOUB 3
#define IDX_CHIKOU  4

//+------------------------------------------------------------------+
//| Inicjalizacja                                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   gSymbol = (StringLen(InpSymbol) > 0) ? InpSymbol : _Symbol;

   if(!sym.Name(gSymbol))
   {
      PrintFormat("Nie można ustawić symbolu %s", gSymbol);
      return(INIT_FAILED);
   }
   sym.Refresh();
   sym.RefreshRates();

   if(!SymbolSelect(gSymbol, true))
   {
      PrintFormat("Nie można wybrać symbolu %s w Market Watch (BossaFX może używać innej nazwy: US30, US30.cash, DJI30, .US30)", gSymbol);
      return(INIT_FAILED);
   }

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints((ulong)InpSlippagePoints);
   trade.SetTypeFillingBySymbol(gSymbol);
   trade.SetMarginMode();
   trade.LogLevel(LOG_LEVEL_ERRORS);

   ichi_handle = iIchimoku(gSymbol, PERIOD_H4, InpTenkan, InpKijun, InpSenkouB);
   if(ichi_handle == INVALID_HANDLE)
   {
      PrintFormat("Błąd tworzenia Ichimoku handle dla %s", gSymbol);
      return(INIT_FAILED);
   }

   atr_handle = iATR(gSymbol, InpATRTimeframe, InpATRPeriod);
   if(atr_handle == INVALID_HANDLE)
   {
      PrintFormat("Błąd tworzenia ATR handle dla %s", gSymbol);
      return(INIT_FAILED);
   }

   datetime t[];
   if(CopyTime(gSymbol, PERIOD_H4, 0, 1, t) > 0)
      gLastBarTime = t[0];

   PrintFormat("Ichimoku US30 H4 (BossaFX) zainicjalizowany. Symbol=%s, Magic=%I64d, AutoLot=%s, Ryzyko=%.2f%%",
               gSymbol, InpMagic, (InpUseAutoLot ? "TAK" : "NIE"), InpRiskPercent);

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Deinicjalizacja                                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(ichi_handle != INVALID_HANDLE) IndicatorRelease(ichi_handle);
   if(atr_handle  != INVALID_HANDLE) IndicatorRelease(atr_handle);
}

//+------------------------------------------------------------------+
//| Pomocnicze - czy nowy bar H4                                     |
//+------------------------------------------------------------------+
bool IsNewBarH4()
{
   datetime t[];
   if(CopyTime(gSymbol, PERIOD_H4, 0, 1, t) <= 0) return false;
   if(t[0] != gLastBarTime)
   {
      gLastBarTime = t[0];
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Czas serwera w sesji?                                            |
//+------------------------------------------------------------------+
bool InSession()
{
   if(!InpUseSessionFilter) return true;
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if(InpSessionStartHour <= InpSessionEndHour)
      return (dt.hour >= InpSessionStartHour && dt.hour < InpSessionEndHour);
   return (dt.hour >= InpSessionStartHour || dt.hour < InpSessionEndHour);
}

//+------------------------------------------------------------------+
//| Filtr piątkowy                                                   |
//+------------------------------------------------------------------+
bool FridayBlock()
{
   if(!InpAvoidFridayClose) return false;
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   return (dt.day_of_week == 5 && dt.hour >= InpFridayCloseHour);
}

//+------------------------------------------------------------------+
//| Filtr spreadu                                                    |
//+------------------------------------------------------------------+
bool SpreadOK()
{
   if(!InpUseSpreadFilter) return true;
   sym.RefreshRates();
   long sp = (long)SymbolInfoInteger(gSymbol, SYMBOL_SPREAD);
   if(sp > InpMaxSpreadPoints)
   {
      PrintFormat("Pomijam sygnał: spread=%d > max=%d", (int)sp, InpMaxSpreadPoints);
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Liczba otwartych pozycji EA                                      |
//+------------------------------------------------------------------+
int CountPositions(int direction = -1) // -1 dowolne, 0 buy, 1 sell
{
   int total = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!pos.SelectByIndex(i)) continue;
      if(pos.Symbol() != gSymbol) continue;
      if(pos.Magic()  != InpMagic) continue;
      if(direction == 0 && pos.PositionType() != POSITION_TYPE_BUY)  continue;
      if(direction == 1 && pos.PositionType() != POSITION_TYPE_SELL) continue;
      total++;
   }
   return total;
}

//+------------------------------------------------------------------+
//| Pobierz dane Ichimoku                                            |
//+------------------------------------------------------------------+
bool GetIchimoku(int shift, double &tenkan, double &kijun, double &senkouA, double &senkouB, double &chikou)
{
   double buf[];
   ArraySetAsSeries(buf, true);

   if(CopyBuffer(ichi_handle, IDX_TENKAN,  shift, 1, buf) <= 0) return false;
   tenkan = buf[0];
   if(CopyBuffer(ichi_handle, IDX_KIJUN,   shift, 1, buf) <= 0) return false;
   kijun = buf[0];
   if(CopyBuffer(ichi_handle, IDX_SENKOUA, shift, 1, buf) <= 0) return false;
   senkouA = buf[0];
   if(CopyBuffer(ichi_handle, IDX_SENKOUB, shift, 1, buf) <= 0) return false;
   senkouB = buf[0];
   if(CopyBuffer(ichi_handle, IDX_CHIKOU,  shift, 1, buf) <= 0) return false;
   chikou = buf[0];

   return true;
}

//+------------------------------------------------------------------+
//| Czy Cena zamknięcia powyżej/poniżej chmury (Kumo)                |
//+------------------------------------------------------------------+
int PriceVsCloud(double close, double senkouA, double senkouB)
{
   double top = MathMax(senkouA, senkouB);
   double bot = MathMin(senkouA, senkouB);
   if(close > top) return 1;
   if(close < bot) return -1;
   return 0;
}

//+------------------------------------------------------------------+
//| Wykrycie świeżego TK Cross (Tenkan x Kijun)                      |
//| zwraca: 1 = byczy, -1 = niedźwiedzi, 0 = brak                    |
//+------------------------------------------------------------------+
int DetectTKCross(int lookback)
{
   double tBuf[], kBuf[];
   int need = lookback + 2;
   ArraySetAsSeries(tBuf, true);
   ArraySetAsSeries(kBuf, true);
   if(CopyBuffer(ichi_handle, IDX_TENKAN, 1, need, tBuf) < need) return 0;
   if(CopyBuffer(ichi_handle, IDX_KIJUN,  1, need, kBuf) < need) return 0;

   for(int i = 0; i < lookback; i++)
   {
      double tA = tBuf[i],   kA = kBuf[i];
      double tB = tBuf[i+1], kB = kBuf[i+1];
      if(tA > kA && tB <= kB) return 1;
      if(tA < kA && tB >= kB) return -1;
   }
   return 0;
}

//+------------------------------------------------------------------+
//| Pobierz cenę close N słupków wstecz                              |
//+------------------------------------------------------------------+
double CloseAt(int shift)
{
   double c[];
   ArraySetAsSeries(c, true);
   if(CopyClose(gSymbol, PERIOD_H4, shift, 1, c) <= 0) return 0.0;
   return c[0];
}

//+------------------------------------------------------------------+
//| ATR                                                              |
//+------------------------------------------------------------------+
double GetATR(int shift = 1)
{
   double a[];
   ArraySetAsSeries(a, true);
   if(CopyBuffer(atr_handle, 0, shift, 1, a) <= 0) return 0.0;
   return a[0];
}

//+------------------------------------------------------------------+
//| Normalizacja ceny i wolumenu                                     |
//+------------------------------------------------------------------+
double NPrice(double p)
{
   int digits = (int)SymbolInfoInteger(gSymbol, SYMBOL_DIGITS);
   return NormalizeDouble(p, digits);
}

double NormalizeVolume(double vol)
{
   double minV  = SymbolInfoDouble(gSymbol, SYMBOL_VOLUME_MIN);
   double maxV  = SymbolInfoDouble(gSymbol, SYMBOL_VOLUME_MAX);
   double stepV = SymbolInfoDouble(gSymbol, SYMBOL_VOLUME_STEP);
   if(stepV <= 0) stepV = 0.01;

   if(InpMinLot > 0 && minV < InpMinLot) minV = InpMinLot;

   double v = MathFloor(vol / stepV) * stepV;
   if(v < minV) v = minV;
   if(v > maxV) v = maxV;
   if(InpMaxLot > 0 && v > InpMaxLot) v = InpMaxLot;
   return NormalizeDouble(v, 2);
}

//+------------------------------------------------------------------+
//| Wartość 1 punktu na 1 lot (waluta konta)                         |
//+------------------------------------------------------------------+
double TickValuePerPoint()
{
   double tv = SymbolInfoDouble(gSymbol, SYMBOL_TRADE_TICK_VALUE);
   double ts = SymbolInfoDouble(gSymbol, SYMBOL_TRADE_TICK_SIZE);
   double pt = SymbolInfoDouble(gSymbol, SYMBOL_POINT);
   if(ts <= 0 || pt <= 0) return tv; // fallback
   return tv * (pt / ts);
}

//+------------------------------------------------------------------+
//| AUTOLOT - oblicz wielkość pozycji                                |
//+------------------------------------------------------------------+
double CalculateLot(double slDistancePoints)
{
   if(!InpUseAutoLot)
      return NormalizeVolume(InpFixedLot);

   if(slDistancePoints <= 0) return NormalizeVolume(InpFixedLot);

   double equity = acc.Equity();
   double riskMoney = equity * InpRiskPercent / 100.0;
   if(InpMaxRiskCapEUR > 0 && riskMoney > InpMaxRiskCapEUR) riskMoney = InpMaxRiskCapEUR;

   double valPerPoint = TickValuePerPoint();
   if(valPerPoint <= 0) return NormalizeVolume(InpFixedLot);

   double lossPerLot = slDistancePoints * valPerPoint; // strata przy 1 locie i SL=slDistancePoints
   if(lossPerLot <= 0) return NormalizeVolume(InpFixedLot);

   double lots = riskMoney / lossPerLot;
   double normLots = NormalizeVolume(lots);

   PrintFormat("AutoLot: equity=%.2f, ryzyko=%.2f%% (%.2f), SLpts=%.0f, val/pt=%.4f -> lot=%.2f",
               equity, InpRiskPercent, riskMoney, slDistancePoints, valPerPoint, normLots);

   return normLots;
}

//+------------------------------------------------------------------+
//| Slope Tenkan / Kijun (1=rośnie, -1=spada, 0=płasko/n-a)          |
//+------------------------------------------------------------------+
int LineSlope(int bufferIdx, int lookback)
{
   double a[];
   ArraySetAsSeries(a, true);
   int need = lookback + 2;
   if(CopyBuffer(ichi_handle, bufferIdx, 1, need, a) < need) return 0;
   double now  = a[0];
   double prev = a[lookback];
   if(now > prev) return 1;
   if(now < prev) return -1;
   return 0;
}

//+------------------------------------------------------------------+
//| Czy w ostatnich N świecach był pullback (low <= TS+tol lub HIGH) |
//| i ostatnia świeca zamknęła się ponad/pod linią (potwierdzenie)   |
//| dir: 1=BUY (long), -1=SELL                                       |
//| line: 'T' lub 'K'                                                |
//+------------------------------------------------------------------+
bool DetectPullbackTouch(int dir, char line, int lookback, double tol)
{
   int bufIdx = (line == 'T') ? IDX_TENKAN : IDX_KIJUN;

   double lineArr[];
   ArraySetAsSeries(lineArr, true);
   int need = lookback + 2;
   if(CopyBuffer(ichi_handle, bufIdx, 1, need, lineArr) < need) return false;

   double highArr[], lowArr[], closeArr[];
   ArraySetAsSeries(highArr,  true);
   ArraySetAsSeries(lowArr,   true);
   ArraySetAsSeries(closeArr, true);
   if(CopyHigh (gSymbol, PERIOD_H4, 1, need, highArr)  < need) return false;
   if(CopyLow  (gSymbol, PERIOD_H4, 1, need, lowArr)   < need) return false;
   if(CopyClose(gSymbol, PERIOD_H4, 1, need, closeArr) < need) return false;

   double atr = GetATR(1);
   if(atr <= 0) return false;
   double tolPrice = tol * atr;

   bool touched = false;
   for(int i = 0; i < lookback; i++)
   {
      double L = lineArr[i];
      if(dir == 1)
      {
         if(lowArr[i] <= L + tolPrice) { touched = true; break; }
      }
      else
      {
         if(highArr[i] >= L - tolPrice) { touched = true; break; }
      }
   }
   if(!touched) return false;

   double L1   = lineArr[0];
   double C1   = closeArr[0];
   double C2   = closeArr[1];

   if(dir == 1)
      return (C1 > L1 && C1 > C2);
   else
      return (C1 < L1 && C1 < C2);
}

//+------------------------------------------------------------------+
//| Sygnał wejścia: zwraca 1=BUY, -1=SELL, 0=brak                    |
//| Wypełnia signalKind:                                             |
//|   "TKCROSS" - przebicie TK Cross,                                |
//|   "PB_TENKAN" / "PB_KIJUN" - pullback bounce                     |
//+------------------------------------------------------------------+
int CheckEntrySignal(string &signalKind)
{
   signalKind = "";

   double t1, k1, sa1, sb1, ch1;
   if(!GetIchimoku(1, t1, k1, sa1, sb1, ch1)) return 0;

   double futA = (t1 + k1) / 2.0;
   double highArr[], lowArr[];
   ArraySetAsSeries(highArr, true);
   ArraySetAsSeries(lowArr,  true);
   if(CopyHigh(gSymbol, PERIOD_H4, 1, InpSenkouB, highArr) < InpSenkouB) return 0;
   if(CopyLow (gSymbol, PERIOD_H4, 1, InpSenkouB, lowArr)  < InpSenkouB) return 0;
   double hh = highArr[ArrayMaximum(highArr, 0, InpSenkouB)];
   double ll = lowArr [ArrayMinimum(lowArr,  0, InpSenkouB)];
   double futB = (hh + ll) / 2.0;

   double close1 = CloseAt(1);
   double close26 = CloseAt(InpChikouShift + 1);
   if(close1 == 0 || close26 == 0) return 0;

   int priceVsCloud = PriceVsCloud(close1, sa1, sb1);

   bool kijunBull = !InpUseKijunFilter || (close1 > k1);
   bool kijunBear = !InpUseKijunFilter || (close1 < k1);

   bool chikouBull = !InpUseChikouFilter || (close1 > close26);
   bool chikouBear = !InpUseChikouFilter || (close1 < close26);

   bool futureBull = !InpUseFutureKumoFilter || (futA > futB);
   bool futureBear = !InpUseFutureKumoFilter || (futA < futB);

   bool tAboveCloud = (MathMin(t1,k1) > MathMax(sa1, sb1));
   bool tBelowCloud = (MathMax(t1,k1) < MathMin(sa1, sb1));

   int slopeT = InpUseSlopeFilter ? LineSlope(IDX_TENKAN, InpSlopeLookback) : 0;
   int slopeK = InpUseSlopeFilter ? LineSlope(IDX_KIJUN,  InpSlopeLookback) : 0;
   bool slopeBull = !InpUseSlopeFilter
                    || ((!InpRequireKijunSlope || slopeK >= 0) &&
                        (!InpRequireTenkanSlope || slopeT >= 0) &&
                        (slopeK >= 0 || slopeT >= 0));
   bool slopeBear = !InpUseSlopeFilter
                    || ((!InpRequireKijunSlope || slopeK <= 0) &&
                        (!InpRequireTenkanSlope || slopeT <= 0) &&
                        (slopeK <= 0 || slopeT <= 0));

   bool baseBull = (priceVsCloud == 1) && kijunBull && chikouBull && futureBull && slopeBull;
   bool baseBear = (priceVsCloud == -1) && kijunBear && chikouBear && futureBear && slopeBear;

   // ------------------------------------------------------------------
   // [Tryb 1] TK CROSS (breakout)
   // ------------------------------------------------------------------
   if(InpEnableTKCrossEntry)
   {
      int tkCross = InpRequireTKCross ? DetectTKCross(InpTKCrossLookback) : (t1 > k1 ? 1 : (t1 < k1 ? -1 : 0));
      bool strongBull = !InpStrongTKCrossOnly || tAboveCloud;
      bool strongBear = !InpStrongTKCrossOnly || tBelowCloud;

      if(baseBull && tkCross == 1 && strongBull) { signalKind = "TKCROSS"; return 1; }
      if(baseBear && tkCross == -1 && strongBear) { signalKind = "TKCROSS"; return -1; }
   }

   // ------------------------------------------------------------------
   // [Tryb 2] PULLBACK BOUNCE (kontynuacja trendu na dotknięciu TS/KS)
   // Wymaga aktualnie potwierdzonego trendu (TK po właściwej stronie chmury,
   // TS i KS rosną/spadają, cena nad/pod chmurą) i świecy potwierdzającej.
   // ------------------------------------------------------------------
   if(InpEnablePullbackEntry)
   {
      bool trendUp   = baseBull && (t1 > k1) && tAboveCloud;
      bool trendDown = baseBear && (t1 < k1) && tBelowCloud;

      if(trendUp)
      {
         if(InpPullbackOnTenkan && DetectPullbackTouch(1, 'T', InpPullbackLookback, InpPullbackTouchTolATR))
            { signalKind = "PB_TENKAN"; return 1; }
         if(InpPullbackOnKijun  && DetectPullbackTouch(1, 'K', InpPullbackLookback, InpPullbackTouchTolATR))
            { signalKind = "PB_KIJUN";  return 1; }
      }
      if(trendDown)
      {
         if(InpPullbackOnTenkan && DetectPullbackTouch(-1, 'T', InpPullbackLookback, InpPullbackTouchTolATR))
            { signalKind = "PB_TENKAN"; return -1; }
         if(InpPullbackOnKijun  && DetectPullbackTouch(-1, 'K', InpPullbackLookback, InpPullbackTouchTolATR))
            { signalKind = "PB_KIJUN";  return -1; }
      }
   }

   return 0;
}

//+------------------------------------------------------------------+
//| Oblicz SL/TP                                                     |
//+------------------------------------------------------------------+
bool ComputeSLTP(int dir, double price, double &sl, double &tp, double &slDistPts)
{
   double point = SymbolInfoDouble(gSymbol, SYMBOL_POINT);
   if(point <= 0) return false;

   double atr = GetATR(1);
   if(atr <= 0) return false;

   double t1, k1, sa1, sb1, ch1;
   if(!GetIchimoku(1, t1, k1, sa1, sb1, ch1)) return false;

   double cloudTop = MathMax(sa1, sb1);
   double cloudBot = MathMin(sa1, sb1);

   double bufferPrice = InpSLBufferPoints * point;
   double minStop     = InpMinStopPoints   * point;

   long stopsLevel = SymbolInfoInteger(gSymbol, SYMBOL_TRADE_STOPS_LEVEL);
   double brokerMin = stopsLevel * point;
   if(brokerMin > minStop) minStop = brokerMin;

   double slCandidate = 0;

   if(dir == 1) // BUY
   {
      double slATR   = price - InpATRMultSL * atr - bufferPrice;
      double slKijun = InpUseKijunSL ? (k1 - bufferPrice) : slATR;
      double slCloud = InpUseCloudSL ? (cloudBot - bufferPrice) : slATR;
      slCandidate = MathMin(slATR, MathMin(slKijun, slCloud)); // najdalszy = najmniejszy dla BUY

      if(price - slCandidate < minStop) slCandidate = price - minStop;

      slDistPts = (price - slCandidate) / point;
      tp = price + (price - slCandidate) * InpRR;
   }
   else // SELL
   {
      double slATR   = price + InpATRMultSL * atr + bufferPrice;
      double slKijun = InpUseKijunSL ? (k1 + bufferPrice) : slATR;
      double slCloud = InpUseCloudSL ? (cloudTop + bufferPrice) : slATR;
      slCandidate = MathMax(slATR, MathMax(slKijun, slCloud)); // najdalszy = największy dla SELL

      if(slCandidate - price < minStop) slCandidate = price + minStop;

      slDistPts = (slCandidate - price) / point;
      tp = price - (slCandidate - price) * InpRR;
   }

   sl = NPrice(slCandidate);
   tp = NPrice(tp);
   return (slDistPts > 0);
}

//+------------------------------------------------------------------+
//| Tracking ticketów z wykonanym częściowym TP                      |
//+------------------------------------------------------------------+
bool IsPartialDone(ulong ticket)
{
   for(int i = 0; i < ArraySize(gPartialDoneTickets); i++)
      if(gPartialDoneTickets[i] == ticket) return true;
   return false;
}

void MarkPartialDone(ulong ticket)
{
   if(IsPartialDone(ticket)) return;
   int n = ArraySize(gPartialDoneTickets);
   ArrayResize(gPartialDoneTickets, n + 1);
   gPartialDoneTickets[n] = ticket;
}

//+------------------------------------------------------------------+
//| Otwarcie pozycji                                                 |
//+------------------------------------------------------------------+
void TryOpen(int dir, string kind)
{
   if(!SpreadOK()) return;
   sym.RefreshRates();

   double price = (dir == 1) ? sym.Ask() : sym.Bid();
   double sl=0, tp=0, slDistPts=0;
   if(!ComputeSLTP(dir, price, sl, tp, slDistPts))
   {
      Print("Nie można policzyć SL/TP - pomijam wejście");
      return;
   }

   double lots = CalculateLot(slDistPts);
   if(lots <= 0)
   {
      Print("Lot <= 0 - pomijam wejście");
      return;
   }

   string cmt = InpComment + "_" + kind;

   bool ok = false;
   if(dir == 1)
      ok = trade.Buy(lots, gSymbol, price, sl, tp, cmt);
   else
      ok = trade.Sell(lots, gSymbol, price, sl, tp, cmt);

   if(ok)
   {
      if(kind == "TKCROSS") gLastTKCrossBar = gLastBarTime;
      PrintFormat("OTWARTO %s [%s]: lot=%.2f, price=%.2f, SL=%.2f (%.0f pkt), TP=%.2f, RR=%.2f",
                  (dir==1?"BUY":"SELL"), kind, lots, price, sl, slDistPts, tp, InpRR);
   }
   else
   {
      PrintFormat("Błąd otwarcia (%d): %s", trade.ResultRetcode(), trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| Zarządzanie pozycjami: BE, trailing, exit                        |
//+------------------------------------------------------------------+
void ManagePositions()
{
   double t1, k1, sa1, sb1, ch1;
   if(!GetIchimoku(1, t1, k1, sa1, sb1, ch1)) return;

   double point = SymbolInfoDouble(gSymbol, SYMBOL_POINT);
   sym.RefreshRates();
   double bid = sym.Bid();
   double ask = sym.Ask();

   double cloudTop = MathMax(sa1, sb1);
   double cloudBot = MathMin(sa1, sb1);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!pos.SelectByIndex(i)) continue;
      if(pos.Symbol() != gSymbol) continue;
      if(pos.Magic()  != InpMagic) continue;

      ulong  ticket = pos.Ticket();
      bool   isBuy  = (pos.PositionType() == POSITION_TYPE_BUY);
      double open   = pos.PriceOpen();
      double curSL  = pos.StopLoss();
      double curTP  = pos.TakeProfit();
      double price  = isBuy ? bid : ask;

      // === Wyjście: odwrotny TK Cross ===
      if(InpExitOnTKCross)
      {
         int cross = DetectTKCross(2);
         if((isBuy && cross == -1) || (!isBuy && cross == 1))
         {
            trade.PositionClose(ticket);
            PrintFormat("Zamknięto #%I64u: odwrotny TK Cross", ticket);
            continue;
         }
      }

      // === Wyjście: powrót do/za chmurę ===
      if(InpExitOnCloudBreak)
      {
         double close1 = CloseAt(1);
         if((isBuy && close1 < cloudBot) || (!isBuy && close1 > cloudTop))
         {
            trade.PositionClose(ticket);
            PrintFormat("Zamknięto #%I64u: cena za chmurą", ticket);
            continue;
         }
      }

      double initRisk = (curSL > 0) ? MathAbs(open - curSL) : 0;
      double moved    = isBuy ? (price - open) : (open - price);

      // === Częściowy TP po 1R ===
      if(InpUsePartialTP && initRisk > 0 && !IsPartialDone(ticket))
      {
         if(moved >= InpPartialTPAtR * initRisk)
         {
            double posVol = pos.Volume();
            double step   = SymbolInfoDouble(gSymbol, SYMBOL_VOLUME_STEP);
            double minV   = SymbolInfoDouble(gSymbol, SYMBOL_VOLUME_MIN);
            if(step <= 0) step = 0.01;
            double closeVol = posVol * (InpPartialTPPercent / 100.0);
            closeVol = MathFloor(closeVol / step) * step;
            closeVol = NormalizeDouble(closeVol, 2);

            double remain = NormalizeDouble(posVol - closeVol, 2);
            if(closeVol >= minV && remain >= minV)
            {
               if(trade.PositionClosePartial(ticket, closeVol))
               {
                  MarkPartialDone(ticket);
                  PrintFormat("Partial TP #%I64u: zamknieto %.2f z %.2f (po %.2fR)",
                              ticket, closeVol, posVol, InpPartialTPAtR);
               }
            }
            else
            {
               MarkPartialDone(ticket);
            }
         }
      }

      // === Break-Even ===
      if(InpUseBreakEven && initRisk > 0)
      {
         if(moved >= InpBreakEvenAtR * initRisk)
         {
            double beSL = isBuy ? (open + InpBreakEvenOffsetPt * point) : (open - InpBreakEvenOffsetPt * point);
            bool needUpdate = isBuy ? (curSL < beSL || curSL == 0) : (curSL > beSL || curSL == 0);
            if(needUpdate)
            {
               if(trade.PositionModify(ticket, NPrice(beSL), curTP))
                  PrintFormat("BE #%I64u: SL -> %.2f", ticket, beSL);
            }
         }
      }

      // === Trailing po Tenkan-sen (ciaśniejszy) ===
      bool tenkanTrailActive = InpUseTenkanTrailing &&
                               (!InpTenkanTrailAfterPartial || IsPartialDone(ticket));
      if(tenkanTrailActive)
      {
         double newSL = isBuy
                        ? (t1 - InpTenkanTrailBuffer * point)
                        : (t1 + InpTenkanTrailBuffer * point);

         long   stopsLevel = SymbolInfoInteger(gSymbol, SYMBOL_TRADE_STOPS_LEVEL);
         double minStop    = stopsLevel * point;

         if(isBuy && newSL > curSL && newSL < price && (price - newSL) >= minStop)
         {
            if(trade.PositionModify(ticket, NPrice(newSL), curTP))
               PrintFormat("Trailing #%I64u BUY (Tenkan): SL -> %.2f", ticket, newSL);
         }
         else if(!isBuy && (curSL == 0 || newSL < curSL) && newSL > price && (newSL - price) >= minStop)
         {
            if(trade.PositionModify(ticket, NPrice(newSL), curTP))
               PrintFormat("Trailing #%I64u SELL (Tenkan): SL -> %.2f", ticket, newSL);
         }
      }

      // === Trailing po Kijun-sen ===
      if(InpUseKijunTrailing)
      {
         double newSL = isBuy
                        ? (k1 - InpKijunTrailBuffer * point)
                        : (k1 + InpKijunTrailBuffer * point);

         long   stopsLevel = SymbolInfoInteger(gSymbol, SYMBOL_TRADE_STOPS_LEVEL);
         double minStop    = stopsLevel * point;
         if(isBuy  && (price - newSL) < minStop) continue;
         if(!isBuy && (newSL - price) < minStop) continue;

         if(isBuy && newSL > curSL && newSL < price)
         {
            if(trade.PositionModify(ticket, NPrice(newSL), curTP))
               PrintFormat("Trailing #%I64u BUY (Kijun): SL -> %.2f", ticket, newSL);
         }
         else if(!isBuy && (curSL == 0 || newSL < curSL) && newSL > price)
         {
            if(trade.PositionModify(ticket, NPrice(newSL), curTP))
               PrintFormat("Trailing #%I64u SELL (Kijun): SL -> %.2f", ticket, newSL);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Ile świec H4 mineło od podanego czasu (do TimeCurrent)           |
//+------------------------------------------------------------------+
int BarsSince(datetime t)
{
   if(t == 0) return 100000;
   datetime arr[];
   if(CopyTime(gSymbol, PERIOD_H4, t, TimeCurrent(), arr) <= 0) return 100000;
   return ArraySize(arr) - 1;
}

//+------------------------------------------------------------------+
//| Czy aktywny cooldown po stracie                                  |
//+------------------------------------------------------------------+
bool InCooldownAfterLoss()
{
   if(InpCooldownBarsAfterLoss <= 0) return false;
   if(gLastClosedTradeBar == 0) return false;
   if(gLastClosedTradeProfit >= 0) return false;
   int bars = BarsSince(gLastClosedTradeBar);
   if(bars < InpCooldownBarsAfterLoss)
   {
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| OnTick                                                           |
//+------------------------------------------------------------------+
void OnTick()
{
   if(!sym.RefreshRates()) return;

   ManagePositions();

   if(!IsNewBarH4()) return;

   if(!InSession())   return;
   if(FridayBlock())  return;
   if(InCooldownAfterLoss()) return;

   int totalPos = CountPositions();
   if(totalPos >= InpMaxPositions && !InpAllowHedge) return;

   string kind = "";
   int signal = CheckEntrySignal(kind);
   if(signal == 0) return;

   // One-per-bar dotyczy tylko trybu TK Cross (pullbacki mogą wystąpić tuż
   // po zamknięciu poprzedniej pozycji na tym samym słupku)
   if(InpOnePositionPerBar && kind == "TKCROSS" && gLastTKCrossBar == gLastBarTime) return;

   if(!InpAllowHedge)
   {
      if(signal == 1  && CountPositions(1) > 0) return; // mamy SELL
      if(signal == -1 && CountPositions(0) > 0) return; // mamy BUY
   }

   TryOpen(signal, kind);
}

//+------------------------------------------------------------------+
//| OnTradeTransaction - sledzimy zamkniecia dla cooldown            |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest&    request,
                        const MqlTradeResult&     result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if(trans.symbol != gSymbol) return;

   if(!HistoryDealSelect(trans.deal)) return;
   if((long)HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != InpMagic) return;

   long entry = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_INOUT) return;

   double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT)
                 + HistoryDealGetDouble(trans.deal, DEAL_SWAP)
                 + HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);

   ulong posId = trans.position;

   bool stillOpen = PositionSelectByTicket(posId);
   if(stillOpen) return; // to bylo czesciowe zamkniecie, nie aktualizujemy cooldown ani listy partial

   gLastClosedTradeBar    = gLastBarTime;
   gLastClosedTradeProfit = profit;

   for(int i = ArraySize(gPartialDoneTickets) - 1; i >= 0; i--)
   {
      if(gPartialDoneTickets[i] == posId)
      {
         for(int j = i; j < ArraySize(gPartialDoneTickets) - 1; j++)
            gPartialDoneTickets[j] = gPartialDoneTickets[j+1];
         ArrayResize(gPartialDoneTickets, ArraySize(gPartialDoneTickets) - 1);
      }
   }

   PrintFormat("Zamknieto pozycje #%I64u: profit=%.2f, cooldown=%s",
               posId, profit, (profit < 0 ? "TAK" : "NIE"));
}

//+------------------------------------------------------------------+
