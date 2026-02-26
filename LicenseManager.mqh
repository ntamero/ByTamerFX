//+------------------------------------------------------------------+
//|                                            LicenseManager.mqh    |
//|                        BytamerFX License Verification System     |
//|                                  Copyright 2026, By T@MER        |
//|                              https://www.bytamer.com             |
//+------------------------------------------------------------------+
//| Lisans Dogrulama Sistemi v3.3.0:                                 |
//| - Web API dogrulama (sifreli endpoint)                           |
//| - Offline cache (4 saat - sikila stirilmis)                      |
//| - Periyodik kontrol (5 dakika)                                   |
//| - Broker hesap eslestirme                                        |
//| - Sureli lisans (saatlik/gunluk)                                 |
//| - XOR string sifreleme (anti-reverse)                            |
//| - Integrity check (dosya boyut dogrulama)                        |
//| - Daginik kontrol noktalari (anti-crack)                         |
//| Format: BTAI-XXXXX-XXXXX-XXXXX-XXXXX                            |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, By T@MER"
#property link      "https://www.bytamer.com"
#property version   "1.00"
#property strict

#ifndef LICENSE_MANAGER_MQH
#define LICENSE_MANAGER_MQH

#include "Config.mqh"

//+------------------------------------------------------------------+
//| B2b: XOR String Sifreleme - derlemede string aramayi zorlastirir |
//| Her string farkli anahtar ile sifrelenir                         |
//+------------------------------------------------------------------+
namespace CryptoStr
{
   // XOR cozucu - anahtar ile string'i desifreler
   string Decode(const uchar &encoded[], int len, uchar key)
   {
      string result = "";
      for(int i = 0; i < len; i++)
      {
         uchar ch = (uchar)(encoded[i] ^ key);
         result += CharToString(ch);
      }
      return result;
   }

   // API URL: "https://bytamer.com/api/license.php"
   // XOR key: 0x5A
   string GetApiUrl()
   {
      uchar enc[] = {0x32,0x2E,0x2E,0x2A,0x29,0x60,0x75,0x75,
                     0x38,0x23,0x2E,0x3B,0x37,0x3F,0x28,0x74,
                     0x39,0x35,0x37,0x75,0x3B,0x2A,0x33,0x75,
                     0x36,0x33,0x39,0x3F,0x34,0x29,0x3F,0x74,
                     0x2A,0x32,0x2A};
      return Decode(enc, 35, 0x5A);
   }

   // Anahtar prefix: "BTAI-"
   // XOR key: 0x3C
   string GetKeyPrefix()
   {
      uchar enc[] = {0x7E,0x68,0x7D,0x75,0x11};
      return Decode(enc, 5, 0x3C);
   }

   // Hata: "Lisans anahtari bos veya cok kisa"
   // XOR key: 0x47
   string GetEmptyError()
   {
      uchar enc[] = {0x0B,0x2E,0x34,0x26,0x29,0x34,0x67,0x26,
                     0x29,0x26,0x2F,0x33,0x26,0x35,0x2E,0x67,
                     0x25,0x28,0x34,0x67,0x31,0x22,0x3E,0x26,
                     0x67,0x24,0x28,0x2C,0x67,0x2C,0x2E,0x34,0x26};
      return Decode(enc, 33, 0x47);
   }

   // Cache dosya prefix: "bytamerfx_license_"
   // XOR key: 0x29
   string GetCachePrefix()
   {
      uchar enc[] = {0x4B,0x50,0x5D,0x48,0x44,0x4C,0x5B,0x4F,
                     0x51,0x76,0x45,0x40,0x4A,0x4C,0x47,0x5A,
                     0x4C,0x76};
      return Decode(enc, 18, 0x29);
   }

   // Destek email: "info@bytamer.com"
   // XOR key: 0x71
   string GetSupportEmail()
   {
      uchar enc[] = {0x18,0x1F,0x17,0x1E,0x31,0x13,0x08,0x05,
                     0x10,0x1C,0x14,0x03,0x5F,0x12,0x1E,0x1C};
      return Decode(enc, 16, 0x71);
   }
}

