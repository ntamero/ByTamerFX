"""
MIA v4.0 — Candle Pattern & Supply/Demand Zone Detection
Gercek mum formasyonlari + arz/talep bolgeleri
Copyright 2026, By T@MER — https://www.bytamer.com
"""

import numpy as np
import pandas as pd
from dataclasses import dataclass, field
from typing import List, Tuple, Optional
from enum import Enum
import logging

log = logging.getLogger("Patterns")


# ═══════════════════════════════════════════════════════════
# CANDLE PATTERN DETECTION
# ═══════════════════════════════════════════════════════════

class PatternType(Enum):
    BULLISH = "bullish"
    BEARISH = "bearish"

@dataclass
class CandlePattern:
    name:       str             # Pattern adi
    type:       PatternType     # Bullish/Bearish
    score:      int             # Skor (0-15)
    bar_index:  int             # Hangi barda tespit edildi
    confidence: float = 0.0     # 0-1 arasi guven


class CandlePatternDetector:
    """
    Gercek mum pattern tespiti — M15 + H1 + H4
    Desteklenen pattern'lar:
      - Bullish/Bearish Engulfing
      - Pin Bar (Hammer / Shooting Star)
      - Morning Star / Evening Star (3-bar)
      - Inside Bar
      - Doji Reversal
      - Three White Soldiers / Three Black Crows
      - Tweezer Top / Bottom
    """

    def __init__(self):
        self._min_body_pct = 0.10   # Minimum govde orani
        self._pin_wick_ratio = 2.0  # Pin bar fitil/govde orani

    def detect_all(self, df: pd.DataFrame, lookback: int = 5) -> List[CandlePattern]:
        """
        Son 'lookback' barda tum pattern'lari tara.
        df: OHLCV DataFrame (open, high, low, close, volume)
        Return: Tespit edilen pattern listesi (skora gore sirali)
        """
        if len(df) < 10:
            return []

        patterns = []
        # Son kapanmis barlardan kontrol et (en son bar = acik, -2 = son kapanmis)
        end = len(df) - 1   # -1 = acik bar, skip
        start = max(3, end - lookback)

        for i in range(start, end):
            patterns.extend(self._check_bar(df, i))

        # Skora gore sirala, en guclu basta
        patterns.sort(key=lambda p: p.score, reverse=True)
        return patterns

    def detect_latest(self, df: pd.DataFrame) -> Optional[CandlePattern]:
        """Son kapanmis barda en guclu pattern'i dondur"""
        patterns = self.detect_all(df, lookback=3)
        return patterns[0] if patterns else None

    def _check_bar(self, df: pd.DataFrame, i: int) -> List[CandlePattern]:
        """Belirli bir barda tum pattern'lari kontrol et"""
        found = []

        # Bar verileri
        o, h, l, c = float(df['open'].iloc[i]), float(df['high'].iloc[i]), \
                     float(df['low'].iloc[i]), float(df['close'].iloc[i])
        body = c - o
        total = h - l
        if total < 1e-10:
            return found

        body_pct = abs(body) / total
        upper_wick = h - max(o, c)
        lower_wick = min(o, c) - l
        is_bull = body > 0
        abs_body = abs(body)

        # Onceki bar
        if i < 1:
            return found
        o1, h1, l1, c1 = float(df['open'].iloc[i-1]), float(df['high'].iloc[i-1]), \
                         float(df['low'].iloc[i-1]), float(df['close'].iloc[i-1])
        body1 = c1 - o1
        total1 = h1 - l1
        is_bull1 = body1 > 0

        # ── ENGULFING ────────────────────────────────────
        if abs_body > 0 and abs(body1) > 0:
            # Bullish Engulfing: onceki bearish, simdi bullish, simdi oncekini yutuyor
            if not is_bull1 and is_bull and c > o1 and o < c1 and abs_body > abs(body1) * 1.1:
                conf = min(1.0, abs_body / (abs(body1) + 1e-9) - 1.0)
                found.append(CandlePattern("bullish_engulfing", PatternType.BULLISH, 10, i, conf))

            # Bearish Engulfing
            if is_bull1 and not is_bull and c < o1 and o > c1 and abs_body > abs(body1) * 1.1:
                conf = min(1.0, abs_body / (abs(body1) + 1e-9) - 1.0)
                found.append(CandlePattern("bearish_engulfing", PatternType.BEARISH, 10, i, conf))

        # ── PIN BAR (Hammer / Shooting Star) ─────────────
        if body_pct < 0.35 and total > 0:
            # Hammer (bullish pin): uzun alt fitil, kisa ust fitil
            if lower_wick > abs_body * self._pin_wick_ratio and upper_wick < abs_body * 0.5:
                conf = min(1.0, lower_wick / (abs_body + 1e-9) / 3.0)
                found.append(CandlePattern("pin_bar", PatternType.BULLISH, 8, i, conf))

            # Shooting Star (bearish pin): uzun ust fitil, kisa alt fitil
            if upper_wick > abs_body * self._pin_wick_ratio and lower_wick < abs_body * 0.5:
                conf = min(1.0, upper_wick / (abs_body + 1e-9) / 3.0)
                found.append(CandlePattern("pin_bar", PatternType.BEARISH, 8, i, conf))

        # ── HAMMER (classic — govde %30'dan az, alt fitil %60'tan fazla)
        if body_pct > 0.10 and body_pct < 0.30:
            if lower_wick / total > 0.60 and upper_wick / total < 0.10:
                found.append(CandlePattern("hammer", PatternType.BULLISH, 7, i, 0.7))
            if upper_wick / total > 0.60 and lower_wick / total < 0.10:
                found.append(CandlePattern("shooting_star", PatternType.BEARISH, 7, i, 0.7))

        # ── DOJI REVERSAL ────────────────────────────────
        if body_pct < 0.10 and total > 0:
            # Onceki barin yonune ters doji = reversal sinyali
            if i >= 2:
                o2, c2 = float(df['open'].iloc[i-2]), float(df['close'].iloc[i-2])
                if c2 > o2 and not is_bull1:  # Yukari trend sonunda doji
                    found.append(CandlePattern("doji_reversal", PatternType.BEARISH, 6, i, 0.5))
                elif c2 < o2 and is_bull1:  # Asagi trend sonunda doji
                    found.append(CandlePattern("doji_reversal", PatternType.BULLISH, 6, i, 0.5))

        # ── INSIDE BAR ───────────────────────────────────
        if h < h1 and l > l1:
            # Tam icinde = breakout beklentisi
            conf = 1.0 - (total / (total1 + 1e-9))  # Ne kadar kucukse o kadar iyi
            # Yon: onceki barin yonunde
            ptype = PatternType.BULLISH if is_bull1 else PatternType.BEARISH
            found.append(CandlePattern("inside_bar", ptype, 5, i, max(0, conf)))

        # ── MORNING STAR / EVENING STAR (3-bar) ──────────
        if i >= 2:
            o2, h2, l2, c2 = float(df['open'].iloc[i-2]), float(df['high'].iloc[i-2]), \
                             float(df['low'].iloc[i-2]), float(df['close'].iloc[i-2])
            body2 = c2 - o2
            total2 = h2 - l2
            body1_pct = abs(body1) / (total1 + 1e-9)

            # Morning Star: buyuk bearish + kucuk govde + buyuk bullish
            if body2 < 0 and abs(body2) / (total2 + 1e-9) > 0.50 and \
               body1_pct < 0.30 and \
               is_bull and body_pct > 0.50 and c > (o2 + c2) / 2:
                found.append(CandlePattern("morning_star", PatternType.BULLISH, 12, i, 0.8))

            # Evening Star: buyuk bullish + kucuk govde + buyuk bearish
            if body2 > 0 and abs(body2) / (total2 + 1e-9) > 0.50 and \
               body1_pct < 0.30 and \
               not is_bull and body_pct > 0.50 and c < (o2 + c2) / 2:
                found.append(CandlePattern("evening_star", PatternType.BEARISH, 12, i, 0.8))

        # ── THREE WHITE SOLDIERS / THREE BLACK CROWS ─────
        if i >= 2:
            o2, c2 = float(df['open'].iloc[i-2]), float(df['close'].iloc[i-2])
            body2 = c2 - o2

            # Three White Soldiers: 3 ardisik guclu bullish
            if body2 > 0 and body1 > 0 and body > 0:
                b2_pct = abs(body2) / (float(df['high'].iloc[i-2]) - float(df['low'].iloc[i-2]) + 1e-9)
                b1_pct = abs(body1) / (total1 + 1e-9)
                if b2_pct > 0.50 and b1_pct > 0.50 and body_pct > 0.50:
                    if c > c1 > c2:  # Her biri oncekinden yuksek kapanir
                        found.append(CandlePattern("three_soldiers", PatternType.BULLISH, 15, i, 0.9))

            # Three Black Crows: 3 ardisik guclu bearish
            if body2 < 0 and body1 < 0 and body < 0:
                b2_pct = abs(body2) / (float(df['high'].iloc[i-2]) - float(df['low'].iloc[i-2]) + 1e-9)
                b1_pct = abs(body1) / (total1 + 1e-9)
                if b2_pct > 0.50 and b1_pct > 0.50 and body_pct > 0.50:
                    if c < c1 < c2:
                        found.append(CandlePattern("three_crows", PatternType.BEARISH, 15, i, 0.9))

        # ── TWEEZER TOP / BOTTOM ─────────────────────────
        if total1 > 0 and total > 0:
            # Tweezer Bottom: 2 barin dipleri neredeyse ayni
            low_diff_pct = abs(l - l1) / (total + 1e-9)
            if low_diff_pct < 0.05 and not is_bull1 and is_bull:
                found.append(CandlePattern("tweezer_bottom", PatternType.BULLISH, 6, i, 0.6))

            # Tweezer Top: 2 barin tepeleri neredeyse ayni
            high_diff_pct = abs(h - h1) / (total + 1e-9)
            if high_diff_pct < 0.05 and is_bull1 and not is_bull:
                found.append(CandlePattern("tweezer_top", PatternType.BEARISH, 6, i, 0.6))

        return found

    def score_for_direction(self, patterns: List[CandlePattern], is_buy: bool) -> int:
        """
        Belirli yondeki en iyi pattern skorunu dondur.
        Ayni yonde birden fazla pattern varsa en iyisini al + bonus
        """
        target = PatternType.BULLISH if is_buy else PatternType.BEARISH
        matching = [p for p in patterns if p.type == target]
        if not matching:
            return 0

        best = matching[0].score  # Zaten skora gore sirali
        # 2+ pattern bonus
        bonus = min(3, len(matching) - 1) if len(matching) > 1 else 0
        return min(15, best + bonus)


