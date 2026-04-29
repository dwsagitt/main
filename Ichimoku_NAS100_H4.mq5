//+------------------------------------------------------------------+
//|                                          Ichimoku_NAS100_H4.mq5 |
//|                     Strategia Ichimoku NAS100 (US Tech 100)     |
//|                  Trend: D1 | Wejscie: H4 | Filtr konsolidacji   |
//+------------------------------------------------------------------+
#property copyright "Strategia Ichimoku NAS100 H4"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

CTrade         trade;
CPositionInfo  posInfo;

//--- Parametry wejsciowe
input group "=== ICHIMOKU PARAMETRY ==="
input int      InpTenkan        = 9;        // Tenkan-sen (klasyk: 9)
input int      InpKijun         = 26;       // Kijun-sen (klasyk: 26)
input int      InpSenkouB       = 52;       // Senkou Span B (klasyk: 52)

input group "=== ZARZADZANIE RYZYKIEM ==="
input double   InpRiskPercent   = 1.0;      // Ryzyko na transakcje (%)
input double   InpMinRR         = 2.0;      // Minimalne R:R (TP)
input int      InpSlPoints      = 500;      // Bazowy SL w punktach (fallback)

enum ENUM_RISK_BASE
{
   RISK_BALANCE     = 0,  // Saldo (balance) - statyczne
   RISK_EQUITY      = 1,  // Kapital biezacy (equity) - dynamiczne ZALECANE
   RISK_FREE_MARGIN = 2   // Wolny depozyt (free margin)
};
input ENUM_RISK_BASE InpRiskBase = RISK_EQUITY;  // Baza do liczenia ryzyka
input double   InpMaxLot         = 0.0;          // Max lot (0 = limit brokera)
input bool     InpScaleLogs      = true;         // Loguj zmiane lota

input group "=== TRAILING STOP & BREAK EVEN ==="
input bool     InpUseBreakEven  = true;     // Aktywuj Break Even po 1R
input double   InpBreakEvenAtR  = 1.0;      // Po ilu R aktywowac BE
input bool     InpUseTrailKijun = true;     // Trailing Stop po Kijun H4
input double   InpTrailStartAtR = 1.5;      // Po ilu R startuje trailing

input group "=== FILTR KONSOLIDACJI ==="
input double   InpMinKumoATR    = 0.3;      // Min. szerokosc chmury jako mnoznik ATR (0=wylaczone)
input int      InpKijunFlatBars = 5;        // Ile swiec Kijun musi sie zmieniac
input double   InpKijunFlatATR  = 0.15;     // Prog "Kijun flat" jako mnoznik ATR
input bool     InpUseADX        = true;     // Uzyc filtra ADX
input int      InpADXPeriod     = 14;       // Okres ADX
input double   InpADXMin        = 18.0;     // Minimalne ADX
input bool     InpUseChikou     = true;     // Wymagaj potwierdzenia Chikou
input int      InpATRPeriod     = 14;       // Okres ATR (do filtrow)

input group "=== USTAWIENIA OGOLNE ==="
input ulong    InpMagic         = 20240102; // Magic number
input int      InpSlippage      = 10;       // Slippage w punktach
input bool     InpUseUSSession  = false;    // (przestarzale) Tylko sesja US
input bool     InpDebug         = false;    // Tryb diagnostyczny
input ENUM_TIMEFRAMES InpEntryTF = PERIOD_CURRENT; // TF wejscia (CURRENT = z wykresu)
input ENUM_TIMEFRAMES InpTrendTF = PERIOD_D1;      // TF filtra trendu

input group "=== FILTR GODZINOWY (UTC) ==="
input bool     InpUseHourFilter = false;    // Wlacz filtr godzinowy
input int      InpStartHour     = 13;       // Godzina startu (UTC, 0-23)
input int      InpEndHour       = 20;       // Godzina konca (UTC, 0-23)
input int      InpStartMinute   = 30;       // Minuta startu (np. 30 dla 13:30)
input bool     InpBlockFridayPM = false;    // Nie otwieraj po 18:00 UTC w piatek

//--- Stale czasowe (ustawiane w OnInit)
ENUM_TIMEFRAMES gEntryTF = PERIOD_H1;
ENUM_TIMEFRAMES gTrendTF = PERIOD_D1;
#define ENTRY_TF gEntryTF
#define TREND_TF gTrendTF

//--- Zmienne globalne
int    handleIchiH4, handleIchiD1, handleADX, handleATR;

