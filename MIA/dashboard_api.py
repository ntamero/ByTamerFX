"""
MIA v6.2.0 Dashboard API Server
Dashboard HTML'sine gerçek zamanlı veri sağlar.
Port: 8765

Endpoints:
  GET /api/state     — Tam piyasa durumu (500ms realtime thread ile güncellenir)
  GET /              — Quantum Trade OS Dashboard (dashboard_miav62.html)
"""

import threading
import time
import json
import logging
import os
import math
from http.server import HTTPServer, BaseHTTPRequestHandler
from typing import Optional, List
import config as cfg

log = logging.getLogger("DashAPI")


class DashboardState:
    """Dashboard için paylaşılan durum nesnesi"""
    def __init__(self):
        self._lock   = threading.Lock()
        self._trade_history = []   # Kapanan işlemler
        self._trade_stats = {"wins": 0, "losses": 0, "total_realized": 0.0}
        self._state  = {
            "account": {
                "balance": 0, "equity": 0, "margin_level": 0,
                "daily_pnl": 0, "floating_pnl": 0,
                "open_positions": 0, "drawdown_pct": 0,
            },
            "technicals": {},
            "positions":  {},
            "brain": {
                "global_risk": "MEDIUM",
                "market_read": "",
                "focus_symbols": [],
                "last_decision_time": "",
            },
            "context": {
                "session": "", "fear_greed_index": 50,
                "fear_greed_label": "Neutral",
                "upcoming_news": [], "recent_news": [],
            },
            "active_symbols": [],
            "recent_logs": [],
            "equity_history": [],
            "trade_history": [],
            "trade_stats": {"wins": 0, "losses": 0, "total_realized": 0.0, "win_rate": 0.0},
            "safety_shield": {
                "status": "NORMAL",       # NORMAL / WARNING / CRITICAL / EMERGENCY
                "equity_ratio": 100.0,    # equity/balance * 100
                "equity_threshold": cfg.EQUITY_EMERGENCY_PCT,
                "margin_level": 0.0,
                "margin_guard": cfg.MARGIN_GUARD_PCT,
                "margin_emergency": cfg.MARGIN_EMERGENCY_PCT,
                "margin_guard_active": False,
                "hedge_details": {},      # {symbol: [{ticket, age_sec, profit, direction}]}
                "hedge_max_time": cfg.HEDGE_MAX_TIME_SEC,
                "hedge_max_loss_pct": cfg.HEDGE_MAX_LOSS_PCT,
                "symbol_pnl": {},         # {symbol: total_pnl}
                "symbol_max_loss_pct": cfg.SYMBOL_MAX_LOSS_PCT,
                "last_alert": "",
            },
            "generated_at": "",
        }

    def update(self, key: str, value):
        with self._lock:
            self._state[key] = value

    def update_partial(self, key: str, sub_key: str, value):
        with self._lock:
            if key in self._state and isinstance(self._state[key], dict):
                self._state[key][sub_key] = value

    def add_log(self, msg: str, type_: str = ""):
        t = time.strftime("%H:%M:%S", time.gmtime())
        with self._lock:
            self._state["recent_logs"].append({"time": t, "msg": msg, "type": type_})
            if len(self._state["recent_logs"]) > 200:
                self._state["recent_logs"].pop(0)

    def record_closed_trades(self, closed_list: list):
        """Kapanan işlemleri kaydet."""
        if not closed_list:
            return
        with self._lock:
            for t in closed_list:
                t["closed_at"] = time.strftime("%H:%M:%S", time.gmtime())
                self._trade_history.append(t)
                pnl = t.get("pnl", 0)
                if pnl > 0:
                    self._trade_stats["wins"] += 1
                else:
                    self._trade_stats["losses"] += 1
                self._trade_stats["total_realized"] += pnl
            # Son 100 işlemi tut
            if len(self._trade_history) > 100:
                self._trade_history = self._trade_history[-100:]
            # State'e yaz
            total = self._trade_stats["wins"] + self._trade_stats["losses"]
            wr = (self._trade_stats["wins"] / total * 100) if total > 0 else 0
            self._state["trade_history"] = list(self._trade_history)
            self._state["trade_stats"] = {
                "wins": self._trade_stats["wins"],
                "losses": self._trade_stats["losses"],
                "total_realized": round(self._trade_stats["total_realized"], 2),
                "win_rate": round(wr, 1),
            }

    def get_json(self) -> str:
        with self._lock:
            self._state["generated_at"] = time.strftime("%H:%M:%S UTC", time.gmtime())
            return json.dumps(self._state, default=str)

    def get_state(self) -> dict:
        with self._lock:
            return dict(self._state)


# Global state instance
dash_state = DashboardState()


class DashHandler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        pass  # HTTP loglarını sustur

    def do_GET(self):
        # Query string'i ayır
        path = self.path.split('?')[0]

        if path == '/api/state':
            data = dash_state.get_json()
            self._respond(200, data, 'application/json')

        elif path == '/':
            # v4.6.1 Quantum Trade OS — MIA v6.2 dashboard
            html_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'dashboard_miav62.html')
            try:
                with open(html_path, 'r', encoding='utf-8') as f:
                    html_content = f.read()
                self._respond(200, html_content.encode('utf-8'), 'text/html; charset=utf-8', raw=True)
            except FileNotFoundError:
                # Fallback: inline dashboard
                self._respond(200, DASHBOARD_HTML.encode('utf-8'), 'text/html; charset=utf-8', raw=True)

        else:
            self._respond(404, '{"error":"not found"}')

    def do_OPTIONS(self):
        self.send_response(200)
        self._cors_headers()
        self.end_headers()

    def _respond(self, code, data, ct='application/json', raw=False):
        self.send_response(code)
        self.send_header('Content-Type', ct)
        self._cors_headers()
        if isinstance(data, str):
            data = data.encode('utf-8')
        self.send_header('Content-Length', len(data))
        self.end_headers()
        self.wfile.write(data)

    def _cors_headers(self):
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET,POST,OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')


class DashboardServer:
    """
    Dashboard API sunucusu.
    main.py tarafından başlatılır.
    """
    def __init__(self, port: int = 8765):
        self.port   = port
        self.server = None
        self.thread = None

    def start(self):
        try:
            self.server = HTTPServer(('0.0.0.0', self.port), DashHandler)
            self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
            self.thread.start()
            log.info(f"📊 Dashboard: http://localhost:{self.port}")
        except Exception as e:
            log.error(f"Dashboard sunucusu başlatılamadı: {e}")

    def stop(self):
        if self.server:
            self.server.shutdown()


def update_from_snapshot(snapshot, positions_dict: dict, active_symbols: list):
    """
    MarketIntelligence snapshot → Dashboard state güncelle.
    main.py'de her Brain çağrısından sonra çağrılır.
    """
    acc = snapshot.account
    dash_state.update("account", {
        "balance":     acc.balance,
        "equity":      acc.equity,
        "margin":      acc.margin,
        "margin_level":acc.margin_level,
        "daily_pnl":   acc.daily_pnl,
        "floating_pnl":acc.floating_pnl,
        "drawdown_pct":acc.drawdown_pct,
        "open_positions":acc.open_positions,
        "leverage":    acc.leverage,
    })

    # Teknik veriler + sinyal
    tech = {}
    for sym, t in snapshot.technicals.items():
        buy_s  = _estimate_score(t, "BUY")
        sell_s = _estimate_score(t, "SELL")
        atr    = t.atr_m15 or 0
        price  = t.price or 0
        tp1    = round(price + atr * 1.0, 5) if atr and price else 0
        tp2    = round(price + atr * 1.5, 5) if atr and price else 0
        tp3    = round(price + atr * 2.2, 5) if atr and price else 0
        # Mum verisi (son 60 bar) — TechnicalSnapshot'da varsa
        candles_raw = getattr(t, 'candles_m15', None) or []
        candles = _enrich_candles(candles_raw)
        tech[sym] = {
            "price":         price,
            "rsi_m15":       t.rsi_m15,
            "rsi_h1":        t.rsi_h1,
            "adx":           t.adx,
            "macd_hist":     t.macd_hist,
            "macd_cross":    t.macd_cross,
            "atr_m15":       atr,
            "atr_percentile":t.atr_percentile,
            "bb_position":   t.bb_position,
            "stoch_k":       t.stoch_k,
            "stoch_d":       t.stoch_d,
            "stoch_zone":    t.stoch_zone,
            "trend_aligned": t.trend_aligned,
            "ema8":          t.ema8,
            "ema21":         t.ema21,
            "ema50":         t.ema50,
            "spread_pts":    getattr(t, 'spread_pts', 0),
            "spread_ok":     getattr(t, 'spread_ok', True),
            # Sinyal skorları — JS doğrudan okusun
            "buy_score":     buy_s,
            "sell_score":    sell_s,
            "ema_score":     _layer_ema(t),
            "macd_score":    _layer_macd(t),
            "adx_score":     _layer_adx(t),
            "rsi_score":     _layer_rsi(t),
            "bb_score":      _layer_bb(t),
            "stoch_score":   _layer_stoch(t),
            "atr_score":     int(min(5, (t.atr_percentile or 0) / 20)),
            # TP seviyeleri
            "tp1": tp1, "tp2": tp2, "tp3": tp3,
            # Mum verisi
            "candles_m15": candles,
            # Eski nested format da kalsın (geriye uyumluluk)
            "signal": {
                "buy_score":  buy_s,
                "sell_score": sell_s,
            }
        }
    dash_state.update("technicals", tech)

    # Pozisyonlar
    dash_state.update("positions", positions_dict)

    # Bağlam
    ctx = snapshot.context
    dash_state.update("context", {
        "session":          ctx.session,
        "fear_greed_index": ctx.fear_greed_index,
        "fear_greed_label": ctx.fear_greed_label,
        "upcoming_news":    [vars(n) if hasattr(n,'__dict__') else n for n in ctx.upcoming_news],
        "recent_news":      [vars(n) if hasattr(n,'__dict__') else n for n in ctx.recent_news],
        "day_of_week":      ctx.day_of_week,
        "is_holiday":       ctx.is_holiday,
    })

    dash_state.update("active_symbols", active_symbols)


def update_grid_state(grid_agent):
    """GridAgent state → Dashboard güncelle."""
    try:
        gs = grid_agent.get_grid_state()
        dash_state.update_partial("brain", "grid", gs)
    except Exception:
        pass


def update_news_state(news_manager):
    """NewsManager state → Dashboard güncelle."""
    try:
        events = getattr(news_manager, '_events', [])
        blocked = list(getattr(news_manager, '_blocked_symbols', set()))
        dash_state.update_partial("context", "news_blocked_symbols", blocked)
        dash_state.update_partial("context", "news_event_count", len(events))
    except Exception:
        pass