//+------------------------------------------------------------------+
//| B2c: Integrity Check - EA dosya boyut dogrulama                  |
//+------------------------------------------------------------------+
namespace IntegrityCheck
{
   // EA kendi boyutunu kontrol eder
   // Derlendikten sonra gercek boyut buraya yazilir
   // Varsayilan: 0 = kontrol devre disi (ilk derleme icin)
   long EXPECTED_FILE_SIZE = 0;  // Derleme sonrasi guncellenir

   bool Verify()
   {
      // Boyut tanimlanmadiysa atla (ilk derleme)
      if(EXPECTED_FILE_SIZE == 0) return true;

      string eaPath = MQLInfoString(MQL_PROGRAM_PATH);
      if(eaPath == "") return true;

      // Dosya boyutu al
      long fileHandle = FileOpen(eaPath, FILE_READ|FILE_BIN);
      if(fileHandle == INVALID_HANDLE)
      {
         // Dosya acilamadiysa -> kontrol edilemiyor, devam et
         return true;
      }
      long fileSize = FileSize((int)fileHandle);
      FileClose((int)fileHandle);

      // Boyut kontrolu (+/- 512 byte tolerans)
      if(MathAbs(fileSize - EXPECTED_FILE_SIZE) > 512)
      {
         Print("[INTEGRITY] Dosya boyut uyumsuzlugu! Beklenen:", EXPECTED_FILE_SIZE, " Gercek:", fileSize);
         return false;
      }

      return true;
   }
}

//+------------------------------------------------------------------+
//| Lisans Durumlari                                                  |
//+------------------------------------------------------------------+
enum ENUM_LICENSE_STATUS
{
    LICENSE_VALID = 0,           // Gecerli lisans
    LICENSE_INVALID = 1,         // Gecersiz lisans
    LICENSE_EXPIRED = 2,         // Suresi dolmus
    LICENSE_REVOKED = 3,         // Iptal edilmis
    LICENSE_SUSPENDED = 4,       // Askiya alinmis
    LICENSE_ACCOUNT_MISMATCH = 5,// Hesap eslesmedi
    LICENSE_SERVER_ERROR = 6,    // Sunucu hatasi
    LICENSE_NO_CONNECTION = 7,   // Baglanti yok
    LICENSE_EMPTY = 8            // Lisans bos
};

//+------------------------------------------------------------------+
//| Lisans Yoneticisi Sinifi                                          |
//+------------------------------------------------------------------+
class CLicenseManager
{
private:
    string          m_licenseKey;           // Lisans anahtari
    string          m_brokerAccount;        // Broker hesap numarasi
    string          m_apiUrl;               // API URL
    bool            m_isValid;              // Lisans gecerli mi
    ENUM_LICENSE_STATUS m_status;           // Lisans durumu
    int             m_daysRemaining;        // Kalan gun
    int             m_hoursRemaining;       // Kalan saat
    string          m_customerName;         // Musteri adi
    string          m_endDate;              // Bitis tarihi
    int             m_maxSymbols;           // Max sembol sayisi
    datetime        m_lastCheck;            // Son kontrol zamani
    int             m_checkInterval;        // Kontrol araligi (saniye)
    string          m_lastError;            // Son hata mesaji
    int             m_failedAttempts;       // Basarisiz deneme sayisi
    int             m_maxFailedAttempts;    // Max basarisiz deneme
    bool            m_offlineMode;          // Offline mod aktif mi
    datetime        m_offlineExpiry;        // Offline mod bitis zamani
    datetime        m_cacheExpiry;          // Onbellek bitis zamani
    string          m_licenseType;          // Lisans tipi (hourly/daily/monthly)

public:
    //+------------------------------------------------------------------+
    //| Constructor                                                       |
    //+------------------------------------------------------------------+
    CLicenseManager()
    {
        m_licenseKey = "";
        m_brokerAccount = "";
        m_apiUrl = CryptoStr::GetApiUrl();  // v3.3.0: XOR sifreli
        m_isValid = false;
        m_status = LICENSE_EMPTY;
        m_daysRemaining = 0;
        m_hoursRemaining = 0;
        m_customerName = "";
        m_endDate = "";
        m_maxSymbols = 0;
        m_lastCheck = 0;
        m_checkInterval = 300;        // 5 dakika
        m_lastError = "";
        m_failedAttempts = 0;
        m_maxFailedAttempts = 3;
        m_offlineMode = false;
        m_offlineExpiry = 0;
        m_cacheExpiry = 0;
        m_licenseType = "";
    }

