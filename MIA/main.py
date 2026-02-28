"""
BytamerFX MIA v6.2.0 — Multi-Agent Autonomous Orchestrator
Coklu-ajan, coklu-thread, olay-gudumlu orkestrator.

Thread Modeli:
  MAIN THREAD    (1s)       : SpeedAgent + GridAgent + RiskAgent + Arbitrator + Execute
  STRATEGY THREAD (2-5dk)   : Brain.decide_symbol() per symbol -> Arbitrator
  MASTER THREAD   (15-30dk) : Brain.decide_portfolio() -> lot/blacklist/risk
  SENTIMENT THREAD (5dk)    : SentimentEngine.update() -> SignalEngine overlay
  DASHBOARD+TELEGRAM THREAD : HTTP server + Telegram polling

Olay Tetikleyiciler:
  SIGNAL           : Sinyal skoru >= 70 (speed agent scan)
  SESSION_CHANGE   : Seans degisimi (London acilisi vb.)
  SPREAD_RECOVERED : Spread normallesme

Copyright 2026, By T@MER — https://www.bytamer.com
Calistirma: python main.py
"""

import time
import signal as os_signal
import logging
import sys
import threading
from enum import Enum, auto
from typing import Dict, List, Set, Optional
from dataclasses import dataclass, field

import config as cfg
from mt5_bridge        import MT5Bridge
from market_intel      import MarketIntelligence
from brain             import AutonomousBrain, MasterDecision
from executor          import TradeExecutor
from signal_engine     import SignalEngine, Dir
from agents            import (
    SpeedAgent, RiskAgent, SentimentAgent, GridAgent, Arbitrator, AgentDecision,
)
from news_manager      import NewsManager
from sentiment_engine  import SentimentEngine
from telegram_commander import MIACommander
from dashboard_api     import (DashboardServer, dash_state, update_from_snapshot,
                                update_brain_decision, update_grid_state, update_news_state,
                                update_safety_shield)
from mt5_chart_writer  import MT5ChartWriter

# ─── LOGGING ──────────────────────────────────────────────
logging.basicConfig(
    level   = getattr(logging, cfg.LOG_LEVEL),
    format  = "%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    datefmt = "%H:%M:%S",
    handlers = [
        logging.StreamHandler(sys.stdout),
        logging.FileHandler(cfg.LOG_FILE, encoding="utf-8"),
    ]
)
log = logging.getLogger("MIA")


# ═══════════════════════════════════════════════════════════
# OLAY TIPLERI
# ═══════════════════════════════════════════════════════════

class EventType(Enum):
    """Strategy thread'i tetikleyen olay tipleri."""
    SIGNAL          = auto()   # Sinyal skoru >= 70
    SESSION_CHANGE  = auto()   # Seans degisimi
    SPREAD_RECOVERED = auto()  # Spread normallesme
    TIMER           = auto()   # Periyodik zamanlayici
    MANUAL          = auto()   # Telegram /brain komutu
    STARTUP         = auto()   # Ilk calistirma


@dataclass
class StrategyEvent:
    """Strategy thread'e gonderilen olay."""
    event_type: EventType
    symbol:     str = ""       # Bos ise tum aktif semboller
    data:       dict = field(default_factory=dict)
    timestamp:  float = field(default_factory=time.time)


# ═══════════════════════════════════════════════════════════
# ANA SINIF — MIA v4.0
# ═══════════════════════════════════════════════════════════

