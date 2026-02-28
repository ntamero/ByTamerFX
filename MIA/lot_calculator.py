"""
MIA v5.0 — 8-Factor Dynamic Lot Calculator
BytamerFX EA LotCalculator.mqh'den port edildi (v2.2)

Formül:
  final_lot = base × score × trend × category × volatility × margin × open_lot_balance × normalize

8 Faktör:
  1. Balance bazlı temel lot
  2. Sinyal skoru çarpanı (40→0.8x ... 85→1.5x)
  3. Trend gücü çarpanı (WEAK→0.7x ... STRONG→1.3x)
  4. Kategori risk çarpanı (FOREX→1.0x ... CRYPTO→0.5x)
  5. ATR volatilite çarpanı (düşük→1.0x ... extreme→0.3x)
  6. Margin seviye güvenlik çarpanı
  7. Toplam açık lot dengeleme çarpanı
  8. Broker normalizasyon (min/max/step + profil override)

Copyright 2026, By T@MER — https://www.bytamer.com
"""

import math
import logging
from typing import Optional

import config as cfg
from symbol_profiles import SymbolProfile

log = logging.getLogger("LotCalc")

# ─── Kategori çarpanları ──
_CATEGORY_MULT = {
    "forex":      1.0,
    "forex_jpy":  1.0,
    "stocks":     0.9,
    "indices":    0.8,
    "metal":      0.7,
    "metal_xau":  0.7,
    "metal_xag":  0.7,
    "energy":     0.6,
    "crypto":     0.5,
    "crypto_alt": 0.5,
}

# ─── BaseLotPer1000: her $1000 bakiye için temel lot ──
BASE_LOT_PER_1000 = 0.05


