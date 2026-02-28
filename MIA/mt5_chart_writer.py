r"""
MT5 Chart Writer v4.0
Python MIA → MT5 Files\MIA\ klasörüne JSON yazar
MT5 EA (MIA_Dashboard.mq5) bu dosyaları okur ve chart'ta gösterir.

Her aktif sembol için ayrı dosya:
  %MT5_DATA%\MQL5\Files\MIA\EURUSDm.json
  %MT5_DATA%\MQL5\Files\MIA\XAUUSDm.json
  ...

v4.0: regime, sentiment, agents alanları eklendi.
"""

import os
import json
import time
import logging
import pathlib
from typing import Optional

log = logging.getLogger("MT5Writer")

# MT5 varsayilan data dizinleri (Windows)
MT5_DATA_PATHS = [
    r"C:\Users\{user}\AppData\Roaming\MetaQuotes\Terminal",
    r"D:\MetaTrader 5\MQL5\Files",
    r"C:\Program Files\MetaTrader 5\MQL5\Files",
]


class MT5ChartWriter:
    """
    Her aktif sembol icin JSON dosyasi yazar.
    MIA_Dashboard.mq5 EA bu dosyalari okur.
    """

    def __init__(self, data_folder: str = "MIA"):
        self.data_folder = data_folder
        self._mt5_files_dir: Optional[str] = None
        self._output_dir: Optional[str] = None
        self._find_mt5_files_dir()

    def _find_mt5_files_dir(self):
        """MT5 Files klasorunu bul"""
        import glob, getpass

        # 1. MT5 process'inden terminal klasorunu bul
        try:
            import subprocess
            result = subprocess.run(
                ["wmic", "process", "where",
                 "name='terminal64.exe'", "get", "ExecutablePath"],
                capture_output=True, text=True, timeout=3
            )
            for line in result.stdout.splitlines():
                line = line.strip()
                if "terminal64.exe" in line.lower():
                    term_dir = os.path.dirname(line)
                    # Terminal klasoru -> MQL5\Files
                    candidate = os.path.join(term_dir, "MQL5", "Files")
                    if os.path.exists(candidate):
                        self._mt5_files_dir = candidate
                        log.info(f"MT5 Files: {candidate}")
                        break
        except Exception:
            pass

        # 2. AppData roaming'de ara
        if not self._mt5_files_dir:
            user = os.environ.get("USERNAME", "")
            roaming = os.environ.get("APPDATA",
                      rf"C:\Users\{user}\AppData\Roaming")
            pattern = os.path.join(
                roaming, "MetaQuotes", "Terminal", "*", "MQL5", "Files"
            )
            matches = glob.glob(pattern)
            if matches:
                # En son degistirilen terminali sec
                matches.sort(key=os.path.getmtime, reverse=True)
                self._mt5_files_dir = matches[0]
                log.info(f"MT5 Files (AppData): {self._mt5_files_dir}")

        # 3. Bulunamazsa script klasorune yaz
        if not self._mt5_files_dir:
            fallback = os.path.join(os.getcwd(), "MT5_Files")
            log.warning(
                f"MT5 Files klasoru bulunamadi! "
                f"Yerel klasore yaziliyor: {fallback}\n"
                f"EA input'unda DataFolder'i manuel ayarlayin."
            )
            self._mt5_files_dir = fallback

        # MIA alt klasoru olustur
        self._output_dir = os.path.join(self._mt5_files_dir, self.data_folder)
        pathlib.Path(self._output_dir).mkdir(parents=True, exist_ok=True)
        log.info(f"Chart data klasoru: {self._output_dir}")

    def write_symbol_data(self, symbol: str, mt5_symbol: str, data: dict):
        """
        Sembol verilerini JSON dosyasina yaz.
        symbol    : base (EURUSD)
        mt5_symbol: broker'daki gercek ad (EURUSDm)
        data      : yazilacak dict
        """
        if not self._output_dir:
            return

        # Hem base hem broker adiyla yaz (EA hangisini okursa okusun)
        for fname in set([symbol, mt5_symbol]):
            path = os.path.join(self._output_dir, f"{fname}.json")
            try:
                with open(path, "w", encoding="utf-8") as f:
                    json.dump(data, f, ensure_ascii=False, indent=None,
                              separators=(',', ':'))
            except Exception as e:
                log.debug(f"JSON yazma hatasi [{fname}]: {e}")

    def write_from_snapshot(self, snapshot, positions_dict: dict,
                             active_symbols: list, brain_session=None,
                             bridge=None,
                             regime_data: dict = None,
                             sentiment_data: dict = None,
                             master_multiplier: float = 1.0,
                             paused: bool = False):
        """
        MarketIntelligence snapshot'tan tum aktif semboller icin JSON yaz.
        Her brain kararindan sonra main.py'den cagirilir.

        v4.0: regime_data, sentiment_data, master_multiplier, paused parametreleri eklendi.
        """
        if not active_symbols:
            return

        acc = snapshot.account
        ctx = snapshot.context

        for sym in active_symbols:
            t   = snapshot.technicals.get(sym)
            pos = positions_dict.get(sym)

            # Broker sembol adi
            mt5_sym = sym
            if bridge and hasattr(bridge, '_sym'):
                mt5_sym = bridge._sym(sym)

            # Spread bilgisi
            sp_info = {}
            if bridge and hasattr(bridge, 'get_spread_info'):
                try:
                    sp_info = bridge.get_spread_info(sym)
                except Exception:
                    pass

            # Pozisyon ozeti
            main_pnl   = 0.0
            open_pnl   = 0.0
            spm_count  = 0
            kasa       = 0.0
            fifo_net   = 0.0
            open_count = 0
            if pos and pos.get('positions'):
                for p in pos['positions']:
                    open_pnl += p.get('profit', 0)
                    open_count += 1
                    if p.get('role') == 'MAIN':
                        main_pnl = p.get('profit', 0)
                    if 'SPM' in str(p.get('role', '')):
                        spm_count += 1
                kasa     = pos.get('kasa', 0)
                fifo_net = kasa + open_pnl

            # Sinyal skoru
            buy_score  = 0
            sell_score = 0
            direction  = "NOTR"
            ema_s = macd_s = adx_s = rsi_s = bb_s = stoch_s = atr_s = 0

            if t:
                buy_score  = _calc_score(t, "BUY")
                sell_score = _calc_score(t, "SELL")
                if buy_score > sell_score and buy_score > 40:
                    direction = "ALIS"
                elif sell_score > buy_score and sell_score > 40:
                    direction = "SATIS"

                ema_s   = _layer_ema(t)
                macd_s  = _layer_macd(t)
                adx_s   = _layer_adx(t)
                rsi_s   = _layer_rsi(t)
                bb_s    = _layer_bb(t)
                stoch_s = _layer_stoch(t)
                atr_s   = int(min(5, getattr(t,'atr_percentile',0)/20))

            # TP hesapla
            tp1 = tp2 = tp3 = 0.0
            if t and getattr(t,'atr_m15',0) and getattr(t,'price',0):
                price = t.price
                atr   = t.atr_m15
                tp1 = price + atr * 1.0
                tp2 = price + atr * 1.5
                tp3 = price + atr * 2.2

            # Brain bilgisi
            global_risk = "MEDIUM"
            market_read = ""
            if brain_session:
                global_risk = getattr(brain_session, 'global_risk', 'MEDIUM')
                market_read = getattr(brain_session, 'market_read', '')[:100]

            data = {
                # Hesap
                "balance":        round(acc.balance, 2),
                "equity":         round(acc.equity, 2),
                "margin_level":   round(acc.margin_level, 0),
                "daily_pnl":      round(acc.daily_pnl, 2),
                "open_positions": acc.open_positions,

                # Teknik
                "rsi":       round(getattr(t,'rsi_m15',50), 1)  if t else 50.0,
                "adx":       round(getattr(t,'adx',0), 1)       if t else 0.0,
                "atr":       round(getattr(t,'atr_m15',0), 5)   if t else 0.0,
                "ema8":      round(getattr(t,'ema8',0), 5)      if t else 0.0,
                "ema21":     round(getattr(t,'ema21',0), 5)     if t else 0.0,
                "ema50":     round(getattr(t,'ema50',0), 5)     if t else 0.0,
                "trend":     getattr(t,'trend_aligned','NEUTRAL') if t else "NEUTRAL",

                # Spread
                "spread_pts": round(sp_info.get('current_pts', 0), 0),
                "spread_ok":  sp_info.get('is_ok', True),
                "spread_ratio": round(sp_info.get('ratio', 1.0), 3),

                # Sinyal
                "buy_score":   buy_score,
                "sell_score":  sell_score,
                "direction":   direction,
                "durum":       "AKTIF" if sym in active_symbols else "PASIF",
                "ema_score":   ema_s,
                "macd_score":  macd_s,
                "adx_score":   adx_s,
                "rsi_score":   rsi_s,
                "bb_score":    bb_s,
                "stoch_score": stoch_s,
                "atr_score":   atr_s,

                # TP
                "tp1": round(tp1, 5),
                "tp2": round(tp2, 5),
                "tp3": round(tp3, 5),

                # Grid / FIFO
                "main_pnl":   round(main_pnl, 2),
                "open_pnl":   round(open_pnl, 2),
                "spm_count":  spm_count,
                "kasa":       round(kasa, 2),
                "fifo_net":   round(fifo_net, 2),
                "fifo_target": 5.0,

                # Brain / Bağlam
                "global_risk": global_risk,
                "market_read": market_read,
                "session":     ctx.session if ctx else "--",
                "fg_index":    ctx.fear_greed_index if ctx else 50,
                "fg_label":    ctx.fear_greed_label if ctx else "--",

                # v4.0 — Rejim
                "regime": {
                    "name":       (regime_data or {}).get(sym, "UNKNOWN"),
                    "multiplier": self._regime_multiplier((regime_data or {}).get(sym, "")),
                },

                # v4.0 — Sentiment
                "sentiment": {
                    "score":    round((sentiment_data or {}).get(sym, 0.0), 1),
                    "label":    self._sentiment_label((sentiment_data or {}).get(sym, 0.0)),
                    "blackout": abs((sentiment_data or {}).get(sym, 0.0)) > 80,
                },

                # v4.0 — Ajan bilgisi
                "agents": {
                    "master_mult": round(master_multiplier, 2),
                    "paused":      paused,
                },

                # Zaman
                "ts": int(time.time()),
            }

            self.write_symbol_data(sym, mt5_sym, data)

        log.debug(f"Chart JSON yazildi: {active_symbols}")

    # ── v4.0 YARDIMCI METODLAR ─────────────────────────────

    @staticmethod
    def _regime_multiplier(regime_name: str) -> float:
        """Rejim adından lot çarpanı belirle"""
        m = {
            "STRONG_TREND": 1.2,
            "TREND":        1.1,
            "WEAK_TREND":   0.9,
            "RANGE":        0.8,
            "CHOPPY":       0.6,
            "VOLATILE":     0.7,
        }
        return m.get(regime_name, 1.0)

    @staticmethod
    def _sentiment_label(score: float) -> str:
        """Sentiment skorundan etiket üret"""
        if score > 60:   return "EXTREME_GREED"
        if score > 30:   return "GREED"
        if score > 10:   return "BULLISH"
        if score > -10:  return "NEUTRAL"
        if score > -30:  return "BEARISH"
        if score > -60:  return "FEAR"
        return "EXTREME_FEAR"

    def clear_symbol(self, symbol: str, mt5_symbol: str = ""):
        """Sembol JSON'unu temizle (pasif olunca)"""
        for fname in set([symbol, mt5_symbol or symbol]):
            path = os.path.join(self._output_dir or "", f"{fname}.json")
            try:
                if os.path.exists(path):
                    os.remove(path)
            except Exception:
                pass


