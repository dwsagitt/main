//+------------------------------------------------------------------+
//|                                           Ichimoku_Gold_H1.mq5  |
//|                                     Strategia Ichimoku XAUUSD   |
//|                    Trend: D1 | Wejscie: H1 | Filtr konsolidacji |
//+------------------------------------------------------------------+
#property copyright "Strategia Ichimoku Gold H1"
#property version   "1.10"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

CTrade         trade;
CPositionInfo  posInfo;

//--- Parametry wejsciowe
input group "=== ICHIMOKU PARAMETRY (H1 i D1 - po optymalizacji) ==="
input int      InpTenkan        = 13;       // Tenkan-sen
input int      InpKijun         = 28;       // Kijun-sen
input int      InpSenkouB       = 82;       // Senkou Span B
input int      InpChikouShift   = 26;       // Przesuniecie Chikou (oryginal=26)

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
input bool     InpDebug         = false;    // Tryb diagnostyczny (wypisuje filtry)

//--- Zmienne globalne
int    handleIchiH1, handleIchiD1, handleADX;

// Zmienne dla logiki zamkniecia
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

   // Ichimoku H1 - parametry po optymalizacji
   handleIchiH1 = iIchimoku(_Symbol, PERIOD_H1,
                            InpTenkan, InpKijun, InpSenkouB);
   if(handleIchiH1 == INVALID_HANDLE) {
      Print("BLAD: Nie mozna utworzyc Ichimoku H1");
      return INIT_FAILED;
   }

   // Ichimoku D1 - te same parametry co H1 (zgodnie z oryginalna optymalizacja)
   handleIchiD1 = iIchimoku(_Symbol, PERIOD_D1,
                            InpTenkan, InpKijun, InpSenkouB);
   if(handleIchiD1 == INVALID_HANDLE) {
      Print("BLAD: Nie mozna utworzyc Ichimoku D1");
      return INIT_FAILED;
   }

   // ADX H1
   if(InpUseADX) {
      handleADX = iADX(_Symbol, PERIOD_H1, InpADXPeriod);
      if(handleADX == INVALID_HANDLE) {
         Print("BLAD: Nie mozna utworzyc ADX");
         return INIT_FAILED;
      }
   }

   Print("Ichimoku Gold H1 EA init. ", InpTenkan, "/", InpKijun, "/", InpSenkouB,
         " ChikouShift=", InpChikouShift);
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
   // Tenkan / Kijun H1 (do detekcji crossa: indeks 1 = ostatnia zamknieta)
   double tArr[], kArr[];
   ArraySetAsSeries(tArr, true);
   ArraySetAsSeries(kArr, true);
   if(CopyBuffer(handleIchiH1, 0, 1, 3, tArr) <= 0) return;
   if(CopyBuffer(handleIchiH1, 1, 1, 3, kArr) <= 0) return;

   // Chmura H1
   double spAArr[], spBArr[];
   ArraySetAsSeries(spAArr, true);
   ArraySetAsSeries(spBArr, true);
   if(CopyBuffer(handleIchiH1, 2, 1, 2, spAArr) <= 0) return;
   if(CopyBuffer(handleIchiH1, 3, 1, 2, spBArr) <= 0) return;

   // Chikou H1: porownanie Close[1] z Close[1 + Kijun]
   // (nie czytamy bufora 4 - w MT5 wartosc Chikou przy biezacej swiecy
   //  to po prostu Close, a porownanie w terazniejszosci robimy w tyl)
   double closeForChikouH1 = iClose(_Symbol, PERIOD_H1, 1);
   double closeBackH1      = iClose(_Symbol, PERIOD_H1, 1 + InpChikouShift);

   // Ceny H1
   double closeH1_1 = iClose(_Symbol, PERIOD_H1, 1);
   double closeH1_2 = iClose(_Symbol, PERIOD_H1, 2);

   double kumoTopH1    = MathMax(spAArr[0], spBArr[0]);
   double kumoBottomH1 = MathMin(spAArr[0], spBArr[0]);
   double kumoWidthH1  = MathAbs(spAArr[0] - spBArr[0]) / _Point / 10.0; // w pipsach

   // --- FILTR KONSOLIDACJI ---
   if(!FilterConsolidation(kumoWidthH1)) return;

   // --- FILTR SESJI ---
   if(InpUseLondonNY && !IsLondonOrNYSession()) {
      if(InpDebug) Print("FILTR: poza sesja London/NY");
      return;
   }

   // --- FILTR TRENDU D1 ---
   int d1Trend = GetD1Trend();
   if(d1Trend == 0) {
      if(InpDebug) Print("FILTR: D1 brak trendu (cena w chmurze D1 / niespojny Chikou)");
      return;
   }

   // --- JUZ MAMY POZYCJE? ---
   if(PositionExistsWithMagic()) return;

   bool buySignal  = false;
   bool sellSignal = false;

   // --- BUY ---
   if(d1Trend == 1) {
      bool crossBuy        = (tArr[0] > kArr[0]) && (tArr[1] <= kArr[1]);
      bool crossAboveKumo  = crossBuy && (tArr[0] > kumoTopH1);
      bool crossInKumo     = crossBuy && (tArr[0] >= kumoBottomH1) && (tArr[0] <= kumoTopH1);
      bool breakoutBuy     = (closeH1_1 > kumoTopH1) && (closeH1_2 <= kumoTopH1);
      bool chikouBuy       = (closeForChikouH1 > closeBackH1);

      if((crossAboveKumo || crossInKumo || breakoutBuy) && chikouBuy)
         buySignal = true;
      else if(InpDebug)
         PrintFormat("BUY skip: crossAbove=%d crossIn=%d breakout=%d chikou=%d (T=%.2f K=%.2f kumoT=%.2f kumoB=%.2f c1=%.2f c2=%.2f)",
                     crossAboveKumo, crossInKumo, breakoutBuy, chikouBuy,
                     tArr[0], kArr[0], kumoTopH1, kumoBottomH1, closeH1_1, closeH1_2);
   }

   // --- SELL ---
   if(d1Trend == -1) {
      bool crossSell       = (tArr[0] < kArr[0]) && (tArr[1] >= kArr[1]);
      bool crossBelowKumo  = crossSell && (tArr[0] < kumoBottomH1);
      bool crossInKumo     = crossSell && (tArr[0] >= kumoBottomH1) && (tArr[0] <= kumoTopH1);
      bool breakoutSell    = (closeH1_1 < kumoBottomH1) && (closeH1_2 >= kumoBottomH1);
      bool chikouSell      = (closeForChikouH1 < closeBackH1);

      if((crossBelowKumo || crossInKumo || breakoutSell) && chikouSell)
         sellSignal = true;
      else if(InpDebug)
         PrintFormat("SELL skip: crossBelow=%d crossIn=%d breakout=%d chikou=%d (T=%.2f K=%.2f kumoT=%.2f kumoB=%.2f c1=%.2f c2=%.2f)",
                     crossBelowKumo, crossInKumo, breakoutSell, chikouSell,
                     tArr[0], kArr[0], kumoTopH1, kumoBottomH1, closeH1_1, closeH1_2);
   }

   if(buySignal)  OpenBuy();
   if(sellSignal) OpenSell();
}

