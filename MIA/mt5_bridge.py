"""
BytamerFX MT5 Bridge
MetaTrader5 Python kütüphanesi ile MT5 terminali arasındaki köprü.
Windows'ta çalışır. MT5 terminali açık olmalı.
"""

import time
import logging
import pandas as pd
from typing import List, Dict, Optional
import config as cfg

log = logging.getLogger("MT5Bridge")

# MetaTrader5 sadece Windows'ta çalışır
try:
    import MetaTrader5 as mt5
    MT5_AVAILABLE = True
except ImportError:
    MT5_AVAILABLE = False
    log.warning("MetaTrader5 paketi yüklü değil — demo modu aktif")


def _retcode_desc(code: int) -> str:
    """MT5 retcode açıklaması"""
    m = {
        10004:"Yeniden kotasyon", 10006:"Ret", 10007:"İptal",
        10008:"Emir yerleştirildi", 10009:"Tamamlandı",
        10010:"Kısmen tamamlandı", 10011:"Hata",
        10012:"Zaman aşımı", 10013:"Geçersiz emir",
        10014:"Geçersiz hacim", 10015:"Geçersiz fiyat",
        10016:"Geçersiz stop", 10017:"Ticaret devre dışı",
        10018:"Piyasa kapalı", 10019:"Yetersiz para",
        10020:"Fiyat değişti", 10021:"Kotasyon yok",
        10022:"Geçersiz emir son tarihi", 10023:"Emir değişti",
        10024:"Çok fazla emir",
        10025:"Hedge yasak", 10026:"Fifo zorunlu",
        10027:"Pozisyon donduruldu",
    }
    return m.get(code, f"Bilinmeyen kod: {code}")