# ── SKOR HESAPLAMA (dashboard_api ile ayni mantik) ────────
def _calc_score(t, direction: str) -> int:
    score  = 0
    is_buy = direction == "BUY"
    e8  = getattr(t, 'ema8',  0) or 0
    e21 = getattr(t, 'ema21', 0) or 0
    e50 = getattr(t, 'ema50', 0) or 0
    if e8 and e21 and e50:
        if is_buy  and e8 > e21 > e50: score += 20
        elif not is_buy and e8 < e21 < e50: score += 20
        elif is_buy  and e8 > e21: score += 10
        elif not is_buy and e8 < e21: score += 10
    macd = getattr(t, 'macd_hist', 0) or 0
    if macd:
        if is_buy  and macd > 0: score += 15
        elif not is_buy and macd < 0: score += 15
        if getattr(t,'macd_cross','') == ("FRESH_BULL" if is_buy else "FRESH_BEAR"):
            score += 5
    adx = getattr(t, 'adx', 0) or 0
    if adx > 35: score += 15
    elif adx > 25: score += 10
    elif adx > 15: score += 5
    rsi = getattr(t, 'rsi_m15', 50) or 50
    if is_buy  and 30 < rsi < 55: score += 15
    elif not is_buy and 45 < rsi < 70: score += 15
    elif is_buy  and rsi < 30: score += 8
    elif not is_buy and rsi > 70: score += 8
    bb = getattr(t, 'bb_position', 50)
    if bb is not None:
        if is_buy  and bb < 35: score += 15
        elif not is_buy and bb > 65: score += 15
    sz = getattr(t, 'stoch_zone', '')
    if is_buy  and sz == "OVERSOLD":  score += 10
    elif not is_buy and sz == "OVERBOUGHT": score += 10
    return min(100, score)

