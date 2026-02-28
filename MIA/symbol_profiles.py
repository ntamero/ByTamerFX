"""
MIA v5.0 — Symbol Profiles
BytamerFX EA Config.mqh'den port edildi (v3.8.0)

Her varlık sınıfı için özel grid/FIFO/cascading risk parametreleri.
10 profil: FOREX, FOREX_JPY, SILVER, GOLD, CRYPTO_BTC, CRYPTO_ALT,
           INDICES, ENERGY, METAL, DEFAULT

Kullanım:
    from symbol_profiles import get_symbol_profile
    profile = get_symbol_profile("XAUUSD")

Copyright 2026, By T@MER — https://www.bytamer.com
"""

from dataclasses import dataclass


@dataclass
class SymbolProfile:
    """Sembol/varlık sınıfı bazlı grid ve pozisyon yönetimi parametreleri."""

    profile_name: str

    # ── Lot ──
    min_lot: float              # Profil bazlı minimum lot (0 = broker default)

    # ── Kâr eşikleri ($) ──
    min_close_profit: float     # Min kapatma kârı (spread maliyetini karşılamalı)
    ana_close_profit: float     # ANA tek başına kârda iken kapatma hedefi

    # ── SPM / Grid tetikleri ($) ──
    spm_trigger_loss: float     # ANA kayıp → SPM1 tetik
    spm2_trigger_loss: float    # SPM1 kayıp → SPM2 tetik
    spm_close_profit: float     # SPM kâr hedefi (TP1)
    fifo_net_target: float      # FIFO net hedef

    # ── SPM katman limitleri ──
    spm_max_buy_layers: int
    spm_max_sell_layers: int
    spm_lot_base: float         # SPM lot çarpanı (1.0 = ANA lot ile aynı)
    spm_lot_increment: float    # Katman başı lot artışı
    spm_lot_cap: float          # Max çarpan
    spm_cooldown_sec: int       # SPM açma arası bekleme (sn)

    # ── DCA ──
    dca_distance_atr: float     # DCA mesafesi (ATR çarpanı)
    profit_target_per_pos: float  # Pozisyon başı kâr hedefi

    # ── Hedge ──
    hedge_min_spm_count: int    # Hedge için minimum SPM sayısı
    hedge_min_loss_usd: float   # Hedge için minimum toplam kayıp ($)
    rescue_hedge_threshold: float  # SPM2 kayıp eşiği → rescue hedge ($)
    rescue_hedge_lot_mult: float   # Rescue hedge lot çarpanı

    # ── TP (pips) — trend gücüne göre ──
    tp_weak_pips: float         # Zayıf trend TP
    tp_moderate_pips: float     # Orta trend TP
    tp_strong_pips: float       # Güçlü trend TP

    # ── Bi-Directional Grid ──
    grid_atr_mult_low: float    # Düşük volatilite grid ATR çarpanı
    grid_atr_mult_normal: float # Normal volatilite
    grid_atr_mult_high: float   # Yüksek volatilite

    # ── Mum dönüşü TP ($) — trend gücüne göre ──
    candle_close_weak: float    # Zayıf trend min kâr
    candle_close_moderate: float
    candle_close_strong: float

    # ── Trend TP çarpanları ──
    trend_close_mult_moderate: float
    trend_close_mult_strong: float
    trend_confirm_bars: int     # Trend değişimi onay bar sayısı


# =====================================================================
# 10 PROFIL FABRIKA FONKSİYONLARI
# EA Config.mqh v3.8.0'dan birebir port
# =====================================================================

