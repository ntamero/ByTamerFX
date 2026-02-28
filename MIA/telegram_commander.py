"""
MIA — Telegram Commander v5.2.0
BytamerFX Agent'ının Telegram üzerinden kontrol arayüzü.

Komutlar:
  /durum              — Hesap + açık pozisyonlar
  /ac BTC XAG         — Bu sembollerde işlem açmaya başla
  /kapat BTC GBP      — Bu sembollerin pozisyonlarını kapat
  /durdur BTC         — Bu sembolleri pasife al (yeni işlem açma)
  /tumu_kapat         — Tüm açık pozisyonları kapat
  /tumu_durdur        — Tüm sembolleri pasife al
  /aktif              — Aktif sembol listesi
  /semboller          — Tüm mevcut semboller
  /rapor              — Detaylı P&L raporu
  /brain              — Brain'i şimdi çalıştır
  /regime             — Piyasa rejim durumu
  /sentiment          — Duygu analizi / sentiment skoru
  /ajanlar            — Ajan durumları
  /grid               — Grid/FIFO durumu
  /kasa               — Kasa (birikmiş SPM kârı)
  /haber              — Yaklaşan haberler + bloklar
  /pause              — Tüm işlemleri duraklat
  /resume             — İşlemlere devam et
  /yardim             — Komut listesi

Doğal dil de çalışır:
  "btc ve xag için işlem aç"
  "gbp ve btc kapat"
  "her şeyi durdur"
  "durum nedir"
  "duraklat" / "pause"
  "devam" / "resume"
  "rejim" / "regime"
  "duygu" / "sentiment"
  "ajanlar" / "agent"
  "grid" / "fifo" / "kasa"
  "haber" / "news"
"""

import asyncio
import logging
import threading
import time
import re
import requests as _requests
from typing import Optional, List, Callable
from telegram import Update, Bot
from telegram.ext import (
    Application, CommandHandler, MessageHandler,
    filters, ContextTypes
)
import config as cfg

log = logging.getLogger("Telegram")


