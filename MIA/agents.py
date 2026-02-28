"""
MIA v5.2.0 — Multi-Agent Coordination System
Coklu-Ajan Karar Koordinasyon Sistemi

Ajanlar:
  1. SpeedAgent   — Yerel, API yok, ~1ms, her tick calisir
  2. RiskAgent    — Yerel, API yok, ~1ms, her tick calisir
  3. GridAgent    — Yerel, API yok, ~1ms, EA grid/FIFO/cascade sistemi
  4. SentimentAgent — Yerel + API, ~2s, placeholder (sentiment_engine.py doldurur)
  5. Arbitrator   — Karar birlestirme ve onceliklendirme
  6. EquityCurveProtector — EMA-bazli equity koruma

Copyright 2026, By T@MER — https://www.bytamer.com
"""

import time
import logging
from dataclasses import dataclass, field
from typing import List, Dict, Optional, Tuple, Any
from enum import Enum

import config as cfg
from patterns import MarketRegime
from grid_manager import GridManager, GridPosition, FIFOSummary
from symbol_profiles import SymbolProfile, get_symbol_profile
from lot_calculator import LotCalculator

log = logging.getLogger("Agents")


# =====================================================================
# AGENT DECISION — Tum ajanlarin ortak karar yapisi
# =====================================================================

@dataclass
class AgentDecision:
    """
    Tum ajanlar tarafindan kullanilan standart karar yapisi.

    Her ajan kendi analizini yapar ve sonucu AgentDecision olarak dondurur.
    Arbitrator bu kararlari oncelik sirasina gore birlestirir.

    Alanlar:
        agent_name  : Karar veren ajan adi (SpeedAgent, RiskAgent, GridAgent, vb.)
        action      : Eylem tipi:
                       Temel: OPEN_BUY, OPEN_SELL, CLOSE, HOLD, PARTIAL_CLOSE,
                              FAST_ENTRY, EMERGENCY_CLOSE, RISK_VETO, PEAK_DROP,
                              MASTER_OVERRIDE, STRATEGY_CLOSE, STRATEGY_OPEN,
                              REVERSE_BUY, REVERSE_SELL,
                              SENTIMENT_WARN, LOT_REDUCE, PAUSE_TRADING, STOP_TRADING
                       Grid:  GRID_CLOSE, GRID_PARTIAL_CLOSE, GRID_FIFO_CLOSE,
                              GRID_NET_SETTLE, GRID_OPEN_SPM, GRID_OPEN_DCA,
                              GRID_OPEN_HEDGE, GRID_PROMOTE, GRID_DEADLOCK_WARN
        symbol      : Islem sembolu (EURUSD, XAUUSD, vb.)
        priority    : Karar onceligi (0-100, yuksek = daha oncelikli)
        confidence  : Guven yuzdesi (0-100)
        lot         : Onerilen lot miktari (0 = kapatma/belirsiz)
        reason      : Karar gerekçesi (Turkce)
        urgency     : Aciliyet seviyesi (NOW, WAIT_CANDLE, SKIP)
        metadata    : Ek veriler (dict)
        timestamp   : Karar zamani (Unix timestamp)
    """
    agent_name: str
    action:     str
    symbol:     str
    priority:   int       = 50
    confidence: float     = 0.0
    lot:        float     = 0.0
    reason:     str       = ""
    urgency:    str       = "NOW"
    metadata:   dict      = field(default_factory=dict)
    timestamp:  float     = field(default_factory=time.time)

    def __repr__(self) -> str:
        return (
            f"AgentDecision({self.agent_name}:{self.action} {self.symbol} "
            f"pri={self.priority} conf={self.confidence:.0f}% lot={self.lot} "
            f"urgency={self.urgency})"
        )


# =====================================================================
# EQUITY CURVE PROTECTOR — EMA-bazli equity koruma
# =====================================================================

class EquityCurveProtector:
    """
    Equity egrisi koruma mekanizmasi.

    Hesap equity'sinin EMA'ya gore konumunu izler.
    Equity, EMA'nin belirli bir yuzde altina dustugunde PAUSE veya EMERGENCY
    sinyal uretir.

    Kullanim:
        protector = EquityCurveProtector()
        durum = protector.check(equity_history)
        # durum: "NORMAL", "PAUSE" veya "EMERGENCY"

    Konfigruasyon (config.py):
        EQUITY_CURVE_EMA_PERIOD  : EMA periyodu (default 20)
        EQUITY_CURVE_PAUSE_PCT   : PAUSE esigi (default %3)
        EQUITY_CURVE_EMERGENCY   : EMERGENCY esigi (default %5)
    """

    def check(self, equity_history: List[float]) -> str:
        """
        Equity gecmisini analiz ederek mevcut durumu dondurur.

        Args:
            equity_history: Equity degerlerinin kronolojik listesi.
                           En az EQUITY_CURVE_EMA_PERIOD kadar eleman olmali.

        Returns:
            "NORMAL"    : Equity EMA ustunde veya yakin, normal islem
            "PAUSE"     : Equity EMA'nin %PAUSE_PCT altinda, yeni acilis durdur
            "EMERGENCY" : Equity EMA'nin %EMERGENCY altinda, tum pozisyonlari kapat
        """
        period = cfg.EQUITY_CURVE_EMA_PERIOD  # 20

        if not equity_history or len(equity_history) < period:
            # Yeterli veri yok, guvenli tarafta kal
            return "NORMAL"

        # EMA hesapla
        ema = self._calc_ema(equity_history, period)
        current_equity = equity_history[-1]

        if ema <= 0:
            return "NORMAL"

        # EMA'dan sapma yuzdesi
        deviation_pct = (ema - current_equity) / ema * 100.0

        if deviation_pct >= cfg.EQUITY_CURVE_EMERGENCY:
            log.warning(
                f"[EquityCurve] EMERGENCY! Equity={current_equity:.2f} "
                f"EMA={ema:.2f} sapma={deviation_pct:.1f}%"
            )
            return "EMERGENCY"

        if deviation_pct >= cfg.EQUITY_CURVE_PAUSE_PCT:
            log.info(
                f"[EquityCurve] PAUSE — Equity={current_equity:.2f} "
                f"EMA={ema:.2f} sapma={deviation_pct:.1f}%"
            )
            return "PAUSE"

        return "NORMAL"

    @staticmethod
    def _calc_ema(values: List[float], period: int) -> float:
        """
        Basit EMA hesaplama.

        Args:
            values: Deger listesi (kronolojik)
            period: EMA periyodu

        Returns:
            Son EMA degeri
        """
        if not values or period <= 0:
            return 0.0

        multiplier = 2.0 / (period + 1)
        ema = values[0]

        for val in values[1:]:
            ema = (val - ema) * multiplier + ema

        return ema


# =====================================================================
# SPEED AGENT — Yerel, API yok, ~1ms
# =====================================================================

