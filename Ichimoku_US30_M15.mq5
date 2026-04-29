//+------------------------------------------------------------------+
//|                                            Ichimoku_US30_M15.mq5 |
//|                          Strategia Ichimoku Trend-Following     |
//|         Wejscie: M15 | Trend: H4 | Filtry: ATR + godzinowy      |
//+------------------------------------------------------------------+
#property copyright "Strategia Ichimoku US30 M15"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

CTrade         trade;
CPositionInfo  posInfo;

//--- Parametry wejsciowe (zoptymalizowane pod M15 + H4 trend)
input group "=== ICHIMOKU PARAMETRY ==="
input int      InpTenkan        = 9;
input int      InpKijun         = 26;
input int      InpSenkouB       = 52;

input group "=== ZARZADZANIE RYZYKIEM ==="
input double   InpRiskPercent   = 1.0;      // Ryzyko na transakcje (%)
input double   InpMinRR         = 2.0;      // Minimalne R:R (TP)
input int      InpSlPoints      = 200;      // Bazowy SL w punktach (fallback)

enum ENUM_RISK_BASE
{
   RISK_BALANCE     = 0,  // Saldo (balance)
   RISK_EQUITY      = 1,  // Kapital biezacy (equity) - ZALECANE
   RISK_FREE_MARGIN = 2   // Wolny depozyt
};
input ENUM_RISK_BASE InpRiskBase = RISK_EQUITY;
input double   InpMaxLot         = 0.0;
input bool     InpScaleLogs      = false;   // Loguj zmiane lota (na M15 wylacz)

input group "=== TRAILING STOP & BREAK EVEN ==="
input bool     InpUseBreakEven  = true;     // BE po osiagnieciu zysku
input double   InpBreakEvenAtR  = 1.0;      // Po ilu R aktywowac BE
input bool     InpUseTrailKijun = true;     // Trailing po Kijun
input double   InpTrailStartAtR = 1.5;      // Po ilu R startuje trailing

input group "=== FILTR KONSOLIDACJI ==="
input double   InpMinKumoATR    = 0.25;     // Chmura >= 0.25 * ATR
input int      InpKijunFlatBars = 5;        // Ile swiec Kijun musi sie zmieniac
input double   InpKijunFlatATR  = 0.12;     // Prog "Kijun flat" jako mnoznik ATR
input bool     InpUseADX        = true;
input int      InpADXPeriod     = 14;
input double   InpADXMin        = 20.0;     // Wyzszy prog na M15
input bool     InpUseChikou     = true;
input int      InpATRPeriod     = 14;

input group "=== FILTR GODZINOWY (UTC) ==="
input bool     InpUseHourFilter = true;     // WLACZONY domyslnie na M15
input int      InpStartHour     = 13;       // 13:30 UTC = otwarcie sesji USA
input int      InpStartMinute   = 30;
input int      InpEndHour       = 20;       // 20:00 UTC
input bool     InpBlockFridayPM = true;     // Nie otwieraj w piatek po 18:00 UTC

input group "=== USTAWIENIA OGOLNE ==="
input ulong          InpMagic    = 20240115; // Magic number
input int            InpSlippage = 10;       // Slippage w punktach
input ENUM_TIMEFRAMES InpEntryTF = PERIOD_CURRENT; // TF wejscia (CURRENT = z wykresu)
input ENUM_TIMEFRAMES InpTrendTF = PERIOD_H4;      // TF filtra trendu (H4 zalecany)
input bool           InpDebug    = false;    // Tryb diagnostyczny

//--- Stale czasowe (ustawiane w OnInit)
ENUM_TIMEFRAMES gEntryTF = PERIOD_M15;
ENUM_TIMEFRAMES gTrendTF = PERIOD_H4;
#define ENTRY_TF gEntryTF
#define TREND_TF gTrendTF

//--- Zmienne globalne
int    handleIchiE, handleIchiT, handleADX, handleATR;