def _forex() -> SymbolProfile:
    """FOREX (EURUSD, GBPUSD, AUDUSD vb. — JPY hariç)"""
    return SymbolProfile(
        profile_name="FOREX",
        min_lot=0.01,
        min_close_profit=2.0,
        ana_close_profit=5.0,
        spm_trigger_loss=-4.0,
        spm2_trigger_loss=-5.0,
        spm_close_profit=3.0,
        fifo_net_target=5.0,
        spm_max_buy_layers=1,
        spm_max_sell_layers=1,
        spm_lot_base=1.0,
        spm_lot_increment=0.1,
        spm_lot_cap=1.5,
        spm_cooldown_sec=20,
        dca_distance_atr=2.0,
        profit_target_per_pos=3.0,
        hedge_min_spm_count=1,
        hedge_min_loss_usd=-5.0,
        rescue_hedge_threshold=-7.0,
        rescue_hedge_lot_mult=1.3,
        tp_weak_pips=30.0,
        tp_moderate_pips=60.0,
        tp_strong_pips=100.0,
        grid_atr_mult_low=1.0,
        grid_atr_mult_normal=1.5,
        grid_atr_mult_high=2.0,
        candle_close_weak=1.50,
        candle_close_moderate=3.00,
        candle_close_strong=5.00,
        trend_close_mult_moderate=1.3,
        trend_close_mult_strong=1.8,
        trend_confirm_bars=2,
    )


def _forex_jpy() -> SymbolProfile:
    """FOREX JPY pariteleri (USDJPY, GBPJPY, EURJPY vb.)"""
    return SymbolProfile(
        profile_name="FOREX_JPY",
        min_lot=0.01,
        min_close_profit=2.0,
        ana_close_profit=5.0,
        spm_trigger_loss=-4.0,
        spm2_trigger_loss=-5.0,
        spm_close_profit=3.0,
        fifo_net_target=5.0,
        spm_max_buy_layers=1,
        spm_max_sell_layers=1,
        spm_lot_base=1.0,
        spm_lot_increment=0.1,
        spm_lot_cap=1.5,
        spm_cooldown_sec=20,
        dca_distance_atr=2.0,
        profit_target_per_pos=3.0,
        hedge_min_spm_count=1,
        hedge_min_loss_usd=-5.0,
        rescue_hedge_threshold=-7.0,
        rescue_hedge_lot_mult=1.3,
        tp_weak_pips=40.0,
        tp_moderate_pips=80.0,
        tp_strong_pips=130.0,
        grid_atr_mult_low=1.0,
        grid_atr_mult_normal=1.5,
        grid_atr_mult_high=2.0,
        candle_close_weak=1.50,
        candle_close_moderate=3.00,
        candle_close_strong=5.00,
        trend_close_mult_moderate=1.3,
        trend_close_mult_strong=1.8,
        trend_confirm_bars=2,
    )


def _silver() -> SymbolProfile:
    """GÜMÜŞ (XAG)"""
    return SymbolProfile(
        profile_name="SILVER_XAG",
        min_lot=0.01,
        min_close_profit=2.5,
        ana_close_profit=7.0,
        spm_trigger_loss=-7.0,
        spm2_trigger_loss=-7.0,
        spm_close_profit=5.0,
        fifo_net_target=5.0,
        spm_max_buy_layers=1,
        spm_max_sell_layers=1,
        spm_lot_base=1.0,
        spm_lot_increment=0.1,
        spm_lot_cap=1.5,
        spm_cooldown_sec=20,
        dca_distance_atr=2.0,
        profit_target_per_pos=4.0,
        hedge_min_spm_count=1,
        hedge_min_loss_usd=-5.0,
        rescue_hedge_threshold=-7.0,
        rescue_hedge_lot_mult=1.3,
        tp_weak_pips=20.0,
        tp_moderate_pips=50.0,
        tp_strong_pips=80.0,
        grid_atr_mult_low=1.0,
        grid_atr_mult_normal=1.5,
        grid_atr_mult_high=2.0,
        candle_close_weak=2.00,
        candle_close_moderate=4.00,
        candle_close_strong=6.00,
        trend_close_mult_moderate=1.3,
        trend_close_mult_strong=1.8,
        trend_confirm_bars=2,
    )