    //+------------------------------------------------------------------+
    //| Lisans sistemini baslat                                          |
    //+------------------------------------------------------------------+
    bool Init(string licenseKey, long brokerAccount)
    {
        // v3.3.0 B2c: Integrity check - dosya degistirilmis mi?
        if(!IntegrityCheck::Verify())
        {
            m_status = LICENSE_INVALID;
            m_isValid = false;
            m_lastError = "Dosya butunlugu dogrulanamadi";
            return false;
        }

        // Onceki durumu tamamen sifirla (EA tekrar yuklendiginde eski deger kalmasin)
        m_isValid = false;
        m_status = LICENSE_EMPTY;
        m_daysRemaining = 0;
        m_hoursRemaining = 0;
        m_customerName = "";
        m_endDate = "";
        m_maxSymbols = 0;
        m_lastCheck = 0;
        m_lastError = "";
        m_failedAttempts = 0;
        m_offlineMode = false;
        m_offlineExpiry = 0;
        m_cacheExpiry = 0;
        m_licenseType = "";

        // v3.3.0: API URL'yi sifreli kaynaktan yukle
        m_apiUrl = CryptoStr::GetApiUrl();

        m_licenseKey = licenseKey;
        m_brokerAccount = IntegerToString(brokerAccount);

        // Bosluk ve gorunmez karakterleri temizle
        StringTrimLeft(m_licenseKey);
        StringTrimRight(m_licenseKey);

        // Debug
        Print("[LICENSE] Girilen anahtar uzunluk: ", StringLen(m_licenseKey),
              " | Deger: '", m_licenseKey, "'");

        // Bos kontrol
        if(StringLen(m_licenseKey) < 10)
        {
            m_status = LICENSE_EMPTY;
            m_lastError = CryptoStr::GetEmptyError();  // v3.3.0: sifreli string
            PrintLicenseError();
            return false;
        }

        // Lisans format kontrolu: BTAI-XXXXX-XXXXX-XXXXX-XXXXX
        if(!ValidateKeyFormat(m_licenseKey))
        {
            m_status = LICENSE_INVALID;
            m_lastError = "Lisans formati hatali (" + CryptoStr::GetKeyPrefix() + "XXXXX-XXXXX-XXXXX-XXXXX)";
            PrintLicenseError();
            return false;
        }

        // Broker hesap kontrolu
        if(brokerAccount <= 0)
        {
            m_status = LICENSE_ACCOUNT_MISMATCH;
            m_lastError = "Gecersiz broker hesap numarasi";
            PrintLicenseError();
            return false;
        }

        // Her zaman once online dogrulama dene
        if(ValidateLicense())
        {
            return true;
        }

        // Online basarisiz olduysa ve baglanti sorunu varsa cache'e bak
        if(m_status == LICENSE_NO_CONNECTION || m_status == LICENSE_SERVER_ERROR)
        {
            if(LoadFromCache())
            {
                Print("[LICENSE] Baglanti sorunu - Onbellekten yuklendi - Kalan: ", m_daysRemaining, " gun ", m_hoursRemaining, " saat");
                m_offlineMode = true;
                return m_isValid;
            }
        }

        return false;
    }

    //+------------------------------------------------------------------+
    //| Lisans anahtar format dogrulama                                  |
    //| Format: BTAI-XXXXX-XXXXX-XXXXX-XXXXX (24 karakter + 4 tire)     |
    //+------------------------------------------------------------------+
    bool ValidateKeyFormat(string key)
    {
        // Minimum uzunluk: BTAI-XXXXX-XXXXX-XXXXX-XXXXX = 28+ karakter
        if(StringLen(key) < 28) return false;

        // BTAI- ile baslamali (v3.3.0: sifreli prefix)
        if(StringSubstr(key, 0, 5) != CryptoStr::GetKeyPrefix()) return false;

        // 4 tire olmali (BTAI-X-X-X-X)
        int dashCount = 0;
        for(int i = 0; i < StringLen(key); i++)
        {
            if(StringGetCharacter(key, i) == '-')
                dashCount++;
        }
        if(dashCount != 4) return false;

        return true;
    }

