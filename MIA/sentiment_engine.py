"""
MIA v4.0 — Sentiment & News Analysis Engine
Coklu kaynak sentiment analizi: Fear&Greed, Haber Takvimi, RSS, DXY Trendi
Her sembol icin agirlikli sentiment skoru hesaplar.
Copyright 2026, By T@MER — https://www.bytamer.com
"""

import time
import logging
import xml.etree.ElementTree as ET
from dataclasses import dataclass, field, asdict
from typing import Dict, List, Optional, Tuple
import requests

import config as cfg

log = logging.getLogger("SentimentEngine")


# ─── VERI YAPILARI ──────────────────────────────────────────────

@dataclass
class SentimentScore:
    """Tek bir sembol icin hesaplanmis sentiment skoru"""
    value: float                    # -100 (extreme bearish) ... +100 (extreme bullish)
    label: str                      # EXTREME_FEAR / FEAR / NEUTRAL / GREED / EXTREME_GREED
    news_blackout: bool             # True = HIGH impact haber 15dk icinde
    volatility_expected: str        # HIGH / NORMAL / LOW
    sources: Dict[str, float]       # Kaynak bazinda skor kirilimi
    upcoming_news: List[dict]       # Yaklasan haber etkinlikleri
    timestamp: float                # Unix timestamp (hesaplama ani)


# ─── YARDIMCI: SEMBOL → PARA BIRIMLERI ─────────────────────────

def extract_currencies(symbol: str) -> List[str]:
    """
    Sembol adini para birimlerine ayirir.
    EURUSD  -> ['EUR', 'USD']
    XAUUSD  -> ['XAU', 'USD']
    BTCUSD  -> ['BTC', 'USD']
    USDJPY  -> ['USD', 'JPY']
    """
    known_bases = ["XAU", "XAG", "BTC", "ETH", "EUR", "GBP", "AUD", "NZD", "USD", "CAD", "CHF", "JPY"]
    sym = symbol.upper().replace("M", "").replace(".R", "").replace(".RAW", "")

    # Bilinen 3 harfli bazlari dene
    for base in known_bases:
        if sym.startswith(base):
            quote = sym[len(base):]
            if quote in known_bases or len(quote) == 3:
                return [base, quote]

    # Fallback: ilk 3 + son 3
    if len(sym) >= 6:
        return [sym[:3], sym[3:6]]
    return [sym]


# ─── KEYWORD LISTELERI (RSS sentiment icin) ─────────────────────

POSITIVE_KEYWORDS = [
    "rally", "surge", "gain", "bullish", "recovery", "upward", "strong",
    "growth", "soar", "rise", "jump", "boom", "optimism", "optimistic",
    "positive", "improve", "support", "higher", "advance", "rebound",
    "breakout", "momentum", "hawkish", "beat", "exceed", "robust",
]

NEGATIVE_KEYWORDS = [
    "crash", "plunge", "decline", "bearish", "fall", "weak", "recession",
    "crisis", "drop", "slump", "downturn", "loss", "sell-off", "selloff",
    "negative", "lower", "tumble", "collapse", "pessimism", "pessimistic",
    "concern", "fear", "risk", "dovish", "miss", "disappoint", "fragile",
]

# Para birimi keyword eslestirmesi (RSS haberlerde para birimini tespit icin)
CURRENCY_KEYWORDS = {
    "EUR": ["euro", "eurozone", "ecb", "european", "eur", "lagarde"],
    "USD": ["dollar", "usd", "fed", "federal reserve", "fomc", "powell", "us economy",
            "treasury", "nonfarm", "payroll"],
    "GBP": ["pound", "sterling", "gbp", "bank of england", "boe", "bailey"],
    "JPY": ["yen", "jpy", "bank of japan", "boj", "ueda", "japanese"],
    "AUD": ["aussie", "aud", "rba", "reserve bank of australia", "australian"],
    "XAU": ["gold", "xau", "bullion", "precious metal", "safe haven", "gold price"],
    "XAG": ["silver", "xag", "silver price"],
    "BTC": ["bitcoin", "btc", "crypto", "cryptocurrency", "digital asset"],
    "DXY": ["dollar index", "dxy", "greenback", "usd index"],
}