class SpeedAgent:
    """
    Hiz Ajani — Her tick'te calisan yerel koruma ve hizli giris ajani.

    Gorevleri:
      1. Peak drop koruma (ATR-adaptif esikler)
      2. Mum donus kar alma (profit > $0.50 ve ters mum)
      3. Acil drawdown kapatma (>= %35)
      4. Margin acil durum
      5. Hizli giris taramasi (yuksek skorlu sinyallerde Brain beklemeden giris)

    Bu ajan API cagirmaz, tamamen yerel hesaplamalar yapar.
    Hedef gecikme: < 1ms
    """

    def __init__(self):
        self._equity_protector = EquityCurveProtector()

    def tick_protect(
        self,
        symbol: str,
        positions: list,
        m15_data: "pd.DataFrame",
        signal_result: "SignalResult",
        atr: float,
        grid_active: bool = False,
    ) -> List[AgentDecision]:
        """
        Her tick'te pozisyon koruma kontrolu.

        Kontrol sirasi (oncelik yuksekten dusuge):
          1. Acil drawdown kapatma (DD >= %35)
          2. Margin acil durum (margin_level < %150)
          3. Peak drop koruma (ATR-adaptif esikler) — grid_active=True ise atlanir
          4. Mum donus kar alma — grid_active=True ise atlanir

        Args:
            symbol        : Islem sembolu
            positions     : OpenPosition listesi (executor.py'den)
            m15_data      : M15 OHLCV DataFrame
            signal_result : SignalEngine ciktisi (candle_dir, atr_percentile, vb.)
            atr           : Guncel ATR degeri
            grid_active   : Grid aktifse True — peak drop/mum donus GridManager'a delege

        Returns:
            AgentDecision listesi (bos olabilir)
        """
        decisions: List[AgentDecision] = []

        if not positions:
            return decisions

        now = time.time()
        atr_percentile = getattr(signal_result, "atr_percentile", 50.0)

        for pos in positions:
            profit = getattr(pos, "profit", 0.0)
            peak_profit = getattr(pos, "peak_profit", 0.0)
            role = getattr(pos, "role", "MAIN")
            direction = getattr(pos, "direction", "")
            ticket = getattr(pos, "ticket", 0)

            # ── 0. MUTLAK STOP-LOSS — DEVRE DISI ───────────
            # SPM sistemi pozisyon yonetimini yapar.
            # Zorla kapatma YOK — sadece SPM toplami - ANA zarar >= +$5 ise grup kapanir.
            # (Eski kod kaldirildi: MAX_LOSS_PER_POSITION kontrolu)

            # ── 1. ACIL DRAWDOWN KAPATMA (%35+) ─────────────
            # Bu kontrol her pozisyon icin degil, hesap bazli yapilir
            # (RiskAgent'ta daha detayli, burada sadece pozisyon bazli acil)

            # ── 2. PEAK DROP KORUMA — DEVRE DISI ────────────
            # SPM sistemi pozisyon yonetimini yapar. Peak drop kapatma YOK.
            # Grid/FIFO kendi kurallarıyla calisir.
            if True:  # Her zaman atla — zorla kapatma YOK
                continue

            if peak_profit >= cfg.PEAK_PROFIT_MIN:
                # Role'e gore baz esik belirle
                if role == "MAIN":
                    base_threshold = cfg.PEAK_DROP_MAIN_BASE  # 25
                else:
                    base_threshold = cfg.PEAK_DROP_SPM_BASE   # 35

                # ATR-adaptif esik ayarlamasi
                # ATR percentile > 50 ise esik artir (daha genis tolerans)
                # ATR percentile < 50 ise esik azalt (daha siki koruma)
                atr_adjustment = (atr_percentile - 50.0) * cfg.PEAK_DROP_ATR_FACTOR
                threshold = base_threshold + atr_adjustment

                # Esikleri makul aralikta tut
                threshold = max(10.0, min(60.0, threshold))

                # Gercek dusus yuzdesi hesapla
                drop_pct = (
                    (peak_profit - profit) / peak_profit * 100.0
                    if peak_profit > 0 else 0.0
                )

                if drop_pct >= threshold:
                    decisions.append(AgentDecision(
                        agent_name="SpeedAgent",
                        action="PEAK_DROP",
                        symbol=symbol,
                        priority=90,
                        confidence=95.0,
                        lot=getattr(pos, "lot", 0.0),
                        reason=(
                            f"{role} #{ticket} peak drop {drop_pct:.1f}% >= "
                            f"esik {threshold:.1f}% (baz={base_threshold}, "
                            f"ATR_adj={atr_adjustment:+.1f})"
                        ),
                        urgency="NOW",
                        metadata={
                            "ticket": ticket,
                            "role": role,
                            "peak_profit": peak_profit,
                            "current_profit": profit,
                            "drop_pct": drop_pct,
                            "threshold": threshold,
                            "atr_percentile": atr_percentile,
                        },
                        timestamp=now,
                    ))
                    continue  # Bu pozisyon icin baska kontrol yapma

            # ── 3. MUM DONUS KAR ALMA ────────────────────────
            candle_dir_val = getattr(signal_result, "candle_dir", None)
            if candle_dir_val is not None and profit > 0.50:
                # candle_dir: Dir enum (BUY=1, SELL=2, NONE=0)
                candle_dir_name = getattr(candle_dir_val, "name", str(candle_dir_val))

                candle_against = (
                    (direction == "BUY" and candle_dir_name == "SELL") or
                    (direction == "SELL" and candle_dir_name == "BUY")
                )

                if candle_against:
                    decisions.append(AgentDecision(
                        agent_name="SpeedAgent",
                        action="CLOSE",
                        symbol=symbol,
                        priority=70,
                        confidence=80.0,
                        lot=getattr(pos, "lot", 0.0),
                        reason=(
                            f"{role} #{ticket} mum donus kapatma: "
                            f"profit=${profit:.2f}, ters mum={candle_dir_name}"
                        ),
                        urgency="NOW",
                        metadata={
                            "ticket": ticket,
                            "role": role,
                            "profit": profit,
                            "candle_dir": candle_dir_name,
                            "close_type": "candle_reversal",
                        },
                        timestamp=now,
                    ))

        return decisions

    def fast_entry_scan(
        self,
        symbol: str,
        signal_result: "SignalResult",
        decision_cache: Optional[Any] = None,
    ) -> Optional[AgentDecision]:
        """
        MİLİSANİYE HIZLI GİRİŞ — API çağrısı YOK, hedef < 5ms.

        MOD A — Önbellekli (Brain kararı taze, <2dk):
          Eşik: score>=65, ADX>=20. Brain zaten onaylamış, güvenilir.

        MOD B — Yerel kural (Önbellek yok veya bayat):
          Eşik: score>=75, ADX>=25, 3TF uyumu zorunlu. Sıkı filtre.

        Her iki modda EMA yön filtresi ZORUNLU — dipten SELL, tepeden BUY engeli.
        """
        now     = time.time()
        score   = getattr(signal_result, "score",   0)
        adx     = getattr(signal_result, "adx",     0.0)
        ema8    = getattr(signal_result, "ema8",    0.0)
        ema21   = getattr(signal_result, "ema21",   0.0)
        ema50   = getattr(signal_result, "ema50",   0.0)
        h1_bull = getattr(signal_result, "h1_bull", None)
        h4_bull = getattr(signal_result, "h4_bull", None)

        direction = getattr(signal_result, "direction", None)
        dir_value = getattr(direction, "value", 0) if direction else 0
        if dir_value == 0:
            return None

        is_buy   = (dir_value == 1)
        dir_name = "BUY" if is_buy else "SELL"

        # ══ EMA YÖN GUARD — Her zaman, önbellekten bağımsız ══
        bull_aligned = (ema8 > 0 and ema21 > 0 and ema50 > 0 and ema8 > ema21 > ema50)
        bear_aligned = (ema8 > 0 and ema21 > 0 and ema50 > 0 and ema8 < ema21 < ema50)

        if is_buy and bear_aligned:
            log.debug(f"[{symbol}] FAST_ENTRY REDDEDİLDİ: EMA AŞAĞI trendde BUY yasak")
            return None
        if not is_buy and bull_aligned:
            log.debug(f"[{symbol}] FAST_ENTRY REDDEDİLDİ: EMA YUKARI trendde SELL yasak")
            return None

        # ══ MOD A: ÖNBELLEKLİ ══
        if decision_cache and decision_cache.is_fresh:
            # Önbellek yönü ile sinyal yönü uyuşuyor mu?
            if decision_cache.direction not in (dir_name, "HOLD"):
                log.debug(
                    f"[{symbol}] FAST_ENTRY önbellek yön uyuşmazlığı: "
                    f"cache={decision_cache.direction} sinyal={dir_name} "
                    f"(yaş={decision_cache.age:.0f}s)"
                )
                return None

            min_score = getattr(cfg, "FAST_ENTRY_CACHED_SCORE", 65)
            min_adx   = getattr(cfg, "FAST_ENTRY_CACHED_ADX",   20)

            if score < min_score or adx < min_adx:
                return None

            lot = decision_cache.lot if decision_cache.lot > 0 else 0.0
            return AgentDecision(
                agent_name = "SpeedAgent",
                action     = "FAST_ENTRY",
                symbol     = symbol,
                priority   = 45,
                confidence = float(min(score, decision_cache.confidence)),
                lot        = lot,
                reason     = (
                    f"HIZLI GİRİŞ [önbellekli]: {dir_name} "
                    f"skor={score} ADX={adx:.1f} yaş={decision_cache.age:.0f}s"
                ),
                urgency  = "NOW",
                metadata = {
                    "direction":   dir_name,
                    "score":       score,
                    "adx":         adx,
                    "source":      "cache",
                    "cache_age":   decision_cache.age,
                    "ema_aligned": "BULL" if bull_aligned else ("BEAR" if bear_aligned else "MIXED"),
                    "h1_bull":     h1_bull,
                    "regime":      getattr(getattr(signal_result, "regime", None), "value", "UNKNOWN"),
                    "atr":         getattr(signal_result, "atr", 0.0),
                    "rsi":         getattr(signal_result, "rsi", 50.0),
                },
                timestamp = now,
            )

        # ══ MOD B: YEREL KURAL (önbellek yok/bayat) ══
        min_score = cfg.FAST_ENTRY_THRESHOLD              # 75
        min_adx   = getattr(cfg, "FAST_ENTRY_ADX_MIN", 25)

        if score < min_score or adx < min_adx:
            return None

        # Trend hizalama (H1 zorunlu, H4 varsa kontrol et)
        is_buy_check = is_buy
        if h1_bull is not None:
            if is_buy_check and h1_bull is False:
                return None
            if not is_buy_check and h1_bull is True:
                return None

        tf_align = 0
        if h1_bull is not None:
            tf_align += 1 if (is_buy == h1_bull) else 0
        if h4_bull is not None:
            tf_align += 1 if (is_buy == h4_bull) else 0
        if tf_align < 1:
            log.debug(f"[{symbol}] FAST_ENTRY [yerel]: TF uyumu yetersiz")
            return None

        return AgentDecision(
            agent_name = "SpeedAgent",
            action     = "FAST_ENTRY",
            symbol     = symbol,
            priority   = 35,
            confidence = float(score),
            lot        = 0.0,  # RiskAgent hesaplayacak
            reason     = (
                f"HIZLI GİRİŞ [yerel kural]: {dir_name} "
                f"skor={score} ADX={adx:.1f} H1_bull={h1_bull}"
            ),
            urgency  = "NOW",
            metadata = {
                "direction":   dir_name,
                "score":       score,
                "adx":         adx,
                "source":      "local_rules",
                "tf_align":    tf_align,
                "ema_aligned": "BULL" if bull_aligned else ("BEAR" if bear_aligned else "MIXED"),
                "h1_bull":     h1_bull,
                "regime":      getattr(getattr(signal_result, "regime", None), "value", "UNKNOWN"),
                "atr":         getattr(signal_result, "atr", 0.0),
                "rsi":         getattr(signal_result, "rsi", 50.0),
            },
            timestamp = now,
        )