bool   signalCloseBarRecorded = false;
double signalCloseBarHigh     = 0;
double signalCloseBarLow      = 0;
datetime signalCloseBarTime   = 0;

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

   handleIchiE = iIchimoku(_Symbol, ENTRY_TF, InpTenkan, InpKijun, InpSenkouB);
   if(handleIchiE == INVALID_HANDLE) { Print("BLAD: Ichimoku entry"); return INIT_FAILED; }

   handleIchiT = iIchimoku(_Symbol, TREND_TF, InpTenkan, InpKijun, InpSenkouB);
   if(handleIchiT == INVALID_HANDLE) { Print("BLAD: Ichimoku trend"); return INIT_FAILED; }

   if(InpUseADX) {
      handleADX = iADX(_Symbol, ENTRY_TF, InpADXPeriod);
      if(handleADX == INVALID_HANDLE) { Print("BLAD: ADX"); return INIT_FAILED; }
   }

   handleATR = iATR(_Symbol, ENTRY_TF, InpATRPeriod);
   if(handleATR == INVALID_HANDLE) { Print("BLAD: ATR"); return INIT_FAILED; }

   PrintFormat("Ichimoku EA init. Entry=%s Trend=%s | %d/%d/%d MinKumoATR=%.2f ADX=%.1f MinRR=%.1f Risk=%.1f%% Hours=%d (%d:%02d-%d:00)",
               EnumToString(gEntryTF), EnumToString(gTrendTF),
               InpTenkan, InpKijun, InpSenkouB,
               InpMinKumoATR, InpADXMin, InpMinRR, InpRiskPercent,
               InpUseHourFilter, InpStartHour, InpStartMinute, InpEndHour);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(handleIchiE != INVALID_HANDLE) IndicatorRelease(handleIchiE);
   if(handleIchiT != INVALID_HANDLE) IndicatorRelease(handleIchiT);
   if(handleADX   != INVALID_HANDLE) IndicatorRelease(handleADX);
   if(handleATR   != INVALID_HANDLE) IndicatorRelease(handleATR);
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
      OnNewBar();
   }

   if(PositionExistsWithMagic()) {
      ManageOpenPosition();
      CheckCloseConditions();
   }
}