def update_safety_shield(grid_agent, account: dict):
    """
    v3.8.0 SafetyShield state → Dashboard güncelle.
    Her tick'te çağrılır (main loop'tan).
    """
    try:
        balance = account.get("balance", 0)
        equity = account.get("equity", 0)
        margin_level = account.get("margin_level", 0)

        # Equity ratio
        equity_ratio = (equity / balance * 100.0) if balance > 0 else 100.0

        # Margin guard aktif mi?
        margin_guard_active = (0 < margin_level < cfg.MARGIN_GUARD_PCT) if margin_level > 0 else False

        # Hedge detayları
        hedge_details = {}
        symbol_pnl = {}
        if grid_agent and cfg.GRID_ENABLED:
            gs = grid_agent.get_grid_state()
            hedge_details = gs.get("hedge_details", {})
            for sym, summary in gs.get("summaries", {}).items():
                symbol_pnl[sym] = summary.get("total_pnl", 0)

        # Status hesapla
        status = "NORMAL"
        last_alert = ""
        if equity_ratio < cfg.EQUITY_EMERGENCY_PCT:
            status = "EMERGENCY"
            last_alert = f"EQUITY ACİL: {equity_ratio:.0f}% < {cfg.EQUITY_EMERGENCY_PCT}%"
        elif margin_level > 0 and margin_level < cfg.MARGIN_EMERGENCY_PCT:
            status = "EMERGENCY"
            last_alert = f"MARGIN ACİL: {margin_level:.0f}% < {cfg.MARGIN_EMERGENCY_PCT}%"
        elif margin_guard_active:
            status = "WARNING"
            last_alert = f"MARGIN GUARD: {margin_level:.0f}% < {cfg.MARGIN_GUARD_PCT}%"
        elif equity_ratio < cfg.EQUITY_EMERGENCY_PCT + 15:
            status = "WARNING"
            last_alert = f"EQUITY UYARI: {equity_ratio:.0f}%"
        else:
            # Hedge deadlock kontrolü
            for sym, hedges in hedge_details.items():
                for h in hedges:
                    if h.get("age_sec", 0) > cfg.HEDGE_MAX_TIME_SEC * 0.8:
                        status = "CRITICAL"
                        age_min = h["age_sec"] / 60
                        last_alert = f"HEDGE DEADLOCK: {sym} {age_min:.0f}dk"
                        break
            # Symbol loss kontrolü
            if status == "NORMAL" and balance > 0:
                for sym, pnl in symbol_pnl.items():
                    loss_pct = abs(pnl) / balance * 100 if pnl < 0 else 0
                    if loss_pct > cfg.SYMBOL_MAX_LOSS_PCT * 0.8:
                        status = "WARNING"
                        last_alert = f"SEMBOL KAYIP: {sym} -{loss_pct:.0f}%"
                        break

        dash_state.update("safety_shield", {
            "status": status,
            "equity_ratio": round(equity_ratio, 1),
            "equity_threshold": cfg.EQUITY_EMERGENCY_PCT,
            "margin_level": round(margin_level, 0),
            "margin_guard": cfg.MARGIN_GUARD_PCT,
            "margin_emergency": cfg.MARGIN_EMERGENCY_PCT,
            "margin_guard_active": margin_guard_active,
            "hedge_details": hedge_details,
            "hedge_max_time": cfg.HEDGE_MAX_TIME_SEC,
            "hedge_max_loss_pct": cfg.HEDGE_MAX_LOSS_PCT,
            "symbol_pnl": {k: round(v, 2) for k, v in symbol_pnl.items()},
            "symbol_max_loss_pct": cfg.SYMBOL_MAX_LOSS_PCT,
            "last_alert": last_alert,
        })
    except Exception as e:
        log.debug(f"SafetyShield update hata: {e}")


def update_brain_decision(market_read: str, global_risk: str, focus: list):
    dash_state.update("brain", {
        "global_risk":        global_risk,
        "market_read":        market_read,
        "focus_symbols":      focus,
        "last_decision_time": time.strftime("%H:%M:%S UTC", time.gmtime()),
    })


# ── SERVER-SIDE INDICATOR HESAPLAMA (Candle overlay verileri) ──
def _compute_ema(closes: List[float], period: int) -> List[Optional[float]]:
    """EMA hesapla — ilk period-1 bar None."""
    if len(closes) < period:
        return [None] * len(closes)
    k = 2.0 / (period + 1)
    result: List[Optional[float]] = [None] * (period - 1)
    sma = sum(closes[:period]) / period
    result.append(round(sma, 6))
    for i in range(period, len(closes)):
        val = closes[i] * k + result[-1] * (1 - k)
        result.append(round(val, 6))
    return result


def _compute_bb(closes: List[float], period: int = 20, mult: float = 2.0):
    """Bollinger Bands — upper, lower listesi dön."""
    n = len(closes)
    upper = [None] * n
    lower = [None] * n
    for i in range(period - 1, n):
        window = closes[i - period + 1:i + 1]
        sma = sum(window) / period
        variance = sum((x - sma) ** 2 for x in window) / period
        std = math.sqrt(variance)
        upper[i] = round(sma + mult * std, 6)
        lower[i] = round(sma - mult * std, 6)
    return upper, lower


def _enrich_candles(candles_raw) -> list:
    """Candle listesine EMA, BB ve timestamp ekle."""
    if not candles_raw:
        return []
    closes = [c.close for c in candles_raw]
    ema8 = _compute_ema(closes, 8)
    ema21 = _compute_ema(closes, 21)
    ema50 = _compute_ema(closes, 50)
    bbu, bbl = _compute_bb(closes, 20, 2.0)

    result = []
    for i, c in enumerate(candles_raw):
        # Timestamp: Unix saniye olarak
        ts = 0
        t_val = getattr(c, 'time', None)
        if t_val:
            if isinstance(t_val, (int, float)):
                ts = int(t_val)
            else:
                try:
                    from datetime import datetime
                    t_str = str(t_val)
                    if '+' in t_str:
                        t_str = t_str.split('+')[0].strip()
                    dt = datetime.strptime(t_str, "%Y-%m-%d %H:%M:%S")
                    ts = int(dt.timestamp())
                except Exception:
                    ts = 0

        result.append({
            "o": c.open, "h": c.high, "l": c.low, "c": c.close,
            "v": getattr(c, 'volume', 0),
            "t": ts,
            "e8": ema8[i], "e21": ema21[i], "e50": ema50[i],
            "bbu": bbu[i], "bbl": bbl[i],
        })
    return result


# ── SINYAL SKORU HESAPLAMA (Dashboard için) ───────────────
def _estimate_score(t, direction: str) -> int:
    """Geliştirilmiş sinyal skoru — trend-aligned ADX, geniş RSI aralığı."""
    score = 0
    is_buy = direction == "BUY"

    # Trend yönü tespiti (EMA sıralamasından)
    trend_bullish = False
    trend_bearish = False
    if t.ema8 and t.ema21 and t.ema50:
        trend_bullish = t.ema8 > t.ema21 > t.ema50
        trend_bearish = t.ema8 < t.ema21 < t.ema50

    # EMA (0-20)
    if t.ema8 and t.ema21 and t.ema50:
        if is_buy and trend_bullish: score += 20
        elif not is_buy and trend_bearish: score += 20
        elif is_buy and t.ema8 > t.ema21: score += 12
        elif not is_buy and t.ema8 < t.ema21: score += 12
        elif is_buy and t.price and t.price > t.ema50: score += 5
        elif not is_buy and t.price and t.price < t.ema50: score += 5

    # MACD (0-20)
    if t.macd_hist:
        if is_buy and t.macd_hist > 0: score += 15
        elif not is_buy and t.macd_hist < 0: score += 15
        if t.macd_cross == ("FRESH_BULL" if is_buy else "FRESH_BEAR"):
            score += 5

    # ADX (0-15) — Sadece trend yönüyle uyumluysa skor ver
    if t.adx:
        aligned = (is_buy and trend_bullish) or (not is_buy and trend_bearish)
        partial = (is_buy and t.ema8 and t.ema21 and t.ema8 > t.ema21) or \
                  (not is_buy and t.ema8 and t.ema21 and t.ema8 < t.ema21)
        if aligned:
            if t.adx > 35: score += 15
            elif t.adx > 25: score += 12
            elif t.adx > 15: score += 7
        elif partial:
            if t.adx > 30: score += 8
            elif t.adx > 20: score += 4

    # RSI (0-15) — Geniş aralık, trend-uyumlu
    if t.rsi_m15:
        if is_buy and 25 < t.rsi_m15 < 70: score += 15
        elif not is_buy and 30 < t.rsi_m15 < 75: score += 15
        elif is_buy and t.rsi_m15 <= 25: score += 10  # Oversold reversal
        elif not is_buy and t.rsi_m15 >= 75: score += 10  # Overbought reversal

    # BB (0-15) — Dengeli skor
    if t.bb_position is not None:
        if is_buy:
            if t.bb_position < 20: score += 15
            elif t.bb_position < 40: score += 10
            elif t.bb_position < 55: score += 5
        else:
            if t.bb_position > 80: score += 15
            elif t.bb_position > 60: score += 10
            elif t.bb_position > 45: score += 5

    # Stoch (0-15) — Artırılmış ağırlık
    if t.stoch_k:
        if is_buy and t.stoch_zone == "OVERSOLD": score += 15
        elif not is_buy and t.stoch_zone == "OVERBOUGHT": score += 15
        elif is_buy and t.stoch_k and t.stoch_k < 40: score += 7
        elif not is_buy and t.stoch_k and t.stoch_k > 60: score += 7

    return min(100, score)

def _layer_ema(t) -> int:
    if not (t.ema8 and t.ema21 and t.ema50): return 0
    if t.ema8 > t.ema21 > t.ema50 or t.ema8 < t.ema21 < t.ema50: return 20
    if t.ema8 != t.ema21: return 10
    return 0

def _layer_macd(t) -> int:
    if not t.macd_hist: return 0
    base = 15 if abs(t.macd_hist) > 0 else 0
    if t.macd_cross != "NONE": base = min(20, base+5)
    return base

def _layer_adx(t) -> int:
    if not t.adx: return 0
    if t.adx > 35: return 15
    if t.adx > 25: return 10
    if t.adx > 15: return 5
    return 0

def _layer_rsi(t) -> int:
    if not t.rsi_m15: return 0
    if 30 < t.rsi_m15 < 70: return 12
    return 6

def _layer_bb(t) -> int:
    if t.bb_position is None: return 0
    if t.bb_position < 25 or t.bb_position > 75: return 15
    if t.bb_position < 35 or t.bb_position > 65: return 8
    return 4

def _layer_stoch(t) -> int:
    if t.stoch_zone == "OVERSOLD" or t.stoch_zone == "OVERBOUGHT": return 10
    return 4








