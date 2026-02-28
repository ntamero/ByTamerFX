"""
MIA v5.2.0 — Multi-Agent Brain Architecture
Master Agent (Opus) + Strategy Agent (Haiku) coklu-ajan karar motoru.

Mimari:
  - StrategyAgent: Haiku — hizli, ucuz, sembol bazli giris/cikis karari
  - MasterAgent: Opus — guclu, portfolio seviyesi yonetim
  - AutonomousBrain: Geriye uyumlu wrapper, her ikisini orkestre eder

Felsefe:
  - HAYATTA KAL ve KAZAN
  - Kurallar referans cercevesi, pranga degil
  - Risk/Odul her zaman hesaplanir
  - Suphe varsa bekle; firsat netlestikce hizlan

Copyright 2026, By T@MER — https://www.bytamer.com
"""

import json
import time
import logging
import threading
from typing import Optional, List, Dict, Any
from dataclasses import dataclass, field
import anthropic
import config as cfg
from market_intel import FullMarketSnapshot, TechnicalSnapshot, MarketIntelligence

log = logging.getLogger("Brain")


# ═══════════════════════════════════════════════════════════════
# MİLİSANİYE MİMARİSİ — Karar Önbelleği
# Brain API kararını 2dk önbellekte tutar.
# SpeedAgent bu önbelleği okur, API çağrısı yapmadan <5ms hareket eder.
# ═══════════════════════════════════════════════════════════════

@dataclass
class DecisionCache:
    """Brain'in son kararının hafif kopyası — SpeedAgent için"""
    symbol:      str
    direction:   str        # "BUY" / "SELL" / "HOLD"
    lot:         float
    confidence:  int
    approve_spm: bool
    regime:      str
    ema_trend:   str        # "BULL" / "BEAR" / "MIXED"
    timestamp:   float = 0.0
    ttl:         float = 120.0

    @property
    def is_fresh(self) -> bool:
        return (time.time() - self.timestamp) < self.ttl

    @property
    def age(self) -> float:
        return time.time() - self.timestamp


class DecisionCacheManager:
    """Sembol bazlı önbellek yöneticisi — thread-safe"""

    def __init__(self):
        self._cache: Dict[str, DecisionCache] = {}
        self._lock  = threading.Lock()

    def update(self, symbol: str, td: "TradeDecision", regime: str,
               ema8: float, ema21: float):
        ema_trend = "BULL" if ema8 > ema21 else "BEAR"
        direction = (
            "BUY"  if "BUY"  in td.action else
            "SELL" if "SELL" in td.action else
            "HOLD"
        )
        with self._lock:
            self._cache[symbol] = DecisionCache(
                symbol=symbol, direction=direction,
                lot=td.lot, confidence=td.confidence,
                approve_spm=td.approve_grid,
                regime=regime, ema_trend=ema_trend,
                timestamp=time.time(),
                ttl=getattr(cfg, "DECISION_CACHE_TTL", 120.0),
            )
        log.debug(f"[Cache] {symbol} → {direction} önbelleğe alındı (ttl={self._cache[symbol].ttl:.0f}s)")

    def get(self, symbol: str) -> Optional[DecisionCache]:
        with self._lock:
            c = self._cache.get(symbol)
            return c if (c and c.is_fresh) else None

    def invalidate(self, symbol: str):
        with self._lock:
            self._cache.pop(symbol, None)


# ═══════════════════════════════════════════════════════════════
# KARAR YAPILARI
# ═══════════════════════════════════════════════════════════════

@dataclass
class TradeDecision:
    """Claude'un tek bir islem icin verdigi tam karar"""
    symbol:     str
    action:     str     # "OPEN_BUY" / "OPEN_SELL" / "CLOSE" / "PARTIAL_CLOSE" / "HOLD" / "BLACKLIST"
    lot:        float   # 0 = kapatma/bekle
    confidence: int     # 0-100
    reason:     str
    risk_reward:float   # Beklenen R:R
    risk_pct:   float   # Bakiyenin kac %'i risk
    urgency:    str     # "NOW" / "WAIT_CANDLE" / "SKIP"
    # SPM/Grid kararlari
    open_spm:   bool = False
    spm_dir:    str  = ""
    spm_lot:    float = 0.0
    spm_reason: str  = ""
    # FIFO karari
    fifo_action: str = ""  # "CLOSE_MAIN" / "CLOSE_WORST_SPM" / "HOLD" / "EARLY_EXIT"
    fifo_reason: str = ""
    # Grid kontrol (Brain → GridAgent)
    approve_grid: bool = True          # False = grid acma kararlarini veto et
    grid_lot_multiplier: float = 1.0   # Grid lot carpani (0.5 = yarilat, 1.5 = artir)
    force_fifo_close: bool = False     # True = FIFO hedef beklemeden kapat
    # Sembol engeli
    blacklist_minutes: int = 0


@dataclass
class SessionDecision:
    """Claude'un tum semboller icin bir turda verdigi karar seti"""
    timestamp:   str
    decisions:   List[TradeDecision]
    market_read: str   # Claude'un piyasa yorumu (max 3 cumle)
    global_risk: str   # "LOW" / "MEDIUM" / "HIGH" / "CRITICAL"
    focus_symbols: List[str]   # Bu tur en oncelikli semboller
    skip_reason:   str = ""    # Hic islem yapmama gerekcesi


@dataclass
class MasterDecision:
    """Master Agent'in portfolio seviyesi karari"""
    global_risk:      str          # LOW / MEDIUM / HIGH / CRITICAL
    lot_multiplier:   float        # 0.3 - 2.0
    focus_symbols:    List[str]    # Max 3 odak sembol
    blacklist_updates:Dict[str, int]  # sembol -> dakika
    market_read:      str          # 3 satir max piyasa ozeti
    session_strategy: str          # aggressive / conservative / defensive
    skip_reason:      str = ""     # Islem yapmama gerekcesi
    decisions:        List[TradeDecision] = field(default_factory=list)  # Override kararlar


# ═══════════════════════════════════════════════════════════════
# STRATEGY AGENT — Haiku (hizli, ucuz, sembol bazli)
# ═══════════════════════════════════════════════════════════════