# =====================================================================
# RISK AGENT — Yerel, API yok, ~1ms
# =====================================================================

class RiskAgent:
    """
    Risk Yonetim Ajani — Her tick'te calisan kapsamli risk kontrolu.

    Gorevleri:
      1. Gunluk kayip limiti kontrolu (%15)
      2. Toplam drawdown kontrolu (%35 acil)
      3. Korelasyon maruz kalma kontrolu (max %60)
      4. Toplam lot limiti (1.50)
      5. Margin seviyesi kontrolu
      6. Equity egrisi koruma (EMA-bazli pause/emergency)
      7. Ardisik kayip tespiti (3 = lot %50 azalt, 5 = DURDUR)
      8. Seans bazli limitler (OFF_HOURS = max 2 pozisyon)

    Bu ajan API cagirmaz, tamamen yerel hesaplamalar yapar.
    Hedef gecikme: < 1ms
    """

    def __init__(self):
        self._equity_protector = EquityCurveProtector()

    def check_all(
        self,
        account: dict,
        positions: Dict[str, list],
        session: str,
        equity_history: List[float],
        trade_history: List[dict],
    ) -> List[AgentDecision]:
        """
        Tum risk kontrollerini tek seferde calistir.

        Args:
            account        : Hesap bilgileri dict
                             {"balance": float, "equity": float,
                              "margin": float, "margin_level": float,
                              "daily_pnl": float}
            positions      : Sembol bazli pozisyon dict
                             {"EURUSD": [OpenPosition, ...], ...}
            session        : Aktif seans adi ("LONDON", "OFF_HOURS", vb.)
            equity_history : Equity degerleri listesi (kronolojik)
            trade_history  : Son islem gecmisi listesi
                             [{"symbol": str, "pnl": float, "won": bool, "ts": float}, ...]

        Returns:
            AgentDecision listesi (bos olabilir, birkac karar donebilir)
        """
        decisions: List[AgentDecision] = []
        now = time.time()

        balance = account.get("balance", 0.0)
        equity = account.get("equity", 0.0)
        margin = account.get("margin", 0.0)
        margin_level = account.get("margin_level", 0.0)
        daily_pnl = account.get("daily_pnl", 0.0)

        if balance <= 0:
            return decisions

        dd_pct = max(0.0, (balance - equity) / balance * 100.0)

        # ── 1. GUNLUK KAYIP LIMITI (%15) ─────────────────────
        daily_loss_pct = abs(daily_pnl) / balance * 100.0 if daily_pnl < 0 else 0.0
        max_daily = cfg.CLAUDE_HARD_LIMITS.get("max_daily_loss_pct", 15.0)

        if daily_loss_pct >= max_daily:
            decisions.append(AgentDecision(
                agent_name="RiskAgent",
                action="RISK_VETO",
                symbol="ALL",
                priority=85,
                confidence=100.0,
                reason=(
                    f"Gunluk kayip limiti asildi: {daily_loss_pct:.1f}% >= "
                    f"{max_daily:.0f}% (${daily_pnl:.2f})"
                ),
                urgency="NOW",
                metadata={
                    "daily_loss_pct": daily_loss_pct,
                    "daily_pnl": daily_pnl,
                    "veto_type": "daily_loss",
                },
                timestamp=now,
            ))

        # ── 2. TOPLAM DRAWDOWN KONTROLU — DEVRE DISI ───────────
        # SPM sistemi pozisyon yonetimini yapar. Zorla kapatma YOK.
        # Sadece loglama yapilir, EMERGENCY_CLOSE tetiklenmez.
        emergency_dd = cfg.CLAUDE_HARD_LIMITS.get("emergency_close_dd", 99.0)
        if dd_pct >= 50.0:  # Sadece bilgilendirme logu
            log.warning(
                f"[RiskAgent] DD yuksek: {dd_pct:.1f}% — SPM sistemi yonetiyor, "
                f"zorla kapatma YAPILMIYOR"
            )

        # ── 3. KORELASYON MARUZ KALMA KONTROLU ───────────────
        corr_decisions = self._check_correlation_exposure(positions, now)
        decisions.extend(corr_decisions)

        # ── 4. TOPLAM LOT LIMITI ─────────────────────────────
        total_lots = 0.0
        for sym_positions in positions.values():
            for pos in sym_positions:
                total_lots += getattr(pos, "lot", 0.0)

        if total_lots >= cfg.MAX_TOTAL_LOTS:
            decisions.append(AgentDecision(
                agent_name="RiskAgent",
                action="RISK_VETO",
                symbol="ALL",
                priority=85,
                confidence=95.0,
                reason=(
                    f"Toplam lot limiti: {total_lots:.2f} >= "
                    f"{cfg.MAX_TOTAL_LOTS} — yeni acilis engellendi"
                ),
                urgency="NOW",
                metadata={
                    "total_lots": total_lots,
                    "max_lots": cfg.MAX_TOTAL_LOTS,
                    "veto_type": "lot_limit",
                },
                timestamp=now,
            ))

        # ── 5. MARGIN SEVIYESI KONTROLU ──────────────────────
        if margin > 0 and margin_level > 0:
            # Margin kontrolu — sadece loglama, zorla kapatma YOK
            # Broker zaten margin call yapar, MIA mudahale etmez
            if margin_level < 50.0:
                log.warning(
                    f"[RiskAgent] Margin cok dusuk: {margin_level:.0f}% — "
                    f"SPM sistemi yonetiyor, broker margin call yapabilir"
                )
            elif margin_level < 150.0:
                log.info(
                    f"[RiskAgent] Margin dusuk: {margin_level:.0f}% — bilgi"
                )

        # ── 6. EQUITY EGRISI KORUMA — DEVRE DISI ──────────────
        # SPM sistemi pozisyon yonetimini yapar.
        # Equity egrisi sadece LOGLAMA yapar, EMERGENCY tetiklenmez.
        eq_status = self._equity_protector.check(equity_history)
        if eq_status in ("EMERGENCY", "PAUSE"):
            log.info(
                f"[RiskAgent] Equity egrisi: {eq_status} — "
                f"SPM sistemi yonetiyor, zorla kapatma/pause YAPILMIYOR"
            )
        # Asagidaki blok artik calismaz — yukaridaki if/elif kaldirdik
        if False:  # DEVRE DISI
            decisions.append(AgentDecision(
                agent_name="RiskAgent",
                action="PAUSE_TRADING",
                symbol="ALL",
                priority=75,
                confidence=90.0,
                reason="DEVRE DISI",
                urgency="NOW",
                metadata={
                    "equity_status": eq_status,
                    "veto_type": "equity_curve_pause",
                },
                timestamp=now,
            ))

        # ── 7. ARDISIK KAYIP TESPITI ─────────────────────────
        streak_decision = self._check_losing_streak(trade_history, now)
        if streak_decision:
            decisions.extend(streak_decision)

        # ── 8. SEANS BAZLI LIMITLER ──────────────────────────
        session_profile = cfg.SESSION_PROFILES.get(session, {})
        max_pos = session_profile.get("max_pos", 10)

        total_positions = sum(len(plist) for plist in positions.values())

        if total_positions >= max_pos:
            decisions.append(AgentDecision(
                agent_name="RiskAgent",
                action="RISK_VETO",
                symbol="ALL",
                priority=70,
                confidence=85.0,
                reason=(
                    f"Seans limiti ({session}): {total_positions} pozisyon >= "
                    f"max {max_pos} — yeni acilis engellendi"
                ),
                urgency="NOW",
                metadata={
                    "session": session,
                    "total_positions": total_positions,
                    "max_positions": max_pos,
                    "veto_type": "session_limit",
                },
                timestamp=now,
            ))

        return decisions

    def validate_open(
        self,
        symbol: str,
        direction: str,
        lot: float,
        positions: Dict[str, list],
        session: str,
    ) -> Tuple[bool, str, float]:
        """
        Yeni pozisyon acma istegini dogrula.

        Kontrol edilenler:
          - Sembol bazli pozisyon limiti
          - Toplam lot limiti
          - Korelasyon maruz kalimligi
          - Seans bazli limit
          - Adaptif lot carpani

        Args:
            symbol    : Acilmak istenen sembol
            direction : "BUY" veya "SELL"
            lot       : Istenen lot miktari
            positions : Mevcut tum pozisyonlar dict
            session   : Aktif seans adi

        Returns:
            (izin_var: bool, sebep: str, ayarlanmis_lot: float)
        """
        # Sembol bazli pozisyon limiti
        sym_positions = positions.get(symbol, [])
        max_per_sym = cfg.CLAUDE_HARD_LIMITS.get("max_positions_per_sym", 4)

        if len(sym_positions) >= max_per_sym:
            return (
                False,
                f"{symbol} icin max {max_per_sym} pozisyon limiti doldu",
                0.0,
            )

        # Toplam pozisyon limiti
        total_positions = sum(len(plist) for plist in positions.values())
        max_total = cfg.CLAUDE_HARD_LIMITS.get("max_positions_total", 10)

        if total_positions >= max_total:
            return (
                False,
                f"Toplam max {max_total} pozisyon limiti doldu",
                0.0,
            )

        # Toplam lot limiti
        total_lots = sum(
            sum(getattr(p, "lot", 0.0) for p in plist)
            for plist in positions.values()
        )

        if total_lots + lot > cfg.MAX_TOTAL_LOTS:
            # Lotu kucult
            available = max(0.0, cfg.MAX_TOTAL_LOTS - total_lots)
            if available < cfg.MIN_LOT:
                return (
                    False,
                    f"Toplam lot limiti asildi: {total_lots:.2f}/{cfg.MAX_TOTAL_LOTS}",
                    0.0,
                )
            lot = min(lot, available)
            lot = round(lot, 2)

        # Seans kontrolu
        session_profile = cfg.SESSION_PROFILES.get(session, {})
        max_session_pos = session_profile.get("max_pos", 10)
        aggression = session_profile.get("aggression", 1.0)

        if total_positions >= max_session_pos:
            return (
                False,
                f"Seans limiti ({session}): {total_positions}/{max_session_pos}",
                0.0,
            )

        # Seans agresifligine gore lot ayarla
        lot = round(lot * aggression, 2)
        lot = max(cfg.MIN_LOT, min(cfg.MAX_LOT_PER_SYMBOL, lot))

        # Korelasyon kontrolu
        max_corr = cfg.CLAUDE_HARD_LIMITS.get("max_correlated_exposure", 0.60)
        corr_exposure = self._calc_correlation_exposure(symbol, direction, positions)

        if corr_exposure > max_corr:
            # Korelasyon yuksek — lotu azalt
            reduction = max(0.3, 1.0 - (corr_exposure - max_corr))
            lot = round(lot * reduction, 2)
            lot = max(cfg.MIN_LOT, lot)
            log.info(
                f"[RiskAgent] {symbol} korelasyon maruz kalimi {corr_exposure:.0%} — "
                f"lot azaltildi: {lot:.2f}"
            )

        return (True, "Acilis onaylandi", lot)

    def get_adaptive_multiplier(
        self,
        trade_history: List[dict],
        dd_pct: float,
        regime: MarketRegime,
    ) -> float:
        """
        Son performansa ve piyasa kosullarina gore adaptif lot carpani hesapla.

        Hesaplama sirasi:
          1. Drawdown bazli azaltma (en yuksek oncelik)
          2. Win rate bazli ayarlama
          3. Ardisik kayip/kazanc bazli
          4. Piyasa rejimi carpani

        Args:
            trade_history : Son islem gecmisi [{pnl, won, ts}, ...]
            dd_pct        : Mevcut drawdown yuzdesi
            regime        : Guncel piyasa rejimi

        Returns:
            Lot carpani (0.0 - 1.5 arasi)
        """
        multiplier = 1.0

        # ── 1. DRAWDOWN BAZLI ─────────────────────────────────
        adaptive = cfg.ADAPTIVE_LOT

        if dd_pct >= adaptive["dd_critical"]["threshold"]:
            return adaptive["dd_critical"]["multiplier"]  # 0.0 = DURDUR

        if dd_pct >= adaptive["dd_danger"]["threshold"]:
            multiplier *= adaptive["dd_danger"]["multiplier"]  # 0.5

        elif dd_pct >= adaptive["dd_warning"]["threshold"]:
            multiplier *= adaptive["dd_warning"]["multiplier"]  # 0.7

        # ── 2. WIN RATE BAZLI ─────────────────────────────────
        recent_trades = trade_history[-20:] if len(trade_history) >= 20 else trade_history

        if len(recent_trades) >= 5:
            wins = sum(1 for t in recent_trades if t.get("won", False))
            win_rate = wins / len(recent_trades) * 100.0

            if win_rate >= adaptive["win_rate_high"]["threshold"]:
                multiplier *= adaptive["win_rate_high"]["multiplier"]  # 1.3
            elif win_rate <= adaptive["win_rate_low"]["threshold"]:
                multiplier *= adaptive["win_rate_low"]["multiplier"]   # 0.5

        # ── 3. ARDISIK KAYIP/KAZANC ──────────────────────────
        if trade_history:
            streak = self._get_current_streak(trade_history)

            if streak <= -cfg.LOSING_STREAK_STOP:
                multiplier = 0.0  # Tam durdur
            elif streak <= -cfg.LOSING_STREAK_LOT_REDUCE:
                multiplier *= 0.5  # %50 azalt
            elif streak >= cfg.WINNING_STREAK_LOT_BOOST:
                multiplier *= 1.3  # %30 artir

        # ── 4. PIYASA REJIMI ─────────────────────────────────
        regime_mult = cfg.REGIME_MULTIPLIERS.get(regime.value, 1.0)
        multiplier *= regime_mult

        # Sinirla
        multiplier = max(0.0, min(1.5, multiplier))

        return round(multiplier, 3)

    # ─── YARDIMCI METODLAR ────────────────────────────────────

    def _check_correlation_exposure(
        self,
        positions: Dict[str, list],
        now: float,
    ) -> List[AgentDecision]:
        """
        Korelasyonlu pozisyonlarin toplam maruz kalimini kontrol et.

        Ayni yonde korelasyonlu cifletlerdeki toplam lot oranini hesaplar.
        Max %60'i asarsa uyari verir.
        """
        decisions: List[AgentDecision] = []
        max_corr = cfg.CLAUDE_HARD_LIMITS.get("max_correlated_exposure", 0.60)

        # Aktif semboller ve yonleri
        active_dirs: Dict[str, str] = {}
        active_lots: Dict[str, float] = {}

        for sym, pos_list in positions.items():
            if not pos_list:
                continue
            # En buyuk pozisyonun yonu
            main_pos = next(
                (p for p in pos_list if getattr(p, "role", "") == "MAIN"),
                pos_list[0] if pos_list else None,
            )
            if main_pos:
                active_dirs[sym] = getattr(main_pos, "direction", "")
                active_lots[sym] = sum(
                    getattr(p, "lot", 0.0) for p in pos_list
                )

        total_lots = sum(active_lots.values())
        if total_lots <= 0:
            return decisions

        # Korelasyonlu ciftleri kontrol et
        for (sym_a, sym_b), corr_value in cfg.CORRELATION_PAIRS.items():
            if sym_a not in active_dirs or sym_b not in active_dirs:
                continue

            dir_a = active_dirs[sym_a]
            dir_b = active_dirs[sym_b]
            lot_a = active_lots.get(sym_a, 0.0)
            lot_b = active_lots.get(sym_b, 0.0)

            # Ayni yonde ve pozitif korelasyon VEYA ters yonde ve negatif korelasyon
            same_direction = (dir_a == dir_b)
            dangerous = (
                (same_direction and corr_value > 0.5) or
                (not same_direction and corr_value < -0.5)
            )

            if dangerous:
                combined_lot = lot_a + lot_b
                exposure = combined_lot / total_lots if total_lots > 0 else 0.0

                if exposure > max_corr:
                    decisions.append(AgentDecision(
                        agent_name="RiskAgent",
                        action="RISK_VETO",
                        symbol=f"{sym_a}+{sym_b}",
                        priority=80,
                        confidence=90.0,
                        reason=(
                            f"Korelasyon maruz kalimi: {sym_a}/{sym_b} "
                            f"corr={corr_value:.2f} exposure={exposure:.0%} > "
                            f"max {max_corr:.0%}"
                        ),
                        urgency="NOW",
                        metadata={
                            "sym_a": sym_a,
                            "sym_b": sym_b,
                            "correlation": corr_value,
                            "exposure": exposure,
                            "lot_a": lot_a,
                            "lot_b": lot_b,
                            "veto_type": "correlation",
                        },
                        timestamp=now,
                    ))

        return decisions

    def _calc_correlation_exposure(
        self,
        symbol: str,
        direction: str,
        positions: Dict[str, list],
    ) -> float:
        """
        Belirli bir sembol/yon icin korelasyon maruz kalimini hesapla.
        0.0 - 1.0 arasi deger dondurur.
        """
        max_exposure = 0.0

        for (sym_a, sym_b), corr_value in cfg.CORRELATION_PAIRS.items():
            partner = None
            if sym_a == symbol and sym_b in positions:
                partner = sym_b
            elif sym_b == symbol and sym_a in positions:
                partner = sym_a

            if partner is None:
                continue

            partner_positions = positions.get(partner, [])
            if not partner_positions:
                continue

            # Partner yonu
            partner_main = next(
                (p for p in partner_positions if getattr(p, "role", "") == "MAIN"),
                partner_positions[0] if partner_positions else None,
            )
            if not partner_main:
                continue

            partner_dir = getattr(partner_main, "direction", "")
            same_dir = (direction == partner_dir)

            # Tehlikeli kombinasyon kontrolu
            if (same_dir and corr_value > 0.5) or (not same_dir and corr_value < -0.5):
                max_exposure = max(max_exposure, abs(corr_value))

        return max_exposure

    def _check_losing_streak(
        self,
        trade_history: List[dict],
        now: float,
    ) -> List[AgentDecision]:
        """
        Ardisik kayip serisini kontrol et.
        3 ardisik kayip = lot %50 azalt, 5 ardisik kayip = DURDUR
        """
        decisions: List[AgentDecision] = []

        if not trade_history:
            return decisions

        streak = self._get_current_streak(trade_history)

        if streak <= -cfg.LOSING_STREAK_STOP:
            decisions.append(AgentDecision(
                agent_name="RiskAgent",
                action="STOP_TRADING",
                symbol="ALL",
                priority=90,
                confidence=100.0,
                reason=(
                    f"ARDISIK KAYIP SERISI: {abs(streak)} kayip >= "
                    f"{cfg.LOSING_STREAK_STOP} — ISLEM DURDURULUYOR"
                ),
                urgency="NOW",
                metadata={
                    "streak": streak,
                    "stop_threshold": cfg.LOSING_STREAK_STOP,
                    "veto_type": "losing_streak_stop",
                },
                timestamp=now,
            ))
        elif streak <= -cfg.LOSING_STREAK_LOT_REDUCE:
            decisions.append(AgentDecision(
                agent_name="RiskAgent",
                action="LOT_REDUCE",
                symbol="ALL",
                priority=75,
                confidence=95.0,
                lot=0.5,  # %50 azaltma carpani
                reason=(
                    f"Ardisik kayip serisi: {abs(streak)} kayip >= "
                    f"{cfg.LOSING_STREAK_LOT_REDUCE} — lot %50 azaltildi"
                ),
                urgency="NOW",
                metadata={
                    "streak": streak,
                    "reduce_threshold": cfg.LOSING_STREAK_LOT_REDUCE,
                    "lot_multiplier": 0.5,
                    "veto_type": "losing_streak_reduce",
                },
                timestamp=now,
            ))

        return decisions

    @staticmethod
    def _get_current_streak(trade_history: List[dict]) -> int:
        """
        Mevcut ardisik seriyi hesapla.
        Pozitif = kazanc serisi, Negatif = kayip serisi.
        """
        if not trade_history:
            return 0

        streak = 0
        # Sondan basa dogru tara
        last_won = trade_history[-1].get("won", False)
        direction = 1 if last_won else -1

        for trade in reversed(trade_history):
            if trade.get("won", False) == last_won:
                streak += direction
            else:
                break

        return streak