//+------------------------------------------------------------------+
void OnNewBar()
{
   double tArr[], kArr[];
   if(CopyBuffer(handleIchiE, 0, 1, 3, tArr) <= 0) return;
   if(CopyBuffer(handleIchiE, 1, 1, 3, kArr) <= 0) return;
   ArraySetAsSeries(tArr, true);
   ArraySetAsSeries(kArr, true);

   double spAArr[], spBArr[];
   if(CopyBuffer(handleIchiE, 2, 1, 2, spAArr) <= 0) return;
   if(CopyBuffer(handleIchiE, 3, 1, 2, spBArr) <= 0) return;
   ArraySetAsSeries(spAArr, true);
   ArraySetAsSeries(spBArr, true);

   double close1 = iClose(_Symbol, ENTRY_TF, 1);
   double close2 = iClose(_Symbol, ENTRY_TF, 2);
   double closeBack = iClose(_Symbol, ENTRY_TF, 1 + InpKijun);

   double kumoTop    = MathMax(spAArr[0], spBArr[0]);
   double kumoBottom = MathMin(spAArr[0], spBArr[0]);
   double kumoWidth  = MathAbs(spAArr[0] - spBArr[0]);

   double atr = GetATR();
   if(atr <= 0) return;

   if(!FilterConsolidation(kumoWidth, atr)) return;
   if(!IsAllowedHour()) return;

   int trend = GetTrend();
   if(trend == 0) {
      if(InpDebug) Print("FILTR: brak trendu na ", EnumToString(gTrendTF));
      return;
   }

   if(PositionExistsWithMagic()) return;

   bool buySignal  = false;
   bool sellSignal = false;

   if(trend == 1) {
      bool crossBuy        = (tArr[0] > kArr[0]) && (tArr[1] <= kArr[1]);
      bool crossAboveKumo  = crossBuy && (tArr[0] > kumoTop);
      bool crossInKumo     = crossBuy && (tArr[0] >= kumoBottom) && (tArr[0] <= kumoTop);
      bool breakoutBuy     = (close1 > kumoTop) && (close2 <= kumoTop);
      bool chikouBuy       = !InpUseChikou || (close1 > closeBack);

      if((crossAboveKumo || crossInKumo || breakoutBuy) && chikouBuy)
         buySignal = true;
      else if(InpDebug)
         PrintFormat("BUY skip: crossA=%d crossIn=%d break=%d chikou=%d",
                     crossAboveKumo, crossInKumo, breakoutBuy, chikouBuy);
   }

   if(trend == -1) {
      bool crossSell       = (tArr[0] < kArr[0]) && (tArr[1] >= kArr[1]);
      bool crossBelowKumo  = crossSell && (tArr[0] < kumoBottom);
      bool crossInKumo     = crossSell && (tArr[0] >= kumoBottom) && (tArr[0] <= kumoTop);
      bool breakoutSell    = (close1 < kumoBottom) && (close2 >= kumoBottom);
      bool chikouSell      = !InpUseChikou || (close1 < closeBack);

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
bool FilterConsolidation(double kumoWidth, double atr)
{
   if(InpMinKumoATR > 0 && kumoWidth < InpMinKumoATR * atr) {
      if(InpDebug) PrintFormat("FILTR: chmura za waska %.4f < %.4f", kumoWidth, InpMinKumoATR * atr);
      return false;
   }

   if(InpKijunFlatBars > 0 && InpKijunFlatATR > 0) {
      double kijunArr[];
      if(CopyBuffer(handleIchiE, 1, 1, InpKijunFlatBars + 1, kijunArr) <= 0) return false;
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
         if(InpDebug) PrintFormat("FILTR: Kijun flat (prog %.4f)", flatThreshold);
         return false;
      }
   }

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
int GetTrend()
{
   double spA[], spB[];
   if(CopyBuffer(handleIchiT, 2, 1, 2, spA) <= 0) return 0;
   if(CopyBuffer(handleIchiT, 3, 1, 2, spB) <= 0) return 0;
   ArraySetAsSeries(spA, true);
   ArraySetAsSeries(spB, true);

   double kumoTop    = MathMax(spA[0], spB[0]);
   double kumoBottom = MathMin(spA[0], spB[0]);
   double closeT     = iClose(_Symbol, TREND_TF, 1);
   double closeBack  = iClose(_Symbol, TREND_TF, 1 + InpKijun);

   bool aboveCloud = (closeT > kumoTop);
   bool belowCloud = (closeT < kumoBottom);
   bool greenCloud = (spA[0] > spB[0]);
   bool redCloud   = (spA[0] < spB[0]);
   bool chikouUp   = (closeT > closeBack);
   bool chikouDown = (closeT < closeBack);

   if(aboveCloud && greenCloud && chikouUp)   return  1;
   if(belowCloud && redCloud   && chikouDown) return -1;
   return 0;
}

//+------------------------------------------------------------------+
void OpenBuy()
{
   double ask     = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double kijun   = GetKijun();
   double lastLow = iLow(_Symbol, ENTRY_TF, 1);

   double slLevel = MathMin(kijun, lastLow) - 5 * _Point;
   double slDist  = ask - slLevel;

   if(slDist <= 0 || slDist < InpSlPoints * _Point * 0.1) {
      if(InpDebug) Print("BUY: SL za blisko");
      return;
   }

   double tpEstimate = ask + slDist * InpMinRR;
   double lotSize    = CalculateLotSize(slDist);
   if(lotSize <= 0) return;

   if(trade.Buy(lotSize, _Symbol, ask, slLevel, tpEstimate, "Ichimoku BUY")) {
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
   double kijun    = GetKijun();
   double lastHigh = iHigh(_Symbol, ENTRY_TF, 1);

   double slLevel = MathMax(kijun, lastHigh) + 5 * _Point;
   double slDist  = slLevel - bid;

   if(slDist <= 0 || slDist < InpSlPoints * _Point * 0.1) {
      if(InpDebug) Print("SELL: SL za blisko");
      return;
   }

   double tpEstimate = bid - slDist * InpMinRR;
   double lotSize    = CalculateLotSize(slDist);
   if(lotSize <= 0) return;

   if(trade.Sell(lotSize, _Symbol, bid, slLevel, tpEstimate, "Ichimoku SELL")) {
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
void ManageOpenPosition()
{
   if(!InpUseBreakEven && !InpUseTrailKijun) return;
   if(!PositionSelectByMagic()) return;
   if(currentRSize <= 0) {
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

   double rProfit = isBuy
      ? (currentPrice - currentEntry) / currentRSize
      : (currentEntry - currentPrice) / currentRSize;

   if(InpUseBreakEven && !beActivated && rProfit >= InpBreakEvenAtR) {
      double newSL = currentEntry + (isBuy ? +5 : -5) * _Point;
      bool shouldMove = isBuy ? (newSL > currentSL) : (newSL < currentSL);
      if(shouldMove) {
         if(trade.PositionModify(currentTicket, newSL, currentTP)) {
            Print("BE aktywowane: SL=", newSL);
            beActivated = true;
         }
      }
      else beActivated = true;
   }

   if(InpUseTrailKijun && rProfit >= InpTrailStartAtR) {
      double kijun = GetKijun();
      if(isBuy) {
         double newSL = kijun - 5 * _Point;
         if(newSL > currentSL && newSL < bid) {
            if(trade.PositionModify(currentTicket, newSL, currentTP)) {
               if(!trailActivated) Print("Trailing Kijun aktywne. SL=", newSL);
               trailActivated = true;
            }
         }
      }
      else {
         double newSL = kijun + 5 * _Point;
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
   if(CopyBuffer(handleIchiE, 0, 1, 2, tenkanArr) <= 0) return;
   ArraySetAsSeries(tenkanArr, true);
   double tenkanNow = tenkanArr[0];

   double close1 = iClose(_Symbol, ENTRY_TF, 1);
   double high1  = iHigh(_Symbol,  ENTRY_TF, 1);
   double low1   = iLow(_Symbol,   ENTRY_TF, 1);
   datetime time1 = iTime(_Symbol, ENTRY_TF, 1);

   if(isBuy) {
      if(!signalCloseBarRecorded) {
         if(close1 < tenkanNow) {
            signalCloseBarRecorded = true;
            signalCloseBarHigh     = high1;
            signalCloseBarTime     = time1;
         }
      }
      else {
         datetime time2 = iTime(_Symbol, ENTRY_TF, 2);
         if(time2 == signalCloseBarTime) {
            if(high1 < signalCloseBarHigh) {
               Print("BUY: Potwierdzenie zamkniecia.");
               CloseAllPositions();
            }
            else ResetCloseSignal();
         }
         else if(time1 != signalCloseBarTime) {
            if(high1 < signalCloseBarHigh) {
               Print("BUY: Potwierdzenie (delayed).");
               CloseAllPositions();
            }
            else ResetCloseSignal();
         }
      }
   }
   else {
      if(!signalCloseBarRecorded) {
         if(close1 > tenkanNow) {
            signalCloseBarRecorded = true;
            signalCloseBarLow      = low1;
            signalCloseBarTime     = time1;
         }
      }
      else {
         datetime time2 = iTime(_Symbol, ENTRY_TF, 2);
         if(time2 == signalCloseBarTime) {
            if(low1 > signalCloseBarLow) {
               Print("SELL: Potwierdzenie zamkniecia.");
               CloseAllPositions();
            }
            else ResetCloseSignal();
         }
         else if(time1 != signalCloseBarTime) {
            if(low1 > signalCloseBarLow) {
               Print("SELL: Potwierdzenie (delayed).");
               CloseAllPositions();
            }
            else ResetCloseSignal();
         }
      }
   }

   int trend = GetTrend();
   if(isBuy  && trend == -1) { Print("AWARYJNE: trend zmieniony na SELL."); CloseAllPositions(); }
   if(!isBuy && trend ==  1) { Print("AWARYJNE: trend zmieniony na BUY.");  CloseAllPositions(); }
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
double GetKijun()
{
   double kArr[];
   if(CopyBuffer(handleIchiE, 1, 1, 2, kArr) <= 0) return 0;
   ArraySetAsSeries(kArr, true);
   return kArr[0];
}

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

   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double lotStep   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minLot    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

   if(tickValue == 0 || tickSize == 0 || lotStep == 0) return 0;

   double valuePerLot = (slDistance / tickSize) * tickValue;
   if(valuePerLot <= 0) return 0;

   double lots = riskAmount / valuePerLot;
   lots = MathFloor(lots / lotStep) * lotStep;
   lots = MathMax(lots, minLot);
   lots = MathMin(lots, maxLot);
   if(InpMaxLot > 0) lots = MathMin(lots, InpMaxLot);

   if(InpScaleLogs)
      PrintFormat("Lot calc: %s=%.2f risk=%.2f%% (%.2f) slDist=%.2f -> %.2f",
                  baseLabel, riskBase, InpRiskPercent, riskAmount, slDistance, lots);

   return lots;
}

//+------------------------------------------------------------------+
//| Filtr godzinowy z opcjonalna blokada piatkowego popoludnia       |
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
      if(InpDebug) PrintFormat("FILTR: poza godzinami (%d:%02d)", h, m);
      return false;
   }

   if(InpBlockFridayPM && dt.day_of_week == 5 && h >= 18) {
      if(InpDebug) Print("FILTR: piatek po 18:00 UTC");
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
