"""
MIA v5.2.0 — BytamerFX Config
Coklu-Ajan Otonom Forex Sistemi
Copyright 2026, By T@MER — https://www.bytamer.com
"""
import os
from pathlib import Path

# .env dosyasindan hassas bilgileri yukle
_env_path = Path(__file__).parent / ".env"
if _env_path.exists():
    for line in _env_path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            k, v = line.split("=", 1)
            key, val = k.strip(), v.strip()
            # Bos system env var'i override et (.env oncelikli)
            if val and not os.environ.get(key):
                os.environ[key] = val

# ─── ANTHROPIC ────────────────────────────────────────────
ANTHROPIC_API_KEY = os.environ.get("ANTHROPIC_API_KEY", "")

# ─── MODEL KONFIGURASYONU ────────────────────────────────
# Master Agent: Sonnet (karar verme)
# Strategy Agent: Sonnet (sembol bazli strateji)
MASTER_MODEL   = "claude-sonnet-4-6"
STRATEGY_MODEL = "claude-sonnet-4-6"
CLAUDE_MODEL   = MASTER_MODEL  # Geriye uyumluluk

# ─── MT5 ──────────────────────────────────────────────────
MT5_LOGIN    = int(os.environ.get("MT5_LOGIN", "0"))
MT5_PASSWORD = os.environ.get("MT5_PASSWORD", "")
MT5_SERVER   = os.environ.get("MT5_SERVER", "")
MT5_PATH     = r"C:\Program Files\MetaTrader 5\terminal64.exe"
MT5_MAGIC    = 20260217

# Broker sembol suffix — Exness: "m" → EURUSDm
BROKER_SUFFIX = "m"

# ─── TELEGRAM ─────────────────────────────────────────────
TELEGRAM_TOKEN    = os.environ.get("TELEGRAM_TOKEN", "")
TELEGRAM_CHAT_ID  = int(os.environ.get("TELEGRAM_CHAT_ID", "0"))
TELEGRAM_USER_IDS = [
    -1003212753244,   # Grup
    1210624972,       # T@MER
]
TELEGRAM_ENABLED  = True

# ─── SEMBOLLER ────────────────────────────────────────────
ALL_SYMBOLS    = ["BTCUSD", "XAGUSD", "XAUUSD", "GBPUSD", "USDJPY", "EURUSD", "AUDUSD"]
DEFAULT_ACTIVE = []   # Bos = Telegram /ac ile baslat

SYMBOL_ALIASES = {
    "BTC": "BTCUSD", "XAG": "XAGUSD", "XAU": "XAUUSD",
    "GOLD": "XAUUSD", "ALTIN": "XAUUSD", "GUMUS": "XAGUSD", "SILVER": "XAGUSD",
    "GBP": "GBPUSD", "JPY": "USDJPY", "EUR": "EURUSD", "AUD": "AUDUSD",
    "BTCUSDM": "BTCUSD", "XAUUSDM": "XAUUSD", "EURUSDM": "EURUSD", "GBPUSDM": "GBPUSD",
}

# ─── SEMBOL OZELLIKLERI ───────────────────────────────────
SYMBOL_SPECS = {
    "BTCUSD": {"pip": 1.0,    "contract": 1.0,      "digits": 2, "class": "crypto"},
    "XAGUSD": {"pip": 0.001,  "contract": 5000.0,   "digits": 3, "class": "metal"},
    "XAUUSD": {"pip": 0.01,   "contract": 100.0,    "digits": 2, "class": "metal"},
    "GBPUSD": {"pip": 0.0001, "contract": 100000.0, "digits": 5, "class": "major"},
    "USDJPY": {"pip": 0.01,   "contract": 100000.0, "digits": 3, "class": "major"},
    "EURUSD": {"pip": 0.0001, "contract": 100000.0, "digits": 5, "class": "major"},
    "AUDUSD": {"pip": 0.0001, "contract": 100000.0, "digits": 5, "class": "major"},
}

# ─── HESAP ────────────────────────────────────────────────
INITIAL_BALANCE    = 100.0   # Gercek hesap bakiyesi fallback ($100)
MIN_BALANCE_FLOOR  = 50.0
MAX_ACCOUNT_DD_PCT = 99.0     # DEVRE DISI — SPM sistemi yonetir
LEVERAGE           = 2000

# ─── CALISMA ZAMAN DILIMI ────────────────────────────────
PRIMARY_TF = "M15"   # Giris sinyali
TREND_TF   = "H1"    # Trend filtresi
UPPER_TF   = "H4"    # Ust trend

# ─── SPREAD KURALI (%15 HARD LIMIT) ──────────────────────
SPREAD_MAX_RATIO    = 1.15
SPREAD_CHECK_BYPASS = False