class LotCalculator:
    """
    8-Faktör dinamik lot hesaplayıcı.
    EA CLotCalculator birebir Python portu.
    """

    def __init__(
        self,
        symbol: str,
        profile: SymbolProfile,
        category: str = "",
        broker_min_lot: float = 0.01,
        broker_max_lot: float = 0.50,
        broker_lot_step: float = 0.01,
        tick_value: float = 0.0,
        contract_size: float = 0.0,
    ):
        self.symbol = symbol
        self.profile = profile
        self.category = category or self._detect_category(symbol)

        # Broker bilgileri (MT5'den gelecek)
        self._broker_min = broker_min_lot
        self._broker_max = broker_max_lot
        self._lot_step = broker_lot_step if broker_lot_step > 0 else 0.01
        self._tick_value = tick_value
        self._contract_size = contract_size

        # Profil min lot override
        if profile.min_lot > 0 and profile.min_lot >= self._broker_min:
            self._min_lot = profile.min_lot
        else:
            self._min_lot = self._broker_min

        # Config MIN_LOT_OVERRIDES (kullanıcı tercihi — en yüksek öncelik)
        override = cfg.MIN_LOT_OVERRIDES.get(symbol, 0.0)
        if override > 0:
            self._min_lot = max(self._min_lot, override)

        log.info(
            f"[LOT-{symbol}] Init: min={self._min_lot:.2f} max={self._broker_max:.2f} "
            f"step={self._lot_step:.2f} profile={profile.profile_name} cat={self.category}"
        )

    # ── Broker bilgilerini güncelle (MT5 bağlantısı sonrası) ──
    def update_broker_info(
        self,
        min_lot: float,
        max_lot: float,
        lot_step: float,
        tick_value: float = 0.0,
        contract_size: float = 0.0,
    ):
        self._broker_min = min_lot
        self._broker_max = max_lot
        self._lot_step = lot_step if lot_step > 0 else 0.01
        self._tick_value = tick_value
        self._contract_size = contract_size

        # Profil override tekrar uygula
        if self.profile.min_lot > 0 and self.profile.min_lot >= self._broker_min:
            self._min_lot = self.profile.min_lot
        else:
            self._min_lot = self._broker_min

        override = cfg.MIN_LOT_OVERRIDES.get(self.symbol, 0.0)
        if override > 0:
            self._min_lot = max(self._min_lot, override)

    # ═════════════════════════════════════════════════════════
    # ANA HESAPLAMA
    # ═════════════════════════════════════════════════════════

    def calculate(
        self,
        balance: float,
        atr: float,
        score: int,
        trend_strength: str = "MODERATE",
        margin_level: float = 0.0,
        total_open_lots: float = 0.0,
        current_price: float = 0.0,
    ) -> float:
        """
        8-faktör dinamik lot hesapla.

        Args:
            balance:         Hesap bakiyesi ($)
            atr:             H1 ATR(14) değeri
            score:           Sinyal skoru (0-100)
            trend_strength:  "WEAK" / "MODERATE" / "STRONG"
            margin_level:    Margin seviyesi (%) — 0 = pozisyon yok
            total_open_lots: Toplam açık lot miktarı
            current_price:   Sembol fiyatı (volatilite hesabı için)

        Returns:
            Normalize edilmiş lot miktarı
        """
        if balance <= 0:
            return self._min_lot

        # 1. Bakiye bazlı temel lot
        base = (balance / 1000.0) * BASE_LOT_PER_1000

        # 2. Sinyal skoru çarpanı
        s_mult = self._score_mult(score)

        # 3. Trend gücü çarpanı
        t_mult = self._trend_mult(trend_strength)

        # 4. Kategori risk çarpanı
        c_mult = _CATEGORY_MULT.get(self.category, 0.7)

        # 5. ATR volatilite çarpanı
        v_mult = self._volatility_mult(atr, current_price)

        # 6. Margin seviye çarpanı
        m_mult = self._margin_mult(margin_level)

        # 7. Açık lot dengeleme çarpanı
        l_mult = self._open_lot_balancer(total_open_lots)

        # 8. Çarp ve normalize
        lot = base * s_mult * t_mult * c_mult * v_mult * m_mult * l_mult
        result = self._normalize(lot)

        log.info(
            f"[LOT-{self.symbol}] "
            f"bal=${balance:.0f} base={base:.3f} "
            f"score={score}({s_mult:.1f}x) trend={trend_strength}({t_mult:.1f}x) "
            f"cat={c_mult:.1f}x vol={v_mult:.2f}x margin={m_mult:.2f}x lotbal={l_mult:.2f}x "
            f"→ {result:.2f}lot"
        )
        return result

    # ── SPM lot hesabı ──
    def calculate_spm_lot(
        self,
        ana_lot: float,
        spm_layer: int,
    ) -> float:
        """
        SPM lot hesabı: ana_lot × spm_lot_base + (layer × spm_lot_increment)
        Profildeki spm_lot_cap ile sınırlandırılır.
        """
        p = self.profile
        mult = min(p.spm_lot_cap, p.spm_lot_base + (spm_layer * p.spm_lot_increment))
        lot = ana_lot * mult
        return self._normalize(lot)

    # ═════════════════════════════════════════════════════════
    # ÇARPAN FONKSİYONLARI (EA'dan birebir)
    # ═════════════════════════════════════════════════════════

    @staticmethod
    def _score_mult(score: int) -> float:
        """Sinyal skoru çarpanı — EA GetScoreMultiplier()"""
        if score >= 85:
            return 1.5
        if score >= 70:
            return 1.3
        if score >= 55:
            return 1.1
        if score >= 45:
            return 1.0
        if score >= 38:
            return 0.8
        return 0.5

    @staticmethod
    def _trend_mult(trend: str) -> float:
        """Trend gücü çarpanı — EA GetTrendMultiplier()"""
        t = trend.upper()
        if t == "STRONG":
            return 1.3
        if t == "MODERATE":
            return 1.0
        if t == "WEAK":
            return 0.7
        return 1.0

    def _volatility_mult(self, atr: float, price: float = 0.0) -> float:
        """ATR volatilite çarpanı — EA GetVolatilityMultiplier()"""
        if atr <= 0 or price <= 0:
            return 1.0

        atr_pct = (atr / price) * 100.0

        # Tick value bazlı ek kontrol (EA v2.2)
        if self._tick_value > 0 and self._min_lot > 0:
            point = atr  # Basitleştirme: ATR ≈ pip cinsinden hareket
            dollar_per_pip = self._tick_value * self._min_lot
            potential_loss = dollar_per_pip * (atr / max(0.0001, self._lot_step))
            if potential_loss > 50.0:
                return 0.3
            if potential_loss > 30.0:
                return 0.4
            if potential_loss > 15.0:
                return 0.5

        if atr_pct > 3.0:
            return 0.4
        if atr_pct > 2.0:
            return 0.5
        if atr_pct > 1.5:
            return 0.6
        if atr_pct > 1.0:
            return 0.7
        if atr_pct > 0.5:
            return 0.85
        return 1.0

    @staticmethod
    def _margin_mult(margin_level: float) -> float:
        """Margin seviye güvenlik çarpanı — EA GetMarginMultiplier()"""
        if margin_level <= 0:
            return 1.0  # Pozisyon yok veya bilgi yok

        if margin_level < 300:
            return 0.5
        if margin_level < 500:
            return 0.7
        if margin_level < 1000:
            return 0.85
        return 1.0

    @staticmethod
    def _open_lot_balancer(total_open_lots: float) -> float:
        """Toplam açık lot dengeleme — EA GetOpenLotBalancer()"""
        if total_open_lots <= 0:
            return 1.0

        max_vol = getattr(cfg, "MAX_TOTAL_LOTS", 0.30)
        if max_vol <= 0:
            max_vol = 0.30

        ratio = total_open_lots / max_vol

        if ratio >= 0.90:
            return 0.3
        if ratio >= 0.70:
            return 0.5
        if ratio >= 0.50:
            return 0.7
        if ratio >= 0.30:
            return 0.85
        return 1.0

    def _normalize(self, lot: float) -> float:
        """Lot normalizasyon ve clamp — EA NormalizeLot()"""
        # Step'e yuvarla (aşağı)
        lot = math.floor(lot / self._lot_step) * self._lot_step
        # Min/max clamp
        lot = max(self._min_lot, min(self._broker_max, lot))
        return round(lot, 2)

    # ═════════════════════════════════════════════════════════
    # YARDIMCI
    # ═════════════════════════════════════════════════════════

    @staticmethod
    def _detect_category(symbol: str) -> str:
        sym = symbol.upper()
        specs = cfg.SYMBOL_SPECS.get(sym.replace("M", ""), {})
        cls = specs.get("class", "")
        if cls:
            return cls

        if "XAU" in sym or "GOLD" in sym:
            return "metal_xau"
        if "XAG" in sym or "SILVER" in sym:
            return "metal_xag"
        if "BTC" in sym:
            return "crypto"
        if any(c in sym for c in ("ETH", "LTC", "XRP", "DOGE", "SOL")):
            return "crypto_alt"
        if "JPY" in sym:
            return "forex_jpy"
        if any(c in sym for c in ("EUR", "GBP", "AUD", "NZD", "CAD", "CHF")):
            return "forex"
        if any(c in sym for c in ("US30", "NAS", "SPX", "DAX")):
            return "indices"
        if any(c in sym for c in ("OIL", "NGAS", "BRENT")):
            return "energy"
        return "forex"

    @property
    def min_lot(self) -> float:
        return self._min_lot

    @property
    def max_lot(self) -> float:
        return self._broker_max