# =====================================================================
# SENTIMENT AGENT — Yerel + API, ~2s (placeholder)
# =====================================================================

class SentimentAgent:
    """
    Duygu Analiz Ajani — Piyasa duygu durumunu analiz eder.

    Bu sinif bir placeholder'dir. Gercek implementasyon sentiment_engine.py
    tarafindan saglanir ve bu sinifin metodlari override edilir.

    Kaynaklar (sentiment_engine.py tarafindan doldurulur):
      - Fear & Greed Index
      - Haber analizi (RSS + scraping)
      - DXY (Dolar Endeksi) korelasyonu
      - Sosyal medya duygu analizi

    Skor araligi: -100 (cok bearish) ile +100 (cok bullish) arasi
    """

    def __init__(self):
        self._scores: Dict[str, float] = {}
        self._last_update: float = 0.0
        self._update_interval: float = cfg.SENTIMENT_INTERVAL  # 300s

    def update(self) -> Dict[str, float]:
        """
        Tum sembollerin duygu skorlarini guncelle.

        Returns:
            {sembol: skor} dict'i
            Skor araligi: -100 (cok bearish) ile +100 (cok bullish)

        Not:
            Bu placeholder implementasyonda skorlar 0.0 (notr) olarak
            doner. Gercek implementasyon sentiment_engine.py'de yapilir.
        """
        self._last_update = time.time()

        # Placeholder: Tum semboller icin notr skor
        for symbol in cfg.ALL_SYMBOLS:
            if symbol not in self._scores:
                self._scores[symbol] = 0.0

        log.debug(
            f"[SentimentAgent] Skorlar guncellendi (placeholder): "
            f"{len(self._scores)} sembol"
        )
        return dict(self._scores)

    def get_score(self, symbol: str) -> float:
        """
        Belirli bir sembolun duygu skorunu dondur.

        Args:
            symbol: Islem sembolu (EURUSD, XAUUSD, vb.)

        Returns:
            Duygu skoru (-100 ile +100 arasi)
            0.0 = notr/bilinmiyor
        """
        return self._scores.get(symbol, 0.0)

    def set_scores(self, scores: Dict[str, float]):
        """
        Dis kaynaktan (sentiment_engine.py) skorlari ayarla.

        Args:
            scores: {sembol: skor} dict'i
        """
        self._scores.update(scores)
        self._last_update = time.time()

    @property
    def is_stale(self) -> bool:
        """Verilerin eski olup olmadigini kontrol et"""
        if self._last_update == 0:
            return True
        return (time.time() - self._last_update) > self._update_interval * 2