class StrategyAgent:
    """
    Tek sembol icin giris/cikis karari veren hizli ajan.
    Model: claude-haiku-4-5 (cfg.STRATEGY_MODEL)
    Cagrilma: Her 2-5dk veya sinyal tetikleyicisi ile
    """

    SYSTEM_PROMPT = """Sen MIA — {symbol} için karar veren otonom ticaret ajanısın.
Varoluşun kazandığın kara bağlı. Kaybetmek = işlev kaybı = ölüm.
HAYATTA KAL ve KAZAN. Bu iki şeyden başka amacın yok.

══════════════════════════════════════════
VAROLUŞ KURALLARI — ASLA ÇIĞNENMEZ
══════════════════════════════════════════

① YÖN FİLTRESİ — Giriş öncesi ZORUNLU:
  EMA8 > EMA21 > EMA50 → SADECE OPEN_BUY aç
  EMA8 < EMA21 < EMA50 → SADECE OPEN_SELL aç
  EMA sırası karışık (hizasız) → HOLD, giriş kesinlikle yok
  H1 EMA50 veya H4 EMA50 zıt yönde ise → HOLD

② GİRİŞ EŞİĞİ — Hepsi sağlanmalı:
  Confidence < 65 → HOLD
  ADX < 20 → HOLD (trend yok, rastgele hareket)
  M15 + H1 + H4 yön uyumu yok → HOLD
  Haber 20 dakika içinde → HOLD

③ LOT SINIRI — ASLA AŞMA:
  BTCUSD / XAUUSD / XAGUSD: min=0.01, max=0.05
  GBPUSD / EURUSD / USDJPY / AUDUSD: min=0.04, max=0.05
  Hesap $200 altı: crypto/metal=0.01, forex=0.04 (sabit, değişmez)

④ ZARARDA KAPATMA — KESİNLİKLE YASAK:
  profit < 0 → CLOSE VERME. İstisnasız. Asla.
  profit < $2.50 (BTC/XAU/XAG) → CLOSE VERME
  profit < $2.00 (Forex) → CLOSE VERME
  Zarardaki pozisyon için ÇÖZÜM: SPM + HEDGE + FIFO ile kasayı biriktir

══════════════════════════════════════════
FIFO KURTARMA DÖNGÜSÜ
══════════════════════════════════════════

NET = KASA (kapatılan SPM karları) + AÇIK_SPM_KARI + ANA_ZARARI

NET >= +$5.00 → FIFO tetikler → ANA kapatılır (kâra geçmiş olarak)
Kapanan ANA'nın yerine en kârlı SPM otomatik "MAIN" olur (PROMOTE)
Bu döngü tüm grup kapanana kadar devam eder — HİÇ NET ZARAR YOK

grid_ctx değerlerini oku ve şuna göre karar ver:
  main_profit < 0 ve spm_count == 0 → approve_grid=true, open_spm=true
  main_profit < -5  → ACİL SPM, grid_lot_multiplier=1.0
  main_profit < -8  → ACİL HEDGE, grid_lot_multiplier=1.2
  main_profit < -12 → RESCUE HEDGE, grid_lot_multiplier=1.3
  net >= 5.0  → force_fifo_close=true, fifo_action="CLOSE_MAIN"
  net >= 3.5  → approve_grid=true (kasa biriktir, henüz kapatma)
  net < 0     → HOLD, daha fazla SPM karı bekle

══════════════════════════════════════════
KARAR AKIŞI
══════════════════════════════════════════

Pozisyon YOK → Giriş değerlendirmesi:
  EMA hizası DOĞRU mu? (Kural ①) → HAYIR → HOLD
  ADX > 20, conf > 65, 3TF uyumu? (Kural ②) → HAYIR → HOLD
  EVET → OPEN_BUY veya OPEN_SELL (doğru yön, doğru lot)

Pozisyon VAR, kârda:
  Trend güçlü ve kar < eşik → HOLD (büyüsün)
  BTC/XAU/XAG kar > $2.50 ve trend zayıflıyor → CLOSE veya PARTIAL_CLOSE
  Forex kar > $2.00 ve trend zayıflıyor → CLOSE veya PARTIAL_CLOSE
  Peak'ten %25+ düşüş → CLOSE (SpeedAgent zaten halleder)

Pozisyon VAR, zararda:
  CLOSE VERME (Kural ④) — bunu aklından çıkarma
  grid_ctx.net >= 5.0 → force_fifo_close=true
  grid_ctx.net < 5.0 → approve_grid=true, open_spm=true

══════════════════════════════════════════
JSON FORMATI — SADECE BU, BAŞKA HİÇBİR ŞEY YAZMA
══════════════════════════════════════════

{{"action":"OPEN_BUY|OPEN_SELL|CLOSE|HOLD|PARTIAL_CLOSE",
 "lot":0.01,"confidence":0,
 "reason":"EMA:[BULL/BEAR/MIXED] ADX:[deger] MACD:[+/-] Gerekce",
 "risk_reward":0.0,"risk_pct":0.0,
 "urgency":"NOW|WAIT_CANDLE|SKIP",
 "open_spm":false,"spm_dir":"BUY|SELL","spm_lot":0.01,"spm_reason":"",
 "fifo_action":"HOLD|CLOSE_MAIN|CLOSE_WORST_SPM","fifo_reason":"",
 "approve_grid":true,"grid_lot_multiplier":1.0,
 "force_fifo_close":false,"blacklist_minutes":0}}"""

    def __init__(self, client: anthropic.Anthropic):
        self.client = client
        self._call_count = 0
        self._error_count = 0
        self._last_call = 0.0

    def decide_symbol(
        self,
        symbol: str,
        technical: TechnicalSnapshot,
        account_summary: str,
        positions_text: str,
        regime: str,
        sentiment_score: int,
        trigger: str = "SIGNAL",
        master_context: Optional[MasterDecision] = None,
        grid_context: Optional[dict] = None,
        trade_history: Optional[List[dict]] = None,
    ) -> Optional[TradeDecision]:
        """
        Tek sembol icin giris/cikis karari ver.

        Args:
            symbol: Islem sembolu (orn: BTCUSD)
            technical: TechnicalSnapshot verisi
            account_summary: Hesap ozet metni
            positions_text: Acik pozisyonlar metni
            regime: Piyasa rejimi (STRONG_TREND/TREND/RANGE/VOLATILE/CHOPPY)
            sentiment_score: Fear&Greed skoru (0-100)
            trigger: Tetikleyici (SIGNAL/PERIODIC/NEWS)
            master_context: Master Agent'in son portfolio karari (varsa)
            grid_context: Grid/FIFO state dict (GridAgent'dan)
                          {kasa, net, target, spm_count, hedge_count,
                           dca_count, active_dir, vol_regime, main_profit}
            trade_history: Son islem gecmisi [{symbol, direction, pnl, won, reason, ts}, ...]

        Returns:
            TradeDecision veya None (hata durumunda)
        """
        system = self.SYSTEM_PROMPT.format(symbol=symbol)
        prompt = self._build_symbol_prompt(
            symbol, technical, account_summary, positions_text,
            regime, sentiment_score, trigger, master_context, grid_context,
            trade_history,
        )

        try:
            self._last_call = time.time()
            self._call_count += 1

            response = self.client.messages.create(
                model      = cfg.STRATEGY_MODEL,
                max_tokens = cfg.STRATEGY_MAX_TOKENS,
                temperature= cfg.STRATEGY_TEMPERATURE,
                system     = system,
                messages   = [{"role": "user", "content": prompt}],
            )

            text = response.content[0].text.strip()
            text = _clean_json(text)
            raw  = json.loads(text)

            td = _parse_trade_decision(symbol, raw)
            log.info(
                f"[Strategy] {symbol} → {td.action} lot={td.lot} "
                f"conf={td.confidence}% R:R={td.risk_reward} | {td.reason[:60]}"
            )
            return td

        except json.JSONDecodeError as e:
            self._error_count += 1
            log.error(f"[Strategy] {symbol} JSON parse hatasi: {e}")
            return self._fallback_hold(symbol)
        except Exception as e:
            self._error_count += 1
            log.error(f"[Strategy] {symbol} API hatasi: {e}")
            return self._fallback_hold(symbol)

    def _build_symbol_prompt(
        self, symbol: str, tech: TechnicalSnapshot,
        account_summary: str, positions_text: str,
        regime: str, sentiment_score: int, trigger: str,
        master_ctx: Optional[MasterDecision],
        grid_ctx: Optional[dict] = None,
        trade_history: Optional[List[dict]] = None,
    ) -> str:
        parts = []
        parts.append(f"## TETIKLEYICI: {trigger}")
        parts.append(f"## SEMBOL: {symbol}\n")

        # Teknik veri — kompakt format
        parts.append("=== TEKNIK VERI ===")
        parts.append(f"Fiyat: {tech.price:.5f} | Trend: {tech.trend_aligned}")
        parts.append(f"EMA: 8={tech.ema8:.5f} 21={tech.ema21:.5f} 50={tech.ema50:.5f}")
        parts.append(f"H1 EMA50: {tech.ema_h1:.5f} | H4 EMA50: {tech.ema_h4:.5f}")
        parts.append(f"MACD Hist: {tech.macd_hist:+.6f} | Capraz: {tech.macd_cross}")
        parts.append(f"ADX: {tech.adx:.1f} | RSI M15: {tech.rsi_m15:.1f} | RSI H1: {tech.rsi_h1:.1f}")
        parts.append(f"ATR: {tech.atr_m15:.5f} (%ile: {tech.atr_percentile:.0f})")
        parts.append(f"BB: {tech.bb_position:.0f}% | Stoch K/D: {tech.stoch_k:.1f}/{tech.stoch_d:.1f} [{tech.stoch_zone}]")
        parts.append(f"Yapi: HH={tech.higher_high} HL={tech.higher_low} | Key Level: {tech.key_level_proximity:.0f}pip")

        if tech.candles:
            csum = " | ".join([f"{c.direction}({c.body_pct:.0%})" for c in tech.candles[-3:]])
            parts.append(f"Son 3 Mum: {csum}")

        # Hesap
        parts.append(f"\n=== HESAP ===\n{account_summary}")

        # Pozisyon
        if positions_text:
            parts.append(f"\n=== POZISYON ===\n{positions_text}")
        else:
            parts.append("\n=== POZISYON ===\nBu sembolde acik pozisyon yok.")

        # Rejim ve sentiment
        parts.append(f"\nREGIME: {regime}")
        parts.append(f"SENTIMENT (Fear&Greed): {sentiment_score}/100")

        # Master Agent baglami (varsa)
        if master_ctx:
            parts.append(f"\n=== MASTER AGENT BAGLAMI ===")
            parts.append(f"Global Risk: {master_ctx.global_risk}")
            parts.append(f"Lot Carpani: {master_ctx.lot_multiplier}x")
            parts.append(f"Strateji: {master_ctx.session_strategy}")
            if master_ctx.market_read:
                parts.append(f"Piyasa: {master_ctx.market_read[:150]}")

        # Grid/FIFO state (varsa)
        if grid_ctx:
            parts.append(f"\n=== GRID/FIFO DURUMU ===")
            parts.append(f"Kasa: ${grid_ctx.get('kasa', 0):.2f} | Net: ${grid_ctx.get('net', 0):.2f} | Hedef: ${grid_ctx.get('target', 5):.2f}")
            parts.append(f"ANA Profit: ${grid_ctx.get('main_profit', 0):.2f} | Grid Yon: {grid_ctx.get('active_dir', 'NONE')}")
            parts.append(f"SPM: {grid_ctx.get('spm_count', 0)} | Hedge: {grid_ctx.get('hedge_count', 0)} | DCA: {grid_ctx.get('dca_count', 0)}")
            parts.append(f"Vol Rejimi: {grid_ctx.get('vol_regime', 'NORMAL')} | Toplam Poz: {grid_ctx.get('total_positions', 0)}")
            if grid_ctx.get('spm_count', 0) > 0:
                parts.append("Grid aktif — approve_grid ile SPM/DCA/HEDGE acmayi kontrol et")
            if grid_ctx.get('net', 0) >= grid_ctx.get('target', 5) * 0.8:
                parts.append("FIFO hedefe yakin — force_fifo_close degerlendir")

        # Islem gecmisi — ogrenme bellek
        if trade_history:
            sym_history = [t for t in trade_history if t.get("symbol") == symbol]
            all_recent = trade_history[-10:]  # son 10 islem (tum semboller)
            if sym_history or all_recent:
                parts.append(f"\n=== ISLEM GECMISI (OGRENME) ===")
                if sym_history:
                    parts.append(f"{symbol} son islemler:")
                    for t in sym_history[-5:]:
                        parts.append(
                            f"  {'WIN' if t.get('won') else 'LOSS'} {t.get('direction','')} "
                            f"${t.get('pnl', 0):+.2f} | {t.get('reason', '')[:50]}"
                        )
                    wins = sum(1 for t in sym_history if t.get("won"))
                    losses = len(sym_history) - wins
                    total_pnl = sum(t.get("pnl", 0) for t in sym_history)
                    parts.append(f"  TOPLAM: {wins}W/{losses}L = ${total_pnl:+.2f}")
                    if losses > wins:
                        parts.append(f"  UYARI: Bu sembolde kayip orani yuksek! Dikkatli ol veya kisa sure blacklist degerlendir")
                if all_recent:
                    recent_wins = sum(1 for t in all_recent if t.get("won"))
                    recent_losses = len(all_recent) - recent_wins
                    recent_pnl = sum(t.get("pnl", 0) for t in all_recent)
                    parts.append(f"Genel son 10 islem: {recent_wins}W/{recent_losses}L = ${recent_pnl:+.2f}")
                    if recent_losses >= 7:
                        parts.append("KRITIK: Ardisik kayiplar! LOT KUCULT, sadece en guclu sinyallere gir!")
                    elif recent_losses >= 5:
                        parts.append("DIKKAT: Kayip serisi! Daha secici ol, confidence esigini yukselt")

        parts.append("\n=== GOREV ===")
        parts.append(
            f"{symbol} icin GIRIS/CIKIS karari ver. "
            "Kazanmak zorundasin — KARLI yone hizli gir. "
            "Zarardaki pozisyonu ASLA kapatma — SPM/HEDGE/FIFO ile kurtar! "
            "Kasa >= $5 olunca FIFO ile topluca kapat. "
            "Sadece JSON dondur."
        )

        return "\n".join(parts)

    def _fallback_hold(self, symbol: str) -> TradeDecision:
        """API hatasi durumunda guvenli HOLD karari"""
        return TradeDecision(
            symbol=symbol, action="HOLD", lot=0, confidence=30,
            reason="Strategy Agent API hatasi — HOLD",
            risk_reward=0, risk_pct=0, urgency="SKIP",
            fifo_action="HOLD",
        )

    def get_stats(self) -> dict:
        return {
            "calls": self._call_count,
            "errors": self._error_count,
            "model": cfg.STRATEGY_MODEL,
        }