def _gold() -> SymbolProfile:
    """ALTIN (XAU)"""
    return SymbolProfile(
        profile_name="GOLD_XAU",
        min_lot=0.01,
        min_close_profit=2.5,
        ana_close_profit=7.0,
        spm_trigger_loss=-7.0,
        spm2_trigger_loss=-7.0,
        spm_close_profit=5.0,
        fifo_net_target=5.0,
        spm_max_buy_layers=1,
        spm_max_sell_layers=1,
        spm_lot_base=1.0,
        spm_lot_increment=0.1,
        spm_lot_cap=1.5,
        spm_cooldown_sec=25,
        dca_distance_atr=2.0,
        profit_target_per_pos=4.0,
        hedge_min_spm_count=1,
        hedge_min_loss_usd=-5.0,
        rescue_hedge_threshold=-7.0,
        rescue_hedge_lot_mult=1.3,
        tp_weak_pips=50.0,
        tp_moderate_pips=120.0,
        tp_strong_pips=200.0,
        grid_atr_mult_low=1.0,
        grid_atr_mult_normal=1.5,
        grid_atr_mult_high=2.0,
        candle_close_weak=2.00,
        candle_close_moderate=4.00,
        candle_close_strong=7.00,
        trend_close_mult_moderate=1.3,
        trend_close_mult_strong=1.8,
        trend_confirm_bars=2,
    )


def _crypto_btc() -> SymbolProfile:
    """BITCOIN (BTC)"""
    return SymbolProfile(
        profile_name="CRYPTO_BTC",
        min_lot=0.01,
        min_close_profit=3.0,
        ana_close_profit=8.0,
        spm_trigger_loss=-5.0,
        spm2_trigger_loss=-5.0,
        spm_close_profit=3.0,
        fifo_net_target=5.0,
        spm_max_buy_layers=2,
        spm_max_sell_layers=2,
        spm_lot_base=1.0,
        spm_lot_increment=0.1,
        spm_lot_cap=1.5,
        spm_cooldown_sec=10,
        dca_distance_atr=2.0,
        profit_target_per_pos=5.0,
        hedge_min_spm_count=1,
        hedge_min_loss_usd=-5.0,
        rescue_hedge_threshold=-8.0,
        rescue_hedge_lot_mult=1.3,
        tp_weak_pips=15000.0,
        tp_moderate_pips=30000.0,
        tp_strong_pips=50000.0,
        grid_atr_mult_low=1.0,
        grid_atr_mult_normal=1.5,
        grid_atr_mult_high=2.0,
        candle_close_weak=3.00,
        candle_close_moderate=5.00,
        candle_close_strong=8.00,
        trend_close_mult_moderate=1.3,
        trend_close_mult_strong=1.8,
        trend_confirm_bars=2,
    )


def _crypto_alt() -> SymbolProfile:
    """DİĞER KRİPTO (ETH, LTC, XRP, DOGE, SOL vb.)"""
    return SymbolProfile(
        profile_name="CRYPTO_ALT",
        min_lot=0.01,
        min_close_profit=2.5,
        ana_close_profit=7.0,
        spm_trigger_loss=-7.0,
        spm2_trigger_loss=-7.0,
        spm_close_profit=5.0,
        fifo_net_target=5.0,
        spm_max_buy_layers=1,
        spm_max_sell_layers=1,
        spm_lot_base=1.0,
        spm_lot_increment=0.1,
        spm_lot_cap=1.5,
        spm_cooldown_sec=30,
        dca_distance_atr=2.5,
        profit_target_per_pos=4.0,
        hedge_min_spm_count=1,
        hedge_min_loss_usd=-5.0,
        rescue_hedge_threshold=-7.0,
        rescue_hedge_lot_mult=1.3,
        tp_weak_pips=5000.0,
        tp_moderate_pips=10000.0,
        tp_strong_pips=18000.0,
        grid_atr_mult_low=1.0,
        grid_atr_mult_normal=1.5,
        grid_atr_mult_high=2.0,
        candle_close_weak=2.00,
        candle_close_moderate=4.00,
        candle_close_strong=6.00,
        trend_close_mult_moderate=1.3,
        trend_close_mult_strong=1.8,
        trend_confirm_bars=2,
    )


