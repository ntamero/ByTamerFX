//+------------------------------------------------------------------+
//|                                            LicenseManager.mqh    |
//|                        BytamerFX License Verification System     |
//|                                  Copyright 2026, By T@MER        |
//|                              https://www.bytamer.com             |
//+------------------------------------------------------------------+
//| Lisans Dogrulama Sistemi:                                        |
//| - Web API dogrulama (bytamer.com/api/license.php)                |
//| - Offline cache (24 saat)                                        |
//| - Periyodik kontrol (1 saat)                                     |
//| - Broker hesap eslestirme                                        |
//| - Sureli lisans (saatlik/gunluk)                                 |
//| - Eski suresi dolan lisans tekrar CALISMAZ                       |
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
        m_apiUrl = "https://bytamer.com/api/license.php";
        m_isValid = false;
        m_status = LICENSE_EMPTY;
        m_daysRemaining = 0;
        m_hoursRemaining = 0;
        m_customerName = "";
        m_endDate = "";
        m_maxSymbols = 0;
        m_lastCheck = 0;
        m_checkInterval = 3600;       // 1 saat
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
        m_licenseKey = licenseKey;
        m_brokerAccount = IntegerToString(brokerAccount);

        // Bos kontrol
        if(StringLen(m_licenseKey) < 10)
        {
            m_status = LICENSE_EMPTY;
            m_lastError = "Lisans anahtari bos veya cok kisa";
            PrintLicenseError();
            return false;
        }

        // Lisans format kontrolu: BTAI-XXXXX-XXXXX-XXXXX-XXXXX
        if(!ValidateKeyFormat(m_licenseKey))
        {
            m_status = LICENSE_INVALID;
            m_lastError = "Lisans formati hatali (BTAI-XXXXX-XXXXX-XXXXX-XXXXX)";
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
        // Minimum uzunluk: BTAI-XXXXX-XXXXX-XXXXX-XXXXX = 29 karakter
        if(StringLen(key) < 29) return false;

        // BTAI- ile baslamali
        if(StringSubstr(key, 0, 5) != "BTAI-") return false;

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

            // Offline mod
            if(m_failedAttempts >= m_maxFailedAttempts && LoadFromCache())
            {
                m_offlineMode = true;
                m_offlineExpiry = TimeCurrent() + 86400; // 24 saat offline izin
                Print("[LICENSE] Offline mod aktif (24 saat)");
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

        // Basarili - verileri al
        m_isValid = true;
        m_status = LICENSE_VALID;
        m_daysRemaining = (int)GetJsonInt(json, "days_remaining");
        m_hoursRemaining = (int)GetJsonInt(json, "hours_remaining");
        m_maxSymbols = (int)GetJsonInt(json, "max_symbols");
        m_endDate = GetJsonString(json, "end_date");
        m_customerName = GetJsonString(json, "customer");
        m_licenseType = GetJsonString(json, "license_type");

        // Periyodik kontrol araligi: saatlik lisans = 30dk, gunluk = 1 saat
        if(m_licenseType == "hourly")
            m_checkInterval = 1800;  // 30 dakika
        else
            m_checkInterval = 3600;  // 1 saat

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
        string filename = "bytamerfx_license_" + m_brokerAccount + ".dat";
        int handle = FileOpen(filename, FILE_WRITE|FILE_BIN|FILE_COMMON);

        if(handle != INVALID_HANDLE)
        {
            // Hash olustur (manipulasyona karsi)
            string data = m_licenseKey + "|" + m_brokerAccount + "|" +
                          IntegerToString(m_daysRemaining) + "|" +
                          IntegerToString(m_hoursRemaining) + "|" + m_endDate;
            string hash = GenerateHash(data);

            // Verileri yaz
            FileWriteString(handle, hash + "\n");
            FileWriteString(handle, IntegerToString(m_daysRemaining) + "\n");
            FileWriteString(handle, IntegerToString(m_hoursRemaining) + "\n");
            FileWriteString(handle, m_endDate + "\n");
            FileWriteString(handle, m_customerName + "\n");
            FileWriteString(handle, IntegerToString(m_maxSymbols) + "\n");
            FileWriteString(handle, m_licenseType + "\n");
            FileWriteString(handle, IntegerToString(TimeCurrent() + 86400) + "\n"); // 24 saat gecerli

            FileClose(handle);
        }
    }

    //+------------------------------------------------------------------+
    //| Onbellekten yukle                                                |
    //+------------------------------------------------------------------+
    bool LoadFromCache()
    {
        string filename = "bytamerfx_license_" + m_brokerAccount + ".dat";

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

        // Cache suresi dolmus mu?
        if(StringToInteger(expiry) < TimeCurrent())
        {
            FileDelete(filename, FILE_COMMON);
            Print("[LICENSE] Cache suresi doldu - silindi");
            return false;
        }

        // Hash dogrula (manipulasyona karsi)
        string data = m_licenseKey + "|" + m_brokerAccount + "|" + days + "|" + hours + "|" + endDate;
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
        string filename = "bytamerfx_license_" + m_brokerAccount + ".dat";
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
        Print("   Destek: info@bytamer.com");
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
