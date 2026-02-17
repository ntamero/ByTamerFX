//+------------------------------------------------------------------+
//|                                             AccountSecurity.mqh  |
//|                              Copyright 2026, By T@MER            |
//|                              https://www.bytamer.com             |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, By T@MER"
#property link      "https://www.bytamer.com"
#property strict

#ifndef ACCOUNT_SECURITY_MQH
#define ACCOUNT_SECURITY_MQH

#include "Config.mqh"

class CAccountSecurity
{
private:
   long     m_expectedAccount;
   long     m_actualAccount;
   string   m_broker;
   bool     m_verified;

public:
   CAccountSecurity() : m_expectedAccount(0), m_actualAccount(0), m_verified(false) {}

   bool Initialize(long expectedAccount)
   {
      m_expectedAccount = expectedAccount;
      m_actualAccount   = AccountInfoInteger(ACCOUNT_LOGIN);
      m_broker          = AccountInfoString(ACCOUNT_COMPANY);

      if(m_actualAccount != m_expectedAccount)
      {
         Print("!!! GUVENLIK HATASI: Hesap numarasi uyusmuyor!");
         Print(StringFormat("  Beklenen: %d | Mevcut: %d | Broker: %s",
               m_expectedAccount, m_actualAccount, m_broker));
         Print("EA DEVRE DISI BIRAKILDI!");
         m_verified = false;
         return false;
      }

      m_verified = true;
      Print(StringFormat("Hesap dogrulandi: %d | Broker: %s", m_actualAccount, m_broker));
      return true;
   }

   bool Recheck()
   {
      long current = AccountInfoInteger(ACCOUNT_LOGIN);
      if(current != m_expectedAccount)
      {
         m_verified = false;
         Print("!!! HESAP DEGISTI - EA DURDURULUYOR!");
         return false;
      }
      return true;
   }

   bool     IsVerified()       const { return m_verified; }
   long     GetAccountNumber() const { return m_actualAccount; }
   string   GetBrokerName()    const { return m_broker; }
   double   GetBalance()       const { return AccountInfoDouble(ACCOUNT_BALANCE); }
   double   GetEquity()        const { return AccountInfoDouble(ACCOUNT_EQUITY); }
};

#endif