    //+------------------------------------------------------------------+
    //| Online lisans dogrulama                                          |
    //+------------------------------------------------------------------+
    bool ValidateLicense()
    {
        // API istegi olustur
        string postData = "action=validate";
        postData += "&license_key=" + UrlEncode(m_licenseKey);
        postData += "&broker_account=" + m_brokerAccount;
        postData += "&ea_version=" + EA_VERSION;
        postData += "&ea_name=BytamerFX";
        postData += "&mt5_build=" + IntegerToString(TerminalInfoInteger(TERMINAL_BUILD));
        postData += "&server_name=" + UrlEncode(AccountInfoString(ACCOUNT_SERVER));
        postData += "&symbol=" + _Symbol;

        char data[];
        char result[];
        string headers = "Content-Type: application/x-www-form-urlencoded\r\n";
        string resultHeaders;

        StringToCharArray(postData, data, 0, StringLen(postData));
        ArrayResize(data, StringLen(postData));

        int timeout = 10000; // 10 saniye
        int res = WebRequest("POST", m_apiUrl, headers, timeout, data, result, resultHeaders);

        if(res == -1)
        {
            int error = (int)GetLastError();
            m_lastError = "WebRequest hatasi: " + IntegerToString(error);
            m_failedAttempts++;

            Print("[LICENSE] Baglanti hatasi (Deneme: ", m_failedAttempts, "/", m_maxFailedAttempts, ")");
            Print("[LICENSE] MT5: Araclar -> Ayarlar -> Expert Advisors -> WebRequest icin izin ver");
            Print("[LICENSE] URL ekleyin: ", m_apiUrl);

            // Offline mod - v3.3.0: 24 saat → 4 saat (B2d sikilastirma)
            if(m_failedAttempts >= m_maxFailedAttempts && LoadFromCache())
            {
                m_offlineMode = true;
                m_offlineExpiry = TimeCurrent() + 14400; // 4 saat offline izin (v3.3.0)
                Print("[LICENSE] Offline mod aktif (4 saat)");
                return m_isValid;
            }

            m_status = LICENSE_NO_CONNECTION;
            return false;
        }

        // HTTP durum kodu kontrolu
        if(res != 200)
        {
            m_lastError = "HTTP hatasi: " + IntegerToString(res);
            m_status = LICENSE_SERVER_ERROR;
            return false;
        }

        // JSON yaniti parse et
        string response = CharArrayToString(result);
        return ParseResponse(response);
    }

    //+------------------------------------------------------------------+
    //| API yanitini parse et                                            |
    //+------------------------------------------------------------------+
    bool ParseResponse(string json)
    {
        // Basit JSON parser
        bool success = GetJsonBool(json, "success");
        string status = GetJsonString(json, "status");
        string message = GetJsonString(json, "message");

        Print("[LICENSE] API Response - success:", success, " status:", status);

        m_lastError = message;
        m_lastCheck = TimeCurrent();
        m_failedAttempts = 0;

        if(!success)
        {
            // Durum kodunu belirle
            if(status == "invalid")          m_status = LICENSE_INVALID;
            else if(status == "expired")     m_status = LICENSE_EXPIRED;
            else if(status == "revoked")     m_status = LICENSE_REVOKED;
            else if(status == "suspended")   m_status = LICENSE_SUSPENDED;
            else if(status == "account_mismatch") m_status = LICENSE_ACCOUNT_MISMATCH;
            else                             m_status = LICENSE_INVALID;

            m_isValid = false;
            PrintLicenseError();

            // Suresi dolan lisans icin cache'i temizle (eski lisans calisamaz)
            if(m_status == LICENSE_EXPIRED || m_status == LICENSE_REVOKED)
            {
                DeleteCache();
            }

            return false;
        }

        // Basarili - "active" veya "valid" kabul et
        if(status != "valid" && status != "active")
        {
            m_status = LICENSE_INVALID;
            m_isValid = false;
            m_lastError = "Beklenmeyen status: " + status;
            PrintLicenseError();
            return false;
        }

        m_isValid = true;
        m_status = LICENSE_VALID;

        // API flat veya nested ("data":{}) donebilir - her ikisini de destekle
        m_daysRemaining = (int)GetJsonInt(json, "days_remaining");
        m_endDate = GetJsonString(json, "end_date");
        m_maxSymbols = (int)GetJsonInt(json, "max_symbols");
        m_customerName = GetJsonString(json, "customer");
        m_hoursRemaining = (int)GetJsonInt(json, "hours_remaining");
        m_licenseType = GetJsonString(json, "license_type");

        // Eger license_type bos ise gun sayisina gore hesapla
        if(m_licenseType == "")
        {
            if(m_daysRemaining <= 1)       m_licenseType = "hourly";
            else if(m_daysRemaining <= 7)  m_licenseType = "daily";
            else                           m_licenseType = "monthly";
        }

        // Eger hours_remaining 0 ve days 0 ise end_date'den hesapla
        if(m_hoursRemaining == 0 && m_daysRemaining == 0 && m_endDate != "")
        {
            datetime endTime = StringToTime(m_endDate);
            if(endTime > TimeCurrent())
            {
                int diff = (int)(endTime - TimeCurrent());
                m_daysRemaining = diff / 86400;
                m_hoursRemaining = (diff % 86400) / 3600;
            }
        }

        // Periyodik kontrol araligi: her lisans tipi icin 5 dakika
        m_checkInterval = 300;  // 5 dakika

        // Onbellege kaydet
        SaveToCache();

        // Offline mod iptal (basarili online dogrulama)
        m_offlineMode = false;
        m_offlineExpiry = 0;

        Print("=== LISANS DOGRULANDI ===");
        Print("   Musteri: ", m_customerName);
        Print("   Bitis: ", m_endDate);
        Print("   Kalan: ", m_daysRemaining, " gun ", m_hoursRemaining, " saat");
        Print("   Max Sembol: ", m_maxSymbols);
        Print("   Lisans Tipi: ", m_licenseType);
        Print("   Sonraki Kontrol: ", m_checkInterval / 60, " dk");
        Print("========================");

        return true;
    }