//+------------------------------------------------------------------+
//| Filtr konsolidacji                                               |
//+------------------------------------------------------------------+
bool FilterConsolidation(double kumoWidthPips)
{
   // 1. Szerokosc chmury
   if(kumoWidthPips < InpMinKumoWidth) {
      if(InpDebug) PrintFormat("FILTR: chmura za waska %.1f < %.1f pips", kumoWidthPips, InpMinKumoWidth);
      return false;
   }

   // 2. Kijun plaski
   double kijunArr[];
   ArraySetAsSeries(kijunArr, true);
   if(CopyBuffer(handleIchiH1, 1, 1, InpKijunFlatBars + 1, kijunArr) <= 0) return false;

   bool kijunFlat = true;
   for(int i = 1; i <= InpKijunFlatBars; i++) {
      if(MathAbs(kijunArr[0] - kijunArr[i]) > _Point * 5) {
         kijunFlat = false;
         break;
      }
   }
   if(kijunFlat) {
      if(InpDebug) PrintFormat("FILTR: Kijun plaski przez %d swiec", InpKijunFlatBars);
      return false;
   }

   // 3. ADX
   if(InpUseADX) {
      double adxArr[];
      ArraySetAsSeries(adxArr, true);
      if(CopyBuffer(handleADX, 0, 1, 2, adxArr) <= 0) return false;
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
   ArraySetAsSeries(spAD1, true);
   ArraySetAsSeries(spBD1, true);
   if(CopyBuffer(handleIchiD1, 2, 1, 2, spAD1) <= 0) return 0;
   if(CopyBuffer(handleIchiD1, 3, 1, 2, spBD1) <= 0) return 0;

   double kumoTopD1    = MathMax(spAD1[0], spBD1[0]);
   double kumoBottomD1 = MathMin(spAD1[0], spBD1[0]);
   double closeD1      = iClose(_Symbol, PERIOD_D1, 1);

   // Chikou D1: Close[1] vs Close[1 + KijunD1]
   double closeForChikouD1 = iClose(_Symbol, PERIOD_D1, 1);
   double closeBackD1      = iClose(_Symbol, PERIOD_D1, 1 + InpChikouShift);

   bool aboveCloud = (closeD1 > kumoTopD1);
   bool belowCloud = (closeD1 < kumoBottomD1);
   bool greenCloud = (spAD1[0] > spBD1[0]);
   bool redCloud   = (spAD1[0] < spBD1[0]);
   bool chikouUp   = (closeForChikouD1 > closeBackD1);
   bool chikouDown = (closeForChikouD1 < closeBackD1);

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
   ArraySetAsSeries(tenkanArr, true);
   if(CopyBuffer(handleIchiH1, 0, 1, 2, tenkanArr) <= 0) return;
   double tenkanNow = tenkanArr[0];

   double closeH1_1  = iClose(_Symbol, PERIOD_H1, 1);
   double highH1_1   = iHigh(_Symbol,  PERIOD_H1, 1);
   double lowH1_1    = iLow(_Symbol,   PERIOD_H1, 1);
   datetime timeH1_1 = iTime(_Symbol, PERIOD_H1, 1);

   // --- BUY: zamkniecie ---
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
               Print("BUY: Potwierdzenie zamkniecia (delayed). Zamykam.");
               CloseAllPositions();
            }
            else {
               ResetCloseSignal();
            }
         }
      }
   }

   // --- SELL: zamkniecie ---
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
               Print("SELL: Potwierdzenie zamkniecia (delayed). Zamykam.");
               CloseAllPositions();
            }
            else {
               ResetCloseSignal();
            }
         }
      }
   }

   // --- Awaryjne zamkniecie: zmiana trendu D1 ---
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
   ArraySetAsSeries(kArr, true);
   if(CopyBuffer(handleIchiH1, 1, 1, 2, kArr) <= 0) return 0;
   return kArr[0];
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
   // London: 7:00-16:00 UTC | NY: 12:00-21:00 UTC
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
