//+------------------------------------------------------------------+
//| SafeH1_EA.mq5                                                    |
//| Minimal, safety-first MT5 EA template (H1, market orders)        |
//| - New-bar execution (avoids multi-orders on same bar)            |
//| - 1 position per symbol                                          |
//| - EMA cross entry (simple placeholder strategy)                  |
//| - ATR-based SL/TP                                                |
//| - Daily/weekly loss limits (equity-based)                        |
//| - Trading window in JST (configurable server<->JST offset)       |
//+------------------------------------------------------------------+
#property strict

#include <Trade/Trade.mqh>
CTrade trade;

// -------------------- Inputs --------------------
input double InpLots                 = 0.10;   // Adjust per broker/symbol
input int    InpMagic                = 260221; // Magic number
input int    InpSlippagePoints       = 20;     // Deviation in points
input ENUM_TIMEFRAMES InpTF          = PERIOD_H1;

// Strategy (placeholder)
input int    InpFastEMA              = 20;
input int    InpSlowEMA              = 50;
input int    InpTrendLookbackBars    = 5;      // slope filter

// Risk/exit
input int    InpATRPeriod            = 14;
input double InpSL_ATR_Mult          = 2.0;    // SL = ATR * mult
input double InpTP_RR                = 1.2;    // TP = SL * RR
input bool   InpMoveToBE             = true;   // move SL to break-even
input double InpBE_Trigger_R         = 1.0;    // move to BE when profit >= 1R
input int    InpBE_OffsetPoints      = 5;      // BE + small offset

// Trading window (JST)
input int    InpServerToJstOffsetHrs = 0;      // JST = ServerTime + offsetHours
input int    InpTradeStartHourJST    = 21;     // inclusive
input int    InpTradeEndHourJST      = 2;      // exclusive (crosses midnight)

// Loss limits (equity-based)
input double InpDailyLossLimitPct    = 2.0;    // stop trading for day if equity drops by X% from day start
input double InpWeeklyLossLimitPct   = 5.0;    // stop trading for week if equity drops by X% from week start

// -------------------- Globals --------------------
datetime g_lastBarTime = 0;

double   g_dayStartEquity  = 0.0;
double   g_weekStartEquity = 0.0;
int      g_dayKey = -1;    // YYYYMMDD
int      g_weekKey = -1;   // YYYYWW

// -------------------- Utilities --------------------
int DayKey(datetime tJst)
{
   MqlDateTime dt; TimeToStruct(tJst, dt);
   return dt.year*10000 + dt.mon*100 + dt.day;
}

// Simple week key (approx): year*100 + weekOfYear
int WeekKey(datetime tJst)
{
   MqlDateTime dt; TimeToStruct(tJst, dt);
   int doy = dt.day_of_year;
   int woy = (doy-1)/7 + 1;
   return dt.year*100 + woy;
}

datetime ServerToJst(datetime serverTime)
{
   return (datetime)(serverTime + InpServerToJstOffsetHrs*3600);
}

bool IsInTradingWindowJst(datetime tJst)
{
   MqlDateTime dt; TimeToStruct(tJst, dt);
   int h = dt.hour;

   if(InpTradeStartHourJST == InpTradeEndHourJST)
      return true; // 24h

   if(InpTradeStartHourJST < InpTradeEndHourJST)
      return (h >= InpTradeStartHourJST && h < InpTradeEndHourJST);
   else
      return (h >= InpTradeStartHourJST || h < InpTradeEndHourJST);
}

bool IsNewBar()
{
   datetime t = iTime(_Symbol, InpTF, 0);
   if(t == 0) return false;
   if(t != g_lastBarTime)
   {
      g_lastBarTime = t;
      return true;
   }
   return false;
}

bool HasOpenPositionForThisEA()
{
   for(int i=PositionsTotal()-1; i>=0; --i)
   {
      if(PositionSelectByIndex(i))
      {
         string sym = PositionGetString(POSITION_SYMBOL);
         long   mg  = PositionGetInteger(POSITION_MAGIC);
         if(sym == _Symbol && (int)mg == InpMagic)
            return true;
      }
   }
   return false;
}

void ResetDayWeekAnchorsIfNeeded(datetime nowJst)
{
   int dk = DayKey(nowJst);
   int wk = WeekKey(nowJst);

   if(g_dayKey != dk)
   {
      g_dayKey = dk;
      g_dayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   }
   if(g_weekKey != wk)
   {
      g_weekKey = wk;
      g_weekStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   }
}

bool LossLimitHit()
{
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(g_dayStartEquity > 0.0)
   {
      double dayDD = (g_dayStartEquity - eq) / g_dayStartEquity * 100.0;
      if(dayDD >= InpDailyLossLimitPct) return true;
   }
   if(g_weekStartEquity > 0.0)
   {
      double weekDD = (g_weekStartEquity - eq) / g_weekStartEquity * 100.0;
      if(weekDD >= InpWeeklyLossLimitPct) return true;
   }
   return false;
}