bool   signalCloseBarRecorded = false;
double signalCloseBarHigh     = 0;
double signalCloseBarLow      = 0;
datetime signalCloseBarTime   = 0;

// Trailing/BE state per pozycja
ulong  currentTicket   = 0;
double currentEntry    = 0;
double currentInitSL   = 0;
double currentRSize    = 0;
bool   beActivated     = false;
bool   trailActivated  = false;

//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpSlippage);

   gEntryTF = (InpEntryTF == PERIOD_CURRENT) ? _Period : InpEntryTF;
   gTrendTF = InpTrendTF;

   handleIchiH4 = iIchimoku(_Symbol, ENTRY_TF, InpTenkan, InpKijun, InpSenkouB);
   if(handleIchiH4 == INVALID_HANDLE) { Print("BLAD: Ichimoku H4"); return INIT_FAILED; }

   handleIchiD1 = iIchimoku(_Symbol, TREND_TF, InpTenkan, InpKijun, InpSenkouB);
   if(handleIchiD1 == INVALID_HANDLE) { Print("BLAD: Ichimoku D1"); return INIT_FAILED; }

   if(InpUseADX) {
      handleADX = iADX(_Symbol, ENTRY_TF, InpADXPeriod);
      if(handleADX == INVALID_HANDLE) { Print("BLAD: ADX"); return INIT_FAILED; }
   }

   handleATR = iATR(_Symbol, ENTRY_TF, InpATRPeriod);
   if(handleATR == INVALID_HANDLE) { Print("BLAD: ATR"); return INIT_FAILED; }

   PrintFormat("Ichimoku EA init. EntryTF=%s TrendTF=%s | %d/%d/%d MinKumoATR=%.2f FlatATR=%.2f ADX=%d/%.1f MinRR=%.1f Risk=%.1f%% Chikou=%d",
               EnumToString(gEntryTF), EnumToString(gTrendTF),
               InpTenkan, InpKijun, InpSenkouB,
               InpMinKumoATR, InpKijunFlatATR,
               InpADXPeriod, InpADXMin, InpMinRR, InpRiskPercent, InpUseChikou);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(handleIchiH4 != INVALID_HANDLE) IndicatorRelease(handleIchiH4);
   if(handleIchiD1 != INVALID_HANDLE) IndicatorRelease(handleIchiD1);
   if(handleADX    != INVALID_HANDLE) IndicatorRelease(handleADX);
   if(handleATR    != INVALID_HANDLE) IndicatorRelease(handleATR);
}

//+------------------------------------------------------------------+
double GetATR()
{
   double atrArr[];
   if(CopyBuffer(handleATR, 0, 1, 1, atrArr) <= 0) return 0;
   return atrArr[0];
}

//+------------------------------------------------------------------+
void OnTick()
{
   static datetime lastBarTime = 0;
   datetime currentBarTime = iTime(_Symbol, ENTRY_TF, 0);
   bool isNewBar = (currentBarTime != lastBarTime);

   if(isNewBar) {
      lastBarTime = currentBarTime;
      OnNewBarH4();
   }

   if(PositionExistsWithMagic()) {
      ManageOpenPosition();
      CheckCloseConditions();
   }
}