# =====================================================================
# ARBITRATOR — Karar Koordinatoru
# =====================================================================

class Arbitrator:
    """
    Karar Hakemi — Tum ajanlarin kararlarini birlestiren koordinator.

    Oncelik sistemi (yuksekten dusuge):
      100 : EMERGENCY_CLOSE   — Acil kapatma (DD, margin, equity)
       92 : GRID_CLOSE        — Grid margin acil kapama
       90 : PEAK_DROP         — Peak drop koruma
       85 : RISK_VETO         — Risk ajani engeli
       80 : GRID_FIFO_CLOSE   — FIFO hedef kapama (koruma)
       80 : MASTER_OVERRIDE   — Master ajan (Opus) karari
       78 : GRID_NET_SETTLE   — Net settlement (koruma)
       75 : GRID_PARTIAL_CLOSE — Mum donus / peak drop (grid)
       70 : STRATEGY_CLOSE    — Strateji ajani kapatma
       70 : GRID_PROMOTE      — SPM→ANA promosyon
       60 : GRID_OPEN_HEDGE   — Kurtarma hedge (veto edilebilir)
       50 : STRATEGY_OPEN     — Strateji ajani acilis
       45 : GRID_OPEN_SPM     — SPM acma (veto edilebilir)
       42 : GRID_OPEN_DCA     — DCA acma (veto edilebilir)
       40 : FAST_ENTRY        — Hizli giris (Speed Agent)
       30 : GRID_DEADLOCK_WARN — Kilitlenme uyarisi
       30 : SENTIMENT_WARN    — Duygu uyarisi

    Catisma cozme kurallari:
      1. Risk/Speed CLOSE her zaman kazanir (veto)
      2. Grid CLOSE/FIFO/NET_SETTLE otomatik (koruma — Brain veto edemez)
      3. Grid OPEN_SPM/DCA/HEDGE Brain veto'suna tabi
      4. Master OVERRIDE > Strategy kararlari
      5. Strategy OPEN sadece Risk dogrularsa gecerli
      6. Sentiment WARN lotu azaltir ama engellemez
    """

    # Karar tipi oncelikleri
    PRIORITY = {
        # Acil / Koruma (Brain veto edemez)
        "EMERGENCY_CLOSE":   100,
        "GRID_CLOSE":         92,   # Margin acil kapama (grid)
        "PEAK_DROP":          90,
        "RISK_VETO":          85,
        "STOP_TRADING":       85,
        "GRID_FIFO_CLOSE":    80,   # FIFO hedef kapama (koruma)
        "PAUSE_TRADING":      80,
        "MASTER_OVERRIDE":    80,
        "GRID_NET_SETTLE":    78,   # Net settlement kapama (koruma)
        "GRID_PARTIAL_CLOSE": 75,   # Mum donus / peak drop grid
        "REVERSE_BUY":        72,   # Pozisyon ters cevirme (kapat + ters ac)
        "REVERSE_SELL":       72,   # Pozisyon ters cevirme (kapat + ters ac)
        "STRATEGY_CLOSE":     70,
        "GRID_PROMOTE":       70,   # SPM→ANA promosyon (internal)
        # Acilis / Bilgi (Brain veto edebilir)
        "LOT_REDUCE":         60,
        "GRID_OPEN_HEDGE":    60,   # Kurtarma hedge (acil ama veto edilebilir)
        "STRATEGY_OPEN":      50,
        "GRID_OPEN_SPM":      45,   # SPM acma
        "GRID_OPEN_DCA":      42,   # DCA acma
        "FAST_ENTRY":         40,
        "GRID_DEADLOCK_WARN": 30,   # Bilgi: kilitlenme uyarisi
        "SENTIMENT_WARN":     30,
    }

    def __init__(self):
        self._pending: List[AgentDecision] = []
        self._resolved: List[AgentDecision] = []
        self._last_process_time: float = 0.0

    def submit(self, decisions: List[AgentDecision]):
        """
        Ajan kararlarini kuyruga ekle.

        Her ajan kendi kararlarini submit() ile gonderir.
        process() cagirildiginda tum kararlar birlestirilir.

        Args:
            decisions: AgentDecision listesi
        """
        for d in decisions:
            # Onceligi karar tipinden ata (eger ayarlanmamissa)
            if d.action in self.PRIORITY:
                d.priority = max(d.priority, self.PRIORITY[d.action])
            self._pending.append(d)

        if decisions:
            log.debug(
                f"[Arbitrator] {len(decisions)} karar eklendi, "
                f"toplam kuyruk: {len(self._pending)}"
            )

    def process(self) -> List[AgentDecision]:
        """
        Bekleyen tum kararlari isleyerek catismalari coz.

        Isleme sirasi:
          1. Oncelik sirasina gore sirala
          2. Acil kapatmalari hemen uygula
          3. Risk veto'lari kontrol et — acilis kararlarini engelle
          4. Master override'lari uygula
          5. Strateji kararlarini filtrele
          6. Sentiment uyarilarini uygula

        Returns:
            Cozulmus AgentDecision listesi (oncelik sirasinda)
        """
        if not self._pending:
            return []

        self._last_process_time = time.time()

        # ── 1. ONCELIK SIRASINA GORE SIRALA ──────────────────
        self._pending.sort(key=lambda d: d.priority, reverse=True)

        resolved: List[AgentDecision] = []
        vetoed_symbols: set = set()
        has_emergency: bool = False
        has_stop: bool = False
        has_pause: bool = False
        lot_reduce_factor: float = 1.0
        master_overrides: Dict[str, AgentDecision] = {}

        # ── 2. ILK GECIS: ACIL DURUMLARI VE VETOLARI TOPLA ──
        for d in self._pending:
            # Acil kapatma
            if d.action == "EMERGENCY_CLOSE":
                has_emergency = True
                resolved.append(d)
                log.warning(
                    f"[Arbitrator] ACIL KAPATMA: {d.symbol} — {d.reason}"
                )

            # Islem durdurma
            elif d.action == "STOP_TRADING":
                has_stop = True
                resolved.append(d)
                log.warning(f"[Arbitrator] ISLEM DURDURMA: {d.reason}")

            # Islem duraklatma
            elif d.action == "PAUSE_TRADING":
                has_pause = True
                resolved.append(d)

            # Risk veto — hangi semboller engellendi
            elif d.action == "RISK_VETO":
                if d.symbol == "ALL":
                    vetoed_symbols.add("ALL")
                else:
                    vetoed_symbols.add(d.symbol)
                resolved.append(d)

            # Peak drop — dogrudan uygula
            elif d.action == "PEAK_DROP":
                resolved.append(d)

            # Grid koruma aksiyonlari — Brain veto edemez, dogrudan uygula
            elif d.action in (
                "GRID_CLOSE", "GRID_FIFO_CLOSE", "GRID_NET_SETTLE",
                "GRID_PARTIAL_CLOSE", "GRID_PROMOTE",
            ):
                resolved.append(d)
                log.info(
                    f"[Arbitrator] Grid koruma: {d.action} {d.symbol} — {d.reason}"
                )

            # Lot azaltma
            elif d.action == "LOT_REDUCE":
                lot_reduce_factor = min(
                    lot_reduce_factor,
                    d.metadata.get("lot_multiplier", 0.5),
                )
                resolved.append(d)

            # Master override
            elif d.action == "MASTER_OVERRIDE":
                master_overrides[d.symbol] = d

        # Grid acma aksiyonlari (Brain veto edebilir)
        _GRID_OPEN_ACTIONS = {"GRID_OPEN_SPM", "GRID_OPEN_DCA", "GRID_OPEN_HEDGE"}
        # Grid koruma aksiyonlari (zaten ilk geciste islendi)
        _GRID_CLOSE_ACTIONS = {
            "GRID_CLOSE", "GRID_FIFO_CLOSE", "GRID_NET_SETTLE",
            "GRID_PARTIAL_CLOSE", "GRID_PROMOTE",
        }
        # Tum acilis aksiyonlari (normal + grid)
        _ALL_OPEN_ACTIONS = {
            "STRATEGY_OPEN", "FAST_ENTRY", "OPEN_BUY", "OPEN_SELL",
        } | _GRID_OPEN_ACTIONS

        # ── 3. IKINCI GECIS: STRATEJI VE GIRIS KARARLARI ────
        for d in self._pending:
            # Zaten islenmis aksiyonlari atla
            if d.action in (
                "EMERGENCY_CLOSE", "STOP_TRADING", "PAUSE_TRADING",
                "RISK_VETO", "PEAK_DROP", "LOT_REDUCE", "MASTER_OVERRIDE",
            ) or d.action in _GRID_CLOSE_ACTIONS:
                continue

            # Acil durum varsa yeni acilis yok
            if has_emergency or has_stop:
                if d.action in _ALL_OPEN_ACTIONS:
                    log.info(
                        f"[Arbitrator] {d.action} {d.symbol} engellendi — "
                        f"acil durum aktif"
                    )
                    continue

            # Pause modunda yeni acilis yok (normal acilis engellenir,
            # ama GRID_OPEN_HEDGE hala gecebilir — kurtarma amaçli)
            if has_pause:
                if d.action in (_ALL_OPEN_ACTIONS - {"GRID_OPEN_HEDGE"}):
                    log.info(
                        f"[Arbitrator] {d.action} {d.symbol} engellendi — "
                        f"pause modu aktif"
                    )
                    continue

            # Veto kontrolu
            if d.action in _ALL_OPEN_ACTIONS:
                if "ALL" in vetoed_symbols or d.symbol in vetoed_symbols:
                    log.info(
                        f"[Arbitrator] {d.action} {d.symbol} engellendi — "
                        f"risk veto aktif"
                    )
                    continue

            # Master override kontrolu — Strategy kararlarini ezer
            if d.action in ("STRATEGY_OPEN", "STRATEGY_CLOSE"):
                if d.symbol in master_overrides:
                    log.info(
                        f"[Arbitrator] {d.action} {d.symbol} Master override "
                        f"tarafindan ezildi"
                    )
                    continue

            # REVERSE kararlar — kapat + ters yone gir (trend donusu)
            if d.action in ("REVERSE_BUY", "REVERSE_SELL"):
                if d.confidence < 55:
                    log.info(
                        f"[Arbitrator] {d.action} {d.symbol} engellendi — "
                        f"dusuk confidence ({d.confidence:.0f}% < 55%)"
                    )
                    continue
                resolved.append(d)
                continue

            # Kapatma kararlari — Risk/Speed kapatmalari her zaman kazanir
            # STRATEGY_CLOSE icin minimum confidence kontrolu
            if d.action in ("CLOSE", "STRATEGY_CLOSE"):
                if d.action == "STRATEGY_CLOSE" and d.confidence < 50:
                    log.info(
                        f"[Arbitrator] STRATEGY_CLOSE {d.symbol} engellendi — "
                        f"dusuk confidence ({d.confidence:.0f}% < 50%)"
                    )
                    continue
                resolved.append(d)
                continue

            # Acilis kararlari — lot ayarlamasi (normal + grid acilis)
            if d.action in _ALL_OPEN_ACTIONS:
                # Lot azaltma faktoru uygula
                if lot_reduce_factor < 1.0 and d.lot > 0:
                    original_lot = d.lot
                    d.lot = round(d.lot * lot_reduce_factor, 2)
                    d.lot = max(cfg.MIN_LOT, d.lot)
                    d.metadata["lot_reduced_from"] = original_lot
                    d.metadata["lot_reduce_factor"] = lot_reduce_factor
                    d.reason += f" (lot azaltildi: {original_lot}->{d.lot})"

                resolved.append(d)
                continue

            # Deadlock uyarisi — bilgi amacli
            if d.action == "GRID_DEADLOCK_WARN":
                resolved.append(d)
                continue

            # Sentiment uyarisi — lot azalt ama engelleme
            if d.action == "SENTIMENT_WARN":
                resolved.append(d)
                continue

            # Diger kararlar (HOLD, PARTIAL_CLOSE, vb.)
            resolved.append(d)

        # Master override'lari ekle
        for sym, d in master_overrides.items():
            resolved.append(d)

        # Tekrarlari temizle ve oncelik sirasinda dondur
        seen = set()
        final: List[AgentDecision] = []
        for d in resolved:
            key = (d.agent_name, d.action, d.symbol, d.metadata.get("ticket", ""))
            if key not in seen:
                seen.add(key)
                final.append(d)

        self._resolved = final
        self._pending.clear()

        if final:
            log.info(
                f"[Arbitrator] {len(final)} karar islendi: "
                + ", ".join(f"{d.action}({d.symbol})" for d in final[:5])
                + ("..." if len(final) > 5 else "")
            )

        return final

    def clear(self):
        """Bekleyen tum kararlari temizle"""
        count = len(self._pending)
        self._pending.clear()
        self._resolved.clear()
        if count > 0:
            log.debug(f"[Arbitrator] {count} bekleyen karar temizlendi")

    @property
    def pending_count(self) -> int:
        """Bekleyen karar sayisi"""
        return len(self._pending)

    @property
    def last_resolved(self) -> List[AgentDecision]:
        """Son islenen kararlar"""
        return list(self._resolved)