class MIA:
    """
    MIA v4.0 — Market Intelligence Agent
    Coklu-ajan, coklu-thread, olay-gudumlu otonom forex sistemi.

    Sembol yonetimi Telegram'dan yapilir:
      /ac BTC XAG   -> aktive et
      /kapat GBP    -> pozisyonlari kapat
      /durdur EUR   -> pasife al
      /pause        -> tum islemleri duraklat
      /resume       -> islemlere devam et
    """

    # ─── MAX THREAD RESTART ────────────────────────────────
    MAX_THREAD_RETRIES = 3

    def __init__(self):
        # ── Cekirdek Bilesenlerin ──────────────────────────
        self.bridge        = MT5Bridge()
        self.intel         = None    # connect() sonrasi olusturulacak
        self.brain         = AutonomousBrain()
        self.risk_agent    = RiskAgent()
        self.executor      = None    # connect() sonrasi olusturulacak
        self.signals       = {sym: SignalEngine(sym) for sym in cfg.ALL_SYMBOLS}
        self.speed_agent   = SpeedAgent()
        self.grid_agent    = GridAgent()
        self.news_manager  = NewsManager()
        self.sentiment_agent  = SentimentAgent()
        self.arbitrator    = Arbitrator()
        self.sentiment_engine = None  # connect() sonrasi olusturulacak
        self.telegram      = MIACommander()
        self.dashboard     = DashboardServer(port=8765)
        self.chart_writer  = MT5ChartWriter()

        # ── Paylasilan Durum (thread-safe) ─────────────────
        self._lock               = threading.Lock()
        self._active_symbols: Set[str] = set(cfg.DEFAULT_ACTIVE)
        self.running             = False
        self._paused             = False  # /pause komutu ile
        self.tick_count          = 0
        self.start_time          = 0.0

        # ── Zamanlayicilar ─────────────────────────────────
        self._last_status        = 0.0
        self._last_periodic_notify = 0.0
        self._last_session       = ""

        # ── Spread Takibi ──────────────────────────────────
        self._spread_high: Dict[str, bool] = {}

        # ── Equity Gecmisi (RiskAgent icin) ────────────────
        self._equity_history: List[float] = []
        self._trade_history:  List[dict]  = []

        # ── Olay Kuyrugu (Strategy Thread) ─────────────────
        self._event_queue:  List[StrategyEvent] = []
        self._event_lock    = threading.Lock()
        self._event_signal  = threading.Event()

        # ── Arbitrator Kilidi (tek thread process yapar) ───
        self._arbitrator_lock = threading.Lock()

        # ── Thread Retry Sayaclari ─────────────────────────
        self._thread_retries: Dict[str, int] = {
            "strategy":  0,
            "master":    0,
            "sentiment": 0,
        }

        # ── Graceful Shutdown ──────────────────────────────
        os_signal.signal(os_signal.SIGINT,  self._shutdown)
        os_signal.signal(os_signal.SIGTERM, self._shutdown)

        # ── Telegram Callback'leri ─────────────────────────
        self._wire_telegram()

    # ═══════════════════════════════════════════════════════
    # BASLAT
    # ═══════════════════════════════════════════════════════

    def start(self):
        """MIA v4.0 tum bilesenlerini baslat ve ana donguyu calistir."""
        self._print_banner()

        # ── MT5 Baglantisi ─────────────────────────────────
        connected = self.bridge.connect()
        if not connected:
            log.warning("MT5 baglanamadi — demo modu")

        # ── Geciktirilmis Bilesenlerin ─────────────────────
        self.intel = MarketIntelligence(self.bridge)
        self.brain.set_intel(self.intel)
        self.executor = TradeExecutor(self.bridge, self.brain, self.risk_agent)
        self.sentiment_engine = SentimentEngine(self.bridge)

        # ── Dashboard + Telegram ───────────────────────────
        self.dashboard.start()
        if cfg.TELEGRAM_ENABLED:
            self.telegram.start()

        # ── Durum Bayraklari ───────────────────────────────
        self.running    = True
        self._paused    = False
        self.start_time = time.time()

        # ── Hesap Bilgisi ──────────────────────────────────
        acc = self.bridge.get_account()
        log.info(f"Hesap: #{cfg.MT5_LOGIN} | Bakiye: ${acc.get('balance',0):.2f}")
        log.info(f"Aktif: {list(self._active_symbols) or 'YOK — Telegram /ac ile baslat'}")

        # GridAgent aktive et (default active semboller icin)
        if cfg.GRID_ENABLED and self._active_symbols:
            for sym in self._active_symbols:
                self.grid_agent.activate(sym)
            log.info(f"GridAgent: {list(self._active_symbols)} aktif")

        log.info("MIA v6.2.0 hazir — Coklu-Ajan Otonom Sistem + EA Grid\n")

        # ── Alt Thread'leri Baslat ─────────────────────────
        self._start_strategy_thread()
        self._start_master_thread()
        self._start_sentiment_thread()
        self._start_dashboard_thread()

        # ── Ilk Calismada Strategy Tetikle ─────────────────
        if self._active_symbols:
            self._push_event(StrategyEvent(
                event_type=EventType.STARTUP,
            ))

        # ── Ana Dongu (bu thread'de) ──────────────────────
        self._main_loop()

    # ═══════════════════════════════════════════════════════
    # THREAD BASLATMA VE YONETIMI
    # ═══════════════════════════════════════════════════════

    def _start_strategy_thread(self):
        """Strategy thread'i baslat (olay-gudumlu + zamanlayici)."""
        t = threading.Thread(
            target=self._strategy_thread_wrapper,
            name="StrategyThread",
            daemon=True,
        )
        t.start()
        log.info("[Thread] StrategyThread baslatildi")

    def _start_master_thread(self):
        """Master thread'i baslat (15-30dk periyodik)."""
        t = threading.Thread(
            target=self._master_thread_wrapper,
            name="MasterThread",
            daemon=True,
        )
        t.start()
        log.info("[Thread] MasterThread baslatildi")

    def _start_sentiment_thread(self):
        """Sentiment thread'i baslat (5dk periyodik)."""
        t = threading.Thread(
            target=self._sentiment_thread_wrapper,
            name="SentimentThread",
            daemon=True,
        )
        t.start()
        log.info("[Thread] SentimentThread baslatildi")

    def _start_dashboard_thread(self):
        """Dashboard realtime thread — 500ms periyot, anlik fiyat/pozisyon/hesap."""
        t = threading.Thread(
            target=self._dashboard_thread_loop,
            name="DashboardRT",
            daemon=True,
        )
        t.start()
        log.info("[Thread] DashboardRT baslatildi (500ms)")

    def _dashboard_thread_loop(self):
        """
        Dashboard icin bagimsiz realtime dongu.
        Ana donguden ayri calisir — ana dongunun agir islemleri
        (SpeedAgent, GridAgent vb.) dashboard guncellemeyi yavaslatamaz.
        """
        while self.running:
            t0 = time.time()
            try:
                self._tick_dashboard()
            except Exception as e:
                log.debug(f"dashboard_rt: {e}")
            elapsed = time.time() - t0
            time.sleep(max(0.05, 0.5 - elapsed))

    def _thread_wrapper(self, name: str, target_fn, restart_fn):
        """
        Thread guvenlik sarmalayici: try/except + otomatik yeniden baslat.

        Args:
            name:       Thread adi (strategy/master/sentiment)
            target_fn:  Calistirilacak fonksiyon
            restart_fn: Yeniden baslatma fonksiyonu
        """
        try:
            target_fn()
        except Exception as e:
            log.error(f"[{name}] Thread HATASI: {e}", exc_info=True)
            retries = self._thread_retries.get(name, 0)
            if retries < self.MAX_THREAD_RETRIES and self.running:
                self._thread_retries[name] = retries + 1
                wait = (retries + 1) * 5
                log.warning(
                    f"[{name}] Thread yeniden baslatiliyor "
                    f"({retries+1}/{self.MAX_THREAD_RETRIES}) — {wait}s bekleniyor"
                )
                time.sleep(wait)
                restart_fn()
            else:
                log.critical(
                    f"[{name}] Thread kalici hata — "
                    f"max {self.MAX_THREAD_RETRIES} deneme asildi. "
                    f"Diger thread'ler devam ediyor."
                )
                self.telegram.notify_emergency(
                    f"{name} thread'i kalici hatayla durdu!"
                )

    # ═══════════════════════════════════════════════════════
    # ANA DONGU (MAIN THREAD) — 1s periyot
    # ═══════════════════════════════════════════════════════

    def _main_loop(self):
        """
        Ana tick dongusu — her saniye calisir.

        Isler:
          1. SpeedAgent.tick_protect() — pozisyon koruma (~1ms)
          2. SpeedAgent.fast_entry_scan() — hizli giris taramasi (~1ms)
          3. RiskAgent.check_all() — hesap risk kontrolu (~1ms)
          4. Arbitrator.process() — karar birlestirme (~1ms)
          5. Executor.execute_agent_decisions() — kararlari yurutme
          6. Olay tetikleyicilerini kontrol et (sinyal, seans, spread)
          7. Periyodik loglama ve raporlama
        """
        while self.running:
            t0 = time.time()
            self.tick_count += 1
            try:
                active = self._get_active()

                if active and not self._paused:
                    # ── 1. SpeedAgent: Pozisyon Koruma ─────────
                    for sym in active:
                        try:
                            self._tick_speed_agent(sym)
                        except Exception as e:
                            log.debug(f"[{sym}] speed tick: {e}")

                    # ── 2. GridAgent: Grid Pipeline ───────────
                    if cfg.GRID_ENABLED:
                        for sym in active:
                            try:
                                self._tick_grid_agent(sym)
                            except Exception as e:
                                log.debug(f"[{sym}] grid tick: {e}")

                    # ── 3. SpeedAgent: Hizli Giris Taramasi ───
                    for sym in active:
                        try:
                            self._tick_fast_entry(sym)
                        except Exception as e:
                            log.debug(f"[{sym}] fast entry: {e}")

                    # ── 4. RiskAgent: Hesap Risk Kontrolu ─────
                    try:
                        self._tick_risk_agent(active)
                    except Exception as e:
                        log.debug(f"risk agent: {e}")

                    # ── 5. News Manager: Haber Block + Alert ──
                    if cfg.NEWS_ENABLED:
                        try:
                            self._tick_news_manager(active)
                        except Exception as e:
                            log.debug(f"news: {e}")

                    # ── 6+7. Arbitrator: Isle + Yurutme ──────
                    try:
                        self._tick_arbitrator()
                    except Exception as e:
                        log.debug(f"arbitrator: {e}")

                    # ── 8. Olay Tetikleyicileri ────────────────
                    try:
                        self._check_event_triggers(active)
                    except Exception as e:
                        log.debug(f"events: {e}")

                # ── 9. Dashboard → Ayri thread'e tasindi (DashboardRT, 500ms)

                # ── 10. Periyodik Loglama ───────────────────────
                now = time.time()
                if now - self._last_status > 30:
                    self._log_status()
                    self._last_status = now

                # Gunluk rapor (24 saatte bir)
                if now - self._last_periodic_notify > 86400:
                    self._send_daily_report()
                    self._last_periodic_notify = now

            except Exception as e:
                log.error(f"Ana dongu hatasi: {e}", exc_info=False)

            elapsed = time.time() - t0
            time.sleep(max(0.05, 1.0 - elapsed))

    # ─── SPEED AGENT TICK ──────────────────────────────────

    def _tick_speed_agent(self, symbol: str):
        """
        SpeedAgent.tick_protect() — her tick pozisyon koruma.
        Peak drop, mum donus kapatma, acil DD.
        """
        state = self.executor.get_state(symbol)
        if not state or not state.positions:
            return

        # M15 verisi al
        m15 = self.bridge.get_ohlcv(symbol, cfg.PRIMARY_TF, 30)
        if m15 is None or len(m15) < 10:
            return

        # Sinyal sonucu (SignalEngine'den)
        sig = self.signals.get(symbol)
        if not sig:
            return

        # Hafif sinyal degerlendirmesi (sadece son veri icin)
        try:
            h1 = self.bridge.get_ohlcv(symbol, cfg.TREND_TF, 50)
            h4 = self.bridge.get_ohlcv(symbol, cfg.UPPER_TF, 30)
            if h1 is not None and len(h1) >= 20 and h4 is not None and len(h4) >= 10:
                signal_result = sig.evaluate(m15, h1, h4)
            else:
                signal_result = sig.evaluate(m15, m15, m15)
        except Exception:
            # Signal engine hatasi — minimal result olustur
            from signal_engine import SignalResult
            signal_result = SignalResult()

        atr = getattr(signal_result, "atr", 0.0)

        # Grid aktifse peak drop/mum donus GridManager'a delege edilir
        grid_active = self.grid_agent.should_delegate_peak_drop(symbol)

        # SpeedAgent kararlarini al
        decisions = self.speed_agent.tick_protect(
            symbol     = symbol,
            positions  = list(state.positions),
            m15_data   = m15,
            signal_result = signal_result,
            atr        = atr,
            grid_active = grid_active,
        )

        if decisions:
            with self._arbitrator_lock:
                self.arbitrator.submit(decisions)

            # Tick management (profit/peak guncelleme + acil DD)
            bar = m15.iloc[-2] if len(m15) >= 2 else m15.iloc[-1]
            body = bar['close'] - bar['open']
            tot = bar['high'] - bar['low']
            cdir = ("BUY" if body > 0 else "SELL") if (tot > 0 and abs(body) / tot > 0.3) else "NONE"
            logs = self.executor.tick_management(symbol, m15, None, cdir)
            for entry in logs:
                log.info(f"[TICK] {entry}")
                if any(w in entry for w in ["CLOSE", "PEAK", "CANDLE", "EMERGENCY"]):
                    self.telegram.notify(f">>> {entry}")
                    dash_state.add_log(entry, 'orange')
        else:
            # Decisions olmasa bile tick_management calistir (profit tracking)
            try:
                bar = m15.iloc[-2] if len(m15) >= 2 else m15.iloc[-1]
                body = bar['close'] - bar['open']
                tot = bar['high'] - bar['low']
                cdir = ("BUY" if body > 0 else "SELL") if (tot > 0 and abs(body) / tot > 0.3) else "NONE"
                self.executor.tick_management(symbol, m15, None, cdir)
            except Exception:
                pass

    # ─── FAST ENTRY TICK ───────────────────────────────────

    def _tick_fast_entry(self, symbol: str):
        """
        SpeedAgent hızlı giriş — Brain önbelleği ile <5ms.
        API çağrısı YOK. Önbellekli modda daha düşük eşik kullanır.
        """
        state = self.executor.get_state(symbol)
        # Zaten MAIN pozisyon varsa hizli giris yapma
        if state and state.main:
            return

        sig_engine = self.signals.get(symbol)
        if not sig_engine:
            return

        # Son sinyal sonucunu kullan
        signal_result = getattr(sig_engine, '_last_result', None)
        if signal_result is None:
            return

        # Brain önbelleğinden oku — API çağrısı YOK
        decision_cache = self.brain.decision_cache.get(symbol)

        decision = self.speed_agent.fast_entry_scan(symbol, signal_result, decision_cache)
        if decision:
            source = decision.metadata.get("source", "?")
            score  = decision.metadata.get("score", 0)
            log.info(
                f"[{symbol}] FAST_ENTRY [{source}]: skor={score} "
                f"önbellek={'VAR (yaş={:.0f}s)'.format(decision_cache.age) if decision_cache else 'YOK'}"
            )
            with self._arbitrator_lock:
                self.arbitrator.submit([decision])

            # Yüksek skor → arka planda tam Strategy güncellemesi tetikle
            if score >= cfg.FAST_ENTRY_THRESHOLD:
                self._push_event(StrategyEvent(
                    event_type=EventType.SIGNAL,
                    symbol=symbol,
                    data={"score": score, "direction": decision.metadata.get("direction", "")},
                ))

    # ─── GRID AGENT TICK ────────────────────────────────────

    def _tick_grid_agent(self, symbol: str):
        """
        GridAgent.tick() — her tick grid pipeline calistir.
        SPM/DCA/HEDGE acma, FIFO kapama, peak drop (profil-bazli).
        """
        if not self.grid_agent.is_active(symbol):
            return

        # MT5'den pozisyon verisi
        positions_raw = self.bridge.get_positions(symbol)
        if not positions_raw:
            return

        # Hesap bilgisi
        acc = self.bridge.get_account()

        # M15 mum yonu
        candle_dir = "NONE"
        try:
            m15 = self.bridge.get_ohlcv(symbol, cfg.PRIMARY_TF, 5)
            if m15 is not None and len(m15) >= 2:
                bar = m15.iloc[-2]
                body = bar['close'] - bar['open']
                tot = bar['high'] - bar['low']
                if tot > 0 and abs(body) / tot > 0.3:
                    candle_dir = "BUY" if body > 0 else "SELL"
        except Exception:
            pass

        # H1 veri (trend hesabi icin)
        h1_data = None
        try:
            h1 = self.bridge.get_ohlcv(symbol, cfg.TREND_TF, 60)
            if h1 is not None and len(h1) >= 20:
                h1_data = {
                    "closes": h1['close'].tolist(),
                    "highs": h1['high'].tolist(),
                    "lows": h1['low'].tolist(),
                }
        except Exception:
            pass

        # Sinyal skoru ve yonu
        signal_score = 0
        signal_dir = "NONE"
        sig_engine = self.signals.get(symbol)
        if sig_engine:
            last_result = getattr(sig_engine, '_last_result', None)
            if last_result:
                signal_score = getattr(last_result, 'score', 0)
                dir_val = getattr(last_result, 'direction', None)
                if dir_val:
                    dir_v = getattr(dir_val, 'value', 0)
                    signal_dir = "BUY" if dir_v == 1 else "SELL" if dir_v == 2 else "NONE"

        # Yeni bar kontrolu (basit: tick_count % 15*60 == 0 gibi degil, M15 bar degisimi)
        new_bar = False

        # Spread orani
        spread_ratio = 1.0
        try:
            tick_info = self.bridge.get_tick(symbol)
            if tick_info:
                spread_ratio = tick_info.get("spread_ratio", 1.0)
        except Exception:
            pass

        # Haber blogu
        news_blocked = self.news_manager.is_blocked(symbol)

        # Grid pipeline calistir
        decisions = self.grid_agent.tick(
            symbol=symbol,
            positions_raw=positions_raw,
            account=acc,
            candle_dir=candle_dir,
            h1_data=h1_data,
            signal_score=signal_score,
            signal_dir=signal_dir,
            new_bar=new_bar,
            spread_ratio=spread_ratio,
            news_blocked=news_blocked,
        )

        if decisions:
            with self._arbitrator_lock:
                self.arbitrator.submit(decisions)

    # ─── NEWS MANAGER TICK ───────────────────────────────────

    def _tick_news_manager(self, active: List[str]):
        """
        Haber yoneticisi — blok kontrolu ve grid genisletme.
        Haber blogu aktifse RISK_VETO gonder.
        """
        # Haber blok kontrolu
        now = time.time()
        for sym in active:
            if self.news_manager.is_blocked(sym):
                blocked_details = self.news_manager.get_active_blocks()
                reason = blocked_details.get(sym, "Haber blogu")
                with self._arbitrator_lock:
                    self.arbitrator.submit([AgentDecision(
                        agent_name="NewsManager",
                        action="RISK_VETO",
                        symbol=sym,
                        priority=85,
                        confidence=100.0,
                        reason=f"Haber blogu: {reason}",
                        urgency="NOW",
                        metadata={"veto_type": "news_block"},
                        timestamp=now,
                    )])

        # Uyari mesajlari (Telegram)
        alerts = self.news_manager.check_alerts()
        for alert_msg in alerts:
            self.telegram.notify(alert_msg)

    # ─── RISK AGENT TICK ───────────────────────────────────

    def _tick_risk_agent(self, active: List[str]):
        """
        RiskAgent.check_all() — kapsamli hesap risk kontrolu.
        Gunluk kayip, DD, korelasyon, margin, equity egrisi, ardisik kayip.
        """
        acc = self.bridge.get_account()
        balance = acc.get("balance", 0)
        equity = acc.get("equity", 0)

        # Equity gecmisini guncelle
        if equity > 0:
            self._equity_history.append(equity)
            # Fazla buyumesini engelle (son 200 deger)
            if len(self._equity_history) > 200:
                self._equity_history = self._equity_history[-200:]

        # Pozisyon dict'i hazirla
        positions_dict: Dict[str, list] = {}
        for sym in cfg.ALL_SYMBOLS:
            state = self.executor.get_state(sym)
            if state and state.positions:
                positions_dict[sym] = list(state.positions)

        # Aktif seans belirle
        session = self._get_current_session()

        # Risk kontrolu calistir
        decisions = self.risk_agent.check_all(
            account       = acc,
            positions     = positions_dict,
            session       = session,
            equity_history= self._equity_history,
            trade_history = self._trade_history,
        )

        if decisions:
            with self._arbitrator_lock:
                self.arbitrator.submit(decisions)

    # ─── ARBITRATOR TICK ───────────────────────────────────

    def _tick_arbitrator(self):
        """
        Arbitrator.process() — biriken kararlari isle.
        Sonuclari executor'a gonder.
        """
        with self._arbitrator_lock:
            resolved = self.arbitrator.process()

        if not resolved:
            return

        # Kararlari yurutme
        logs = self.executor.execute_agent_decisions(resolved)

        # Log + Telegram bildirimi
        acc = self.bridge.get_account()
        for entry in logs:
            if entry.startswith("OPEN"):
                self._handle_open_log(entry, resolved, acc)
            elif entry.startswith("CLOSE") or entry.startswith("PEAK_DROP"):
                self._handle_close_log(entry, acc)
            elif entry.startswith("EMERGENCY"):
                self.telegram.notify_emergency(entry)
            elif entry.startswith("FIFO"):
                parts = entry.split()
                sym = parts[1] if len(parts) > 1 else "?"
                try:
                    net = float(parts[-1].replace("$", "").replace("+", ""))
                except (ValueError, IndexError):
                    net = 0.0
                self.telegram.notify_fifo(sym, net)

        # Dashboard guncelle
        if logs:
            self._update_dashboard_after_execution(resolved)

    # ─── OLAY TETIKLEYICILERI ──────────────────────────────

    def _check_event_triggers(self, active: List[str]):
        """
        Seans degisimi ve spread normallesme olaylarini kontrol et.
        Strategy thread'e olay gonder.
        """
        # ── SEANS DEGISIMI KONTROLU ────────────────────────
        current_session = self._get_current_session()
        if current_session != self._last_session and self._last_session:
            log.info(f"[Olay] Seans degisimi: {self._last_session} -> {current_session}")
            self._push_event(StrategyEvent(
                event_type=EventType.SESSION_CHANGE,
                data={
                    "from_session": self._last_session,
                    "to_session": current_session,
                },
            ))
        self._last_session = current_session

        # ── SPREAD NORMALLESME KONTROLU ────────────────────
        for sym in active:
            try:
                tick_info = self.bridge.get_tick(sym)
                if tick_info is None:
                    continue
                spread_pts = tick_info.get("spread", 0)
                spec = cfg.SYMBOL_SPECS.get(sym, {})
                pip = spec.get("pip", 0.0001)
                # Spread yuksek mi kontrol et
                # Basit heuristik: spread > 5 pip ise yuksek
                spread_pips = spread_pts * (pip if pip > 0 else 0.0001)
                was_high = self._spread_high.get(sym, False)
                is_high = spread_pips > 5  # Basit esik

                if was_high and not is_high:
                    log.info(f"[Olay] {sym} spread normallesme")
                    self._push_event(StrategyEvent(
                        event_type=EventType.SPREAD_RECOVERED,
                        symbol=sym,
                        data={"spread_pips": spread_pips},
                    ))
                self._spread_high[sym] = is_high
            except Exception:
                pass

    # ═══════════════════════════════════════════════════════
    # STRATEGY THREAD (2-5dk + olay gudumlu)
    # ═══════════════════════════════════════════════════════

    def _strategy_thread_wrapper(self):
        self._thread_wrapper(
            "strategy",
            self._strategy_thread_loop,
            self._start_strategy_thread,
        )

    def _strategy_thread_loop(self):
        """
        Strategy thread ana dongusu.
        Hem zamanlayici hem olay tetikleyicileri ile calisir.

        Her aktif sembol icin:
          1. Teknik veri + snapshot al
          2. brain.decide_symbol() -> TradeDecision
          3. AgentDecision'a cevir
          4. Arbitrator'a gonder
        """
        last_timer = 0.0
        interval = cfg.STRATEGY_AGENT_INTERVAL  # 180s (3dk)

        while self.running:
            # Olay veya zamanlayici bekle
            triggered = self._event_signal.wait(timeout=5.0)

            if not self.running:
                break

            now = time.time()
            events = []

            # ── Olaylari topla ──────────────────────────────
            if triggered:
                self._event_signal.clear()
                with self._event_lock:
                    events = list(self._event_queue)
                    self._event_queue.clear()

            # ── Zamanlayici kontrolu ────────────────────────
            timer_fired = (now - last_timer) >= interval
            if timer_fired:
                events.append(StrategyEvent(event_type=EventType.TIMER))
                last_timer = now

            if not events:
                continue
            if self._paused:
                continue

            # ── Olaylari isle ──────────────────────────────
            for event in events:
                try:
                    self._run_strategy_cycle(event)
                except Exception as e:
                    log.error(f"[Strategy] Dongu hatasi: {e}", exc_info=True)

    def _run_strategy_cycle(self, event: StrategyEvent):
        """
        Tek bir strategy dongusunu calistir.
        Belirli bir sembol veya tum aktif semboller icin.
        """
        active = self._get_active()
        if not active:
            return

        trigger_name = event.event_type.name
        log.info(f"[Strategy] Dongu basliyor — tetik={trigger_name} sembol={event.symbol or 'HEPSI'}")

        # Hedef semboller
        if event.symbol and event.symbol in active:
            target_symbols = [event.symbol]
        else:
            target_symbols = active

        try:
            snapshot = self.intel.get_snapshot(target_symbols)
        except Exception as e:
            log.error(f"[Strategy] Snapshot alinamadi: {e}")
            return

        active_pos = self.executor.get_active_positions_dict()

        # Hesap ozeti
        acc = snapshot.account
        account_summary = (
            f"Bakiye: ${acc.balance:.2f} | Equity: ${acc.equity:.2f} | "
            f"DD: {acc.drawdown_pct:.1f}% | Gunluk: ${acc.daily_pnl:+.2f} | "
            f"Pozisyon: {acc.open_positions}"
        )

        # Master Agent konteksti
        master_ctx = self.brain.last_master_decision

        strategy_decisions: List[AgentDecision] = []

        for sym in target_symbols:
            tech = snapshot.technicals.get(sym)
            if not tech:
                continue

            # Blacklist kontrolu
            if sym in self.brain._blacklist and time.time() < self.brain._blacklist[sym]:
                log.debug(f"[Strategy] {sym} blacklist'te — atlaniyor")
                continue

            # Pozisyon metni
            pos_text = ""
            if sym in active_pos:
                pos_data = active_pos[sym]
                pos_lines = []
                for pos in pos_data.get("positions", []):
                    pos_lines.append(
                        f"#{pos['ticket']} {pos['role']} {pos['direction']} "
                        f"{pos['lot']}lot P&L=${pos['profit']:+.2f}"
                    )
                pos_text = "\n".join(pos_lines)

            # Rejim hesapla
            from brain import _detect_regime
            regime = _detect_regime(tech)

            # Sentiment skoru
            sentiment = getattr(snapshot.context, 'fear_greed_index', 50)
            sent_score = self.sentiment_agent.get_score(sym)
            if sent_score != 0:
                sentiment = int(50 + sent_score / 2)  # -100..+100 -> 0..100

            # Grid context (GridAgent'dan)
            grid_ctx = None
            if cfg.GRID_ENABLED:
                fifo = self.grid_agent.get_fifo_summary(sym)
                if fifo:
                    grid_ctx = {
                        "kasa": fifo.kasa,
                        "net": fifo.net,
                        "target": fifo.target,
                        "main_profit": fifo.main_profit,
                        "active_dir": fifo.active_grid_dir,
                        "vol_regime": fifo.vol_regime,
                        "spm_count": fifo.spm_count,
                        "hedge_count": fifo.hedge_count,
                        "dca_count": fifo.dca_count,
                        "total_positions": fifo.total_positions,
                        "total_pnl": fifo.total_pnl,
                    }

            # Strategy Agent cagir (API cagrisi — yavasi)
            td = self.brain.decide_symbol(
                symbol=sym,
                technical=tech,
                account_summary=account_summary,
                positions_text=pos_text,
                regime=regime,
                sentiment_score=sentiment,
                trigger=trigger_name,
                grid_context=grid_ctx,
            )

            if td:
                # ══ YÖN GUARD — EMA hizasına aykırı kararı engelle ══
                # Bu kontrol Brain'den bağımsız, her zaman çalışır.
                ema8  = tech.ema8
                ema21 = tech.ema21
                ema50 = tech.ema50
                bull_aligned = (ema8 > 0 and ema21 > 0 and ema50 > 0 and ema8 > ema21 > ema50)
                bear_aligned = (ema8 > 0 and ema21 > 0 and ema50 > 0 and ema8 < ema21 < ema50)

                if td.action == "OPEN_SELL" and bull_aligned:
                    log.warning(
                        f"[YÖN GUARD] {sym} SELL→HOLD engellendi! "
                        f"EMA YUKARI hizalı ({ema8:.5f}>{ema21:.5f}>{ema50:.5f}) "
                        f"— Dipten SELL açma yasak!"
                    )
                    td.action  = "HOLD"
                    td.urgency = "SKIP"
                elif td.action == "OPEN_BUY" and bear_aligned:
                    log.warning(
                        f"[YÖN GUARD] {sym} BUY→HOLD engellendi! "
                        f"EMA AŞAĞI hizalı ({ema8:.5f}<{ema21:.5f}<{ema50:.5f}) "
                        f"— Tepeden BUY açma yasak!"
                    )
                    td.action  = "HOLD"
                    td.urgency = "SKIP"
                # ══ YÖN GUARD SONU ══

            if td and td.action != "HOLD" and td.urgency != "SKIP":
                # TradeDecision -> AgentDecision donusumu
                agent_dec = self._trade_to_agent_decision(td, "StrategyAgent")
                strategy_decisions.append(agent_dec)

                log.info(
                    f"[Strategy] {sym} -> {td.action} lot={td.lot} "
                    f"conf={td.confidence}% | {td.reason[:60]}"
                )

        # Arbitrator'a gonder
        if strategy_decisions:
            with self._arbitrator_lock:
                self.arbitrator.submit(strategy_decisions)
            log.info(f"[Strategy] {len(strategy_decisions)} karar Arbitrator'a gonderildi")

        # Dashboard guncelle
        try:
            update_from_snapshot(snapshot, active_pos, active)
            if cfg.GRID_ENABLED:
                update_grid_state(self.grid_agent)
            if cfg.NEWS_ENABLED:
                update_news_state(self.news_manager)
            # v3.8.0: SafetyShield dashboard
            acc_dict = {"balance": snapshot.account.balance,
                        "equity": snapshot.account.equity,
                        "margin_level": snapshot.account.margin_level}
            update_safety_shield(self.grid_agent if cfg.GRID_ENABLED else None, acc_dict)
            self.chart_writer.write_from_snapshot(
                snapshot, active_pos, active,
                brain_session=None, bridge=self.bridge,
            )
        except Exception as e:
            log.debug(f"[Strategy] Dashboard guncelleme: {e}")

    # ═══════════════════════════════════════════════════════
    # MASTER THREAD (15-30dk periyodik)
    # ═══════════════════════════════════════════════════════

    def _master_thread_wrapper(self):
        self._thread_wrapper(
            "master",
            self._master_thread_loop,
            self._start_master_thread,
        )

    def _master_thread_loop(self):
        """
        Master thread ana dongusu.
        Her 15-30 dakikada:
          1. brain.decide_portfolio() -> MasterDecision
          2. executor.master_lot_multiplier guncelle
          3. Blacklist guncelle
          4. Override kararlari Arbitrator'a gonder
          5. Telegram: HIGH/CRITICAL risk bildirim
        """
        # Ilk cagri biraz beklesin (strategy thread'in oncelik almasi icin)
        time.sleep(30)

        interval = cfg.MASTER_AGENT_INTERVAL  # 900s (15dk)

        while self.running:
            try:
                if self._paused:
                    time.sleep(10)
                    continue

                active = self._get_active()
                if not active:
                    time.sleep(30)
                    continue

                log.info("[Master] Portfolio analizi basliyor...")

                # Snapshot al
                try:
                    snapshot = self.intel.get_snapshot(active)
                except Exception as e:
                    log.error(f"[Master] Snapshot alinamadi: {e}")
                    time.sleep(60)
                    continue

                active_pos = self.executor.get_active_positions_dict()

                # Grid state (portfolio seviyesi)
                grid_state = None
                if cfg.GRID_ENABLED:
                    grid_state = self.grid_agent.get_grid_state()

                # Master Agent cagir (Opus — yavas ama guclu)
                master = self.brain.decide_portfolio(
                    snapshot, active_pos, trigger="PERIODIC",
                    grid_state=grid_state,
                )

                if master:
                    self._apply_master_decision(master, snapshot, active_pos, active)

            except Exception as e:
                log.error(f"[Master] Dongu hatasi: {e}", exc_info=True)

            # Sonraki periyoda bekle
            for _ in range(int(interval)):
                if not self.running:
                    return
                time.sleep(1)

    def _apply_master_decision(self, master: MasterDecision,
                                snapshot, active_pos: dict,
                                active: List[str]):
        """Master kararini sisteme uygula."""
        # 1. Lot carpanini guncelle
        self.executor.set_master_lot_multiplier(master.lot_multiplier)

        # 2. Blacklist guncelle (brain icerisinde zaten yapiliyor)

        # 3. Override kararlari Arbitrator'a gonder
        if master.decisions:
            override_agent_decisions = []
            for td in master.decisions:
                ad = self._trade_to_agent_decision(td, "MasterAgent")
                ad.action = "MASTER_OVERRIDE"
                ad.priority = 80
                override_agent_decisions.append(ad)

            with self._arbitrator_lock:
                self.arbitrator.submit(override_agent_decisions)
            log.info(f"[Master] {len(override_agent_decisions)} override karar Arbitrator'a gonderildi")

        # 4. Telegram: HIGH/CRITICAL risk bildirim — DEVRE DISI (spam onleme)
        # Sadece log'a yaz, Telegram'a gonderme
        if master.global_risk in ("HIGH", "CRITICAL"):
            log.info(f"[Master] 🧠 {master.global_risk} {' '.join(master.focus_symbols)} | {master.market_read[:80]}")

        # 5. Dashboard guncelle
        try:
            update_from_snapshot(snapshot, active_pos, active)
            update_brain_decision(
                master.market_read, master.global_risk, master.focus_symbols
            )
            if cfg.GRID_ENABLED:
                update_grid_state(self.grid_agent)
            if cfg.NEWS_ENABLED:
                update_news_state(self.news_manager)
            # v3.8.0: SafetyShield
            acc_dict = {"balance": snapshot.account.balance,
                        "equity": snapshot.account.equity,
                        "margin_level": snapshot.account.margin_level}
            update_safety_shield(self.grid_agent if cfg.GRID_ENABLED else None, acc_dict)
        except Exception as e:
            log.debug(f"[Master] Dashboard guncelleme: {e}")

        log.info(
            f"[Master] Karar uygulanddi — risk={master.global_risk} "
            f"lot_x={master.lot_multiplier} strateji={master.session_strategy} "
            f"odak={master.focus_symbols}"
        )

    # ═══════════════════════════════════════════════════════
    # SENTIMENT THREAD (5dk periyodik)
    # ═══════════════════════════════════════════════════════

    def _sentiment_thread_wrapper(self):
        self._thread_wrapper(
            "sentiment",
            self._sentiment_thread_loop,
            self._start_sentiment_thread,
        )

    def _sentiment_thread_loop(self):
        """
        Sentiment thread ana dongusu.
        Her 5 dakikada:
          1. sentiment_engine.update() -> sembol skorlari
          2. SignalEngine'lere sentiment overlay ayarla
          3. SentimentAgent'a skorlari set et
          4. Dashboard durumunu guncelle
        """
        # Ilk cagri 10s sonra
        time.sleep(10)

        interval = cfg.SENTIMENT_INTERVAL  # 300s (5dk)

        while self.running:
            try:
                log.info("[Sentiment] Guncelleme basliyor...")

                # Sentiment Engine guncelle
                scores = self.sentiment_engine.update()

                # SignalEngine'lere sentiment overlay ayarla
                flat_scores = {}
                for sym, score_obj in scores.items():
                    value = getattr(score_obj, 'value', 0.0)
                    flat_scores[sym] = value

                for sym, sig_engine in self.signals.items():
                    if hasattr(sig_engine, 'set_sentiment'):
                        sig_engine.set_sentiment(flat_scores)

                # SentimentAgent'a set et
                self.sentiment_agent.set_scores(flat_scores)

                # Dashboard guncelle
                try:
                    summary = self.sentiment_engine.format_summary()
                    dash_state.add_log(f"Sentiment guncellendi", 'blue')
                except Exception:
                    pass

                log.info(
                    f"[Sentiment] {len(scores)} sembol guncellendi | "
                    + " | ".join(f"{s}={getattr(sc, 'value', 0):+.0f}" for s, sc in list(scores.items())[:5])
                )

            except Exception as e:
                log.error(f"[Sentiment] Guncelleme hatasi: {e}", exc_info=True)

            # Sonraki periyoda bekle
            for _ in range(int(interval)):
                if not self.running:
                    return
                time.sleep(1)

    # ═══════════════════════════════════════════════════════
    # OLAY KUYRUGU YONETIMI
    # ═══════════════════════════════════════════════════════

    def _push_event(self, event: StrategyEvent):
        """Strategy thread'e olay gonder (thread-safe)."""
        with self._event_lock:
            # Ayni tipte bekleyen olay varsa ekleme (flood koruma)
            exists = any(
                e.event_type == event.event_type and e.symbol == event.symbol
                for e in self._event_queue
            )
            if not exists:
                self._event_queue.append(event)
        self._event_signal.set()

    # ═══════════════════════════════════════════════════════
    # TELEGRAM CALLBACK'LER
    # ═══════════════════════════════════════════════════════

    def _wire_telegram(self):
        """Telegram komut callback'lerini bagla."""
        t = self.telegram

        # Mevcut komutlar
        t.on_activate        = self._cmd_activate
        t.on_deactivate      = self._cmd_deactivate
        t.on_close           = self._cmd_close_symbols
        t.on_close_all       = self._cmd_close_all
        t.on_stop_all        = self._cmd_stop_all
        t.on_brain_now       = self._cmd_brain_now
        t.get_status         = self._build_status_msg
        t.get_report         = self._build_report_msg
        t.get_active_symbols = lambda: list(self._active_symbols)

        # Yeni komutlar (v4.0) — eger telegram_commander destekliyorsa
        if hasattr(t, 'on_regime'):
            t.on_regime      = self._cmd_regime
        if hasattr(t, 'on_sentiment'):
            t.on_sentiment   = self._cmd_sentiment
        if hasattr(t, 'on_agents'):
            t.on_agents      = self._cmd_agents
        if hasattr(t, 'on_pause'):
            t.on_pause       = self._cmd_pause
        if hasattr(t, 'on_resume'):
            t.on_resume      = self._cmd_resume

        # v5.0 — Grid/News komutlari
        if hasattr(t, 'get_grid_status'):
            t.get_grid_status = self._build_grid_msg
        if hasattr(t, 'get_kasa'):
            t.get_kasa        = self._build_kasa_msg
        if hasattr(t, 'get_news_status'):
            t.get_news_status = self._build_news_msg

    def _cmd_activate(self, symbols: List[str]):
        """Sembolleri aktive et."""
        added = []
        with self._lock:
            for s in symbols:
                if s in cfg.ALL_SYMBOLS:
                    self._active_symbols.add(s)
                    added.append(s)
        if added:
            # GridAgent'i da aktive et
            if cfg.GRID_ENABLED:
                for s in added:
                    self.grid_agent.activate(s)
            log.info(f"[TG] Aktive: {added}")
            # Strategy thread'i tetikle
            self._push_event(StrategyEvent(
                event_type=EventType.MANUAL,
                data={"added_symbols": added},
            ))

    def _cmd_deactivate(self, symbols: List[str]):
        """Sembolleri durdur (pozisyonlar korunur)."""
        with self._lock:
            for s in symbols:
                self._active_symbols.discard(s)
                self.grid_agent.deactivate(s)
                try:
                    mt5_sym = self.bridge._sym(s) if hasattr(self.bridge, '_sym') else s
                    self.chart_writer.clear_symbol(s, mt5_sym)
                except Exception:
                    pass
        log.info(f"[TG] Durduruldu: {symbols}")

    def _cmd_close_symbols(self, symbols: List[str]):
        """Belirli sembollerin pozisyonlarini kapat."""
        def _do():
            for sym in symbols:
                state = self.executor.get_state(sym)
                if state and state.positions:
                    pnl = state.total_pnl
                    self.bridge.close_all_symbol(sym, "TG_Kapat")
                    state.positions.clear()
                    state.kasa = 0.0
                    self.brain.record_trade_result(sym, pnl, pnl > 0)
                    self._record_trade_history(sym, pnl, pnl > 0)
                    self.telegram.notify_trade_close(sym, "HEPSI", pnl, "Telegram komutu")
                    log.info(f"[TG] {sym} kapatildi P&L=${pnl:+.2f}")
                else:
                    self.telegram.notify(f">> {sym}'de acik pozisyon yok")
        threading.Thread(target=_do, daemon=True).start()

    def _cmd_close_all(self):
        """Tum pozisyonlari kapat."""
        def _do():
            total = 0.0
            count = 0
            for sym in cfg.ALL_SYMBOLS:
                state = self.executor.get_state(sym)
                if state and state.positions:
                    pnl = state.total_pnl
                    self.bridge.close_all_symbol(sym, "TG_TumKapat")
                    state.positions.clear()
                    state.kasa = 0.0
                    total += pnl
                    count += 1
            msg = (
                f"*Tum pozisyonlar kapatildi*\n{count} sembol | ${total:+.2f}"
                if count else "Acik pozisyon yok"
            )
            self.telegram.notify(msg)
            log.info(f"[TG] TUM KAPANDI | ${total:+.2f}")
        threading.Thread(target=_do, daemon=True).start()

    def _cmd_stop_all(self):
        """Tum sembolleri durdur."""
        with self._lock:
            self._active_symbols.clear()
        log.info("[TG] Tum semboller durduruldu")

    def _cmd_brain_now(self):
        """Brain'i manuel tetikle."""
        log.info("[TG] Brain manuel tetiklendi")
        self._push_event(StrategyEvent(event_type=EventType.MANUAL))

    def _cmd_pause(self):
        """Tum islemleri duraklat (risk override)."""
        self._paused = True
        log.warning("[TG] ISLEMLER DURAKLATILDI — /resume ile devam")
        self.telegram.notify("*ISLEMLER DURAKLATILDI*\nYeniden baslatmak icin /resume")

    def _cmd_resume(self):
        """Islemlere devam et."""
        self._paused = False
        log.info("[TG] Islemler yeniden baslatildi")
        self.telegram.notify("*ISLEMLER YENIDEN BASLATILDI*")
        # Strategy thread'i tetikle
        self._push_event(StrategyEvent(event_type=EventType.MANUAL))

    def _cmd_regime(self) -> str:
        """Piyasa rejimi bilgisi — /regime komutu."""
        try:
            lines = ["*Piyasa Rejimleri*\n"]
            active = self._get_active() or cfg.ALL_SYMBOLS
            for sym in active:
                sig_engine = self.signals.get(sym)
                if sig_engine:
                    last_result = getattr(sig_engine, '_last_result', None)
                    if last_result:
                        regime = getattr(last_result, 'regime', 'N/A')
                        regime_name = regime.value if hasattr(regime, 'value') else str(regime)
                        adx = getattr(last_result, 'adx', 0)
                        atr_pct = getattr(last_result, 'atr_percentile', 0)
                        lines.append(f"*{sym}*: {regime_name} | ADX={adx:.0f} | ATR%={atr_pct:.0f}")
                    else:
                        lines.append(f"*{sym}*: Henuz veri yok")
            return "\n".join(lines)
        except Exception as e:
            return f"Rejim bilgisi alinamadi: {e}"

    def _cmd_sentiment(self) -> str:
        """Sentiment skorlari — /sentiment komutu."""
        try:
            if self.sentiment_engine:
                return self.sentiment_engine.format_summary()
            return "Sentiment henuz hesaplanmadi"
        except Exception as e:
            return f"Sentiment bilgisi alinamadi: {e}"

    def _cmd_agents(self) -> str:
        """Ajan durumlari — /ajanlar komutu."""
        try:
            lines = ["*Ajan Durumlari*\n"]

            # SpeedAgent
            lines.append("*SpeedAgent*: Aktif (her tick)")

            # RiskAgent
            lines.append("*RiskAgent*: Aktif (her tick)")

            # Strategy Agent
            st_stats = self.brain.strategy_agent.get_stats()
            lines.append(
                f"*StrategyAgent*: {st_stats['calls']} cagri | "
                f"{st_stats['errors']} hata | Model: {st_stats['model']}"
            )

            # Master Agent
            m_stats = self.brain.master_agent.get_stats()
            lines.append(
                f"*MasterAgent*: {m_stats['calls']} cagri | "
                f"{m_stats['errors']} hata | "
                f"Risk: {m_stats['last_risk']} | "
                f"Strateji: {m_stats['last_strategy']}"
            )

            # Grid Agent
            ga = self.grid_agent
            ga_syms = list(ga.active_symbols)
            ga_kasa = ga.get_total_kasa()
            lines.append(
                f"*GridAgent*: {len(ga_syms)} sembol aktif | "
                f"Kasa: ${ga_kasa:.2f} | Grid={'ON' if cfg.GRID_ENABLED else 'OFF'}"
            )

            # News Manager
            upcoming = self.news_manager.get_all_upcoming(60)
            lines.append(f"*NewsManager*: {len(upcoming)} haber (60dk) | News={'ON' if cfg.NEWS_ENABLED else 'OFF'}")

            # Sentiment Agent
            stale = "Guncel" if not self.sentiment_agent.is_stale else "Eski"
            lines.append(f"*SentimentAgent*: {stale}")

            # Arbitrator
            lines.append(f"*Arbitrator*: Bekleyen={self.arbitrator.pending_count}")

            # Paused durumu
            if self._paused:
                lines.append("\n*DURUM: DURAKLATILDI*")
            else:
                lines.append(f"\n*Aktif semboller:* {', '.join(self._get_active()) or 'YOK'}")

            # Thread retry bilgisi
            for name, count in self._thread_retries.items():
                if count > 0:
                    lines.append(f"[!] {name} thread: {count} yeniden baslama")

            return "\n".join(lines)
        except Exception as e:
            return f"Ajan bilgisi alinamadi: {e}"

    # ═══════════════════════════════════════════════════════
    # DURUM MESAJLARI
    # ═══════════════════════════════════════════════════════

    def _build_status_msg(self) -> str:
        """Telegram /durum komutu icin durum mesaji."""
        try:
            acc = self.bridge.get_account()
            b  = acc.get("balance", 0)
            e  = acc.get("equity", 0)
            p  = acc.get("profit", 0)
            ml = acc.get("margin_level", 0)
            dd = max(0, (b - e) / (b + 1e-9) * 100)

            lines = [
                "*MIA v6.2.0 Durum*",
                f"Hesap: #{cfg.MT5_LOGIN}",
                f"Bakiye: ${b:.2f} | Equity: ${e:.2f}",
                f"Float P&L: ${p:+.2f} | DD: {dd:.1f}% | Margin: {ml:.0f}%",
                f"Aktif: {', '.join(self._active_symbols) or 'YOK'}",
                f"Duraklatildi: {'EVET' if self._paused else 'HAYIR'}",
            ]

            # Master ajan durumu
            master = self.brain.last_master_decision
            if master:
                lines.append(
                    f"Risk: {master.global_risk} | Lot: {master.lot_multiplier}x | "
                    f"Strateji: {master.session_strategy}"
                )

            pos_count = 0
            for sym in cfg.ALL_SYMBOLS:
                state = self.executor.get_state(sym) if self.executor else None
                if state and state.positions:
                    pos_count += len(state.positions)
                    lines.append(f"\n*{sym}* kasa=${state.kasa:.2f}")
                    for pos in state.positions:
                        lines.append(
                            f"  {pos.role} {pos.direction} {pos.lot}lot -> ${pos.profit:+.2f}"
                        )

            if pos_count == 0:
                lines.append("\n_Acik pozisyon yok_")

            if self.brain:
                st = self.brain.get_stats()
                lines.append(
                    f"\nBrain: {st['api_calls']} cagri | {st['win_rate']} WR | {st['total_pnl']}"
                )

            uptime_min = (time.time() - self.start_time) / 60
            lines.append(f"Tick: {self.tick_count} | Uptime: {uptime_min:.0f}dk")

            return "\n".join(lines)
        except Exception as e:
            return f"Durum alinamadi: {e}"

    def _build_report_msg(self) -> str:
        """Telegram /rapor komutu icin performans raporu."""
        try:
            lines = ["*MIA v4.0 Performans Raporu*\n"]
            total_pnl = 0.0
            tw = 0
            tl = 0
            for sym, perf in self.brain._performance.items():
                w = perf.get("wins", 0)
                l = perf.get("losses", 0)
                pnl = perf.get("total_pnl", 0)
                total_pnl += pnl
                tw += w
                tl += l
                wr = w / (w + l) * 100 if (w + l) > 0 else 0
                lines.append(f"*{sym}*: {w}W/{l}L ({wr:.0f}%) ${pnl:+.2f}")

            lines.append(f"\n*TOPLAM*: {tw}W/{tl}L ${total_pnl:+.2f}")

            if self.brain._blacklist:
                lines.append(f"Blacklist: {list(self.brain._blacklist.keys())}")

            # Ajan istatistikleri
            lines.append("\n*Ajan Istatistikleri:*")
            st = self.brain.strategy_agent.get_stats()
            mt = self.brain.master_agent.get_stats()
            lines.append(f"Strategy: {st['calls']} cagri ({st['errors']} hata)")
            lines.append(f"Master: {mt['calls']} cagri ({mt['errors']} hata)")

            return "\n".join(lines)
        except Exception as e:
            return f"Rapor: {e}"

    def _build_grid_msg(self) -> str:
        """Telegram /grid komutu icin grid/FIFO durumu."""
        try:
            if not cfg.GRID_ENABLED:
                return "Grid sistemi devre disi."
            ga = self.grid_agent
            summaries = ga.get_all_summaries()
            if not summaries:
                return "Grid aktif sembol yok."
            lines = []
            total_kasa = 0.0
            total_pos = 0
            for sym, fs in summaries.items():
                sym_s = sym.replace("USD", "").replace("USDJPY", "JPY")
                total_kasa += fs.kasa
                total_pos += fs.total_positions
                dir_s = fs.active_grid_dir or "—"
                lines.append(
                    f"*{sym_s}*: {dir_s} | Poz: {fs.total_positions} "
                    f"(M+{fs.spm_count}SPM+{fs.hedge_count}H+{fs.dca_count}D)\n"
                    f"  Kasa: `${fs.kasa:.2f}` | Net: `${fs.net:.2f}` | "
                    f"Hedef: `${fs.target:.2f}`\n"
                    f"  PnL: `${fs.total_pnl:+.2f}` | Rejim: {fs.vol_regime}"
                )
            lines.append(f"\n*TOPLAM*: {total_pos} poz | Kasa: `${total_kasa:.2f}`")
            return "\n".join(lines)
        except Exception as e:
            return f"Grid durumu alinamadi: {e}"

    def _build_kasa_msg(self) -> str:
        """Telegram /kasa komutu icin kasa bilgisi."""
        try:
            if not cfg.GRID_ENABLED:
                return "Grid sistemi devre disi."
            ga = self.grid_agent
            summaries = ga.get_all_summaries()
            total_kasa = ga.get_total_kasa()
            lines = [f"Toplam Kasa: `${total_kasa:.2f}`\n"]
            for sym, fs in summaries.items():
                sym_s = sym.replace("USD", "").replace("USDJPY", "JPY")
                if fs.kasa > 0 or fs.spm_open_profit > 0:
                    lines.append(
                        f"*{sym_s}*: Kasa=`${fs.kasa:.2f}` | "
                        f"SPM Acik=`${fs.spm_open_profit:+.2f}` | "
                        f"Net=`${fs.net:.2f}`"
                    )
            if len(lines) == 1:
                lines.append("_Henuz kasa birikimi yok_")
            return "\n".join(lines)
        except Exception as e:
            return f"Kasa bilgisi alinamadi: {e}"

    def _build_news_msg(self) -> str:
        """Telegram /haber komutu icin haber durumu."""
        try:
            if not cfg.NEWS_ENABLED:
                return "Haber yoneticisi devre disi."
            nm = self.news_manager
            blocked = nm.get_active_blocks()
            upcoming = nm.get_all_upcoming(60)
            lines = []
            if blocked:
                lines.append("*Aktif Bloklar:*")
                for sym, title in blocked.items():
                    sym_s = sym.replace("USD", "").replace("USDJPY", "JPY")
                    lines.append(f"  🔴 `{sym_s}` — {title}")
            else:
                lines.append("_Aktif haber bloku yok_")
            if upcoming:
                lines.append(f"\n*Yaklasan ({len(upcoming)} haber):*")
                for ev in upcoming[:8]:
                    mins = int(ev.minutes_until) if hasattr(ev, 'minutes_until') else 0
                    impact = getattr(ev, 'impact', '?')
                    title = getattr(ev, 'title', '?')
                    currency = getattr(ev, 'currency', '?')
                    emoji = "🔴" if impact == "CRITICAL" else "🟠" if impact == "HIGH" else "🟡"
                    lines.append(f"  {emoji} {currency} {title} ({mins}dk)")
            else:
                lines.append("\n_60dk icinde haber yok_")
            return "\n".join(lines)
        except Exception as e:
            return f"Haber bilgisi alinamadi: {e}"

    # ═══════════════════════════════════════════════════════
    # YARDIMCI METODLAR
    # ═══════════════════════════════════════════════════════

    def _get_active(self) -> List[str]:
        """Thread-safe aktif sembol listesi."""
        with self._lock:
            return list(self._active_symbols)

    def _get_current_session(self) -> str:
        """GMT saatine gore aktif seansi belirle."""
        try:
            from datetime import datetime, timezone
            now_utc = datetime.now(timezone.utc)
            hour = now_utc.hour

            # Seans saatleri (GMT)
            if 0 <= hour < 6:
                return "TOKYO"
            elif 6 <= hour < 7:
                return "TOKYO_LONDON_OVERLAP"
            elif 7 <= hour < 12:
                return "LONDON"
            elif 12 <= hour < 16:
                return "LONDON_NY_OVERLAP"
            elif 16 <= hour < 21:
                return "NEW_YORK"
            else:
                return "OFF_HOURS"
        except Exception:
            return "LONDON"

    def _trade_to_agent_decision(self, td, agent_name: str) -> AgentDecision:
        """TradeDecision -> AgentDecision donusumu."""
        # Action mapping
        action = td.action
        if action == "OPEN_BUY":
            mapped_action = "STRATEGY_OPEN"
            direction = "BUY"
        elif action == "OPEN_SELL":
            mapped_action = "STRATEGY_OPEN"
            direction = "SELL"
        elif action == "CLOSE":
            mapped_action = "STRATEGY_CLOSE"
            direction = ""
        elif action == "PARTIAL_CLOSE":
            mapped_action = "PARTIAL_CLOSE"
            direction = ""
        else:
            mapped_action = action
            direction = ""

        return AgentDecision(
            agent_name = agent_name,
            action     = mapped_action,
            symbol     = td.symbol,
            priority   = 50 if "OPEN" in action else 70,
            confidence = float(td.confidence),
            lot        = td.lot,
            reason     = td.reason,
            urgency    = td.urgency,
            metadata   = {
                "direction":    direction,
                "risk_reward":  td.risk_reward,
                "risk_pct":     td.risk_pct,
                "open_spm":     td.open_spm,
                "spm_dir":      td.spm_dir,
                "spm_lot":      td.spm_lot,
                "fifo_action":  td.fifo_action,
                "session":      self._get_current_session(),
            },
        )

    def _record_trade_history(self, symbol: str, pnl: float, won: bool):
        """Islem gecmisini kaydet (RiskAgent icin)."""
        self._trade_history.append({
            "symbol": symbol,
            "pnl":    pnl,
            "won":    won,
            "ts":     time.time(),
        })
        # Fazla buyumesini engelle
        if len(self._trade_history) > 100:
            self._trade_history = self._trade_history[-100:]

    def _handle_open_log(self, entry: str, resolved: List[AgentDecision],
                          acc: dict):
        """OPEN log satirini isle — Telegram bildirim gonder."""
        parts = entry.split()
        sym = parts[1] if len(parts) > 1 else "?"
        d   = parts[2] if len(parts) > 2 else "?"
        try:
            lot = float(parts[3].replace("lot", "")) if len(parts) > 3 else 0
        except (ValueError, IndexError):
            lot = 0

        price = self.bridge.get_current_price(sym)
        active_pos = self.executor.get_active_positions_dict()
        sym_pos = active_pos.get(sym, {})
        spm_c = sum(1 for p in sym_pos.get("positions", []) if "SPM" in str(p.get("role", "")))
        kasa = sym_pos.get("kasa", 0)

        # AI skor — resolved'dan al
        ai_score = 0
        for rd in resolved:
            if rd.symbol == sym:
                ai_score = rd.confidence
                break

        extra = {
            "balance":     acc.get("balance", 0),
            "equity":      acc.get("equity", 0),
            "free_margin": acc.get("margin_free", 0),
            "positions":   acc.get("open_positions", 0),
            "ai_score":    ai_score,
            "session":     self._get_current_session(),
            "spm_count":   spm_c,
            "hedge_count": 0,
            "kasa":        kasa,
            "fifo_net":    kasa,
            "all_systems": {"all": True, "ai": True, "news": True, "hybrid": True, "spm": True},
        }
        self.telegram.notify_trade_open(sym, d, lot, price or 0, "", extra=extra)

    def _handle_close_log(self, entry: str, acc: dict):
        """CLOSE log satirini isle — Telegram bildirim gonder."""
        parts = entry.split()
        sym  = parts[1] if len(parts) > 1 else "?"
        role = parts[2] if len(parts) > 2 else "?"
        try:
            pnl = float(parts[-1].replace("$", "").replace("+", "").replace("(", "").replace(")", ""))
        except (ValueError, IndexError):
            pnl = 0.0

        # Ticket'i log'dan cikart (#XXXXXXX)
        ticket = 0
        for p in parts:
            if p.startswith("#") and p[1:].isdigit():
                ticket = int(p[1:])
                break

        self._record_trade_history(sym, pnl, pnl > 0)

        # Executor'dan kapanan pozisyon detaylarini al
        closed_list = self.executor.pop_closed_positions()
        # Dashboard'a kapanan islemleri kaydet
        if closed_list:
            dash_state.record_closed_trades(closed_list)
        closed_info = None
        for ci in closed_list:
            if ci.get("ticket") == ticket or ci.get("symbol") == sym:
                closed_info = ci
                break

        extra = {
            "balance":     acc.get("balance", 0),
            "daily_pnl":   acc.get("profit", 0),
        }
        if closed_info:
            extra.update({
                "lot":         closed_info.get("lot", 0),
                "ticket":      closed_info.get("ticket", 0),
                "direction":   closed_info.get("direction", ""),
                "open_price":  closed_info.get("open_price", 0),
                "close_price": closed_info.get("close_price", 0),
            })

        self.telegram.notify_trade_close(sym, role, pnl, "", extra=extra)

    def _update_dashboard_after_execution(self, resolved: List[AgentDecision]):
        """Arbitrator yurutmesinden sonra dashboard guncelle."""
        try:
            active = self._get_active()
            active_pos = self.executor.get_active_positions_dict()
            snapshot = self.intel.get_snapshot(active or cfg.ALL_SYMBOLS[:3])
            update_from_snapshot(snapshot, active_pos, active or [])

            # Grid/News state guncelle
            if cfg.GRID_ENABLED:
                update_grid_state(self.grid_agent)
            if cfg.NEWS_ENABLED:
                update_news_state(self.news_manager)
            # v3.8.0: SafetyShield
            acc = snapshot.account
            update_safety_shield(
                self.grid_agent if cfg.GRID_ENABLED else None,
                {"balance": acc.balance, "equity": acc.equity, "margin_level": acc.margin_level}
            )

            # Kararlari dashboard loguna ekle
            for d in resolved[:5]:
                color = 'green' if 'OPEN' in d.action else 'red' if 'CLOSE' in d.action else 'blue'
                dash_state.add_log(
                    f"{d.action} {d.symbol} c={d.confidence:.0f}% {d.reason[:40]}",
                    color,
                )

            # Chart writer
            self.chart_writer.write_from_snapshot(
                snapshot, active_pos, active or [],
                brain_session=None, bridge=self.bridge,
            )
        except Exception as e:
            log.debug(f"Dashboard guncelleme: {e}")

    def _tick_dashboard(self):
        """
        Dashboard'u her tick'te (1s) canli guncelle.
        MT5'den hesap + pozisyon verisi cekip dash_state'e yazar.
        """
        import MetaTrader5 as mt5

        # 1. Hesap verisi — her tick
        info = mt5.account_info()
        if not info:
            return
        b = info.balance
        e = info.equity
        p = info.profit
        ml = info.margin_level if info.margin_level else 0
        m = info.margin
        lev = info.leverage
        dd = max(0, (b - e) / (b + 1e-9) * 100) if b > 0 else 0

        # daily_pnl = realized (kapanan) + floating (acik) — gercek gunluk toplam
        realized = dash_state._trade_stats.get("total_realized", 0.0)
        daily_total = realized + p

        dash_state.update("account", {
            "balance": round(b, 2),
            "equity": round(e, 2),
            "margin": round(m, 2),
            "margin_level": round(ml, 1),
            "daily_pnl": round(daily_total, 2),
            "floating_pnl": round(p, 2),
            "drawdown_pct": round(dd, 2),
            "open_positions": mt5.positions_total(),
            "leverage": lev,
        })

        # 2. Pozisyon verisi — her tick (canli P&L)
        all_pos = mt5.positions_get()
        if all_pos is None:
            all_pos = ()

        # MT5 sembol → internal sembol cevirme (bridge'den)
        reverse_map = {}
        if hasattr(self, 'bridge') and hasattr(self.bridge, '_sym_map'):
            for base, mt5name in self.bridge._sym_map.items():
                reverse_map[mt5name] = base

        pos_dict = {}
        for pos in all_pos:
            # Oncelikle bridge map'den cevir, yoksa suffix kaldir
            sym_raw = reverse_map.get(pos.symbol, pos.symbol.rstrip('m').rstrip('M').replace('.', ''))
            # Executor state'den role/peak bilgisi al
            ex_state = self.executor.get_state(sym_raw) if hasattr(self, 'executor') else None
            ex_pos = None
            role = "MAIN"
            peak = max(0, pos.profit)
            if ex_state:
                ex_pos = next((p for p in ex_state.positions if p.ticket == pos.ticket), None)
                if ex_pos:
                    role = ex_pos.role
                    peak = ex_pos.peak_profit

            sym_key = sym_raw
            if sym_key not in pos_dict:
                pos_dict[sym_key] = {"symbol": sym_key, "positions": []}
            pos_dict[sym_key]["positions"].append({
                "ticket": pos.ticket,
                "role": role,
                "direction": "BUY" if pos.type == 0 else "SELL",
                "lot": pos.volume,
                "open_price": pos.price_open,
                "open_time": int(pos.time),
                "profit": round(pos.profit, 2),
                "peak_profit": round(peak, 2),
                "swap": round(pos.swap, 2),
                "comment": pos.comment or "",
            })

        dash_state.update("positions", pos_dict)

        # 3. Canli fiyat + spread guncelleme — sidebar sembolleri anlik degissin
        #    Lock DISINDA MT5 tick verisi topla, sonra lock ICINDE hizlica yaz
        if hasattr(self, 'bridge') and hasattr(self.bridge, '_sym_map'):
            price_updates = {}
            for base, mt5name in self.bridge._sym_map.items():
                tick = mt5.symbol_info_tick(mt5name)
                if tick and tick.bid > 0:
                    mid = (tick.bid + tick.ask) / 2
                    price_updates[base] = {
                        "price": round(mid, 2 if tick.bid > 100 else (3 if tick.bid > 10 else 5)),
                        "spread_pts": round((tick.ask - tick.bid) / mt5.symbol_info(mt5name).point, 1) if mt5.symbol_info(mt5name) else 0,
                    }
            if price_updates:
                with dash_state._lock:
                    if "technicals" not in dash_state._state:
                        dash_state._state["technicals"] = {}
                    tech = dash_state._state["technicals"]
                    for base, data in price_updates.items():
                        if base not in tech:
                            tech[base] = {}
                        tech[base]["price"] = data["price"]
                        tech[base]["spread_pts"] = data["spread_pts"]

        # 4. Win Rate + Trade Stats — MT5 deal history (her 5 saniyede bir)
        if not hasattr(self, '_wr_last_update'):
            self._wr_last_update = 0
            self._wr_last_count = -1  # Degisiklik tespiti icin
        now = time.time()
        if now - self._wr_last_update >= 5:
            self._wr_last_update = now
            try:
                from datetime import datetime as _dt
                today_start = _dt.now().replace(hour=0, minute=0, second=0, microsecond=0)
                deals = mt5.history_deals_get(today_start, _dt.now())
                if deals is not None:
                    wins = 0
                    losses = 0
                    total_realized = 0.0
                    closed_trades = []
                    for d in deals:
                        if d.entry in (1, 2) and d.profit != 0:
                            pnl = d.profit + d.swap + d.commission
                            if pnl > 0:
                                wins += 1
                            elif pnl < 0:
                                losses += 1
                            total_realized += pnl
                            closed_trades.append({
                                "symbol": d.symbol,
                                "pnl": round(pnl, 2),
                                "closed_at": _dt.fromtimestamp(d.time).strftime("%H:%M:%S"),
                                "direction": "BUY" if d.type == 0 else "SELL",
                                "lot": d.volume,
                                "role": "MAIN",
                                "ticket": d.ticket,
                            })
                    total = wins + losses
                    wr = (wins / total * 100) if total > 0 else 0
                    with dash_state._lock:
                        dash_state._trade_stats["wins"] = wins
                        dash_state._trade_stats["losses"] = losses
                        dash_state._trade_stats["total_realized"] = total_realized
                        dash_state._state["trade_stats"] = {
                            "wins": wins,
                            "losses": losses,
                            "total_realized": round(total_realized, 2),
                            "win_rate": round(wr, 1),
                        }
                        if closed_trades:
                            dash_state._state["trade_history"] = closed_trades[-50:]
                        # daily_pnl = realized + floating (gercek gunluk P&L)
                        floating = dash_state._state.get("account", {}).get("floating_pnl", 0)
                        dash_state._state["account"]["daily_pnl"] = round(total_realized + floating, 2)
                    # Degisiklik oldugunda logla
                    if total != self._wr_last_count:
                        log.info(f"[WinRate] Guncellendi: W={wins} L={losses} WR={wr:.1f}% Realized=${total_realized:.2f} Deals={len(deals)}")
                        self._wr_last_count = total
                else:
                    log.debug("[WinRate] MT5 history_deals_get None dondu")
            except Exception as e:
                log.warning(f"[WinRate] Hesaplama hatasi: {e}", exc_info=True)

    def _log_status(self):
        """Periyodik durum logu (30 saniyede bir)."""
        try:
            acc = self.bridge.get_account()
            b  = acc.get("balance", 0)
            e  = acc.get("equity", 0)
            p  = acc.get("profit", 0)
            m  = acc.get("margin", 0)
            ml = acc.get("margin_level", 0)
            lev = acc.get("leverage", 0)
            dd = max(0, (b - e) / (b + 1e-9) * 100)
            up = (time.time() - self.start_time) / 60

            master = self.brain.last_master_decision
            risk = master.global_risk if master else "N/A"
            lot_x = master.lot_multiplier if master else 1.0

            # Acik pozisyon sayisini MT5'den al
            import MetaTrader5 as mt5
            all_pos = mt5.positions_get() or []
            open_count = len(all_pos)

            # Dashboard hesap verisini her zaman guncelle (aktif sembol olmasa bile)
            dash_state.update("account", {
                "balance": b, "equity": e, "margin": m,
                "margin_level": ml, "daily_pnl": p, "floating_pnl": p,
                "drawdown_pct": round(dd, 2), "open_positions": open_count,
                "leverage": lev,
            })

            # Eger executor'da pozisyon yoksa ama MT5'de varsa, positions dict'i de guncelle
            if open_count > 0 and not any(self.executor.get_state(s) and self.executor.get_state(s).positions for s in cfg.ALL_SYMBOLS):
                pos_dict = {}
                for pos in all_pos:
                    sym = pos.symbol.replace('.','')
                    if sym not in pos_dict:
                        pos_dict[sym] = {"symbol": sym, "positions": []}
                    pos_dict[sym]["positions"].append({
                        "ticket": pos.ticket,
                        "role": "MAIN",
                        "direction": "BUY" if pos.type == 0 else "SELL",
                        "lot": pos.volume,
                        "open_price": pos.price_open,
                        "profit": pos.profit,
                        "peak_profit": max(0, pos.profit),
                    })
                dash_state.update("positions", pos_dict)

            log.info(
                f"[${b:.2f} eq${e:.2f} p{p:+.2f} dd{dd:.1f}% "
                f"risk={risk} lot_x={lot_x:.1f} "
                f"{up:.0f}m t={self.tick_count} "
                f"aktif:{list(self._active_symbols)} "
                f"{'PAUSED' if self._paused else 'RUNNING'}]"
            )
        except Exception:
            pass

    def _send_daily_report(self):
        """Gunluk kapannis raporu — gun sonu bir kez."""
        try:
            acc = self.bridge.get_account()
            b   = acc.get("balance", 0)
            pnl = acc.get("profit", 0)
            wins = losses = 0
            for s in cfg.ALL_SYMBOLS:
                st = self.executor.get_state(s)
                if st:
                    wins   += getattr(st, "day_wins", 0)
                    losses += getattr(st, "day_losses", 0)
            active = self._get_active()
            self.telegram.notify_daily_report(b, pnl, wins, losses, active)
        except Exception:
            pass

    # ═══════════════════════════════════════════════════════
    # GRACEFUL SHUTDOWN
    # ═══════════════════════════════════════════════════════

    def _shutdown(self, signum, frame):
        """
        Duzgun kapatma:
          1. running = False (tum thread'ler durur)
          2. Thread'lerin bitmesini bekle (max 5s)
          3. MT5 baglantisini kes
          4. Telegram durma bildirimi
        """
        log.info("\n[KAPATMA] Durdurma sinyali alindi...")
        self.running = False

        # Event signal'i tetikle (strategy thread bekliyorsa)
        self._event_signal.set()

        # Telegram bildirimi
        self.telegram.notify("*MIA kapatiliyor...*")

        # Thread'lerin durmasini bekle (max 5s)
        log.info("[KAPATMA] Thread'ler bekleniyor (max 5s)...")
        time.sleep(2)

        # MT5 baglantisini kes
        try:
            self.bridge.disconnect()
            log.info("[KAPATMA] MT5 baglantisi kesildi")
        except Exception:
            pass

        # Telegram durdur
        try:
            self.telegram.stop()
        except Exception:
            pass

        log.info("[KAPATMA] MIA v4.0 kapatildi.")
        sys.exit(0)

    # ═══════════════════════════════════════════════════════
    # BANNER
    # ═══════════════════════════════════════════════════════

    def _print_banner(self):
        log.info("=" * 65)
        log.info("  MIA v6.2.0 — Market Intelligence Agent")
        log.info("  BytamerFX | Coklu-Ajan Otonom Sistem + EA Grid")
        log.info("  SpeedAgent + GridAgent + RiskAgent + StrategyAgent + MasterAgent")
        log.info("  Arbitrator Karar Koordinasyonu | Olay-Gudumlu Mimari")
        log.info(f"  Hesap: #{cfg.MT5_LOGIN} | By T@MER — bytamer.com")
        log.info("=" * 65)


# ═══════════════════════════════════════════════════════════
# GIRIS NOKTASI
# ═══════════════════════════════════════════════════════════

if __name__ == "__main__":
    MIA().start()