def _layer_ema(t) -> int:
    e8=getattr(t,'ema8',0) or 0; e21=getattr(t,'ema21',0) or 0; e50=getattr(t,'ema50',0) or 0
    if not (e8 and e21 and e50): return 0
    if (e8>e21>e50) or (e8<e21<e50): return 20
    if e8 != e21: return 10
    return 0

def _layer_macd(t) -> int:
    m = getattr(t,'macd_hist',0) or 0
    base = 15 if abs(m) > 0 else 0
    if getattr(t,'macd_cross','') != 'NONE': base = min(20, base+5)
    return base

def _layer_adx(t) -> int:
    a = getattr(t,'adx',0) or 0
    if a > 35: return 15
    if a > 25: return 10
    if a > 15: return 5
    return 0

def _layer_rsi(t) -> int:
    r = getattr(t,'rsi_m15',50) or 50
    return 12 if 30 < r < 70 else 6

def _layer_bb(t) -> int:
    b = getattr(t,'bb_position',50)
    if b is None: return 0
    if b < 25 or b > 75: return 15
    if b < 35 or b > 65: return 8
    return 4

def _layer_stoch(t) -> int:
    sz = getattr(t,'stoch_zone','')
    return 10 if sz in ("OVERSOLD","OVERBOUGHT") else 4
