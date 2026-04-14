//+------------------------------------------------------------------+
//|                          PRO AI MULTI SCANNER EA V3 (FILTER).mq5 |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property strict
#include <Trade/Trade.mqh>

CTrade trade;

input double LotSize = 0.01;
input int MaxPositions = 1;
input int ATR_Period = 40;
input double RR = 2.0;
input int Magic = 777;

input double MinATR = 0.0005;
input double MaxATR = 0.02;
input double MaxSpreadATR = 0.5;
input double MinBodyPercent = 0.5;
input int CooldownMinutes = 20;

datetime lastTradeTime = 0;

string symbols[] =
{
   "EURUSDm","GBPUSDx","USDJPYm","USDCHFx",
   "AUDUSDx","XAUUSDX"
};

struct Signal
{
   string symbol;
   bool buy;
   bool sell;
   double entry;
   double sl;
   double tp;
};

// ================= BASIC ================= //
int PositionCount()
{
   int total=0;
   for(int i=0;i<PositionsTotal();i++)
      if(PositionGetTicket(i))
         if(PositionGetInteger(POSITION_MAGIC)==Magic)
            total++;
   return total;
}

bool HasPosition(string sym)
{
   for(int i=0;i<PositionsTotal();i++)
      if(PositionGetTicket(i))
         if(PositionGetString(POSITION_SYMBOL)==sym &&
            PositionGetInteger(POSITION_MAGIC)==Magic)
            return true;
   return false;
}

double GetATR(string sym)
{
   int handle=iATR(sym,PERIOD_H1,ATR_Period);
   double buffer[];
   ArraySetAsSeries(buffer,true);
   CopyBuffer(handle,0,0,1,buffer);
   IndicatorRelease(handle);
   return buffer[0];
}

// ================= SIGNAL ================= //
Signal GetSignal(string sym)
{
   Signal s;
   s.symbol=sym;

   if(HasPosition(sym))
      return s;

   double atr = GetATR(sym);

   if(atr < MinATR || atr > MaxATR)
      return s;

   double spread = SymbolInfoInteger(sym,SYMBOL_SPREAD) * _Point;
   if(spread > atr * MaxSpreadATR)
      return s;

   double closeH1=iClose(sym,PERIOD_H1,0);
   double sma50=iMA(sym,PERIOD_H1,50,0,MODE_SMA,PRICE_CLOSE);

   bool trendBull=closeH1>sma50;
   bool trendBear=closeH1<sma50;

   int hhIndex=iHighest(sym,PERIOD_H1,MODE_HIGH,20,1);
   int llIndex=iLowest(sym,PERIOD_H1,MODE_LOW,20,1);

   double hh=iHigh(sym,PERIOD_H1,hhIndex);
   double ll=iLow(sym,PERIOD_H1,llIndex);

   bool breakoutUp = closeH1 > hh;
   bool breakoutDn = closeH1 < ll;

   double closeM5 = iClose(sym, PERIOD_M5, 1);
   double openM5  = iOpen(sym, PERIOD_M5, 1);

   double prevClose = iClose(sym, PERIOD_M5, 2);

   double impulse = MathAbs(closeM5 - prevClose);
   if(impulse < atr * 0.1)
      return s;

   bool strongCandle = MathAbs(closeM5-openM5) > (atr*0.2);

   bool buy = breakoutUp && trendBull && strongCandle;
   bool sell = breakoutDn && trendBear && strongCandle;

   double price = SymbolInfoDouble(sym,SYMBOL_BID);

   if(buy)
   {
      s.buy=true;
      s.entry=price;
      s.sl=price-atr;
      s.tp=price+(atr*2.5);
   }

   if(sell)
   {
      s.sell=true;
      s.entry=price;
      s.sl=price+atr;
      s.tp=price-(atr*2.5);
   }

   return s;
}

// ================= MANAGEMENT ================= //
void ManagePositions()
{
   for(int i=0;i<PositionsTotal();i++)
   {
      if(!PositionGetTicket(i)) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=Magic) continue;

      string sym=PositionGetString(POSITION_SYMBOL);

      double open=PositionGetDouble(POSITION_PRICE_OPEN);
      double sl=PositionGetDouble(POSITION_SL);
      double tp=PositionGetDouble(POSITION_TP);
      double price=SymbolInfoDouble(sym,SYMBOL_BID);

      double atr=GetATR(sym);
      double profit=MathAbs(price-open);

      bool isBuy = PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY;

      double newSL = sl;

      if(profit >= atr * 2)
         newSL = open;

      if(profit >= atr * 3)
      {
         if(isBuy) newSL = price - atr;
         else newSL = price + atr;
      }

      if(newSL != sl)
         trade.PositionModify(sym,newSL,tp);
   }
}

// ================= MAIN ================= //
void OnTick()
{
   ManagePositions();

   if(TimeCurrent() - lastTradeTime < CooldownMinutes * 60)
      return;

   if(PositionCount()>=MaxPositions)
      return;

   for(int i=0;i<ArraySize(symbols);i++)
   {
      string sym = symbols[i];

      if(HasPosition(sym)) continue;

      Signal s = GetSignal(sym);

      trade.SetExpertMagicNumber(Magic);

      if(s.buy)
      {
         trade.Buy(LotSize,sym,s.entry,s.sl,s.tp);
         lastTradeTime = TimeCurrent();
      }

      if(s.sell)
      {
         trade.Sell(LotSize,sym,s.entry,s.sl,s.tp);
         lastTradeTime = TimeCurrent();
      }
   }
}