    //+------------------------------------------------------------------+
    //| Periyodik kontrol (OnTick icinde cagrilacak)                     |
    //+------------------------------------------------------------------+
    bool CheckPeriodically()
    {
        // Henuz kontrol zamani gelmedi
        if(TimeCurrent() - m_lastCheck < m_checkInterval)
            return m_isValid;

        // Offline modda ve sure dolmadi
        if(m_offlineMode && TimeCurrent() < m_offlineExpiry)
            return m_isValid;

        // Offline mod suresi doldu - tekrar dogrula
        if(m_offlineMode && TimeCurrent() >= m_offlineExpiry)
        {
            Print("[LICENSE] Offline mod suresi doldu - Yeniden dogrulama...");
            m_offlineMode = false;
        }

        // Yeniden dogrula
        Print("[LICENSE] Periyodik lisans kontrolu...");
        bool result = ValidateLicense();

        if(!result && m_status == LICENSE_EXPIRED)
        {
            Print("[LICENSE] !!! LISANS SURESI DOLDU - EA DEVRE DISI !!!");
            m_isValid = false;
            DeleteCache();  // Eski lisans bir daha calisamaz
        }

        return m_isValid;
    }

    //+------------------------------------------------------------------+
    //| Getters                                                          |
    //+------------------------------------------------------------------+
    bool                IsValid()          const { return m_isValid; }
    ENUM_LICENSE_STATUS GetStatus()        const { return m_status; }
    int                 GetDaysRemaining() const { return m_daysRemaining; }
    int                 GetHoursRemaining()const { return m_hoursRemaining; }
    string              GetCustomerName()  const { return m_customerName; }
    string              GetLastError()     const { return m_lastError; }
    string              GetEndDate()       const { return m_endDate; }
    int                 GetMaxSymbols()    const { return m_maxSymbols; }
    bool                IsOfflineMode()    const { return m_offlineMode; }
    string              GetLicenseType()   const { return m_licenseType; }

    string GetLicenseKeyMasked() const
    {
        if(StringLen(m_licenseKey) > 14)
            return StringSubstr(m_licenseKey, 0, 9) + "..." + StringSubstr(m_licenseKey, StringLen(m_licenseKey) - 5, 5);
        return "****";
    }

