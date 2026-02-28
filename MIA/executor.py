"""
MIA v4.0 — Trade Executor
Coklu-Ajan Karar Yurütme Katmani

Brain.SessionDecision + Arbitrator.AgentDecision → MT5 emirleri
Tum emir yonetimi, pozisyon takibi, FIFO kasasi, risk dogrulamasi
ve cooldown sistemi burada.

Degisiklikler (v4.0):
  - ATR-Adaptif peak drop artik SpeedAgent'ta — executor sadece
    profit tracking ve karar yurutme yapar
  - RiskAgent entegrasyonu: Her OPEN oncesi validate_open() cagirilir
  - Adaptif lot carpani: MasterAgent lot_multiplier * RiskAgent multiplier
  - Cooldown sistemi: Kapatmadan sonra TRADE_COOLDOWN_SECONDS bekleme
  - execute_agent_decisions(): Arbitrator ciktisini yurutur
  - Geriye uyumluluk: execute_session() hala calisir

Copyright 2026, By T@MER — https://www.bytamer.com
"""

import time
import logging
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Tuple
from symbol_profiles import get_symbol_profile

from brain import SessionDecision, TradeDecision
from agents import AgentDecision
import config as cfg
from grid_manager import GridManager

log = logging.getLogger("Executor")


# =====================================================================
# VERI YAPILARI
# =====================================================================

@dataclass
class OpenPosition:
    """Executor'in tuttugu pozisyon kaydi"""
    ticket:      int
    symbol:      str
    direction:   str     # "BUY" / "SELL"
    lot:         float
    open_price:  float
    open_time:   float
    role:        str     # "MAIN" / "SPM1" / "SPM2" / "HEDGE" / "DCA"
    profit:      float   = 0.0
    peak_profit: float   = 0.0
    partial_done:bool    = False
    # FIFO kasa (bu pozisyonun katkisi)
    kasa_contrib: float  = 0.0
    # v5.0: Grid entegrasyon
    spm_layer:   int     = 0       # SPM katman numarası (1, 2, ...)
    parent_ticket: int   = 0       # Bağlı ANA ticket
    breakeven_locked: bool = False # Breakeven kilidi aktif mi


@dataclass
class SymbolState:
    """Bir sembolun tum durumu"""
    symbol:      str
    positions:   List[OpenPosition] = field(default_factory=list)
    kasa:        float = 0.0       # Kapatilan SPM karlari
    total_cashed:float = 0.0
    blacklisted: bool  = False
    blacklist_until: float = 0.0
    last_open_time:  float = 0.0
    last_close_time: float = 0.0   # v4.0: Cooldown icin son kapama zamani

    @property
    def main(self) -> Optional[OpenPosition]:
        for p in self.positions:
            if p.role == "MAIN":
                return p
        return None

    @property
    def spms(self) -> List[OpenPosition]:
        return [p for p in self.positions if p.role.startswith("SPM")]

    @property
    def hedges(self) -> List[OpenPosition]:
        return [p for p in self.positions if p.role == "HEDGE"]

    @property
    def total_pnl(self) -> float:
        return sum(p.profit for p in self.positions)

    def to_dict(self) -> dict:
        return {
            "symbol": self.symbol,
            "kasa":   self.kasa,
            "positions": [
                {
                    "ticket":     p.ticket,
                    "role":       p.role,
                    "direction":  p.direction,
                    "lot":        p.lot,
                    "open_price": p.open_price,
                    "profit":     p.profit,
                    "peak_profit":p.peak_profit,
                    "kasa":       self.kasa,
                }
                for p in self.positions
            ]
        }


# =====================================================================
# TRADE EXECUTOR
# =====================================================================