//+------------------------------------------------------------------+
//| Logika na nowej swiece H4                                        |
//+------------------------------------------------------------------+
void OnNewBarH4()
{
   double tArr[], kArr[];
   if(CopyBuffer(handleIchiH4, 0, 1, 3, tArr) <= 0) return;
   if(CopyBuffer(handleIchiH4, 1, 1, 3, kArr) <= 0) return;
   ArraySetAsSeries(tArr, true);
   ArraySetAsSeries(kArr, true);

   double spAArr[], spBArr[];
   if(CopyBuffer(handleIchiH4, 2, 1, 2, spAArr) <= 0) return;
   if(CopyBuffer(handleIchiH4, 3, 1, 2, spBArr) <= 0) return;
   ArraySetAsSeries(spAArr, true);
   ArraySetAsSeries(spBArr, true);

   // Chikou: porownanie Close[1] z Close[1 + Kijun] - klasyczna logika
   double closeH4_1 = iClose(_Symbol, ENTRY_TF, 1);
   double closeH4_2 = iClose(_Symbol, ENTRY_TF, 2);
   double closeBack = iClose(_Symbol, ENTRY_TF, 1 + InpKijun);

   double kumoTopH4    = MathMax(spAArr[0], spBArr[0]);
   double kumoBottomH4 = MathMin(spAArr[0], spBArr[0]);
   double kumoWidth    = MathAbs(spAArr[0] - spBArr[0]); // w cenie

   double atr = GetATR();
   if(atr <= 0) {
      if(InpDebug) Print("FILTR: ATR niedostepne");
      return;
   }

   if(!FilterConsolidation(kumoWidth, atr)) return;

   if(!IsAllowedHour()) return;

   if(InpUseUSSession && !IsUSSession()) {
      if(InpDebug) Print("FILTR: poza sesja US");
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
      bool crossAboveKumo  = crossBuy && (tArr[0] > kumoTopH4);
      bool crossInKumo     = crossBuy && (tArr[0] >= kumoBottomH4) && (tArr[0] <= kumoTopH4);
      bool breakoutBuy     = (closeH4_1 > kumoTopH4) && (closeH4_2 <= kumoTopH4);
      bool chikouBuy       = !InpUseChikou || (closeH4_1 > closeBack);

      if((crossAboveKumo || crossInKumo || breakoutBuy) && chikouBuy)
         buySignal = true;
      else if(InpDebug)
         PrintFormat("BUY skip: crossA=%d crossIn=%d break=%d chikou=%d",
                     crossAboveKumo, crossInKumo, breakoutBuy, chikouBuy);
   }

   if(d1Trend == -1) {
      bool crossSell       = (tArr[0] < kArr[0]) && (tArr[1] >= kArr[1]);
      bool crossBelowKumo  = crossSell && (tArr[0] < kumoBottomH4);
      bool crossInKumo     = crossSell && (tArr[0] >= kumoBottomH4) && (tArr[0] <= kumoTopH4);
      bool breakoutSell    = (closeH4_1 < kumoBottomH4) && (closeH4_2 >= kumoBottomH4);
      bool chikouSell      = !InpUseChikou || (closeH4_1 < closeBack);

      if((crossBelowKumo || crossInKumo || breakoutSell) && chikouSell)
         sellSignal = true;
      else if(InpDebug)
         PrintFormat("SELL skip: crossB=%d crossIn=%d break=%d chikou=%d",
                     crossBelowKumo, crossInKumo, breakoutSell, chikouSell);
   }

   if(buySignal)  OpenBuy();
   if(sellSignal) OpenSell();
}