# ═══════════════════════════════════════════════════════════
# SUPPLY / DEMAND ZONE DETECTION
# ═══════════════════════════════════════════════════════════

class ZoneType(Enum):
    SUPPLY = "supply"    # Satis baskisi bolgesi (direnç)
    DEMAND = "demand"    # Alis baskisi bolgesi (destek)

@dataclass
class SDZone:
    type:        ZoneType
    level:       float          # Zone merkez fiyati
    upper:       float          # Zone ust siniri
    lower:       float          # Zone alt siniri
    strength:    float = 0.0    # 0-1 arasi guc
    touch_count: int   = 0      # Kac kez test edilmis
    created_bar: int   = 0      # Hangi barda olusturuldu
    fresh:       bool  = True   # Hic kirilmamis mi


class SupplyDemandDetector:
    """
    Swing high/low bazli arz/talep bolgesi tespiti
    """

    def __init__(self, swing_lookback: int = 5, zone_tolerance_pct: float = 0.3):
        self._swing_lookback = swing_lookback
        self._zone_tolerance = zone_tolerance_pct / 100.0

    def detect_zones(self, df: pd.DataFrame, lookback: int = 50) -> List[SDZone]:
        """
        Son 'lookback' barda supply/demand zone'lari tespit et.
        Return: Zone listesi (guce gore sirali)
        """
        if len(df) < lookback:
            lookback = len(df)
        if lookback < 10:
            return []

        zones = []
        start = len(df) - lookback
        end = len(df) - 1  # Son acik bar haric

        highs = df['high'].values
        lows = df['low'].values
        closes = df['close'].values

        # Swing High/Low bul
        swing_highs = self._find_swing_highs(highs, start, end)
        swing_lows = self._find_swing_lows(lows, start, end)

        # Supply zones (swing high civari)
        for idx, level in swing_highs:
            atr_local = self._local_atr(df, idx)
            zone = SDZone(
                type=ZoneType.SUPPLY,
                level=level,
                upper=level + atr_local * 0.3,
                lower=level - atr_local * 0.3,
                created_bar=idx,
            )
            # Kac kez test edilmis?
            zone.touch_count = self._count_touches(highs, closes, zone, start, end)
            zone.strength = self._calc_zone_strength(zone, df, idx)
            zone.fresh = self._is_zone_fresh(closes, zone, idx, end)
            zones.append(zone)

        # Demand zones (swing low civari)
        for idx, level in swing_lows:
            atr_local = self._local_atr(df, idx)
            zone = SDZone(
                type=ZoneType.DEMAND,
                level=level,
                upper=level + atr_local * 0.3,
                lower=level - atr_local * 0.3,
                created_bar=idx,
            )
            zone.touch_count = self._count_touches(lows, closes, zone, start, end)
            zone.strength = self._calc_zone_strength(zone, df, idx)
            zone.fresh = self._is_zone_fresh(closes, zone, idx, end)
            zones.append(zone)

        # Guce gore sirala
        zones.sort(key=lambda z: z.strength, reverse=True)
        return zones[:10]  # En guclu 10 zone

    def score_proximity(self, zones: List[SDZone], price: float, is_buy: bool) -> int:
        """
        Fiyatin zone'a yakinligina gore skor ver (0-10)
        """
        if not zones:
            return 0

        score = 0
        for zone in zones:
            distance_pct = abs(price - zone.level) / (price + 1e-9) * 100

            if distance_pct > 1.0:  # %1'den uzaksa atla
                continue

            # Zone'a yakin
            if distance_pct < 0.1:
                base = 7  # Cok yakin
            elif distance_pct < 0.3:
                base = 5
            elif distance_pct < 0.5:
                base = 3
            else:
                base = 1

            # Yon uyumu kontrolu
            if zone.type == ZoneType.DEMAND and is_buy:
                score += base
            elif zone.type == ZoneType.SUPPLY and not is_buy:
                score += base
            elif zone.type == ZoneType.DEMAND and not is_buy:
                score -= 2  # Ters yon — puan dusur
            elif zone.type == ZoneType.SUPPLY and is_buy:
                score -= 2

            # Guc bonusu
            if zone.strength > 0.7:
                score += 2
            if zone.fresh:
                score += 1

            break  # Sadece en yakin zone'u say

        return max(0, min(10, score))

    def _find_swing_highs(self, highs: np.ndarray, start: int, end: int) -> List[Tuple[int, float]]:
        """Swing high noktalarini bul"""
        swing_highs = []
        lb = self._swing_lookback
        for i in range(start + lb, end - lb):
            is_swing = True
            for j in range(1, lb + 1):
                if highs[i] <= highs[i-j] or highs[i] <= highs[i+j]:
                    is_swing = False
                    break
            if is_swing:
                swing_highs.append((i, float(highs[i])))
        return swing_highs

    def _find_swing_lows(self, lows: np.ndarray, start: int, end: int) -> List[Tuple[int, float]]:
        """Swing low noktalarini bul"""
        swing_lows = []
        lb = self._swing_lookback
        for i in range(start + lb, end - lb):
            is_swing = True
            for j in range(1, lb + 1):
                if lows[i] >= lows[i-j] or lows[i] >= lows[i+j]:
                    is_swing = False
                    break
            if is_swing:
                swing_lows.append((i, float(lows[i])))
        return swing_lows

    def _count_touches(self, prices: np.ndarray, closes: np.ndarray,
                       zone: SDZone, start: int, end: int) -> int:
        """Zone'a kac kez dokunuldugunu say"""
        count = 0
        for i in range(start, end):
            if zone.lower <= prices[i] <= zone.upper:
                count += 1
            elif zone.lower <= closes[i] <= zone.upper:
                count += 1
        return count

    def _calc_zone_strength(self, zone: SDZone, df: pd.DataFrame, idx: int) -> float:
        """Zone gucunu hesapla (0-1)"""
        strength = 0.0

        # Touch count bonusu (2-4 ideal)
        if 2 <= zone.touch_count <= 4:
            strength += 0.4
        elif zone.touch_count >= 5:
            strength += 0.2  # Cok fazla test = zayifliyor

        # Fresh zone bonusu
        if zone.fresh:
            strength += 0.3

        # Hacim bonusu (zone olusturuldugunda hacim yuksek mi?)
        if 'volume' in df.columns or 'tick_volume' in df.columns:
            vol_col = 'tick_volume' if 'tick_volume' in df.columns else 'volume'
            vol_at = float(df[vol_col].iloc[min(idx, len(df)-1)])
            vol_avg = float(df[vol_col].iloc[max(0, idx-20):idx].mean()) if idx > 20 else vol_at
            if vol_at > vol_avg * 1.5:
                strength += 0.3

        return min(1.0, strength)

    def _is_zone_fresh(self, closes: np.ndarray, zone: SDZone, created: int, end: int) -> bool:
        """Zone hic kirilmamis mi kontrol et"""
        for i in range(created + 1, end):
            if zone.type == ZoneType.SUPPLY and closes[i] > zone.upper:
                return False  # Supply kirildi
            if zone.type == ZoneType.DEMAND and closes[i] < zone.lower:
                return False  # Demand kirildi
        return True

    def _local_atr(self, df: pd.DataFrame, idx: int, period: int = 14) -> float:
        """Yerel ATR hesapla"""
        start = max(0, idx - period)
        end = min(len(df), idx + 1)
        if end - start < 3:
            return 0.001
        h = df['high'].iloc[start:end].values
        l = df['low'].iloc[start:end].values
        c = df['close'].iloc[start:end].values
        tr = np.maximum(h[1:] - l[1:],
                       np.maximum(np.abs(h[1:] - c[:-1]), np.abs(l[1:] - c[:-1])))
        return float(np.mean(tr)) if len(tr) > 0 else 0.001