# ─── DINAMIK LOT ─────────────────────────────────────────
LOT_DYNAMIC         = True
LOT_RISK_PCT        = 0.5
MIN_LOT             = 0.01
MAX_LOT_PER_SYMBOL  = 0.05
MAX_TOTAL_LOTS      = 0.20

# ─── HARD LIMITLER ───────────────────────────────────────
MAX_LOSS_PER_POSITION  = 99999.0  # DEVRE DISI — SPM sistemi yonetir, zorla kapatma YOK
CLAUDE_HARD_LIMITS = {
    "max_positions_total":     10,
    "max_positions_per_sym":   4,
    "min_risk_reward":         1.5,
    "max_correlated_exposure": 0.60,
    "news_blackout_minutes":   15,
    "max_daily_loss_pct":      99.0,    # DEVRE DISI — SPM yonetir
    "emergency_close_dd":      99.0,    # DEVRE DISI — zorla kapatma YOK
}

# ─── HABER / BAGLAM ─────────────────────────────────────
NEWS_FETCH_INTERVAL = 900
MARKET_CONTEXT_URL  = "https://api.alternative.me/fng/"

# ─── LOG ─────────────────────────────────────────────────
LOG_FILE  = "fx_agent.log"
LOG_LEVEL = "INFO"

# ─── TREND ONAY ──────────────────────────────────────────
TREND_CONFIRM_COUNT = 3   # Kac bar ust uste trend onaylamali

# ═══════════════════════════════════════════════════════════
# MIA v4.0 YENI KONFIGURASYONLAR
# ═══════════════════════════════════════════════════════════

# ─── AJAN INTERVALLERI ───────────────────────────────────
SPEED_AGENT_INTERVAL    = 1.0      # saniye — her tick
STRATEGY_AGENT_INTERVAL = 120      # saniye — 2 dakikada bir Brain guncelleme
MASTER_AGENT_INTERVAL   = 600      # saniye — 10 dakikada bir portfoy
SENTIMENT_INTERVAL      = 300      # saniye — 5 dakika
RISK_AGENT_INTERVAL     = 1.0      # saniye — her tick

# ─── STRATEGY AGENT ──────────────────────────────────────
STRATEGY_MAX_TOKENS     = 400      # Daha kisa yanit = daha hizli API donus
STRATEGY_TEMPERATURE    = 0.1      # Dusuk = tutarli, deterministik kararlar
STRATEGY_MIN_CONFIDENCE = 65       # Minimum guven yuzesi — dusuk esik anlamsiz giris yapiyor

# ─── MASTER AGENT ────────────────────────────────────────
MASTER_MAX_TOKENS       = 1200     # Opus response limiti
MASTER_TEMPERATURE      = 0.2      # Cok dusuk = en tutarli
MASTER_LOT_MULTIPLIER_RANGE = (0.1, 1.5)  # Min/max lot carpani

# ─── SINYAL ESIKLERI ─────────────────────────────────────
SIGNAL_BASE_THRESHOLD   = 55       # Yeni baz esik (eskisi 40)
SIGNAL_MIN_THRESHOLD    = 40       # Alt sinir
SIGNAL_MAX_THRESHOLD    = 80       # Ust sinir
FAST_ENTRY_THRESHOLD    = 75       # Speed Agent hizli giris esigi — 70 cok dusuktu

# ─── MARKET REGIME ───────────────────────────────────────
REGIME_STRONG_TREND_ADX  = 30      # ADX > 30 = strong trend
REGIME_TREND_ADX         = 20      # ADX > 20 = trend
REGIME_CHOPPY_ADX        = 15      # ADX < 15 = choppy
REGIME_VOLATILE_ATR_PCT  = 80      # ATR percentile > 80 = volatile

REGIME_MULTIPLIERS = {
    "STRONG_TREND": 1.2,
    "TREND":        1.0,
    "RANGE":        0.7,
    "VOLATILE":     0.8,
    "CHOPPY":       0.5,
}

# ─── KORELASYON MATRISI ──────────────────────────────────
CORRELATION_PAIRS = {
    ("EURUSD", "GBPUSD"):  0.85,
    ("EURUSD", "AUDUSD"):  0.70,
    ("EURUSD", "USDJPY"): -0.60,
    ("GBPUSD", "AUDUSD"):  0.65,
    ("XAUUSD", "XAGUSD"):  0.90,
    ("BTCUSD", "XAUUSD"):  0.30,
    ("XAUUSD", "EURUSD"):  0.40,
}