double GetATR()
{
   return iATR(_Symbol, InpTF, InpATRPeriod, 0);
}

double NormalizePrice(double price)
{
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   return NormalizeDouble(price, digits);
}

double PointValue()
{
   return SymbolInfoDouble(_Symbol, SYMBOL_POINT);
}

// -------------------- Strategy (placeholder) --------------------
int GetSignal()
{
   // +1 buy, -1 sell, 0 none
   double fast0 = iMA(_Symbol, InpTF, InpFastEMA, 0, MODE_EMA, PRICE_CLOSE, 0);
   double fast1 = iMA(_Symbol, InpTF, InpFastEMA, 0, MODE_EMA, PRICE_CLOSE, 1);
   double slow0 = iMA(_Symbol, InpTF, InpSlowEMA, 0, MODE_EMA, PRICE_CLOSE, 0);
   double slow1 = iMA(_Symbol, InpTF, InpSlowEMA, 0, MODE_EMA, PRICE_CLOSE, 1);
   double slowN = iMA(_Symbol, InpTF, InpSlowEMA, 0, MODE_EMA, PRICE_CLOSE, InpTrendLookbackBars);

   bool slowUp   = (slow0 > slowN);
   bool slowDown = (slow0 < slowN);

   bool crossUp   = (fast1 <= slow1 && fast0 > slow0);
   bool crossDown = (fast1 >= slow1 && fast0 < slow0);

   if(crossUp && slowUp)     return +1;
   if(crossDown && slowDown) return -1;
   return 0;
}

// -------------------- Trade management --------------------
void TryOpen(int signal)
{
   if(signal == 0) return;

   double atr = GetATR();
   if(atr <= 0) return;

   double sl_dist = atr * InpSL_ATR_Mult;
   double tp_dist = sl_dist * InpTP_RR;

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpSlippagePoints);

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   if(signal > 0)
   {
      double sl = NormalizePrice(ask - sl_dist);
      double tp = NormalizePrice(ask + tp_dist);
      trade.Buy(InpLots, _Symbol, ask, sl, tp, "SafeH1 Buy");
   }
   else
   {
      double sl = NormalizePrice(bid + sl_dist);
      double tp = NormalizePrice(bid - tp_dist);
      trade.Sell(InpLots, _Symbol, bid, sl, tp, "SafeH1 Sell");
   }
}

void ManageBreakEven()
{
   if(!InpMoveToBE) return;

   for(int i=PositionsTotal()-1; i>=0; --i)
   {
      if(!PositionSelectByIndex(i)) continue;

      string sym = PositionGetString(POSITION_SYMBOL);
      long mg    = PositionGetInteger(POSITION_MAGIC);
      if(sym != _Symbol || (int)mg != InpMagic) continue;

      long type = PositionGetInteger(POSITION_TYPE);
      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl    = PositionGetDouble(POSITION_SL);
      double tp    = PositionGetDouble(POSITION_TP);

      double R = 0.0;
      if(type == POSITION_TYPE_BUY && sl > 0)  R = entry - sl;
      if(type == POSITION_TYPE_SELL && sl > 0) R = sl - entry;
      if(R <= 0) continue;

      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      if(type == POSITION_TYPE_BUY)
      {
         double profitDist = bid - entry;
         if(profitDist >= InpBE_Trigger_R * R)
         {
            double newSL = NormalizePrice(entry + InpBE_OffsetPoints * PointValue());
            if(sl < newSL)
            {
               trade.SetExpertMagicNumber(InpMagic);
               trade.PositionModify(_Symbol, newSL, tp);
            }
         }
      }
      else if(type == POSITION_TYPE_SELL)
      {
         double profitDist = entry - ask;
         if(profitDist >= InpBE_Trigger_R * R)
         {
            double newSL = NormalizePrice(entry - InpBE_OffsetPoints * PointValue());
            if(sl == 0.0 || sl > newSL)
            {
               trade.SetExpertMagicNumber(InpMagic);
               trade.PositionModify(_Symbol, newSL, tp);
            }
         }
      }
   }
}

// -------------------- MT5 lifecycle --------------------
int OnInit()
{
   g_lastBarTime = iTime(_Symbol, InpTF, 0);

   datetime nowServer = TimeCurrent();
   datetime nowJst = ServerToJst(nowServer);

   g_dayKey = DayKey(nowJst);
   g_weekKey = WeekKey(nowJst);
   g_dayStartEquity  = AccountInfoDouble(ACCOUNT_EQUITY);
   g_weekStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);

   return(INIT_SUCCEEDED);
}

void OnTick()
{
   datetime nowServer = TimeCurrent();
   datetime nowJst = ServerToJst(nowServer);

   ResetDayWeekAnchorsIfNeeded(nowJst);

   // Manage open positions even outside window
   ManageBreakEven();

   if(LossLimitHit())
      return;

   if(!IsNewBar())
      return;

   if(!IsInTradingWindowJst(nowJst))
      return;

   if(HasOpenPositionForThisEA())
      return;

   int signal = GetSignal();
   TryOpen(signal);
}