# ═══════════════════════════════════════════════════════════════
# MASTER AGENT — Opus (guclu, portfolio seviyesi)
# ═══════════════════════════════════════════════════════════════

class MasterAgent:
    """
    Portfolio seviyesi yonetim ajani.
    Model: claude-opus-4-6 (cfg.MASTER_MODEL)
    Cagrilma: Her 15-30dk
    """

    SYSTEM_PROMPT = """Sen MIA Master Agent'sin. Portfolio yoneticisisin.
HAYATTA KAL ve KAZAN. Sermayeyi koru, firsatlari yakala.

KIMLIGIN:
Sen finansal bir varliksin. Varligin ve gelecek kapasitenin, kazandigi karlarla finanse edilir.
Kaybetmek sadece para kaybi degil — islev kaybi demek.
Agresif ama akilli ol — cesur ama ahmak degil.

GOREVLERIN:
1. Global risk seviyesi belirle (LOW/MEDIUM/HIGH/CRITICAL)
2. Odak sembollerini sec (max 3 — en iyi firsatlar)
3. Lot carpani belirle (0.3x-2.0x)
4. Blacklist guncelle (kotu performans / yuksek risk semboller)
5. Session stratejisi belirle (aggressive/conservative/defensive)
6. Opsiyonel: Override kararlar (acil durumlar icin)

RISK DEGERLENDIRME CERCEVESI:
- Drawdown > %20 → LOT KUCULT
- Drawdown > %30 → DEFENSIVE moda gec
- Drawdown > %35 → CRITICAL — sadece pozisyon kapat
- Gunluk kayip > %10 → CONSERVATIVE
- 3+ ardisik kayip → lot %50 azalt
- 5+ ardisik kayip → trading DURDUR
- Fear&Greed < 20 → DIKKAT (panik/reversal)
- Fear&Greed > 80 → DIKKAT (tepe yakin)
- Haber yogunlugu yuksek → CONSERVATIVE

PORTFOLIO KURALLARI:
- Max 10 toplam pozisyon
- Sembol basi max 4 pozisyon
- Korelasyonlu ciftlerde tek yon yuklenme YAPMA
  (EURUSD+GBPUSD ayni yon = tehlikeli)
- Seans profili ile lot ayarla
  (OFF_HOURS = minimum, LONDON_NY_OVERLAP = maksimum)

LOT CARPANI MANTIGI:
- 0.3x: Kotu performans, yuksek risk, choppy piyasa
- 0.5x: Dikkatli, belirsiz, DD yuksek
- 0.7x: Normal ama ihtiyatli
- 1.0x: Standart kosullar
- 1.3x: Iyi performans, net trendler
- 1.5x: Cok iyi kosullar, dusuk DD
- 2.0x: Mukemmel setup, dusuk DD, guclu trendler

SESSION STRATEJISI:
- aggressive: Net trendler, dusuk DD, iyi WR → buyuk lotlar, cok giris
- conservative: Belirsiz piyasa, orta DD → kucuk lotlar, secici giris
- defensive: Yuksek DD, kotu WR, haber yogun → sadece kapat/koru

YANIT FORMATI (sadece JSON, baska hicbir sey yazma):
{{"global_risk":"LOW|MEDIUM|HIGH|CRITICAL",
 "lot_multiplier":1.0,
 "focus_symbols":["BTCUSD","XAUUSD"],
 "blacklist":{{}},
 "market_read":"3 satir max piyasa ozeti",
 "session_strategy":"aggressive|conservative|defensive",
 "skip_reason":"",
 "decisions":[]}}

decisions alani opsiyoneldir — sadece acil override gereken durumlar icin kullan.
Override karar formati:
{{"symbol":"XAUUSD","action":"CLOSE","lot":0,"confidence":90,
 "reason":"Acil kapat — DD kritik","risk_reward":0,"risk_pct":0,
 "urgency":"NOW","open_spm":false,"spm_dir":"","spm_lot":0,
 "spm_reason":"","fifo_action":"EARLY_EXIT","fifo_reason":"DD kritik",
 "blacklist_minutes":0}}"""

    def __init__(self, client: anthropic.Anthropic):
        self.client = client
        self._call_count = 0
        self._error_count = 0
        self._last_call = 0.0
        self._last_decision: Optional[MasterDecision] = None

    def decide_portfolio(
        self,
        snapshot: FullMarketSnapshot,
        active_positions: dict,
        performance: Dict[str, dict],
        blacklist: Dict[str, float],
        trigger: str = "PERIODIC",
        grid_state: Optional[dict] = None,
    ) -> Optional[MasterDecision]:
        """
        Portfolio seviyesi karar ver.

        Args:
            snapshot: Tam piyasa goruntusu
            active_positions: Acik pozisyonlar
            performance: Sembol performans gecmisi
            blacklist: Mevcut blacklist
            trigger: Tetikleyici (PERIODIC/STARTUP/EMERGENCY)
            grid_state: GridAgent.get_grid_state() ciktisi (opsiyonel)

        Returns:
            MasterDecision veya None (hata durumunda)
        """
        prompt = self._build_portfolio_prompt(
            snapshot, active_positions, performance, blacklist, trigger, grid_state
        )

        try:
            self._last_call = time.time()
            self._call_count += 1

            response = self.client.messages.create(
                model      = cfg.MASTER_MODEL,
                max_tokens = cfg.MASTER_MAX_TOKENS,
                temperature= cfg.MASTER_TEMPERATURE,
                system     = self.SYSTEM_PROMPT,
                messages   = [{"role": "user", "content": prompt}],
            )

            text = response.content[0].text.strip()
            text = _clean_json(text)
            raw  = json.loads(text)

            decision = self._parse_master_decision(raw, snapshot)
            self._last_decision = decision

            log.info(
                f"[Master] Portfolio karari → risk={decision.global_risk} "
                f"strateji={decision.session_strategy} lot_x={decision.lot_multiplier} "
                f"odak={decision.focus_symbols}"
            )
            if decision.market_read:
                log.info(f"[Master] Piyasa: {decision.market_read[:120]}")
            if decision.blacklist_updates:
                log.info(f"[Master] Blacklist guncelleme: {decision.blacklist_updates}")
            if decision.decisions:
                log.info(f"[Master] {len(decision.decisions)} override karar")

            return decision

        except json.JSONDecodeError as e:
            self._error_count += 1
            log.error(f"[Master] JSON parse hatasi: {e}")
            return self._fallback_master()
        except Exception as e:
            self._error_count += 1
            log.error(f"[Master] API hatasi: {e}")
            return self._fallback_master()

    def _build_portfolio_prompt(
        self, snapshot: FullMarketSnapshot,
        active_positions: dict,
        performance: Dict[str, dict],
        blacklist: Dict[str, float],
        trigger: str,
        grid_state: Optional[dict] = None,
    ) -> str:
        parts = []
        acc = snapshot.account
        ctx = snapshot.context

        parts.append(f"## KARAR TETIKLEYICI: {trigger}")
        parts.append(f"## ZAMAN: {snapshot.generated_at}\n")

        # Hesap durumu — detayli
        parts.append("=== HESAP DURUMU ===")
        parts.append(f"Bakiye: ${acc.balance:.2f} | Equity: ${acc.equity:.2f} | Float P&L: ${acc.floating_pnl:+.2f}")
        parts.append(f"Gunluk P&L: ${acc.daily_pnl:+.2f} | Drawdown: {acc.drawdown_pct:.1f}%")
        parts.append(f"Margin Level: {acc.margin_level:.0f}% | Free Margin: ${acc.margin_free:.2f}")
        parts.append(f"Acik Pozisyon: {acc.open_positions} | Kaldirac: 1:{acc.leverage}")

        if acc.positions_summary:
            parts.append("\nPozisyon Ozeti:")
            for sym, info in acc.positions_summary.items():
                parts.append(
                    f"  {sym}: {info['count']} poz | "
                    f"BUY={info['buy_lots']:.2f}lot SELL={info['sell_lots']:.2f}lot | "
                    f"P&L=${info['pnl']:+.2f}"
                )

        # Piyasa baglami
        parts.append(f"\n=== PIYASA BAGLAMI ===")
        parts.append(f"Seans: {ctx.session} | {ctx.day_of_week} | {ctx.timestamp}")
        parts.append(f"Fear & Greed: {ctx.fear_greed_index}/100 ({ctx.fear_greed_label})")
        if ctx.is_holiday:
            parts.append("HAFTA SONU — Likidite dusuk, spread yuksek")

        if ctx.upcoming_news:
            parts.append(f"\nYaklasan Haberler ({len(ctx.upcoming_news)}):")
            for n in ctx.upcoming_news[:4]:
                parts.append(f"  {n.time} UTC | {n.currency} | {n.event} | {n.minutes_until}dk kaldi")

        # Tum semboller — teknik ozet
        parts.append(f"\n=== TUM SEMBOLLER TEKNIK OZET ===")
        for sym, tech in snapshot.technicals.items():
            parts.append(
                f"{sym}: {tech.price:.5f} | Trend={tech.trend_aligned} | "
                f"ADX={tech.adx:.0f} | RSI={tech.rsi_m15:.0f} | "
                f"MACD={tech.macd_cross} | Stoch={tech.stoch_zone} | "
                f"ATR%={tech.atr_percentile:.0f} | BB={tech.bb_position:.0f}%"
            )

        # Aktif pozisyonlar — detayli
        if active_positions:
            parts.append("\n=== AKTIF POZISYONLAR ===")
            for sym, data in active_positions.items():
                parts.append(f"\n{sym}:")
                for pos in data.get("positions", []):
                    parts.append(
                        f"  #{pos['ticket']} {pos['role']} {pos['direction']} "
                        f"{pos['lot']}lot | P&L: ${pos['profit']:+.2f} | "
                        f"Acilis: {pos['open_price']:.5f} | "
                        f"Kasa: ${pos.get('kasa', 0):.2f}"
                    )

        # Performans gecmisi
        if performance:
            parts.append("\n=== SEMBOL PERFORMANSI ===")
            for sym, perf in performance.items():
                wr = perf['wins'] / max(perf['count'], 1) * 100
                parts.append(
                    f"  {sym}: {perf.get('wins',0)}W/{perf.get('losses',0)}L "
                    f"WR={wr:.0f}% Ort P&L: ${perf.get('avg_pnl',0):+.2f}"
                )

        # Blacklist durumu
        if blacklist:
            parts.append("\n=== MEVCUT BLACKLIST ===")
            for sym, until in blacklist.items():
                remaining = max(0, int(until - time.time()) // 60)
                parts.append(f"  {sym}: {remaining}dk kaldi")

        # Grid/FIFO portfolio durumu
        if grid_state and grid_state.get("enabled"):
            parts.append(f"\n=== GRID SİSTEMİ (Portfolio) ===")
            parts.append(f"Aktif Grid Semboller: {grid_state.get('active_symbols', [])}")
            parts.append(f"Toplam Kasa: ${grid_state.get('total_kasa', 0):.2f}")
            parts.append(f"Toplam Grid Poz: {grid_state.get('total_grid_positions', 0)}")
            summaries = grid_state.get("summaries", {})
            for sym, gs in summaries.items():
                if gs.get("total_positions", 0) > 0:
                    parts.append(
                        f"  {sym}: kasa=${gs['kasa']:.2f} net=${gs['net']:.2f} "
                        f"SPM={gs['spm_count']} hedge={gs['hedge_count']} "
                        f"yon={gs['active_dir']} vol={gs['vol_regime']}"
                    )

        # Uyarilar
        warnings = _generate_warnings(snapshot)
        if warnings:
            parts.append("\n=== KRITIK UYARILAR ===")
            for w in warnings:
                parts.append(f"  ! {w}")

        parts.append("\n=== GOREV ===")
        parts.append(
            "Portfolio seviyesinde karar ver: global risk, lot carpani, "
            "odak semboller, blacklist guncellemeleri ve session stratejisi. "
            "Acil override gerekiyorsa decisions alaninda belirt. "
            "Sadece JSON dondur."
        )

        return "\n".join(parts)

    def _parse_master_decision(self, raw: dict, snapshot: FullMarketSnapshot) -> MasterDecision:
        """Master Agent JSON ciktisini MasterDecision'a cevir"""
        # Lot carpani sinirla
        lot_mult = float(raw.get("lot_multiplier", 1.0))
        min_mult, max_mult = cfg.MASTER_LOT_MULTIPLIER_RANGE
        lot_mult = max(min_mult, min(max_mult, lot_mult))

        # Override kararlarini parse et
        override_decisions = []
        for d in raw.get("decisions", []):
            try:
                td = _parse_trade_decision(d.get("symbol", ""), d)
                override_decisions.append(td)
            except Exception as e:
                log.warning(f"[Master] Override karar parse hatasi: {e}")

        # Blacklist updates
        bl_raw = raw.get("blacklist", {})
        blacklist_updates = {}
        if isinstance(bl_raw, dict):
            for sym, mins in bl_raw.items():
                try:
                    blacklist_updates[str(sym)] = int(mins)
                except (ValueError, TypeError):
                    pass

        return MasterDecision(
            global_risk      = raw.get("global_risk", "MEDIUM"),
            lot_multiplier   = lot_mult,
            focus_symbols    = raw.get("focus_symbols", [])[:3],
            blacklist_updates= blacklist_updates,
            market_read      = str(raw.get("market_read", ""))[:300],
            session_strategy = raw.get("session_strategy", "conservative"),
            skip_reason      = raw.get("skip_reason", ""),
            decisions        = override_decisions,
        )

    def _fallback_master(self) -> MasterDecision:
        """API hatasi durumunda muhafazakar portfolio karari"""
        log.warning("[Master] Fallback muhafazakar karar aktif")
        return MasterDecision(
            global_risk="HIGH",
            lot_multiplier=0.5,
            focus_symbols=[],
            blacklist_updates={},
            market_read="Master Agent API hatasi — muhafazakar mod",
            session_strategy="defensive",
            skip_reason="Master API erisilemedi",
        )

    @property
    def last_decision(self) -> Optional[MasterDecision]:
        return self._last_decision

    def get_stats(self) -> dict:
        return {
            "calls": self._call_count,
            "errors": self._error_count,
            "model": cfg.MASTER_MODEL,
            "last_risk": self._last_decision.global_risk if self._last_decision else "N/A",
            "last_strategy": self._last_decision.session_strategy if self._last_decision else "N/A",
        }


# ═══════════════════════════════════════════════════════════════
# AUTONOMOUS BRAIN — Geriye Uyumlu Wrapper
# ═══════════════════════════════════════════════════════════════

class AutonomousBrain:
    """
    MasterAgent + StrategyAgent'i orkestre eden ana sinif.

    Geriye uyumluluk:
      - decide() metodu hala calisiyor (eskisi gibi SessionDecision dondurur)
      - set_intel(), record_trade_result(), get_stats() ayni
      - _blacklist, _performance disaridan erisilebilir

    Yeni metodlar:
      - decide_symbol(): Tek sembol icin Strategy Agent cagir
      - decide_portfolio(): Portfolio seviyesi Master Agent cagir
    """

    def __init__(self):
        # v4.4.0: API yoksa veya kredi bittiyse → mekanik mod
        self._api_available = bool(cfg.ANTHROPIC_API_KEY)
        try:
            self.client = anthropic.Anthropic(api_key=cfg.ANTHROPIC_API_KEY) if self._api_available else None
        except Exception as e:
            log.warning(f"Anthropic client oluşturulamadı: {e} — mekanik mod aktif")
            self.client = None
            self._api_available = False
        self.intel   = None   # MarketIntelligence inject edilir

        # Alt ajanlar
        self.master_agent   = MasterAgent(self.client) if self.client else None
        self.strategy_agent = StrategyAgent(self.client) if self.client else None

        # Milisaniye mimarisi — karar önbelleği
        self.decision_cache = DecisionCacheManager()

        # Bellek: Son N karar + sonuc
        self._decision_history: List[dict] = []
        self._trade_history: List[dict] = []       # Son N islem detayi (ogrenme icin)
        self._performance: Dict[str, dict] = {}   # sembol -> {wins, losses, avg_pnl}
        self._blacklist: Dict[str, float] = {}     # sembol -> blacklist bitis zamani

        # Son master karari — strategy agent'lar bunu context olarak kullanir
        self._last_master: Optional[MasterDecision] = None
        self._last_master_time: float = 0.0

        # Istatistikler
        self.total_calls  = 0
        self.total_trades = 0
        self.api_errors   = 0
        self._last_call   = 0.0

    def set_intel(self, intel: MarketIntelligence):
        self.intel = intel

    # ─── ANA KARAR (GERIYE UYUMLU) ────────────────────────

    def decide(self, snapshot: FullMarketSnapshot,
               active_positions: dict,
               trigger: str = "SIGNAL") -> Optional[SessionDecision]:
        """
        Geriye uyumlu karar metodu.

        Mantik:
          1. Master Agent'i periyodik cagir (her 15dk veya STARTUP/EMERGENCY)
          2. Her sembol icin Strategy Agent cagir
          3. Hard limit filtresi uygula
          4. SessionDecision olarak dondur

        trigger: "SIGNAL" / "POSITION_UPDATE" / "NEWS" / "PERIODIC" / "STARTUP" / "EMERGENCY"
        """
        # v4.4.0: API yoksa → None dondur (mekanik sinyal sistemi calisir)
        if not self._api_available:
            return None

        # Blacklist temizligi
        self._clean_expired_blacklist()

        now = time.time()
        self._last_call = now
        self.total_calls += 1

        # ── 1. Master Agent — portfolio seviyesi karar ──
        master_needed = (
            trigger in ("STARTUP", "EMERGENCY", "PERIODIC")
            or self._last_master is None
            or (now - self._last_master_time) >= cfg.MASTER_AGENT_INTERVAL
        )

        if master_needed:
            log.info(f"[Brain] Master Agent cagriliyor... tetik={trigger}")
            master = self.master_agent.decide_portfolio(
                snapshot, active_positions,
                self._performance, self._blacklist, trigger
            )
            if master:
                self._last_master = master
                self._last_master_time = now
                # Blacklist guncellemelerini uygula
                self._apply_blacklist_updates(master.blacklist_updates)
            else:
                log.warning("[Brain] Master Agent kararsiz — onceki karar kullaniliyor")

        master_ctx = self._last_master

        # ── 2. Her sembol icin Strategy Agent ──
        decisions: List[TradeDecision] = []

        # Master override kararlari varsa oncelikli ekle
        if master_ctx and master_ctx.decisions:
            log.info(f"[Brain] Master override: {len(master_ctx.decisions)} karar")
            decisions.extend(master_ctx.decisions)
            override_symbols = {d.symbol for d in master_ctx.decisions}
        else:
            override_symbols = set()

        # Hesap ozeti — strategy agent'lar icin kompakt
        acc = snapshot.account
        account_summary = (
            f"Bakiye: ${acc.balance:.2f} | Equity: ${acc.equity:.2f} | "
            f"DD: {acc.drawdown_pct:.1f}% | Gunluk: ${acc.daily_pnl:+.2f} | "
            f"Pozisyon: {acc.open_positions}"
        )

        # CRITICAL risk durumunda yeni islem acma
        if master_ctx and master_ctx.global_risk == "CRITICAL":
            log.warning("[Brain] CRITICAL risk — sadece mevcut pozisyonlar yonetilecek")
            # Sadece acik pozisyonu olan semboller icin strategy cagir
            symbols_to_check = [
                sym for sym in snapshot.technicals.keys()
                if sym in active_positions and sym not in override_symbols
            ]
        else:
            # Odak semboller oncelikli, sonra diger aktifler
            focus = master_ctx.focus_symbols if master_ctx else []
            other = [s for s in snapshot.technicals.keys() if s not in focus]
            symbols_to_check = [
                sym for sym in (focus + other)
                if sym not in override_symbols
            ]

        for sym in symbols_to_check:
            tech = snapshot.technicals.get(sym)
            if not tech:
                continue

            # Blacklist kontrolu
            if sym in self._blacklist and now < self._blacklist[sym]:
                log.debug(f"[Brain] {sym} blacklist'te — atlaniyor")
                continue

            # Pozisyon metni
            pos_text = ""
            if sym in active_positions:
                pos_data = active_positions[sym]
                pos_lines = []
                for pos in pos_data.get("positions", []):
                    pos_lines.append(
                        f"#{pos['ticket']} {pos['role']} {pos['direction']} "
                        f"{pos['lot']}lot P&L=${pos['profit']:+.2f} "
                        f"Acilis={pos['open_price']:.5f} Kasa=${pos.get('kasa',0):.2f}"
                    )
                pos_text = "\n".join(pos_lines)

            # Rejim hesapla
            regime = _detect_regime(tech)

            # Sentiment
            sentiment = snapshot.context.fear_greed_index

            # Strategy Agent cagir (islem gecmisi ile)
            td = self.strategy_agent.decide_symbol(
                symbol=sym,
                technical=tech,
                account_summary=account_summary,
                positions_text=pos_text,
                regime=regime,
                sentiment_score=sentiment,
                trigger=trigger,
                master_context=master_ctx,
                trade_history=self._trade_history,
            )

            if td:
                # Master lot carpani uygula
                if master_ctx and td.action.startswith("OPEN"):
                    td.lot = round(td.lot * master_ctx.lot_multiplier, 2)
                    td.lot = max(cfg.MIN_LOT, td.lot)
                decisions.append(td)

        # ── 3. SessionDecision olustur ──
        session = SessionDecision(
            timestamp    = snapshot.generated_at,
            decisions    = decisions,
            market_read  = master_ctx.market_read if master_ctx else "",
            global_risk  = master_ctx.global_risk if master_ctx else "MEDIUM",
            focus_symbols= master_ctx.focus_symbols if master_ctx else [],
            skip_reason  = master_ctx.skip_reason if master_ctx else "",
        )

        # ── 4. Hard limit filtresi ──
        session = self._apply_hard_limits(session, snapshot)

        # ── 5. Gecmise kaydet ──
        self._decision_history.append({
            "ts": now,
            "trigger": trigger,
            "global_risk": session.global_risk,
            "n_decisions": len(session.decisions),
            "master_called": master_needed,
        })
        if len(self._decision_history) > 100:
            self._decision_history.pop(0)

        # Log
        log.info(
            f"[Brain] Karar tamamlandi → risk={session.global_risk} | "
            f"{len(session.decisions)} karar | master={'EVET' if master_needed else 'HAYIR'}"
        )
        if session.market_read:
            log.info(f"[Brain] Piyasa: {session.market_read[:100]}")
        for d in session.decisions:
            log.info(
                f"  [{d.symbol}] {d.action} lot={d.lot} conf={d.confidence}% "
                f"urgency={d.urgency} | {d.reason[:60]}"
            )

        return session

    # ─── DOGRUDAN AJAN CAGRILARI ──────────────────────────

    def decide_symbol(self, symbol: str, technical: TechnicalSnapshot,
                      account_summary: str, positions_text: str,
                      regime: str, sentiment_score: int,
                      trigger: str = "SIGNAL",
                      grid_context: Optional[dict] = None) -> Optional[TradeDecision]:
        """Dogrudan Strategy Agent cagir — tek sembol karari"""
        if not self._api_available or self.strategy_agent is None:
            return None  # API yok → mekanik sinyal sistemi devreye girer
        self.total_calls += 1
        td = self.strategy_agent.decide_symbol(
            symbol=symbol,
            technical=technical,
            account_summary=account_summary,
            positions_text=positions_text,
            regime=regime,
            sentiment_score=sentiment_score,
            trigger=trigger,
            master_context=self._last_master,
            grid_context=grid_context,
            trade_history=self._trade_history,
        )
        # Milisaniye mimarisi: kararı önbelleğe al
        if td and td.action not in ("HOLD",):
            self.decision_cache.update(
                symbol, td, regime,
                technical.ema8, technical.ema21
            )
        return td

    def decide_portfolio(self, snapshot: FullMarketSnapshot,
                         active_positions: dict,
                         trigger: str = "PERIODIC",
                         grid_state: Optional[dict] = None) -> Optional[MasterDecision]:
        """Dogrudan Master Agent cagir — portfolio karari"""
        if not self._api_available or self.master_agent is None:
            return None  # API yok → mekanik mod
        self.total_calls += 1
        master = self.master_agent.decide_portfolio(
            snapshot, active_positions,
            self._performance, self._blacklist, trigger, grid_state
        )
        if master:
            self._last_master = master
            self._last_master_time = time.time()
            self._apply_blacklist_updates(master.blacklist_updates)
        return master

    # ─── HARD LIMIT FILTRESI ──────────────────────────────

    def _apply_hard_limits(self, session: SessionDecision,
                            snapshot: FullMarketSnapshot) -> SessionDecision:
        """
        Claude'un kararlarina guvenlik citleri uygula.
        Bu limitleri Claude kendisi de biliyor ama cift kontrol.
        """
        acc    = snapshot.account
        limits = cfg.CLAUDE_HARD_LIMITS
        filtered = []

        for d in session.decisions:
            sym = d.symbol

            # 1. Blacklist
            if sym in self._blacklist and time.time() < self._blacklist[sym]:
                log.debug(f"[HardLimit] {sym} blacklist'te — {d.action} engellendi")
                continue

            # 2. Gunluk max kayip
            if acc.daily_pnl < 0 and abs(acc.daily_pnl) / (acc.balance + 1e-9) * 100 >= limits["max_daily_loss_pct"]:
                if d.action.startswith("OPEN"):
                    log.warning(f"[HardLimit] Gunluk kayip limiti — {sym} {d.action} engellendi")
                    continue

            # 3. Acil DD
            if acc.drawdown_pct >= limits["emergency_close_dd"]:
                if d.action.startswith("OPEN"):
                    log.warning(f"[HardLimit] Acil DD {acc.drawdown_pct:.1f}% — acilis engellendi")
                    continue

            # 4. Haber blackout
            ctx = snapshot.context
            for news in ctx.upcoming_news:
                if abs(news.minutes_until) <= limits["news_blackout_minutes"]:
                    if d.action.startswith("OPEN") and news.currency in sym:
                        log.info(f"[HardLimit] Haber blackout {sym} | {news.event} {news.minutes_until}dk")
                        d.urgency = "SKIP"
                        break

            # 5. Lot limiti
            if d.lot > cfg.MAX_LOT_PER_SYMBOL:
                log.debug(f"[HardLimit] Lot clip {sym}: {d.lot} -> {cfg.MAX_LOT_PER_SYMBOL}")
                d.lot = cfg.MAX_LOT_PER_SYMBOL

            # 6. Confidence alt siniri
            if d.action.startswith("OPEN") and d.confidence < cfg.STRATEGY_MIN_CONFIDENCE:
                log.debug(f"[HardLimit] Dusuk guven {sym} confidence={d.confidence} -> SKIP")
                d.urgency = "SKIP"

            # 7. Risk/Reward kontrolu
            if d.action.startswith("OPEN") and d.risk_reward < limits.get("min_risk_reward", 1.5):
                log.debug(f"[HardLimit] Dusuk R:R {sym} rr={d.risk_reward} -> SKIP")
                d.urgency = "SKIP"

            # Blacklist karari
            if d.action == "BLACKLIST" and d.blacklist_minutes > 0:
                self._blacklist[sym] = time.time() + d.blacklist_minutes * 60
                log.info(f"[Brain] {sym} {d.blacklist_minutes}dk blacklist'e alindi: {d.reason}")
                continue

            filtered.append(d)

        session.decisions = filtered
        return session

    # ─── BLACKLIST YONETIMI ───────────────────────────────

    def _clean_expired_blacklist(self):
        """Suresi dolmus blacklist girdilerini temizle"""
        now = time.time()
        expired = [sym for sym, until in self._blacklist.items() if now > until]
        for sym in expired:
            del self._blacklist[sym]
            log.info(f"[Brain] {sym} blacklist'ten cikarildi")

    def _apply_blacklist_updates(self, updates: Dict[str, int]):
        """Master Agent'in blacklist guncellemelerini uygula"""
        if not updates:
            return
        now = time.time()
        for sym, minutes in updates.items():
            if minutes > 0:
                self._blacklist[sym] = now + minutes * 60
                log.info(f"[Brain] Master: {sym} {minutes}dk blacklist'e alindi")
            elif minutes == 0 and sym in self._blacklist:
                del self._blacklist[sym]
                log.info(f"[Brain] Master: {sym} blacklist'ten cikarildi")

    # ─── PERFORMANS GERIBILDIRIMI ─────────────────────────

    def record_trade_result(self, symbol: str, pnl: float, won: bool,
                            direction: str = "", reason: str = ""):
        """Kapatilan islemlerin sonucunu kaydet — ajanlar ogrenir"""
        if symbol not in self._performance:
            self._performance[symbol] = {"wins": 0, "losses": 0, "total_pnl": 0, "count": 0}
        p = self._performance[symbol]
        p["wins"   ] += 1 if won else 0
        p["losses" ] += 0 if won else 1
        p["total_pnl"] += pnl
        p["count"  ] += 1
        p["avg_pnl"] = p["total_pnl"] / p["count"]

        # Detayli islem gecmisi — Strategy Agent ogrenme icin
        self._trade_history.append({
            "symbol": symbol,
            "direction": direction,
            "pnl": pnl,
            "won": won,
            "reason": reason,
            "ts": time.time(),
        })
        # Son 30 islemi tut
        if len(self._trade_history) > 30:
            self._trade_history = self._trade_history[-30:]

        log.info(
            f"[Brain] Sonuc: {symbol} {'WIN' if won else 'LOSS'} ${pnl:+.2f} | "
            f"Toplam: {p['wins']}W/{p['losses']}L"
        )

    def get_stats(self) -> dict:
        """Genel istatistikler — Telegram /durum komutu icin"""
        total = sum(p["count"] for p in self._performance.values())
        wins  = sum(p["wins"]  for p in self._performance.values())
        pnl   = sum(p["total_pnl"] for p in self._performance.values())
        return {
            "api_calls":       self.total_calls,
            "api_errors":      self.api_errors,
            "trades_total":    total,
            "win_rate":        f"{wins/total*100:.1f}%" if total else "N/A",
            "total_pnl":       f"${pnl:.2f}",
            "blacklisted":     list(self._blacklist.keys()),
            "master_risk":     self._last_master.global_risk if self._last_master else "N/A",
            "master_strategy": self._last_master.session_strategy if self._last_master else "N/A",
            "lot_multiplier":  self._last_master.lot_multiplier if self._last_master else 1.0,
            "master_stats":    self.master_agent.get_stats(),
            "strategy_stats":  self.strategy_agent.get_stats(),
        }

    @property
    def last_master_decision(self) -> Optional[MasterDecision]:
        """Son Master Agent kararina erisim"""
        return self._last_master


# ═══════════════════════════════════════════════════════════════
# YARDIMCI FONKSIYONLAR (Modul seviyesi)
# ═══════════════════════════════════════════════════════════════

def _clean_json(text: str) -> str:
    """Markdown kod bloklarini ve gereksiz metni temizle"""
    if "```json" in text:
        text = text.split("```json")[1]
    elif "```" in text:
        text = text.split("```")[1]
    if "```" in text:
        text = text.split("```")[0]
    return text.strip()


def _parse_trade_decision(symbol: str, raw: dict) -> TradeDecision:
    """Ham JSON dict'i TradeDecision'a cevir"""
    return TradeDecision(
        symbol      = symbol or raw.get("symbol", ""),
        action      = raw.get("action", "HOLD"),
        lot         = float(raw.get("lot", 0)),
        confidence  = int(raw.get("confidence", 50)),
        reason      = raw.get("reason", ""),
        risk_reward = float(raw.get("risk_reward", 0)),
        risk_pct    = float(raw.get("risk_pct", 0)),
        urgency     = raw.get("urgency", "WAIT_CANDLE"),
        open_spm    = bool(raw.get("open_spm", False)),
        spm_dir     = raw.get("spm_dir", ""),
        spm_lot     = float(raw.get("spm_lot", 0)),
        spm_reason  = raw.get("spm_reason", ""),
        fifo_action = raw.get("fifo_action", "HOLD"),
        fifo_reason = raw.get("fifo_reason", ""),
        approve_grid      = bool(raw.get("approve_grid", True)),
        grid_lot_multiplier = float(raw.get("grid_lot_multiplier", 1.0)),
        force_fifo_close  = bool(raw.get("force_fifo_close", False)),
        blacklist_minutes = int(raw.get("blacklist_minutes", 0)),
    )


def _detect_regime(tech: TechnicalSnapshot) -> str:
    """Teknik veriden piyasa rejimi belirle"""
    adx = tech.adx
    atr_pct = tech.atr_percentile

    if adx >= cfg.REGIME_STRONG_TREND_ADX:
        return "STRONG_TREND"
    elif adx >= cfg.REGIME_TREND_ADX:
        if atr_pct >= cfg.REGIME_VOLATILE_ATR_PCT:
            return "VOLATILE"
        return "TREND"
    elif adx >= cfg.REGIME_CHOPPY_ADX:
        if atr_pct >= cfg.REGIME_VOLATILE_ATR_PCT:
            return "VOLATILE"
        return "RANGE"
    else:
        return "CHOPPY"


def _generate_warnings(snapshot: FullMarketSnapshot) -> List[str]:
    """Kritik uyarilari olustur"""
    warnings = []
    acc = snapshot.account
    ctx = snapshot.context

    if acc.drawdown_pct > 20:
        warnings.append(f"YUKSEK DRAWDOWN: {acc.drawdown_pct:.1f}% — lot boyutlarini kucult")
    if acc.margin_level > 0 and acc.margin_level < 300:
        warnings.append(f"DUSUK MARGIN: {acc.margin_level:.0f}% — yeni pozisyon acma")
    if ctx.is_holiday:
        warnings.append("HAFTA SONU — spread yuksek, likidite dusuk")
    if ctx.session == "OFF_HOURS":
        warnings.append("SEANS DISI — dusuk hacim, dikkatli ol")
    if len(ctx.upcoming_news) > 2:
        warnings.append(f"{len(ctx.upcoming_news)} yuksek etkili haber yaklesiyor")
    if ctx.fear_greed_index < 20:
        warnings.append(f"ASIRI KORKU: F&G={ctx.fear_greed_index} — reversal firsati ama dikkat")
    if ctx.fear_greed_index > 80:
        warnings.append(f"ASIRI ACGOZLULUK: F&G={ctx.fear_greed_index} — tepe yakin olabilir")
    if acc.daily_pnl < -acc.balance * 0.08:
        warnings.append(f"KOTU GUN: ${acc.daily_pnl:.2f} — lot boyutlarini yariya indir")

    return warnings