def _indices() -> SymbolProfile:
    """ENDEKSLER (US30, NAS100, SPX500 vb.)"""
    return SymbolProfile(
        profile_name="INDICES",
        min_lot=0.01,
        min_close_profit=2.5,
        ana_close_profit=7.0,
        spm_trigger_loss=-7.0,
        spm2_trigger_loss=-7.0,
        spm_close_profit=5.0,
        fifo_net_target=5.0,
        spm_max_buy_layers=1,
        spm_max_sell_layers=1,
        spm_lot_base=1.0,
        spm_lot_increment=0.1,
        spm_lot_cap=1.5,
        spm_cooldown_sec=20,
        dca_distance_atr=2.0,
        profit_target_per_pos=4.0,
        hedge_min_spm_count=1,
        hedge_min_loss_usd=-5.0,
        rescue_hedge_threshold=-7.0,
        rescue_hedge_lot_mult=1.3,
        tp_weak_pips=100.0,
        tp_moderate_pips=250.0,
        tp_strong_pips=450.0,
        grid_atr_mult_low=1.0,
        grid_atr_mult_normal=1.5,
        grid_atr_mult_high=2.0,
        candle_close_weak=2.00,
        candle_close_moderate=4.00,
        candle_close_strong=6.00,
        trend_close_mult_moderate=1.3,
        trend_close_mult_strong=1.8,
        trend_confirm_bars=2,
    )


def _energy() -> SymbolProfile:
    """ENERJİ (USOIL, NGAS vb.)"""
    return SymbolProfile(
        profile_name="ENERGY",
        min_lot=0.01,
        min_close_profit=2.0,
        ana_close_profit=6.0,
        spm_trigger_loss=-7.0,
        spm2_trigger_loss=-7.0,
        spm_close_profit=5.0,
        fifo_net_target=5.0,
        spm_max_buy_layers=1,
        spm_max_sell_layers=1,
        spm_lot_base=1.0,
        spm_lot_increment=0.1,
        spm_lot_cap=1.5,
        spm_cooldown_sec=25,
        dca_distance_atr=2.0,
        profit_target_per_pos=4.0,
        hedge_min_spm_count=1,
        hedge_min_loss_usd=-5.0,
        rescue_hedge_threshold=-7.0,
        rescue_hedge_lot_mult=1.3,
        tp_weak_pips=40.0,
        tp_moderate_pips=80.0,
        tp_strong_pips=140.0,
        grid_atr_mult_low=1.0,
        grid_atr_mult_normal=1.5,
        grid_atr_mult_high=2.0,
        candle_close_weak=1.50,
        candle_close_moderate=3.00,
        candle_close_strong=5.00,
        trend_close_mult_moderate=1.3,
        trend_close_mult_strong=1.8,
        trend_confirm_bars=2,
    )


def _metal() -> SymbolProfile:
    """METAL (XPT, XPD gibi — XAU/XAG hariç)"""
    return SymbolProfile(
        profile_name="METAL",
        min_lot=0.01,
        min_close_profit=2.5,
        ana_close_profit=7.0,
        spm_trigger_loss=-7.0,
        spm2_trigger_loss=-7.0,
        spm_close_profit=5.0,
        fifo_net_target=5.0,
        spm_max_buy_layers=1,
        spm_max_sell_layers=1,
        spm_lot_base=1.0,
        spm_lot_increment=0.1,
        spm_lot_cap=1.5,
        spm_cooldown_sec=20,
        dca_distance_atr=2.0,
        profit_target_per_pos=4.0,
        hedge_min_spm_count=1,
        hedge_min_loss_usd=-5.0,
        rescue_hedge_threshold=-7.0,
        rescue_hedge_lot_mult=1.3,
        tp_weak_pips=30.0,
        tp_moderate_pips=70.0,
        tp_strong_pips=120.0,
        grid_atr_mult_low=1.0,
        grid_atr_mult_normal=1.5,
        grid_atr_mult_high=2.0,
        candle_close_weak=2.00,
        candle_close_moderate=4.00,
        candle_close_strong=6.00,
        trend_close_mult_moderate=1.3,
        trend_close_mult_strong=1.8,
        trend_confirm_bars=2,
    )


