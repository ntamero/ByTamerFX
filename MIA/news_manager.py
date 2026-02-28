"""
MIA v5.0 — News Manager (Ekonomik Takvim)
BytamerFX EA NewsManager.mqh'den port edildi (v3.8.0)

4 etki seviyesi: CRITICAL (NFP, FOMC), HIGH (CPI, GDP), MEDIUM (PMI), LOW
Sembol bazlı currency eşleme, trade block (20dk önce, 5dk sonra),
grid aralığı genişletme (haber yakınında +%50).

Veri kaynağı: ForexFactory RSS / investing.com RSS (sentiment_engine.py ile paylaşır)

Copyright 2026, By T@MER — https://www.bytamer.com
"""

import time
import logging
from dataclasses import dataclass, field
from typing import List, Dict, Set, Optional
from datetime import datetime, timezone

import config as cfg

log = logging.getLogger("News")


# =====================================================================
# VERİ YAPILARI
# =====================================================================

@dataclass
class NewsEvent:
    """Ekonomik takvim haberi."""
    event_time: float           # Unix timestamp
    currency: str               # USD, EUR, GBP, vb.
    title: str                  # Haber başlığı
    impact: str                 # "CRITICAL" / "HIGH" / "MEDIUM" / "LOW"
    actual: str = ""            # Gerçekleşen
    forecast: str = ""          # Beklenen
    previous: str = ""          # Önceki

    @property
    def minutes_until(self) -> float:
        return (self.event_time - time.time()) / 60

    @property
    def is_active(self) -> bool:
        """Haber aktif mi? (block window içinde)"""
        mins = self.minutes_until
        return -cfg.NEWS_BLOCK_AFTER_MIN <= mins <= cfg.NEWS_BLOCK_BEFORE_MIN

    @property
    def is_upcoming(self) -> bool:
        """Yaklaşan haber (alert window)"""
        return 0 < self.minutes_until <= cfg.NEWS_ALERT_BEFORE_MIN


# =====================================================================
# KEYWORD TANIMLARı — EA'dan birebir port
# =====================================================================

_CRITICAL_KEYWORDS = [
    "Non-Farm", "NFP", "Nonfarm",
    "FOMC", "Fed Rate", "Federal Funds Rate",
    "ECB Rate", "ECB Interest", "ECB Main",
    "BOE Rate", "BOE Interest", "Bank Rate",
    "BOJ Rate", "BOJ Interest",
    "RBA Rate", "RBA Cash",
    "RBNZ Rate", "RBNZ Cash",
    "BOC Rate", "BOC Overnight",
    "SNB Rate", "SNB Policy",
]

_HIGH_KEYWORDS = [
    "CPI", "Consumer Price", "Inflation",
    "GDP", "Gross Domestic",
    "Employment", "Unemployment", "Jobless",
    "Retail Sales",
    "PMI", "Purchasing Managers",
    "Trade Balance",
    "ISM Manufacturing", "ISM Services",
    "Core PCE", "PCE Price",
    "ADP Employment", "ADP Nonfarm",
    "Initial Jobless", "Continuing Claims",
    "PPI", "Producer Price",
    "Housing Starts", "Building Permits",
    "Existing Home", "New Home",
]

_MEDIUM_KEYWORDS = [
    "Industrial Production",
    "Manufacturing",
    "Services",
    "Construction",
    "Consumer Confidence",
    "Business Confidence",
    "Current Account",
    "Import", "Export",
    "Capacity Utilization",
    "Durable Goods",
    "Factory Orders",
]

# Sembol → ilgili currency eşlemesi
_SYMBOL_CURRENCIES: Dict[str, List[str]] = {
    "EURUSD": ["EUR", "USD"],
    "GBPUSD": ["GBP", "USD"],
    "USDJPY": ["USD", "JPY"],
    "AUDUSD": ["AUD", "USD"],
    "XAUUSD": ["XAU", "USD"],
    "XAGUSD": ["XAG", "USD"],
    "BTCUSD": ["BTC", "USD"],
    # Genişletilebilir
    "GBPJPY": ["GBP", "JPY"],
    "EURJPY": ["EUR", "JPY"],
}

# Metal/Crypto → USD haberi yeterli
_USD_AFFECTED = {"XAU", "XAG", "BTC", "ETH", "LTC"}


# =====================================================================
# NEWS MANAGER
# =====================================================================