# ═══════════════════════════════════════════════════════════
# MARKET REGIME DETECTION
# ═══════════════════════════════════════════════════════════

class MarketRegime(Enum):
    STRONG_TREND = "STRONG_TREND"
    TREND        = "TREND"
    RANGE        = "RANGE"
    VOLATILE     = "VOLATILE"
    CHOPPY       = "CHOPPY"


def detect_regime(adx: float, atr_percentile: float,
                  ema_aligned: bool, bb_width_pct: float) -> MarketRegime:
    """
    Piyasa rejimini tespit et
    adx: ADX degeri
    atr_percentile: ATR yuzdelik (0-100)
    ema_aligned: EMA8>21>50 veya 8<21<50
    bb_width_pct: Bollinger bant genisligi / fiyat yuzesi
    """
    import config as cfg

    # Oncelik sirasi
    if adx >= cfg.REGIME_STRONG_TREND_ADX and ema_aligned:
        return MarketRegime.STRONG_TREND

    if atr_percentile >= cfg.REGIME_VOLATILE_ATR_PCT:
        return MarketRegime.VOLATILE

    if adx >= cfg.REGIME_TREND_ADX:
        return MarketRegime.TREND

    if adx < cfg.REGIME_CHOPPY_ADX:
        return MarketRegime.CHOPPY

    return MarketRegime.RANGE


def get_regime_multiplier(regime: MarketRegime) -> float:
    """Regime'e gore skor carpanini dondur"""
    import config as cfg
    return cfg.REGIME_MULTIPLIERS.get(regime.value, 1.0)