class MT5Bridge:
    """
    MT5 ile tüm iletişim bu sınıf üzerinden geçer.
    - Bağlantı yönetimi
    - OHLCV veri çekimi
    - Emir açma/kapama
    - Hesap bilgisi
    - Spread kontrolü
    """

    def __init__(self):
        self.connected    = False
        self.magic_number = 20260217  # BytamerFX magic
        self._last_rates: Dict[str, Dict] = {}
        self._sym_map:        Dict[str, str]   = {}
        self._suffix          = cfg.BROKER_SUFFIX
        self._spread_baseline: Dict[str, float] = {}   # sembol → tipik spread (points)
        self._spread_samples:  Dict[str, list]  = {}   # rolling örnekler
        # Spread baseline — bağlanınca ölçülür, işlem saatinde referans alınır
        self._spread_baseline: Dict[str, float] = {}   # sembol → tipik spread (points)
        self._spread_samples:  Dict[str, list]  = {}   # son 20 ölçüm (rolling avg)

    # ─── BAĞLANTI ─────────────────────────────────────────

    def connect(self) -> bool:
        if not MT5_AVAILABLE:
            log.warning("MT5 paketi yok — demo modu")
            self.connected = False
            return False

        if not mt5.initialize(
            path     = cfg.MT5_PATH,
            login    = cfg.MT5_LOGIN,
            password = cfg.MT5_PASSWORD,
            server   = cfg.MT5_SERVER,
        ):
            log.error(f"MT5 başlatılamadı: {mt5.last_error()}")
            return False

        info = mt5.account_info()
        if info is None:
            log.error("Hesap bilgisi alınamadı")
            return False

        log.info(f"MT5 Bağlandı: #{info.login} {info.server} | Bakiye: ${info.balance:.2f}")
        self.connected = True
        self._detect_symbols()
        return True

    def _detect_symbols(self):
        """
        Broker suffix otomatik tespiti.
        MT5'te mevcut sembolleri tarar, EURUSD/EURUSDm/EURUSD.raw eşleştirir.
        config.BROKER_SUFFIX boş ise otomatik tespit yapar.
        """
        self._sym_map = {}
        if not MT5_AVAILABLE:
            return

        # Önce config'deki suffix'i dene
        suffix = self._suffix  # "m", ".raw", "" vb.

        for base in cfg.ALL_SYMBOLS:
            candidates = []
            if suffix:
                # Config suffix öncelikli
                candidates = [base + suffix, base]
            else:
                # Otomatik: birden fazla varyant dene
                candidates = [base, base+"m", base+".r", base+".raw",
                              base+"_", base+"i", base+".std"]

            found = None
            for cand in candidates:
                info = mt5.symbol_info(cand)
                if info is not None:
                    found = cand
                    break

            if found:
                self._sym_map[base] = found
                if found != base:
                    log.info(f"Sembol eşleşti: {base} → {found}")
            else:
                # Son çare: MT5'teki tüm semboller arasında ara
                all_syms = mt5.symbols_get()
                if all_syms:
                    for s in all_syms:
                        if s.name.startswith(base):
                            self._sym_map[base] = s.name
                            log.info(f"Sembol bulundu: {base} → {s.name}")
                            break
                if base not in self._sym_map:
                    log.warning(f"Sembol bulunamadı: {base} — base isim kullanılacak")
                    self._sym_map[base] = base

        log.info(f"Sembol haritası: {self._sym_map}")
        # Başlangıç spread baseline ölçümü
        for base in cfg.ALL_SYMBOLS:
            self.update_spread_baseline(base)
        # Bağlantı sonrası spread baseline ölç
        self._measure_spread_baseline()

    def _measure_spread_baseline(self):
        """
        Her sembol için spread baseline ölç.
        İlk 5 ölçüm ortalaması → tipik spread referansı.
        Sonraki ölçümler rolling average ile güncellenir (son 20 ölçüm).
        """
        if not MT5_AVAILABLE or not self.connected:
            return
        import time as _time
        log.info("Spread baseline ölçülüyor...")
        for base, real in self._sym_map.items():
            samples = []
            for _ in range(5):
                info = mt5.symbol_info(real)
                if info and info.spread > 0:
                    samples.append(float(info.spread))
                _time.sleep(0.05)
            if samples:
                baseline = sum(samples) / len(samples)
                self._spread_baseline[base] = baseline
                self._spread_samples[base]  = samples
                log.info(f"  {base} ({real}): baseline={baseline:.1f}pts")
            else:
                log.warning(f"  {base}: spread ölçülemedi")

    def update_spread_baseline(self, symbol: str):
        """
        Rolling average ile baseline güncelle.
        Her spread kontrolünde çağrılır — zamanla daha doğru baseline oluşur.
        """
        if not MT5_AVAILABLE or not self.connected:
            return
        info = mt5.symbol_info(self._sym(symbol))
        if not info or info.spread <= 0:
            return
        current = float(info.spread)
        samples = self._spread_samples.get(symbol, [])
        samples.append(current)
        if len(samples) > 20:
            samples.pop(0)
        self._spread_samples[symbol] = samples
        # Baseline = rolling avg (düşük uç ağırlıklı — spike'ları filtrele)
        if samples:
            sorted_s   = sorted(samples)
            lower_half = sorted_s[:max(1, len(sorted_s)//2)]  # Alt yarı = normal spread
            self._spread_baseline[symbol] = sum(lower_half) / len(lower_half)

    def _sym(self, base: str) -> str:
        """
        Base sembol adını broker'daki gerçek adına çevir.
        EURUSD → EURUSDm (veya ne ise)
        """
        if self._sym_map:
            return self._sym_map.get(base, base + self._suffix)
        return base + self._suffix

    def disconnect(self):
        if MT5_AVAILABLE and self.connected:
            mt5.shutdown()
            self.connected = False
            log.info("MT5 bağlantısı kapatıldı")

    def ensure_connected(self) -> bool:
        if not self.connected:
            return self.connect()
        return True

    # ─── HESAP BİLGİSİ ────────────────────────────────────

    def get_account(self) -> dict:
        if not self.ensure_connected():
            return self._demo_account()

        info = mt5.account_info()
        if not info:
            # v4.4.0: Bağlantı kopmuş olabilir — reconnect dene
            log.warning("get_account: account_info None — reconnect deneniyor")
            self.connected = False
            if self.connect():
                info = mt5.account_info()
            if not info:
                return self._demo_account()

        return {
            "balance":      info.balance,
            "equity":       info.equity,
            "margin":       info.margin,
            "margin_free":  info.margin_free,
            "margin_level": info.margin_level,
            "profit":       info.profit,
            "leverage":     info.leverage,
            "currency":     info.currency,
        }

    def _demo_account(self) -> dict:
        return {
            "balance": cfg.INITIAL_BALANCE,
            "equity":  cfg.INITIAL_BALANCE,
            "margin":  0, "margin_free": cfg.INITIAL_BALANCE,
            "margin_level": 0, "profit": 0,
            "leverage": 2000, "currency": "USD",
        }

    # ─── VERİ ÇEKİMİ ──────────────────────────────────────

    TF_MAP = {
        "M1":  1,  "M5":  5,  "M15": 15,
        "H1":  60, "H4":  240, "D1": 1440,
    }

    def get_ohlcv(self, symbol: str, tf: str, bars: int = 200) -> pd.DataFrame:
        """OHLCV veri çek, DataFrame döndür"""
        if not self.ensure_connected():
            return self._demo_ohlcv(symbol, bars)

        try:
            tf_mt5 = getattr(mt5, f"TIMEFRAME_{tf}")
        except AttributeError:
            tf_mt5 = mt5.TIMEFRAME_M15

        rates = mt5.copy_rates_from_pos(self._sym(symbol), tf_mt5, 0, bars)
        if rates is None or len(rates) == 0:
            # v4.4.0: Bağlantı kopmuş olabilir — reconnect dene
            log.warning(f"Veri alınamadı: {symbol} {tf} — reconnect deneniyor")
            self.connected = False
            if self.connect():
                rates = mt5.copy_rates_from_pos(self._sym(symbol), tf_mt5, 0, bars)
            if rates is None or len(rates) == 0:
                log.warning(f"Veri alınamadı (reconnect sonrası): {symbol} {tf}")
                return self._demo_ohlcv(symbol, bars)

        df = pd.DataFrame(rates)
        df.rename(columns={
            "time": "time", "open": "open", "high": "high",
            "low": "low", "close": "close", "tick_volume": "volume"
        }, inplace=True)
        df['time'] = pd.to_datetime(df['time'], unit='s')
        df.set_index('time', inplace=True)
        return df

    def _demo_ohlcv(self, symbol: str, bars: int) -> pd.DataFrame:
        """Demo modu için sentetik veri"""
        import numpy as np
        np.random.seed(hash(symbol) % 2**32)
        base = {"BTCUSD":85000,"XAUUSD":2900,"XAGUSD":32,"EURUSD":1.085,
                "GBPUSD":1.26,"USDJPY":150,"AUDUSD":0.63}.get(symbol, 1.0)
        prices = [float(base)]
        for _ in range(bars - 1):
            prices.append(prices[-1] * (1 + np.random.randn() * 0.0005))
        p = np.array(prices)
        noise = np.abs(np.random.randn(bars)) * base * 0.001
        df = pd.DataFrame({
            'open':   p,
            'high':   p + noise,
            'low':    p - noise,
            'close':  p * (1 + np.random.randn(bars) * 0.0002),
            'volume': np.full(bars, 100, dtype=float),
        })
        return df

    def get_all_ohlcv(self, symbol: str) -> tuple:
        """M15 + H1 + H4 veri çek"""
        m15 = self.get_ohlcv(symbol, "M15", 200)
        h1  = self.get_ohlcv(symbol, "H1",  100)
        h4  = self.get_ohlcv(symbol, "H4",  50)
        return m15, h1, h4

    # ─── CACHED H1 ATR ───────────────────────────────────────

    def get_h1_atr(self, symbol: str, period: int = 14) -> float:
        """
        H1 ATR(14) hesapla — cached (5 dakika).
        Grid aralığı ve lot hesabı için kullanılır.
        """
        cache_key = f"h1_atr_{symbol}"
        now = time.time()

        # Cache kontrolü (5dk)
        if hasattr(self, '_atr_cache'):
            cached = self._atr_cache.get(cache_key)
            if cached and (now - cached[1]) < 300:
                return cached[0]
        else:
            self._atr_cache = {}

        try:
            h1 = self.get_ohlcv(symbol, "H1", period + 10)
            if h1 is None or len(h1) < period:
                return 0.0

            # ATR hesapla
            high = h1['high'].values
            low = h1['low'].values
            close = h1['close'].values

            tr_list = []
            for i in range(1, len(high)):
                tr = max(
                    high[i] - low[i],
                    abs(high[i] - close[i - 1]),
                    abs(low[i] - close[i - 1]),
                )
                tr_list.append(tr)

            if len(tr_list) < period:
                return 0.0

            atr = sum(tr_list[-period:]) / period
            self._atr_cache[cache_key] = (atr, now)
            return atr

        except Exception as e:
            log.debug(f"H1 ATR hatası {symbol}: {e}")
            return 0.0

    # ─── POZİSYONLAR ──────────────────────────────────────

    def get_positions(self, symbol: str) -> List[dict]:
        """Açık pozisyonları çek"""
        if not self.ensure_connected():
            return []

        positions = mt5.positions_get(symbol=self._sym(symbol))
        if not positions:
            return []

        result = []
        for p in positions:
            if p.magic != self.magic_number:
                continue  # Sadece bizim pozisyonlar
            # Comment'ten role ve layer bilgisi parse et
            role, layer = self._parse_comment(p.comment)
            result.append({
                "ticket":     p.ticket,
                "symbol":     p.symbol,
                "type":       p.type,  # 0=BUY, 1=SELL
                "direction":  "BUY" if p.type == 0 else "SELL",
                "lot":        p.volume,
                "volume":     p.volume,
                "open_price": p.price_open,
                "price_open": p.price_open,
                "profit":     p.profit + p.swap,
                "open_time":  p.time,
                "time":       p.time,
                "comment":    p.comment,
                "role":       role,
                "layer":      layer,
            })
        return result

    def get_all_positions(self) -> List[dict]:
        """Tüm sembollerdeki açık pozisyonlar"""
        result = []
        for sym in cfg.SYMBOLS:
            result += self.get_positions(sym)
        return result

    def _parse_comment(self, comment: str) -> tuple:
        """
        Comment'ten role ve layer parse et.
        Yeni format: MIA_MAIN_XAUUSD, MIA_SPM_1_XAUUSD, MIA_HEDGE_XAUUSD
        Eski format: ANA_BFX, SPM1_BFX, HEDGE_BFX
        """
        if not comment:
            return "MAIN", 0
        c = comment.upper()

        # Yeni MIA_ format
        if "MIA_" in c:
            if "SPM" in c:
                parts = c.split("_")
                for i, part in enumerate(parts):
                    if part == "SPM" and i + 1 < len(parts):
                        try:
                            layer = int(parts[i + 1])
                            return f"SPM{layer}", layer
                        except ValueError:
                            return "SPM1", 1
                return "SPM1", 1
            if "HEDGE" in c:
                return "HEDGE", 0
            if "DCA" in c:
                return "DCA", 0
            if "MAIN" in c:
                return "MAIN", 0
            return "MAIN", 0

        # Eski format (geriye uyumluluk)
        if c.startswith("SPM"):
            try:
                layer = int(c.replace("SPM", "").split("_")[0])
                return f"SPM{layer}", layer
            except Exception:
                return "SPM1", 1
        if c.startswith("HEDGE"):
            return "HEDGE", 0
        if c.startswith("DCA"):
            return "DCA", 0
        return "MAIN", 0

    def get_spread(self, symbol: str) -> float:
        """Mevcut spread (points cinsinden)"""
        if not self.ensure_connected():
            return 0
        info = mt5.symbol_info(self._sym(symbol))
        if info:
            return info.spread
        return 0

    def update_spread_baseline(self, symbol: str):
        """
        Rolling spread baseline güncelle.
        Her çağrıda anlık spread ölçer, 20 örnek ortalaması = baseline.
        """
        if not MT5_AVAILABLE or not self.connected:
            return
        info = mt5.symbol_info(self._sym(symbol))
        if not info:
            return
        pts = float(info.spread)
        if pts <= 0:
            return
        if symbol not in self._spread_samples:
            self._spread_samples[symbol] = []
        samples = self._spread_samples[symbol]
        samples.append(pts)
        if len(samples) > 20:
            samples.pop(0)
        self._spread_baseline[symbol] = sum(samples) / len(samples)

    def get_spread_info(self, symbol: str) -> dict:
        """
        Detaylı spread analizi.
        Returns:
          current_pts  : Anlık spread (points)
          current_usd  : Anlık spread (USD, 0.01 lot için)
          typical_pts  : Tipik spread (MT5 symbol_info'dan)
          ratio        : current / typical oranı (1.0 = normal, 1.15 = %15 yüksek)
          is_ok        : cfg.SPREAD_MAX_RATIO altında mı?
          reason       : Neden reddedildi?
        """
        result = {
            "current_pts": 0, "current_usd": 0.0,
            "typical_pts": 0, "ratio": 1.0,
            "is_ok": True,   "reason": "",
        }
        if not self.ensure_connected():
            result["reason"] = "MT5 bağlı değil"
            return result

        info = mt5.symbol_info(self._sym(symbol))
        if not info:
            result["reason"] = "Sembol bulunamadı"
            return result

        current = float(info.spread)   # anlık spread (points)

        # ── BASELINE TESPİTİ (öncelik sırası) ────────────────
        # 1. Rolling baseline (en güvenilir — bağlantı sonrası ölçüm)
        baseline = self._spread_baseline.get(symbol, 0.0)
        # 2. MT5 spread_float (bazı brokerlar verir)
        if baseline <= 0:
            baseline = float(getattr(info, "spread_float", 0) or 0)
        # 3. Symbol class'a göre bilinen tipik değerler
        if baseline <= 0:
            spec    = cfg.SYMBOL_SPECS.get(symbol, {})
            cls     = spec.get("class","major")
            default_baselines = {
                "major": 10.0,   # EURUSD tipik ~1.0 pip = 10 points (5 digit)
                "metal": 25.0,   # XAUUSD tipik ~2.5 pip
                "crypto": 500.0, # BTCUSD tipik ~50 point
            }
            baseline = default_baselines.get(cls, 15.0)
        # 4. Son çare: current spread = baseline (ratio=1.0, geçer)
        if baseline <= 0:
            baseline = current

        typical = baseline
        ratio = current / typical if typical > 0 else 1.0

        # Rolling baseline güncelle (arka planda)
        self.update_spread_baseline(symbol)

        # USD cinsinden maliyet (0.01 lot için)
        tick_val  = info.trade_tick_value  # 1 pip'in 1 lot için USD değeri
        pip_pts   = 10 if info.digits in (5, 3) else 1
        spread_usd_per_lot = (current / pip_pts) * tick_val
        spread_usd = spread_usd_per_lot * 0.01  # 0.01 lot

        max_ratio = cfg.SPREAD_MAX_RATIO  # 1.15 = %15 tolerans
        is_ok     = ratio <= max_ratio
        reason    = "" if is_ok else (
            f"Spread çok yüksek: {current:.0f}pts "
            f"(baseline {typical:.0f}pts, oran {ratio:.2f}x — limit {max_ratio:.2f}x / %{(max_ratio-1)*100:.0f})"
        )

        result.update({
            "current_pts": current,
            "current_usd": round(spread_usd, 5),
            "typical_pts": round(typical, 1),
            "ratio":       round(ratio, 3),
            "is_ok":       is_ok,
            "reason":      reason,
            "pct_above":   round((ratio - 1.0) * 100, 1),   # tipik üstünde kaç %
        })
        return result

    def is_spread_ok(self, symbol: str) -> tuple:
        """
        Spread kabul edilebilir mi?
        Returns: (is_ok: bool, reason: str, spread_info: dict)
        """
        info = self.get_spread_info(symbol)
        return info["is_ok"], info.get("reason",""), info

    # ─── EMİR YÖNETİMİ ────────────────────────────────────

    def open_position(self, symbol: str, direction: str, lot: float,
                      role: str = "ANA", layer: int = 0,
                      comment_extra: str = "") -> Optional[int]:
        """
        Pozisyon aç.
        Returns: ticket (başarılı) veya None (başarısız)
        """
        if not self.ensure_connected():
            log.warning(f"MT5 bağlı değil — {symbol} {direction} {lot} lot AÇILAMADI")
            return None

        sym_info = mt5.symbol_info(self._sym(symbol))
        if sym_info is None:
            log.error(f"Sembol bilgisi yok: {symbol}")
            return None

        if not sym_info.visible:
            mt5.symbol_select(self._sym(symbol), True)

        # ── SPREAD KONTROLÜ ───────────────────────────────
        ok, reason, sp_info = self.is_spread_ok(symbol)
        if not ok:
            log.warning(f"[{symbol}] SPREAD REDDEDİLDİ — {reason}")
            return None
        log.info(f"[{symbol}] Spread OK: {sp_info['current_pts']}pts (oran {sp_info['ratio']:.2f}x) → emir gönderiliyor")

        # Fiyat
        tick = mt5.symbol_info_tick(self._sym(symbol))
        if tick is None:
            log.error(f"Tick bilgisi yok: {symbol}")
            return None

        order_type = mt5.ORDER_TYPE_BUY if direction == "BUY" else mt5.ORDER_TYPE_SELL
        price      = tick.ask if direction == "BUY" else tick.bid

        # ── DİNAMİK LOT HESAPLAMA ─────────────────────────
        # Kullanıcı lot=0 gönderirse otomatik hesapla
        if lot <= 0:
            lot = self.calc_dynamic_lot(symbol, sym_info, sp_info)
        
        # Lot normalize (min/max/step)
        lot = self._normalize_lot(symbol, lot, sym_info)

        broker_sym = self._sym(symbol)   # BTCUSD → BTCUSDm

        # Comment — MIA_ROLE_SYMBOL formatı (grid restart tanıma için)
        sym_short = symbol[:6]
        if role in ("SPM1", "SPM2"):
            comment = f"MIA_SPM_{layer}_{sym_short}"
        elif role in ("MAIN", "ANA"):
            comment = f"MIA_MAIN_{sym_short}"
        elif role in ("HEDGE", "DCA"):
            comment = f"MIA_{role}_{sym_short}"
        else:
            comment = f"MIA_{role}_{sym_short}"
        if comment_extra:
            comment = f"{comment}_{comment_extra[:8]}"

        # Filling mode — sembolün desteklediğini kullan
        filling = mt5.ORDER_FILLING_FOK
        if sym_info and hasattr(sym_info, 'filling_mode'):
            fm = sym_info.filling_mode
            if fm & 2:   filling = mt5.ORDER_FILLING_IOC
            elif fm & 1: filling = mt5.ORDER_FILLING_FOK
            elif fm & 4: filling = mt5.ORDER_FILLING_RETURN

        log.info(f"[{symbol}] EMİR → {direction} {lot}lot @ {price:.5f} | {broker_sym} filling={filling}")

        request = {
            "action":       mt5.TRADE_ACTION_DEAL,
            "symbol":       broker_sym,
            "volume":       lot,
            "type":         order_type,
            "price":        price,
            "sl":           0.0,
            "tp":           0.0,
            "deviation":    30,
            "magic":        self.magic_number,
            "comment":      comment,
            "type_time":    mt5.ORDER_TIME_GTC,
            "type_filling": filling,
        }

        result = mt5.order_send(request)
        if result is None:
            log.error(f"order_send None: {symbol} {direction}")
            return None
        if result.retcode != mt5.TRADE_RETCODE_DONE:
            log.error(f"[{symbol}] EMİR BAŞARISIZ retcode={result.retcode} comment='{result.comment}' | {direction} {lot}lot broker={broker_sym}")
            log.error(f"  Hata açıklaması: {_retcode_desc(result.retcode)}")
            return None

        log.info(f"✅ AÇ: {symbol} {direction} {lot}lot #{result.order} | {comment}")
        return result.order

    def close_position(self, ticket: int) -> bool:
        """Pozisyon kapat"""
        if not self.ensure_connected():
            return False

        pos = mt5.positions_get(ticket=ticket)
        if not pos or len(pos) == 0:
            log.warning(f"Kapat: Pozisyon bulunamadı #{ticket}")
            return False

        p = pos[0]
        tick = mt5.symbol_info_tick(p.symbol)
        if not tick:
            return False

        close_type = mt5.ORDER_TYPE_SELL if p.type == 0 else mt5.ORDER_TYPE_BUY
        close_price= tick.bid if p.type == 0 else tick.ask

        request = {
            "action":   mt5.TRADE_ACTION_DEAL,
            "symbol":   p.symbol,
            "volume":   p.volume,
            "type":     close_type,
            "position": ticket,
            "price":    close_price,
            "deviation": 20,
            "magic":    self.magic_number,
            "comment":  "CLOSE_BFX",
            "type_time": mt5.ORDER_TIME_GTC,
            "type_filling": mt5.ORDER_FILLING_IOC,
        }
        result = mt5.order_send(request)
        if result and result.retcode == mt5.TRADE_RETCODE_DONE:
            log.info(f"✅ KAPAT: #{ticket} {p.symbol} P=${p.profit:.2f}")
            return True
        log.error(f"Kapat HATA: #{ticket} retcode={result.retcode if result else 'None'}")
        return False

    def close_partial(self, ticket: int, lot: float) -> bool:
        """Kısmi kapat"""
        if not self.ensure_connected():
            return False

        pos = mt5.positions_get(ticket=ticket)
        if not pos:
            return False
        p = pos[0]

        tick = mt5.symbol_info_tick(p.symbol)
        close_type  = mt5.ORDER_TYPE_SELL if p.type == 0 else mt5.ORDER_TYPE_BUY
        close_price = tick.bid if p.type == 0 else tick.ask

        lot = self._normalize_lot(p.symbol, lot)

        request = {
            "action":   mt5.TRADE_ACTION_DEAL,
            "symbol":   p.symbol,
            "volume":   lot,
            "type":     close_type,
            "position": ticket,
            "price":    close_price,
            "deviation": 20,
            "magic":    self.magic_number,
            "comment":  f"PARTIAL_BFX",
            "type_time": mt5.ORDER_TIME_GTC,
            "type_filling": mt5.ORDER_FILLING_IOC,
        }
        result = mt5.order_send(request)
        if result and result.retcode == mt5.TRADE_RETCODE_DONE:
            log.info(f"✅ KISMİ KAPAT: #{ticket} {lot}lot")
            return True
        return False

    def close_all_symbol(self, symbol: str, reason: str = ""):
        """Sembolün tüm pozisyonlarını kapat"""
        positions = mt5.positions_get(symbol=self._sym(symbol)) if self.connected else []
        if not positions:
            return
        for p in positions:
            if p.magic == self.magic_number:
                self.close_position(p.ticket)
        log.info(f"[{symbol}] Tüm pozisyonlar kapatıldı | {reason}")

    def close_all(self, reason: str = ""):
        """Tüm açık pozisyonları kapat"""
        for sym in cfg.SYMBOLS:
            self.close_all_symbol(sym, reason)

    # ─── YARDIMCI ─────────────────────────────────────────

    def calc_dynamic_lot(self, symbol: str, sym_info=None, spread_info: dict = None) -> float:
        """
        Balance + spread + sembol tipine göre dinamik lot hesapla.
        
        Formül:
          base_lot  = balance * LOT_RISK_PCT / 100 / risk_per_lot_usd
          spread_adj= spread yüksekse lotu küçült
          dd_adj    = drawdown yüksekse lotu küçült
          
        risk_per_lot_usd: Sembolün 1 pip hareketi = kaç USD (1 lot için)
        """
        import math

        if sym_info is None and self.connected:
            sym_info = mt5.symbol_info(self._sym(symbol))
        if spread_info is None:
            spread_info = self.get_spread_info(symbol)

        acc = self.get_account()
        balance = acc.get("balance", cfg.INITIAL_BALANCE)
        equity  = acc.get("equity",  balance)
        dd_pct  = max(0, (balance - equity) / (balance + 1e-9) * 100)

        # ── ADIM 1: Risk miktarı ──
        risk_usd = balance * (cfg.LOT_RISK_PCT / 100)

        # ── ADIM 2: Margin-based lot hesabı (daha güvenli) ──
        # Hedef: risk_usd kadar margin kullanalım
        # Sembolün margin gereksinimini kullan
        lot_result = cfg.MIN_LOT
        if sym_info and self.connected:
            tick = mt5.symbol_info_tick(self._sym(symbol))
            price = tick.ask if tick else 0
            # Margin hesabı: margin_initial genellikle 1 lot için gerekli margin
            margin_per_lot = sym_info.margin_initial if hasattr(sym_info,'margin_initial') and sym_info.margin_initial > 0 else 0
            if margin_per_lot <= 0 and price > 0:
                # Fallback: price * contract_size / leverage
                contract = sym_info.trade_contract_size if hasattr(sym_info,'trade_contract_size') else 1
                acc_info = mt5.account_info()
                lev = acc_info.leverage if acc_info and acc_info.leverage > 0 else 2000
                margin_per_lot = price * contract / lev
            if margin_per_lot > 0:
                # Bakiyenin max %3'ünü margin olarak kullan (güvenli)
                max_margin = balance * 0.03
                lot_result = max_margin / margin_per_lot
            else:
                lot_result = cfg.MIN_LOT

        # Min lot güvencesi
        base_lot = max(cfg.MIN_LOT, lot_result)

        # ── ADIM 3: Spread düzeltmesi ──
        # Spread normal seviyenin üstünde → lot küçül (lineer ceza)
        ratio = spread_info.get("ratio", 1.0) if spread_info else 1.0
        spread_penalty = 0.0
        if ratio > 1.0:
            # Her %1 fazla spread → lot %1 küçültülür
            # Ör: spread %10 yüksekse → lot %10 küçük
            #     spread %15 yüksekse → lot %15 küçük (limit zaten %15 üstüne girmez ama lot küçülür)
            spread_penalty = min(0.40, (ratio - 1.0))
            base_lot = base_lot * (1.0 - spread_penalty)
            log.info(f"[{symbol}] Spread={ratio:.2f}x → lot -%{spread_penalty*100:.0f} azaltıldı")

        # ── ADIM 4: Drawdown düzeltmesi ──
        if dd_pct > 10:
            dd_penalty = min(0.60, (dd_pct - 10) / 50)  # >10%DD → kademeli küçültme
            base_lot   = base_lot * (1.0 - dd_penalty)
            log.debug(f"[{symbol}] DD düzeltme: dd={dd_pct:.1f}% → lot -{dd_penalty*100:.0f}%")

        # ── ADIM 5: Sınırlar ──
        base_lot = max(cfg.MIN_LOT, min(cfg.MAX_LOT_PER_SYMBOL, base_lot))

        # Step'e yuvarla
        if sym_info and sym_info.volume_step > 0:
            base_lot = math.floor(base_lot / sym_info.volume_step) * sym_info.volume_step

        result = round(base_lot, 2)
        log.info(
            f"[{symbol}] DynamicLot: "
            f"balance=${balance:.2f} | risk=${risk_usd:.2f} | "
            f"spread={ratio:.2f}x(-{spread_penalty*100:.0f}%) | "
            f"dd={dd_pct:.1f}% | "
            f"→ {result}lot"
        )
        return max(cfg.MIN_LOT, result)

    def get_current_price(self, symbol: str, direction: str = "BUY") -> Optional[float]:
        """Anlık fiyat döndür"""
        if not self.connected:
            return None
        tick = mt5.symbol_info_tick(self._sym(symbol))
        if not tick:
            return None
        return tick.ask if direction == "BUY" else tick.bid

    def _normalize_lot(self, symbol: str, lot: float, sym_info=None) -> float:
        if not self.connected:
            return lot
        if sym_info is None:
            sym_info = mt5.symbol_info(self._sym(symbol))
        if sym_info is None:
            return lot

        min_lot  = sym_info.volume_min
        max_lot  = sym_info.volume_max
        lot_step = sym_info.volume_step

        if lot_step > 0:
            import math
            lot = math.floor(lot / lot_step) * lot_step
        lot = max(min_lot, min(max_lot, lot))
        return round(lot, 2)

    def symbol_info(self, symbol: str) -> Optional[dict]:
        if not self.ensure_connected():
            return None
        info = mt5.symbol_info(self._sym(symbol))
        if not info:
            return None
        return {
            "spread":  info.spread,
            "digits":  info.digits,
            "min_lot": info.volume_min,
            "max_lot": info.volume_max,
            "lot_step":info.volume_step,
            "tick_value": info.trade_tick_value,
        }