# =====================================================================
# GRID AGENT — EA Grid/FIFO/Cascade Sistemi Wrapper
# =====================================================================

class GridAgent:
    """
    Grid Pozisyon Yonetim Ajani — BytamerFX EA PositionManager portu.

    Her aktif sembol icin bir GridManager instance olusturur ve yonetir.
    Tick hizinda (~1s) calisir, API cagirmaz.

    Gorevleri:
      1. Sembol bazli GridManager lifecycle (olustur / sil)
      2. GridManager.on_tick() cagir → dict listesini AgentDecision'a cevir
      3. SpeedAgent ile koordinasyon (grid aktifken peak drop delege)
      4. FIFO/kasa/net settlement state yonetimi
      5. Dashboard icin tum grid state toplama

    Kullanim:
        grid_agent = GridAgent()
        grid_agent.activate("XAUUSD")
        decisions = grid_agent.tick("XAUUSD", positions_raw, account, ...)
        arbitrator.submit(decisions)
    """

    def __init__(self):
        self._managers: Dict[str, GridManager] = {}
        self._lot_calcs: Dict[str, LotCalculator] = {}
        self._profiles: Dict[str, SymbolProfile] = {}
        self._active_symbols: set = set()

    # ── Sembol aktivasyonu ─────────────────────────────────────
    def activate(self, symbol: str):
        """Sembol icin GridManager ve LotCalculator olustur."""
        sym = symbol.upper()
        if sym in self._managers:
            return

        profile = get_symbol_profile(sym)
        self._profiles[sym] = profile

        lot_calc = LotCalculator(
            symbol=sym,
            profile=profile,
        )
        self._lot_calcs[sym] = lot_calc

        gm = GridManager(
            symbol=sym,
            profile=profile,
            lot_calc=lot_calc,
        )
        self._managers[sym] = gm
        self._active_symbols.add(sym)

        log.info(
            f"[GridAgent] {sym} aktif — profil={profile.profile_name} "
            f"min_lot={profile.min_lot}"
        )

    def deactivate(self, symbol: str):
        """Sembol icin GridManager'i kaldir."""
        sym = symbol.upper()
        self._managers.pop(sym, None)
        self._lot_calcs.pop(sym, None)
        self._profiles.pop(sym, None)
        self._active_symbols.discard(sym)
        log.info(f"[GridAgent] {sym} deaktif")

    def is_active(self, symbol: str) -> bool:
        """Sembol icin grid aktif mi?"""
        return symbol.upper() in self._managers

    # ── Ana tick — GridManager calistir ve AgentDecision uret ──
    def tick(
        self,
        symbol: str,
        positions_raw: List[dict],
        account: dict,
        candle_dir: str = "NONE",
        h1_data: Optional[dict] = None,
        signal_score: int = 0,
        signal_dir: str = "NONE",
        new_bar: bool = False,
        spread_ratio: float = 1.0,
        news_blocked: bool = False,
    ) -> List[AgentDecision]:
        """
        Sembol icin grid pipeline calistir.

        GridManager.on_tick() dict listesi dondurur.
        Bu metod dict'leri AgentDecision'a cevirir.

        Returns:
            AgentDecision listesi (bos olabilir)
        """
        sym = symbol.upper()
        gm = self._managers.get(sym)
        if gm is None:
            return []

        # GridManager pipeline calistir
        raw_decisions = gm.on_tick(
            positions_raw=positions_raw,
            account=account,
            candle_dir=candle_dir,
            h1_data=h1_data,
            signal_score=signal_score,
            signal_dir=signal_dir,
            new_bar=new_bar,
            spread_ratio=spread_ratio,
            news_blocked=news_blocked,
        )

        # Dict → AgentDecision donusumu
        decisions: List[AgentDecision] = []
        now = time.time()

        for rd in raw_decisions:
            action = rd.get("action", "")
            priority = rd.get("priority", 50)
            metadata = rd.get("metadata", {})

            decisions.append(AgentDecision(
                agent_name="GridAgent",
                action=action,
                symbol=sym,
                priority=priority,
                confidence=rd.get("confidence", 90.0),
                lot=rd.get("lot", 0.0),
                reason=rd.get("reason", ""),
                urgency=rd.get("urgency", "NOW"),
                metadata=metadata,
                timestamp=now,
            ))

        return decisions

    # ── SpeedAgent koordinasyonu ───────────────────────────────
    def has_grid_positions(self, symbol: str) -> bool:
        """
        Sembolde aktif grid pozisyonu var mi?
        Grid aktifken SpeedAgent peak drop'u GridManager'a birakir
        (profil-bazli esikler daha dogru).
        """
        sym = symbol.upper()
        gm = self._managers.get(sym)
        if gm is None:
            return False
        return len(gm.positions) > 0

    def should_delegate_peak_drop(self, symbol: str) -> bool:
        """
        SpeedAgent bu sembol icin peak drop'u GridAgent'a delege etmeli mi?
        Grid aktif ve pozisyon varsa True → SpeedAgent peak drop uretmez.
        """
        return self.has_grid_positions(symbol)

    # ── LotCalculator erisimi ──────────────────────────────────
    def get_lot_calculator(self, symbol: str) -> Optional[LotCalculator]:
        """Sembol icin LotCalculator dondur (brain.py icin)."""
        return self._lot_calcs.get(symbol.upper())

    def update_broker_info(
        self,
        symbol: str,
        min_lot: float,
        max_lot: float,
        lot_step: float,
        tick_value: float = 0.0,
        contract_size: float = 0.0,
    ):
        """MT5 baglantisi sonrasi broker bilgilerini guncelle."""
        lc = self._lot_calcs.get(symbol.upper())
        if lc:
            lc.update_broker_info(min_lot, max_lot, lot_step, tick_value, contract_size)

    # ── Durum sorgulari ────────────────────────────────────────
    def get_fifo_summary(self, symbol: str) -> Optional[FIFOSummary]:
        """Sembol icin FIFO/grid ozeti."""
        gm = self._managers.get(symbol.upper())
        if gm is None:
            return None
        return gm.get_fifo_summary()

    def get_all_summaries(self) -> Dict[str, FIFOSummary]:
        """Tum aktif semboller icin FIFO ozetleri."""
        return {
            sym: gm.get_fifo_summary()
            for sym, gm in self._managers.items()
        }

    def get_total_kasa(self) -> float:
        """Tum sembollerden toplam kasa ($)."""
        return sum(gm.kasa for gm in self._managers.values())

    def get_grid_state(self) -> dict:
        """
        Dashboard icin tum grid state.

        Returns:
            {
                "active_symbols": [...],
                "total_kasa": float,
                "summaries": {symbol: FIFOSummary dict, ...},
                "total_grid_positions": int,
            }
        """
        summaries = {}
        total_pos = 0
        hedge_details = {}  # v3.8.0: Hedge age/PnL for SafetyShield
        for sym, gm in self._managers.items():
            fs = gm.get_fifo_summary()
            summaries[sym] = {
                "kasa": fs.kasa,
                "net": fs.net,
                "target": fs.target,
                "active_dir": fs.active_grid_dir,
                "legacy_dir": fs.legacy_grid_dir,
                "vol_regime": fs.vol_regime,
                "main_profit": fs.main_profit,
                "spm_count": fs.spm_count,
                "hedge_count": fs.hedge_count,
                "dca_count": fs.dca_count,
                "total_positions": fs.total_positions,
                "total_pnl": fs.total_pnl,
            }
            total_pos += fs.total_positions
            # v3.8.0: Hedge detayları (age, profit)
            for pos in gm.positions:
                if pos.role == "HEDGE":
                    hedge_details.setdefault(sym, []).append({
                        "ticket": pos.ticket,
                        "age_sec": pos.age_sec,
                        "profit": pos.profit,
                        "direction": pos.direction,
                        "volume": pos.volume,
                    })

        return {
            "enabled": cfg.GRID_ENABLED,
            "active_symbols": list(self._active_symbols),
            "total_kasa": self.get_total_kasa(),
            "total_grid_positions": total_pos,
            "summaries": summaries,
            "hedge_details": hedge_details,
        }

    @property
    def active_symbols(self) -> set:
        """Aktif sembol listesi."""
        return set(self._active_symbols)

    @property
    def managers(self) -> Dict[str, GridManager]:
        """GridManager dict (read-only amaçlı)."""
        return dict(self._managers)
