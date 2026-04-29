//+------------------------------------------------------------------+
//|                                           Ichimoku_Gold_H1.mq5  |
//|                                     Strategia Ichimoku XAUUSD   |
//|                    Trend: D1 | Wejscie: H1 | Filtr konsolidacji |
//+------------------------------------------------------------------+
#property copyright "Strategia Ichimoku Gold H1"
#property version   "1.20"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

CTrade         trade;
CPositionInfo  posInfo;

//--- Parametry wejsciowe (wartosci po optymalizacji w MT5)
input group "=== ICHIMOKU PARAMETRY ==="
input int      InpTenkan        = 13;       // Tenkan-sen
input int      InpKijun         = 28;       // Kijun-sen
input int      InpSenkouB       = 82;       // Senkou Span B

input group "=== ZARZADZANIE RYZYKIEM ==="
input double   InpRiskPercent   = 1.0;      // Ryzyko na transakcje (%)
input double   InpMinRR         = 6.0;      // Minimalne R:R
input int      InpSlPoints      = 2300;     // Bazowy SL w punktach (fallback)

input group "=== FILTR KONSOLIDACJI ==="
input double   InpMinKumoWidth  = 85.0;     // Min. szerokosc chmury w pipsach
input int      InpKijunFlatBars = 36;       // Ile swiec Kijun musi sie zmieniac
input bool     InpUseADX        = true;     // Uzyc filtra ADX
input int      InpADXPeriod     = 10;       // Okres ADX
input double   InpADXMin        = 20.0;     // Minimalne ADX

input group "=== USTAWIENIA OGOLNE ==="
input ulong    InpMagic         = 20240101; // Magic number
input int      InpSlippage      = 50;       // Slippage w punktach
input bool     InpUseLondonNY   = false;    // Tylko sesja London/NY
input bool     InpDebug         = false;    // Tryb diagnostyczny

//--- Zmienne globalne
int    handleIchiH1, handleIchiD1, handleADX;

bool   signalCloseBarRecorded = false;
double signalCloseBarHigh     = 0;
double signalCloseBarLow      = 0;
datetime signalCloseBarTime   = 0;

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpSlippage);

   handleIchiH1 = iIchimoku(_Symbol, PERIOD_H1, InpTenkan, InpKijun, InpSenkouB);
   if(handleIchiH1 == INVALID_HANDLE) {
      Print("BLAD: Nie mozna utworzyc Ichimoku H1");
      return INIT_FAILED;
   }

   handleIchiD1 = iIchimoku(_Symbol, PERIOD_D1, InpTenkan, InpKijun, InpSenkouB);
   if(handleIchiD1 == INVALID_HANDLE) {
      Print("BLAD: Nie mozna utworzyc Ichimoku D1");
      return INIT_FAILED;
   }

   if(InpUseADX) {
      handleADX = iADX(_Symbol, PERIOD_H1, InpADXPeriod);
      if(handleADX == INVALID_HANDLE) {
         Print("BLAD: Nie mozna utworzyc ADX");
         return INIT_FAILED;
      }
   }

   PrintFormat("Ichimoku Gold H1 EA init. %d/%d/%d MinKumo=%.1f FlatBars=%d ADX=%d/%.1f MinRR=%.1f",
               InpTenkan, InpKijun, InpSenkouB,
               InpMinKumoWidth, InpKijunFlatBars,
               InpADXPeriod, InpADXMin, InpMinRR);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(handleIchiH1 != INVALID_HANDLE) IndicatorRelease(handleIchiH1);
   if(handleIchiD1 != INVALID_HANDLE) IndicatorRelease(handleIchiD1);
   if(handleADX    != INVALID_HANDLE) IndicatorRelease(handleADX);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   static datetime lastBarTime = 0;
   datetime currentBarTime = iTime(_Symbol, PERIOD_H1, 0);
   bool isNewBar = (currentBarTime != lastBarTime);

   if(isNewBar) {
      lastBarTime = currentBarTime;
      OnNewBarH1();
   }

   if(PositionExistsWithMagic()) {
      CheckCloseConditions();
   }
}