    //+------------------------------------------------------------------+
    //| Durum mesaji al                                                  |
    //+------------------------------------------------------------------+
    string GetStatusMessage() const
    {
        switch(m_status)
        {
            case LICENSE_VALID:
                if(m_daysRemaining > 0)
                    return "Gecerli (" + IntegerToString(m_daysRemaining) + " gun)";
                else
                    return "Gecerli (" + IntegerToString(m_hoursRemaining) + " saat)";
            case LICENSE_INVALID:         return "Gecersiz lisans anahtari";
            case LICENSE_EXPIRED:         return "Lisans suresi dolmus";
            case LICENSE_REVOKED:         return "Lisans iptal edilmis";
            case LICENSE_SUSPENDED:       return "Lisans askiya alinmis";
            case LICENSE_ACCOUNT_MISMATCH:return "Broker hesabi eslesmedi";
            case LICENSE_SERVER_ERROR:    return "Sunucu hatasi";
            case LICENSE_NO_CONNECTION:   return "Baglanti kurulamadi";
            case LICENSE_EMPTY:           return "Lisans anahtari girilmemis";
            default:                      return "Bilinmeyen durum";
        }
    }

    //+------------------------------------------------------------------+
    //| Dashboard icin durum rengi                                       |
    //+------------------------------------------------------------------+
    color GetStatusColor() const
    {
        switch(m_status)
        {
            case LICENSE_VALID:           return clrLime;
            case LICENSE_EXPIRED:         return clrOrange;
            case LICENSE_REVOKED:
            case LICENSE_SUSPENDED:
            case LICENSE_INVALID:
            case LICENSE_ACCOUNT_MISMATCH:return clrRed;
            case LICENSE_SERVER_ERROR:
            case LICENSE_NO_CONNECTION:   return clrYellow;
            default:                      return clrGray;
        }
    }