# ─── ANA SINIF ──────────────────────────────────────────────────

class SentimentEngine:
    """
    Coklu kaynak sentiment analiz motoru.

    Kaynaklar ve agirliklar (config.SENTIMENT_WEIGHTS):
      - fear_greed:  0.20  —  Crypto/genel piyasa Fear & Greed Index
      - news:        0.35  —  Ekonomik takvim (ForexFactory) etkisi
      - rss:         0.25  —  RSS haber akisi keyword analizi
      - dxy:         0.20  —  Dolar Endeksi (DXY) trendi

    Her sembol icin -100..+100 arasi agirlikli sentiment skoru uretir.
    """

    def __init__(self, mt5_bridge=None):
        """
        Args:
            mt5_bridge: MT5Bridge instance (opsiyonel). DXY verisi icin kullanilir.
                        Yoksa EURUSD inversinden tahmin yapilir.
        """
        self.bridge = mt5_bridge

        # Cache deposu: {anahtar: {"data": ..., "ts": float}}
        self._cache: Dict[str, dict] = {}

        # Son hesaplanan sentiment skorlari
        self._last_scores: Dict[str, SentimentScore] = {}

        log.info("SentimentEngine baslatildi | Agirliklar: %s", cfg.SENTIMENT_WEIGHTS)

    # ═══════════════════════════════════════════════════════════════
    # ANA GUNCELLEME — Tum semboller icin sentiment hesapla
    # ═══════════════════════════════════════════════════════════════

    def update(self) -> Dict[str, SentimentScore]:
        """
        Tum veri kaynaklarini cek, her sembol icin agirlikli sentiment skoru hesapla.

        Returns:
            Dict[str, SentimentScore]: sembol -> sentiment skoru
        """
        t0 = time.time()
        scores: Dict[str, SentimentScore] = {}

        # ── Veri kaynaklarini topla ─────────────────────────────
        try:
            fg_data = self._fetch_fear_greed()
        except Exception as e:
            log.warning("Fear&Greed alinamadi: %s", e)
            fg_data = {"value": 50, "label": "Neutral"}

        try:
            news_list = self._fetch_news_calendar()
        except Exception as e:
            log.warning("Haber takvimi alinamadi: %s", e)
            news_list = []

        try:
            rss_data = self._fetch_rss_news()
        except Exception as e:
            log.warning("RSS haberleri alinamadi: %s", e)
            rss_data = {}

        try:
            dxy_score = self._fetch_dxy_trend()
        except Exception as e:
            log.warning("DXY trendi alinamadi: %s", e)
            dxy_score = 0.0

        # ── Agirliklar ──────────────────────────────────────────
        w = cfg.SENTIMENT_WEIGHTS
        w_fg   = w.get("fear_greed", 0.20)
        w_news = w.get("news", 0.35)
        w_rss  = w.get("rss", 0.25)
        w_dxy  = w.get("dxy", 0.20)

        # ── Her sembol icin skorla ──────────────────────────────
        symbols = cfg.SYMBOLS if cfg.SYMBOLS else cfg.ALL_SYMBOLS

        for symbol in symbols:
            try:
                currencies = extract_currencies(symbol)

                # Kaynak bazinda skorlar
                s_fg   = self._fg_to_score(fg_data)
                s_news = self._news_impact(news_list, currencies)
                s_rss  = self._rss_sentiment(rss_data, currencies)
                s_dxy  = self._dxy_impact(dxy_score, symbol)

                # Agirlikli toplam
                raw = (s_fg * w_fg) + (s_news * w_news) + (s_rss * w_rss) + (s_dxy * w_dxy)
                value = max(-100.0, min(100.0, raw))

                # Yaklasan haberler (bu sembolun para birimleri icin)
                upcoming = self._get_upcoming_news(news_list, currencies)

                # News blackout kontrolu (15dk icinde HIGH impact)
                blackout = any(
                    0 <= n.get("minutes_until", 999) <= cfg.CLAUDE_HARD_LIMITS.get("news_blackout_minutes", 15)
                    for n in upcoming
                )

                # Volatilite beklentisi
                vol_exp = self._vol_expectation(news_list, currencies)

                scores[symbol] = SentimentScore(
                    value=round(value, 2),
                    label=self._label(value),
                    news_blackout=blackout,
                    volatility_expected=vol_exp,
                    sources={
                        "fear_greed": round(s_fg, 2),
                        "news": round(s_news, 2),
                        "rss": round(s_rss, 2),
                        "dxy": round(s_dxy, 2),
                    },
                    upcoming_news=upcoming[:5],
                    timestamp=time.time(),
                )

            except Exception as e:
                log.error("[%s] Sentiment hesaplama hatasi: %s", symbol, e, exc_info=True)
                scores[symbol] = SentimentScore(
                    value=0.0,
                    label="NEUTRAL",
                    news_blackout=False,
                    volatility_expected="NORMAL",
                    sources={"fear_greed": 0, "news": 0, "rss": 0, "dxy": 0},
                    upcoming_news=[],
                    timestamp=time.time(),
                )

        self._last_scores = scores
        elapsed = time.time() - t0
        log.info(
            "Sentiment guncellendi: %d sembol | %.1fs | %s",
            len(scores),
            elapsed,
            " | ".join(f"{s}={sc.value:+.0f}({sc.label})" for s, sc in scores.items()),
        )
        return scores

    # ═══════════════════════════════════════════════════════════════
    # VERI KAYNAKLARI
    # ═══════════════════════════════════════════════════════════════

    # ─── FEAR & GREED INDEX ─────────────────────────────────────

    def _fetch_fear_greed(self) -> dict:
        """
        Crypto Fear & Greed Index API.
        API: https://api.alternative.me/fng/
        Cache: 15 dakika

        Returns:
            {"value": 0-100, "label": str}
        """
        cache_key = "fear_greed"
        cached = self._get_cache(cache_key, max_age=900)  # 15 min
        if cached is not None:
            return cached

        try:
            resp = requests.get(
                "https://api.alternative.me/fng/",
                timeout=8,
                headers={"User-Agent": "MIA-FX-Agent/4.0"},
            )
            resp.raise_for_status()
            data = resp.json()

            fg_entry = data.get("data", [{}])[0]
            result = {
                "value": int(fg_entry.get("value", 50)),
                "label": fg_entry.get("value_classification", "Neutral"),
            }

            self._set_cache(cache_key, result)
            log.debug("Fear&Greed: %d (%s)", result["value"], result["label"])
            return result

        except Exception as e:
            log.warning("Fear&Greed API hatasi: %s — varsayilan kullaniliyor", e)
            return {"value": 50, "label": "Neutral"}

    # ─── EKONOMIK TAKVIM (ForexFactory) ─────────────────────────

    def _fetch_news_calendar(self) -> list:
        """
        Haftalik ekonomik takvim.
        API: https://nfs.faireconomy.media/ff_calendar_thisweek.json
        Cache: 15 dakika
        Sadece HIGH impact haberleri filtreler.

        Returns:
            List[dict]: Her biri {currency, event, impact, minutes_until, actual, forecast, previous}
        """
        cache_key = "news_calendar"
        cached = self._get_cache(cache_key, max_age=900)  # 15 min
        if cached is not None:
            return cached

        try:
            resp = requests.get(
                "https://nfs.faireconomy.media/ff_calendar_thisweek.json",
                timeout=10,
                headers={"User-Agent": "MIA-FX-Agent/4.0"},
            )
            resp.raise_for_status()
            raw_events = resp.json()

        except Exception as e:
            log.warning("Haber takvimi alinamadi: %s", e)
            self._set_cache(cache_key, [])
            return []

        from datetime import datetime

        now_utc = datetime.utcnow()
        items = []

        for ev in raw_events:
            try:
                # Impact filtresi — sadece HIGH
                impact_raw = ev.get("impact", "").strip()
                if impact_raw not in ("High", "high", "HIGH"):
                    continue

                # Zaman parse
                date_str = ev.get("date", "")
                if not date_str:
                    continue

                # Format: "2026-02-25T13:30:00-05:00" veya benzeri
                try:
                    ev_time = datetime.strptime(date_str[:19], "%Y-%m-%dT%H:%M:%S")
                except ValueError:
                    continue

                # Timezone offset varsa UTC'ye cevir
                if len(date_str) > 19:
                    tz_part = date_str[19:]
                    try:
                        sign = 1 if tz_part[0] == '+' else -1
                        tz_hours = int(tz_part[1:3])
                        tz_mins = int(tz_part[4:6]) if len(tz_part) > 4 else 0
                        from datetime import timedelta
                        offset = timedelta(hours=tz_hours, minutes=tz_mins)
                        ev_time = ev_time - (sign * offset)  # UTC'ye cevir
                    except (ValueError, IndexError):
                        pass

                minutes_until = int((ev_time - now_utc).total_seconds() / 60)

                items.append({
                    "currency": ev.get("country", "").upper().strip(),
                    "event": ev.get("title", "").strip(),
                    "impact": "HIGH",
                    "minutes_until": minutes_until,
                    "actual": str(ev.get("actual", "")).strip(),
                    "forecast": str(ev.get("forecast", "")).strip(),
                    "previous": str(ev.get("previous", "")).strip(),
                    "time_utc": ev_time.strftime("%Y-%m-%d %H:%M"),
                })

            except Exception:
                continue

        # Zamana gore sirala (en yakini once)
        items.sort(key=lambda x: abs(x.get("minutes_until", 9999)))

        self._set_cache(cache_key, items)
        log.debug("Haber takvimi: %d HIGH impact etkinlik", len(items))
        return items

    # ─── RSS HABER AKISI ────────────────────────────────────────

    def _fetch_rss_news(self) -> dict:
        """
        RSS feed'lerden haber cek ve keyword bazli sentiment analiz yap.
        Config: cfg.RSS_FEEDS
        Cache: 5 dakika

        Returns:
            Dict[str, dict]: para_birimi -> {"score": float, "count": int, "headlines": list}
        """
        cache_key = "rss_news"
        cached = self._get_cache(cache_key, max_age=300)  # 5 min
        if cached is not None:
            return cached

        feeds = getattr(cfg, "RSS_FEEDS", [])
        if not feeds:
            return {}

        all_articles: List[dict] = []

        for feed_url in feeds:
            try:
                resp = requests.get(
                    feed_url,
                    timeout=10,
                    headers={
                        "User-Agent": "MIA-FX-Agent/4.0",
                        "Accept": "application/rss+xml, application/xml, text/xml",
                    },
                )
                resp.raise_for_status()

                root = ET.fromstring(resp.content)

                # RSS 2.0 format: channel/item
                for item in root.iter("item"):
                    title_el = item.find("title")
                    desc_el = item.find("description")
                    title = title_el.text.strip() if title_el is not None and title_el.text else ""
                    desc = desc_el.text.strip() if desc_el is not None and desc_el.text else ""

                    if title:
                        all_articles.append({
                            "title": title,
                            "description": desc,
                            "text": f"{title} {desc}".lower(),
                            "source": feed_url,
                        })

            except ET.ParseError as e:
                log.debug("RSS XML parse hatasi (%s): %s", feed_url, e)
            except Exception as e:
                log.debug("RSS fetch hatasi (%s): %s", feed_url, e)

        # Makale basina sentiment skoru ve para birimi tespiti
        currency_sentiment: Dict[str, dict] = {}

        for article in all_articles:
            text = article["text"]

            # Keyword sentiment skoru
            pos_count = sum(1 for kw in POSITIVE_KEYWORDS if kw in text)
            neg_count = sum(1 for kw in NEGATIVE_KEYWORDS if kw in text)
            total = pos_count + neg_count
            if total == 0:
                continue

            article_score = ((pos_count - neg_count) / total) * 100  # -100 to +100

            # Hangi para birimlerine ait?
            matched_currencies = []
            for ccy, keywords in CURRENCY_KEYWORDS.items():
                if any(kw in text for kw in keywords):
                    matched_currencies.append(ccy)

            # Eslesme yoksa genel piyasa haberi — USD'ye ata
            if not matched_currencies:
                matched_currencies = ["USD"]

            # Para birimlerine dagit
            for ccy in matched_currencies:
                if ccy not in currency_sentiment:
                    currency_sentiment[ccy] = {
                        "score_sum": 0.0,
                        "count": 0,
                        "headlines": [],
                    }
                currency_sentiment[ccy]["score_sum"] += article_score
                currency_sentiment[ccy]["count"] += 1
                if len(currency_sentiment[ccy]["headlines"]) < 5:
                    currency_sentiment[ccy]["headlines"].append(article["title"][:80])

        # Ortalama skorlari hesapla
        result = {}
        for ccy, data in currency_sentiment.items():
            avg_score = data["score_sum"] / max(1, data["count"])
            result[ccy] = {
                "score": max(-100.0, min(100.0, avg_score)),
                "count": data["count"],
                "headlines": data["headlines"],
            }

        self._set_cache(cache_key, result)
        log.debug("RSS sentiment: %s", {k: f"{v['score']:+.1f}" for k, v in result.items()})
        return result

    # ─── DXY (DOLAR ENDEKSI) TRENDI ─────────────────────────────

    def _fetch_dxy_trend(self) -> float:
        """
        DXY trend skorunu hesapla.
        - Oncelik: MT5 bridge uzerinden gercek DXY verisi
        - Fallback: EURUSD inversinden tahmin

        Returns:
            float: -100 (DXY dusus / USD zayif) ... +100 (DXY yukselis / USD guclu)
        """
        cache_key = "dxy_trend"
        cached = self._get_cache(cache_key, max_age=300)  # 5 min
        if cached is not None:
            return cached

        dxy_score = 0.0

        # ── Yontem 1: MT5'ten DXY verisi ──
        if self.bridge and hasattr(self.bridge, "connected") and self.bridge.connected:
            try:
                dxy_sym = getattr(cfg, "DXY_SYMBOL", "DX.f")
                df = self.bridge.get_ohlcv(dxy_sym, "H1", 50)
                if df is not None and len(df) >= 20:
                    dxy_score = self._calc_trend_score(df)
                    log.debug("DXY (MT5 %s): skor=%.1f", dxy_sym, dxy_score)
                    self._set_cache(cache_key, dxy_score)
                    return dxy_score
            except Exception as e:
                log.debug("DXY direkt veri alinamadi: %s — EURUSD fallback", e)

        # ── Yontem 2: EURUSD inversinden tahmin ──
        if self.bridge and hasattr(self.bridge, "connected") and self.bridge.connected:
            try:
                df_eu = self.bridge.get_ohlcv("EURUSD", "H1", 50)
                if df_eu is not None and len(df_eu) >= 20:
                    eu_score = self._calc_trend_score(df_eu)
                    # EURUSD ve DXY ters korele: EU yukselis = DXY dusus
                    dxy_score = -eu_score * 0.85  # 0.85 korelasyon faktoru
                    log.debug("DXY (EURUSD inverse): skor=%.1f", dxy_score)
                    self._set_cache(cache_key, dxy_score)
                    return dxy_score
            except Exception as e:
                log.debug("EURUSD fallback basarisiz: %s", e)

        # ── Yontem 3: Varsayilan (notr) ──
        log.debug("DXY verisi alinamadi — notr (0) kullaniliyor")
        self._set_cache(cache_key, 0.0)
        return 0.0

    def _calc_trend_score(self, df) -> float:
        """
        OHLCV DataFrame'den basit trend skoru hesapla.
        EMA8 vs EMA21 konumu + momentum.

        Returns:
            float: -100 ... +100
        """
        try:
            close = df["close"]
            if len(close) < 21:
                return 0.0

            ema8 = close.ewm(span=8, adjust=False).mean()
            ema21 = close.ewm(span=21, adjust=False).mean()

            current_price = float(close.iloc[-1])
            ema8_val = float(ema8.iloc[-1])
            ema21_val = float(ema21.iloc[-1])

            # EMA8 > EMA21 = yukselis trendi, tersi dusus
            if ema21_val == 0:
                return 0.0

            # EMA farki (normalize)
            ema_diff_pct = (ema8_val - ema21_val) / ema21_val * 10000  # basis points

            # Fiyat vs EMA21 (normalize)
            price_vs_ema = (current_price - ema21_val) / ema21_val * 10000

            # Momentum: son 5 barin yonu
            if len(close) >= 6:
                recent_change = (float(close.iloc[-1]) - float(close.iloc[-6])) / float(close.iloc[-6]) * 10000
            else:
                recent_change = 0.0

            # Birlestir: agirlikli skor
            raw = (ema_diff_pct * 0.4) + (price_vs_ema * 0.3) + (recent_change * 0.3)

            # -100..+100 araligina sinirla
            # Tipik hareket: 10-50 basis point → 10-50 skor
            score = max(-100.0, min(100.0, raw))
            return score

        except Exception as e:
            log.debug("Trend skoru hesaplama hatasi: %s", e)
            return 0.0

    # ═══════════════════════════════════════════════════════════════
    # SKOR DONUSUM FONKSIYONLARI
    # ═══════════════════════════════════════════════════════════════

    def _fg_to_score(self, fg_data: dict) -> float:
        """
        Fear & Greed Index (0-100) -> Sentiment skor (-100 to +100).

        Mantik:
          0   = Extreme Fear  -> -100 (bearish risk varliklari, bullish altin)
          25  = Fear           -> -50
          50  = Neutral        ->   0
          75  = Greed          -> +50
          100 = Extreme Greed  -> +100 (bullish risk varliklari)

        Returns:
            float: -100 ... +100
        """
        fg_value = fg_data.get("value", 50)
        # Lineer donusum: 0-100 -> -100 to +100
        score = (fg_value - 50) * 2.0
        return max(-100.0, min(100.0, score))

    def _news_impact(self, news_list: list, currencies: List[str]) -> float:
        """
        Haber takvimi etkisini sentiment skoruna donustur.

        Mantik:
        - Yaklasan HIGH impact haber (15dk icinde): Notr'e cek (belirsizlik)
        - Gecmis haber (actual vs forecast):
            - actual > forecast = pozitif surpriz = +skor
            - actual < forecast = negatif surpriz = -skor
        - Haber yoksa: notr

        Args:
            news_list: _fetch_news_calendar() sonucu
            currencies: sembolun para birimleri ['EUR', 'USD']

        Returns:
            float: -100 ... +100
        """
        if not news_list or not currencies:
            return 0.0

        score_sum = 0.0
        impact_count = 0

        for news in news_list:
            news_ccy = news.get("currency", "").upper()
            if news_ccy not in currencies:
                continue

            minutes = news.get("minutes_until", 9999)
            actual_str = news.get("actual", "").strip()
            forecast_str = news.get("forecast", "").strip()

            # ── Yaklasan haber (henuz gerceklesmedi) ──
            if 0 <= minutes <= 30:
                # Belirsizlik → skor 0'a cek (risk azalt)
                # Cok yakin = guclu notr etkisi
                proximity_weight = max(0, 1.0 - (minutes / 30.0))
                score_sum += 0  # Notr'e zorlama — diger kaynaklarin etkisini azaltir
                impact_count += 1
                continue

            # ── Gecmis haber (actual mevcut) ──
            if minutes < 0 and minutes > -240 and actual_str and forecast_str:
                try:
                    # Numerik degerleri parse et (% isaretini kaldir)
                    actual_val = float(actual_str.replace("%", "").replace("K", "000")
                                       .replace("M", "000000").replace("B", "000000000")
                                       .replace(",", "").strip())
                    forecast_val = float(forecast_str.replace("%", "").replace("K", "000")
                                         .replace("M", "000000").replace("B", "000000000")
                                         .replace(",", "").strip())

                    if forecast_val == 0:
                        continue

                    # Surpriz orani
                    surprise_pct = (actual_val - forecast_val) / abs(forecast_val) * 100

                    # Zamanla azalan etki (yeni = guclu, eski = zayif)
                    recency = max(0.2, 1.0 - (abs(minutes) / 240.0))

                    # Skor: surpriz * recency * olcek
                    news_score = max(-100.0, min(100.0, surprise_pct * 10 * recency))

                    # Para birimine gore yon: USD haberi pozitif = USD guclu
                    # Eger haber para birimi first currency ise ayni yon,
                    # second currency ise ters yon
                    if news_ccy == currencies[0]:
                        score_sum += news_score
                    elif len(currencies) > 1 and news_ccy == currencies[1]:
                        score_sum -= news_score  # Karsi para birimi

                    impact_count += 1

                except (ValueError, ZeroDivisionError):
                    continue

        if impact_count == 0:
            return 0.0

        avg_score = score_sum / impact_count
        return max(-100.0, min(100.0, avg_score))

    def _rss_sentiment(self, rss_data: dict, currencies: List[str]) -> float:
        """
        RSS keyword sentiment skorunu sembol icin aggregate et.

        Args:
            rss_data: _fetch_rss_news() sonucu {ccy: {"score": float, "count": int}}
            currencies: sembolun para birimleri ['EUR', 'USD']

        Returns:
            float: -100 ... +100
        """
        if not rss_data or not currencies:
            return 0.0

        # First currency (base) icin dogrudan skor
        base_ccy = currencies[0]
        quote_ccy = currencies[1] if len(currencies) > 1 else None

        base_data = rss_data.get(base_ccy, {})
        quote_data = rss_data.get(quote_ccy, {}) if quote_ccy else {}

        base_score = base_data.get("score", 0.0)
        quote_score = quote_data.get("score", 0.0)

        # Net sentiment: base pozitif = sembol yukselis, quote pozitif = sembol dusus
        # Ornek: EURUSD → EUR bullish(+50) ve USD bearish(-30) = +80 bullish EURUSD icin
        net_score = base_score - quote_score

        # Haber sayisiyla guveni agirliklandir
        base_count = base_data.get("count", 0)
        quote_count = quote_data.get("count", 0)
        total_count = base_count + quote_count

        if total_count == 0:
            return 0.0

        # Az haber = dusuk guven, cok haber = yuksek guven
        confidence = min(1.0, total_count / 10.0)  # 10+ haber = tam guven

        result = net_score * confidence
        return max(-100.0, min(100.0, result))

    def _dxy_impact(self, dxy_score: float, symbol: str) -> float:
        """
        DXY trend skorunu sembol bazinda etkiye donustur.

        DXY yukselis (pozitif) = USD guclu:
          - USDJPY: ayni yon (USD guclu = USDJPY yukselir)
          - EURUSD, GBPUSD, AUDUSD: ters yon (USD guclu = bunlar duser)
          - XAUUSD, XAGUSD: ters yon (guvenli liman — dolar gucluyse altin duser)
          - BTCUSD: hafif ters (kripto slightly inverse)

        Args:
            dxy_score: DXY trend skoru (-100..+100)
            symbol: sembol adi

        Returns:
            float: -100 ... +100
        """
        sym = symbol.upper()
        spec = cfg.SYMBOL_SPECS.get(symbol, {})
        sym_class = spec.get("class", "major")

        # USD-quote semboller (EURUSD, GBPUSD, AUDUSD): DXY ile ters
        usd_quote_pairs = ["EURUSD", "GBPUSD", "AUDUSD", "NZDUSD"]
        # USD-base semboller (USDJPY, USDCHF): DXY ile ayni
        usd_base_pairs = ["USDJPY", "USDCHF", "USDCAD"]

        if sym in usd_base_pairs:
            # USD guclenirse USDJPY yukselir → ayni yon
            return dxy_score * 0.80

        elif sym in usd_quote_pairs:
            # USD guclenirse EURUSD duser → ters yon
            return -dxy_score * 0.80

        elif sym_class == "metal":
            # Altin/gumus: guvenli liman — dolar guclu ise metal duser
            return -dxy_score * 0.70

        elif sym_class == "crypto":
            # Kripto: hafif ters korelasyon
            return -dxy_score * 0.40

        else:
            # Bilinmeyen sembol — hafif etki
            return -dxy_score * 0.30

    # ═══════════════════════════════════════════════════════════════
    # ETIKETLEME VE YARDIMCI FONKSIYONLAR
    # ═══════════════════════════════════════════════════════════════

    def _label(self, score: float) -> str:
        """
        Sentiment skorunu insan okunabilir etikete donustur.

        -100...-60  → EXTREME_FEAR
        -60...-20   → FEAR
        -20...+20   → NEUTRAL
        +20...+60   → GREED
        +60...+100  → EXTREME_GREED
        """
        if score <= -60:
            return "EXTREME_FEAR"
        elif score <= -20:
            return "FEAR"
        elif score <= 20:
            return "NEUTRAL"
        elif score <= 60:
            return "GREED"
        else:
            return "EXTREME_GREED"

    def _vol_expectation(self, news_list: list, currencies: List[str]) -> str:
        """
        Yaklasan haberlere gore volatilite beklentisi.

        - HIGH impact haber 4 saat icinde → HIGH
        - HIGH impact haber 4+ saat icinde veya yok → NORMAL
        - Haftasonu / sessiz donem → LOW

        Returns:
            "HIGH" / "NORMAL" / "LOW"
        """
        if not news_list:
            return "NORMAL"

        for news in news_list:
            news_ccy = news.get("currency", "").upper()
            if news_ccy not in currencies:
                continue

            minutes = news.get("minutes_until", 9999)

            # 4 saat (240 dk) icinde HIGH impact haber
            if 0 <= minutes <= 240:
                return "HIGH"

        # Haftasonu kontrolu
        from datetime import datetime
        dow = datetime.utcnow().weekday()
        if dow >= 5:  # Cumartesi veya Pazar
            return "LOW"

        return "NORMAL"

    def _get_upcoming_news(self, news_list: list, currencies: List[str]) -> List[dict]:
        """
        Belirli para birimleri icin yaklasan haberleri filtrele.

        Returns:
            Pozitif minutes_until olan haberler, zamana gore sirali
        """
        upcoming = []
        for news in news_list:
            news_ccy = news.get("currency", "").upper()
            minutes = news.get("minutes_until", -1)
            if news_ccy in currencies and minutes >= 0:
                upcoming.append(news)

        upcoming.sort(key=lambda x: x.get("minutes_until", 9999))
        return upcoming

    # ═══════════════════════════════════════════════════════════════
    # CACHE YONETIMI
    # ═══════════════════════════════════════════════════════════════

    def _get_cache(self, key: str, max_age: float) -> Optional[any]:
        """
        Cache'ten veri al (max_age saniye icinde gecerliyse).

        Returns:
            Cached data veya None
        """
        entry = self._cache.get(key)
        if entry is None:
            return None

        age = time.time() - entry.get("ts", 0)
        if age > max_age:
            return None

        return entry.get("data")

    def _set_cache(self, key: str, data) -> None:
        """Cache'e veri yaz."""
        self._cache[key] = {
            "data": data,
            "ts": time.time(),
        }

    def clear_cache(self) -> None:
        """Tum cache'i temizle (test / yeniden baslama icin)."""
        self._cache.clear()
        log.info("Sentiment cache temizlendi")

    # ═══════════════════════════════════════════════════════════════
    # ERISIM YARDIMCILARI
    # ═══════════════════════════════════════════════════════════════

    def get_score(self, symbol: str) -> Optional[SentimentScore]:
        """
        Son hesaplanan sentiment skorunu getir (update() cagirilmis olmali).
        """
        return self._last_scores.get(symbol)

    def get_all_scores(self) -> Dict[str, SentimentScore]:
        """Tum semboller icin son skorlar."""
        return dict(self._last_scores)

    def is_news_blackout(self, symbol: str) -> bool:
        """Belirtilen sembol icin haber karartmasi var mi?"""
        score = self._last_scores.get(symbol)
        if score is None:
            return False
        return score.news_blackout

    def format_summary(self) -> str:
        """Dashboard / log icin okunabilir sentiment ozeti."""
        if not self._last_scores:
            return "Sentiment: Henuz hesaplanmadi"

        lines = ["=== SENTIMENT OZETI ==="]
        for sym, sc in self._last_scores.items():
            blackout = " [BLACKOUT]" if sc.news_blackout else ""
            vol = f" vol={sc.volatility_expected}" if sc.volatility_expected != "NORMAL" else ""
            lines.append(
                f"  {sym}: {sc.value:+6.1f} ({sc.label}){blackout}{vol}"
                f"  | FG={sc.sources['fear_greed']:+.0f}"
                f" NEWS={sc.sources['news']:+.0f}"
                f" RSS={sc.sources['rss']:+.0f}"
                f" DXY={sc.sources['dxy']:+.0f}"
            )

        return "\n".join(lines)

    def to_dict(self) -> Dict[str, dict]:
        """Tum skorlari dict formatinda dondur (JSON serialization icin)."""
        return {
            sym: asdict(score) for sym, score in self._last_scores.items()
        }