//+------------------------------------------------------------------+
//| Filtr konsolidacji                                               |
//+------------------------------------------------------------------+
bool FilterConsolidation(double kumoWidth, double atr)
{
   // 1. Szerokosc chmury w stosunku do ATR (uniwersalnie na kazdym instrumencie)
   if(InpMinKumoATR > 0 && kumoWidth < InpMinKumoATR * atr) {
      if(InpDebug) PrintFormat("FILTR: chmura za waska %.4f < %.4f (ATR=%.4f * %.2f)",
                               kumoWidth, InpMinKumoATR * atr, atr, InpMinKumoATR);
      return false;
   }

   // 2. Kijun "flat" - prog skalowany ATR
   if(InpKijunFlatBars > 0 && InpKijunFlatATR > 0) {
      double kijunArr[];
      if(CopyBuffer(handleIchiH4, 1, 1, InpKijunFlatBars + 1, kijunArr) <= 0) return false;
      ArraySetAsSeries(kijunArr, true);

      double flatThreshold = InpKijunFlatATR * atr;
      bool kijunFlat = true;
      for(int i = 1; i <= InpKijunFlatBars; i++) {
         if(MathAbs(kijunArr[0] - kijunArr[i]) > flatThreshold) {
            kijunFlat = false;
            break;
         }
      }
      if(kijunFlat) {
         if(InpDebug) PrintFormat("FILTR: Kijun plaski (prog %.4f, ATR=%.4f)",
                                  flatThreshold, atr);
         return false;
      }
   }

   // 3. ADX
   if(InpUseADX) {
      double adxArr[];
      if(CopyBuffer(handleADX, 0, 1, 2, adxArr) <= 0) return false;
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
   if(CopyBuffer(handleIchiD1, 2, 1, 2, spAD1) <= 0) return 0;
   if(CopyBuffer(handleIchiD1, 3, 1, 2, spBD1) <= 0) return 0;
   ArraySetAsSeries(spAD1, true);
   ArraySetAsSeries(spBD1, true);

   double kumoTopD1    = MathMax(spAD1[0], spBD1[0]);
   double kumoBottomD1 = MathMin(spAD1[0], spBD1[0]);
   double closeD1      = iClose(_Symbol, TREND_TF, 1);
   double closeBackD1  = iClose(_Symbol, TREND_TF, 1 + InpKijun);

   bool aboveCloud = (closeD1 > kumoTopD1);
   bool belowCloud = (closeD1 < kumoBottomD1);
   bool greenCloud = (spAD1[0] > spBD1[0]);
   bool redCloud   = (spAD1[0] < spBD1[0]);
   bool chikouUp   = (closeD1 > closeBackD1);
   bool chikouDown = (closeD1 < closeBackD1);

   if(aboveCloud && greenCloud && chikouUp)   return  1;
   if(belowCloud && redCloud   && chikouDown) return -1;
   return 0;
}

//+------------------------------------------------------------------+
void OpenBuy()
{
   double ask     = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double kijunH4 = GetKijunH4();
   double lastLow = iLow(_Symbol, ENTRY_TF, 1);

   double slLevel = MathMin(kijunH4, lastLow) - 10 * _Point;
   double slDist  = ask - slLevel;

   if(slDist <= 0 || slDist < InpSlPoints * _Point * 0.1) {
      if(InpDebug) Print("BUY: SL za blisko, pomijam");
      return;
   }

   double tpEstimate = ask + slDist * InpMinRR;
   double lotSize    = CalculateLotSize(slDist);
   if(lotSize <= 0) return;

   if(trade.Buy(lotSize, _Symbol, ask, slLevel, tpEstimate, "Ichimoku BUY H4")) {
      Print("BUY otwarte: Lot=", lotSize, " Entry=", ask, " SL=", slLevel, " TP=", tpEstimate);
      currentTicket  = trade.ResultOrder();
      currentEntry   = ask;
      currentInitSL  = slLevel;
      currentRSize   = slDist;
      beActivated    = false;
      trailActivated = false;
      ResetCloseSignal();
   }
   else Print("BUY BLAD: ", trade.ResultRetcodeDescription());
}

//+------------------------------------------------------------------+
void OpenSell()
{
   double bid      = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double kijunH4  = GetKijunH4();
   double lastHigh = iHigh(_Symbol, ENTRY_TF, 1);

   double slLevel = MathMax(kijunH4, lastHigh) + 10 * _Point;
   double slDist  = slLevel - bid;

   if(slDist <= 0 || slDist < InpSlPoints * _Point * 0.1) {
      if(InpDebug) Print("SELL: SL za blisko, pomijam");
      return;
   }

   double tpEstimate = bid - slDist * InpMinRR;
   double lotSize    = CalculateLotSize(slDist);
   if(lotSize <= 0) return;

   if(trade.Sell(lotSize, _Symbol, bid, slLevel, tpEstimate, "Ichimoku SELL H4")) {
      Print("SELL otwarte: Lot=", lotSize, " Entry=", bid, " SL=", slLevel, " TP=", tpEstimate);
      currentTicket  = trade.ResultOrder();
      currentEntry   = bid;
      currentInitSL  = slLevel;
      currentRSize   = slDist;
      beActivated    = false;
      trailActivated = false;
      ResetCloseSignal();
   }
   else Print("SELL BLAD: ", trade.ResultRetcodeDescription());
}

//+------------------------------------------------------------------+
//| Zarzadzanie otwarta pozycja: Break Even + Trailing Stop          |
//+------------------------------------------------------------------+
void ManageOpenPosition()
{
   if(!InpUseBreakEven && !InpUseTrailKijun) return;
   if(!PositionSelectByMagic()) return;
   if(currentRSize <= 0) {
      // Pozycja przejeta po restarcie - odtworz dane
      currentEntry  = PositionGetDouble(POSITION_PRICE_OPEN);
      currentInitSL = PositionGetDouble(POSITION_SL);
      currentRSize  = MathAbs(currentEntry - currentInitSL);
      if(currentRSize <= 0) return;
   }

   ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   bool isBuy = (posType == POSITION_TYPE_BUY);

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double currentPrice = isBuy ? bid : ask;
   double currentSL    = PositionGetDouble(POSITION_SL);
   double currentTP    = PositionGetDouble(POSITION_TP);

   // Aktualny zysk w R
   double rProfit = isBuy
      ? (currentPrice - currentEntry) / currentRSize
      : (currentEntry - currentPrice) / currentRSize;

   // --- BREAK EVEN ---
   if(InpUseBreakEven && !beActivated && rProfit >= InpBreakEvenAtR) {
      double newSL = currentEntry + (isBuy ? +5 : -5) * _Point; // mini bufor
      bool shouldMove = isBuy ? (newSL > currentSL) : (newSL < currentSL);

      if(shouldMove) {
         if(trade.PositionModify(currentTicket, newSL, currentTP)) {
            Print("BE aktywowane: SL przeniesiony na ", newSL);
            beActivated = true;
         }
      }
      else {
         beActivated = true;
      }
   }

   // --- TRAILING PO KIJUN ---
   if(InpUseTrailKijun && rProfit >= InpTrailStartAtR) {
      double kijunH4 = GetKijunH4();

      if(isBuy) {
         double newSL = kijunH4 - 10 * _Point;
         if(newSL > currentSL && newSL < bid) {
            if(trade.PositionModify(currentTicket, newSL, currentTP)) {
               if(!trailActivated) Print("Trailing Kijun aktywne. SL=", newSL);
               trailActivated = true;
            }
         }
      }
      else {
         double newSL = kijunH4 + 10 * _Point;
         if(newSL < currentSL && newSL > ask) {
            if(trade.PositionModify(currentTicket, newSL, currentTP)) {
               if(!trailActivated) Print("Trailing Kijun aktywne. SL=", newSL);
               trailActivated = true;
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
void CheckCloseConditions()
{
   if(!PositionSelectByMagic()) return;

   ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   bool isBuy = (posType == POSITION_TYPE_BUY);

   double tenkanArr[];
   if(CopyBuffer(handleIchiH4, 0, 1, 2, tenkanArr) <= 0) return;
   ArraySetAsSeries(tenkanArr, true);
   double tenkanNow = tenkanArr[0];

   double closeH4_1  = iClose(_Symbol, ENTRY_TF, 1);
   double highH4_1   = iHigh(_Symbol,  ENTRY_TF, 1);
   double lowH4_1    = iLow(_Symbol,   ENTRY_TF, 1);
   datetime timeH4_1 = iTime(_Symbol, ENTRY_TF, 1);

   if(isBuy) {
      if(!signalCloseBarRecorded) {
         if(closeH4_1 < tenkanNow) {
            signalCloseBarRecorded = true;
            signalCloseBarHigh     = highH4_1;
            signalCloseBarTime     = timeH4_1;
            if(InpDebug) Print("BUY: Swieca sygnalowa zamkniecia. High=", signalCloseBarHigh);
         }
      }
      else {
         datetime timeH4_2 = iTime(_Symbol, ENTRY_TF, 2);
         if(timeH4_2 == signalCloseBarTime) {
            if(highH4_1 < signalCloseBarHigh) {
               Print("BUY: Potwierdzenie zamkniecia. Zamykam.");
               CloseAllPositions();
            }
            else {
               if(InpDebug) Print("BUY: Potwierdzenie nieudane.");
               ResetCloseSignal();
            }
         }
         else if(timeH4_1 != signalCloseBarTime) {
            if(highH4_1 < signalCloseBarHigh) {
               Print("BUY: Potwierdzenie (delayed). Zamykam.");
               CloseAllPositions();
            }
            else ResetCloseSignal();
         }
      }
   }
   else {
      if(!signalCloseBarRecorded) {
         if(closeH4_1 > tenkanNow) {
            signalCloseBarRecorded = true;
            signalCloseBarLow      = lowH4_1;
            signalCloseBarTime     = timeH4_1;
            if(InpDebug) Print("SELL: Swieca sygnalowa zamkniecia. Low=", signalCloseBarLow);
         }
      }
      else {
         datetime timeH4_2 = iTime(_Symbol, ENTRY_TF, 2);
         if(timeH4_2 == signalCloseBarTime) {
            if(lowH4_1 > signalCloseBarLow) {
               Print("SELL: Potwierdzenie zamkniecia. Zamykam.");
               CloseAllPositions();
            }
            else {
               if(InpDebug) Print("SELL: Potwierdzenie nieudane.");
               ResetCloseSignal();
            }
         }
         else if(timeH4_1 != signalCloseBarTime) {
            if(lowH4_1 > signalCloseBarLow) {
               Print("SELL: Potwierdzenie (delayed). Zamykam.");
               CloseAllPositions();
            }
            else ResetCloseSignal();
         }
      }
   }

   // Awaryjne zamkniecie: zmiana trendu D1
   int d1Trend = GetD1Trend();
   if(isBuy  && d1Trend == -1) { Print("AWARYJNE: D1 zmienil trend na SELL."); CloseAllPositions(); }
   if(!isBuy && d1Trend ==  1) { Print("AWARYJNE: D1 zmienil trend na BUY.");  CloseAllPositions(); }
}

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
   currentTicket  = 0;
   currentRSize   = 0;
   beActivated    = false;
   trailActivated = false;
   ResetCloseSignal();
}

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
bool PositionSelectByMagic()
{
   for(int i = 0; i < PositionsTotal(); i++) {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) == (long)InpMagic &&
         PositionGetString(POSITION_SYMBOL) == _Symbol) {
         currentTicket = ticket;
         return PositionSelectByTicket(ticket);
      }
   }
   return false;
}

//+------------------------------------------------------------------+
double GetKijunH4()
{
   double kArr[];
   if(CopyBuffer(handleIchiH4, 1, 1, 2, kArr) <= 0) return 0;
   ArraySetAsSeries(kArr, true);
   return kArr[0];
}

//+------------------------------------------------------------------+
//| Auto-lot na podstawie aktualnego kapitalu                        |
//+------------------------------------------------------------------+
double CalculateLotSize(double slDistance)
{
   double riskBase = 0;
   string baseLabel = "";
   switch(InpRiskBase)
   {
      case RISK_EQUITY:
         riskBase = AccountInfoDouble(ACCOUNT_EQUITY);
         baseLabel = "Equity";
         break;
      case RISK_FREE_MARGIN:
         riskBase = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
         baseLabel = "FreeMargin";
         break;
      case RISK_BALANCE:
      default:
         riskBase = AccountInfoDouble(ACCOUNT_BALANCE);
         baseLabel = "Balance";
         break;
   }

   if(riskBase <= 0) {
      Print("BLAD lota: ", baseLabel, " <= 0");
      return 0;
   }

   double riskAmount = riskBase * InpRiskPercent / 100.0;

   double tickValue  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize   = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double lotStep    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minLot     = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot     = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

   if(tickValue == 0 || tickSize == 0 || lotStep == 0) return 0;

   double valuePerLot = (slDistance / tickSize) * tickValue;
   if(valuePerLot <= 0) return 0;

   double lots = riskAmount / valuePerLot;
   lots = MathFloor(lots / lotStep) * lotStep;
   lots = MathMax(lots, minLot);
   lots = MathMin(lots, maxLot);
   if(InpMaxLot > 0) lots = MathMin(lots, InpMaxLot);

   if(InpScaleLogs)
      PrintFormat("Lot calc: base=%s=%.2f risk=%.2f%% (%.2f) slDist=%.2f valPerLot=%.2f -> %.2f lots",
                  baseLabel, riskBase, InpRiskPercent, riskAmount, slDistance, valuePerLot, lots);

   return lots;
}

//+------------------------------------------------------------------+
//| Sesja US (NAS100): premarket od 13:00 UTC, regular 14:30-21:00   |
//+------------------------------------------------------------------+
bool IsUSSession()
{
   MqlDateTime dt;
   TimeToStruct(TimeGMT(), dt);
   int h = dt.hour;
   // Pre-market + regular session: 13:00 - 21:00 UTC
   return (h >= 13 && h < 21);
}

//+------------------------------------------------------------------+
//| Filtr godzinowy z opcjonalnym blokowaniem piatku                 |
//+------------------------------------------------------------------+
bool IsAllowedHour()
{
   if(!InpUseHourFilter) return true;

   MqlDateTime dt;
   TimeToStruct(TimeGMT(), dt);
   int h = dt.hour;
   int m = dt.min;

   int nowMin   = h * 60 + m;
   int startMin = InpStartHour * 60 + InpStartMinute;
   int endMin   = InpEndHour   * 60;

   bool inWindow;
   if(startMin <= endMin)
      inWindow = (nowMin >= startMin && nowMin < endMin);
   else
      inWindow = (nowMin >= startMin || nowMin < endMin);

   if(!inWindow) {
      if(InpDebug) PrintFormat("FILTR: poza godzinami (%d:%02d, okno %d:%02d-%d:00)",
                               h, m, InpStartHour, InpStartMinute, InpEndHour);
      return false;
   }

   if(InpBlockFridayPM && dt.day_of_week == 5 && h >= 18) {
      if(InpDebug) Print("FILTR: piatek po 18:00 UTC - blokada");
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
void ResetCloseSignal()
{
   signalCloseBarRecorded = false;
   signalCloseBarHigh     = 0;
   signalCloseBarLow      = 0;
   signalCloseBarTime     = 0;
}
//+------------------------------------------------------------------+
