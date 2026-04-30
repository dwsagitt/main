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
#property version   "1.00"
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

input group "=== Filtry trendu ==="
input bool    InpUseChikouFilter   = true;            // Wymagaj potwierdzenia Chikou Span
input bool    InpUseFutureKumoFilter = true;          // Wymagaj zgodności przyszłej chmury (Senkou A vs B)
input bool    InpUseKijunFilter    = true;            // Cena musi być po właściwej stronie Kijun-sen
input bool    InpRequireTKCross    = true;            // Wymagaj świeżego przecięcia Tenkan/Kijun (TK Cross)
input int     InpTKCrossLookback   = 5;               // Ile świec wstecz akceptujemy świeży TK Cross
input bool    InpStrongTKCrossOnly = true;            // Tylko mocne TK Cross (przecięcie ponad/pod chmurą)

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
input bool    InpUseKijunTrailing  = true;            // Trailing po Kijun-sen
input int     InpKijunTrailBuffer  = 100;             // Bufor trailingu (punkty) za Kijun
input bool    InpExitOnTKCross     = true;            // Zamknij gdy odwrotny TK Cross
input bool    InpExitOnCloudBreak  = true;            // Zamknij gdy cena wraca do/za chmurę
input bool    InpUseBreakEven      = true;            // Przesuń SL na BE po osiągnięciu R
input double  InpBreakEvenAtR      = 1.0;             // Po ilu R uruchomić BE (1.0 = po pierwszym R)
input int     InpBreakEvenOffsetPt = 30;              // Offset BE w punktach (lock zysku)

input group "=== Ograniczenia handlu ==="
input int     InpMaxPositions      = 1;               // Max otwartych pozycji EA na symbolu
input bool    InpOnePositionPerBar = true;            // Tylko 1 sygnał na słupek
input bool    InpAllowHedge        = false;           // Zezwól na pozycje przeciwne (hedge)
input int     InpSlippagePoints    = 30;              // Maks. poślizg [pkt]

//==================================================================
// ZMIENNE GLOBALNE
//==================================================================
int      ichi_handle = INVALID_HANDLE;
int      atr_handle  = INVALID_HANDLE;
string   gSymbol     = "";
datetime gLastBarTime = 0;
datetime gLastTradeBar = 0;

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
//| Sygnał wejścia: zwraca 1=BUY, -1=SELL, 0=brak                    |
//+------------------------------------------------------------------+
int CheckEntrySignal()
{
   double t1, k1, sa1, sb1, ch1;
   if(!GetIchimoku(1, t1, k1, sa1, sb1, ch1)) return 0;

   // Projekcja przyszłej chmury (26 świec do przodu) liczona klasycznie:
   //   Future Senkou A = (Tenkan + Kijun) / 2
   //   Future Senkou B = (max(High, 52) + min(Low, 52)) / 2
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
   int tkCross = InpRequireTKCross ? DetectTKCross(InpTKCrossLookback) : (t1 > k1 ? 1 : (t1 < k1 ? -1 : 0));

   bool tkBull = (tkCross == 1);
   bool tkBear = (tkCross == -1);

   bool kijunBull = !InpUseKijunFilter || (close1 > k1);
   bool kijunBear = !InpUseKijunFilter || (close1 < k1);

   bool chikouBull = !InpUseChikouFilter || (close1 > close26);
   bool chikouBear = !InpUseChikouFilter || (close1 < close26);

   bool futureBull = !InpUseFutureKumoFilter || (futA > futB);
   bool futureBear = !InpUseFutureKumoFilter || (futA < futB);

   bool strongBull = !InpStrongTKCrossOnly || (MathMin(t1,k1) > MathMax(sa1, sb1));
   bool strongBear = !InpStrongTKCrossOnly || (MathMax(t1,k1) < MathMin(sa1, sb1));

   if(priceVsCloud == 1 && tkBull && kijunBull && chikouBull && futureBull && strongBull)
      return 1;

   if(priceVsCloud == -1 && tkBear && kijunBear && chikouBear && futureBear && strongBear)
      return -1;

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
//| Otwarcie pozycji                                                 |
//+------------------------------------------------------------------+
void TryOpen(int dir)
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

   bool ok = false;
   if(dir == 1)
      ok = trade.Buy(lots, gSymbol, price, sl, tp, InpComment);
   else
      ok = trade.Sell(lots, gSymbol, price, sl, tp, InpComment);

   if(ok)
   {
      gLastTradeBar = gLastBarTime;
      PrintFormat("OTWARTO %s: lot=%.2f, price=%.2f, SL=%.2f (%.0f pkt), TP=%.2f, RR=%.2f",
                  (dir==1?"BUY":"SELL"), lots, price, sl, slDistPts, tp, InpRR);
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

      // === Break-Even ===
      if(InpUseBreakEven && curSL > 0)
      {
         double initRisk = MathAbs(open - curSL);
         if(initRisk > 0)
         {
            double moved = isBuy ? (price - open) : (open - price);
            if(moved >= InpBreakEvenAtR * initRisk)
            {
               double beSL = isBuy ? (open + InpBreakEvenOffsetPt * point) : (open - InpBreakEvenOffsetPt * point);
               bool needUpdate = isBuy ? (curSL < beSL) : (curSL > beSL || curSL == 0);
               if(needUpdate)
               {
                  if(trade.PositionModify(ticket, NPrice(beSL), curTP))
                     PrintFormat("BE #%I64u: SL -> %.2f", ticket, beSL);
               }
            }
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
               PrintFormat("Trailing #%I64u BUY: SL -> %.2f (Kijun=%.2f)", ticket, newSL, k1);
         }
         else if(!isBuy && (curSL == 0 || newSL < curSL) && newSL > price)
         {
            if(trade.PositionModify(ticket, NPrice(newSL), curTP))
               PrintFormat("Trailing #%I64u SELL: SL -> %.2f (Kijun=%.2f)", ticket, newSL, k1);
         }
      }
   }
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

   if(InpOnePositionPerBar && gLastTradeBar == gLastBarTime) return;

   int totalPos = CountPositions();
   if(totalPos >= InpMaxPositions && !InpAllowHedge) return;

   int signal = CheckEntrySignal();
   if(signal == 0) return;

   if(!InpAllowHedge)
   {
      if(signal == 1  && CountPositions(1) > 0) return; // mamy SELL
      if(signal == -1 && CountPositions(0) > 0) return; // mamy BUY
   }

   TryOpen(signal);
}

//+------------------------------------------------------------------+
