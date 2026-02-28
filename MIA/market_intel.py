"""
Market Intelligence v4.0 — Piyasa Veri Toplayici + Regime Detection + Sentiment
Claude'a sunulacak tum ham verileri toplar:
  - MT5: OHLCV, indikatorler, pozisyonlar, hesap
  - Haber: Ekonomik takvim (ForexFactory uyumlu)
  - Sentiment: Fear & Greed index + SentimentEngine entegrasyonu
  - Teknik: Coklu zaman dilimi analiz + Market Regime
  - DXY: EURUSD'den ters korelasyon tahmini
Copyright 2026, By T@MER — https://www.bytamer.com
"""

import time
import logging
import requests
import json
import hashlib
import numpy as np
import pandas as pd
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Tuple
from dataclasses import dataclass, field, asdict
import config as cfg
from patterns import detect_regime, get_regime_multiplier, MarketRegime, CandlePatternDetector, SupplyDemandDetector

log = logging.getLogger("MarketIntel")


@dataclass
class CandleData:
    tf: str
    open: float; high: float; low: float; close: float
    volume: float; time: str
    body_pct: float      # Govde / toplam uzunluk
    direction: str       # BUY / SELL / DOJI
    upper_wick: float    # Ust fitil orani
    lower_wick: float    # Alt fitil orani


@dataclass
class TechnicalSnapshot:
    symbol: str
    price: float
    # Trend
    ema8: float; ema21: float; ema50: float
    ema_h1: float; ema_h4: float
    trend_aligned: str       # "STRONG_BULL" / "BULL" / "NEUTRAL" / "BEAR" / "STRONG_BEAR"
    # Momentum
    macd_hist: float
    macd_cross: str          # "FRESH_BULL" / "FRESH_BEAR" / "NONE"
    # Guc
    adx: float
    rsi_m15: float; rsi_h1: float
    # Volatilite
    atr_m15: float
    atr_percentile: float    # 0-100 (100 = tarihsel max)
    bb_position: float       # 0-100 (0=alt, 50=orta, 100=ust)
    # Stokastik
    stoch_k: float; stoch_d: float
    stoch_zone: str          # "OVERSOLD" / "NEUTRAL" / "OVERBOUGHT"
    # Yapi
    higher_high: bool; higher_low: bool  # Son 5 bar yapisi
    key_level_proximity: float           # En yakin destek/dirence uzaklik (pip)
    # Mumlar
    candles: List[CandleData] = field(default_factory=list)
    candles_m15: List[CandleData] = field(default_factory=list)  # Dashboard icin son 60 bar
    # MIA v4.0 — Regime Detection
    regime: str = "RANGE"                # STRONG_TREND / TREND / RANGE / VOLATILE / CHOPPY
    regime_multiplier: float = 1.0       # Regime'e gore skor carpani
    volume_ratio: float = 1.0            # current volume / 20-bar average
    bb_width_pct: float = 0.0            # bollinger width / price * 100
    # MIA v5.0 — Strategy Agent icin zenginlestirilmis veri
    patterns_found: List[str] = field(default_factory=list)    # ["bullish_engulfing(10)", "hammer(8)"]
    sd_zones: List[str] = field(default_factory=list)           # ["DEMAND@1.2340(str=3)", "SUPPLY@1.2450(str=2)"]
    spread_current: float = 0.0                                  # Anlik spread (pip)
    spread_ratio: float = 0.0                                    # spread / ATR orani


@dataclass
class AccountState:
    balance: float
    equity: float
    margin: float
    margin_free: float
    margin_level: float
    floating_pnl: float
    daily_pnl: float
    drawdown_pct: float
    leverage: int
    open_positions: int
    # Sembol bazli acik pozisyon ozeti
    positions_summary: Dict = field(default_factory=dict)