class NewsManager:
    """
    Ekonomik takvim yöneticisi.

    Kullanım:
        nm = NewsManager()
        nm.update_events(events_list)  # Periyodik güncelleme
        if nm.is_blocked("XAUUSD"):
            # Trade açma
        factor = nm.get_grid_widen("XAUUSD")  # 1.0 veya 1.5
    """

    def __init__(self):
        self._events: List[NewsEvent] = []
        self._last_update: float = 0.0
        self._blocked_symbols: Set[str] = set()
        self._alert_sent: Set[str] = set()  # Aynı haberi tekrar uyarma

    # ── Haber listesini güncelle (dışarıdan çağrılır) ──
    def update_events(self, events: List[NewsEvent]):
        """Haber listesini güncelle. sentiment_engine.py'den gelir."""
        self._events = events
        self._last_update = time.time()
        self._refresh_blocks()

    def update_from_raw(self, raw_events: List[dict]):
        """Ham dict listesinden NewsEvent oluştur ve güncelle."""
        events = []
        for e in raw_events:
            title = e.get("title", "")
            impact = self._classify_impact(title)
            events.append(NewsEvent(
                event_time=e.get("time", 0),
                currency=e.get("currency", "USD"),
                title=title,
                impact=impact,
                actual=e.get("actual", ""),
                forecast=e.get("forecast", ""),
                previous=e.get("previous", ""),
            ))
        self.update_events(events)

    # ═════════════════════════════════════════════════════════
    # SORGULAR
    # ═════════════════════════════════════════════════════════

    def is_blocked(self, symbol: str) -> bool:
        """Sembol trade bloğunda mı?"""
        if not cfg.NEWS_ENABLED:
            return False
        return symbol.upper() in self._blocked_symbols

    def get_grid_widen(self, symbol: str) -> float:
        """Grid aralığı genişletme faktörü (1.0 normal, 1.5 haber yakın)."""
        if not cfg.NEWS_ENABLED:
            return 1.0

        sym = symbol.upper()
        currencies = self._get_currencies(sym)

        for event in self._events:
            if event.currency not in currencies:
                continue
            if event.impact not in ("CRITICAL", "HIGH"):
                continue
            mins = event.minutes_until
            # Haber öncesi 30dk → grid genişlet
            if 0 < mins <= 30:
                return 1.0 + (cfg.GRID_NEWS_WIDEN_PCT / 100.0)

        return 1.0

    def get_upcoming(self, symbol: str, minutes: int = 60) -> List[NewsEvent]:
        """Belirtilen süre içindeki yaklaşan haberler."""
        sym = symbol.upper()
        currencies = self._get_currencies(sym)
        result = []
        for event in self._events:
            if event.currency not in currencies:
                continue
            if 0 < event.minutes_until <= minutes:
                result.append(event)
        return sorted(result, key=lambda e: e.event_time)

    def get_active_blocks(self) -> Dict[str, str]:
        """Aktif bloklar: {sembol: haber başlığı}"""
        blocks = {}
        for sym in self._blocked_symbols:
            currencies = self._get_currencies(sym)
            for event in self._events:
                if event.currency in currencies and event.is_active:
                    blocks[sym] = f"{event.title} ({event.impact})"
                    break
        return blocks

    def get_all_upcoming(self, minutes: int = 60) -> List[NewsEvent]:
        """Tüm yaklaşan haberler (sembol fark etmez)."""
        return [
            e for e in self._events
            if 0 < e.minutes_until <= minutes
            and e.impact in ("CRITICAL", "HIGH", "MEDIUM")
        ]

    def check_alerts(self) -> List[str]:
        """
        Yeni uyarı mesajları döndür (Telegram/Discord için).
        Aynı haber için tekrar uyarı göndermez.
        """
        alerts = []
        for event in self._events:
            if event.impact not in ("CRITICAL", "HIGH"):
                continue
            alert_key = f"{event.title}_{event.event_time}"
            if alert_key in self._alert_sent:
                continue
            mins = event.minutes_until
            if 0 < mins <= cfg.NEWS_ALERT_BEFORE_MIN:
                emoji = "🔴" if event.impact == "CRITICAL" else "🟠"
                alerts.append(
                    f"{emoji} {event.currency} {event.title} — "
                    f"{mins:.0f}dk sonra"
                )
                self._alert_sent.add(alert_key)
        return alerts

    # ═════════════════════════════════════════════════════════
    # INTERNAL
    # ═════════════════════════════════════════════════════════

    def _refresh_blocks(self):
        """Bloke sembol listesini güncelle."""
        self._blocked_symbols.clear()

        for event in self._events:
            if event.impact not in ("CRITICAL", "HIGH"):
                continue
            if not event.is_active:
                continue

            # Bu haberin etkilediği sembolleri bul
            for sym, currencies in _SYMBOL_CURRENCIES.items():
                if event.currency in currencies:
                    self._blocked_symbols.add(sym)

            # USD haberi tüm metal/crypto'yu etkiler
            if event.currency == "USD":
                for sym in cfg.ALL_SYMBOLS:
                    self._blocked_symbols.add(sym)

    def _classify_impact(self, title: str) -> str:
        """Haber başlığından etki seviyesi belirle. EA keyword listesi."""
        t = title.upper()

        for kw in _CRITICAL_KEYWORDS:
            if kw.upper() in t:
                return "CRITICAL"

        for kw in _HIGH_KEYWORDS:
            if kw.upper() in t:
                return "HIGH"

        for kw in _MEDIUM_KEYWORDS:
            if kw.upper() in t:
                return "MEDIUM"

        return "LOW"

    @staticmethod
    def _get_currencies(symbol: str) -> List[str]:
        """Sembol için ilgili currency'leri döndür."""
        sym = symbol.upper().replace("M", "")
        if sym in _SYMBOL_CURRENCIES:
            return _SYMBOL_CURRENCIES[sym]

        # Fallback: sembolden parse et
        currencies = ["USD"]  # USD her zaman
        if len(sym) >= 6:
            base = sym[:3]
            quote = sym[3:6]
            currencies = [base, quote]
        return currencies

    # ═════════════════════════════════════════════════════════
    # DURUM
    # ═════════════════════════════════════════════════════════

    def to_dict(self) -> dict:
        """Dashboard için dict."""
        return {
            "enabled": cfg.NEWS_ENABLED,
            "blocked_symbols": list(self._blocked_symbols),
            "upcoming_count": len(self.get_all_upcoming(60)),
            "events": [
                {
                    "time": e.event_time,
                    "currency": e.currency,
                    "title": e.title,
                    "impact": e.impact,
                    "minutes_until": round(e.minutes_until, 1),
                }
                for e in self._events
                if -10 < e.minutes_until < 120
                and e.impact in ("CRITICAL", "HIGH", "MEDIUM")
            ][:20],
            "last_update": self._last_update,
        }