# ─── SESSION PROFILLERI ──────────────────────────────────
SESSION_PROFILES = {
    "TOKYO":              {"aggression": 0.6, "max_pos": 3, "description": "Dusuk likidite"},
    "LONDON":             {"aggression": 1.0, "max_pos": 6, "description": "Yuksek likidite"},
    "NEW_YORK":           {"aggression": 0.9, "max_pos": 5, "description": "Yuksek volatilite"},
    "LONDON_NY_OVERLAP":  {"aggression": 1.2, "max_pos": 7, "description": "Maksimum likidite"},
    "TOKYO_LONDON_OVERLAP": {"aggression": 0.8, "max_pos": 4, "description": "Orta likidite"},
    "OFF_HOURS":          {"aggression": 0.3, "max_pos": 2, "description": "Minimum islem"},
}

# ─── HAYATTA KALMA MEKANIZMALARI ─────────────────────────
EQUITY_CURVE_EMA_PERIOD  = 20     # Equity EMA periyodu
EQUITY_CURVE_PAUSE_PCT   = 99.0   # DEVRE DISI — SPM sistemi yonetir
EQUITY_CURVE_EMERGENCY   = 99.0   # DEVRE DISI — zorla kapatma YOK

LOSING_STREAK_LOT_REDUCE = 5      # 5 ardisik kayip = lot %50 azalt
LOSING_STREAK_STOP       = 10     # 10 ardisik kayip = trading DURDUR
WINNING_STREAK_LOT_BOOST = 5      # 5 ardisik kazanc = lot %30 artir

# Adaptif lot carpanlari
ADAPTIVE_LOT = {
    "win_rate_high":    {"threshold": 70, "multiplier": 1.3},  # WR > %70 = 1.3x
    "win_rate_low":     {"threshold": 30, "multiplier": 0.5},  # WR < %30 = 0.5x
    "dd_warning":       {"threshold": 20, "multiplier": 0.7},  # DD > %20 = 0.7x
    "dd_danger":        {"threshold": 35, "multiplier": 0.5},  # DD > %35 = 0.5x
    "dd_critical":      {"threshold": 50, "multiplier": 0.3},  # DD > %50 = 0.3x (durma, kucuk lotla devam)
}

# ─── PEAK DROP ATR-ADAPTIF ───────────────────────────────
PEAK_DROP_MAIN_BASE     = 25      # MAIN: baz %25
PEAK_DROP_SPM_BASE      = 35      # SPM: baz %35
PEAK_DROP_ATR_FACTOR    = 0.5     # ATR percentile > 50 → esik artir
PEAK_PROFIT_MIN         = 0.50    # Minimum peak profit ($)

# ─── COOLDOWN ────────────────────────────────────────────
TRADE_COOLDOWN_SECONDS  = 60      # Ayni sembol yeniden acma bekleme
BRAIN_COOLDOWN_SECONDS  = 10      # Brain cagrilari arasi min bekleme

# ─── SENTIMENT KAYNAKLARI ────────────────────────────────
SENTIMENT_WEIGHTS = {
    "fear_greed":  0.20,
    "news":        0.35,
    "rss":         0.25,
    "dxy":         0.20,
}
RSS_FEEDS = [
    "https://www.investing.com/rss/news.rss",
]
DXY_SYMBOL = "DX.f"   # MT5'te DXY sembol adi (broker'a gore degisir)

# ─── CANDLE PATTERN SKORLARI ─────────────────────────────
PATTERN_SCORES = {
    "bullish_engulfing":  10,
    "bearish_engulfing":  10,
    "pin_bar":            8,
    "morning_star":       12,
    "evening_star":       12,
    "inside_bar":         5,
    "doji_reversal":      6,
    "three_soldiers":     15,
    "three_crows":        15,
    "hammer":             7,
    "shooting_star":      7,
    "tweezer_top":        6,
    "tweezer_bottom":     6,
}

# ═══════════════════════════════════════════════════════════
# MIA v5.0 — EA ENTEGRASYON KONFİGÜRASYONLARI
# BytamerFX EA (v3.8.0) grid/FIFO/cascade sistemi
# ═══════════════════════════════════════════════════════════

# ─── GRID SİSTEMİ ──────────────────────────────────────────
GRID_ENABLED            = True
GRID_WARMUP_SEC         = 10       # Başlangıçta SPM bekleme (hızlı aktif)
GRID_TREND_CHECK_SEC    = 60       # H1 trend kontrol aralığı (sn)
GRID_TREND_CONFIRM      = 2        # Trend değişimi onay bar sayısı
GRID_ENABLE_BIDIR       = True     # Bi-directional grid modu
GRID_LOT_REDUCTION      = 0.03    # Katman başı lot azaltma (%3)
GRID_NEWS_WIDEN_PCT     = 50       # Haber yakınında grid aralığı genişletme (%50)