//+------------------------------------------------------------------+
//| Logika na nowej swiece H1                                        |
//+------------------------------------------------------------------+
void OnNewBarH1()
{
   double tenkanH1_1, kijunH1_1, spanAH1_1, spanBH1_1, chikouH1_1;
   if(!GetIchiH1Values(1, tenkanH1_1, kijunH1_1, spanAH1_1, spanBH1_1, chikouH1_1)) return;

   double tArr[], kArr[];
   CopyBuffer(handleIchiH1, 0, 1, 3, tArr);
   CopyBuffer(handleIchiH1, 1, 1, 3, kArr);
   ArraySetAsSeries(tArr, true);
   ArraySetAsSeries(kArr, true);

   double spAArr[], spBArr[];
   CopyBuffer(handleIchiH1, 2, 1, 2, spAArr);
   CopyBuffer(handleIchiH1, 3, 1, 2, spBArr);
   ArraySetAsSeries(spAArr, true);
   ArraySetAsSeries(spBArr, true);

   int chikouShift = InpKijun;
   double chikouArr[];
   CopyBuffer(handleIchiH1, 4, 1 + chikouShift, 1, chikouArr);
   double chikouH1 = chikouArr[0];

   double closeH1_1 = iClose(_Symbol, PERIOD_H1, 1);
   double closeH1_2 = iClose(_Symbol, PERIOD_H1, 2);

   double kumoTopH1    = MathMax(spAArr[0], spBArr[0]);
   double kumoBottomH1 = MathMin(spAArr[0], spBArr[0]);
   double kumoWidthH1  = MathAbs(spAArr[0] - spBArr[0]) / _Point / 10.0;

   if(!FilterConsolidation(kumoWidthH1)) return;

   if(InpUseLondonNY && !IsLondonOrNYSession()) {
      if(InpDebug) Print("FILTR: poza sesja London/NY");
      return;
   }

   int d1Trend = GetD1Trend();
   if(d1Trend == 0) {
      if(InpDebug) Print("FILTR: D1 brak trendu");
      return;
   }

   if(PositionExistsWithMagic()) return;

   bool buySignal  = false;
   bool sellSignal = false;

   if(d1Trend == 1) {
      bool crossBuy        = (tArr[0] > kArr[0]) && (tArr[1] <= kArr[1]);
      bool crossAboveKumo  = crossBuy && (tArr[0] > kumoTopH1);
      bool crossInKumo     = crossBuy && (tArr[0] >= kumoBottomH1) && (tArr[0] <= kumoTopH1);
      bool breakoutBuy     = (closeH1_1 > kumoTopH1) && (closeH1_2 <= kumoTopH1);
      bool chikouBuy       = (chikouH1 > iClose(_Symbol, PERIOD_H1, 27));

      if((crossAboveKumo || crossInKumo || breakoutBuy) && chikouBuy)
         buySignal = true;
   }

   if(d1Trend == -1) {
      bool crossSell       = (tArr[0] < kArr[0]) && (tArr[1] >= kArr[1]);
      bool crossBelowKumo  = crossSell && (tArr[0] < kumoBottomH1);
      bool crossInKumo     = crossSell && (tArr[0] >= kumoBottomH1) && (tArr[0] <= kumoTopH1);
      bool breakoutSell    = (closeH1_1 < kumoBottomH1) && (closeH1_2 >= kumoBottomH1);
      bool chikouSell      = (chikouH1 < iClose(_Symbol, PERIOD_H1, 27));

      if((crossBelowKumo || crossInKumo || breakoutSell) && chikouSell)
         sellSignal = true;
   }

   if(buySignal)  OpenBuy();
   if(sellSignal) OpenSell();
}

