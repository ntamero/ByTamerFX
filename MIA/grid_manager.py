"""
MIA v5.0 — Grid Position Manager
BytamerFX EA PositionManager.mqh'den port edildi (v3.8.0)

Her aktif sembol için bir GridManager instance çalışır.
Tick hızında (~1s) çalışır, API çağrısı yapmaz (tamamen lokal).

Pipeline (EA OnTick sırası):
  1. refresh_positions()          — MT5'den pozisyon oku
  2. check_margin_emergency()     — Margin < %150 → acil kapat
  3. manage_profitable(new_bar)   — Mum TP + peak drop + partial close
  4. manage_breakeven_lock()      — Sanal breakeven kilidi
  5. manage_spm_system()          — SPM1→SPM2 kademeli grid
  6. check_fifo_target()          — Çift yollu FIFO settlement
  7. check_net_settlement()       — Kasa + en kötü >= $5
  8. check_rescue_hedge()         — Kurtarma hedge açma
  9. manage_hedge()               — Hedge akıllı kapama
  10. manage_dca()                — DCA yönetimi
  11. check_deadlock()            — Kilitlenme tespiti

Grid kararları AgentDecision olarak döner → Arbitrator üzerinden Executor'a gider.
Kapama kararları otomatik (koruma), açma kararları Brain'in veto'suna tabi.

Copyright 2026, By T@MER — https://www.bytamer.com
"""

import time
import math
import logging
from dataclasses import dataclass, field
from typing import List, Dict, Optional, Tuple

import config as cfg
from symbol_profiles import SymbolProfile
from lot_calculator import LotCalculator

log = logging.getLogger("Grid")


# =====================================================================
# VERİ YAPILARI
# =====================================================================

@dataclass
class GridPosition:
    """Tek bir pozisyonun grid state'i."""
    ticket: int
    symbol: str
    direction: str          # "BUY" / "SELL"
    role: str               # "MAIN" / "SPM1" / "SPM2" / "DCA" / "HEDGE"
    spm_layer: int = 0      # 0=MAIN, 1=SPM1, 2=SPM2
    parent_ticket: int = 0  # DCA/SPM: bağlı olduğu ANA ticket
    volume: float = 0.0
    open_price: float = 0.0
    profit: float = 0.0
    open_time: float = 0.0
    peak_profit: float = 0.0
    partial_closed: bool = False
    breakeven_locked: bool = False
    comment: str = ""

    @property
    def is_buy(self) -> bool:
        return self.direction == "BUY"

    @property
    def is_profitable(self) -> bool:
        return self.profit > 0

    @property
    def age_sec(self) -> float:
        return time.time() - self.open_time if self.open_time > 0 else 0


@dataclass
class FIFOSummary:
    """FIFO/Grid durumu özeti — dashboard ve Brain için."""
    kasa: float = 0.0              # Kapatılan SPM kârları ($)
    net: float = 0.0               # kasa + ANA kayıp
    target: float = 5.0            # FIFO hedef ($)
    active_grid_dir: str = "NONE"  # Aktif grid yönü
    legacy_grid_dir: str = "NONE"  # Eski grid yönü
    vol_regime: str = "NORMAL"     # LOW / NORMAL / HIGH / EXTREME
    main_profit: float = 0.0
    spm_count: int = 0
    hedge_count: int = 0
    dca_count: int = 0
    total_positions: int = 0
    total_pnl: float = 0.0
    spm_open_profit: float = 0.0   # Açık SPM toplam kâr


# =====================================================================
# GRID MANAGER — ANA MOTOR
# =====================================================================

