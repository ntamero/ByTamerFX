"""
MIA v4.0 — Enhanced Signal Engine
12 Katman: EMA | MACD | ADX | RSI | BB | Stoch | Volume | Patterns |
           Supply/Demand | MTF Confluence | Regime (carpan) | Sentiment (overlay)
MTF: M15 giris + H1 trend + H4 ust trend
Copyright 2026, By T@MER — https://www.bytamer.com
"""

import numpy as np
import pandas as pd
from dataclasses import dataclass, field
from enum import Enum
from typing import Optional, Tuple, List, Dict
import logging

import config as cfg
from patterns import (
    CandlePatternDetector, SupplyDemandDetector,
    MarketRegime, detect_regime, get_regime_multiplier,
    PatternType
)

log = logging.getLogger("SignalEngine")


class Dir(Enum):
    NONE = 0
    BUY  = 1
    SELL = 2


class Trend(Enum):
    WEAK     = 0
    MODERATE = 1
    STRONG   = 2


@dataclass
class ScoreBreakdown:
    ema_trend:       int = 0   # Layer 1  — max 20
    macd_momentum:   int = 0   # Layer 2  — max 20
    adx_strength:    int = 0   # Layer 3  — max 15
    rsi_level:       int = 0   # Layer 4  — max 15
    bb_position:     int = 0   # Layer 5  — max 15
    stoch_signal:    int = 0   # Layer 6  — max 10
    volume_profile:  int = 0   # Layer 7  — max 15  [YENi]
    candle_patterns: int = 0   # Layer 8  — max 15  [YENi]
    supply_demand:   int = 0   # Layer 9  — max 10  [YENi]
    mtf_confluence:  int = 0   # Layer 10 — max 10  [YENi]
    sentiment:       int = 0   # Layer 12 — max 5   [YENi]

    @property
    def total(self) -> int:
        return (self.ema_trend + self.macd_momentum + self.adx_strength +
                self.rsi_level + self.bb_position + self.stoch_signal +
                self.volume_profile + self.candle_patterns + self.supply_demand +
                self.mtf_confluence + self.sentiment)


@dataclass
class SignalResult:
    direction:     Dir = Dir.NONE
    score:         int = 0
    raw_score:     int = 0         # Regime carpani oncesi ham skor
    buy:           ScoreBreakdown = field(default_factory=ScoreBreakdown)
    sell:          ScoreBreakdown = field(default_factory=ScoreBreakdown)
    candle_dir:    Dir = Dir.NONE
    trend_dir:     Dir = Dir.NONE
    trend_str:     Trend = Trend.WEAK
    adx:           float = 0.0
    rsi:           float = 50.0
    atr:           float = 0.0
    atr_percentile: float = 50.0
    h1_bull:       bool = False
    h4_bull:       bool = False
    regime:        MarketRegime = MarketRegime.RANGE      # [YENi]
    regime_multiplier: float = 1.0                        # [YENi]
    threshold:     int = 55                                # [YENi] Dinamik esik
    patterns_found: list = field(default_factory=list)     # [YENi]
    sd_zones:      list = field(default_factory=list)      # [YENi]
    volume_ratio:  float = 1.0                             # [YENi]
    bb_pct_b:      float = 0.5                             # [YENi]
    stoch_k:       float = 50.0                            # [YENi]