class MIACommander:
    """
    MIA (Market Intelligence Agent) Telegram arayüzü.
    Agent ile iki yönlü iletişim:
      - Kullanıcı → komut gönderir
      - MIA → bildirim ve rapor gönderir
    """

    def __init__(self):
        self.bot_token   = cfg.TELEGRAM_TOKEN
        self.chat_id     = cfg.TELEGRAM_CHAT_ID
        self._app        = None
        self._bot        = None
        self._loop       = None
        self._thread     = None
        self._ready      = threading.Event()

        # Callback'ler — main.py tarafından set edilir
        self.on_activate:   Optional[Callable] = None   # fn(symbols: List[str])
        self.on_deactivate: Optional[Callable] = None   # fn(symbols: List[str])
        self.on_close:      Optional[Callable] = None   # fn(symbols: List[str])
        self.on_close_all:  Optional[Callable] = None   # fn()
        self.on_stop_all:   Optional[Callable] = None   # fn()
        self.on_brain_now:  Optional[Callable] = None   # fn()
        self.get_status:    Optional[Callable] = None   # fn() → str
        self.get_report:    Optional[Callable] = None   # fn() → str
        self.get_active_symbols: Optional[Callable] = None  # fn() → List[str]

        # v4.0 — Yeni callback'ler
        self.on_pause:      Optional[Callable] = None   # fn() → pause all trading
        self.on_resume:     Optional[Callable] = None   # fn() → resume trading
        self.get_regime:    Optional[Callable] = None   # fn() → str (regime info)
        self.get_sentiment: Optional[Callable] = None   # fn() → str (sentiment info)
        self.get_agents:    Optional[Callable] = None   # fn() → str (agent statuses)

        # v5.0 — Grid/News callback'ler
        self.get_grid_status: Optional[Callable] = None  # fn() → str (grid/fifo info)
        self.get_kasa:        Optional[Callable] = None  # fn() → str (kasa bilgisi)
        self.get_news_status: Optional[Callable] = None  # fn() → str (news/block info)

    # ─── BAŞLAT / DURDUR ──────────────────────────────────

    def start(self):
        """Telegram bot'u ayrı thread'de başlat"""
        self._thread = threading.Thread(target=self._run_bot, daemon=True)
        self._thread.start()
        self._ready.wait(timeout=10)
        if self._ready.is_set():
            log.info("✅ MIA Telegram Commander hazır")
        else:
            log.warning("⚠️ Telegram bot başlatılamadı")

    def stop(self):
        if self._app and self._loop:
            asyncio.run_coroutine_threadsafe(
                self._app.stop(), self._loop
            )

    def _run_bot(self):
        """Bot'u çalıştıran thread"""
        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)
        self._loop = loop
        loop.run_until_complete(self._start_bot())

    async def _start_bot(self):
        # ── ADIM 1: HTTP ile webhook + eski session temizle ──
        # Bu işlem python-telegram-bot başlamadan önce yapılır
        base = f"https://api.telegram.org/bot{self.bot_token}"
        try:
            # Webhook sil (varsa)
            r = _requests.post(f"{base}/deleteWebhook",
                               json={"drop_pending_updates": True}, timeout=10)
            log.info(f"deleteWebhook: {r.json().get('result','?')}")
            # Eski pending update'leri boşalt
            offset = None
            for _ in range(3):
                params = {"timeout": 0, "limit": 100}
                if offset:
                    params["offset"] = offset
                r = _requests.get(f"{base}/getUpdates", params=params, timeout=10)
                data = r.json()
                updates = data.get("result", [])
                if not updates:
                    break
                offset = updates[-1]["update_id"] + 1
                log.info(f"Eski {len(updates)} güncelleme temizlendi")
            # Offset ile son ack gönder
            if offset:
                _requests.get(f"{base}/getUpdates",
                              params={"offset": offset, "timeout": 0}, timeout=10)
            log.info("Telegram oturumu temizlendi")
        except Exception as e:
            log.warning(f"HTTP temizleme: {e}")

        # 3 saniye bekle — Telegram sunucusunun önceki bağlantıyı kapatması için
        await asyncio.sleep(3)

        # ── ADIM 2: Application kur ──────────────────────────
        self._app = (
            Application.builder()
            .token(self.bot_token)
            .connect_timeout(30)
            .read_timeout(30)
            .build()
        )
        self._bot = self._app.bot

        # Komut handler'ları
        handlers = [
            CommandHandler("start",         self._cmd_start),
            CommandHandler("durum",         self._cmd_durum),
            CommandHandler("ac",            self._cmd_ac),
            CommandHandler("kapat",         self._cmd_kapat),
            CommandHandler("durdur",        self._cmd_durdur),
            CommandHandler("tumu_kapat",    self._cmd_tumu_kapat),
            CommandHandler("tumu_durdur",   self._cmd_tumu_durdur),
            CommandHandler("aktif",         self._cmd_aktif),
            CommandHandler("semboller",     self._cmd_semboller),
            CommandHandler("rapor",         self._cmd_rapor),
            CommandHandler("brain",         self._cmd_brain),
            # v4.0 — Yeni komutlar
            CommandHandler("regime",        self._cmd_regime),
            CommandHandler("sentiment",     self._cmd_sentiment),
            CommandHandler("ajanlar",       self._cmd_ajanlar),
            CommandHandler("pause",         self._cmd_pause),
            CommandHandler("resume",        self._cmd_resume),
            # v5.0 — Grid/News komutları
            CommandHandler("grid",          self._cmd_grid),
            CommandHandler("kasa",          self._cmd_kasa),
            CommandHandler("haber",         self._cmd_haber),
            CommandHandler("news",          self._cmd_haber),
            CommandHandler("fifo",          self._cmd_grid),
            CommandHandler("yardim",        self._cmd_yardim),
            MessageHandler(filters.TEXT & ~filters.COMMAND, self._handle_text),
        ]
        for h in handlers:
            self._app.add_handler(h)

        await self._app.initialize()
        await self._app.start()
        self._ready.set()

        # Başlangıç bildirimi
        await self._send(
            "🤖 *MIA başladı* — BytamerFX Autonomous Agent\n"
            f"Hesap: #{cfg.MT5_LOGIN}\n"
            "Tüm semboller kapalı. /ac komutunu kullanarak başlat.\n"
            "Yardım için /yardim"
        )

        # ── ADIM 3: Polling ──────────────────────────────────
        for attempt in range(10):
            try:
                await self._app.updater.start_polling(
                    drop_pending_updates=True,
                    allowed_updates=["message", "callback_query"],
                    error_callback=self._on_poll_error,
                )
                log.info("Telegram polling başladı")
                break
            except Exception as e:
                wait = (attempt + 1) * 3
                log.warning(f"Polling deneme {attempt+1}/10, {wait}sn bekleniyor: {e}")
                await asyncio.sleep(wait)
        else:
            log.error("Telegram polling 10 denemede başlatılamadı!")

        await asyncio.Event().wait()  # Sonsuza kadar çalış

    def _on_poll_error(self, error: Exception) -> None:
        """Polling hatası — Conflict durumunda sessizce geç"""
        import telegram.error as tge
        if isinstance(error, tge.Conflict):
            log.warning("Telegram Conflict: başka bir bot instance çalışıyor. 10sn beklenecek...")
        else:
            log.error(f"Telegram polling hatası: {error}")

    # ─── KOMUTLAR ─────────────────────────────────────────

    async def _cmd_start(self, update: Update, ctx: ContextTypes.DEFAULT_TYPE):
        if not self._auth(update): return
        await self._cmd_yardim(update, ctx)

    async def _cmd_yardim(self, update: Update, ctx: ContextTypes.DEFAULT_TYPE):
        if not self._auth(update): return
        text = (
            "🤖 *MIA v5.0 — Komut Listesi*\n\n"
            "▶️ *İşlem Başlatma*\n"
            "`/ac BTC XAG` — BTC ve XAG'da işlem aç\n"
            "`/ac HEPSI` — Tüm sembolleri aktive et\n\n"
            "⏹ *Kapatma ve Durdurma*\n"
            "`/kapat BTC GBP` — Bu sembolleri kapat\n"
            "`/kapat HEPSI` — Tüm pozisyonları kapat\n"
            "`/durdur BTC` — BTC'yi pasif yap (var olan poz açık kalır)\n"
            "`/tumu_kapat` — Her şeyi kapat\n"
            "`/tumu_durdur` — Her şeyi durdur\n\n"
            "⏸ *Duraklat / Devam*\n"
            "`/pause` — Tüm işlemleri duraklat\n"
            "`/resume` — İşlemlere devam et\n\n"
            "📊 *Durum ve Raporlar*\n"
            "`/durum` — Anlık hesap durumu\n"
            "`/aktif` — Aktif semboller\n"
            "`/semboller` — Tüm mevcut semboller\n"
            "`/rapor` — Detaylı P&L raporu\n\n"
            "🧠 *Brain ve Ajanlar*\n"
            "`/brain` — Analizi şimdi çalıştır\n"
            "`/regime` — Piyasa rejim durumu\n"
            "`/sentiment` — Duygu/haber analizi\n"
            "`/ajanlar` — Ajan durumları\n\n"
            "📐 *Grid / FIFO / Haber*\n"
            "`/grid` — Grid/FIFO durumu (tüm semboller)\n"
            "`/kasa` — Kasa bilgisi (birikmiş SPM kârı)\n"
            "`/haber` — Yaklaşan haberler ve bloklar\n\n"
            "💬 *Doğal Dil de Çalışır*\n"
            "`btc ve xag için işlem aç`\n"
            "`gbp kapat`\n"
            "`her şeyi durdur`\n"
            "`durum nedir`\n"
            "`duraklat` / `devam et`\n"
            "`rejim` / `sentiment` / `ajanlar`\n"
            "`grid` / `fifo` / `kasa` / `haber`\n\n"
            "📌 *Sembol Takma Adları*\n"
            "BTC=BTCUSD | XAG=XAGUSD | XAU/GOLD=XAUUSD\n"
            "GBP=GBPUSD | JPY=USDJPY | EUR=EURUSD | AUD=AUDUSD"
        )
        await self._send(text)

    async def _cmd_durum(self, update: Update, ctx: ContextTypes.DEFAULT_TYPE):
        if not self._auth(update): return
        if self.get_status:
            status = self.get_status()
            await self._send(status)
        else:
            await self._send("⚠️ Durum verisi henüz hazır değil")

    async def _cmd_ac(self, update: Update, ctx: ContextTypes.DEFAULT_TYPE):
        if not self._auth(update): return
        args = ctx.args
        if not args:
            await self._send("❌ Kullanım: `/ac BTC XAG` veya `/ac HEPSI`")
            return
        symbols = self._parse_symbols(args)
        if not symbols:
            await self._send("❌ Geçerli sembol bulunamadı. /semboller ile listele.")
            return
        if self.on_activate:
            self.on_activate(symbols)
        names = ", ".join(symbols)
        await self._send(f"✅ *Aktive edildi:* {names}\nMIA bu sembollerde işlem aramaya başlıyor...")

    async def _cmd_kapat(self, update: Update, ctx: ContextTypes.DEFAULT_TYPE):
        if not self._auth(update): return
        args = ctx.args
        if not args:
            await self._send("❌ Kullanım: `/kapat BTC GBP` veya `/kapat HEPSI`")
            return

        # HEPSI kontrolü
        if args[0].upper() in ("HEPSI", "ALL", "TUMU", "TÜMÜ"):
            if self.on_close_all:
                self.on_close_all()
            await self._send("🔴 *Tüm pozisyonlar kapatılıyor...*")
            return

        symbols = self._parse_symbols(args)
        if not symbols:
            await self._send("❌ Geçerli sembol bulunamadı.")
            return
        if self.on_close:
            self.on_close(symbols)
        names = ", ".join(symbols)
        await self._send(f"🔴 *Kapatılıyor:* {names}")

    async def _cmd_durdur(self, update: Update, ctx: ContextTypes.DEFAULT_TYPE):
        if not self._auth(update): return
        args = ctx.args
        if not args:
            await self._send("❌ Kullanım: `/durdur BTC` — BTC'yi pasife al")
            return
        symbols = self._parse_symbols(args)
        if not symbols:
            await self._send("❌ Geçerli sembol bulunamadı.")
            return
        if self.on_deactivate:
            self.on_deactivate(symbols)
        names = ", ".join(symbols)
        await self._send(f"⏸ *Durduruldu:* {names}\n(Açık pozisyonlar korunuyor)")

    async def _cmd_tumu_kapat(self, update: Update, ctx: ContextTypes.DEFAULT_TYPE):
        if not self._auth(update): return
        if self.on_close_all:
            self.on_close_all()
        await self._send("🔴 *Tüm pozisyonlar kapatılıyor...*")

    async def _cmd_tumu_durdur(self, update: Update, ctx: ContextTypes.DEFAULT_TYPE):
        if not self._auth(update): return
        if self.on_stop_all:
            self.on_stop_all()
        await self._send("⏸ *Tüm semboller durduruldu.*\nYeniden başlatmak için /ac kullan.")

    async def _cmd_aktif(self, update: Update, ctx: ContextTypes.DEFAULT_TYPE):
        if not self._auth(update): return
        if self.get_active_symbols:
            syms = self.get_active_symbols()
            if syms:
                await self._send(f"✅ *Aktif semboller:* {', '.join(syms)}")
            else:
                await self._send("⏸ Aktif sembol yok. /ac ile başlat.")
        else:
            await self._send("⚠️ Bilgi alınamadı")

    async def _cmd_semboller(self, update: Update, ctx: ContextTypes.DEFAULT_TYPE):
        if not self._auth(update): return
        lines = ["📋 *Mevcut Semboller:*\n"]
        for sym in cfg.ALL_SYMBOLS:
            spec = cfg.SYMBOL_SPECS.get(sym, {})
            alias = [k for k, v in cfg.SYMBOL_ALIASES.items() if v == sym]
            alias_str = f" ({', '.join(alias)})" if alias else ""
            lines.append(f"• `{sym}`{alias_str} — {spec.get('class','')}")
        await self._send("\n".join(lines))

    async def _cmd_rapor(self, update: Update, ctx: ContextTypes.DEFAULT_TYPE):
        if not self._auth(update): return
        if self.get_report:
            report = self.get_report()
            await self._send(report)
        else:
            await self._send("⚠️ Rapor hazır değil")

    async def _cmd_brain(self, update: Update, ctx: ContextTypes.DEFAULT_TYPE):
        if not self._auth(update): return
        await self._send("🧠 *Brain analizi başlatılıyor...*")
        if self.on_brain_now:
            self.on_brain_now()

    # ─── v4.0 YENİ KOMUTLAR ────────────────────────────────

    async def _cmd_regime(self, update: Update, ctx: ContextTypes.DEFAULT_TYPE):
        if not self._auth(update): return
        if self.get_regime:
            info = self.get_regime()
            await self._send(f"📈 *Piyasa Rejimi*\n{info}")
        else:
            await self._send("⚠️ Rejim verisi henüz hazır değil")

    async def _cmd_sentiment(self, update: Update, ctx: ContextTypes.DEFAULT_TYPE):
        if not self._auth(update): return
        if self.get_sentiment:
            info = self.get_sentiment()
            await self._send(f"💬 *Sentiment Analizi*\n{info}")
        else:
            await self._send("⚠️ Sentiment verisi henüz hazır değil")

    async def _cmd_ajanlar(self, update: Update, ctx: ContextTypes.DEFAULT_TYPE):
        if not self._auth(update): return
        if self.get_agents:
            info = self.get_agents()
            await self._send(f"🤖 *Ajan Durumları*\n{info}")
        else:
            await self._send("⚠️ Ajan bilgisi henüz hazır değil")

    async def _cmd_pause(self, update: Update, ctx: ContextTypes.DEFAULT_TYPE):
        if not self._auth(update): return
        if self.on_pause:
            self.on_pause()
        await self._send("⏸ *Tüm işlemler duraklatıldı.*\nDevam etmek için /resume kullan.")

    async def _cmd_resume(self, update: Update, ctx: ContextTypes.DEFAULT_TYPE):
        if not self._auth(update): return
        if self.on_resume:
            self.on_resume()
        await self._send("▶️ *İşlemler tekrar aktif.*\nMIA normal operasyona devam ediyor.")

    # ─── v5.0 GRID/NEWS KOMUTLARI ────────────────────────

    async def _cmd_grid(self, update: Update, ctx: ContextTypes.DEFAULT_TYPE):
        if not self._auth(update): return
        if self.get_grid_status:
            info = self.get_grid_status()
            await self._send(f"📐 *Grid/FIFO Durumu*\n{info}")
        else:
            await self._send("⚠️ Grid verisi henüz hazır değil")

    async def _cmd_kasa(self, update: Update, ctx: ContextTypes.DEFAULT_TYPE):
        if not self._auth(update): return
        if self.get_kasa:
            info = self.get_kasa()
            await self._send(f"💰 *Kasa Durumu*\n{info}")
        else:
            await self._send("⚠️ Kasa verisi henüz hazır değil")

    async def _cmd_haber(self, update: Update, ctx: ContextTypes.DEFAULT_TYPE):
        if not self._auth(update): return
        if self.get_news_status:
            info = self.get_news_status()
            await self._send(f"📰 *Haber Durumu*\n{info}")
        else:
            await self._send("⚠️ Haber verisi henüz hazır değil")

    # ─── DOĞAL DİL ────────────────────────────────────────

    async def _handle_text(self, update: Update, ctx: ContextTypes.DEFAULT_TYPE):
        if not self._auth(update): return
        text = update.message.text.lower().strip()

        # Açma komutları
        if any(w in text for w in ["işlem aç", "aç", "başla", "aktive", "trade aç", "al", "start"]):
            symbols = self._extract_symbols_from_text(text)
            if "hepsi" in text or "tümü" in text or "tumu" in text or "all" in text:
                symbols = cfg.ALL_SYMBOLS
            if symbols:
                if self.on_activate:
                    self.on_activate(symbols)
                await self._send(f"✅ *Aktive:* {', '.join(symbols)}")
            else:
                await self._send("Hangi sembol? Örnek: `btc ve xag için işlem aç`")
            return

        # Kapatma komutları
        if any(w in text for w in ["kapat", "çık", "close", "sat", "kap"]):
            if "hepsi" in text or "tümü" in text or "tumu" in text or "all" in text:
                if self.on_close_all:
                    self.on_close_all()
                await self._send("🔴 Tüm pozisyonlar kapatılıyor")
                return
            symbols = self._extract_symbols_from_text(text)
            if symbols:
                if self.on_close:
                    self.on_close(symbols)
                await self._send(f"🔴 Kapatılıyor: {', '.join(symbols)}")
            else:
                await self._send("Hangi sembol? Örnek: `btc ve gbp kapat`")
            return

        # Durdurma
        if any(w in text for w in ["durdur", "dur", "pasif", "stop", "bekle"]):
            if "hepsi" in text or "tümü" in text or "all" in text:
                if self.on_stop_all:
                    self.on_stop_all()
                await self._send("⏸ Tüm semboller durduruldu")
            else:
                symbols = self._extract_symbols_from_text(text)
                if symbols:
                    if self.on_deactivate:
                        self.on_deactivate(symbols)
                    await self._send(f"⏸ Durduruldu: {', '.join(symbols)}")
            return

        # Durum sorgusu
        if any(w in text for w in ["durum", "nedir", "bakiye", "hesap", "kaç", "status", "nasıl"]):
            if self.get_status:
                await self._send(self.get_status())
            return

        # Rapor
        if any(w in text for w in ["rapor", "kazanç", "kar", "zarar", "sonuç"]):
            if self.get_report:
                await self._send(self.get_report())
            return

        # Brain
        if any(w in text for w in ["analiz", "brain", "değerlendir", "bak"]):
            await self._send("🧠 Analiz başlatılıyor...")
            if self.on_brain_now:
                self.on_brain_now()
            return

        # v4.0 — Duraklat
        if any(w in text for w in ["duraklat", "pause", "beklet"]):
            if self.on_pause:
                self.on_pause()
            await self._send("⏸ Tüm işlemler duraklatıldı. /resume ile devam.")
            return

        # v4.0 — Devam
        if any(w in text for w in ["devam", "resume", "baslat tekrar"]):
            if self.on_resume:
                self.on_resume()
            await self._send("▶️ İşlemler tekrar aktif.")
            return

        # v4.0 — Rejim
        if any(w in text for w in ["regime", "rejim", "piyasa durumu"]):
            if self.get_regime:
                await self._send(f"📈 *Rejim*\n{self.get_regime()}")
            else:
                await self._send("⚠️ Rejim verisi henüz hazır değil")
            return

        # v4.0 — Sentiment
        if any(w in text for w in ["duygu", "sentiment", "haber"]):
            if self.get_sentiment:
                await self._send(f"💬 *Sentiment*\n{self.get_sentiment()}")
            else:
                await self._send("⚠️ Sentiment verisi henüz hazır değil")
            return

        # v4.0 — Ajanlar
        if any(w in text for w in ["ajan", "ajanlar", "agent"]):
            if self.get_agents:
                await self._send(f"🤖 *Ajanlar*\n{self.get_agents()}")
            else:
                await self._send("⚠️ Ajan bilgisi henüz hazır değil")
            return

        # v5.0 — Grid/FIFO
        if any(w in text for w in ["grid", "fifo", "ızgara"]):
            if self.get_grid_status:
                await self._send(f"📐 *Grid*\n{self.get_grid_status()}")
            else:
                await self._send("⚠️ Grid verisi henüz hazır değil")
            return

        # v5.0 — Kasa
        if any(w in text for w in ["kasa", "birikmiş", "spm kar"]):
            if self.get_kasa:
                await self._send(f"💰 *Kasa*\n{self.get_kasa()}")
            else:
                await self._send("⚠️ Kasa verisi henüz hazır değil")
            return

        # v5.0 — Haber
        if any(w in text for w in ["haber", "news", "ekonomik takvim", "blok"]):
            if self.get_news_status:
                await self._send(f"📰 *Haberler*\n{self.get_news_status()}")
            else:
                await self._send("⚠️ Haber verisi henüz hazır değil")
            return

        # Anlayamadı
        await self._send(
            "❓ Anlayamadım. Örnekler:\n"
            "• `btc ve xag için işlem aç`\n"
            "• `gbp ve btc kapat`\n"
            "• `durum nedir`\n"
            "• `duraklat` / `devam`\n"
            "• `rejim` / `sentiment` / `ajanlar`\n"
            "• `grid` / `kasa` / `haber`\n"
            "• `/yardim` — tam komut listesi"
        )

    # ─── BİLDİRİM GÖNDERİCİ ──────────────────────────────
    # Bu metodlar main.py'den çağrılır

    def notify(self, message: str):
        """Anlık bildirim gönder (thread-safe)"""
        if not cfg.TELEGRAM_ENABLED or not self._loop:
            return
        try:
            asyncio.run_coroutine_threadsafe(
                self._send(message), self._loop
            )
        except Exception as e:
            log.debug(f"Telegram notify hatası: {e}")

    def notify_trade_open(self, symbol: str, direction: str, lot: float,
                           price: float, reason: str, extra: dict = None):
        e       = extra or {}
        emoji   = "🟢" if direction == "BUY" else "🔴"
        dir_txt = "ALIS" if direction == "BUY" else "SATIS"
        sym_s   = symbol.replace("USD","").replace("USDJPY","JPY")
        pr_s    = f"{price:.5f}" if price else "--"
        bal     = e.get("balance")
        bal_s   = f"${bal:.2f}" if isinstance(bal,(int,float)) else "--"
        skor    = e.get("ai_score", 0)
        ses     = e.get("session", "--")
        spm     = e.get("spm_count", 0)
        kasa    = e.get("kasa", 0)
        msg = (
            f"{emoji} *{sym_s} {dir_txt} ACILDI*\n"
            f"Lot: `{lot}` | Fiyat: `{pr_s}`\n"
            f"Bakiye: `{bal_s}` | AI: `{skor:.0f}/100`\n"
            f"Seans: `{ses}` | SPM: `{spm}` | Kasa: `${kasa:.2f}`"
        )
        self.notify(msg)

    def notify_spread_blocked(self, symbol: str, current_pts: int,
                               typical_pts: int, ratio: float):
        """Spread yüksek — sadece log, Telegram gönderme"""
        log.warning(f"[SPREAD] {symbol}: {current_pts}pts (oran {ratio:.2f}x) — işlem açılmadı")

    def notify_trade_close(self, symbol: str, role: str, pnl: float,
                            reason: str, extra: dict = None):
        """İşlem kapandı — detaylı bildirim (BytamerAI EA formatı)"""
        e     = extra or {}
        emoji = "💰" if pnl > 0 else "🔴"
        sym_s = symbol.replace("USD","").replace("USDJPY","JPY")

        # Temel bilgiler
        bal     = e.get("balance")
        bal_s   = f"${bal:.2f}" if isinstance(bal,(int,float)) else "--"
        daily   = e.get("daily_pnl")
        day_s   = f"${daily:+.2f}" if isinstance(daily,(int,float)) else "--"

        # Ek detaylar
        lot     = e.get("lot", 0)
        lot_s   = f"`{lot:.2f}`" if lot else "--"
        ticket  = e.get("ticket", 0)
        tkt_s   = f"#{ticket}" if ticket else ""
        o_price = e.get("open_price", 0)
        c_price = e.get("close_price", 0)
        op_s    = f"`{o_price:.5f}`" if o_price else "--"
        cp_s    = f"`{c_price:.5f}`" if c_price else "--"
        direction = e.get("direction", "")
        dir_s   = "ALIS" if direction == "BUY" else "SATIS" if direction == "SELL" else ""

        # PnL emoji
        if pnl > 0:
            pnl_line = f"💰 P&L: `${pnl:+.2f}`"
        else:
            pnl_line = f"🔴 P&L: `${pnl:+.2f}`"

        msg = (
            f"{emoji} *{sym_s} {role} KAPANDI* {tkt_s}\n"
            f"{'═' * 28}\n"
        )
        if dir_s:
            msg += f"Yön: `{dir_s}` | Lot: {lot_s}\n"
        if o_price:
            msg += f"Açılış: {op_s}\n"
        if c_price:
            msg += f"Kapanış: {cp_s}\n"
        msg += (
            f"{pnl_line}\n"
            f"{'═' * 28}\n"
            f"Bakiye: `{bal_s}` | Gün: `{day_s}`"
        )
        self.notify(msg)

    def notify_fifo(self, symbol: str, net_pnl: float, kasa: float = 0):
        """FIFO tamamlandı — sadece karlıysa bildir"""
        if net_pnl <= 0:
            return
        sym_s = symbol.replace("USD","").replace("USDJPY","JPY")
        self.notify(
            f"🔵 *{sym_s} FIFO +${net_pnl:.2f}* | Kasa: `${kasa:.2f}`"
        )

    def notify_grid_action(self, symbol: str, action: str, details: str = ""):
        """Grid/FIFO aksiyonu — SPM/DCA/HEDGE açma/kapama"""
        sym_s = symbol.replace("USD", "").replace("USDJPY", "JPY")
        emoji = "📐"
        if "CLOSE" in action or "SETTLE" in action:
            emoji = "🔵"
        elif "OPEN" in action:
            emoji = "📐"
        elif "DEADLOCK" in action:
            emoji = "⚠️"
        detail_s = f"\n{details}" if details else ""
        self.notify(f"{emoji} *{sym_s} {action}*{detail_s}")

    def notify_news_block(self, symbol: str, news_title: str, minutes: int):
        """Haber bloku — sembol geçici olarak kapatıldı"""
        sym_s = symbol.replace("USD", "").replace("USDJPY", "JPY")
        self.notify(f"📰 *{sym_s} HABER BLOKU*\n{news_title}\n{minutes}dk kaldı")

    def notify_warning(self, message: str):
        """Uyarı — sadece kritik durumlar için çağır"""
        self.notify(f"⚠️ {message}")

    def notify_emergency(self, message: str):
        """Acil durum — DD limiti, margin call vb."""
        self.notify(f"🚨 *ACİL* — {message}")

    def notify_brain_decision(self, market_read: str, risk: str, focus: list):
        """Brain kararı — sadece HIGH/CRITICAL risk seviyesinde gönder"""
        if risk not in ("HIGH", "CRITICAL"):
            return   # LOW/MEDIUM → sessiz
        syms = " ".join(focus) if focus else ""
        short = market_read[:120] if market_read else ""
        self.notify(
            f"🧠 *{risk}* {syms}\n_{short}_"
        )

    def notify_status_periodic(self, balance: float, equity: float,
                                 pnl: float, dd: float, open_pos: int):
        """Periyodik durum — artık çağrılmıyor, sessiz"""
        pass  # Gürültü yaratmasın — /durum komutu ile sorgula

    def notify_daily_report(self, balance: float, daily_pnl: float,
                             wins: int, losses: int, symbols: list):
        """Günlük kapanış raporu — gün sonu bir kez"""
        total = wins + losses
        wr    = round(wins / total * 100) if total else 0
        sym_s = " ".join(s.replace("USD","") for s in symbols) if symbols else "—"
        emoji = "📈" if daily_pnl >= 0 else "📉"
        self.notify(
            f"{emoji} *Günlük Rapor*\n"
            f"Bakiye: `${balance:.2f}` | Gün P&L: `${daily_pnl:+.2f}`\n"
            f"İşlem: {total} ({wins}K/{losses}Z) | WR: %{wr}\n"
            f"Semboller: {sym_s}"
        )

    # ─── YARDIMCILAR ──────────────────────────────────────

    def _auth(self, update: Update) -> bool:
        """Yetkili kullanıcıdan gelen mesajları işle"""
        chat_id = update.effective_chat.id
        allowed = getattr(cfg, 'TELEGRAM_USER_IDS', [self.chat_id])
        if chat_id not in allowed:
            log.warning(f"Yetkisiz erişim: chat_id={chat_id}")
            return False
        return True

    def _parse_symbols(self, args: List[str]) -> List[str]:
        """Komut argümanlarından sembol listesi çıkar"""
        result = []
        for arg in args:
            sym = self._resolve_symbol(arg.upper())
            if sym and sym not in result:
                result.append(sym)
        return result

    def _extract_symbols_from_text(self, text: str) -> List[str]:
        """Doğal dil metninden sembolleri çıkar"""
        result = []
        text_upper = text.upper()
        # Önce takma adları kontrol et
        for alias, sym in cfg.SYMBOL_ALIASES.items():
            if alias in text_upper and sym not in result:
                result.append(sym)
        # Sonra tam sembol adlarını kontrol et
        for sym in cfg.ALL_SYMBOLS:
            if sym in text_upper and sym not in result:
                result.append(sym)
        return result

    def _resolve_symbol(self, name: str) -> Optional[str]:
        """Takma adı gerçek sembol adına çevir"""
        if name in cfg.ALL_SYMBOLS:
            return name
        return cfg.SYMBOL_ALIASES.get(name)

    async def _send(self, text: str):
        """Telegram mesajı gönder — Markdown hatası olursa düz metin dene"""
        if not self._bot:
            log.debug(f"[Telegram] Bot hazır değil: {text[:50]}")
            return
        # Özel karakterleri temizle (━ gibi box-drawing karakterler 400 hatası verir)
        clean = (text
                 .replace("━", "-")
                 .replace("═", "=")
                 .replace("│", "|")
                 .replace("╔","").replace("╗","").replace("╚","").replace("╝","")
                 .replace("■","*").replace("◆","*").replace("⊞","*"))
        try:
            await self._bot.send_message(
                chat_id    = self.chat_id,
                text       = clean,
                parse_mode = "Markdown",
            )
        except Exception:
            # Markdown parse hatası → düz metin olarak tekrar dene
            try:
                plain = (clean
                         .replace("*","").replace("`","")
                         .replace("_","").replace("[","").replace("]",""))
                await self._bot.send_message(
                    chat_id = self.chat_id,
                    text    = plain,
                )
            except Exception as e2:
                log.debug(f"[Telegram] Gönderme hatası: {e2}")
