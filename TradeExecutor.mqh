//+------------------------------------------------------------------+
//|                                             TradeExecutor.mqh    |
//|                              Copyright 2026, By T@MER            |
//|                              https://www.bytamer.com             |
//+------------------------------------------------------------------+
//| SL=0 MUTLAK KURAL: sl parametresi her zaman IGNORE edilir       |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, By T@MER"
#property link      "https://www.bytamer.com"
#property strict

#ifndef TRADE_EXECUTOR_MQH
#define TRADE_EXECUTOR_MQH

#include "Config.mqh"
#include <Trade/Trade.mqh>

class CTradeExecutor
{
private:
   CTrade   m_trade;
   string   m_symbol;

public:
   CTradeExecutor() {}

   void Initialize(string symbol)
   {
      m_symbol = symbol;
      m_trade.SetExpertMagicNumber(MagicNumber);
      m_trade.SetDeviationInPoints(MaxSlippage);
      m_trade.SetTypeFilling(ORDER_FILLING_IOC);
      m_trade.SetTypeFillingBySymbol(symbol);

      Print(StringFormat("Trade Executor: %s | Magic=%d | Slip=%d | SL=YOK (MUTLAK)",
            symbol, MagicNumber, MaxSlippage));
   }

   //--- Pozisyon ac (SL PARAMETRESI HER ZAMAN 0)
   ulong OpenPosition(ENUM_SIGNAL_DIR dir, double lot, double tp, double sl, string comment)
   {
      // SL=0 MUTLAK KURAL - sl parametresi IGNORE edilir
      sl = 0;

      bool result = false;
      if(dir == SIGNAL_BUY)
         result = m_trade.Buy(lot, m_symbol, 0, 0, tp, comment);
      else if(dir == SIGNAL_SELL)
         result = m_trade.Sell(lot, m_symbol, 0, 0, tp, comment);
      else
         return 0;

      if(result)
      {
         ulong ticket = m_trade.ResultOrder();
         if(ticket > 0)
         {
            string dirStr = (dir == SIGNAL_BUY) ? "BUY" : "SELL";
            Print(StringFormat("ISLEM ACILDI: %s | %s | Lot=%.2f | TP=%.5f | SL=YOK | Ticket=%d",
                  dirStr, m_symbol, lot, tp, ticket));
            return ticket;
         }
      }

      int err = (int)m_trade.ResultRetcode();
      string errMsg = m_trade.ResultRetcodeDescription();
      string dirStr = (dir == SIGNAL_BUY) ? "BUY" : "SELL";
      Print(StringFormat("ISLEM HATASI: %s | %s | Lot=%.2f | Hata=%d | %s",
            dirStr, m_symbol, lot, err, errMsg));
      return 0;
   }

   //--- Pozisyon kapat
   bool ClosePosition(ulong ticket)
   {
      if(!PositionSelectByTicket(ticket)) return false;

      double profit = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);

      if(m_trade.PositionClose(ticket))
      {
         Print(StringFormat("POZISYON KAPANDI: Ticket=%d | Net=%.2f USD", ticket, profit));
         return true;
      }

      Print(StringFormat("KAPAMA HATASI: Ticket=%d | %s", ticket, m_trade.ResultRetcodeDescription()));
      return false;
   }

   //--- TP guncelle (SL her zaman 0)
   bool UpdateTP(ulong ticket, double newTP)
   {
      if(!PositionSelectByTicket(ticket)) return false;
      return m_trade.PositionModify(ticket, 0, newTP);  // SL=0 MUTLAK
   }
};

#endif