class SignalEngine:
    """
    MIA v4.0 Enhanced Signal Engine — 12 Katman + Regime + Dinamik Esik
    """

    def __init__(self, symbol: str):
        self.symbol = symbol
        self._trend_dir = Dir.NONE
        self._trend_confirm = 0
        self._pending_trend = Dir.NONE

        # v4.0 yeni bilesenler
        self._pattern_detector = CandlePatternDetector()
        self._sd_detector = SupplyDemandDetector()
        self._sentiment_scores: Dict[str, float] = {}  # Sentiment Agent'tan gelir

    def set_sentiment(self, scores: Dict[str, float]):
        """Sentiment Agent'tan gelen skorlari ayarla"""
        self._sentiment_scores = scores

    # ─── ANA DEGERLENDIRME ────────────────────────────────

    def evaluate(self, m15: pd.DataFrame, h1: pd.DataFrame, h4: pd.DataFrame,
                 session: str = "LONDON") -> SignalResult:
        """
        Tum indikatorleri hesapla, 12 katman skor, regime carpani, dinamik esik.
        m15/h1/h4: OHLCV DataFrame (open, high, low, close, volume/tick_volume)
        """
        result = SignalResult()
        if len(m15) < 60 or len(h1) < 10 or len(h4) < 5:
            return result

        # ── INDIKATORLER ────────────────────────────────
        c  = m15['close']
        h  = m15['high']
        l  = m15['low']
        op = m15['open']

        # Tick volume (yoksa volume kullan)
        vol = m15['tick_volume'] if 'tick_volume' in m15.columns else (
              m15['volume'] if 'volume' in m15.columns else pd.Series(np.ones(len(m15))))

        # EMA
        ema8  = c.ewm(span=8,  adjust=False).mean()
        ema21 = c.ewm(span=21, adjust=False).mean()
        ema50 = c.ewm(span=50, adjust=False).mean()

        # MACD
        e12 = c.ewm(span=12, adjust=False).mean()
        e26 = c.ewm(span=26, adjust=False).mean()
        macd_main = e12 - e26
        macd_sig  = macd_main.ewm(span=9, adjust=False).mean()
        macd_hist = macd_main - macd_sig

        # RSI
        delta = c.diff()
        gain  = delta.clip(lower=0).ewm(span=14, adjust=False).mean()
        loss  = (-delta.clip(upper=0)).ewm(span=14, adjust=False).mean()
        rsi   = 100 - 100 / (1 + gain / (loss + 1e-9))

        # ATR
        tr = pd.concat([h-l, (h-c.shift()).abs(), (l-c.shift()).abs()], axis=1).max(axis=1)
        atr14 = tr.ewm(span=14, adjust=False).mean()

        # ATR Percentile (son 100 bar icinde suankinin yuzdeligi)
        atr_window = atr14.iloc[-100:] if len(atr14) >= 100 else atr14
        atr_pct = (atr_window < atr14.iloc[-1]).sum() / (len(atr_window) + 1e-9) * 100

        # ADX
        pdm_raw = (h.diff()).where((h.diff() > 0) & (h.diff() > -l.diff()), 0.0)
        ndm_raw = (-l.diff()).where((-l.diff() > 0) & (-l.diff() > h.diff()), 0.0)
        pdi = pdm_raw.ewm(span=14, adjust=False).mean() / (atr14 + 1e-9) * 100
        ndi = ndm_raw.ewm(span=14, adjust=False).mean() / (atr14 + 1e-9) * 100
        dx  = (pdi - ndi).abs() / (pdi + ndi + 1e-9) * 100
        adx = dx.ewm(span=14, adjust=False).mean()

        # Bollinger
        bb_mid = c.rolling(20).mean()
        bb_std = c.rolling(20).std()
        bb_up  = bb_mid + 2 * bb_std
        bb_lo  = bb_mid - 2 * bb_std

        # Stochastic
        lo14 = l.rolling(14).min()
        hi14 = h.rolling(14).max()
        stk  = (c - lo14) / (hi14 - lo14 + 1e-9) * 100
        std  = stk.rolling(3).mean()

        # OBV (On Balance Volume)
        obv = (vol * np.sign(c.diff()).fillna(0)).cumsum()

        # H1 EMA50 + RSI + MACD
        h1_ema50 = h1['close'].ewm(span=50, adjust=False).mean()
        h1_d = h1['close'].diff()
        h1_g = h1_d.clip(lower=0).ewm(span=14, adjust=False).mean()
        h1_l = (-h1_d.clip(upper=0)).ewm(span=14, adjust=False).mean()
        h1_rsi = 100 - 100 / (1 + h1_g / (h1_l + 1e-9))

        h1_e12 = h1['close'].ewm(span=12, adjust=False).mean()
        h1_e26 = h1['close'].ewm(span=26, adjust=False).mean()
        h1_macd = h1_e12 - h1_e26
        h1_macd_sig = h1_macd.ewm(span=9, adjust=False).mean()

        # H1 ADX
        h1_tr = pd.concat([h1['high']-h1['low'],
                           (h1['high']-h1['close'].shift()).abs(),
                           (h1['low']-h1['close'].shift()).abs()], axis=1).max(axis=1)
        h1_atr = h1_tr.ewm(span=14, adjust=False).mean()
        h1_pdm = (h1['high'].diff()).where((h1['high'].diff() > 0) & (h1['high'].diff() > -h1['low'].diff()), 0.0)
        h1_ndm = (-h1['low'].diff()).where((-h1['low'].diff() > 0) & (-h1['low'].diff() > h1['high'].diff()), 0.0)
        h1_pdi = h1_pdm.ewm(span=14, adjust=False).mean() / (h1_atr + 1e-9) * 100
        h1_ndi = h1_ndm.ewm(span=14, adjust=False).mean() / (h1_atr + 1e-9) * 100
        h1_dx  = (h1_pdi - h1_ndi).abs() / (h1_pdi + h1_ndi + 1e-9) * 100
        h1_adx = h1_dx.ewm(span=14, adjust=False).mean()

        # H4 EMA50
        h4_ema50 = h4['close'].ewm(span=50, adjust=False).mean()

        # ── SON BAR DEGERLERI ────────────────────────────
        i = len(m15) - 1
        price  = float(c.iloc[i])
        e8     = float(ema8.iloc[i])
        e21    = float(ema21.iloc[i])
        e50    = float(ema50.iloc[i])
        e8_2   = float(ema8.iloc[i-2])
        e21_2  = float(ema21.iloc[i-2])
        mm     = float(macd_main.iloc[i])
        ms     = float(macd_sig.iloc[i])
        mh     = float(macd_hist.iloc[i])
        mh_1   = float(macd_hist.iloc[i-1])
        mm_1   = float(macd_main.iloc[i-1])
        ms_1   = float(macd_sig.iloc[i-1])
        adx_v  = float(adx.iloc[i])
        adx_2  = float(adx.iloc[i-2])
        pdi_v  = float(pdi.iloc[i])
        ndi_v  = float(ndi.iloc[i])
        pdi_2  = float(pdi.iloc[i-2])
        ndi_2  = float(ndi.iloc[i-2])
        rsi_v  = float(rsi.iloc[i])
        rsi_1  = float(rsi.iloc[i-1])
        bbu    = float(bb_up.iloc[i])
        bbl    = float(bb_lo.iloc[i])
        bbm    = float(bb_mid.iloc[i])
        bbu_5  = float(bb_up.iloc[i-5])
        bbl_5  = float(bb_lo.iloc[i-5])
        sk     = float(stk.iloc[i])
        sd_v   = float(std.iloc[i])
        sk_2   = float(stk.iloc[i-2])
        sd_2   = float(std.iloc[i-2])
        atr_v  = float(atr14.iloc[i])

        h1_i   = len(h1) - 1
        h4_i   = len(h4) - 1
        h1_e50 = float(h1_ema50.iloc[h1_i])
        h1_r   = float(h1_rsi.iloc[h1_i])
        h1_adx_v = float(h1_adx.iloc[h1_i])
        h1_macd_v = float(h1_macd.iloc[h1_i])
        h1_macd_sig_v = float(h1_macd_sig.iloc[h1_i])
        h4_e50 = float(h4_ema50.iloc[h4_i])
        h1_c   = float(h1['close'].iloc[h1_i])
        h4_c   = float(h4['close'].iloc[h4_i])

        # Volume hesaplari
        vol_avg_20 = float(vol.rolling(20).mean().iloc[i]) if len(vol) >= 20 else float(vol.mean())
        vol_now = float(vol.iloc[i])
        vol_ratio = vol_now / (vol_avg_20 + 1e-9)
        obv_now = float(obv.iloc[i])
        obv_5 = float(obv.iloc[i-5]) if i >= 5 else obv_now

        # NaN kontrolu
        if any(np.isnan(v) for v in [e8, e21, e50, mm, adx_v, rsi_v, bbu, sk, atr_v]):
            return result

        h1_bull = h1_c > h1_e50
        h4_bull = h4_c > h4_e50

        buy  = ScoreBreakdown()
        sell = ScoreBreakdown()

        # ── LAYER 1: EMA RIBBON (0-20) ──────────────────
        bull_align = e8 > e21 > e50
        bear_align = e8 < e21 < e50
        ribbon_width     = abs(e8 - e50)
        ribbon_width_old = abs(e8_2 - float(ema50.iloc[i-2]))
        expanding = ribbon_width > ribbon_width_old * 1.05
        fresh_bull = (e8 > e21) and (e8_2 <= e21_2)
        fresh_bear = (e8 < e21) and (e8_2 >= e21_2)

        if bull_align:
            buy.ema_trend += 8
            if price > e8:  buy.ema_trend += 3
            if h1_bull:     buy.ema_trend += 4
            if expanding:   buy.ema_trend += 3
            if fresh_bull:  buy.ema_trend += 2
        elif e8 > e21:
            buy.ema_trend += 4
            if h1_bull:    buy.ema_trend += 2
            if fresh_bull: buy.ema_trend += 2

        if bear_align:
            sell.ema_trend += 8
            if price < e8:   sell.ema_trend += 3
            if not h1_bull:  sell.ema_trend += 4
            if expanding:    sell.ema_trend += 3
            if fresh_bear:   sell.ema_trend += 2
        elif e8 < e21:
            sell.ema_trend += 4
            if not h1_bull:  sell.ema_trend += 2
            if fresh_bear:   sell.ema_trend += 2

        buy.ema_trend = min(20, buy.ema_trend)
        sell.ema_trend = min(20, sell.ema_trend)

        # ── LAYER 2: MACD MOMENTUM (0-20) ───────────────
        hist_growing = abs(mh) > abs(mh_1)
        near_zero    = abs(mm) < atr_v * 0.3

        bull_div = self._check_divergence(
            [float(l.iloc[i-4]), float(l.iloc[i-2]), float(l.iloc[i])],
            [float(macd_main.iloc[i-4]), float(macd_main.iloc[i-2]), mm], True)
        bear_div = self._check_divergence(
            [float(h.iloc[i-4]), float(h.iloc[i-2]), float(h.iloc[i])],
            [float(macd_main.iloc[i-4]), float(macd_main.iloc[i-2]), mm], False)

        if mm > ms:
            buy.macd_momentum += 6
            if mh > 0 and hist_growing: buy.macd_momentum += 5
            elif mh > 0:                buy.macd_momentum += 3
            if mm > 0:                  buy.macd_momentum += 3
            if near_zero and mh > 0:    buy.macd_momentum += 2
        if bull_div: buy.macd_momentum += 3
        buy.macd_momentum = min(20, buy.macd_momentum)

        if mm < ms:
            sell.macd_momentum += 6
            if mh < 0 and hist_growing: sell.macd_momentum += 5
            elif mh < 0:                sell.macd_momentum += 3
            if mm < 0:                  sell.macd_momentum += 3
            if near_zero and mh < 0:    sell.macd_momentum += 2
        if bear_div: sell.macd_momentum += 3
        sell.macd_momentum = min(20, sell.macd_momentum)

        # ── LAYER 3: ADX STRENGTH (0-15) ────────────────
        if adx_v >= 20:
            adx_rising = adx_v > adx_2
            di_gap = abs(pdi_v - ndi_v)
            fresh_di_bull = (pdi_v > ndi_v) and (pdi_2 <= ndi_2)
            fresh_di_bear = (ndi_v > pdi_v) and (ndi_2 <= pdi_2)

            if pdi_v > ndi_v:
                buy.adx_strength += 6 if adx_v >= 35 else (4 if adx_v >= 25 else 2)
                buy.adx_strength += 4 if di_gap > 15 else (3 if di_gap > 8 else (1 if di_gap > 3 else 0))
                if adx_rising:    buy.adx_strength += 3
                if fresh_di_bull: buy.adx_strength += 2
            buy.adx_strength = min(15, buy.adx_strength)

            if ndi_v > pdi_v:
                sell.adx_strength += 6 if adx_v >= 35 else (4 if adx_v >= 25 else 2)
                sell.adx_strength += 4 if di_gap > 15 else (3 if di_gap > 8 else (1 if di_gap > 3 else 0))
                if adx_rising:    sell.adx_strength += 3
                if fresh_di_bear: sell.adx_strength += 2
            sell.adx_strength = min(15, sell.adx_strength)

        # ── LAYER 4: RSI (0-15) ─────────────────────────
        rsi_rising  = rsi_v > rsi_1
        rsi_falling = rsi_v < rsi_1
        h1_rsi_bull = 40 < h1_r < 75
        h1_rsi_bear = 25 < h1_r < 60

        if 30 <= rsi_v <= 50:
            buy.rsi_level += 5
            if rsi_rising: buy.rsi_level += 3
            if rsi_v < 35: buy.rsi_level += 2
        elif 50 < rsi_v <= 65:
            buy.rsi_level += 3
            if rsi_rising: buy.rsi_level += 2
        elif 65 < rsi_v <= 75:
            buy.rsi_level += 2
        if h1_rsi_bull and buy.rsi_level > 0: buy.rsi_level += 2
        if rsi_v > 75: buy.rsi_level = 0
        buy.rsi_level = min(15, buy.rsi_level)

        if 50 <= rsi_v <= 70:
            sell.rsi_level += 5
            if rsi_falling: sell.rsi_level += 3
            if rsi_v > 65:  sell.rsi_level += 2
        elif 35 <= rsi_v < 50:
            sell.rsi_level += 3
            if rsi_falling: sell.rsi_level += 2
        elif 25 <= rsi_v < 35:
            sell.rsi_level += 2
        if h1_rsi_bear and sell.rsi_level > 0: sell.rsi_level += 2
        if rsi_v < 25: sell.rsi_level = 0
        sell.rsi_level = min(15, sell.rsi_level)

        # ── LAYER 5: BOLLINGER (0-15) ───────────────────
        bb_range = bbu - bbl
        pct_b = 0.5
        squeezing = False
        if bb_range > 0:
            pct_b = (price - bbl) / bb_range
            squeezing = (bbu - bbl) < (bbu_5 - bbl_5) * 0.85

            if pct_b < 0.2:           buy.bb_position += 8
            elif pct_b < 0.35:        buy.bb_position += 5
            elif 0.35 < pct_b < 0.65: buy.bb_position += 3
            if price > bbm and buy.bb_position > 0: buy.bb_position += 2
            if squeezing: buy.bb_position += 3
            buy.bb_position = min(15, buy.bb_position)

            if pct_b > 0.8:           sell.bb_position += 8
            elif pct_b > 0.65:        sell.bb_position += 5
            elif 0.35 < pct_b < 0.65: sell.bb_position += 3
            if price < bbm and sell.bb_position > 0: sell.bb_position += 2
            if squeezing: sell.bb_position += 3
            sell.bb_position = min(15, sell.bb_position)

        # ── LAYER 6: STOCHASTIC (0-10) ──────────────────
        bull_cross = (sk > sd_v) and (sk_2 <= sd_2)
        bear_cross = (sk < sd_v) and (sk_2 >= sd_2)

        if sk < 20:
            buy.stoch_signal += 6
            if bull_cross: buy.stoch_signal += 4
        elif sk < 35:
            buy.stoch_signal += 3
            if bull_cross: buy.stoch_signal += 3
        buy.stoch_signal = min(10, buy.stoch_signal)

        if sk > 80:
            sell.stoch_signal += 6
            if bear_cross: sell.stoch_signal += 4
        elif sk > 65:
            sell.stoch_signal += 3
            if bear_cross: sell.stoch_signal += 3
        sell.stoch_signal = min(10, sell.stoch_signal)

        # ══════════════════════════════════════════════════
        # YENi KATMANLAR (v4.0)
        # ══════════════════════════════════════════════════

        # ── LAYER 7: VOLUME PROFILE (0-15) ──────────────
        obv_rising = obv_now > obv_5
        obv_falling = obv_now < obv_5
        price_up = price > float(c.iloc[i-5]) if i >= 5 else True
        price_dn = price < float(c.iloc[i-5]) if i >= 5 else False

        # Bullish volume: fiyat yukari + OBV yukari + hacim yuksek
        if price_up and obv_rising:
            buy.volume_profile += 8
        elif obv_rising:
            buy.volume_profile += 3
        if vol_ratio > 1.5:  buy.volume_profile += 4
        if vol_ratio > 2.0:  buy.volume_profile += 3
        buy.volume_profile = min(15, buy.volume_profile)

        # Bearish volume
        if price_dn and obv_falling:
            sell.volume_profile += 8
        elif obv_falling:
            sell.volume_profile += 3
        if vol_ratio > 1.5:  sell.volume_profile += 4
        if vol_ratio > 2.0:  sell.volume_profile += 3
        sell.volume_profile = min(15, sell.volume_profile)

        # ── LAYER 8: CANDLE PATTERNS (0-15) ─────────────
        m15_patterns = self._pattern_detector.detect_all(m15, lookback=5)
        h1_patterns = self._pattern_detector.detect_all(h1, lookback=3)

        buy.candle_patterns = self._pattern_detector.score_for_direction(m15_patterns, is_buy=True)
        sell.candle_patterns = self._pattern_detector.score_for_direction(m15_patterns, is_buy=False)

        # H1 dogrulama bonusu
        h1_buy_bonus = self._pattern_detector.score_for_direction(h1_patterns, is_buy=True)
        h1_sell_bonus = self._pattern_detector.score_for_direction(h1_patterns, is_buy=False)
        if h1_buy_bonus > 0 and buy.candle_patterns > 0:
            buy.candle_patterns = min(15, buy.candle_patterns + 3)
        if h1_sell_bonus > 0 and sell.candle_patterns > 0:
            sell.candle_patterns = min(15, sell.candle_patterns + 3)

        # H4 alignment (eski layer 7 mantigi, simdi ek)
        if h4_bull and buy.candle_patterns == 0:
            buy.candle_patterns += 2
        if not h4_bull and sell.candle_patterns == 0:
            sell.candle_patterns += 2

        buy.candle_patterns = min(15, buy.candle_patterns)
        sell.candle_patterns = min(15, sell.candle_patterns)

        # ── LAYER 9: SUPPLY/DEMAND ZONES (0-10) ─────────
        sd_zones = self._sd_detector.detect_zones(m15, lookback=50)
        buy.supply_demand = self._sd_detector.score_proximity(sd_zones, price, is_buy=True)
        sell.supply_demand = self._sd_detector.score_proximity(sd_zones, price, is_buy=False)

        # ── LAYER 10: MTF MOMENTUM CONFLUENCE (0-10) ────
        m15_rsi_bull = 30 < rsi_v < 65
        m15_rsi_bear = 35 < rsi_v < 70
        h1_rsi_bull_zone = 35 < h1_r < 70
        h1_rsi_bear_zone = 30 < h1_r < 65
        m15_macd_bull = mm > ms
        h1_macd_bull = h1_macd_v > h1_macd_sig_v

        # Bullish confluence
        if m15_rsi_bull and h1_rsi_bull_zone and h4_bull:
            buy.mtf_confluence += 4
        if m15_macd_bull and h1_macd_bull:
            buy.mtf_confluence += 3
        if adx_v > 20 and h1_adx_v > 20:
            buy.mtf_confluence += 3
        buy.mtf_confluence = min(10, buy.mtf_confluence)

        # Bearish confluence
        if m15_rsi_bear and h1_rsi_bear_zone and not h4_bull:
            sell.mtf_confluence += 4
        if not m15_macd_bull and not h1_macd_bull:
            sell.mtf_confluence += 3
        if adx_v > 20 and h1_adx_v > 20:
            sell.mtf_confluence += 3
        sell.mtf_confluence = min(10, sell.mtf_confluence)

        # ── LAYER 11: MARKET REGIME (carpan) ────────────
        ema_aligned = bull_align or bear_align
        bb_width_pct = bb_range / (price + 1e-9) * 100 if price > 0 else 0
        regime = detect_regime(adx_v, atr_pct, ema_aligned, bb_width_pct)
        regime_mult = get_regime_multiplier(regime)

        # ── LAYER 12: SENTIMENT OVERLAY (0-5) ───────────
        sent = self._sentiment_scores.get(self.symbol, 0.0)
        if sent > 50:
            buy.sentiment += 5
        elif sent > 20:
            buy.sentiment += 2
        if sent < -50:
            sell.sentiment += 5
        elif sent < -20:
            sell.sentiment += 2
        # Ters yon penalti
        if sent < -30:
            buy.sentiment = max(0, buy.sentiment - 3)
        if sent > 30:
            sell.sentiment = max(0, sell.sentiment - 3)

        # ── SONUC ────────────────────────────────────────
        result.buy  = buy
        result.sell = sell
        result.adx  = adx_v
        result.rsi  = rsi_v
        result.atr  = atr_v
        result.atr_percentile = float(atr_pct)
        result.h1_bull = h1_bull
        result.h4_bull = h4_bull
        result.regime = regime
        result.regime_multiplier = regime_mult
        result.patterns_found = m15_patterns[:5]
        result.sd_zones = sd_zones[:5]
        result.volume_ratio = vol_ratio
        result.bb_pct_b = pct_b
        result.stoch_k = sk

        # Trend gucu
        result.trend_str = (Trend.STRONG if adx_v >= 35 else
                            Trend.MODERATE if adx_v >= 25 else Trend.WEAK)
        result.trend_dir = Dir.BUY if h1_bull else Dir.SELL

        # Mum yonu (en son kapanmis bar)
        result.candle_dir = self._get_candle_dir(m15)

        # Onay trend guncelle
        self._update_confirmed_trend(h1_bull, h4_bull)

        # Dinamik esik hesapla
        sentiment_vol = "HIGH" if abs(sent) > 60 else "NORMAL"
        threshold = self._calc_dynamic_threshold(regime, session, sentiment_vol)
        result.threshold = threshold

        # Ham skor (regime carpani oncesi)
        bs_raw = buy.total
        ss_raw = sell.total

        # Regime carpanli skor
        bs = int(bs_raw * regime_mult)
        ss = int(ss_raw * regime_mult)

        result.raw_score = max(bs_raw, ss_raw)

        # Yon karari (dinamik esikle)
        if bs >= threshold and bs > ss:
            result.direction = Dir.BUY
            result.score = bs
        elif ss >= threshold and ss > bs:
            result.direction = Dir.SELL
            result.score = ss
        else:
            result.direction = Dir.NONE
            result.score = max(bs, ss)

        # v5.0: Son sonucu sakla (Strategy Agent icin)
        self._last_result = result
        return result

    # ─── YARDIMCI FONKSIYONLAR ────────────────────────────

    def _calc_dynamic_threshold(self, regime: MarketRegime, session: str,
                                 sentiment_vol: str) -> int:
        """Dinamik sinyal esigi hesapla"""
        base = cfg.SIGNAL_BASE_THRESHOLD  # 55

        # Regime ayarlamasi
        if regime == MarketRegime.STRONG_TREND:
            base -= 10   # Trendde daha kolay gir
        elif regime == MarketRegime.TREND:
            base -= 5
        elif regime == MarketRegime.CHOPPY:
            base += 15   # Choppy'de cok zor gir
        elif regime == MarketRegime.VOLATILE:
            base += 5
        elif regime == MarketRegime.RANGE:
            base += 5

        # Session ayarlamasi
        if session in ("LONDON_NY_OVERLAP", "LONDON"):
            base -= 5    # Yuksek likidite
        elif session == "OFF_HOURS":
            base += 10   # Dusuk likidite

        # Sentiment volatilite
        if sentiment_vol == "HIGH":
            base += 5    # Haber oncesi ihtiyat

        return max(cfg.SIGNAL_MIN_THRESHOLD, min(cfg.SIGNAL_MAX_THRESHOLD, base))

    def _check_divergence(self, prices: list, indicator: list, is_bull: bool) -> bool:
        """Basit 3-nokta diverjans tespiti"""
        if len(prices) < 3 or len(indicator) < 3:
            return False
        if is_bull:
            return prices[2] < prices[0] and indicator[2] > indicator[0]
        else:
            return prices[2] > prices[0] and indicator[2] < indicator[0]

    def _get_candle_dir(self, m15: pd.DataFrame) -> Dir:
        """Son kapanan mum yonu"""
        if len(m15) < 2:
            return Dir.NONE
        bar = m15.iloc[-2]
        body = bar['close'] - bar['open']
        candle_size = bar['high'] - bar['low']
        if candle_size < 1e-10:
            return Dir.NONE
        body_pct = abs(body) / candle_size
        if body_pct < 0.30:
            return Dir.NONE
        return Dir.BUY if body > 0 else Dir.SELL

    def _update_confirmed_trend(self, h1_bull: bool, h4_bull: bool):
        """Trend onay sayaci"""
        current = Dir.BUY if (h1_bull and h4_bull) else (Dir.SELL if (not h1_bull and not h4_bull) else Dir.NONE)
        if current == Dir.NONE:
            self._trend_confirm = 0
            return
        if current == self._pending_trend:
            self._trend_confirm += 1
        else:
            self._pending_trend = current
            self._trend_confirm = 1
        if self._trend_confirm >= cfg.TREND_CONFIRM_COUNT:
            self._trend_dir = current

    def get_confirmed_trend(self) -> Dir:
        return self._trend_dir

    def check_peak_dip_gate(self, rsi: float, adx: float, candle_dir: Dir) -> Tuple[bool, Dir]:
        """RSI asiri bolge kontrolu"""
        is_peak = rsi > 75
        is_dip  = rsi < 25
        if not is_peak and not is_dip:
            return True, Dir.NONE
        trend = self._trend_dir
        if adx >= 45:
            return True, trend
        elif adx <= 40:
            return False, Dir.NONE
        else:
            return True, trend