//+------------------------------------------------------------------+
//| Filtr konsolidacji                                               |
//+------------------------------------------------------------------+
bool FilterConsolidation(double kumoWidthPips)
{
   if(kumoWidthPips < InpMinKumoWidth) {
      if(InpDebug) PrintFormat("FILTR: chmura za waska %.1f < %.1f", kumoWidthPips, InpMinKumoWidth);
      return false;
   }

   double kijunArr[];
   ArrayResize(kijunArr, InpKijunFlatBars + 1);
   CopyBuffer(handleIchiH1, 1, 1, InpKijunFlatBars + 1, kijunArr);
   ArraySetAsSeries(kijunArr, true);

   bool kijunFlat = true;
   for(int i = 1; i <= InpKijunFlatBars; i++) {
      if(MathAbs(kijunArr[0] - kijunArr[i]) > _Point * 5) {
         kijunFlat = false;
         break;
      }
   }
   if(kijunFlat) {
      if(InpDebug) PrintFormat("FILTR: Kijun plaski %d swiec", InpKijunFlatBars);
      return false;
   }

   if(InpUseADX) {
      double adxArr[];
      CopyBuffer(handleADX, 0, 1, 2, adxArr);
      ArraySetAsSeries(adxArr, true);
      if(adxArr[0] < InpADXMin) {
         if(InpDebug) PrintFormat("FILTR: ADX %.2f < %.2f", adxArr[0], InpADXMin);
         return false;
      }
   }

   return true;
}

//+------------------------------------------------------------------+
//| Trend D1: 1=wzrostowy, -1=spadkowy, 0=brak                       |
//+------------------------------------------------------------------+
int GetD1Trend()
{
   double spAD1[], spBD1[];
   CopyBuffer(handleIchiD1, 2, 1, 2, spAD1);
   CopyBuffer(handleIchiD1, 3, 1, 2, spBD1);
   ArraySetAsSeries(spAD1, true);
   ArraySetAsSeries(spBD1, true);

   double kumoTopD1    = MathMax(spAD1[0], spBD1[0]);
   double kumoBottomD1 = MathMin(spAD1[0], spBD1[0]);
   double closeD1      = iClose(_Symbol, PERIOD_D1, 1);

   double chikouD1arr[];
   CopyBuffer(handleIchiD1, 4, 27, 1, chikouD1arr);
   double chikouD1     = chikouD1arr[0];
   double priceFor26D1 = iClose(_Symbol, PERIOD_D1, 27);

   bool aboveCloud = (closeD1 > kumoTopD1);
   bool belowCloud = (closeD1 < kumoBottomD1);
   bool greenCloud = (spAD1[0] > spBD1[0]);
   bool redCloud   = (spAD1[0] < spBD1[0]);
   bool chikouUp   = (chikouD1 > priceFor26D1);
   bool chikouDown = (chikouD1 < priceFor26D1);

   if(aboveCloud && greenCloud && chikouUp)   return  1;
   if(belowCloud && redCloud   && chikouDown) return -1;
   return 0;
}