class GridManager:
    """
    Sembol bazlı pozisyon yönetim motoru.
    EA CPositionManager OnTick pipeline'ının Python portu.

    Kural:
      - on_tick() her saniye çağrılır
      - Kapama kararları (koruma) → yüksek öncelikli AgentDecision
      - Açma kararları (SPM/DCA/HEDGE) → düşük öncelikli, Brain veto edebilir
      - Tüm kararlar dict listesi olarak döner (agents.py'deki AgentDecision'a çevrilir)
    """

    def __init__(
        self,
        symbol: str,
        profile: SymbolProfile,
        lot_calc: LotCalculator,
    ):
        self.symbol = symbol
        self.profile = profile
        self.lot_calc = lot_calc

        # ── Pozisyon state ──
        self.positions: List[GridPosition] = []
        self._main_ticket: int = 0

        # ── FIFO state ──
        self.kasa: float = 0.0                # Kapatılan SPM kârları
        self.kasa_count: int = 0              # Kapatılan SPM sayısı
        self.total_cashed: float = 0.0        # Toplam kasa (tüm döngüler)

        # ── Grid state ──
        self._grid_direction: str = "NONE"    # H1 trend yönü
        self._vol_regime: str = "NORMAL"      # LOW / NORMAL / HIGH / EXTREME
        self._active_grid_dir: str = "NONE"   # Bi-dir: aktif yön
        self._legacy_grid_dir: str = "NONE"   # Bi-dir: eski yön

        # ── Zamanlama ──
        self._start_time: float = time.time()
        self._last_trend_check: float = 0.0
        self._last_spm_open: float = 0.0
        self._last_hedge_close: float = 0.0
        self._last_net_settle: float = 0.0
        self._last_deadlock_check: float = 0.0

        # ── Deadlock state ──
        self._deadlock_start: float = 0.0
        self._deadlock_last_net: float = 0.0

        # ── Peak tracking (ticket → peak profit) ──
        self._peaks: Dict[int, float] = {}

        # ── Spread baseline ──
        self._spread_baseline: float = 0.0
        self._spread_samples: int = 0

    # ═════════════════════════════════════════════════════════
    # ANA PIPELINE — EA OnTick() birebir port
    # ═════════════════════════════════════════════════════════

    def on_tick(
        self,
        positions_raw: List[dict],
        account: dict,
        candle_dir: str,
        h1_data: Optional[dict] = None,
        signal_score: int = 0,
        signal_dir: str = "NONE",
        new_bar: bool = False,
        spread_ratio: float = 1.0,
        news_blocked: bool = False,
    ) -> List[dict]:
        """
        Grid pipeline — her saniye çağrılır.

        Args:
            positions_raw: MT5'den gelen pozisyon listesi [{ticket, direction, lot, profit, ...}]
            account:       {balance, equity, margin_level, ...}
            candle_dir:    "BUY" / "SELL" / "NONE" (M15 önceki mum yönü)
            h1_data:       H1 verisi (trend hesabı için)
            signal_score:  Sinyal motoru skoru (0-100)
            signal_dir:    Sinyal yönü
            new_bar:       Yeni M15 bar mı?
            spread_ratio:  Mevcut spread / baseline oranı
            news_blocked:  Haber bloğu aktif mi?

        Returns:
            List[dict] — AgentDecision parametreleri listesi
        """
        decisions: List[dict] = []
        now = time.time()

        # ── 1. Pozisyonları yenile ──
        self._refresh_positions(positions_raw)

        # ── Pozisyon yoksa state temizle ──
        if not self.positions:
            self._reset_if_empty()
            return decisions

        # ── 2a. v3.8.0 EQUITY KORUMA — equity < %30 bakiye → TÜM KAPAT ──
        equity = account.get("equity", 0)
        balance = account.get("balance", 0)
        if balance > 0 and equity > 0:
            equity_ratio = (equity / balance) * 100.0
            if equity_ratio < cfg.MAX_ACCOUNT_DD_PCT:  # %30 (v3.8.0: MaxDrawdownPercent)
                log.critical(
                    f"[{self.symbol}] !!! EQUITY ACİL !!! "
                    f"Equity=${equity:.2f} / Balance=${balance:.2f} = "
                    f"{equity_ratio:.1f}% < {cfg.MAX_ACCOUNT_DD_PCT}%"
                )
                decisions += self._emergency_close_all(
                    f"EQUITY_ACİL_{equity_ratio:.0f}%"
                )
                return decisions

        # ── 2b. Margin < %150 → TÜM KAPAT ──
        margin = account.get("margin_level", 9999)
        if margin < 150 and margin > 0:
            decisions += self._emergency_close_all("MARGIN_ACIL: %{:.0f}".format(margin))
            return decisions

        # ── 2c. v3.8.0 SEMBOL KAYIP LİMİTİ — toplam PnL > -%50 bakiye → KAPAT ──
        if balance > 0:
            total_pnl = sum(p.profit for p in self.positions)
            max_symbol_loss = -(balance * 0.50)
            if total_pnl < max_symbol_loss:
                loss_pct = (abs(total_pnl) / balance) * 100.0
                log.critical(
                    f"[{self.symbol}] !!! SEMBOL KAYIP LİMİT !!! "
                    f"ToplamPnL=${total_pnl:.2f} ({loss_pct:.1f}% bakiye)"
                )
                decisions += self._emergency_close_all(
                    f"SEMBOL_LIMIT_{loss_pct:.0f}%"
                )
                return decisions

        # ── 3. Kârlı pozisyon yönetimi ──
        decisions += self._manage_profitable(candle_dir, new_bar)

        # ── 4. Breakeven kilidi ──
        decisions += self._manage_breakeven()

        # ── 5. SPM sistemi (grid) ──
        if cfg.GRID_ENABLED and not news_blocked:
            # Warmup kontrolü
            if now - self._start_time >= cfg.GRID_WARMUP_SEC:
                # H1 trend güncelle (her 120 saniyede)
                if h1_data and now - self._last_trend_check >= cfg.GRID_TREND_CHECK_SEC:
                    self._check_trend_direction(h1_data)
                    self._last_trend_check = now

                decisions += self._manage_spm_system(
                    account, candle_dir, signal_score, signal_dir,
                    spread_ratio, news_blocked
                )

        # ── 6. FIFO hedef kontrolü ──
        decisions += self._check_fifo_target(candle_dir)

        # ── 7. Net settlement ──
        if now - self._last_net_settle >= 10:
            decisions += self._check_net_settlement()
            self._last_net_settle = now

        # ── 8. Rescue hedge ──
        if cfg.GRID_ENABLED and not news_blocked:
            decisions += self._check_rescue_hedge(account, candle_dir, signal_dir)

        # ── 9. Hedge yönetimi ──
        decisions += self._manage_hedge(candle_dir, account)

        # ── 10. Deadlock kontrolü ──
        if now - self._last_deadlock_check >= cfg.DEADLOCK_CHECK_SEC:
            decisions += self._check_deadlock(account)
            self._last_deadlock_check = now

        return decisions

    # ═════════════════════════════════════════════════════════
    # ADIM 1: POZİSYON YENİLEME
    # ═════════════════════════════════════════════════════════

    def _refresh_positions(self, positions_raw: List[dict]):
        """MT5 pozisyonlarını GridPosition'a çevir ve rolleri ata."""
        new_positions: List[GridPosition] = []

        for p in positions_raw:
            ticket = p.get("ticket", 0)
            comment = p.get("comment", "")

            # Rol tespiti: comment'ten parse et
            role, layer = self._parse_role_from_comment(comment)

            gp = GridPosition(
                ticket=ticket,
                symbol=self.symbol,
                direction=p.get("direction", "BUY"),
                role=role,
                spm_layer=layer,
                volume=p.get("lot", 0.0),
                open_price=p.get("open_price", 0.0),
                profit=p.get("profit", 0.0),
                open_time=p.get("open_time", 0.0),
                comment=comment,
            )

            # Peak tracking güncelle
            prev_peak = self._peaks.get(ticket, 0.0)
            gp.peak_profit = max(prev_peak, gp.profit)
            self._peaks[ticket] = gp.peak_profit

            new_positions.append(gp)

        self.positions = new_positions

        # Eski peak'leri temizle
        active_tickets = {p.ticket for p in self.positions}
        self._peaks = {t: v for t, v in self._peaks.items() if t in active_tickets}

        # Main ticket güncelle
        main = self.main
        self._main_ticket = main.ticket if main else 0

    def _parse_role_from_comment(self, comment: str) -> Tuple[str, int]:
        """
        MT5 comment'inden rol ve katman parse et.
        Format: MIA_MAIN_XAUUSD, MIA_SPM_1_XAUUSD, MIA_HEDGE_XAUUSD, MIA_DCA_XAUUSD
        """
        c = comment.upper()
        if "SPM" in c:
            # MIA_SPM_2_XAUUSD → SPM2, layer=2
            parts = c.split("_")
            layer = 1
            for i, part in enumerate(parts):
                if part == "SPM" and i + 1 < len(parts):
                    try:
                        layer = int(parts[i + 1])
                    except ValueError:
                        layer = 1
                    break
            return f"SPM{layer}", layer
        if "HEDGE" in c:
            return "HEDGE", 0
        if "DCA" in c:
            return "DCA", 0
        # Default = MAIN (veya tanınmayan comment)
        return "MAIN", 0

    # ═════════════════════════════════════════════════════════
    # ADIM 3: KÂRLI POZİSYON YÖNETİMİ
    # EA ManageKarliPozisyonlar() birebir port
    # ═════════════════════════════════════════════════════════

    def _manage_profitable(self, candle_dir: str, new_bar: bool) -> List[dict]:
        """Kârlı pozisyonlar: partial close, mum TP, peak drop, trend-hold."""
        decisions: List[dict] = []
        p = self.profile

        for pos in self.positions:
            # HEDGE korumalı — burada işlenmez
            if pos.role == "HEDGE":
                continue

            if pos.profit <= 0:
                continue

            # ── Partial close (60%/40%) ──
            if not pos.partial_closed and pos.profit >= 3.0:
                close_vol = round(pos.volume * 0.60, 2)
                if close_vol >= self.lot_calc.min_lot:
                    decisions.append(self._decision(
                        action="GRID_PARTIAL_CLOSE",
                        priority=72,
                        lot=close_vol,
                        ticket=pos.ticket,
                        reason=f"Partial close %60: +${pos.profit:.2f}",
                    ))

            # ── SPM/DCA: Mum dönüşü anlık kapama ──
            if pos.role.startswith("SPM") or pos.role == "DCA":
                if pos.profit >= p.min_close_profit:
                    is_opposite = (
                        (pos.is_buy and candle_dir == "SELL") or
                        (not pos.is_buy and candle_dir == "BUY")
                    )
                    if is_opposite:
                        decisions.append(self._decision(
                            action="GRID_CLOSE",
                            priority=75,
                            ticket=pos.ticket,
                            reason=f"Mum dönüşü TP: {pos.role} +${pos.profit:.2f}",
                            add_to_kasa=True,
                        ))
                        continue

            # ── Smart close target (trend bazlı) ──
            close_target = self._get_smart_close_target(pos.role)

            if pos.profit >= close_target:
                # Trend-hold logic: güçlü trendde uzat
                if self._is_strong_trend() and self._pos_with_trend(pos):
                    is_candle_opposite = (
                        (pos.is_buy and candle_dir == "SELL") or
                        (not pos.is_buy and candle_dir == "BUY")
                    )
                    if is_candle_opposite:
                        # Mum döndü → hemen kapat
                        decisions.append(self._decision(
                            action="GRID_CLOSE",
                            priority=75,
                            ticket=pos.ticket,
                            reason=f"Trend-hold mum dönüşü: +${pos.profit:.2f}",
                            add_to_kasa=(pos.role != "MAIN"),
                        ))
                    else:
                        # Trend devam — tight peak drop (%15) ile tut
                        if pos.peak_profit > close_target:
                            drop_pct = (pos.peak_profit - pos.profit) / pos.peak_profit
                            if drop_pct >= 0.15:
                                decisions.append(self._decision(
                                    action="GRID_CLOSE",
                                    priority=76,
                                    ticket=pos.ticket,
                                    reason=f"Tight peak drop %{drop_pct*100:.0f}: +${pos.profit:.2f}",
                                    add_to_kasa=(pos.role != "MAIN"),
                                ))
                else:
                    # Normal kapat
                    decisions.append(self._decision(
                        action="GRID_CLOSE",
                        priority=74,
                        ticket=pos.ticket,
                        reason=f"TP hedef: {pos.role} +${pos.profit:.2f} (hedef=${close_target:.2f})",
                        add_to_kasa=(pos.role != "MAIN"),
                    ))
                continue

            # ── Normal peak drop ──
            if pos.peak_profit >= cfg.PEAK_PROFIT_MIN:
                drop_threshold = self._get_peak_drop_pct(pos.role)
                if pos.peak_profit > 0:
                    drop_pct = (pos.peak_profit - pos.profit) / pos.peak_profit
                    if drop_pct >= drop_threshold:
                        decisions.append(self._decision(
                            action="PEAK_DROP",
                            priority=90,
                            ticket=pos.ticket,
                            reason=f"Peak drop %{drop_pct*100:.0f} (eşik %{drop_threshold*100:.0f}): "
                                   f"peak=${pos.peak_profit:.2f} now=${pos.profit:.2f}",
                            add_to_kasa=(pos.role != "MAIN"),
                        ))

        return decisions

    # ═════════════════════════════════════════════════════════
    # ADIM 4: BREAKEVEN KİLİDİ
    # ═════════════════════════════════════════════════════════

    def _manage_breakeven(self) -> List[dict]:
        """Peak profit $2+ olan pozisyonlar için sanal breakeven."""
        # Breakeven bilgi amaçlı — SL koymuyoruz (EA kuralı: SL=0)
        # Peak drop mekanizması zaten koruma sağlıyor
        return []

    # ═════════════════════════════════════════════════════════
    # ADIM 5: SPM SİSTEMİ (GRID)
    # EA ManageSPMSystem() → ManageTrendGrid()
    # ═════════════════════════════════════════════════════════

    def _manage_spm_system(
        self,
        account: dict,
        candle_dir: str,
        signal_score: int,
        signal_dir: str,
        spread_ratio: float,
        news_blocked: bool,
    ) -> List[dict]:
        """SPM grid sistemi: SPM1 (cost-avg) + SPM2 (ters yön)."""
        decisions: List[dict] = []
        main = self.main
        if not main:
            return decisions

        now = time.time()
        p = self.profile
        balance = account.get("balance", 0)
        margin_level = account.get("margin_level", 9999)

        # ── Ortak ön koşullar ──
        if balance < cfg.MIN_BALANCE_FLOOR:
            return decisions
        # v3.8.0: Margin guard %300 (SPM/DCA açılmaması için)
        if margin_level < 300:
            return decisions
        if spread_ratio > cfg.SPREAD_MAX_RATIO:
            return decisions

        total_open_lots = sum(pos.volume for pos in self.positions)
        if total_open_lots >= cfg.MAX_TOTAL_LOTS:
            return decisions

        # Cooldown — acil kayıpta bypass
        cooldown = self._get_adaptive_cooldown()
        emergency_loss = main.profit <= (p.spm_trigger_loss * 2)
        if emergency_loss:
            # Acil durum: minimum 5s cooldown yeter
            if now - self._last_spm_open < 5:
                return decisions
        else:
            if now - self._last_spm_open < cooldown:
                return decisions

        # ── SPM1: ANA zararda → aynı yön (cost-averaging) ──
        spm_count = self._get_spm_count()
        if spm_count == 0 and main.profit <= p.spm_trigger_loss:
            # SPM1 aç — ANA yönünde
            spm_lot = self.lot_calc.calculate_spm_lot(main.volume, 1)
            decisions.append(self._decision(
                action="GRID_OPEN_SPM",
                priority=45,
                lot=spm_lot,
                direction=main.direction,
                reason=f"SPM1 tetik: ANA kayıp ${main.profit:.2f} <= ${p.spm_trigger_loss:.2f}",
                metadata={
                    "layer": 1,
                    "parent_ticket": main.ticket,
                    "role": "SPM1",
                },
            ))
            self._last_spm_open = now
            return decisions

        # ── SPM2: SPM1 zararda → akıllı yön seçimi ──
        spm1 = self._get_spm_by_layer(1)
        if spm1 and spm_count < 2 and spm1.profit <= p.spm2_trigger_loss:
            # Acil durum: ANA zarar büyükse yön desteği gerekmez
            urgent = main.profit <= (p.spm_trigger_loss * 1.5)  # -$7.5+ kayıpta acil
            reverse_dir = "SELL" if main.is_buy else "BUY"
            has_support = self._has_direction_support(
                reverse_dir, candle_dir, signal_dir, signal_score
            )
            # Akıllı yön: Mum+sinyal hala ANA yönde güçlüyse → DCA (aynı yön)
            # Değilse → hedge (ters yön)
            main_dir_strong = (
                candle_dir == main.direction and
                signal_dir == main.direction and
                signal_score >= 50
            )
            if has_support or urgent:
                spm2_dir = main.direction if main_dir_strong else reverse_dir
                spm2_lot = self.lot_calc.calculate_spm_lot(main.volume, 2)
                decisions.append(self._decision(
                    action="GRID_OPEN_SPM",
                    priority=55 if urgent else 43,
                    lot=spm2_lot,
                    direction=spm2_dir,
                    reason=f"SPM2 {'ACİL' if urgent else 'tetik'}: SPM1 kayıp ${spm1.profit:.2f}, ANA ${main.profit:.2f}",
                    metadata={
                        "layer": 2,
                        "parent_ticket": main.ticket,
                        "role": "SPM2",
                    },
                ))
                self._last_spm_open = now

        return decisions

    # ═════════════════════════════════════════════════════════
    # ADIM 6: FIFO HEDEF — ÇİFT YOLLU
    # EA CheckFIFOTarget() birebir port
    # ═════════════════════════════════════════════════════════

    def _check_fifo_target(self, candle_dir: str) -> List[dict]:
        """FIFO çift yollu settlement: Path A (mum dönüşü) + Path B (net hedef)."""
        decisions: List[dict] = []
        main = self.main
        if not main:
            return decisions

        p = self.profile
        spm_list = self.spms

        # ── YOLA: Mum döndü + ANA zararda → en kötü SPM'i kapat ──
        if spm_list and main.profit < 0 and self.kasa >= 2.0:
            main_with_candle = (
                (main.is_buy and candle_dir == "BUY") or
                (not main.is_buy and candle_dir == "SELL")
            )
            if main_with_candle:
                worst = self._get_worst_spm()
                if worst:
                    decisions.append(self._decision(
                        action="GRID_FIFO_CLOSE",
                        priority=80,
                        ticket=worst.ticket,
                        reason=f"FIFO Yol-A: Mum dönüşü + ANA zararda → en kötü SPM kapat "
                               f"(kasa=${self.kasa:.2f})",
                        add_to_kasa=True,
                    ))
                    return decisions

        # ── YOL B: Net hedef → ANA kapat + SPM promosyon ──
        spm_open_profit = sum(
            pos.profit for pos in self.positions
            if pos.role.startswith("SPM") or pos.role in ("DCA", "HEDGE")
            if pos.profit > 0
        )
        net = self.kasa + spm_open_profit + main.profit

        if net >= p.fifo_net_target:
            decisions.append(self._decision(
                action="GRID_FIFO_CLOSE",
                priority=80,
                ticket=main.ticket,
                reason=f"FIFO Yol-B: Net ${net:.2f} >= hedef ${p.fifo_net_target:.2f} → ANA kapat",
                metadata={
                    "fifo_close_ana": True,
                    "promote_after": True,
                    "net_profit": net,
                },
            ))

        return decisions

    # ═════════════════════════════════════════════════════════
    # ADIM 7: NET SETTLEMENT
    # EA CheckNetSettlement() birebir port
    # ═════════════════════════════════════════════════════════

    def _check_net_settlement(self) -> List[dict]:
        """Kasa + en kötü pozisyon kaybı >= FIFO hedef → en kötüyü kapat."""
        decisions: List[dict] = []
        p = self.profile

        if self.kasa < 3.0:
            return decisions

        # En kötü SPM/DCA bul (MAIN ve HEDGE hariç)
        worst = self._get_worst_spm()
        if not worst:
            return decisions

        net = self.kasa + worst.profit  # worst.profit negatif
        if net >= p.fifo_net_target:
            decisions.append(self._decision(
                action="GRID_NET_SETTLE",
                priority=78,
                ticket=worst.ticket,
                reason=f"Net Settlement: kasa=${self.kasa:.2f} + en_kötü=${worst.profit:.2f} "
                       f"= ${net:.2f} >= ${p.fifo_net_target:.2f}",
                metadata={
                    "net_profit": net,
                    "clear_kasa": True,
                },
            ))

        return decisions

    # ═════════════════════════════════════════════════════════
    # ADIM 8: RESCUE HEDGE
    # EA CheckRescueHedge() birebir port
    # ═════════════════════════════════════════════════════════

    def _check_rescue_hedge(
        self,
        account: dict,
        candle_dir: str,
        signal_dir: str,
    ) -> List[dict]:
        """SPM2 ağır zararda → kurtarma hedge aç."""
        decisions: List[dict] = []
        main = self.main
        if not main:
            return decisions

        p = self.profile
        now = time.time()

        # Zaten hedge varsa aç
        if self._get_hedge_count() > 0:
            return decisions

        # Son hedge kapatmadan cooldown (acil durumda kısa)
        total_loss = sum(pos.profit for pos in self.positions)
        hedge_cooldown = 15 if total_loss <= (p.spm_trigger_loss * 3) else 30
        if now - self._last_hedge_close < hedge_cooldown:
            return decisions

        # Margin kontrolü
        margin = account.get("margin_level", 9999)
        if margin < 150:
            return decisions

        # SPM2 zarar kontrolü VEYA toplam zarar çok büyükse direkt hedge
        spm2 = self._get_spm_by_layer(2)
        critical_loss = total_loss <= (p.rescue_hedge_threshold * 2)  # -$14+ toplam
        if spm2:
            if spm2.profit > p.rescue_hedge_threshold and not critical_loss:
                return decisions
        elif not critical_loss:
            # SPM2 yok ve toplam zarar da kritik değil → bekle
            return decisions

        # ── v3.8.0: Akıllı hedge yönü ──
        # Varsayılan: ANA'nın tersi
        hedge_dir = "SELL" if main.is_buy else "BUY"

        # v3.8.0 FIX 5: Güçlü trend ANA yönünde → HEDGE AÇMA (gereksiz)
        # Trend güçlü + ANA yönünde → ANA toparlanacak, hedge zararlı olur
        if self._is_strong_trend() and self._grid_direction == main.direction:
            log.info(
                f"[{self.symbol}] HEDGE İPTAL: Güçlü trend ANA yönünde "
                f"({self._grid_direction}) → hedge gereksiz"
            )
            return decisions

        # Hedge yönü ANA ile aynı olmamalı
        if hedge_dir == main.direction:
            log.info(f"[{self.symbol}] HEDGE İPTAL: Oylama ANA yönü gösteriyor")
            return decisions

        # ── Lot hesabı ──
        hedge_lot = round(main.volume * p.rescue_hedge_lot_mult, 2)
        hedge_lot = max(self.lot_calc.min_lot, hedge_lot)

        decisions.append(self._decision(
            action="GRID_OPEN_HEDGE",
            priority=60,
            lot=hedge_lot,
            direction=hedge_dir,
            reason=f"Rescue Hedge: SPM2 kayıp ${spm2.profit:.2f} <= ${p.rescue_hedge_threshold:.2f}",
            metadata={"role": "HEDGE"},
        ))

        return decisions

    # ═════════════════════════════════════════════════════════
    # ADIM 9: HEDGE YÖNETİMİ
    # EA ManageHedgePositions() birebir port — 5 kapama koşulu
    # ═════════════════════════════════════════════════════════

    def _manage_hedge(self, candle_dir: str, account: dict) -> List[dict]:
        """Hedge akıllı kapama: 5 farklı koşul."""
        decisions: List[dict] = []
        hedges = self.hedges
        if not hedges:
            return decisions

        main = self.main
        p = self.profile
        balance = account.get("balance", 200)

        for hedge in hedges:
            # ── Koşul 1: ANA yok ──
            if not main:
                if hedge.profit >= p.min_close_profit:
                    decisions.append(self._decision(
                        action="GRID_CLOSE",
                        priority=75,
                        ticket=hedge.ticket,
                        reason=f"Hedge kapama: ANA yok + kârda +${hedge.profit:.2f}",
                        add_to_kasa=True,
                    ))
                else:
                    # Zarardaki hedge → ANA'ya promot et
                    decisions.append(self._decision(
                        action="GRID_PROMOTE",
                        priority=70,
                        ticket=hedge.ticket,
                        reason=f"Hedge→ANA promosyon: ANA yok, hedge zararda ${hedge.profit:.2f}",
                        metadata={"promote_to": "MAIN"},
                    ))
                continue

            # ── Koşul 2: ANA + HEDGE net >= $5 ──
            net = main.profit + hedge.profit
            if net >= 5.0 and hedge.is_profitable:
                decisions.append(self._decision(
                    action="GRID_CLOSE",
                    priority=75,
                    ticket=hedge.ticket,
                    reason=f"Hedge kapama: ANA+HEDGE net ${net:.2f} >= $5",
                    add_to_kasa=True,
                ))
                continue

            # ── Koşul 3: Trend ANA yönüne döndü ──
            if self._grid_direction == main.direction and hedge.profit >= 0:
                if main.profit > p.spm_trigger_loss / 2:
                    decisions.append(self._decision(
                        action="GRID_CLOSE",
                        priority=73,
                        ticket=hedge.ticket,
                        reason=f"Hedge kapama: Trend ANA yönüne döndü, ANA toparlanıyor",
                        add_to_kasa=True,
                    ))
                    continue

            # ── Koşul 4: Hedge peak drop %25 ──
            if hedge.peak_profit >= 8.0:
                if hedge.peak_profit > 0:
                    drop = (hedge.peak_profit - hedge.profit) / hedge.peak_profit
                    if drop >= 0.25:
                        decisions.append(self._decision(
                            action="GRID_CLOSE",
                            priority=74,
                            ticket=hedge.ticket,
                            reason=f"Hedge peak drop %{drop*100:.0f}: "
                                   f"peak=${hedge.peak_profit:.2f} now=${hedge.profit:.2f}",
                            add_to_kasa=True,
                        ))
                        continue

            # ── Koşul 5: Deadlock — 10dk + zararda VEYA kayıp > %20 bakiye ──
            if hedge.age_sec > 600 and hedge.profit < 0:
                decisions.append(self._decision(
                    action="GRID_CLOSE",
                    priority=72,
                    ticket=hedge.ticket,
                    reason=f"Hedge deadlock: {hedge.age_sec/60:.0f}dk + zararda ${hedge.profit:.2f}",
                ))
                continue

            if balance > 0 and abs(hedge.profit) > balance * 0.20:
                decisions.append(self._decision(
                    action="GRID_CLOSE",
                    priority=90,
                    ticket=hedge.ticket,
                    reason=f"Hedge acil: kayıp ${hedge.profit:.2f} > %20 bakiye",
                ))

        return decisions

    # ═════════════════════════════════════════════════════════
    # ADIM 10: DEADLOCK TESPİTİ
    # EA CheckDeadlock() — sadece uyarı, kapama yok
    # ═════════════════════════════════════════════════════════

    def _check_deadlock(self, account: dict) -> List[dict]:
        """Kilitlenme tespiti: 5dk net değişim < $0.50 → uyarı."""
        decisions: List[dict] = []
        if len(self.positions) < 2:
            self._deadlock_start = 0
            return decisions

        now = time.time()
        current_net = sum(p.profit for p in self.positions)
        balance = account.get("balance", 200)

        if self._deadlock_start == 0:
            self._deadlock_start = now
            self._deadlock_last_net = current_net
            return decisions

        elapsed = now - self._deadlock_start
        if elapsed >= cfg.DEADLOCK_TIMEOUT_SEC:
            change = abs(current_net - self._deadlock_last_net)
            if change < cfg.DEADLOCK_MIN_CHANGE and current_net < 0:
                loss_pct = abs(current_net) / (balance + 1e-9) * 100
                if loss_pct > 15:
                    decisions.append(self._decision(
                        action="GRID_DEADLOCK_WARN",
                        priority=30,
                        reason=f"KİLİTLENME UYARI: {elapsed/60:.0f}dk net değişim "
                               f"${change:.2f} < ${cfg.DEADLOCK_MIN_CHANGE:.2f} "
                               f"(kayıp %{loss_pct:.1f})",
                    ))
                    log.warning(
                        f"[{self.symbol}] DEADLOCK: {elapsed:.0f}s net=${current_net:.2f} "
                        f"change=${change:.2f} loss={loss_pct:.1f}%"
                    )

            # Reset
            self._deadlock_start = now
            self._deadlock_last_net = current_net

        return decisions

    # ═════════════════════════════════════════════════════════
    # YARDIMCI — TREND
    # ═════════════════════════════════════════════════════════

    def _check_trend_direction(self, h1_data: dict):
        """
        H1 3-kaynak trend oylama: EMA + MACD + ADX.
        EA CheckTrendDirection() portu.
        """
        ema_dir = h1_data.get("ema_trend", "NONE")       # "BUY" / "SELL" / "NONE"
        macd_dir = h1_data.get("macd_dir", "NONE")
        adx_val = h1_data.get("adx", 0)
        adx_plus = h1_data.get("adx_plus", 0)
        adx_minus = h1_data.get("adx_minus", 0)
        atr = h1_data.get("atr", 0)
        atr_avg = h1_data.get("atr_avg", 1)

        # ADX yönü
        adx_dir = "NONE"
        if adx_val >= 20:
            adx_dir = "BUY" if adx_plus > adx_minus else "SELL"

        # 3 kaynak oylama
        votes = {"BUY": 0, "SELL": 0}
        for d in (ema_dir, macd_dir, adx_dir):
            if d in votes:
                votes[d] += 1

        # Çoğunluk yönü
        if votes["BUY"] >= 2:
            self._grid_direction = "BUY"
        elif votes["SELL"] >= 2:
            self._grid_direction = "SELL"
        # else: önceki yön korunur

        # ── Volatilite rejimi güncelle ──
        if atr_avg > 0:
            ratio = atr / atr_avg
            if ratio < 0.8:
                self._vol_regime = "LOW"
            elif ratio < 1.5:
                self._vol_regime = "NORMAL"
            elif ratio < 2.5:
                self._vol_regime = "HIGH"
            else:
                self._vol_regime = "EXTREME"

    def _is_strong_trend(self) -> bool:
        return self._grid_direction in ("BUY", "SELL")

    def _pos_with_trend(self, pos: GridPosition) -> bool:
        return pos.direction == self._grid_direction

    # ═════════════════════════════════════════════════════════
    # YARDIMCI — GRID SPACING, COOLDOWN, LOT
    # ═════════════════════════════════════════════════════════

    def _get_adaptive_cooldown(self) -> float:
        """Volatilite rejimine göre SPM cooldown.
        EXTREME = en hızlı (tam da koruma gerektiği an!)
        """
        base = self.profile.spm_cooldown_sec
        regime = self._vol_regime
        if regime == "LOW":
            return base * 1.5
        if regime == "NORMAL":
            return base
        if regime == "HIGH":
            return base * 0.5
        # EXTREME — acil koruma modu, en hızlı çalış!
        return max(5, base * 0.25)

    def _get_smart_close_target(self, role: str) -> float:
        """Trend gücüne göre akıllı TP hedefi ($)."""
        p = self.profile
        if self._is_strong_trend():
            return p.candle_close_strong
        if self._grid_direction != "NONE":
            return p.candle_close_moderate
        return p.candle_close_weak

    def _get_peak_drop_pct(self, role: str) -> float:
        """Rol bazlı peak drop eşiği."""
        if role == "MAIN":
            return 0.35
        if role.startswith("SPM"):
            return 0.45
        if role == "DCA":
            return 0.55
        return 0.35

    def _has_direction_support(
        self, direction: str, candle_dir: str, signal_dir: str, signal_score: int
    ) -> bool:
        """En az 1 kaynak yön desteği veriyor mu? EA HasDirectionSupport()"""
        votes = 0
        if self._grid_direction == direction:
            votes += 1
        if signal_dir == direction and signal_score >= cfg.SIGNAL_MIN_THRESHOLD:
            votes += 1
        if candle_dir == direction:
            votes += 1
        return votes >= 1

    # ═════════════════════════════════════════════════════════
    # YARDIMCI — POZİSYON ERİŞİM
    # ═════════════════════════════════════════════════════════

    @property
    def main(self) -> Optional[GridPosition]:
        for p in self.positions:
            if p.role == "MAIN":
                return p
        return None

    @property
    def spms(self) -> List[GridPosition]:
        return [p for p in self.positions if p.role.startswith("SPM")]

    @property
    def hedges(self) -> List[GridPosition]:
        return [p for p in self.positions if p.role == "HEDGE"]

    def _get_spm_count(self) -> int:
        return len(self.spms)

    def _get_hedge_count(self) -> int:
        return len(self.hedges)

    def _get_spm_by_layer(self, layer: int) -> Optional[GridPosition]:
        for p in self.positions:
            if p.role == f"SPM{layer}":
                return p
        return None

    def _get_worst_spm(self) -> Optional[GridPosition]:
        """En kötü (en zararlı) SPM/DCA bul — MAIN ve HEDGE hariç."""
        candidates = [
            p for p in self.positions
            if p.role.startswith("SPM") or p.role == "DCA"
        ]
        if not candidates:
            return None
        return min(candidates, key=lambda p: p.profit)

    # ═════════════════════════════════════════════════════════
    # YARDIMCI — KARAR OLUŞTURMA
    # ═════════════════════════════════════════════════════════

    def _decision(
        self,
        action: str,
        priority: int,
        reason: str = "",
        ticket: int = 0,
        lot: float = 0.0,
        direction: str = "",
        add_to_kasa: bool = False,
        metadata: Optional[dict] = None,
    ) -> dict:
        """AgentDecision uyumlu dict oluştur."""
        d = {
            "agent_name": "GridAgent",
            "action": action,
            "symbol": self.symbol,
            "priority": priority,
            "lot": lot,
            "reason": reason,
            "urgency": "NOW",
            "metadata": metadata or {},
        }
        if ticket:
            d["metadata"]["ticket"] = ticket
        if direction:
            d["metadata"]["direction"] = direction
        if add_to_kasa:
            d["metadata"]["add_to_kasa"] = True
        return d

    def _emergency_close_all(self, reason: str) -> List[dict]:
        """Tüm pozisyonları acil kapat."""
        decisions = []
        for pos in self.positions:
            decisions.append(self._decision(
                action="EMERGENCY_CLOSE",
                priority=100,
                ticket=pos.ticket,
                reason=f"ACİL KAPAT ({reason}): {pos.role} {pos.direction} "
                       f"${pos.profit:.2f}",
            ))
        return decisions

    def _reset_if_empty(self):
        """Pozisyon kalmadığında state temizle."""
        if self.kasa > 0:
            self.total_cashed += self.kasa
            log.info(f"[{self.symbol}] Kasa sıfırlandı: +${self.kasa:.2f} → toplam=${self.total_cashed:.2f}")
            self.kasa = 0
            self.kasa_count = 0
        self._deadlock_start = 0
        self._main_ticket = 0

    # ═════════════════════════════════════════════════════════
    # KASA YÖNETİMİ (Executor tarafından çağrılır)
    # ═════════════════════════════════════════════════════════

    def add_to_kasa(self, amount: float):
        """Kapatılan SPM kârını kasaya ekle."""
        if amount > 0:
            self.kasa += amount
            self.kasa_count += 1
            log.info(f"[{self.symbol}] Kasa +${amount:.2f} → toplam=${self.kasa:.2f} ({self.kasa_count} kapanış)")

    def clear_kasa(self, net_profit: float = 0.0):
        """FIFO döngüsü tamamlandı — kasayı sıfırla."""
        self.total_cashed += net_profit if net_profit > 0 else self.kasa
        log.info(f"[{self.symbol}] FIFO döngüsü: kasa=${self.kasa:.2f} → sıfır (toplam=${self.total_cashed:.2f})")
        self.kasa = 0
        self.kasa_count = 0

    # ═════════════════════════════════════════════════════════
    # FIFO ÖZET (Dashboard ve Brain için)
    # ═════════════════════════════════════════════════════════

    def get_fifo_summary(self) -> FIFOSummary:
        """Grid/FIFO durum özeti."""
        main = self.main
        main_profit = main.profit if main else 0.0
        spm_open = sum(p.profit for p in self.spms if p.profit > 0)

        return FIFOSummary(
            kasa=self.kasa,
            net=self.kasa + spm_open + main_profit,
            target=self.profile.fifo_net_target,
            active_grid_dir=self._active_grid_dir or self._grid_direction,
            legacy_grid_dir=self._legacy_grid_dir,
            vol_regime=self._vol_regime,
            main_profit=main_profit,
            spm_count=self._get_spm_count(),
            hedge_count=self._get_hedge_count(),
            dca_count=len([p for p in self.positions if p.role == "DCA"]),
            total_positions=len(self.positions),
            total_pnl=sum(p.profit for p in self.positions),
            spm_open_profit=spm_open,
        )