# --- INLINE DASHBOARD HTML ---
DASHBOARD_HTML = r"""<!DOCTYPE html>
<html lang="tr">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>MIA v5.2.0 — Trading Terminal</title>
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700;800&family=JetBrains+Mono:wght@400;500;600;700&display=swap" rel="stylesheet">
<script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.1/dist/chart.umd.min.js"></script>
<script src="https://unpkg.com/lightweight-charts@4.1.3/dist/lightweight-charts.standalone.production.js"></script>
<style>
*{margin:0;padding:0;box-sizing:border-box}
:root{
  --bg0:#0a0a0f;--bg1:#0e0e16;--bg2:#12121a;--bg3:#1a1a26;--bg4:#22223a;
  --border:rgba(255,255,255,.06);--border2:rgba(255,255,255,.1);--border3:rgba(108,92,231,.2);
  --txt:#fafafa;--txt2:#a0a0b8;--txt3:#71717a;
  --purple:#6c5ce7;--purple2:#a78bfa;--purple3:#5a4bd6;--purple-glow:rgba(108,92,231,.35);
  --green:#10b981;--green2:#34d399;--red:#ef4444;--red2:#f87171;
  --gold:#f59e0b;--cyan:#06d6a0;--blue:#3b82f6;
  --glass:rgba(18,18,26,.75);--glass2:rgba(22,22,34,.65);--glass3:rgba(26,26,42,.5);
}
html,body{height:100%;overflow:hidden;background:var(--bg0);color:var(--txt);font-family:'Inter',sans-serif;font-size:13px}
.mono{font-family:'JetBrains Mono',monospace;font-variant-numeric:tabular-nums}

/* ── ANIMATED BACKGROUND ── */
body::before{content:'';position:fixed;top:0;left:0;width:100%;height:100%;z-index:-2;
  background:radial-gradient(ellipse at 20% 50%,rgba(108,92,231,.08) 0%,transparent 50%),
             radial-gradient(ellipse at 80% 20%,rgba(167,139,250,.05) 0%,transparent 50%),
             radial-gradient(ellipse at 50% 80%,rgba(90,75,214,.06) 0%,transparent 50%);
  animation:bgShift 20s ease-in-out infinite alternate}
body::after{content:'';position:fixed;top:0;left:0;width:100%;height:100%;z-index:-1;
  background-image:linear-gradient(rgba(255,255,255,.015) 1px,transparent 1px),linear-gradient(90deg,rgba(255,255,255,.015) 1px,transparent 1px);
  background-size:60px 60px;
  mask-image:radial-gradient(ellipse at 50% 50%,black 30%,transparent 70%)}
@keyframes bgShift{
  0%{background:radial-gradient(ellipse at 20% 50%,rgba(108,92,231,.08) 0%,transparent 50%),radial-gradient(ellipse at 80% 20%,rgba(167,139,250,.05) 0%,transparent 50%),radial-gradient(ellipse at 50% 80%,rgba(90,75,214,.06) 0%,transparent 50%)}
  50%{background:radial-gradient(ellipse at 60% 30%,rgba(108,92,231,.1) 0%,transparent 50%),radial-gradient(ellipse at 30% 70%,rgba(167,139,250,.06) 0%,transparent 50%),radial-gradient(ellipse at 80% 60%,rgba(90,75,214,.07) 0%,transparent 50%)}
  100%{background:radial-gradient(ellipse at 40% 60%,rgba(108,92,231,.08) 0%,transparent 50%),radial-gradient(ellipse at 70% 40%,rgba(167,139,250,.05) 0%,transparent 50%),radial-gradient(ellipse at 20% 30%,rgba(90,75,214,.06) 0%,transparent 50%)}}

/* ── LAYOUT ── */
.app{display:grid;height:100vh;grid-template-rows:52px 60px 1fr;grid-template-columns:240px 1fr 300px;gap:1px;position:relative;z-index:1}
.topbar{grid-column:1/-1;background:var(--glass);backdrop-filter:blur(30px);display:flex;align-items:center;padding:0 16px;gap:10px;border-bottom:1px solid var(--border)}
.statrow{grid-column:1/-1;background:var(--glass);backdrop-filter:blur(20px);display:flex;align-items:center;padding:0 12px;gap:8px;border-bottom:1px solid var(--border)}
.left{background:var(--glass);backdrop-filter:blur(24px);overflow-y:auto;border-right:1px solid var(--border)}
.center{background:transparent;display:flex;flex-direction:column;overflow:hidden}
.right{background:var(--glass);backdrop-filter:blur(24px);overflow-y:auto;border-left:1px solid var(--border)}

::-webkit-scrollbar{width:4px}
::-webkit-scrollbar-track{background:transparent}
::-webkit-scrollbar-thumb{background:var(--bg4);border-radius:2px}
::-webkit-scrollbar-thumb:hover{background:var(--purple)}

/* ── TOP BAR ── */
.logo{display:flex;align-items:center;gap:8px;margin-right:8px}
.logo-dot{width:10px;height:10px;border-radius:50%;background:var(--purple);box-shadow:0 0 10px var(--purple-glow);animation:pulse 2s infinite}
.logo-text{font-weight:800;font-size:15px;letter-spacing:.8px;background:linear-gradient(135deg,var(--purple),var(--purple2));-webkit-background-clip:text;-webkit-text-fill-color:transparent}
.logo-sub{font-size:9px;color:var(--txt3);font-weight:500;letter-spacing:1px}
.tb-stat{display:flex;flex-direction:column;align-items:center;padding:4px 14px;min-width:72px}
.tb-stat .label{font-size:8px;color:var(--txt3);text-transform:uppercase;letter-spacing:.8px;margin-bottom:2px;font-weight:500}
.tb-stat .val{font-size:14px;font-weight:700;font-family:'JetBrains Mono',monospace}
.tb-sep{width:1px;height:26px;background:var(--border2)}
.tb-right{margin-left:auto;display:flex;align-items:center;gap:8px}
.badge{padding:3px 10px;border-radius:6px;font-size:9px;font-weight:700;letter-spacing:.8px}
.badge-session{background:rgba(108,92,231,.12);color:var(--purple2);border:1px solid rgba(108,92,231,.25)}
.badge-risk{border:1px solid}
.badge-risk.LOW{background:rgba(16,185,129,.1);color:var(--green);border-color:rgba(16,185,129,.25)}
.badge-risk.MEDIUM{background:rgba(245,158,11,.1);color:var(--gold);border-color:rgba(245,158,11,.25)}
.badge-risk.HIGH{background:rgba(239,68,68,.1);color:var(--red);border-color:rgba(239,68,68,.25)}
.badge-risk.CRITICAL{background:rgba(239,68,68,.18);color:#ff6b6b;border-color:rgba(239,68,68,.4);animation:pulse 1s infinite}
.tb-clock{font-family:'JetBrains Mono',monospace;font-size:11px;color:var(--txt3)}
.conn-dot{width:8px;height:8px;border-radius:50%;background:var(--green);box-shadow:0 0 6px rgba(16,185,129,.5);animation:pulse 2s infinite}
.conn-dot.off{background:var(--red);box-shadow:0 0 6px rgba(239,68,68,.5);animation:none}

/* ── STAT ROW ── */
.stat-card{flex:1;background:var(--glass2);backdrop-filter:blur(16px);border:1px solid var(--border);border-radius:8px;padding:8px 12px;display:flex;flex-direction:column;align-items:center;transition:all .3s}
.stat-card:hover{border-color:var(--border2);box-shadow:0 0 20px rgba(108,92,231,.08)}
.stat-card .sc-val{font-size:16px;font-weight:700;font-family:'JetBrains Mono',monospace;line-height:1.2}
.stat-card .sc-label{font-size:8px;color:var(--txt3);text-transform:uppercase;letter-spacing:1px;margin-top:2px;font-weight:500}
.stat-card.accent{border-color:rgba(108,92,231,.2);box-shadow:0 0 16px rgba(108,92,231,.06)}
.val-up{color:var(--green)}.val-down{color:var(--red)}.val-warn{color:var(--gold)}.val-neutral{color:var(--txt)}

@keyframes flashGreen{0%{color:var(--green2);text-shadow:0 0 10px rgba(52,211,153,.5)}100%{text-shadow:none}}
@keyframes flashRed{0%{color:var(--red2);text-shadow:0 0 10px rgba(248,113,113,.5)}100%{text-shadow:none}}
.flash-up{animation:flashGreen .6s ease-out}
.flash-down{animation:flashRed .6s ease-out}

/* ── LEFT SIDEBAR ── */
.panel{padding:12px 14px}
.panel-title{font-size:9px;font-weight:700;color:var(--purple2);letter-spacing:1.4px;text-transform:uppercase;margin-bottom:8px;display:flex;align-items:center;gap:6px}
.panel-title::before{content:'';width:3px;height:12px;background:linear-gradient(180deg,var(--purple),var(--purple2));border-radius:2px}
.wr-container{display:flex;align-items:center;gap:14px}
.wr-donut{position:relative;width:64px;height:64px}
.wr-donut canvas{width:64px!important;height:64px!important}
.wr-center{position:absolute;top:50%;left:50%;transform:translate(-50%,-50%);text-align:center}
.wr-center .wr-val{font-size:15px;font-weight:800;font-family:'JetBrains Mono',monospace}
.wr-center .wr-sub{font-size:7px;color:var(--txt3);text-transform:uppercase;font-weight:600}
.wr-stats{display:flex;flex-direction:column;gap:4px}
.wr-row{display:flex;align-items:center;gap:6px;font-size:10px;color:var(--txt2)}
.wr-row .dot{width:7px;height:7px;border-radius:50%}
.sym-card{background:var(--glass3);border:1px solid var(--border);border-radius:7px;padding:7px 10px;margin-bottom:5px;cursor:pointer;transition:all .25s;display:flex;justify-content:space-between;align-items:center}
.sym-card:hover{border-color:var(--border2);background:rgba(108,92,231,.06);box-shadow:0 0 12px rgba(108,92,231,.06)}
.sym-card.active{border-color:var(--purple);background:rgba(108,92,231,.08);box-shadow:0 0 16px rgba(108,92,231,.1)}
.sym-card .sym-name{font-weight:600;font-size:11px;color:var(--txt)}
.sym-card .sym-price{font-family:'JetBrains Mono',monospace;font-size:12px;font-weight:600;color:var(--purple2);transition:color .3s}
.sym-card .sym-score{display:flex;gap:3px;margin-top:2px}
.sym-card .sym-score .bar{height:3px;border-radius:2px;min-width:16px}
.sym-card .sym-inds{display:flex;flex-wrap:wrap;gap:3px;margin-top:4px}
.ind-chip{font-family:'JetBrains Mono',monospace;font-size:8px;font-weight:600;padding:1px 5px;border-radius:3px;letter-spacing:.3px;line-height:1.3}
.ind-rsi{background:rgba(59,130,246,.12);color:var(--blue);border:1px solid rgba(59,130,246,.2)}
.ind-rsi.hot{background:rgba(239,68,68,.12);color:var(--red);border-color:rgba(239,68,68,.2)}
.ind-rsi.cold{background:rgba(16,185,129,.12);color:var(--green);border-color:rgba(16,185,129,.2)}
.ind-adx{background:rgba(108,92,231,.12);color:var(--purple2);border:1px solid rgba(108,92,231,.2)}
.ind-adx.strong{background:rgba(108,92,231,.2);color:#c4b5fd;border-color:rgba(108,92,231,.4);box-shadow:0 0 4px rgba(108,92,231,.15)}
.ind-atr{background:rgba(245,158,11,.1);color:var(--gold);border:1px solid rgba(245,158,11,.2)}
.ind-trend{background:rgba(6,214,160,.1);color:var(--cyan);border:1px solid rgba(6,214,160,.2)}
.ind-trend.down{background:rgba(239,68,68,.1);color:var(--red);border-color:rgba(239,68,68,.2)}
/* animated progress bar */
.progress-bar{width:100%;height:6px;background:var(--bg3);border-radius:3px;overflow:hidden;margin-top:4px;position:relative}
.progress-fill{height:100%;border-radius:3px;transition:width .8s cubic-bezier(.4,0,.2,1);position:relative;overflow:hidden}
.progress-fill::after{content:'';position:absolute;top:0;left:-100%;width:100%;height:100%;background:linear-gradient(90deg,transparent,rgba(255,255,255,.2),transparent);animation:shimmer 2s infinite}
@keyframes shimmer{0%{left:-100%}100%{left:100%}}
.progress-green .progress-fill{background:linear-gradient(90deg,var(--green),var(--cyan))}
.progress-purple .progress-fill{background:linear-gradient(90deg,var(--purple),var(--purple2))}
.progress-red .progress-fill{background:linear-gradient(90deg,var(--red),var(--gold))}
/* pulsing status dot */
.status-pulse{display:inline-block;width:6px;height:6px;border-radius:50%;margin-right:4px;vertical-align:middle}
.status-pulse.ok{background:var(--green);box-shadow:0 0 6px rgba(16,185,129,.5);animation:pulse 2s infinite}
.status-pulse.warn{background:var(--gold);box-shadow:0 0 6px rgba(245,158,11,.5);animation:pulse 1.5s infinite}
.status-pulse.crit{background:var(--red);box-shadow:0 0 8px rgba(239,68,68,.6);animation:pulse 1s infinite}
/* ── SIGNAL GAUGE ── */
.signal-gauge-wrap{display:flex;justify-content:center;align-items:center;gap:16px;padding:4px 0}
.signal-gauge{position:relative;width:80px;height:80px}
.signal-gauge svg{transform:rotate(-90deg);width:80px;height:80px}
.signal-gauge .gauge-bg{fill:none;stroke:var(--bg4);stroke-width:6}
.signal-gauge .gauge-fill{fill:none;stroke-width:6;stroke-linecap:round;transition:stroke-dashoffset .8s cubic-bezier(.4,0,.2,1),stroke .4s}
.signal-gauge .gauge-center{position:absolute;top:50%;left:50%;transform:translate(-50%,-50%);text-align:center}
.signal-gauge .gauge-val{font-size:18px;font-weight:800;font-family:'JetBrains Mono',monospace;line-height:1}
.signal-gauge .gauge-label{font-size:7px;font-weight:700;letter-spacing:1px;text-transform:uppercase;color:var(--txt3);margin-top:1px}
.signal-gauge .gauge-dir{font-size:8px;font-weight:800;letter-spacing:.5px}

/* ── GLOW EFFECTS ── */
.glow-green{box-shadow:0 0 20px rgba(16,185,129,.12),inset 0 0 20px rgba(16,185,129,.03);border-color:rgba(16,185,129,.2)!important}
.glow-red{box-shadow:0 0 20px rgba(239,68,68,.12),inset 0 0 20px rgba(239,68,68,.03);border-color:rgba(239,68,68,.2)!important}
.glow-purple{box-shadow:0 0 20px rgba(108,92,231,.15),inset 0 0 20px rgba(108,92,231,.04);border-color:rgba(108,92,231,.25)!important}
.stat-card:hover{transform:translateY(-1px);box-shadow:0 4px 20px rgba(108,92,231,.12)}

/* ── SPREAD BADGE ── */
.spread-badge{display:inline-flex;align-items:center;gap:3px;padding:2px 8px;border-radius:4px;font-size:9px;font-weight:600;font-family:'JetBrains Mono',monospace}
.spread-badge.ok{background:rgba(16,185,129,.08);color:var(--green);border:1px solid rgba(16,185,129,.15)}
.spread-badge.wide{background:rgba(245,158,11,.08);color:var(--gold);border:1px solid rgba(245,158,11,.15)}
.spread-badge.danger{background:rgba(239,68,68,.08);color:var(--red);border:1px solid rgba(239,68,68,.15)}

/* ── POSITION MAP (SPM/FIFO Tree) ── */
.pos-map{padding:6px 10px}
.pos-map-row{display:flex;align-items:center;gap:6px;padding:3px 0;font-size:10px;position:relative}
.pos-map-row::before{content:'';position:absolute;left:3px;top:0;bottom:0;width:1px;background:var(--border2)}
.pos-map-row:last-child::before{bottom:50%}
.pos-map-dot{width:8px;height:8px;border-radius:50%;flex-shrink:0;z-index:1;border:1.5px solid var(--bg2)}
.pos-map-dot.main{background:var(--purple);box-shadow:0 0 6px var(--purple-glow)}
.pos-map-dot.spm{background:var(--gold);box-shadow:0 0 4px rgba(245,158,11,.3)}
.pos-map-dot.hedge{background:var(--red);box-shadow:0 0 4px rgba(239,68,68,.3)}
.pos-map-info{flex:1;display:flex;justify-content:space-between;align-items:center}
.pos-map-info .pm-role{font-weight:700;font-size:9px;min-width:36px}
.pos-map-info .pm-dir{font-weight:600;font-size:9px;min-width:28px}
.pos-map-info .pm-lot{font-family:'JetBrains Mono',monospace;font-size:9px;color:var(--txt3)}
.pos-map-info .pm-pnl{font-family:'JetBrains Mono',monospace;font-size:10px;font-weight:700}

/* ── NEWS TICKER ── */
.ticker-wrap{overflow:hidden;white-space:nowrap;background:var(--glass);border-top:1px solid var(--border);height:22px;display:flex;align-items:center}
.ticker-track{display:inline-flex;animation:tickerScroll 40s linear infinite}
.ticker-item{display:inline-flex;align-items:center;gap:4px;padding:0 20px;font-size:9px;color:var(--txt2);font-weight:500}
.ticker-item .ti-dot{width:4px;height:4px;border-radius:50%;flex-shrink:0}
.ticker-item .ti-impact-HIGH{background:var(--red)}
.ticker-item .ti-impact-MEDIUM{background:var(--gold)}
.ticker-item .ti-impact-LOW{background:var(--txt3)}
@keyframes tickerScroll{0%{transform:translateX(0)}100%{transform:translateX(-50%)}}

/* ── INDICATOR MINI BARS (in symbol cards) ── */
.ind-bars{display:flex;gap:2px;margin-top:3px;height:3px}
.ind-bar-seg{flex:1;border-radius:1px;transition:background .3s,opacity .3s}
.ind-bar-seg.active{opacity:1}.ind-bar-seg.inactive{opacity:.3;background:var(--bg4)!important}

/* ── ANIMATED VALUE CHANGE ── */
@keyframes countUp{0%{opacity:.5;transform:translateY(3px)}100%{opacity:1;transform:translateY(0)}}
.val-changed{animation:countUp .3s ease-out}

/* ── LEVERAGE BADGE ── */
.lev-badge{display:inline-flex;align-items:center;gap:3px;padding:2px 8px;border-radius:4px;font-size:9px;font-weight:700;font-family:'JetBrains Mono',monospace;background:rgba(108,92,231,.08);color:var(--purple2);border:1px solid rgba(108,92,231,.15);letter-spacing:.3px}

/* ── SESSION TIMER ── */
.session-timer{font-family:'JetBrains Mono',monospace;font-size:9px;color:var(--txt3);display:flex;align-items:center;gap:4px}
.session-timer .st-dot{width:5px;height:5px;border-radius:50%;background:var(--green);animation:pulse 2s infinite}

.agent-row{display:flex;align-items:center;gap:7px;padding:3px 0;font-size:10px;color:var(--txt2)}
.agent-dot{width:7px;height:7px;border-radius:50%;flex-shrink:0}
.agent-dot.on{background:var(--purple);box-shadow:0 0 6px var(--purple-glow)}
.fg-row{display:flex;align-items:center;gap:10px;padding:4px 0}
.fg-bar{flex:1;height:7px;border-radius:4px;background:linear-gradient(90deg,var(--red),var(--gold),var(--green));position:relative;overflow:visible;box-shadow:0 0 8px rgba(0,0,0,.3)}
.fg-needle{position:absolute;top:-3px;width:3px;height:13px;background:#fff;border-radius:1px;transition:left .6s;box-shadow:0 0 4px rgba(255,255,255,.5)}
.fg-val{font-family:'JetBrains Mono',monospace;font-weight:700;font-size:13px;min-width:24px;text-align:right}
.fg-label{font-size:8px;color:var(--txt3);font-weight:500}
.grid-row{display:flex;justify-content:space-between;padding:2px 0;font-size:10px;color:var(--txt2)}
.grid-row .val{font-family:'JetBrains Mono',monospace;font-weight:600}

/* ── CENTER: CHART BAR (PolyARB Style) ── */
.chart-bar{display:flex;align-items:center;gap:8px;padding:5px 12px;background:var(--glass);backdrop-filter:blur(16px);border-bottom:1px solid var(--border);flex-shrink:0}
.chart-tabs{display:flex;gap:2px;background:var(--bg3);border-radius:6px;padding:2px}
.ct-btn{background:0;border:0;color:var(--txt3);padding:5px 14px;font-size:9px;font-weight:600;letter-spacing:.5px;cursor:pointer;border-radius:4px;transition:all .2s;font-family:'Inter',sans-serif;text-transform:uppercase}
.ct-btn:hover{color:var(--txt2)}.ct-btn.active{background:var(--purple);color:#fff;box-shadow:0 0 12px rgba(108,92,231,.3)}
.chart-sym-info{display:flex;align-items:center;gap:8px;margin-left:12px}
.csi-name{font-weight:700;font-size:13px;color:var(--txt)}
.csi-price{font-size:14px;font-weight:700;color:var(--purple2);font-family:'JetBrains Mono',monospace}
.csi-change{font-size:9px;font-weight:700;padding:2px 8px;border-radius:4px}
.csi-change.up{background:rgba(16,185,129,.12);color:var(--green)}
.csi-change.down{background:rgba(239,68,68,.12);color:var(--red)}
.chart-periods{display:flex;gap:2px;margin-left:auto;background:var(--bg3);border-radius:6px;padding:2px;align-items:center}
.cp-btn{background:0;border:0;color:var(--txt3);padding:5px 12px;font-size:9px;font-weight:600;cursor:pointer;border-radius:4px;transition:all .2s;font-family:'Inter',sans-serif}
.cp-btn:hover{color:var(--txt2)}.cp-btn.active{background:var(--purple);color:#fff;box-shadow:0 0 12px rgba(108,92,231,.3)}
.cp-refresh{background:0;border:0;color:var(--txt3);padding:4px 8px;cursor:pointer;font-size:14px;transition:all .3s;border-radius:4px;line-height:1}
.cp-refresh:hover{color:var(--purple2);transform:rotate(180deg)}
.chart-view{flex:1;min-height:0;display:none;overflow:hidden}
.chart-view.active{display:block}

/* ── MINI CHARTS ── */
.mini-charts{display:flex;gap:1px;height:120px;flex-shrink:0;border-top:1px solid var(--border)}
.mini-col{flex:1;background:var(--glass);backdrop-filter:blur(16px);display:flex;flex-direction:column;overflow:hidden}
.mini-col .mc-title{font-size:8px;font-weight:700;color:var(--purple2);letter-spacing:1.2px;text-transform:uppercase;padding:6px 10px 2px}
.mini-col .mc-wrap{flex:1;padding:2px 6px;min-height:0}

/* ── RIGHT PANEL ── */
.rp-section{border-bottom:1px solid var(--border)}
.pos-card{background:var(--glass2);backdrop-filter:blur(12px);border:1px solid var(--border);border-radius:8px;padding:10px;margin:0 10px 6px;transition:all .3s}
.pos-card:hover{border-color:var(--border2);box-shadow:0 0 16px rgba(108,92,231,.06)}
.pos-card.buy{border-left:3px solid var(--green)}
.pos-card.sell{border-left:3px solid var(--red)}
.pos-card .pc-top{display:flex;justify-content:space-between;align-items:center;margin-bottom:5px}
.pos-card .pc-sym{font-weight:700;font-size:12px}
.pos-card .pc-dir{font-size:9px;font-weight:700;padding:2px 8px;border-radius:4px}
.pos-card .pc-dir.BUY{background:rgba(16,185,129,.1);color:var(--green)}
.pos-card .pc-dir.SELL{background:rgba(239,68,68,.1);color:var(--red)}
.pos-card .pc-row{display:flex;justify-content:space-between;font-size:10px;color:var(--txt3);padding:1px 0}
.pos-card .pc-row .val{font-family:'JetBrains Mono',monospace;color:var(--txt2);font-weight:500}
.pos-card .pc-pnl{font-size:16px;font-weight:800;font-family:'JetBrains Mono',monospace;text-align:center;padding:5px 0 3px}
.pos-card .pc-progress{height:2px;background:var(--bg4);border-radius:1px;margin-top:3px;overflow:hidden}
.pos-card .pc-progress .fill{height:100%;border-radius:1px;transition:width .5s}
.role-badge{padding:2px 6px;border-radius:4px;font-size:8px;font-weight:700;letter-spacing:.5px}
.role-MAIN{background:rgba(108,92,231,.15);color:var(--purple2)}
.role-SPM1,.role-SPM2{background:rgba(167,139,250,.12);color:var(--purple2)}
.role-HEDGE{background:rgba(239,68,68,.12);color:var(--red)}
.role-DCA{background:rgba(245,158,11,.12);color:var(--gold)}
.dir-BUY{color:var(--green)}.dir-SELL{color:var(--red)}
.trade-row{display:flex;align-items:center;padding:5px 12px;border-bottom:1px solid var(--border);font-size:10px;gap:6px;transition:background .2s}
.trade-row:hover{background:rgba(108,92,231,.04)}
.trade-row .t-time{color:var(--txt3);font-family:'JetBrains Mono',monospace;font-size:9px;min-width:48px}
.trade-row .t-sym{font-weight:600;min-width:55px;font-size:10px}
.trade-row .t-dir{font-weight:700;min-width:30px;font-size:9px}
.trade-row .t-lot{color:var(--txt3);min-width:38px;font-family:'JetBrains Mono',monospace;font-size:10px}
.trade-row .t-pnl{font-weight:700;font-family:'JetBrains Mono',monospace;margin-left:auto;font-size:10px}
.log-entry{display:flex;gap:6px;padding:4px 12px;font-size:10px;border-bottom:1px solid rgba(255,255,255,.02)}
.log-entry .log-time{color:var(--txt3);font-family:'JetBrains Mono',monospace;font-size:9px;min-width:48px;flex-shrink:0}
.log-entry .log-msg{color:var(--txt2);word-break:break-word}
.log-entry.green .log-msg{color:var(--green)}
.log-entry.red .log-msg{color:var(--red)}
.log-entry.blue .log-msg{color:var(--purple2)}
.log-entry.gold .log-msg{color:var(--gold)}
.brain-text{font-size:10px;color:var(--txt2);line-height:1.5;padding:0 10px;max-height:80px;overflow-y:auto}

/* ── CHART LEGEND ── */
.chart-legend{position:absolute;top:8px;left:12px;display:flex;gap:12px;z-index:5;pointer-events:none}
.cl-item{display:flex;align-items:center;gap:4px;font-size:9px;color:var(--txt3);font-weight:500}
.cl-line{width:14px;height:2px;border-radius:1px}

@keyframes pulse{0%,100%{opacity:1}50%{opacity:.4}}
@keyframes fadeIn{from{opacity:0;transform:translateY(4px)}to{opacity:1;transform:none}}
.fadeIn{animation:fadeIn .3s ease-out}
.empty{color:var(--txt3);font-size:10px;padding:18px;text-align:center;font-weight:500}
</style>
</head>
<body>
<div class="app">
  <!-- TOP BAR -->
  <div class="topbar">
    <div class="logo"><div class="logo-dot"></div><div><span class="logo-text">MIA v5.2.0</span><br><span class="logo-sub">BYTAMERFX TERMINAL</span></div></div>
    <div class="tb-sep"></div>
    <div class="tb-stat"><span class="label">Bakiye</span><span class="val mono" id="tb-bal">$0.00</span></div>
    <div class="tb-stat"><span class="label">Equity</span><span class="val mono" id="tb-eq">$0.00</span></div>
    <div class="tb-sep"></div>
    <div class="tb-stat"><span class="label">Gunluk P&L</span><span class="val mono" id="tb-dpnl">$0.00</span></div>
    <div class="tb-stat"><span class="label">Floating</span><span class="val mono" id="tb-fpnl">$0.00</span></div>
    <div class="tb-sep"></div>
    <div class="tb-stat"><span class="label">Drawdown</span><span class="val mono" id="tb-dd">0.0%</span></div>
    <div class="tb-stat"><span class="label">Margin</span><span class="val mono" id="tb-margin">0%</span></div>
    <div class="tb-right">
      <span class="lev-badge" id="tb-lev">1:---</span>
      <span class="badge badge-session" id="tb-session">---</span>
      <span class="badge badge-risk MEDIUM" id="tb-risk">MEDIUM</span>
      <span class="session-timer"><span class="st-dot"></span><span id="tb-uptime">00:00:00</span></span>
      <span class="tb-clock mono" id="tb-clock">00:00:00 UTC</span>
      <span class="conn-dot off" id="conn-dot"></span>
    </div>
  </div>

  <!-- STAT CARDS ROW -->
  <div class="statrow">
    <div class="stat-card accent"><span class="sc-val val-neutral" id="sc-portfolio">$0.00</span><span class="sc-label">Portfoy Degeri</span></div>
    <div class="stat-card"><span class="sc-val" id="sc-tpnl">$0.00</span><span class="sc-label">Toplam PNL</span></div>
    <div class="stat-card"><span class="sc-val" id="sc-realized">$0.00</span><span class="sc-label">Realized</span></div>
    <div class="stat-card"><span class="sc-val" id="sc-unrealized">$0.00</span><span class="sc-label">Unrealized</span></div>
    <div class="stat-card"><span class="sc-val val-neutral" id="sc-trades">0</span><span class="sc-label">Acik Pozisyon</span></div>
    <div class="stat-card"><span class="sc-val val-neutral" id="sc-winrate">0.0%</span><span class="sc-label">Win Rate</span></div>
  </div>

  <!-- LEFT SIDEBAR -->
  <div class="left">
    <div class="panel">
      <div class="panel-title">Win Rate</div>
      <div class="wr-container">
        <div class="wr-donut"><canvas id="wr-chart"></canvas><div class="wr-center"><span class="wr-val" id="wr-val">0%</span><br><span class="wr-sub">WIN</span></div></div>
        <div class="wr-stats">
          <div class="wr-row"><span class="dot" style="background:var(--green)"></span>Karli <strong id="wr-wins" class="mono">0</strong></div>
          <div class="wr-row"><span class="dot" style="background:var(--red)"></span>Zarari <strong id="wr-losses" class="mono">0</strong></div>
          <div class="wr-row"><span class="dot" style="background:var(--purple2)"></span>Acik <strong id="wr-open" class="mono">0</strong></div>
        </div>
      </div>
    </div>
    <div class="panel">
      <div class="panel-title">Semboller</div>
      <div id="sym-list"></div>
    </div>
    <div class="panel">
      <div class="panel-title">Fear & Greed</div>
      <div class="fg-row"><div class="fg-bar"><div class="fg-needle" id="fg-needle" style="left:50%"></div></div><span class="fg-val" id="fg-val">50</span></div>
      <div style="text-align:center"><span class="fg-label" id="fg-label">Neutral</span></div>
    </div>
    <div class="panel">
      <div class="panel-title">Grid / FIFO</div>
      <div>
        <div class="grid-row"><span>Kasa</span><span class="mono val" id="grid-kasa">$0.00</span></div>
        <div class="grid-row"><span>Net PNL</span><span class="mono val" id="grid-net">$0.00</span></div>
        <div class="grid-row"><span>Hedef</span><span class="mono val" id="grid-target">$5.00</span></div>
        <div class="grid-row" style="margin-top:4px"><span>FIFO</span><span class="mono" id="fifo-pct" style="font-size:9px;color:var(--purple2)">0%</span></div>
        <div class="progress-bar progress-purple" id="fifo-progress"><div class="progress-fill" style="width:0%"></div></div>
      </div>
    </div>
    <div class="panel" id="ss-panel">
      <div class="panel-title">Safety Shield <span class="mono" id="ss-badge" style="font-size:9px;padding:1px 6px;border-radius:3px;margin-left:4px;background:rgba(16,185,129,.15);color:var(--green)">NORMAL</span></div>
      <div>
        <div class="grid-row"><span>Equity</span><span class="mono val" id="ss-eq" style="color:var(--green)">100%</span></div>
        <div class="grid-row"><span>Margin</span><span class="mono val" id="ss-mg">--</span></div>
        <div class="grid-row"><span>Hedge</span><span class="mono val" id="ss-hg" style="color:var(--green)">OK</span></div>
        <div class="grid-row"><span>Sym Loss</span><span class="mono val" id="ss-sl" style="color:var(--green)">OK</span></div>
        <div id="ss-alert" style="display:none;margin-top:4px;padding:4px 6px;font-size:9px;border-radius:4px;border:1px solid var(--gold);color:var(--gold);background:rgba(245,158,11,.08)"></div>
      </div>
    </div>
    <div class="panel">
      <div class="panel-title">Sinyal Motoru</div>
      <div class="signal-gauge-wrap">
        <div class="signal-gauge" id="gauge-buy">
          <svg viewBox="0 0 80 80"><circle class="gauge-bg" cx="40" cy="40" r="34"/><circle class="gauge-fill" id="gauge-buy-fill" cx="40" cy="40" r="34" stroke="var(--green)" stroke-dasharray="213.6" stroke-dashoffset="213.6"/></svg>
          <div class="gauge-center"><div class="gauge-val" id="sig-buy" style="color:var(--green)">0</div><div class="gauge-dir" style="color:var(--green)">BUY</div><div class="gauge-label">SCORE</div></div>
        </div>
        <div style="display:flex;flex-direction:column;align-items:center;gap:2px">
          <div class="mono" style="font-size:8px;color:var(--txt3);font-weight:600">VS</div>
          <div id="sig-dominant" style="font-size:10px;font-weight:800;padding:2px 8px;border-radius:4px;letter-spacing:.5px">---</div>
        </div>
        <div class="signal-gauge" id="gauge-sell">
          <svg viewBox="0 0 80 80"><circle class="gauge-bg" cx="40" cy="40" r="34"/><circle class="gauge-fill" id="gauge-sell-fill" cx="40" cy="40" r="34" stroke="var(--red)" stroke-dasharray="213.6" stroke-dashoffset="213.6"/></svg>
          <div class="gauge-center"><div class="gauge-val" id="sig-sell" style="color:var(--red)">0</div><div class="gauge-dir" style="color:var(--red)">SELL</div><div class="gauge-label">SCORE</div></div>
        </div>
      </div>
      <div id="sig-bars" style="margin-top:4px"></div>
    </div>
    <div class="panel" id="pos-map-panel" style="display:none">
      <div class="panel-title">Pozisyon Haritasi</div>
      <div class="pos-map" id="pos-map-content"></div>
    </div>
  </div>

  <!-- CENTER: PolyARB-Style Chart Area -->
  <div class="center">
    <!-- Chart Control Bar -->
    <div class="chart-bar">
      <div class="chart-tabs">
        <button class="ct-btn active" data-view="candle">Grafik</button>
        <button class="ct-btn" data-view="pnl">PNL</button>
        <button class="ct-btn" data-view="log">Log</button>
      </div>
      <div class="chart-sym-info">
        <span class="csi-name" id="csi-name">---</span>
        <span class="csi-price mono" id="csi-price">0.000</span>
        <span class="csi-change up" id="csi-change">0.00%</span>
        <span class="spread-badge ok" id="csi-spread">Spread: --</span>
        <span class="ind-chip ind-atr" id="csi-atr" style="font-size:9px">ATR: --</span>
      </div>
      <div class="chart-periods">
        <button class="cp-btn" data-tf="1h">1S</button>
        <button class="cp-btn" data-tf="6h">6S</button>
        <button class="cp-btn active" data-tf="24h">24S</button>
        <button class="cp-btn" data-tf="all">TUMU</button>
        <button class="cp-refresh" onclick="refreshChart()" title="Yenile">&#8635;</button>
      </div>
    </div>
    <!-- Candlestick Chart -->
    <div class="chart-view active" id="view-candle" style="position:relative">
      <div class="chart-legend" id="candle-legend">
        <div class="cl-item"><div class="cl-line" style="background:#6c5ce7"></div>EMA8</div>
        <div class="cl-item"><div class="cl-line" style="background:#a78bfa"></div>EMA21</div>
        <div class="cl-item"><div class="cl-line" style="background:#f59e0b;opacity:.6"></div>EMA50</div>
        <div class="cl-item"><div class="cl-line" style="background:rgba(167,139,250,.25);height:6px"></div>BB</div>
      </div>
      <div id="candle-chart" style="width:100%;height:100%"></div>
    </div>
    <!-- PNL Baseline Chart -->
    <div class="chart-view" id="view-pnl"><div id="pnl-chart" style="width:100%;height:100%"></div></div>
    <!-- Live Log -->
    <div class="chart-view" id="view-log" style="overflow-y:auto;padding:4px 0"><div id="log-list"></div></div>
    <!-- News Ticker -->
    <div class="ticker-wrap" id="news-ticker"><div class="ticker-track" id="ticker-track"></div></div>
    <!-- Bottom Mini Charts -->
    <div class="mini-charts">
      <div class="mini-col"><div class="mc-title">Portfoy Degeri</div><div class="mc-wrap"><canvas id="eq-chart"></canvas></div></div>
      <div class="mini-col"><div class="mc-title">Realized vs Unrealized PNL</div><div class="mc-wrap"><canvas id="ru-chart"></canvas></div></div>
      <div class="mini-col"><div class="mc-title">Win Rate Trendi</div><div class="mc-wrap"><canvas id="wrt-chart"></canvas></div></div>
    </div>
  </div>

  <!-- RIGHT PANEL -->
  <div class="right">
    <div class="rp-section">
      <div class="panel"><div class="panel-title">Acik Pozisyonlar<span class="tab-count" id="rp-pos-count" style="margin-left:4px">0</span></div></div>
      <div id="pos-cards"></div>
    </div>
    <div class="rp-section">
      <div class="panel"><div class="panel-title">Islem Gecmisi<span class="tab-count" id="hist-count" style="margin-left:4px">0</span></div></div>
      <div id="history-list" style="max-height:200px;overflow-y:auto"></div>
      <div class="empty" id="hist-empty">Henuz kapanan islem yok</div>
    </div>
    <div class="rp-section">
      <div class="panel"><div class="panel-title">Brain Analizi</div></div>
      <div class="brain-text" id="brain-text">Bekleniyor...</div>
    </div>
    <div class="panel">
      <div class="panel-title">Yaklasan Haberler</div>
      <div id="news-feed" style="font-size:10px;color:var(--txt2);max-height:140px;overflow-y:auto"><div class="empty">Haber bekleniyor...</div></div>
    </div>
  </div>
</div>

<script>
/* ══════════════════════════════════════════════
   MIA v5.2.0 — BytamerFX Trading Terminal
   Signal Gauges + Position Map + News Ticker
   ══════════════════════════════════════════════ */
let S=null,connected=false,selectedSym=null,prevState={};
let candleChart=null,candleSeries=null,emaSeries={},volumeSeries=null,bbUpper=null,bbLower=null;
let pnlChart=null,pnlBaseline=null,pnlEqLine=null;
let eqChartJs=null,ruChartJs=null,wrtChartJs=null,wrDonut=null;
let pnlHistory=[],wrHistory=[];
let currentView='candle',currentTF='24h';
const REFRESH=1000;
let prevPrices={};

const $=id=>document.getElementById(id);
const fmt=(v,d=2)=>(v||0).toFixed(d);
const fmtUsd=v=>{const n=v||0;return(n>=0?'+':'')+n.toFixed(2)};
const pnlClass=v=>v>0?'val-up':v<0?'val-down':'val-neutral';
const pnlColor=v=>v>0?'var(--green)':v<0?'var(--red)':'var(--txt3)';
function flashEl(el,o,n){if(o===undefined||o===n)return;el.classList.remove('flash-up','flash-down');void el.offsetWidth;el.classList.add(n>o?'flash-up':'flash-down')}

/* ── View Tab Switching ── */
document.querySelectorAll('.ct-btn').forEach(btn=>{
  btn.onclick=()=>{
    document.querySelectorAll('.ct-btn').forEach(b=>b.classList.remove('active'));
    document.querySelectorAll('.chart-view').forEach(v=>v.classList.remove('active'));
    btn.classList.add('active');currentView=btn.dataset.view;
    $('view-'+currentView).classList.add('active');
    if(currentView==='candle'){if(!candleChart)initCandleChart();else renderCandleChart()}
    if(currentView==='pnl'){if(!pnlChart)initPnlChart();updatePnlChart()}
  };
});

/* ── Time Period Switching ── */
document.querySelectorAll('.cp-btn').forEach(btn=>{
  btn.onclick=()=>{
    document.querySelectorAll('.cp-btn').forEach(b=>b.classList.remove('active'));
    btn.classList.add('active');currentTF=btn.dataset.tf;
    if(currentView==='candle')renderCandleChart();
    if(currentView==='pnl')renderPnlPeriod();
  };
});
function refreshChart(){if(currentView==='candle')renderCandleChart();if(currentView==='pnl')renderPnlPeriod()}

/* ── Data Fetch ── */
async function fetchState(){
  try{const r=await fetch('/api/state?t='+Date.now());if(!r.ok)throw 0;S=await r.json();connected=true;$('conn-dot').classList.remove('off');updateAll()}
  catch(e){connected=false;$('conn-dot').classList.add('off')}
}
function updateAll(){
  if(!S)return;updateTopBar();updateStatCards();updateLeft();updatePositions();updateHistory();updateLog();updateRight();updateChartHeader();updateMiniCharts();
  if(currentView==='candle'&&candleChart)renderCandleChart();
  if(currentView==='pnl')updatePnlChart();
  prevState=JSON.parse(JSON.stringify(S));
}

/* ── Top Bar ── */
function updateTopBar(){
  const a=S.account;
  setVal('tb-bal','$'+fmt(a.balance),a.balance,prevState?.account?.balance);
  setVal('tb-eq','$'+fmt(a.equity),a.equity,prevState?.account?.equity);
  setVal('tb-dpnl','$'+fmtUsd(a.daily_pnl),a.daily_pnl);
  $('tb-dpnl').className='val mono '+pnlClass(a.daily_pnl);
  setVal('tb-fpnl','$'+fmtUsd(a.floating_pnl),a.floating_pnl);
  $('tb-fpnl').className='val mono '+pnlClass(a.floating_pnl);
  $('tb-dd').textContent=fmt(a.drawdown_pct,1)+'%';
  $('tb-dd').className='val mono '+(a.drawdown_pct>15?'val-down':a.drawdown_pct>8?'val-warn':'val-neutral');
  $('tb-margin').textContent=fmt(a.margin_level,0)+'%';
  $('tb-margin').className='val mono '+(a.margin_level>0&&a.margin_level<300?'val-warn':a.margin_level>0&&a.margin_level<150?'val-down':'val-neutral');
  $('tb-session').textContent=S.context?.session||'---';
  const r=S.brain?.global_risk||'MEDIUM';const e=$('tb-risk');e.textContent=r;e.className='badge badge-risk '+r;
  /* Leverage */
  const lev=a.leverage||0;if(lev>0)$('tb-lev').textContent='1:'+lev;
  /* Stat card glow effects */
  const fpnl=a.floating_pnl||0;
  const posCard=document.querySelector('.stat-card.accent');
  if(posCard){posCard.classList.remove('glow-green','glow-red','glow-purple');
    if(fpnl>2)posCard.classList.add('glow-green');
    else if(fpnl<-2)posCard.classList.add('glow-red');
    else posCard.classList.add('glow-purple')}
}
function setVal(id,text,nv,ov){const e=$(id);e.textContent=text;if(ov!==undefined&&ov!==nv)flashEl(e,ov,nv)}

/* ── Stat Cards ── */
function updateStatCards(){
  const a=S.account,ts=S.trade_stats||{};
  const real=ts.total_realized||0,unr=a.floating_pnl||0,tot=real+unr;
  $('sc-portfolio').textContent='$'+fmt(a.equity);
  $('sc-tpnl').textContent='$'+fmtUsd(tot);$('sc-tpnl').className='sc-val '+pnlClass(tot);
  $('sc-realized').textContent='$'+fmtUsd(real);$('sc-realized').className='sc-val '+pnlClass(real);
  $('sc-unrealized').textContent='$'+fmtUsd(unr);$('sc-unrealized').className='sc-val '+pnlClass(unr);
  $('sc-trades').textContent=a.open_positions||0;
  const wr=ts.win_rate||0;$('sc-winrate').textContent=fmt(wr,1)+'%';
  $('sc-winrate').className='sc-val '+(wr>=50?'val-up':wr>0?'val-warn':'val-neutral');
}

/* ── Left Sidebar ── */
function updateLeft(){
  const ts=S.trade_stats||{},w=ts.wins||0,l=ts.losses||0,o=S.account?.open_positions||0;
  $('wr-val').textContent=fmt(ts.win_rate||0,0)+'%';$('wr-wins').textContent=w;$('wr-losses').textContent=l;$('wr-open').textContent=o;
  updateWrDonut(w,l,o);

  /* Symbols — anlık fiyat güncellemesi */
  const syms=S.active_symbols||[],tech=S.technicals||{};
  if(!selectedSym&&syms.length)selectedSym=syms[0];
  let h='';syms.forEach(sym=>{
    const t=tech[sym]||{},bs=t.buy_score||0,ss=t.sell_score||0;
    const price=t.price||0;
    const prevP=prevPrices[sym]||price;
    const priceColor=price>prevP?'var(--green)':price<prevP?'var(--red)':'var(--purple2)';
    prevPrices[sym]=price;
    const rsi=t.rsi_m15||0,adx=t.adx||0,atr=t.atr_m15||0,trend=t.trend_aligned;
    const rsiCls=rsi>70?'hot':rsi<30?'cold':'';
    const adxCls=adx>25?'strong':'';
    const trendCls=(t.macd_hist||0)<0?'down':'';
    h+='<div class="sym-card'+(sym===selectedSym?' active':'')+'" onclick="selectSym(\''+sym+'\')">';
    h+='<div style="flex:1"><div style="display:flex;justify-content:space-between;align-items:center">';
    h+='<div class="sym-name">'+sym+'</div>';
    h+='<div class="sym-price" style="color:'+priceColor+'">'+fmt(price,price>1000?2:price>10?3:5)+'</div></div>';
    h+='<div class="sym-score"><div class="bar" style="width:'+Math.min(50,bs)+'px;background:var(--green)"></div><div class="bar" style="width:'+Math.min(50,ss)+'px;background:var(--red)"></div></div>';
    h+='<div class="sym-inds">';
    if(rsi>0)h+='<span class="ind-chip ind-rsi '+rsiCls+'">RSI '+fmt(rsi,0)+'</span>';
    if(adx>0)h+='<span class="ind-chip ind-adx '+adxCls+'">ADX '+fmt(adx,0)+'</span>';
    if(atr>0)h+='<span class="ind-chip ind-atr">ATR '+fmt(atr,atr>1?1:4)+'</span>';
    if(trend!==undefined)h+='<span class="ind-chip ind-trend '+trendCls+'">'+(trend?'TREND':'FLAT')+'</span>';
    h+='</div>';
    /* Mini indicator strength bars */
    const barScores=[t.ema_score||0,t.macd_score||0,t.adx_score||0,t.rsi_score||0,t.bb_score||0,t.stoch_score||0];
    const barMax=[20,20,15,15,15,15];
    const barColors=['#6c5ce7','#a78bfa','#3b82f6','#06d6a0','#f59e0b','#ec4899'];
    h+='<div class="ind-bars" title="EMA|MACD|ADX|RSI|BB|STOCH">';
    barScores.forEach((v,i)=>{const pct=barMax[i]>0?(v/barMax[i]):0;
      h+='<div class="ind-bar-seg '+(pct>0.2?'active':'inactive')+'" style="background:'+barColors[i]+';opacity:'+(0.3+pct*0.7).toFixed(2)+'"></div>';
    });
    h+='</div>';
    h+='</div></div>';
  });
  $('sym-list').innerHTML=h;

  /* Fear & Greed */
  const fg=S.context?.fear_greed_index??50;$('fg-val').textContent=fg;
  $('fg-val').style.color=fg<25?'var(--red)':fg<45?'var(--gold)':fg<55?'var(--txt)':fg<75?'var(--green)':'var(--purple2)';
  $('fg-needle').style.left=fg+'%';$('fg-label').textContent=S.context?.fear_greed_label||'Neutral';

  /* Grid/FIFO */
  const grid=S.brain?.grid||{},summ=grid.summaries||{};let kasa=0,net=0,tgt=5;
  Object.values(summ).forEach(s=>{kasa+=s.kasa||0;net+=s.net||0;tgt=s.target||5});
  $('grid-kasa').textContent='$'+fmt(kasa);$('grid-kasa').style.color=pnlColor(kasa);
  $('grid-net').textContent='$'+fmtUsd(net);$('grid-net').style.color=pnlColor(net);
  $('grid-target').textContent='$'+fmt(tgt);
  /* FIFO Progress Bar */
  const fifoBar=$('fifo-progress');
  if(fifoBar){const pct=tgt>0?Math.min(100,Math.max(0,(kasa/tgt)*100)):0;
    fifoBar.querySelector('.progress-fill').style.width=pct+'%';
    const barCls=pct>=80?'progress-green':pct>=40?'progress-purple':'progress-red';
    fifoBar.className='progress-bar '+barCls;
    const lbl=$('fifo-pct');if(lbl)lbl.textContent=fmt(pct,0)+'%';}
  /* Safety Shield */
  const ss=S.safety_shield||{};
  const ssSt=ss.status||'NORMAL';
  const ssBadge=$('ss-badge');
  const ssColors={NORMAL:['var(--green)','rgba(16,185,129,.15)','ok'],WARNING:['var(--gold)','rgba(245,158,11,.15)','warn'],CRITICAL:['var(--red)','rgba(239,68,68,.15)','crit'],EMERGENCY:['var(--red)','rgba(239,68,68,.25)','crit']};
  const ssC=ssColors[ssSt]||ssColors.NORMAL;
  ssBadge.innerHTML='<span class="status-pulse '+ssC[2]+'"></span>'+ssSt;ssBadge.style.color=ssC[0];ssBadge.style.background=ssC[1];
  const eqR=ss.equity_ratio||100;$('ss-eq').textContent=fmt(eqR,1)+'%';
  $('ss-eq').style.color=eqR<(ss.equity_threshold||30)?'var(--red)':eqR<45?'var(--gold)':'var(--green)';
  const ml=ss.margin_level||0;$('ss-mg').textContent=ml>0?fmt(ml,0)+'%':'--';
  $('ss-mg').style.color=ml>0&&ml<(ss.margin_emergency||150)?'var(--red)':ml>0&&ml<(ss.margin_guard||300)?'var(--gold)':'var(--green)';
  const hd=ss.hedge_details||{};let wH=null;
  Object.entries(hd).forEach(([sy,hx])=>{hx.forEach(h=>{if(!wH||h.age_sec>wH.age_sec)wH={...h,sy}})});
  if(wH){const m=(wH.age_sec/60).toFixed(1),mx=((ss.hedge_max_time||600)/60).toFixed(0);$('ss-hg').textContent=wH.sy+' '+m+'/'+mx+'dk';$('ss-hg').style.color=wH.age_sec>(ss.hedge_max_time||600)*.8?'var(--red)':'var(--gold)'}
  else{$('ss-hg').textContent='OK';$('ss-hg').style.color='var(--green)'}
  const sp=ss.symbol_pnl||{},bal=S.account?.balance||1;let wS=null,wP=0;
  Object.entries(sp).forEach(([sy,pn])=>{if(pn<0){const pc=Math.abs(pn)/bal*100;if(pc>wP){wP=pc;wS=sy}}});
  if(wS){$('ss-sl').textContent=wS+' -'+fmt(wP,0)+'%';$('ss-sl').style.color=wP>(ss.symbol_max_loss_pct||50)*.8?'var(--red)':'var(--gold)'}
  else{$('ss-sl').textContent='OK';$('ss-sl').style.color='var(--green)'}
  const ssAlrt=$('ss-alert');
  if(ss.last_alert&&ssSt!=='NORMAL'){ssAlrt.style.display='';ssAlrt.textContent=ss.last_alert;ssAlrt.style.color=ssC[0];ssAlrt.style.borderColor=ssC[0];ssAlrt.style.background=ssC[1]}
  else{ssAlrt.style.display='none'}
}
function selectSym(s){selectedSym=s;updateChartHeader();if(candleChart)renderCandleChart()}

function updateWrDonut(w,l,o){
  const t=w+l+o;
  if(!wrDonut){wrDonut=new Chart($('wr-chart'),{type:'doughnut',data:{datasets:[{data:[w||1,l||0,o||0],backgroundColor:['#10b981','#ef4444','#6c5ce7'],borderWidth:0}]},options:{cutout:'70%',responsive:false,plugins:{legend:{display:false},tooltip:{enabled:false}},animation:{duration:600}}})}
  else{wrDonut.data.datasets[0].data=t>0?[w,l,o]:[1,0,0];wrDonut.update('none')}
}

/* ── Chart Header (symbol info) ── */
function updateChartHeader(){
  if(!S)return;
  const sym=selectedSym||'---',t=S.technicals?.[sym]||{};
  $('csi-name').textContent=sym;
  const price=t.price||0;
  $('csi-price').textContent=price>1000?fmt(price,2):price>10?fmt(price,3):fmt(price,5);
  /* Candles'tan % degisim hesapla */
  const candles=t.candles_m15||[];
  if(candles.length>=2){
    const first=candles[0].o||candles[0].c,last=candles[candles.length-1].c;
    if(first>0){const pct=((last-first)/first*100);const el=$('csi-change');el.textContent=(pct>=0?'+':'')+pct.toFixed(2)+'%';el.className='csi-change '+(pct>=0?'up':'down')}
  }
}

/* ── Positions (Right Panel) ── */
function updatePositions(){
  const pos=S.positions||{},tech=S.technicals||{};let allPos=[];
  Object.keys(pos).forEach(sym=>{const sp=pos[sym],list=sp.positions||sp||[],price=tech[sym]?.price||0;
    (Array.isArray(list)?list:[]).forEach(p=>{allPos.push({...p,symbol:sp.symbol||sym,current_price:price})})});
  $('rp-pos-count').textContent=allPos.length;
  const el=$('pos-cards');
  if(!allPos.length){el.innerHTML='<div class="empty">Acik pozisyon yok</div>';return}
  let h='';allPos.forEach(p=>{const pnl=p.profit||0,peak=p.peak_profit||0,pct=peak>0?Math.min(100,(pnl/peak)*100):0;
    h+='<div class="pos-card '+(p.direction==='BUY'?'buy':'sell')+'"><div class="pc-top"><span class="pc-sym">'+p.symbol+'</span><span class="pc-dir '+p.direction+'">'+p.direction+'</span></div><div class="pc-row"><span>Rol</span><span class="val"><span class="role-badge role-'+p.role+'">'+p.role+'</span></span></div><div class="pc-row"><span>Lot</span><span class="val">'+fmt(p.lot,2)+'</span></div><div class="pc-row"><span>Giris</span><span class="val">'+fmt(p.open_price,p.open_price>1000?2:4)+'</span></div><div class="pc-pnl" style="color:'+pnlColor(pnl)+'">$'+fmtUsd(pnl)+'</div><div class="pc-progress"><div class="fill" style="width:'+Math.abs(pct)+'%;background:'+(pnl>=0?'var(--green)':'var(--red)')+'"></div></div></div>'});
  el.innerHTML=h;
}

/* ── Trade History ── */
function updateHistory(){
  const trades=S.trade_history||[];$('hist-count').textContent=trades.length;
  if(!trades.length){$('hist-empty').style.display='block';$('history-list').innerHTML='';return}
  $('hist-empty').style.display='none';let h='';
  [...trades].reverse().forEach(t=>{h+='<div class="trade-row fadeIn"><span class="t-time">'+t.closed_at+'</span><span class="t-sym">'+t.symbol+'</span><span class="t-dir dir-'+t.direction+'">'+t.direction+'</span><span class="t-lot">'+fmt(t.lot,2)+'</span><span class="role-badge role-'+t.role+'">'+t.role+'</span><span class="t-pnl" style="color:'+pnlColor(t.pnl)+'">$'+fmtUsd(t.pnl)+'</span></div>'});
  $('history-list').innerHTML=h;
}

/* ── Live Log ── */
function updateLog(){
  const logs=S.recent_logs||[];let h='';
  [...logs].reverse().slice(0,50).forEach(l=>{const c=l.type==='green'?'green':l.type==='red'?'red':l.type==='blue'?'blue':l.type==='gold'?'gold':'';
    h+='<div class="log-entry '+c+'"><span class="log-time">'+l.time+'</span><span class="log-msg">'+l.msg+'</span></div>'});
  $('log-list').innerHTML=h;
}

/* ── Right Panel (Signals, Brain, News) ── */
function updateRight(){
  const t=S.technicals?.[selectedSym]||{};
  const bs=t.buy_score||0,ss=t.sell_score||0;
  $('sig-buy').textContent=bs;$('sig-sell').textContent=ss;
  /* Signal Gauge Animation */
  updateSignalGauge('gauge-buy-fill',bs);updateSignalGauge('gauge-sell-fill',ss);
  /* Dominant signal badge */
  const domEl=$('sig-dominant');
  if(bs>ss&&bs>=30){domEl.textContent='BUY';domEl.style.background='rgba(16,185,129,.15)';domEl.style.color='var(--green)'}
  else if(ss>bs&&ss>=30){domEl.textContent='SELL';domEl.style.background='rgba(239,68,68,.15)';domEl.style.color='var(--red)'}
  else{domEl.textContent='BEKLE';domEl.style.background='rgba(113,113,122,.15)';domEl.style.color='var(--txt3)'}

  /* Indicator breakdown bars */
  const ind=['EMA','MACD','ADX','RSI','BB','STCH','ATR'],keys=['ema_score','macd_score','adx_score','rsi_score','bb_score','stoch_score','atr_score'],mx=[20,20,15,15,15,15,5];
  const indColors=['#6c5ce7','#a78bfa','#3b82f6','#06d6a0','#f59e0b','#ec4899','#71717a'];
  let h='';ind.forEach((n,i)=>{const v=t[keys[i]]||0,pct=Math.min(100,(v/mx[i])*100);
    h+='<div style="display:flex;align-items:center;gap:5px;margin-bottom:3px;font-size:9px"><span style="width:32px;color:var(--txt3);font-weight:600">'+n+'</span><div style="flex:1;height:5px;background:var(--bg4);border-radius:3px;overflow:hidden"><div style="height:100%;width:'+pct+'%;background:linear-gradient(90deg,'+indColors[i]+','+indColors[i]+'88);border-radius:3px;transition:width .6s cubic-bezier(.4,0,.2,1);box-shadow:0 0 4px '+indColors[i]+'33"></div></div><span class="mono" style="width:20px;text-align:right;color:'+(pct>=60?'var(--green)':pct>=30?'var(--gold)':'var(--txt3)')+';font-size:8px;font-weight:700">'+v+'/'+mx[i]+'</span></div>'});
  $('sig-bars').innerHTML=h;

  /* Spread info in chart header */
  const spread=t.spread_pts||0,spreadOk=t.spread_ok!==false;
  const spEl=$('csi-spread');
  if(spread>0){spEl.textContent='Spread: '+fmt(spread,spread>10?0:1);spEl.className='spread-badge '+(spreadOk?'ok':'danger')}
  else{spEl.textContent='Spread: --';spEl.className='spread-badge ok'}
  const atrEl=$('csi-atr');
  const atrV=t.atr_m15||0;
  if(atrV>0){atrEl.textContent='ATR: '+fmt(atrV,atrV>1?2:5);atrEl.style.display=''}else{atrEl.style.display='none'}

  $('brain-text').textContent=S.brain?.market_read||'Bekleniyor...';

  /* News Feed */
  const news=S.context?.upcoming_news||[],nel=$('news-feed');
  if(!news.length){nel.innerHTML='<div class="empty">Yaklasan haber yok</div>'}
  else{let nh='';news.slice(0,8).forEach(n=>{const imp=n.impact||n.importance||'',ic=imp==='HIGH'?'var(--red)':imp==='MEDIUM'?'var(--gold)':'var(--txt3)';
    nh+='<div style="display:flex;gap:6px;padding:3px 0;border-bottom:1px solid var(--border)"><span style="width:5px;height:5px;border-radius:50%;background:'+ic+';margin-top:3px;flex-shrink:0"></span><span style="flex:1">'+((n.title||n.event||'')+'')+'</span><span class="mono" style="font-size:8px;color:var(--txt3)">'+((n.time||n.datetime||'')+'').slice(-5)+'</span></div>'});
  nel.innerHTML=nh}
  /* News Ticker */
  updateTicker(news);
  /* Position Map */
  updatePositionMap();
}

/* ── Signal Gauge SVG Update ── */
function updateSignalGauge(id,score){
  const el=$(id);if(!el)return;
  const circumference=2*Math.PI*34;// r=34
  const pct=Math.min(100,score)/100;
  el.style.strokeDashoffset=circumference*(1-pct);
  // Color gradient based on score
  if(score>=70)el.style.stroke=id.includes('buy')?'var(--green)':'var(--red)';
  else if(score>=40)el.style.stroke=id.includes('buy')?'var(--green2)':'var(--red2)';
  else el.style.stroke='var(--txt3)';
}

/* ── News Ticker ── */
let tickerBuilt=false;
function updateTicker(news){
  if(tickerBuilt&&news.length===0)return;
  const track=$('ticker-track');if(!track)return;
  const allNews=[...(S.context?.upcoming_news||[]),...(S.context?.recent_news||[])];
  if(!allNews.length){track.innerHTML='<span class="ticker-item" style="color:var(--txt3)">Haber bekleniyor...</span>';return}
  let h='';const items=allNews.slice(0,20);
  // Duplicate for seamless scroll
  for(let r=0;r<2;r++){items.forEach(n=>{const imp=n.impact||n.importance||'LOW';
    h+='<span class="ticker-item"><span class="ti-dot ti-impact-'+imp+'"></span>'+((n.title||n.event||'')+'')+' <span class="mono" style="font-size:8px;color:var(--txt3)">'+((n.time||n.datetime||'')+'').slice(-5)+'</span></span>'});}
  track.innerHTML=h;tickerBuilt=true;
}

/* ── Position Map (SPM/FIFO tree view) ── */
function updatePositionMap(){
  const panel=$('pos-map-panel'),content=$('pos-map-content');
  if(!panel||!content)return;
  const pos=S.positions||{};let allPos=[];
  Object.keys(pos).forEach(sym=>{const sp=pos[sym],list=sp.positions||sp||[];
    (Array.isArray(list)?list:[]).forEach(p=>{allPos.push({...p,symbol:sp.symbol||sym})})});
  if(allPos.length<2){panel.style.display='none';return}
  panel.style.display='';
  // Group by symbol
  const bySymbol={};allPos.forEach(p=>{const s=p.symbol;if(!bySymbol[s])bySymbol[s]=[];bySymbol[s].push(p)});
  let h='';
  Object.entries(bySymbol).forEach(([sym,positions])=>{
    if(positions.length<2)return;
    h+='<div style="font-size:9px;font-weight:700;color:var(--purple2);margin:4px 0 2px;letter-spacing:.5px">'+sym+'</div>';
    positions.forEach(p=>{
      const role=p.role||'MAIN';
      const dotCls=role==='MAIN'?'main':role.startsWith('SPM')?'spm':'hedge';
      const pnl=p.profit||0;
      h+='<div class="pos-map-row"><span class="pos-map-dot '+dotCls+'"></span><div class="pos-map-info">';
      h+='<span class="pm-role" style="color:'+(role==='MAIN'?'var(--purple2)':role.startsWith('SPM')?'var(--gold)':'var(--red)')+'">'+role+'</span>';
      h+='<span class="pm-dir '+(p.direction==='BUY'?'dir-BUY':'dir-SELL')+'">'+p.direction+'</span>';
      h+='<span class="pm-lot">'+fmt(p.lot,2)+'</span>';
      h+='<span class="pm-pnl" style="color:'+pnlColor(pnl)+'">$'+fmtUsd(pnl)+'</span>';
      h+='</div></div>';
    });
  });
  content.innerHTML=h||'<div class="empty">Tekli pozisyon</div>';
}

/* ══════════════════════════════════════════════
   CANDLESTICK CHART — EMA + BB + Buy/Sell Markers
   ══════════════════════════════════════════════ */
function initCandleChart(){
  const c=$('candle-chart');if(!c||candleChart)return;
  candleChart=LightweightCharts.createChart(c,{
    layout:{background:{color:'transparent'},textColor:'#71717a',fontSize:10,fontFamily:'JetBrains Mono'},
    grid:{vertLines:{color:'rgba(108,92,231,.04)'},horzLines:{color:'rgba(108,92,231,.06)'}},
    crosshair:{mode:LightweightCharts.CrosshairMode.Normal,
      vertLine:{color:'rgba(108,92,231,.3)',style:2,width:1,labelBackgroundColor:'#6c5ce7'},
      horzLine:{color:'rgba(108,92,231,.3)',style:2,width:1,labelBackgroundColor:'#6c5ce7'}},
    rightPriceScale:{borderColor:'rgba(255,255,255,.04)',scaleMargins:{top:0.05,bottom:0.15}},
    timeScale:{borderColor:'rgba(255,255,255,.04)',timeVisible:true,secondsVisible:false},
    handleScroll:true,handleScale:true
  });
  /* Bollinger Bands (area between upper and lower) */
  bbUpper=candleChart.addLineSeries({color:'rgba(167,139,250,.2)',lineWidth:1,lineStyle:2,priceLineVisible:false,crosshairMarkerVisible:false});
  bbLower=candleChart.addLineSeries({color:'rgba(167,139,250,.2)',lineWidth:1,lineStyle:2,priceLineVisible:false,crosshairMarkerVisible:false});
  /* EMA lines */
  emaSeries.ema8=candleChart.addLineSeries({color:'#6c5ce7',lineWidth:1.5,priceLineVisible:false,crosshairMarkerVisible:false});
  emaSeries.ema21=candleChart.addLineSeries({color:'#a78bfa',lineWidth:1,priceLineVisible:false,crosshairMarkerVisible:false});
  emaSeries.ema50=candleChart.addLineSeries({color:'rgba(245,158,11,.5)',lineWidth:1,lineStyle:2,priceLineVisible:false,crosshairMarkerVisible:false});
  /* Candlestick */
  candleSeries=candleChart.addCandlestickSeries({upColor:'#10b981',downColor:'#ef4444',borderUpColor:'#10b981',borderDownColor:'#ef4444',wickUpColor:'#34d399',wickDownColor:'#f87171'});
  /* Volume */
  volumeSeries=candleChart.addHistogramSeries({priceFormat:{type:'volume'},priceScaleId:'vol',color:'rgba(108,92,231,.15)'});
  candleChart.priceScale('vol').applyOptions({scaleMargins:{top:0.85,bottom:0}});
  new ResizeObserver(()=>{if(candleChart)candleChart.resize(c.clientWidth,c.clientHeight)}).observe(c);
  renderCandleChart();
}

function renderCandleChart(){
  if(!candleChart||!candleSeries||!S)return;
  const t=S.technicals?.[selectedSym];if(!t||!t.candles_m15?.length)return;
  let candles=t.candles_m15.filter(c=>c.t>0);

  /* Time period filter */
  if(currentTF!=='all'){
    const now=Math.floor(Date.now()/1000);
    const limits={'1h':3600,'6h':21600,'24h':86400};
    const cutoff=now-(limits[currentTF]||86400);
    candles=candles.filter(c=>c.t>=cutoff);
  }
  if(!candles.length)return;

  const data=candles.map(c=>({time:c.t,open:c.o,high:c.h,low:c.l,close:c.c}));
  candleSeries.setData(data);

  /* EMA overlays */
  const e8=candles.filter(c=>c.e8).map(c=>({time:c.t,value:c.e8}));
  const e21=candles.filter(c=>c.e21).map(c=>({time:c.t,value:c.e21}));
  const e50=candles.filter(c=>c.e50).map(c=>({time:c.t,value:c.e50}));
  if(e8.length)emaSeries.ema8.setData(e8);
  if(e21.length)emaSeries.ema21.setData(e21);
  if(e50.length)emaSeries.ema50.setData(e50);

  /* Bollinger Bands */
  const bu=candles.filter(c=>c.bbu).map(c=>({time:c.t,value:c.bbu}));
  const bl=candles.filter(c=>c.bbl).map(c=>({time:c.t,value:c.bbl}));
  if(bu.length)bbUpper.setData(bu);
  if(bl.length)bbLower.setData(bl);

  /* Volume bars */
  const vol=candles.map(c=>({time:c.t,value:c.v||0,color:c.c>=c.o?'rgba(16,185,129,.15)':'rgba(239,68,68,.15)'}));
  volumeSeries.setData(vol);

  /* Buy/Sell position markers */
  addPositionMarkers(candles);
  candleChart.timeScale().fitContent();
}

function addPositionMarkers(candles){
  if(!candleSeries||!S)return;
  const pos=S.positions||{};const markers=[];
  /* Open positions — show entry arrows */
  Object.keys(pos).forEach(sym=>{
    if(sym!==selectedSym)return;
    const sp=pos[sym],list=sp.positions||sp||[];
    (Array.isArray(list)?list:[]).forEach(p=>{
      if(!p.open_time)return;
      markers.push({time:p.open_time,position:p.direction==='BUY'?'belowBar':'aboveBar',
        color:p.direction==='BUY'?'#10b981':'#ef4444',
        shape:p.direction==='BUY'?'arrowUp':'arrowDown',
        text:p.direction+' '+fmt(p.lot,2)+' ('+( p.role||'MAIN')+')'});
    });
  });
  /* Closed trades — show result circles */
  const trades=S.trade_history||[];
  trades.forEach(t=>{
    if(t.symbol!==selectedSym||!t.close_time)return;
    markers.push({time:t.close_time,position:'inBar',color:t.pnl>=0?'#10b981':'#ef4444',
      shape:'circle',text:'$'+fmtUsd(t.pnl)});
  });
  markers.sort((a,b)=>a.time-b.time);
  try{candleSeries.setMarkers(markers)}catch(e){}
}

/* ══════════════════════════════════════════════
   PNL BASELINE CHART — Green/Red Gradient
   ══════════════════════════════════════════════ */
function initPnlChart(){
  const c=$('pnl-chart');if(!c||pnlChart)return;
  pnlChart=LightweightCharts.createChart(c,{
    layout:{background:{color:'transparent'},textColor:'#71717a',fontSize:10,fontFamily:'JetBrains Mono'},
    grid:{vertLines:{color:'rgba(108,92,231,.03)'},horzLines:{color:'rgba(108,92,231,.05)'}},
    crosshair:{mode:LightweightCharts.CrosshairMode.Normal,
      vertLine:{labelBackgroundColor:'#6c5ce7'},horzLine:{labelBackgroundColor:'#6c5ce7'}},
    rightPriceScale:{borderColor:'rgba(255,255,255,.04)'},
    timeScale:{borderColor:'rgba(255,255,255,.04)',timeVisible:true}
  });
  /* Baseline series: green above 0, red below 0 */
  pnlBaseline=pnlChart.addBaselineSeries({
    baseValue:{type:'price',price:0},
    topLineColor:'#10b981',topFillColor1:'rgba(16,185,129,.28)',topFillColor2:'rgba(16,185,129,.02)',
    bottomLineColor:'#ef4444',bottomFillColor1:'rgba(239,68,68,.02)',bottomFillColor2:'rgba(239,68,68,.28)',
    lineWidth:2,priceLineVisible:false
  });
  /* Equity dashed line */
  pnlEqLine=pnlChart.addLineSeries({color:'rgba(167,139,250,.4)',lineWidth:1,lineStyle:2,priceLineVisible:false,crosshairMarkerVisible:false});
  new ResizeObserver(()=>{if(pnlChart)pnlChart.resize(c.clientWidth,c.clientHeight)}).observe(c);
}

function updatePnlChart(){
  if(!pnlChart&&currentView==='pnl')initPnlChart();
  if(!pnlChart||!pnlBaseline)return;
  const now=Math.floor(Date.now()/1000);
  const tp=(S.trade_stats?.total_realized||0)+(S.account?.floating_pnl||0),eq=S.account?.equity||0;
  if(!pnlHistory.length||now-pnlHistory[pnlHistory.length-1].time>=3){
    pnlHistory.push({time:now,total:tp,eq:eq});
    if(pnlHistory.length>3000)pnlHistory=pnlHistory.slice(-2000);
  }
  renderPnlPeriod();
}

function renderPnlPeriod(){
  if(!pnlBaseline||pnlHistory.length<2)return;
  let data=pnlHistory;
  if(currentTF!=='all'){
    const now=Math.floor(Date.now()/1000);
    const limits={'1h':3600,'6h':21600,'24h':86400};
    const cutoff=now-(limits[currentTF]||86400);
    data=pnlHistory.filter(p=>p.time>=cutoff);
  }
  if(data.length>1){
    pnlBaseline.setData(data.map(p=>({time:p.time,value:p.total})));
    pnlEqLine.setData(data.map(p=>({time:p.time,value:p.eq})));
  }
  pnlChart.timeScale().fitContent();
}

/* ══════════════════════════════════════════════
   MINI CHARTS (Bottom)
   ══════════════════════════════════════════════ */
function initMiniCharts(){
  const o=()=>({type:'line',data:{labels:[],datasets:[]},options:{responsive:true,maintainAspectRatio:false,scales:{x:{display:false},y:{grid:{color:'rgba(108,92,231,.08)'},ticks:{color:'#71717a',font:{size:8,family:'JetBrains Mono'}},border:{color:'transparent'}}},plugins:{legend:{display:false},tooltip:{enabled:false}},elements:{point:{radius:0},line:{tension:.3}},animation:{duration:300}}});
  const e=o();e.data.datasets=[{data:[],borderColor:'#6c5ce7',borderWidth:1.5,fill:true,backgroundColor:'rgba(108,92,231,.08)'},{data:[],borderColor:'#a78bfa',borderWidth:1,borderDash:[4,3],fill:false}];
  eqChartJs=new Chart($('eq-chart'),e);
  const r=o();r.type='bar';r.data.datasets=[{data:[],backgroundColor:'#10b981',borderRadius:2},{data:[],backgroundColor:'#ef4444',borderRadius:2}];r.options.scales.x={display:true,grid:{display:false},ticks:{color:'#71717a',font:{size:7}}};
  ruChartJs=new Chart($('ru-chart'),r);
  const w=o();w.data.datasets=[{data:[],borderColor:'#6c5ce7',borderWidth:1.5,fill:true,backgroundColor:'rgba(108,92,231,.08)'},{data:[],borderColor:'rgba(113,113,122,.25)',borderWidth:1,borderDash:[3,3],fill:false}];
  wrtChartJs=new Chart($('wrt-chart'),w);
}

function updateMiniCharts(){
  if(!eqChartJs)return;const now=new Date().toLocaleTimeString('tr-TR',{hour:'2-digit',minute:'2-digit'}),a=S.account,ts=S.trade_stats||{};
  eqChartJs.data.labels.push(now);eqChartJs.data.datasets[0].data.push(a.equity||0);eqChartJs.data.datasets[1].data.push(a.balance||0);
  if(eqChartJs.data.labels.length>120){eqChartJs.data.labels.shift();eqChartJs.data.datasets.forEach(d=>d.data.shift())}eqChartJs.update('none');
  ruChartJs.data.labels=['Real','Unreal'];ruChartJs.data.datasets[0].data=[Math.max(0,ts.total_realized||0),Math.max(0,a.floating_pnl||0)];
  ruChartJs.data.datasets[1].data=[Math.abs(Math.min(0,ts.total_realized||0)),Math.abs(Math.min(0,a.floating_pnl||0))];ruChartJs.update('none');
  wrHistory.push(ts.win_rate||0);if(wrHistory.length>120)wrHistory.shift();
  wrtChartJs.data.labels=wrHistory.map((_,i)=>i);wrtChartJs.data.datasets[0].data=[...wrHistory];wrtChartJs.data.datasets[1].data=wrHistory.map(()=>50);wrtChartJs.update('none');
  updatePnlChart();
}

/* ── Session Uptime Timer ── */
const sessionStart=Date.now();
function updateUptime(){
  const elapsed=Math.floor((Date.now()-sessionStart)/1000);
  const h=Math.floor(elapsed/3600),m=Math.floor((elapsed%3600)/60),s=elapsed%60;
  const el=$('tb-uptime');if(el)el.textContent=String(h).padStart(2,'0')+':'+String(m).padStart(2,'0')+':'+String(s).padStart(2,'0');
}

/* ── Init ── */
document.addEventListener('DOMContentLoaded',()=>{
  initCandleChart();initMiniCharts();
  setInterval(()=>{$('tb-clock').textContent=new Date().toUTCString().slice(17,25)+' UTC';updateUptime()},1000);
  fetchState();setInterval(fetchState,REFRESH);
});
</script>
</body>
</html>"""