# ─── KADEMELİ RİSK (CASCADE) ──────────────────────────────
DCA_COOLDOWN_SEC        = 120      # DCA açma arası bekleme
DCA_DISTANCE_ATR        = 2.0      # DCA mesafesi (ATR çarpanı)
DCA_MAX_PER_POSITION    = 1        # Max DCA sayısı
HEDGE_RATIO_TRIGGER     = 2.0      # BUY/SELL lot oranı > bu → hedge
HEDGE_FILL_PCT          = 0.70     # Hedge: karşı yön %70
HEDGE_COOLDOWN_SEC      = 120      # Hedge açma arası bekleme

# ─── DEADLOCK TESPİTİ ──────────────────────────────────────
DEADLOCK_CHECK_SEC      = 30       # Kontrol aralığı
DEADLOCK_TIMEOUT_SEC    = 300      # 5dk değişim yok → uyarı
DEADLOCK_MIN_CHANGE     = 0.50     # Min $ değişim eşiği

# ─── v3.8.0 SAFETY SHIELD ─────────────────────────────────
# Equity koruma: equity < %30 bakiye → TÜM KAPAT
EQUITY_EMERGENCY_PCT    = 1.0      # DEVRE DISI (sadece margin call seviyesinde) — SPM yonetir
# Margin koruma: margin < %150 → TÜM KAPAT, < %300 → SPM/DCA engelle
MARGIN_EMERGENCY_PCT    = 20.0     # Sadece gercek margin call yakininda (broker zaten kapatir)
MARGIN_GUARD_PCT        = 300.0    # SPM/DCA/HEDGE açmak için minimum margin %
# Sembol toplam kayıp: toplam PnL > -%50 bakiye → o sembol TÜM KAPAT
SYMBOL_MAX_LOSS_PCT     = 99.0     # DEVRE DISI — SPM sistemi yonetir
# HEDGE deadlock: max süre + max kayıp
HEDGE_MAX_TIME_SEC      = 600      # 10 dakika
HEDGE_MAX_LOSS_PCT      = 99.0     # DEVRE DISI — SPM sistemi yonetir
# HEDGE yön koruma: ADX >= 30 + trend = ANA yönü → HEDGE açılmaz
HEDGE_TREND_BLOCK_ADX   = 30.0

# ─── HABER YÖNETİCİSİ ─────────────────────────────────────
NEWS_ENABLED            = True
NEWS_BLOCK_BEFORE_MIN   = 20       # Haber öncesi trade blok (dk)
NEWS_BLOCK_AFTER_MIN    = 5        # Haber sonrası blok (dk)
NEWS_ALERT_BEFORE_MIN   = 30       # Uyarı süresi (dk)

# ─── FIFO NET HEDEF ────────────────────────────────────────
FIFO_NET_TARGET_DEFAULT = 5.0      # Profil tarafından override edilir

# ─── MİLİSANİYE MİMARİSİ — Karar Önbelleği ────────────────────────
DECISION_CACHE_TTL      = 90       # Brain kararı 90sn geçerli (hız ↑)
FAST_ENTRY_CACHED_SCORE = 60       # Önbellekli modda yeterli skor (daha duyarlı)
FAST_ENTRY_CACHED_ADX   = 18       # Önbellekli modda yeterli ADX
FAST_ENTRY_ADX_MIN      = 22       # Önbelleksiz modda min ADX (fırsat kaçırma ↓)

# ─── MIN LOT OVERRIDES (kullanıcı tercihi) ─────────────────
MIN_LOT_OVERRIDES = {
    "BTCUSD": 0.01,
    "XAUUSD": 0.01,
    "XAGUSD": 0.01,
    "GBPUSD": 0.04,
    "USDJPY": 0.04,
    "EURUSD": 0.04,
    "AUDUSD": 0.04,
}

# ─── VOLATİLİTE REJİMLERİ (Grid aralığı) ──────────────────
VOLATILITY_REGIMES = {
    "LOW":     {"atr_ratio_max": 0.8,  "grid_mult": 1.0},
    "NORMAL":  {"atr_ratio_max": 1.5,  "grid_mult": 1.5},
    "HIGH":    {"atr_ratio_max": 2.5,  "grid_mult": 2.0},
    "EXTREME": {"atr_ratio_max": 999,  "grid_mult": 0.0},  # Grid bloke
}

# ─── DISCORD (opsiyonel) ────────────────────────────────────
DISCORD_WEBHOOK_URL     = os.environ.get("DISCORD_WEBHOOK_URL", "")
DISCORD_ENABLED         = bool(DISCORD_WEBHOOK_URL)

# Runtime aktif semboller (main.py gunceller)
SYMBOLS = list(DEFAULT_ACTIVE)