def _default() -> SymbolProfile:
    """VARSAYILAN (bilinmeyen enstrümanlar)"""
    return SymbolProfile(
        profile_name="DEFAULT",
        min_lot=0.0,
        min_close_profit=2.0,
        ana_close_profit=6.0,
        spm_trigger_loss=-5.0,
        spm2_trigger_loss=-7.0,
        spm_close_profit=3.0,
        fifo_net_target=5.0,
        spm_max_buy_layers=1,
        spm_max_sell_layers=1,
        spm_lot_base=1.0,
        spm_lot_increment=0.1,
        spm_lot_cap=1.5,
        spm_cooldown_sec=20,
        dca_distance_atr=2.0,
        profit_target_per_pos=3.0,
        hedge_min_spm_count=1,
        hedge_min_loss_usd=-5.0,
        rescue_hedge_threshold=-7.0,
        rescue_hedge_lot_mult=1.3,
        tp_weak_pips=30.0,
        tp_moderate_pips=60.0,
        tp_strong_pips=100.0,
        grid_atr_mult_low=1.0,
        grid_atr_mult_normal=1.5,
        grid_atr_mult_high=2.0,
        candle_close_weak=1.50,
        candle_close_moderate=3.00,
        candle_close_strong=5.00,
        trend_close_mult_moderate=1.3,
        trend_close_mult_strong=1.8,
        trend_confirm_bars=2,
    )


# =====================================================================
# PROFİL SEÇİM FONKSİYONU
# Öncelik: Sembol bazlı > JPY > Kategori > Varsayılan
# EA Config.mqh GetSymbolProfile() birebir port
# =====================================================================

# Sembol → varlık sınıfı eşlemesi
_SYMBOL_CLASS_MAP = {
    "BTCUSD":  "crypto",
    "XAGUSD":  "metal_xag",
    "XAUUSD":  "metal_xau",
    "GBPUSD":  "forex",
    "USDJPY":  "forex_jpy",
    "EURUSD":  "forex",
    "AUDUSD":  "forex",
    # Genişletme için:
    "GBPJPY":  "forex_jpy",
    "EURJPY":  "forex_jpy",
    "ETHUSD":  "crypto_alt",
    "LTCUSD":  "crypto_alt",
    "XRPUSD":  "crypto_alt",
    "DOGEUSD": "crypto_alt",
    "SOLUSD":  "crypto_alt",
    "US30":    "indices",
    "NAS100":  "indices",
    "SPX500":  "indices",
    "USOIL":   "energy",
    "XPTUSD":  "metal",
    "XPDUSD":  "metal",
}


def get_symbol_profile(symbol: str) -> SymbolProfile:
    """
    Sembol adına göre uygun profili döndür.

    Öncelik sırası (EA ile aynı):
      1. Sembol bazlı — XAU, XAG, BTC, ETH vb. tam eşleşme
      2. JPY çiftleri — sembolde JPY varsa
      3. Sınıf bazlı — _SYMBOL_CLASS_MAP'ten
      4. Varsayılan
    """
    sym = symbol.upper().replace("M", "").replace(".", "")  # EURUSDm → EURUSD

    # ── Öncelik 1: Sembol bazlı özel profil ──
    if "XAU" in sym or "GOLD" in sym:
        return _gold()
    if "XAG" in sym or "SILVER" in sym:
        return _silver()
    if "BTC" in sym:
        return _crypto_btc()
    if any(c in sym for c in ("ETH", "LTC", "XRP", "DOGE", "SOL", "ADA", "DOT", "BNB")):
        return _crypto_alt()

    # ── Öncelik 2: JPY çiftleri ──
    if "JPY" in sym:
        return _forex_jpy()

    # ── Öncelik 3: Sınıf haritasından ──
    cls = _SYMBOL_CLASS_MAP.get(sym, "")
    if cls == "forex":
        return _forex()
    if cls == "forex_jpy":
        return _forex_jpy()
    if cls == "metal_xau":
        return _gold()
    if cls == "metal_xag":
        return _silver()
    if cls == "metal":
        return _metal()
    if cls == "crypto":
        return _crypto_btc()
    if cls == "crypto_alt":
        return _crypto_alt()
    if cls == "indices":
        return _indices()
    if cls == "energy":
        return _energy()

    # ── Öncelik 4: Varsayılan ──
    return _default()