    //+------------------------------------------------------------------+
    //| Lisans suresi yakinlik rengi                                     |
    //+------------------------------------------------------------------+
    color GetExpiryColor() const
    {
        if(!m_isValid)
            return clrRed;

        // 6 saatten az
        if(m_daysRemaining == 0 && m_hoursRemaining <= 6)
            return clrRed;

        // 1 gunden az
        if(m_daysRemaining == 0)
            return clrOrangeRed;

        // 2 gunden az
        if(m_daysRemaining <= 2)
            return clrOrange;

        // 7 gunden az
        if(m_daysRemaining <= 7)
            return clrYellow;

        // Normal
        return clrLime;
    }

private:
    //+------------------------------------------------------------------+
    //| URL encode                                                       |
    //+------------------------------------------------------------------+
    string UrlEncode(string text) const
    {
        string result = "";
        for(int i = 0; i < StringLen(text); i++)
        {
            ushort ch = StringGetCharacter(text, i);
            if((ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') ||
               (ch >= '0' && ch <= '9') || ch == '-' || ch == '_' || ch == '.')
            {
                result += CharToString((uchar)ch);
            }
            else
            {
                result += StringFormat("%%%02X", ch);
            }
        }
        return result;
    }

    //+------------------------------------------------------------------+
    //| JSON'dan string deger al                                         |
    //+------------------------------------------------------------------+
    string GetJsonString(string json, string key) const
    {
        string search = "\"" + key + "\":";
        int pos = StringFind(json, search);
        if(pos == -1) return "";

        pos += StringLen(search);

        // Bosluklari atla
        while(pos < StringLen(json) && StringGetCharacter(json, pos) == ' ')
            pos++;

        // null kontrolu
        if(StringSubstr(json, pos, 4) == "null")
            return "";

        // String mi?
        if(StringGetCharacter(json, pos) == '"')
        {
            pos++;
            int endPos = StringFind(json, "\"", pos);
            if(endPos == -1) return "";
            return StringSubstr(json, pos, endPos - pos);
        }

        // Sayi veya boolean
        int endPos = pos;
        while(endPos < StringLen(json))
        {
            ushort ch = StringGetCharacter(json, endPos);
            if(ch == ',' || ch == '}' || ch == ']') break;
            endPos++;
        }

        return StringSubstr(json, pos, endPos - pos);
    }

    //+------------------------------------------------------------------+
    //| JSON'dan int deger al                                            |
    //+------------------------------------------------------------------+
    long GetJsonInt(string json, string key) const
    {
        string value = GetJsonString(json, key);
        if(value == "") return 0;
        return StringToInteger(value);
    }

    //+------------------------------------------------------------------+
    //| JSON'dan bool deger al                                           |
    //+------------------------------------------------------------------+
    bool GetJsonBool(string json, string key) const
    {
        string value = GetJsonString(json, key);
        return (value == "true" || value == "1");
    }

    //+------------------------------------------------------------------+
    //| Onbellege kaydet                                                 |
    //+------------------------------------------------------------------+
    void SaveToCache()
    {
        string filename = CryptoStr::GetCachePrefix() + m_brokerAccount + ".dat";  // v3.3.0: sifreli
        int handle = FileOpen(filename, FILE_WRITE|FILE_BIN|FILE_COMMON);

        if(handle != INVALID_HANDLE)
        {
            // Hash olustur (manipulasyona karsi) - v3.3.0: server timestamp eklendi
            string data = m_licenseKey + "|" + m_brokerAccount + "|" +
                          IntegerToString(m_daysRemaining) + "|" +
                          IntegerToString(m_hoursRemaining) + "|" + m_endDate + "|" +
                          IntegerToString(TimeCurrent());  // saat geri almayi engeller
            string hash = GenerateHash(data);

            // Verileri yaz
            FileWriteString(handle, hash + "\n");
            FileWriteString(handle, IntegerToString(m_daysRemaining) + "\n");
            FileWriteString(handle, IntegerToString(m_hoursRemaining) + "\n");
            FileWriteString(handle, m_endDate + "\n");
            FileWriteString(handle, m_customerName + "\n");
            FileWriteString(handle, IntegerToString(m_maxSymbols) + "\n");
            FileWriteString(handle, m_licenseType + "\n");
            FileWriteString(handle, IntegerToString(TimeCurrent() + 14400) + "\n"); // v3.3.0: 4 saat gecerli (24→4)
            FileWriteString(handle, IntegerToString(TimeCurrent()) + "\n");  // v3.3.0: kayit zamani (anti-clockback)

            FileClose(handle);
        }
    }

    //+------------------------------------------------------------------+
    //| Onbellekten yukle                                                |
    //+------------------------------------------------------------------+
    bool LoadFromCache()
    {
        string filename = CryptoStr::GetCachePrefix() + m_brokerAccount + ".dat";  // v3.3.0: sifreli

        if(!FileIsExist(filename, FILE_COMMON))
            return false;

        int handle = FileOpen(filename, FILE_READ|FILE_TXT|FILE_COMMON);

        if(handle == INVALID_HANDLE)
            return false;

        // Verileri oku
        string savedHash = FileReadString(handle);
        string days = FileReadString(handle);
        string hours = FileReadString(handle);
        string endDate = FileReadString(handle);
        string customer = FileReadString(handle);
        string maxSymbols = FileReadString(handle);
        string licType = FileReadString(handle);
        string expiry = FileReadString(handle);
        string savedTimestamp = FileReadString(handle);  // v3.3.0: kayit zamani

        FileClose(handle);

        // Satir sonu karakterlerini temizle
        StringTrimRight(savedHash);
        StringTrimRight(days);
        StringTrimRight(hours);
        StringTrimRight(endDate);
        StringTrimRight(customer);
        StringTrimRight(maxSymbols);
        StringTrimRight(licType);
        StringTrimRight(expiry);
        StringTrimRight(savedTimestamp);

        // Cache suresi dolmus mu?
        if(StringToInteger(expiry) < TimeCurrent())
        {
            FileDelete(filename, FILE_COMMON);
            Print("[LICENSE] Cache suresi doldu - silindi");
            return false;
        }

        // v3.3.0 B2d: Anti-clockback - saat geri alinmis mi?
        datetime saveTime = (datetime)StringToInteger(savedTimestamp);
        if(saveTime > 0 && TimeCurrent() < saveTime - 300)  // 5dk tolerans
        {
            FileDelete(filename, FILE_COMMON);
            Print("[LICENSE] Saat geri alimi tespit edildi! Cache silindi.");
            return false;
        }

        // Hash dogrula (manipulasyona karsi) - v3.3.0: timestamp dahil
        string data = m_licenseKey + "|" + m_brokerAccount + "|" + days + "|" + hours + "|" + endDate + "|" + savedTimestamp;
        string expectedHash = GenerateHash(data);

        if(savedHash != expectedHash)
        {
            FileDelete(filename, FILE_COMMON);
            Print("[LICENSE] Cache hash eslesmedi - silindi (manipulasyon tespit)");
            return false;
        }

        // Verileri yukle
        m_daysRemaining = (int)StringToInteger(days);
        m_hoursRemaining = (int)StringToInteger(hours);
        m_endDate = endDate;
        m_customerName = customer;
        m_maxSymbols = (int)StringToInteger(maxSymbols);
        m_licenseType = licType;
        m_cacheExpiry = (datetime)StringToInteger(expiry);

        // Kalan gun kontrolu
        if(m_daysRemaining <= 0 && m_hoursRemaining <= 0)
        {
            m_isValid = false;
            m_status = LICENSE_EXPIRED;
            DeleteCache();
            return false;
        }

        m_isValid = true;
        m_status = LICENSE_VALID;
        m_lastCheck = TimeCurrent();

        return true;
    }

    //+------------------------------------------------------------------+
    //| Cache dosyasini sil                                              |
    //+------------------------------------------------------------------+
    void DeleteCache()
    {
        string filename = CryptoStr::GetCachePrefix() + m_brokerAccount + ".dat";  // v3.3.0: sifreli
        if(FileIsExist(filename, FILE_COMMON))
        {
            FileDelete(filename, FILE_COMMON);
            Print("[LICENSE] Cache silindi (suresi dolan lisans tekrar calisamaz)");
        }
    }

    //+------------------------------------------------------------------+
    //| DJB2 Hash olustur (manipulasyona karsi)                          |
    //+------------------------------------------------------------------+
    string GenerateHash(string data) const
    {
        ulong hash = 5381;
        for(int i = 0; i < StringLen(data); i++)
        {
            hash = ((hash << 5) + hash) + StringGetCharacter(data, i);
        }
        return IntegerToString(hash, 16);
    }

    //+------------------------------------------------------------------+
    //| Lisans hatasini yazdir                                           |
    //+------------------------------------------------------------------+
    void PrintLicenseError()
    {
        Print("============================================================");
        Print("   LISANS HATASI - BytamerFX EA DEVRE DISI");
        Print("============================================================");
        Print("   Durum: ", GetStatusMessage());
        Print("   Hata: ", m_lastError);
        Print("   Hesap: ", m_brokerAccount);
        Print("   Anahtar: ", GetLicenseKeyMasked());
        Print("============================================================");
        Print("   Destek: ", CryptoStr::GetSupportEmail());
        Print("   Telegram: @ByTamerAI_Support");
        Print("   Web: https://bytamer.com");
        Print("============================================================");
    }
};

//+------------------------------------------------------------------+
//| Global Lisans Nesnesi                                             |
//+------------------------------------------------------------------+
CLicenseManager g_LicenseManager;

//+------------------------------------------------------------------+
//| Global Fonksiyonlar (kolay erisim)                                |
//+------------------------------------------------------------------+
bool InitLicense(string licenseKey, long brokerAccount)
{
    return g_LicenseManager.Init(licenseKey, brokerAccount);
}

bool IsLicenseValid()
{
    return g_LicenseManager.IsValid();
}

bool CheckLicensePeriodically()
{
    return g_LicenseManager.CheckPeriodically();
}

string GetLicenseStatus()
{
    return g_LicenseManager.GetStatusMessage();
}

int GetLicenseDaysRemaining()
{
    return g_LicenseManager.GetDaysRemaining();
}

int GetLicenseHoursRemaining()
{
    return g_LicenseManager.GetHoursRemaining();
}

color GetLicenseStatusColor()
{
    return g_LicenseManager.GetStatusColor();
}

color GetLicenseExpiryColor()
{
    return g_LicenseManager.GetExpiryColor();
}

string GetLicenseEndDate()
{
    return g_LicenseManager.GetEndDate();
}

string GetLicenseCustomerName()
{
    return g_LicenseManager.GetCustomerName();
}

string GetLicenseKeyMasked()
{
    return g_LicenseManager.GetLicenseKeyMasked();
}

string GetLicenseType()
{
    return g_LicenseManager.GetLicenseType();
}

bool IsLicenseOffline()
{
    return g_LicenseManager.IsOfflineMode();
}

ENUM_LICENSE_STATUS GetLicenseStatusEnum()
{
    return g_LicenseManager.GetStatus();
}

//+------------------------------------------------------------------+

#endif