@dataclass
class NewsItem:
    time: str
    currency: str
    event: str
    impact: str          # "HIGH" / "MEDIUM" / "LOW"
    actual: str; forecast: str; previous: str
    minutes_until: int   # Negatif = gecti


@dataclass
class MarketContext:
    timestamp: str
    fear_greed_index: int         # 0-100
    fear_greed_label: str         # "Extreme Fear" -> "Extreme Greed"
    upcoming_news: List[NewsItem]  # Onumuzdeki 4 saatteki haberler
    recent_news: List[NewsItem]    # Son 2 saatte gecen yuksek etkili haberler
    session: str                   # "TOKYO" / "LONDON" / "NEW_YORK" / "OVERLAP"
    day_of_week: str
    is_holiday: bool


@dataclass
class FullMarketSnapshot:
    """Claude'a sunulacak tam piyasa goruntusu"""
    account: AccountState
    technicals: Dict[str, TechnicalSnapshot]  # sembol -> snapshot
    context: MarketContext
    generated_at: str
    # MIA v4.0 — Regime & Sentiment
    regimes: Dict[str, str] = field(default_factory=dict)           # symbol -> regime name
    sentiment_scores: Dict[str, float] = field(default_factory=dict)  # symbol -> sentiment score


class MarketIntelligence:
    """
    Tum piyasa verisini toplayan ve Claude icin hazirlayan sinif.
    MIA v4.0: Market Regime, Volume Ratio, DXY Estimation, Sentiment entegrasyonu.
    """

    def __init__(self, mt5_bridge):
        self.bridge       = mt5_bridge
        self._news_cache  = []
        self._fg_cache    = {"value": 50, "label": "Neutral", "ts": 0}
        self._last_news   = 0.0
        self._day_open_balance = 0.0
        self._day_start_ts     = 0.0
        # MIA v4.0 — Sentiment Engine entegrasyonu
        self._sentiment_scores: Dict[str, float] = {}

    # ---------------------------------------------------------
    # SENTIMENT ENTEGRASYONU
    # ---------------------------------------------------------

    def set_sentiment_scores(self, scores: Dict[str, float]):
        """Sentiment Engine'den gelen skorlari kaydet"""
        if not isinstance(scores, dict):
            log.warning("set_sentiment_scores: gecersiz tip, dict bekleniyor")
            return
        self._sentiment_scores = scores.copy()
        log.debug(f"Sentiment skorlari guncellendi: {len(scores)} sembol")

    # ---------------------------------------------------------
    # DXY TAHMINI — EURUSD ters korelasyon
    # ---------------------------------------------------------

    def get_dxy_estimate(self) -> float:
        """EURUSD'den DXY tahmini (ters korelasyon)"""
        try:
            m15 = self.bridge.get_ohlcv("EURUSD", "M15", 30)
            if len(m15) < 20:
                return 0.0
            eur_c = m15['close']
            ema8 = eur_c.ewm(span=8, adjust=False).mean()
            ema21 = eur_c.ewm(span=21, adjust=False).mean()
            if ema8.iloc[-1] > ema21.iloc[-1]:
                return -50.0  # EUR up = DXY down
            else:
                return 50.0   # EUR down = DXY up
        except Exception as e:
            log.debug(f"DXY tahmini alinamadi: {e}")
            return 0.0

    # ---------------------------------------------------------
    # ANA SNAPSHOT — Claude'a verilecek tam paket
    # ---------------------------------------------------------

    def get_snapshot(self, symbols: List[str]) -> FullMarketSnapshot:
        account  = self._get_account()
        tech     = {}
        regimes  = {}
        for sym in symbols:
            try:
                snap = self._get_technical(sym, account)
                if snap:
                    tech[sym] = snap
                    regimes[sym] = snap.regime
            except Exception as e:
                log.warning(f"[{sym}] Teknik veri hatasi: {e}", exc_info=True)

        context  = self._get_market_context()

        # Sentiment skorlarini snapshot'a ekle (set edilmisse)
        sentiment = self._sentiment_scores.copy() if self._sentiment_scores else {}

        return FullMarketSnapshot(
            account      = account,
            technicals   = tech,
            context      = context,
            generated_at = datetime.utcnow().strftime("%Y-%m-%d %H:%M:%S UTC"),
            regimes      = regimes,
            sentiment_scores = sentiment,
        )

    # ---------------------------------------------------------
    # HESAP
    # ---------------------------------------------------------

    def _get_account(self) -> AccountState:
        acc = self.bridge.get_account()
        balance = acc.get("balance", cfg.INITIAL_BALANCE)
        equity  = acc.get("equity",  balance)
        dd_pct  = max(0, (balance - equity) / balance * 100) if balance > 0 else 0

        # Gunluk PnL
        now = time.time()
        if now - self._day_start_ts > 86400:
            self._day_open_balance = balance
            self._day_start_ts     = now
        daily = balance + acc.get("profit", 0) - self._day_open_balance

        # Pozisyon ozeti
        all_pos = self.bridge.get_all_positions()
        pos_summary = {}
        for p in all_pos:
            sym = p["symbol"]
            if sym not in pos_summary:
                pos_summary[sym] = {"count": 0, "buy_lots": 0, "sell_lots": 0, "pnl": 0}
            pos_summary[sym]["count"] += 1
            if p["type"] == 0:
                pos_summary[sym]["buy_lots"]  += p["volume"]
            else:
                pos_summary[sym]["sell_lots"] += p["volume"]
            pos_summary[sym]["pnl"] += p["profit"]

        return AccountState(
            balance       = balance,
            equity        = equity,
            margin        = acc.get("margin", 0),
            margin_free   = acc.get("margin_free", balance),
            margin_level  = acc.get("margin_level", 0),
            floating_pnl  = acc.get("profit", 0),
            daily_pnl     = daily,
            drawdown_pct  = dd_pct,
            leverage      = acc.get("leverage", cfg.LEVERAGE),
            open_positions= len(all_pos),
            positions_summary = pos_summary,
        )

    # ---------------------------------------------------------
    # TEKNIK ANALIZ
    # ---------------------------------------------------------

    def _get_technical(self, symbol: str, account: AccountState) -> Optional[TechnicalSnapshot]:
        m15 = self.bridge.get_ohlcv(symbol, cfg.PRIMARY_TF, 200)
        h1  = self.bridge.get_ohlcv(symbol, cfg.TREND_TF,  100)
        h4  = self.bridge.get_ohlcv(symbol, cfg.UPPER_TF,  50)

        if len(m15) < 60:
            return None

        c  = m15['close']
        h  = m15['high']
        l  = m15['low']
        op = m15['open']
        price = float(c.iloc[-1])

        # EMA
        ema8  = float(c.ewm(span=8,  adjust=False).mean().iloc[-1])
        ema21 = float(c.ewm(span=21, adjust=False).mean().iloc[-1])
        ema50 = float(c.ewm(span=50, adjust=False).mean().iloc[-1])
        ema_h1= float(h1['close'].ewm(span=50, adjust=False).mean().iloc[-1])
        ema_h4= float(h4['close'].ewm(span=50, adjust=False).mean().iloc[-1])

        # Trend hizalamasi
        h1c = float(h1['close'].iloc[-1])
        h4c = float(h4['close'].iloc[-1])
        m15_bull = ema8 > ema21 > ema50
        m15_bear = ema8 < ema21 < ema50
        h1_bull  = h1c > ema_h1
        h4_bull  = h4c > ema_h4

        if m15_bull and h1_bull and h4_bull:   trend = "STRONG_BULL"
        elif m15_bull and h1_bull:             trend = "BULL"
        elif m15_bear and not h1_bull and not h4_bull: trend = "STRONG_BEAR"
        elif m15_bear and not h1_bull:         trend = "BEAR"
        else:                                  trend = "NEUTRAL"

        # EMA alignment for regime detection
        ema_aligned = m15_bull or m15_bear

        # MACD
        e12   = c.ewm(span=12, adjust=False).mean()
        e26   = c.ewm(span=26, adjust=False).mean()
        macd  = e12 - e26
        sig   = macd.ewm(span=9, adjust=False).mean()
        hist  = macd - sig
        mh    = float(hist.iloc[-1])
        mh_1  = float(hist.iloc[-2])
        mm    = float(macd.iloc[-1])
        ms    = float(sig.iloc[-1])
        mm_1  = float(macd.iloc[-2])
        ms_1  = float(sig.iloc[-2])
        if mm > ms and mm_1 <= ms_1: macd_cross = "FRESH_BULL"
        elif mm < ms and mm_1 >= ms_1: macd_cross = "FRESH_BEAR"
        else: macd_cross = "NONE"

        # ATR
        tr    = pd.concat([h-l,(h-c.shift()).abs(),(l-c.shift()).abs()],axis=1).max(axis=1)
        atr14 = tr.ewm(span=14, adjust=False).mean()
        atr_v = float(atr14.iloc[-1])
        atr_pct = float(pd.Series(atr14).rank(pct=True).iloc[-1] * 100)

        # ADX
        pdm = (h.diff()).where((h.diff()>0)&(h.diff()>-l.diff()),0.0)
        ndm = (-l.diff()).where((-l.diff()>0)&(-l.diff()>h.diff()),0.0)
        pdi = pdm.ewm(span=14,adjust=False).mean()/(atr14+1e-9)*100
        ndi = ndm.ewm(span=14,adjust=False).mean()/(atr14+1e-9)*100
        dx  = (pdi-ndi).abs()/(pdi+ndi+1e-9)*100
        adx_v = float(dx.ewm(span=14,adjust=False).mean().iloc[-1])

        # RSI — pandas Series'ten guvenli scalar cekme
        def _rsi(series):
            d_ = series.diff()
            g_ = d_.clip(lower=0).ewm(span=14, adjust=False).mean()
            l_ = (-d_.clip(upper=0)).ewm(span=14, adjust=False).mean()
            return float((100 - 100 / (1 + g_ / (l_ + 1e-9))).iloc[-1])

        rsi_m15 = _rsi(c)
        rsi_h1  = _rsi(h1['close'])

        # Bollinger
        bb_m = c.rolling(20).mean()
        bb_s = c.rolling(20).std()
        bbu = float((bb_m + 2 * bb_s).iloc[-1])
        bbl = float((bb_m - 2 * bb_s).iloc[-1])
        bb_pos = (price - bbl) / (bbu - bbl) * 100 if bbu > bbl else 50

        # MIA v4.0 — Bollinger Width % (bant genisligi / fiyat * 100)
        bb_width_pct_val = (bbu - bbl) / price * 100 if price > 0 else 0.0

        # Stokastik
        lo14 = l.rolling(14).min()
        hi14 = h.rolling(14).max()
        stk = (c - lo14) / (hi14 - lo14 + 1e-9) * 100
        std = stk.rolling(3).mean()
        sk = float(stk.iloc[-1])
        sd = float(std.iloc[-1])
        if sk < 20: stoch_zone = "OVERSOLD"
        elif sk > 80: stoch_zone = "OVERBOUGHT"
        else: stoch_zone = "NEUTRAL"

        # Market yapisi (son 5 bar)
        highs = list(h.iloc[-6:-1])
        lows = list(l.iloc[-6:-1])
        hh = highs[-1] > highs[-2] and highs[-2] > highs[-3]
        hl = lows[-1] > lows[-2] and lows[-2] > lows[-3]

        # Key level proximity (basit: BB band mesafesi)
        pip = cfg.SYMBOL_SPECS.get(symbol, {}).get("pip", 0.0001)
        key_prox = min(abs(price - bbu), abs(price - bbl)) / pip

        # MIA v4.0 — Volume Ratio (son bar hacim / 20-bar ortalama)
        volume_ratio_val = 1.0
        try:
            vol_col = None
            if 'tick_volume' in m15.columns:
                vol_col = 'tick_volume'
            elif 'volume' in m15.columns:
                vol_col = 'volume'
            if vol_col is not None:
                vol_series = m15[vol_col].astype(float)
                last_vol = vol_series.iloc[-1]
                avg_vol_20 = vol_series.iloc[-21:-1].mean() if len(vol_series) >= 21 else vol_series.mean()
                volume_ratio_val = last_vol / avg_vol_20 if avg_vol_20 > 0 else 1.0
        except Exception as e:
            log.debug(f"[{symbol}] Volume ratio hesaplanamadi: {e}")
            volume_ratio_val = 1.0

        # MIA v4.0 — Regime Detection
        try:
            regime_enum = detect_regime(adx_v, atr_pct, ema_aligned, bb_width_pct_val)
            regime_name = regime_enum.value
            regime_mult = get_regime_multiplier(regime_enum)
        except Exception as e:
            log.debug(f"[{symbol}] Regime tespit hatasi: {e}")
            regime_name = "RANGE"
            regime_mult = 1.0

        # Son 60 mum — dashboard chart icin
        candles_m15 = []
        n_bars = min(60, len(m15))
        for i in range(-n_bars, 0):
            try:
                bar = m15.iloc[i]
                candles_m15.append(CandleData(
                    tf='M15', open=float(bar['open']), high=float(bar['high']),
                    low=float(bar['low']), close=float(bar['close']),
                    volume=float(bar['volume']) if 'volume' in bar.index else 0.0,
                    time=str(m15.index[i]),
                    body_pct=0, direction='', upper_wick=0, lower_wick=0,
                ))
            except Exception:
                pass

        # Son 5 mumun analizi
        candles = []
        for i in range(-5, 0):
            bar = m15.iloc[i]
            body  = float(bar['close']) - float(bar['open'])
            total = float(bar['high'])  - float(bar['low'])
            if total < 1e-10:
                continue
            body_pct  = abs(body) / total
            upper_wick= (float(bar['high']) - max(float(bar['close']),float(bar['open']))) / total
            lower_wick= (min(float(bar['close']),float(bar['open'])) - float(bar['low'])) / total
            direction = "BUY" if body>0 else ("SELL" if body<0 else "DOJI")
            vol = float(bar['volume']) if 'volume' in bar.index else 0.0
            candles.append(CandleData(
                tf="M15", open=float(bar['open']), high=float(bar['high']),
                low=float(bar['low']), close=float(bar['close']), volume=vol,
                time=str(m15.index[i]),
                body_pct=round(body_pct,2), direction=direction,
                upper_wick=round(upper_wick,2), lower_wick=round(lower_wick,2),
            ))

        # ── MIA v5.0: Mum Formasyonlari + Destek/Direnc + Spread ──
        patterns_found_list = []
        sd_zones_list = []
        spread_current_val = 0.0
        spread_ratio_val = 0.0

        try:
            _cpd = CandlePatternDetector()
            cp_results = _cpd.detect_all(m15, lookback=5)
            for cp in cp_results[:5]:  # En guclu 5 pattern
                patterns_found_list.append(f"{cp.name}({cp.score})")
        except Exception:
            pass

        try:
            _sdd = SupplyDemandDetector()
            sd_results = _sdd.detect_zones(m15, lookback=50)
            for z in sd_results[:6]:  # En guclu 6 zone
                sd_zones_list.append(
                    f"{z.type.value.upper()}@{z.level:.5f}(guc={z.strength:.0f},test={z.touch_count})"
                )
        except Exception:
            pass

        try:
            import MetaTrader5 as mt5
            tick = mt5.symbol_info_tick(self.bridge._sym(symbol))
            if tick and tick.ask > 0 and tick.bid > 0:
                raw_spread = tick.ask - tick.bid
                pip_val = cfg.SYMBOL_SPECS.get(symbol, {}).get("pip", 0.0001)
                spread_current_val = round(raw_spread / pip_val, 2) if pip_val > 0 else 0.0
                spread_ratio_val = round(raw_spread / atr_v * 100, 1) if atr_v > 0 else 0.0
        except Exception:
            pass

        return TechnicalSnapshot(
            symbol=symbol, price=price,
            ema8=ema8, ema21=ema21, ema50=ema50, ema_h1=ema_h1, ema_h4=ema_h4,
            trend_aligned=trend,
            macd_hist=round(mh,6), macd_cross=macd_cross,
            adx=round(adx_v,1),
            rsi_m15=round(rsi_m15,1), rsi_h1=round(rsi_h1,1),
            atr_m15=round(atr_v,5), atr_percentile=round(atr_pct,1),
            bb_position=round(bb_pos,1),
            stoch_k=round(sk,1), stoch_d=round(sd,1), stoch_zone=stoch_zone,
            higher_high=hh, higher_low=hl,
            key_level_proximity=round(key_prox,1),
            candles=candles,
            candles_m15=candles_m15,
            # MIA v4.0 yeni alanlar
            regime=regime_name,
            regime_multiplier=round(regime_mult, 2),
            volume_ratio=round(volume_ratio_val, 2),
            bb_width_pct=round(bb_width_pct_val, 3),
            # MIA v5.0 zenginlestirilmis veri
            patterns_found=patterns_found_list,
            sd_zones=sd_zones_list,
            spread_current=spread_current_val,
            spread_ratio=spread_ratio_val,
        )

    # ---------------------------------------------------------
    # PIYASA BAGLAMI — Haber + Seans + Fear&Greed
    # ---------------------------------------------------------

    def _get_market_context(self) -> MarketContext:
        # Fear & Greed (15dk cache)
        fg = self._get_fear_greed()

        # Haber (15dk cache)
        news = self._get_news_cached()

        # Seans
        session   = self._get_session()
        now_utc   = datetime.utcnow()
        dow       = now_utc.strftime("%A")
        is_holiday= dow in ("Saturday","Sunday")

        # Yaklasan yuksek etkili haberler (4 saat icinde)
        upcoming = [n for n in news
                    if n.impact == "HIGH" and 0 <= n.minutes_until <= 240]
        recent   = [n for n in news
                    if n.impact == "HIGH" and -120 <= n.minutes_until < 0]

        return MarketContext(
            timestamp       = now_utc.strftime("%Y-%m-%d %H:%M UTC"),
            fear_greed_index= fg["value"],
            fear_greed_label= fg["label"],
            upcoming_news   = upcoming[:6],
            recent_news     = recent[:4],
            session         = session,
            day_of_week     = dow,
            is_holiday      = is_holiday,
        )

    def _get_fear_greed(self) -> dict:
        if time.time() - self._fg_cache["ts"] < 900:
            return self._fg_cache
        try:
            r = requests.get(cfg.MARKET_CONTEXT_URL, timeout=5)
            d = r.json()["data"][0]
            self._fg_cache = {
                "value": int(d["value"]),
                "label": d["value_classification"],
                "ts":    time.time()
            }
        except Exception as e:
            log.debug(f"Fear&Greed alinamadi: {e}")
        return self._fg_cache

    def _get_news_cached(self) -> List[NewsItem]:
        """Ekonomik takvim — 15dk cache, ForexFactory benzeri format"""
        if time.time() - self._last_news < cfg.NEWS_FETCH_INTERVAL:
            return self._news_cache

        try:
            items = self._fetch_news()
            self._news_cache = items
            self._last_news  = time.time()
            log.debug(f"Haberler guncellendi: {len(items)} etkinlik")
        except Exception as e:
            log.debug(f"Haber alinamadi: {e}")

        return self._news_cache

    def _fetch_news(self) -> List[NewsItem]:
        """
        ForexFactory uyumlu haber kaynagi.
        Gercek dagitimda bir haber API'sina baglanin.
        Burada: fallback olarak bos liste veya demo data.
        """
        # Demo: gercek implementasyonda bir API'ye baglanin
        # Ornek: https://nfs.faireconomy.media/ff_calendar_thisweek.json
        try:
            r = requests.get(
                "https://nfs.faireconomy.media/ff_calendar_thisweek.json",
                timeout=8
            )
            raw = r.json()
            now_utc = datetime.utcnow()
            items = []
            for ev in raw:
                try:
                    ev_time = datetime.strptime(ev["date"], "%Y-%m-%dT%H:%M:%S%z").replace(tzinfo=None)
                    minutes_until = int((ev_time - now_utc).total_seconds() / 60)
                    impact_map = {"High": "HIGH", "Medium": "MEDIUM", "Low": "LOW"}
                    items.append(NewsItem(
                        time       = ev_time.strftime("%H:%M"),
                        currency   = ev.get("country", ""),
                        event      = ev.get("title", ""),
                        impact     = impact_map.get(ev.get("impact",""), "LOW"),
                        actual     = str(ev.get("actual", "")),
                        forecast   = str(ev.get("forecast", "")),
                        previous   = str(ev.get("previous", "")),
                        minutes_until = minutes_until,
                    ))
                except:
                    continue
            return items
        except:
            return []

    def _get_session(self) -> str:
        h = datetime.utcnow().hour
        # Tokyo: 00-09 UTC, London: 07-16 UTC, NY: 12-21 UTC
        tokyo   = 0 <= h < 9
        london  = 7 <= h < 16
        ny      = 12 <= h < 21
        if london and ny:   return "LONDON_NY_OVERLAP"
        if tokyo and london: return "TOKYO_LONDON_OVERLAP"
        if ny:    return "NEW_YORK"
        if london: return "LONDON"
        if tokyo:  return "TOKYO"
        return "OFF_HOURS"

    # ---------------------------------------------------------
    # PROMPT FORMATLAMA
    # ---------------------------------------------------------

    def format_for_claude(self, snapshot: FullMarketSnapshot,
                           focus_symbols: List[str] = None) -> str:
        """
        FullMarketSnapshot -> Claude'un anlayacagi yapilandirilmis metin.
        Tum gereksiz gurultuyu cikar, kritik bilgileri one cikar.
        MIA v4.0: Regime, Sentiment, Volume bilgileri eklendi.
        """
        acc = snapshot.account
        ctx = snapshot.context
        lines = []

        # -- HESAP DURUMU ----------------------------------------
        lines.append("=== HESAP DURUMU ===")
        lines.append(f"Bakiye: ${acc.balance:.2f} | Equity: ${acc.equity:.2f} | Float P&L: ${acc.floating_pnl:+.2f}")
        lines.append(f"Gunluk P&L: ${acc.daily_pnl:+.2f} | Drawdown: {acc.drawdown_pct:.1f}% | Margin: {acc.margin_level:.0f}%")
        lines.append(f"Acik Pozisyon: {acc.open_positions} | Kaldirac: 1:{acc.leverage}")

        if acc.positions_summary:
            lines.append("Acik Pozisyonlar:")
            for sym, info in acc.positions_summary.items():
                lines.append(f"  {sym}: {info['count']} poz | BUY={info['buy_lots']:.2f}lot SELL={info['sell_lots']:.2f}lot | P&L=${info['pnl']:+.2f}")

        # -- PIYASA BAGLAMI --------------------------------------
        lines.append("\n=== PIYASA BAGLAMI ===")
        lines.append(f"Seans: {ctx.session} | {ctx.day_of_week} | {ctx.timestamp}")
        lines.append(f"Fear & Greed: {ctx.fear_greed_index}/100 ({ctx.fear_greed_label})")
        if ctx.is_holiday:
            lines.append("!! HAFTA SONU -- Likidite dusuk, spread yuksek")

        if ctx.upcoming_news:
            lines.append(f"\nYaklasan Yuksek Etkili Haberler ({len(ctx.upcoming_news)}):")
            for n in ctx.upcoming_news[:4]:
                lines.append(f"  >> {n.time} UTC | {n.currency} | {n.event} | {n.minutes_until}dk kaldi")

        if ctx.recent_news:
            lines.append(f"\nSon Gecen Haberler:")
            for n in ctx.recent_news[:3]:
                actual_vs = f"Gercek:{n.actual} vs Beklenti:{n.forecast}" if n.actual else ""
                lines.append(f"  >> {n.time} UTC | {n.currency} | {n.event} | {actual_vs}")

        # -- TEKNIK ANALIZ ----------------------------------------
        syms = focus_symbols or list(snapshot.technicals.keys())
        lines.append(f"\n=== TEKNIK ANALIZ ({len(syms)} SEMBOL) ===")

        for sym in syms:
            t = snapshot.technicals.get(sym)
            if not t:
                continue

            lines.append(f"\n-- {sym} --")
            lines.append(f"Fiyat: {t.price:.5f} | Trend: {t.trend_aligned}")

            # MIA v4.0 — Regime bilgisi
            lines.append(f"REGIME: {t.regime} ({t.regime_multiplier}x)")

            # MIA v4.0 — Sentiment bilgisi
            sent_score = snapshot.sentiment_scores.get(sym, 0.0)
            if sent_score != 0.0:
                if sent_score > 20:
                    sent_label = "GREED"
                elif sent_score > 0:
                    sent_label = "MILD_GREED"
                elif sent_score > -20:
                    sent_label = "MILD_FEAR"
                else:
                    sent_label = "FEAR"
                lines.append(f"SENTIMENT: {sent_score:+.0f} ({sent_label})")

            # MIA v4.0 — Volume bilgisi
            vol_label = "normal"
            if t.volume_ratio >= 2.0:
                vol_label = "cok yuksek"
            elif t.volume_ratio >= 1.5:
                vol_label = "yuksek"
            elif t.volume_ratio <= 0.5:
                vol_label = "dusuk"
            lines.append(f"VOLUME: {t.volume_ratio:.1f}x ({vol_label}) | BB Width: {t.bb_width_pct:.2f}%")

            lines.append(f"EMA: 8={t.ema8:.5f} 21={t.ema21:.5f} 50={t.ema50:.5f}")
            lines.append(f"H1 EMA50: {t.ema_h1:.5f} | H4 EMA50: {t.ema_h4:.5f}")
            lines.append(f"MACD Hist: {t.macd_hist:+.6f} | Capraz: {t.macd_cross}")
            lines.append(f"ADX: {t.adx:.1f} | RSI M15: {t.rsi_m15:.1f} | RSI H1: {t.rsi_h1:.1f}")
            lines.append(f"ATR M15: {t.atr_m15:.5f} (persentil: {t.atr_percentile:.0f}%ile)")
            lines.append(f"BB Pozisyon: {t.bb_position:.0f}% | Stoch K/D: {t.stoch_k:.1f}/{t.stoch_d:.1f} [{t.stoch_zone}]")
            lines.append(f"Yapi: HH={t.higher_high} HL={t.higher_low} | Key Level: {t.key_level_proximity:.0f} pip uzak")

            if t.candles:
                csum = " | ".join([f"{c.direction}({c.body_pct:.0%})" for c in t.candles[-3:]])
                lines.append(f"Son 3 Mum: {csum}")

        return "\n".join(lines)