class TradeExecutor:
    """
    MIA v4.0 Karar Yurutme Katmani.

    Sorumluluklar:
      - Brain / Arbitrator kararlarini al → MT5 emri gonder
      - Pozisyon takibi (rol, kasa, FIFO)
      - Risk dogrulamasi (RiskAgent.validate_open)
      - Adaptif lot carpani (MasterAgent + RiskAgent)
      - Cooldown sistemi (ayni sembol yeniden acma bekleme)
      - Profit / peak profit guncelleme (SpeedAgent icin veri)
      - Performans geri bildirimi → Brain'e kayit
    """

    def __init__(self, mt5_bridge, brain, risk_agent=None):
        """
        Args:
            mt5_bridge  : MT5Bridge instance (emir gonder/al)
            brain       : AutonomousBrain instance (performans kaydi)
            risk_agent  : RiskAgent instance (opsiyonel, v4.0 risk dogrulamasi)
        """
        self.bridge  = mt5_bridge
        self.brain   = brain
        self.risk_agent = risk_agent
        self.states: Dict[str, SymbolState] = {
            sym: SymbolState(sym) for sym in cfg.ALL_SYMBOLS
        }
        self._magic = 20260217

        # v4.0: Adaptif lot carpani (MasterAgent tarafindan guncellenir)
        self.master_lot_multiplier: float = 1.0

        # v5.0: Son kapanan pozisyon detaylari (Telegram bildirimi icin)
        self._last_closed: List[dict] = []

    # =================================================================
    # MASTER LOT MULTIPLIER (MasterAgent tarafindan set edilir)
    # =================================================================

    def set_master_lot_multiplier(self, multiplier: float):
        """
        MasterAgent'in belirledigi lot carpanini kaydet.

        Args:
            multiplier: 0.0 - 2.0 arasi lot carpani
                        0.0 = islem durdur
                        1.0 = normal
                        2.0 = agresif
        """
        clamped = max(
            cfg.MASTER_LOT_MULTIPLIER_RANGE[0],
            min(cfg.MASTER_LOT_MULTIPLIER_RANGE[1], multiplier),
        )
        if clamped != self.master_lot_multiplier:
            log.info(
                f"[Executor] Master lot carpani guncellendi: "
                f"{self.master_lot_multiplier:.2f} -> {clamped:.2f}"
            )
        self.master_lot_multiplier = clamped

    # =================================================================
    # ANA YURUTME — SessionDecision (geriye uyumlu)
    # =================================================================

    def execute_session(self, session: SessionDecision) -> List[str]:
        """
        Brain'in SessionDecision'ini execute et.
        Geriye uyumluluk icin korundu — v3 akisi hala calisir.

        Args:
            session: Brain'den gelen SessionDecision

        Returns:
            Log mesajlari listesi
        """
        logs = []
        log.info(
            f"[Executor] {len(session.decisions)} karar isleniyor "
            f"(SessionDecision)..."
        )

        # Tum pozisyonlari guncelle
        self._refresh_all()

        for decision in session.decisions:
            try:
                log.info(
                    f"[Executor] -> {decision.symbol} {decision.action} "
                    f"urgency={decision.urgency} lot={decision.lot}"
                )
                result = self._execute_trade_decision(decision)
                if result:
                    logs.extend(result)
                    log.info(f"[Executor] OK {decision.symbol}: {result}")
                else:
                    log.info(
                        f"[Executor] SKIP {decision.symbol}: "
                        f"sonuc yok (HOLD veya engellendi)"
                    )
            except Exception as e:
                log.error(
                    f"[{decision.symbol}] Karar execute hatasi: {e}",
                    exc_info=True,
                )
                logs.append(f"HATA {decision.symbol}: {e}")

        return logs

    # =================================================================
    # ANA YURUTME — AgentDecision (v4.0 yeni)
    # =================================================================

    def execute_agent_decisions(self, decisions: List[AgentDecision]) -> List[str]:
        """
        Arbitrator'un cikti listesini yurutme.

        Desteklenen action tipleri:
          - OPEN_BUY / OPEN_SELL : Normal acilis (risk dogrulama + cooldown)
          - CLOSE                : Pozisyon kapat
          - PARTIAL_CLOSE        : %50 kismi kapat
          - FAST_ENTRY           : Speed Agent hizli giris (OPEN gibi, isaretli)
          - EMERGENCY_CLOSE      : Sembol icin TUM pozisyonlari kapat
          - RISK_VETO            : Yeni acilislari engelle (bilgi amacli)
          - PEAK_DROP            : Ticket bazli peak drop kapatma
          - STOP_TRADING         : Tum islemleri durdur (bilgi)
          - PAUSE_TRADING        : Yeni acilislari duraklat (bilgi)
          - LOT_REDUCE           : Lot azaltma (bilgi, Arbitrator uygulamis)
          - STRATEGY_OPEN        : Strateji ajani acilis (OPEN gibi)
          - STRATEGY_CLOSE       : Strateji ajani kapatma (CLOSE gibi)

        Args:
            decisions: Arbitrator.process() ciktisi

        Returns:
            Log mesajlari listesi
        """
        if not decisions:
            return []

        logs = []
        log.info(
            f"[Executor] {len(decisions)} AgentDecision isleniyor..."
        )

        # Pozisyonlari guncelle
        self._refresh_all()

        # Global veto / pause / stop durumu
        has_veto = False
        has_stop = False

        for d in decisions:
            try:
                result = self._execute_agent_decision(d, has_veto, has_stop)
                if result:
                    logs.extend(result)

                # Durum bayraklarini guncelle (sonraki kararlar icin)
                if d.action in ("RISK_VETO", "PAUSE_TRADING"):
                    has_veto = True
                elif d.action == "STOP_TRADING":
                    has_stop = True

            except Exception as e:
                log.error(
                    f"[{d.symbol}] AgentDecision execute hatasi: {e}",
                    exc_info=True,
                )
                logs.append(f"HATA {d.symbol} {d.action}: {e}")

        return logs

    def _execute_agent_decision(
        self,
        d: AgentDecision,
        has_veto: bool,
        has_stop: bool,
    ) -> List[str]:
        """
        Tek bir AgentDecision'i yurutme.

        Args:
            d          : Yurutulecek karar
            has_veto   : Global veto/pause durumu
            has_stop   : Global stop durumu

        Returns:
            Log mesajlari listesi
        """
        logs = []
        symbol = d.symbol

        # ── EMERGENCY CLOSE — Sembol icin TUM pozisyonlari kapat ──
        if d.action == "EMERGENCY_CLOSE":
            result = self._emergency_close(d)
            logs.extend(result)
            return logs

        # ── PEAK DROP — Ticket bazli kapatma ─────────────────────
        if d.action == "PEAK_DROP":
            result = self._close_by_ticket(d)
            logs.extend(result)
            return logs

        # ── CLOSE / STRATEGY_CLOSE — Pozisyon kapat ─────────────
        if d.action in ("CLOSE", "STRATEGY_CLOSE"):
            result = self._close_position_decision(d)
            logs.extend(result)
            return logs

        # ── PARTIAL CLOSE — %50 kismi kapat ─────────────────────
        if d.action == "PARTIAL_CLOSE":
            result = self._partial_close_decision(d)
            logs.extend(result)
            return logs

        # ── RISK_VETO / PAUSE / STOP / LOT_REDUCE — Bilgi ──────
        if d.action in ("RISK_VETO", "PAUSE_TRADING", "STOP_TRADING", "LOT_REDUCE"):
            log.info(
                f"[Executor] {d.action} ({d.agent_name}): {d.reason}"
            )
            # Bilgi amacli, execute edilecek bir sey yok
            return logs

        # ── REVERSE_BUY / REVERSE_SELL — Pozisyon ters cevirme ──
        if d.action in ("REVERSE_BUY", "REVERSE_SELL"):
            result = self._reverse_position(d)
            logs.extend(result)
            return logs

        # ── OPEN_BUY / OPEN_SELL / FAST_ENTRY / STRATEGY_OPEN ──
        if d.action in ("OPEN_BUY", "OPEN_SELL", "FAST_ENTRY", "STRATEGY_OPEN"):
            # Veto/stop kontrolu
            if has_stop:
                log.info(
                    f"[Executor] {d.action} {symbol} engellendi — "
                    f"STOP_TRADING aktif"
                )
                return logs
            if has_veto and d.action != "FAST_ENTRY":
                log.info(
                    f"[Executor] {d.action} {symbol} engellendi — "
                    f"RISK_VETO/PAUSE aktif"
                )
                return logs

            result = self._open_position_agent(d)
            logs.extend(result)
            return logs

        # ══════════════════════════════════════════════════════
        # v5.0: GRID ACTION HANDLERS
        # ══════════════════════════════════════════════════════

        # ── GRID_CLOSE — Ticket bazlı grid kapatma ──
        if d.action == "GRID_CLOSE":
            result = self._grid_close_ticket(d)
            logs.extend(result)
            return logs

        # ── GRID_PARTIAL_CLOSE — Kısmi kapatma (%60) ──
        if d.action == "GRID_PARTIAL_CLOSE":
            result = self._grid_partial_close(d)
            logs.extend(result)
            return logs

        # ── GRID_FIFO_CLOSE — FIFO settlement kapatma ──
        if d.action == "GRID_FIFO_CLOSE":
            result = self._grid_fifo_close(d)
            logs.extend(result)
            return logs

        # ── GRID_NET_SETTLE — Net settlement kapatma ──
        if d.action == "GRID_NET_SETTLE":
            result = self._grid_net_settle(d)
            logs.extend(result)
            return logs

        # ── GRID_OPEN_SPM — SPM pozisyon aç ──
        if d.action == "GRID_OPEN_SPM":
            if has_stop or has_veto:
                log.info(f"[Executor] {d.action} {symbol} engellendi — veto/stop aktif")
                return logs
            result = self._grid_open_spm(d)
            logs.extend(result)
            return logs

        # ── GRID_OPEN_HEDGE — Rescue hedge aç ──
        if d.action == "GRID_OPEN_HEDGE":
            if has_stop:
                log.info(f"[Executor] {d.action} {symbol} engellendi — stop aktif")
                return logs
            result = self._grid_open_hedge(d)
            logs.extend(result)
            return logs

        # ── GRID_PROMOTE — SPM/HEDGE → ANA promosyon ──
        if d.action == "GRID_PROMOTE":
            result = self._grid_promote(d)
            logs.extend(result)
            return logs

        # ── GRID_DEADLOCK_WARN — Bilgi ──
        if d.action == "GRID_DEADLOCK_WARN":
            log.warning(f"[Executor] GRID DEADLOCK: {d.reason}")
            return logs

        # ── BILINMEYEN ACTION ────────────────────────────────────
        log.warning(
            f"[Executor] Bilinmeyen action: {d.action} "
            f"({d.agent_name}, {symbol})"
        )
        return logs

    # =================================================================
    # v5.0: GRID ACTION YÜRÜTÜCÜLER
    # =================================================================

    def _grid_close_ticket(self, d: AgentDecision) -> List[str]:
        """Grid tarafından ticket bazlı kapatma (mum TP, peak drop, hedge close)."""
        logs = []
        ticket = d.metadata.get("ticket", 0) if d.metadata else 0
        if not ticket:
            return logs

        state = self.states.get(d.symbol)
        if not state:
            return logs

        # ── LOSS GUARD: Grid close icin pozisyon profit kontrolu ──
        target_pos = next(
            (p for p in state.positions if p.ticket == ticket), None
        )
        if target_pos and target_pos.profit < 0:
            # FIFO settlement haricinde zararda kapatma
            is_fifo = d.metadata.get("fifo_settlement", False) if d.metadata else False
            if not is_fifo:
                log.warning(
                    f"[{d.symbol}] LOSS GUARD: GRID_CLOSE #{ticket} "
                    f"zarar ${target_pos.profit:.2f} — ENGELLENDI"
                )
                logs.append(
                    f"LOSS_GUARD GRID_CLOSE {d.symbol} #{ticket} "
                    f"${target_pos.profit:+.2f} engellendi"
                )
                return logs

        result = self.bridge.close_position(ticket)
        if result and result.get("success"):
            profit = result.get("profit", 0.0)
            # Kasaya ekle?
            add_kasa = d.metadata.get("add_to_kasa", False) if d.metadata else False
            if add_kasa and profit > 0 and hasattr(state, '_grid_manager'):
                state._grid_manager.add_to_kasa(profit)
            # Performans kaydı
            self._record_close(d.symbol, profit)
            logs.append(f"GRID_CLOSE {d.symbol} #{ticket}: +${profit:.2f} ({d.reason})")
            log.info(f"[{d.symbol}] Grid kapatma: #{ticket} +${profit:.2f}")
        else:
            logs.append(f"GRID_CLOSE HATA {d.symbol} #{ticket}")

        return logs

    def _grid_partial_close(self, d: AgentDecision) -> List[str]:
        """Kısmi kapatma (%60 lot)."""
        logs = []
        ticket = d.metadata.get("ticket", 0) if d.metadata else 0
        close_vol = d.lot
        if not ticket or close_vol <= 0:
            return logs

        result = self.bridge.close_position_partial(ticket, close_vol)
        if result and result.get("success"):
            profit = result.get("profit", 0.0)
            logs.append(f"PARTIAL_CLOSE {d.symbol} #{ticket}: {close_vol:.2f}lot +${profit:.2f}")
            log.info(f"[{d.symbol}] Kısmi kapama: #{ticket} {close_vol:.2f}lot +${profit:.2f}")
        else:
            logs.append(f"PARTIAL_CLOSE HATA {d.symbol} #{ticket}")

        return logs

    def _grid_fifo_close(self, d: AgentDecision) -> List[str]:
        """FIFO settlement kapatma — ANA veya en kötü SPM."""
        logs = []
        ticket = d.metadata.get("ticket", 0) if d.metadata else 0
        if not ticket:
            return logs

        state = self.states.get(d.symbol)
        if not state:
            return logs

        result = self.bridge.close_position(ticket)
        if result and result.get("success"):
            profit = result.get("profit", 0.0)
            is_ana_close = d.metadata.get("fifo_close_ana", False) if d.metadata else False
            promote = d.metadata.get("promote_after", False) if d.metadata else False

            self._record_close(d.symbol, profit)
            logs.append(f"FIFO_CLOSE {d.symbol} #{ticket}: ${profit:.2f} ({d.reason})")
            log.info(f"[{d.symbol}] FIFO kapatma: #{ticket} ${profit:.2f}")

            # Kasa temizleme ve promosyon GridManager tarafından takip edilir
            if is_ana_close and hasattr(state, '_grid_manager'):
                net = d.metadata.get("net_profit", 0.0)
                state._grid_manager.clear_kasa(net)
        else:
            logs.append(f"FIFO_CLOSE HATA {d.symbol} #{ticket}")

        return logs

    def _grid_net_settle(self, d: AgentDecision) -> List[str]:
        """Net settlement — kasa + en kötü pozisyon kapatma."""
        logs = []
        ticket = d.metadata.get("ticket", 0) if d.metadata else 0
        if not ticket:
            return logs

        state = self.states.get(d.symbol)
        result = self.bridge.close_position(ticket)
        if result and result.get("success"):
            profit = result.get("profit", 0.0)
            self._record_close(d.symbol, profit)
            if d.metadata.get("clear_kasa") and state and hasattr(state, '_grid_manager'):
                net = d.metadata.get("net_profit", 0.0)
                state._grid_manager.clear_kasa(net)
            logs.append(f"NET_SETTLE {d.symbol} #{ticket}: ${profit:.2f} ({d.reason})")
            log.info(f"[{d.symbol}] Net settlement: #{ticket} ${profit:.2f}")

        return logs

    def _grid_open_spm(self, d: AgentDecision) -> List[str]:
        """SPM pozisyon aç (grid)."""
        logs = []
        meta = d.metadata or {}
        direction = meta.get("direction", d.metadata.get("direction", "BUY"))
        layer = meta.get("layer", 1)
        role = meta.get("role", f"SPM{layer}")
        parent = meta.get("parent_ticket", 0)

        # v3.8.0: Margin guard %300 + bakiye kontrolü
        acc = self.bridge.get_account()
        if acc.get("balance", 0) < cfg.MIN_BALANCE_FLOOR:
            return logs
        margin_lvl = acc.get("margin_level", 9999)
        if margin_lvl > 0 and margin_lvl < getattr(cfg, "MARGIN_GUARD_PCT", 300):
            log.info(f"[{d.symbol}] SPM ENGEL: Margin {margin_lvl:.0f}% < %300")
            return logs

        comment = f"MIA_{role}_{d.symbol[:6]}"
        action = "BUY" if direction == "BUY" else "SELL"

        ticket = self.bridge.open_position(
            symbol=d.symbol,
            direction=action,
            lot=d.lot,
            role=role,
            comment_extra=comment,
        )
        if ticket:
            logs.append(f"GRID_SPM {d.symbol} {role} {action} {d.lot:.2f}lot #{ticket}")
            log.info(f"[{d.symbol}] SPM açıldı: {role} {action} {d.lot:.2f}lot #{ticket} — {d.reason}")
        else:
            logs.append(f"GRID_SPM HATA {d.symbol} {role}")

        return logs

    def _grid_open_hedge(self, d: AgentDecision) -> List[str]:
        """Rescue hedge aç."""
        logs = []
        meta = d.metadata or {}
        direction = meta.get("direction", "BUY")

        comment = f"MIA_HEDGE_{d.symbol[:6]}"
        action = "BUY" if direction == "BUY" else "SELL"

        ticket = self.bridge.open_position(
            symbol=d.symbol,
            direction=action,
            lot=d.lot,
            role="HEDGE",
            comment_extra=comment,
        )
        if ticket:
            logs.append(f"GRID_HEDGE {d.symbol} {action} {d.lot:.2f}lot #{ticket}")
            log.info(f"[{d.symbol}] Rescue hedge: {action} {d.lot:.2f}lot #{ticket} — {d.reason}")
        else:
            logs.append(f"GRID_HEDGE HATA {d.symbol}")

        return logs

    def _grid_promote(self, d: AgentDecision) -> List[str]:
        """Grid promosyon: SPM/HEDGE → MAIN rol değişikliği."""
        logs = []
        ticket = d.metadata.get("ticket", 0) if d.metadata else 0
        promote_to = d.metadata.get("promote_to", "MAIN") if d.metadata else "MAIN"

        state = self.states.get(d.symbol)
        if not state:
            return logs

        # Pozisyonu bul ve rol güncelle
        for pos in state.positions:
            if pos.ticket == ticket:
                old_role = pos.role
                pos.role = promote_to
                logs.append(f"PROMOTE {d.symbol} #{ticket}: {old_role} → {promote_to}")
                log.info(f"[{d.symbol}] Promosyon: #{ticket} {old_role} → {promote_to}")
                break

        return logs

    def _record_close(self, symbol: str, profit: float):
        """Kapanış performansını kaydet."""
        try:
            won = profit > 0
            self.brain.record_trade_result(symbol, profit, won)
        except Exception:
            pass

    # =================================================================
    # ACILIS — AgentDecision
    # =================================================================

    def _open_position_agent(self, d: AgentDecision) -> List[str]:
        """
        AgentDecision ile pozisyon acma.
        Risk dogrulamasi, cooldown, adaptif lot uygulanir.

        Args:
            d: OPEN_BUY, OPEN_SELL, FAST_ENTRY veya STRATEGY_OPEN karari

        Returns:
            Log mesajlari
        """
        logs = []
        symbol = d.symbol
        state = self.states.get(symbol)
        if not state:
            log.warning(f"[Executor] {symbol} icin state yok!")
            return logs

        # Yon belirle
        if d.action == "FAST_ENTRY" or d.action == "STRATEGY_OPEN":
            # metadata'dan yon al
            dir_ = d.metadata.get("direction", "")
            if not dir_:
                # action'dan cikar
                if "BUY" in d.reason.upper():
                    dir_ = "BUY"
                elif "SELL" in d.reason.upper():
                    dir_ = "SELL"
                else:
                    log.warning(
                        f"[Executor] {symbol} {d.action}: yon belirlenemedi"
                    )
                    return logs
        else:
            dir_ = "BUY" if "BUY" in d.action else "SELL"

        # ── COOLDOWN KONTROLU ────────────────────────────────────
        cooldown_remaining = self._check_cooldown(symbol)
        if cooldown_remaining > 0:
            log.info(
                f"[Executor] {symbol} cooldown aktif — "
                f"{cooldown_remaining:.0f}s kaldi, acilis engellendi"
            )
            return logs

        # ── MEVCUT MAIN KONTROLU ────────────────────────────────
        if state.main:
            log.info(
                f"[{symbol}] Zaten MAIN pozisyon var "
                f"#{state.main.ticket} — acilis atlandi"
            )
            return logs

        # ── LOT HESAPLAMA (adaptif) ──────────────────────────────
        base_lot = d.lot if d.lot > 0 else cfg.MIN_LOT
        final_lot = self._calculate_final_lot(base_lot, symbol)

        if final_lot <= 0:
            log.info(
                f"[{symbol}] Lot carpani 0 — islem durduruldu "
                f"(master={self.master_lot_multiplier:.2f})"
            )
            return logs

        # ── RISK DOGRULAMASI ─────────────────────────────────────
        if self.risk_agent is not None:
            positions_dict = self._get_positions_dict_for_risk()
            session_name = d.metadata.get("session", "LONDON")

            allowed, reason, adjusted_lot = self.risk_agent.validate_open(
                symbol=symbol,
                direction=dir_,
                lot=final_lot,
                positions=positions_dict,
                session=session_name,
            )

            if not allowed:
                log.info(
                    f"[{symbol}] RiskAgent engelledi: {reason}"
                )
                return logs

            final_lot = adjusted_lot
            log.debug(
                f"[{symbol}] RiskAgent onayladi: lot={adjusted_lot:.2f} "
                f"| {reason}"
            )
        else:
            # Risk agent yok — temel lot dogrulamasi
            final_lot = max(cfg.MIN_LOT, min(cfg.MAX_LOT_PER_SYMBOL, final_lot))

        # ── LOT GUARD — Sembol bazlı min/max zorlama ────────────
        sym_min = cfg.MIN_LOT_OVERRIDES.get(symbol, cfg.MIN_LOT)
        sym_max = 0.05  # Tüm semboller için hard max (hesap güvenliği)
        if final_lot < sym_min:
            log.info(f"[LOT GUARD] {symbol}: {final_lot:.2f} < min={sym_min:.2f} → {sym_min:.2f}")
            final_lot = sym_min
        if final_lot > sym_max:
            log.info(f"[LOT GUARD] {symbol}: {final_lot:.2f} > max={sym_max:.2f} → {sym_max:.2f}")
            final_lot = sym_max

        # ── TOPLAM LOT LIMITI ────────────────────────────────────
        total_lots = sum(
            sum(p.lot for p in s.positions)
            for s in self.states.values()
        )
        if total_lots + final_lot > cfg.MAX_TOTAL_LOTS:
            log.warning(
                f"[{symbol}] Toplam lot limiti asildi — "
                f"{total_lots:.2f}+{final_lot:.2f} > "
                f"{cfg.MAX_TOTAL_LOTS} — {d.action} iptal"
            )
            return logs

        # ── DINAMIK LOT MODU ─────────────────────────────────────
        lot_for_bridge = final_lot
        if cfg.LOT_DYNAMIC:
            lot_for_bridge = 0  # bridge calc_dynamic_lot() cagirir

        # ── MT5 EMIR GONDER ──────────────────────────────────────
        is_fast_entry = d.action == "FAST_ENTRY"
        role = "MAIN"

        ticket = self.bridge.open_position(
            symbol    = symbol,
            direction = dir_,
            lot       = lot_for_bridge,
            role      = role,
            layer     = 0,
        )

        if ticket:
            pos = OpenPosition(
                ticket    = ticket,
                symbol    = symbol,
                direction = dir_,
                lot       = final_lot,
                open_price= self._get_price(symbol, dir_),
                open_time = time.time(),
                role      = role,
            )
            state.positions.append(pos)
            state.last_open_time = time.time()
            state.kasa = 0.0

            entry_type = "FAST_ENTRY" if is_fast_entry else d.action
            log.info(
                f"[{symbol}] {entry_type} {dir_} {final_lot:.2f}lot "
                f"#{ticket} | {d.agent_name}: {d.reason[:80]}"
            )
            logs.append(
                f"OPEN {symbol} {dir_} {final_lot:.2f}lot #{ticket} "
                f"({d.agent_name})"
            )

            # Performans kaydi icin brain'e bildir
            self.brain.record_trade_result(symbol, 0.0, True) if False else None
        else:
            log.warning(
                f"[{symbol}] MT5 emir basarisiz — "
                f"{d.action} {dir_} {final_lot:.2f}lot"
            )

        return logs

    # =================================================================
    # KAPATMA — AgentDecision
    # =================================================================

    def _close_position_decision(self, d: AgentDecision) -> List[str]:
        """
        CLOSE / STRATEGY_CLOSE karari yurutme.
        Metadata'da ticket varsa o pozisyonu kapatir,
        yoksa MAIN pozisyonu kapatir.
        """
        logs = []
        symbol = d.symbol
        state = self.states.get(symbol)
        if not state:
            return logs

        # Ticket bazli kapatma
        target_ticket = d.metadata.get("ticket", 0)
        if target_ticket:
            target_pos = next(
                (p for p in state.positions if p.ticket == target_ticket),
                None,
            )
        else:
            target_pos = state.main

        if not target_pos:
            log.info(f"[{symbol}] Kapatilacak pozisyon bulunamadi")
            return logs

        # ── LOSS GUARD: Zarardaki pozisyon ASLA tek basina kapatilmaz! ──
        # SADECE su durumlar haric:
        #   - EMERGENCY_CLOSE: Mutlak stop-loss ($15+) — hayat kurtarir
        #   - GRID_FIFO_CLOSE: FIFO kasa sistemi — kasa >= $5, net pozitif
        #   - GRID_NET_SETTLE: Net settlement — net pozitif
        # Diger TUM aksiyonlar (CLOSE, STRATEGY_CLOSE, PEAK_DROP vs) ENGELLENIR!
        _FIFO_ALLOWED = ("EMERGENCY_CLOSE", "GRID_FIFO_CLOSE", "GRID_NET_SETTLE")
        if target_pos.profit < 0 and d.action not in _FIFO_ALLOWED:
            log.info(
                f"[{symbol}] LOSS GUARD: {target_pos.role} #{target_pos.ticket} "
                f"zarar ${target_pos.profit:.2f} — {d.action} ENGELLENDI! "
                f"SPM/HEDGE/FIFO ile kurtar, tek basina kapatma YASAK"
            )
            return logs

        # ── MIN PROFIT GUARD: Spread masrafini karsilamayan kapatmayi engelle ──
        # Profil bazli min_close_profit kontrolu (ornegin BTC=$2.50)
        try:
            profile = get_symbol_profile(symbol)
            min_profit = profile.min_close_profit
        except Exception:
            min_profit = 1.0  # Fallback
        if 0 < target_pos.profit < min_profit and d.action not in ("EMERGENCY_CLOSE", "GRID_FIFO_CLOSE"):
            log.info(
                f"[{symbol}] MIN_PROFIT GUARD: {target_pos.role} #{target_pos.ticket} "
                f"kar ${target_pos.profit:.2f} < min ${min_profit:.2f} — kapatma ENGELLENDI"
            )
            logs.append(
                f"MIN_PROFIT {symbol} #{target_pos.ticket} "
                f"${target_pos.profit:+.2f} < ${min_profit:.2f} engellendi"
            )
            return logs

        # Kapama oncesi bilgileri sakla
        _closed_info = {
            "ticket": target_pos.ticket,
            "symbol": symbol,
            "role": target_pos.role,
            "direction": target_pos.direction,
            "lot": target_pos.lot,
            "open_price": target_pos.open_price,
        }

        ok = self.bridge.close_position(target_pos.ticket)
        if ok:
            pnl = target_pos.profit
            won = pnl > 0

            # Kapanan pozisyon detaylarini sakla (Telegram icin)
            _closed_info["pnl"] = pnl
            _closed_info["close_price"] = getattr(target_pos, 'close_price', 0) or target_pos.open_price
            self._last_closed.append(_closed_info)

            # Kasa guncelleme
            if target_pos.role != "MAIN":
                state.kasa += pnl

            self.brain.record_trade_result(
                symbol, pnl, won,
                direction=target_pos.direction,
                reason=f"{d.agent_name}:{d.action}",
            )
            state.positions.remove(target_pos)
            state.last_close_time = time.time()

            # MAIN kapandiysa terfi
            if target_pos.role == "MAIN" and state.spms:
                self._promote_oldest_spm(state)

            log.info(
                f"[{symbol}] {target_pos.role} kapatildi "
                f"${pnl:+.2f} | {d.agent_name}: {d.reason[:60]}"
            )
            logs.append(
                f"CLOSE {symbol} #{target_pos.ticket} "
                f"${pnl:+.2f} ({d.agent_name})"
            )

        return logs

    def _reverse_position(self, d: AgentDecision) -> List[str]:
        """
        REVERSE_BUY / REVERSE_SELL — Mevcut pozisyonlari kapat + ters yone gir.
        Trend donmusse tek hamlede: zarar durdur + yeni trende bin.
        """
        logs = []
        symbol = d.symbol
        state = self.states.get(symbol)
        if not state:
            return logs

        new_dir = "BUY" if d.action == "REVERSE_BUY" else "SELL"

        # 1) Mevcut tum pozisyonlari kapat
        positions_to_close = list(state.positions)  # kopya
        if not positions_to_close:
            log.info(f"[{symbol}] REVERSE: Kapatilacak pozisyon yok, normal acilis yapiliyor")
        else:
            total_pnl = 0.0
            for pos in positions_to_close:
                ok = self.bridge.close_position(pos.ticket)
                if ok:
                    pnl = pos.profit
                    won = pnl > 0
                    total_pnl += pnl

                    _closed_info = {
                        "ticket": pos.ticket, "symbol": symbol,
                        "role": pos.role, "direction": pos.direction,
                        "lot": pos.lot, "open_price": pos.open_price,
                        "pnl": pnl, "close_price": getattr(pos, 'close_price', 0) or pos.open_price,
                    }
                    self._last_closed.append(_closed_info)
                    self.brain.record_trade_result(symbol, pnl, won,
                                                   direction=pos.direction,
                                                   reason=f"REVERSE->{new_dir}")
                    state.positions.remove(pos)
                    log.info(f"[{symbol}] REVERSE kapat: {pos.role} #{pos.ticket} ${pnl:+.2f}")
                else:
                    log.warning(f"[{symbol}] REVERSE kapat basarisiz: #{pos.ticket}")

            # Kasa/state temizle
            state.kasa = 0.0
            state.last_close_time = time.time()
            logs.append(f"REVERSE_CLOSE {symbol} {len(positions_to_close)} poz ${total_pnl:+.2f}")

        # 2) Ters yone yeni pozisyon ac
        base_lot = d.lot if d.lot > 0 else cfg.MIN_LOT
        final_lot = self._calculate_final_lot(base_lot, symbol)
        if final_lot <= 0:
            log.info(f"[{symbol}] REVERSE: Lot 0 — ters acilis iptal")
            return logs

        result = self.bridge.open_position(
            symbol=symbol,
            direction=new_dir,
            lot=final_lot,
            comment=f"MIA_REVERSE_{new_dir}",
        )

        if result and result.get("ticket"):
            ticket = result["ticket"]
            log.info(
                f"[{symbol}] REVERSE {new_dir} acildi #{ticket} "
                f"{final_lot}lot | {d.reason[:60]}"
            )
            logs.append(f"REVERSE_OPEN {symbol} {new_dir} #{ticket} {final_lot}lot")
        else:
            log.warning(f"[{symbol}] REVERSE {new_dir} acilis BASARISIZ")
            logs.append(f"REVERSE_OPEN_FAIL {symbol} {new_dir}")

        return logs

    def _close_by_ticket(self, d: AgentDecision) -> List[str]:
        """
        PEAK_DROP gibi ticket-bazli kapatma kararlari.
        Metadata'da ticket olmali.
        """
        logs = []
        symbol = d.symbol
        state = self.states.get(symbol)
        if not state:
            return logs

        target_ticket = d.metadata.get("ticket", 0)
        if not target_ticket:
            log.warning(
                f"[{symbol}] {d.action}: ticket metadata'da bulunamadi"
            )
            return logs

        target_pos = next(
            (p for p in state.positions if p.ticket == target_ticket),
            None,
        )
        if not target_pos:
            log.info(
                f"[{symbol}] Ticket #{target_ticket} bulunamadi "
                f"(zaten kapatilmis olabilir)"
            )
            return logs

        # ── LOSS GUARD: Zarardaki pozisyonu PEAK_DROP ile kapatma! ──
        # FIFO (GRID_FIFO_CLOSE) ve EMERGENCY haric, profit < 0 ise engelle.
        if target_pos.profit < 0 and d.action not in (
            "EMERGENCY_CLOSE", "GRID_FIFO_CLOSE", "GRID_NET_SETTLE"
        ):
            log.warning(
                f"[{symbol}] LOSS GUARD: {d.action} {target_pos.role} "
                f"#{target_ticket} zarar ${target_pos.profit:.2f} — ENGELLENDI"
            )
            logs.append(
                f"LOSS_GUARD {d.action} {symbol} #{target_ticket} "
                f"${target_pos.profit:+.2f} engellendi"
            )
            return logs

        # ── MIN PROFIT GUARD: Spread masrafini karsilamayan kapatmayi engelle ──
        try:
            profile = get_symbol_profile(symbol)
            min_profit = profile.min_close_profit
        except Exception:
            min_profit = 1.0
        if 0 < target_pos.profit < min_profit and d.action not in (
            "EMERGENCY_CLOSE", "GRID_FIFO_CLOSE", "GRID_NET_SETTLE"
        ):
            log.info(
                f"[{symbol}] MIN_PROFIT GUARD: {d.action} #{target_ticket} "
                f"kar ${target_pos.profit:.2f} < min ${min_profit:.2f} — ENGELLENDI"
            )
            logs.append(
                f"MIN_PROFIT {d.action} {symbol} #{target_ticket} "
                f"${target_pos.profit:+.2f} < ${min_profit:.2f} engellendi"
            )
            return logs

        # Kapama oncesi bilgileri sakla
        _closed_info = {
            "ticket": target_pos.ticket,
            "symbol": symbol,
            "role": target_pos.role,
            "direction": target_pos.direction,
            "lot": target_pos.lot,
            "open_price": target_pos.open_price,
        }

        ok = self.bridge.close_position(target_pos.ticket)
        if ok:
            pnl = target_pos.profit

            # Kapanan pozisyon detaylarini sakla (Telegram icin)
            _closed_info["pnl"] = pnl
            _closed_info["close_price"] = getattr(target_pos, 'close_price', 0) or target_pos.open_price
            self._last_closed.append(_closed_info)

            # Kasa guncelleme
            if target_pos.role != "MAIN":
                state.kasa += pnl

            won = pnl > 0
            self.brain.record_trade_result(symbol, pnl, won)
            state.positions.remove(target_pos)
            state.last_close_time = time.time()

            # MAIN kapandiysa terfi
            if target_pos.role == "MAIN" and state.spms:
                self._promote_oldest_spm(state)

            log.info(
                f"[{symbol}] {d.action} {target_pos.role} "
                f"#{target_ticket} kapatildi ${pnl:+.2f} | "
                f"{d.reason[:60]}"
            )
            logs.append(
                f"{d.action} {symbol} {target_pos.role} "
                f"#{target_ticket} ${pnl:+.2f}"
            )

        return logs

    def _partial_close_decision(self, d: AgentDecision) -> List[str]:
        """
        PARTIAL_CLOSE karari — %50 kismi kapatma.
        """
        logs = []
        symbol = d.symbol
        state = self.states.get(symbol)
        if not state:
            return logs

        # Ticket bazli veya MAIN
        target_ticket = d.metadata.get("ticket", 0)
        if target_ticket:
            target_pos = next(
                (p for p in state.positions if p.ticket == target_ticket),
                None,
            )
        else:
            target_pos = state.main

        if not target_pos:
            return logs
        if target_pos.profit <= 0:
            log.info(
                f"[{symbol}] Kismi kapatma: profit negatif, atlandi"
            )
            return logs

        close_lot = round(target_pos.lot * 0.5, 2)
        close_lot = max(cfg.MIN_LOT, close_lot)

        ok = self.bridge.close_partial(target_pos.ticket, close_lot)
        if ok:
            partial_pnl = target_pos.profit * 0.5
            state.kasa += partial_pnl
            target_pos.partial_done = True

            log.info(
                f"[{symbol}] Kismi kapat {close_lot}lot "
                f"kasa+${partial_pnl:.2f} | {d.agent_name}"
            )
            logs.append(
                f"PARTIAL {symbol} #{target_pos.ticket} "
                f"{close_lot}lot (${partial_pnl:.2f})"
            )

        return logs

    def _emergency_close(self, d: AgentDecision) -> List[str]:
        """
        EMERGENCY_CLOSE — Sembol icin TUM pozisyonlari kapat.
        symbol == "ALL" ise tum semboller icin gecerli.
        """
        logs = []
        target_symbols = []

        if d.symbol == "ALL":
            target_symbols = [
                sym for sym, state in self.states.items()
                if state.positions
            ]
        else:
            target_symbols = [d.symbol]

        for sym in target_symbols:
            state = self.states.get(sym)
            if not state or not state.positions:
                continue

            log.warning(
                f"[{sym}] ACIL KAPATMA — "
                f"{len(state.positions)} pozisyon kapatiliyor | "
                f"{d.agent_name}: {d.reason[:60]}"
            )

            total_pnl = 0.0
            for pos in list(state.positions):
                ok = self.bridge.close_position(pos.ticket)
                if ok:
                    total_pnl += pos.profit

            self.brain.record_trade_result(sym, total_pnl, total_pnl > 0)
            state.positions.clear()
            state.kasa = 0.0
            state.last_close_time = time.time()

            logs.append(
                f"EMERGENCY_CLOSE {sym} "
                f"${total_pnl:+.2f} ({d.agent_name})"
            )

        return logs

    # =================================================================
    # ESKI TradeDecision YURUTME (geriye uyumlu)
    # =================================================================

    def _execute_trade_decision(self, d: TradeDecision) -> List[str]:
        """
        Brain TradeDecision yurutme (v3 uyumluluk).
        Risk dogrulamasi ve cooldown v4'te eklendi.
        """
        logs = []
        state = self.states.get(d.symbol)
        if not state:
            log.warning(f"[Executor] {d.symbol} icin state yok!")
            return logs

        # ── YENI POZISYON ────────────────────────────────────────
        if d.action in ("OPEN_BUY", "OPEN_SELL") and d.urgency != "SKIP":
            dir_ = "BUY" if "BUY" in d.action else "SELL"

            # Cooldown kontrolu
            cooldown_remaining = self._check_cooldown(d.symbol)
            if cooldown_remaining > 0:
                log.info(
                    f"[{d.symbol}] Cooldown aktif — "
                    f"{cooldown_remaining:.0f}s kaldi"
                )
                return logs

            # Adaptif lot hesaplama
            base_lot = d.lot if d.lot > 0 else cfg.MIN_LOT
            lot = self._calculate_final_lot(base_lot, d.symbol)

            # Lot validasyon
            lot = max(cfg.MIN_LOT, min(cfg.MAX_LOT_PER_SYMBOL, lot))

            # Mevcut pozisyon var mi?
            if state.main:
                log.info(
                    f"[{d.symbol}] Zaten MAIN pozisyon var "
                    f"#{state.main.ticket} — acilis atlandi"
                )
                return logs

            # Risk dogrulamasi
            if self.risk_agent is not None:
                positions_dict = self._get_positions_dict_for_risk()
                allowed, reason, adjusted_lot = self.risk_agent.validate_open(
                    symbol=d.symbol,
                    direction=dir_,
                    lot=lot,
                    positions=positions_dict,
                    session="LONDON",  # SessionDecision'da seans bilgisi yok
                )
                if not allowed:
                    log.info(f"[{d.symbol}] RiskAgent engelledi: {reason}")
                    return logs
                lot = adjusted_lot

            # Toplam lot limiti
            total_lots = sum(
                sum(p.lot for p in s.positions)
                for s in self.states.values()
            )
            log.info(
                f"[{d.symbol}] Acilis: {dir_} {lot}lot | "
                f"toplam_lot={total_lots:.2f}/{cfg.MAX_TOTAL_LOTS}"
            )
            if total_lots + lot > cfg.MAX_TOTAL_LOTS:
                log.warning(
                    f"[{d.symbol}] Toplam lot limiti asildi — "
                    f"{d.action} iptal"
                )
                return logs

            # Dinamik lot modu: lot=0 gonderirsek bridge kendi hesaplar
            lot_for_bridge = lot
            if cfg.LOT_DYNAMIC:
                lot_for_bridge = 0   # bridge calc_dynamic_lot() cagirir

            ticket = self.bridge.open_position(
                symbol    = d.symbol,
                direction = dir_,
                lot       = lot_for_bridge,
                role      = "MAIN",
                layer     = 0,
            )
            if ticket:
                pos = OpenPosition(
                    ticket    = ticket,
                    symbol    = d.symbol,
                    direction = dir_,
                    lot       = lot,
                    open_price= self._get_price(d.symbol, dir_),
                    open_time = time.time(),
                    role      = "MAIN",
                )
                state.positions.append(pos)
                state.last_open_time = time.time()
                state.kasa = 0.0
                log.info(
                    f"[{d.symbol}] MAIN {dir_} {lot}lot "
                    f"#{ticket} | {d.reason}"
                )
                logs.append(f"OPEN {d.symbol} {dir_} {lot}lot #{ticket}")

                # Ayni anda SPM acilacak mi?
                if d.open_spm and d.spm_dir and d.spm_lot > 0:
                    self._open_spm(
                        state, d.spm_dir, d.spm_lot, 1,
                        ticket, d.spm_reason,
                    )

        # ── KAPAT ────────────────────────────────────────────────
        elif d.action == "CLOSE":
            main = state.main
            if main:
                ok = self.bridge.close_position(main.ticket)
                if ok:
                    pnl = main.profit
                    won = pnl > 0
                    self.brain.record_trade_result(d.symbol, pnl, won)
                    state.positions.remove(main)
                    state.last_close_time = time.time()
                    # Terfi
                    if state.spms:
                        self._promote_oldest_spm(state)
                    log.info(
                        f"[{d.symbol}] MAIN kapatildi "
                        f"${pnl:+.2f} | {d.reason}"
                    )
                    logs.append(
                        f"CLOSE {d.symbol} #{main.ticket} ${pnl:+.2f}"
                    )

        # ── KISMI KAPAT ──────────────────────────────────────────
        elif d.action == "PARTIAL_CLOSE":
            main = state.main
            if main and main.profit > 0:
                close_lot = round(main.lot * 0.5, 2)
                close_lot = max(cfg.MIN_LOT, close_lot)
                ok = self.bridge.close_partial(main.ticket, close_lot)
                if ok:
                    partial_pnl = main.profit * 0.5
                    state.kasa += partial_pnl
                    main.partial_done = True
                    log.info(
                        f"[{d.symbol}] Kismi kapat {close_lot}lot "
                        f"kasa+${partial_pnl:.2f}"
                    )
                    logs.append(
                        f"PARTIAL {d.symbol} #{main.ticket}"
                    )

        # ── SPM ACMA (bagimsiz karar) ────────────────────────────
        if d.open_spm and d.spm_dir and d.spm_lot > 0:
            main = state.main
            if main:
                layer = len(state.spms) + 1
                self._open_spm(
                    state, d.spm_dir, d.spm_lot, layer,
                    main.ticket, d.spm_reason,
                )
                logs.append(
                    f"SPM{layer} {d.symbol} {d.spm_dir} {d.spm_lot}lot"
                )

        # ── FIFO KARARI ──────────────────────────────────────────
        fifo_logs = self._handle_fifo(state, d)
        logs.extend(fifo_logs)

        return logs

    # =================================================================
    # SPM ACMA
    # =================================================================

    def _open_spm(self, state: SymbolState, direction: str, lot: float,
                   layer: int, parent_ticket: int, reason: str):
        """SPM (grid) pozisyon acma."""
        lot = max(cfg.MIN_LOT, min(cfg.MAX_LOT_PER_SYMBOL, lot))
        ticket = self.bridge.open_position(
            symbol    = state.symbol,
            direction = direction,
            lot       = lot,
            role      = "SPM",
            layer     = layer,
        )
        if ticket:
            pos = OpenPosition(
                ticket    = ticket,
                symbol    = state.symbol,
                direction = direction,
                lot       = lot,
                open_price= self._get_price(state.symbol, direction),
                open_time = time.time(),
                role      = f"SPM{layer}",
            )
            state.positions.append(pos)
            log.info(
                f"[{state.symbol}] SPM{layer} {direction} {lot}lot "
                f"#{ticket} | {reason}"
            )

    # =================================================================
    # FIFO YONETIMI
    # =================================================================

    def _handle_fifo(self, state: SymbolState, d: TradeDecision) -> List[str]:
        """
        Brain'in FIFO kararini uygula.
        Brain "CLOSE_MAIN", "CLOSE_WORST_SPM", "EARLY_EXIT" veya "HOLD" diyebilir.
        """
        logs = []
        action = d.fifo_action

        if action == "CLOSE_MAIN":
            main = state.main
            if not main:
                return logs
            # Net hesap
            spm_total = state.kasa + sum(
                p.profit for p in state.spms if p.profit > 0
            )
            net = spm_total + (main.profit if main.profit < 0 else 0)
            log.info(
                f"[{state.symbol}] FIFO CLOSE_MAIN: "
                f"Net=${net:.2f} | {d.fifo_reason}"
            )
            ok = self.bridge.close_position(main.ticket)
            if ok:
                pnl = main.profit
                self.brain.record_trade_result(
                    state.symbol, pnl + state.kasa, pnl + state.kasa > 0,
                )
                state.positions.remove(main)
                state.kasa = 0.0
                state.last_close_time = time.time()
                if state.spms:
                    self._promote_oldest_spm(state)
                log.info(
                    f"[{state.symbol}] FIFO MAIN kapatildi ${pnl:+.2f}"
                )
                logs.append(
                    f"FIFO {state.symbol} MAIN ${pnl:+.2f}"
                )

        elif action == "CLOSE_WORST_SPM":
            worst = min(state.spms, key=lambda p: p.profit, default=None)
            if worst and state.kasa >= 2.0:
                ok = self.bridge.close_position(worst.ticket)
                if ok:
                    state.kasa += worst.profit  # Negatifse kasa azalir
                    state.positions.remove(worst)
                    state.last_close_time = time.time()
                    log.info(
                        f"[{state.symbol}] FIFO YOL-A worst SPM "
                        f"kapatildi ${worst.profit:+.2f}"
                    )
                    logs.append(
                        f"FIFO_A {state.symbol} worst_spm "
                        f"${worst.profit:+.2f}"
                    )

        elif action == "EARLY_EXIT":
            # Brain standart $5'dan once cikmak istiyor
            main = state.main
            if main:
                spm_total = state.kasa + sum(
                    p.profit for p in state.spms
                )
                net = spm_total + main.profit
                if net > 0:
                    log.info(
                        f"[{state.symbol}] ERKEN CIKIS: "
                        f"Net=${net:.2f} | {d.fifo_reason}"
                    )
                    ok = self.bridge.close_position(main.ticket)
                    if ok:
                        pnl = main.profit
                        self.brain.record_trade_result(
                            state.symbol, net, net > 0,
                        )
                        state.positions.remove(main)
                        state.kasa = 0.0
                        state.last_close_time = time.time()
                        if state.spms:
                            self._promote_oldest_spm(state)
                        logs.append(
                            f"EARLY_EXIT {state.symbol} net=${net:.2f}"
                        )

        return logs

    # =================================================================
    # TICK MANAGEMENT (Basitlestirilmis — SpeedAgent agir isi yapar)
    # =================================================================

    def tick_management(self, symbol: str, m15=None, h1=None,
                         sig_candle_dir: str = "") -> List[str]:
        """
        Her tick'te pozisyon durumu guncelleme.

        v4.0'da basitlestirildi:
        - Peak drop ve mum donus artik SpeedAgent'ta
        - Burasi sadece profit/peak gunceller ve acil DD kontrol eder
        - SpeedAgent kararlari execute_agent_decisions() ile ayri yurutulur

        Args:
            symbol         : Islem sembolu
            m15            : M15 DataFrame (opsiyonel, SpeedAgent'a iletilir)
            h1             : H1 DataFrame (opsiyonel)
            sig_candle_dir : Mum yonu (opsiyonel, SpeedAgent icin)

        Returns:
            Log mesajlari (genellikle bos — SpeedAgent ayri isler)
        """
        logs = []
        state = self.states.get(symbol)
        if not state or not state.positions:
            return logs

        # ── ACIL DD KONTROLU (her zaman aktif, son savunma) ──────
        acc = self.bridge.get_account()
        balance = acc.get("balance", 0)
        equity = acc.get("equity", 0)
        dd = max(
            0,
            (balance - equity) / (balance + 1e-9) * 100,
        )

        emergency_dd = cfg.CLAUDE_HARD_LIMITS.get("emergency_close_dd", 35.0)
        if dd >= emergency_dd:
            log.warning(
                f"[{symbol}] ACIL DD {dd:.1f}% — "
                f"tum pozisyonlar kapatiliyor"
            )
            total_pnl = 0.0
            for pos in list(state.positions):
                ok = self.bridge.close_position(pos.ticket)
                if ok:
                    total_pnl += pos.profit
            self.brain.record_trade_result(symbol, total_pnl, total_pnl > 0)
            state.positions.clear()
            state.kasa = 0.0
            state.last_close_time = time.time()
            return [f"EMERGENCY_CLOSE {symbol} DD={dd:.1f}%"]

        # ── PROFIT / PEAK GUNCELLEME ─────────────────────────────
        for pos in list(state.positions):
            raw = next(
                (
                    p for p in self.bridge.get_positions(symbol)
                    if p["ticket"] == pos.ticket
                ),
                None,
            )
            if not raw:
                # Pozisyon artik MT5'te yok — temizle
                state.positions.remove(pos)
                state.last_close_time = time.time()
                continue

            pos.profit = raw["profit"]
            pos.lot = raw.get("volume", pos.lot)

            if pos.profit > pos.peak_profit:
                pos.peak_profit = pos.profit

        return logs

    # =================================================================
    # YARDIMCI METODLAR
    # =================================================================

    def _calculate_final_lot(self, base_lot: float, symbol: str) -> float:
        """
        Adaptif lot hesaplama.

        final_lot = base_lot * master_multiplier

        Master multiplier: MasterAgent tarafindan set edilir.
        Risk multiplier: RiskAgent.validate_open() icinde uygulanir.

        Args:
            base_lot : Temel lot miktari
            symbol   : Sembol (gelecekte sembol-bazli ayar icin)

        Returns:
            Hesaplanmis lot (0 ise islem durdurulmus demek)
        """
        final = base_lot * self.master_lot_multiplier
        final = round(final, 2)
        final = max(0.0, final)  # 0 = durdur
        return final

    def _check_cooldown(self, symbol: str) -> float:
        """
        Cooldown kontrolu — kapatmadan sonra bekleme suresi.

        Args:
            symbol: Kontrol edilecek sembol

        Returns:
            Kalan cooldown suresi (saniye). 0 = hazir.
        """
        state = self.states.get(symbol)
        if not state:
            return 0.0

        if state.last_close_time <= 0:
            return 0.0

        elapsed = time.time() - state.last_close_time
        remaining = cfg.TRADE_COOLDOWN_SECONDS - elapsed

        return max(0.0, remaining)

    def _get_positions_dict_for_risk(self) -> Dict[str, list]:
        """
        RiskAgent.validate_open() icin pozisyon dict'i olustur.

        Returns:
            {sembol: [OpenPosition, ...]} formati
        """
        result = {}
        for sym, state in self.states.items():
            if state.positions:
                result[sym] = list(state.positions)
        return result

    def _refresh_all(self):
        """Tum pozisyonlari MT5'ten guncelle."""
        for sym in cfg.SYMBOLS:
            state = self.states.get(sym)
            if not state:
                continue

            raw_positions = self.bridge.get_positions(sym)
            existing = {p.ticket: p for p in state.positions}

            new_list = []
            for r in raw_positions:
                t = r["ticket"]
                if t in existing:
                    existing[t].profit = r["profit"]
                    existing[t].lot    = r.get("volume", existing[t].lot)
                    new_list.append(existing[t])
                # else: bridge'den gelen bilinmeyen pozisyon — ignore
            state.positions = new_list

    def _promote_oldest_spm(self, state: SymbolState):
        """En eski zarardaki SPM -> MAIN terfi."""
        spms = sorted(state.spms, key=lambda p: p.open_time)
        if not spms:
            return
        losing = [p for p in spms if p.profit < 0]
        candidate = losing[0] if losing else spms[0]
        old_role = candidate.role
        candidate.role = "MAIN"
        # SPM'leri yeniden numaralandir
        remaining = sorted(
            [p for p in state.positions if p.role.startswith("SPM")],
            key=lambda x: x.open_time,
        )
        for i, p in enumerate(remaining):
            p.role = f"SPM{i+1}"
        log.info(
            f"[{state.symbol}] TERFI: {old_role} "
            f"#{candidate.ticket} -> MAIN"
        )

    def _get_price(self, symbol: str, direction: str) -> float:
        """MT5'ten guncel fiyat al."""
        try:
            import MetaTrader5 as mt5
            tick = mt5.symbol_info_tick(symbol)
            if tick:
                return tick.ask if direction == "BUY" else tick.bid
        except Exception:
            pass
        return 0.0

    def get_active_positions_dict(self) -> dict:
        """Brain'e / Dashboard'a sunulacak pozisyon formati."""
        result = {}
        for sym, state in self.states.items():
            if state.positions:
                result[sym] = state.to_dict()
        return result

    def get_state(self, symbol: str) -> Optional[SymbolState]:
        """Sembol durumunu dondur."""
        return self.states.get(symbol)

    def pop_closed_positions(self) -> List[dict]:
        """Son kapanan pozisyon detaylarini al ve temizle (Telegram icin)."""
        closed = self._last_closed.copy()
        self._last_closed.clear()
        return closed

    def get_all_states_summary(self) -> dict:
        """
        Tum sembol durumlarinin ozeti.
        Dashboard ve loglama icin kullanilir.
        """
        summary = {
            "master_lot_multiplier": self.master_lot_multiplier,
            "active_symbols": [],
            "total_positions": 0,
            "total_pnl": 0.0,
            "total_kasa": 0.0,
        }

        for sym, state in self.states.items():
            if state.positions:
                summary["active_symbols"].append(sym)
                summary["total_positions"] += len(state.positions)
                summary["total_pnl"] += state.total_pnl
                summary["total_kasa"] += state.kasa

        return summary