//+------------------------------------------------------------------+
//| Otwarcie BUY                                                     |
//+------------------------------------------------------------------+
void OpenBuy()
{
   double ask     = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double kijunH1 = GetKijunH1();
   double lastLow = iLow(_Symbol, PERIOD_H1, 1);

   double slLevel = MathMin(kijunH1, lastLow) - 10 * _Point;
   double slDist  = ask - slLevel;

   if(slDist <= 0) {
      Print("BUY: nieprawidlowy SL, pomijam");
      return;
   }

   double tpEstimate = ask + slDist * InpMinRR;
   double lotSize    = CalculateLotSize(slDist);
   if(lotSize <= 0) return;

   if(trade.Buy(lotSize, _Symbol, ask, slLevel, tpEstimate, "Ichimoku BUY")) {
      Print("BUY otwarte: Lot=", lotSize, " SL=", slLevel, " TP=", tpEstimate);
      ResetCloseSignal();
   }
   else {
      Print("BUY BLAD: ", trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| Otwarcie SELL                                                    |
//+------------------------------------------------------------------+
void OpenSell()
{
   double bid      = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double kijunH1  = GetKijunH1();
   double lastHigh = iHigh(_Symbol, PERIOD_H1, 1);

   double slLevel = MathMax(kijunH1, lastHigh) + 10 * _Point;
   double slDist  = slLevel - bid;

   if(slDist <= 0) {
      Print("SELL: nieprawidlowy SL, pomijam");
      return;
   }

   double tpEstimate = bid - slDist * InpMinRR;
   double lotSize    = CalculateLotSize(slDist);
   if(lotSize <= 0) return;

   if(trade.Sell(lotSize, _Symbol, bid, slLevel, tpEstimate, "Ichimoku SELL")) {
      Print("SELL otwarte: Lot=", lotSize, " SL=", slLevel, " TP=", tpEstimate);
      ResetCloseSignal();
   }
   else {
      Print("SELL BLAD: ", trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| Sprawdz warunki zamkniecia pozycji                               |
//+------------------------------------------------------------------+
void CheckCloseConditions()
{
   if(!PositionExistsWithMagic()) return;

   bool isBuy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);

   double tenkanArr[];
   CopyBuffer(handleIchiH1, 0, 1, 2, tenkanArr);
   ArraySetAsSeries(tenkanArr, true);
   double tenkanNow = tenkanArr[0];

   double closeH1_1  = iClose(_Symbol, PERIOD_H1, 1);
   double highH1_1   = iHigh(_Symbol,  PERIOD_H1, 1);
   double lowH1_1    = iLow(_Symbol,   PERIOD_H1, 1);
   datetime timeH1_1 = iTime(_Symbol, PERIOD_H1, 1);

   if(isBuy) {
      if(!signalCloseBarRecorded) {
         if(closeH1_1 < tenkanNow) {
            signalCloseBarRecorded = true;
            signalCloseBarHigh     = highH1_1;
            signalCloseBarTime     = timeH1_1;
            Print("BUY: Swieca sygnalowa zamkniecia. High=", signalCloseBarHigh);
         }
      }
      else {
         datetime timeH1_2 = iTime(_Symbol, PERIOD_H1, 2);
         if(timeH1_2 == signalCloseBarTime) {
            double highConfirm = iHigh(_Symbol, PERIOD_H1, 1);
            if(highConfirm < signalCloseBarHigh) {
               Print("BUY: Potwierdzenie zamkniecia. Zamykam.");
               CloseAllPositions();
            }
            else {
               Print("BUY: Potwierdzenie nieudane. Reset.");
               ResetCloseSignal();
            }
         }
         else if(timeH1_1 != signalCloseBarTime) {
            double highConfirm = highH1_1;
            if(highConfirm < signalCloseBarHigh) {
               Print("BUY: Potwierdzenie (delayed). Zamykam.");
               CloseAllPositions();
            }
            else ResetCloseSignal();
         }
      }
   }

   if(!isBuy) {
      if(!signalCloseBarRecorded) {
         if(closeH1_1 > tenkanNow) {
            signalCloseBarRecorded = true;
            signalCloseBarLow      = lowH1_1;
            signalCloseBarTime     = timeH1_1;
            Print("SELL: Swieca sygnalowa zamkniecia. Low=", signalCloseBarLow);
         }
      }
      else {
         datetime timeH1_2 = iTime(_Symbol, PERIOD_H1, 2);
         if(timeH1_2 == signalCloseBarTime) {
            double lowConfirm = iLow(_Symbol, PERIOD_H1, 1);
            if(lowConfirm > signalCloseBarLow) {
               Print("SELL: Potwierdzenie zamkniecia. Zamykam.");
               CloseAllPositions();
            }
            else {
               Print("SELL: Potwierdzenie nieudane. Reset.");
               ResetCloseSignal();
            }
         }
         else if(timeH1_1 != signalCloseBarTime) {
            double lowConfirm = lowH1_1;
            if(lowConfirm > signalCloseBarLow) {
               Print("SELL: Potwierdzenie (delayed). Zamykam.");
               CloseAllPositions();
            }
            else ResetCloseSignal();
         }
      }
   }

   int d1Trend = GetD1Trend();
   if(isBuy  && d1Trend == -1) { Print("AWARYJNE: D1 zmienil trend na SELL."); CloseAllPositions(); }
   if(!isBuy && d1Trend ==  1) { Print("AWARYJNE: D1 zmienil trend na BUY.");  CloseAllPositions(); }
}

//+------------------------------------------------------------------+
//| Zamknij wszystkie pozycje EA                                     |
//+------------------------------------------------------------------+
void CloseAllPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != (long)InpMagic) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      trade.PositionClose(ticket);
   }
   ResetCloseSignal();
}

//+------------------------------------------------------------------+
//| Sprawdz czy jest otwarta pozycja EA                              |
//+------------------------------------------------------------------+
bool PositionExistsWithMagic()
{
   for(int i = 0; i < PositionsTotal(); i++) {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) == (long)InpMagic &&
         PositionGetString(POSITION_SYMBOL) == _Symbol)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Pobierz Kijun H1 (ostatnia zamknieta)                            |
//+------------------------------------------------------------------+
double GetKijunH1()
{
   double kArr[];
   CopyBuffer(handleIchiH1, 1, 1, 2, kArr);
   ArraySetAsSeries(kArr, true);
   return kArr[0];
}

//+------------------------------------------------------------------+
//| Pomocnicze: pobierz wartosci Ichimoku H1 dla danego indeksu      |
//+------------------------------------------------------------------+
bool GetIchiH1Values(int shift,
                     double &tenkan, double &kijun,
                     double &spanA,  double &spanB, double &chikou)
{
   double tArr[], kArr[], aArr[], bArr[], cArr[];
   if(CopyBuffer(handleIchiH1, 0, shift, 1, tArr) <= 0) return false;
   if(CopyBuffer(handleIchiH1, 1, shift, 1, kArr) <= 0) return false;
   if(CopyBuffer(handleIchiH1, 2, shift, 1, aArr) <= 0) return false;
   if(CopyBuffer(handleIchiH1, 3, shift, 1, bArr) <= 0) return false;
   if(CopyBuffer(handleIchiH1, 4, shift + 26, 1, cArr) <= 0) return false;
   tenkan = tArr[0]; kijun = kArr[0];
   spanA  = aArr[0]; spanB = bArr[0]; chikou = cArr[0];
   return true;
}

//+------------------------------------------------------------------+
//| Oblicz wielkosc lota                                             |
//+------------------------------------------------------------------+
double CalculateLotSize(double slDistance)
{
   double balance    = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = balance * InpRiskPercent / 100.0;

   double tickValue  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize   = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double lotStep    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minLot     = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot     = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

   if(tickValue == 0 || tickSize == 0) return 0;

   double valuePerLot = (slDistance / tickSize) * tickValue;
   if(valuePerLot == 0) return 0;

   double lots = riskAmount / valuePerLot;
   lots = MathFloor(lots / lotStep) * lotStep;
   lots = MathMax(lots, minLot);
   lots = MathMin(lots, maxLot);

   return lots;
}

//+------------------------------------------------------------------+
//| Filtr sesji London/NY (UTC)                                      |
//+------------------------------------------------------------------+
bool IsLondonOrNYSession()
{
   MqlDateTime dt;
   TimeToStruct(TimeGMT(), dt);
   int h = dt.hour;
   return (h >= 7 && h < 21);
}

//+------------------------------------------------------------------+
//| Reset sygnalu zamkniecia                                         |
//+------------------------------------------------------------------+
void ResetCloseSignal()
{
   signalCloseBarRecorded = false;
   signalCloseBarHigh     = 0;
   signalCloseBarLow      = 0;
   signalCloseBarTime     = 0;
}
//+------------------------------------------------------------------+
