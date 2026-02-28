//+------------------------------------------------------------------+
//|  MIA_Dashboard.mq5                                               |
//|  BytamerFX v3.8 - MIA Chart Dashboard                           |
//|  Python MIA'dan veri okur, chart uzerinde panel gosterir        |
//|  Copyright 2026, By T@MER - https://www.bytamer.com            |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, By T@MER"
#property link      "https://www.bytamer.com"
#property version   "3.80"
#property strict

//--- Input parametreleri
input string   DataFolder    = "MIA";          // MIA veri klasoru (MT5\Files\MIA\)
input int      RefreshMs     = 1000;           // Yenileme suresi (ms)
input int      PanelX        = 5;             // Panel X konumu
input int      PanelY        = 25;            // Panel Y konumu
input int      PanelWidth    = 240;           // Panel genisligi
input color    ColorBull     = clrLime;       // Yukari rengi
input color    ColorBear     = clrRed;        // Asagi rengi
input color    ColorNeutral  = clrGray;       // Notr rengi
input color    ColorAccent   = clrDodgerBlue; // Vurgu rengi
input color    ColorPanel    = C'13,15,20';   // Panel arkaplan
input color    ColorHeader   = C'10,18,35';   // Baslik arkaplan
input color    ColorText     = C'200,214,232';// Metin rengi
input color    ColorMuted    = C'90,106,130'; // Soluk metin
input bool     ShowBB        = true;          // Bollinger Bands goster
input bool     ShowSAR       = true;          // Parabolic SAR goster
input bool     ShowEMA       = true;          // EMA cizgileri goster
input bool     ShowSignals   = true;          // Sinyal oklari

//--- Gosterge handle'lari
int            g_bb_handle   = INVALID_HANDLE;
int            g_sar_handle  = INVALID_HANDLE;
int            g_ema8_handle = INVALID_HANDLE;
int            g_ema21_handle= INVALID_HANDLE;
int            g_ema50_handle= INVALID_HANDLE;

//--- Panel nesneleri prefix
string         PREFIX        = "MIA_";
string         g_symbol;
string         g_datafile;

//--- Son okunan veri
struct MIAData {
   double   balance;
   double   equity;
   double   margin_level;
   double   rsi;
   double   adx;
   double   atr;
   double   spread_pts;
   int      buy_score;
   int      sell_score;
   string   trend;
   string   session;
   string   direction;       // ALIŞ / SATIŞ / NOTR
   string   durum;           // AKTIF / PASIF
   double   kasa;
   double   main_pnl;
   int      spm_count;
   double   fifo_net;
   double   fifo_target;
   string   global_risk;
   string   market_read;
   double   tp1, tp2, tp3;
   int      ema_score, macd_score, adx_score;
   int      rsi_score, bb_score, stoch_score, atr_score;
   int      open_positions;
   double   daily_pnl;
   int      fg_index;
   string   fg_label;
   bool     spread_ok;
   double   spread_ratio;
   double   ema8, ema21, ema50;
};

MIAData g_data;
datetime g_last_update = 0;
bool     g_panel_built  = false;

//+------------------------------------------------------------------+
int OnInit()
{
   g_symbol   = Symbol();
   g_datafile = DataFolder + "\\" + g_symbol + ".json";
   
   // Varsayilan deger
   g_data.balance      = AccountInfoDouble(ACCOUNT_BALANCE);
   g_data.equity       = AccountInfoDouble(ACCOUNT_EQUITY);
   g_data.durum        = "PASIF";
   g_data.direction    = "NOTR";
   g_data.global_risk  = "MEDIUM";
   g_data.fifo_target  = 5.0;
   g_data.session      = "--";
   g_data.trend        = "--";
   
   // Gostergeler
   if(ShowBB) {
      g_bb_handle = iBands(_Symbol, PERIOD_M15, 20, 0, 2.0, PRICE_CLOSE);
   }
   if(ShowSAR) {
      g_sar_handle = iSAR(_Symbol, PERIOD_M15, 0.02, 0.2);
   }
   if(ShowEMA) {
      g_ema8_handle  = iMA(_Symbol, PERIOD_M15, 8,  0, MODE_EMA, PRICE_CLOSE);
      g_ema21_handle = iMA(_Symbol, PERIOD_M15, 21, 0, MODE_EMA, PRICE_CLOSE);
      g_ema50_handle = iMA(_Symbol, PERIOD_M15, 50, 0, MODE_EMA, PRICE_CLOSE);
   }
   
   // Panel insa et
   BuildPanel();
   
   // Timer baslat
   EventSetMillisecondTimer(RefreshMs);
   
   Print("MIA Dashboard basladi: ", g_symbol);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   DeleteAllObjects();
   
   // Gosterge handle'larini serbest birak
   if(g_bb_handle    != INVALID_HANDLE) IndicatorRelease(g_bb_handle);
   if(g_sar_handle   != INVALID_HANDLE) IndicatorRelease(g_sar_handle);
   if(g_ema8_handle  != INVALID_HANDLE) IndicatorRelease(g_ema8_handle);
   if(g_ema21_handle != INVALID_HANDLE) IndicatorRelease(g_ema21_handle);
   if(g_ema50_handle != INVALID_HANDLE) IndicatorRelease(g_ema50_handle);
}

//+------------------------------------------------------------------+
void OnTimer()
{
   ReadDataFile();
   UpdatePanel();
   DrawIndicatorLines();
   if(ShowSignals) DrawSignalArrows();
   ChartRedraw();
}

//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long& lparam,
                  const double& dparam, const string& sparam)
{
   // Panel tiklandiysa veya chart boyutu degistiyse yenile
   if(id == CHARTEVENT_CHART_CHANGE) {
      DeleteAllObjects();
      BuildPanel();
      UpdatePanel();
   }
}

//+------------------------------------------------------------------+
//  VERI OKUMA - Python MIA'nin yazdigi JSON dosyayi oku
//+------------------------------------------------------------------+
void ReadDataFile()
{
   int fh = FileOpen(g_datafile, FILE_READ | FILE_TXT);
   if(fh == INVALID_HANDLE) {
      // Dosya yok = MIA henuz baslamadi veya sembol aktif degil
      g_data.durum = "PASIF";
      return;
   }
   
   string json = "";
   while(!FileIsEnding(fh)) {
      json += FileReadString(fh);
   }
   FileClose(fh);
   
   if(StringLen(json) < 10) return;
   
   // JSON parse - basit key:value okuma
   g_data.balance      = JsonGetDouble(json, "balance",     g_data.balance);
   g_data.equity       = JsonGetDouble(json, "equity",      g_data.equity);
   g_data.margin_level = JsonGetDouble(json, "margin_level",g_data.margin_level);
   g_data.rsi          = JsonGetDouble(json, "rsi",         50.0);
   g_data.adx          = JsonGetDouble(json, "adx",         0.0);
   g_data.atr          = JsonGetDouble(json, "atr",         0.0);
   g_data.spread_pts   = JsonGetDouble(json, "spread_pts",  0.0);
   g_data.buy_score    = (int)JsonGetDouble(json, "buy_score",  0);
   g_data.sell_score   = (int)JsonGetDouble(json, "sell_score", 0);
   g_data.trend        = JsonGetString(json, "trend",       "--");
   g_data.session      = JsonGetString(json, "session",     "--");
   g_data.direction    = JsonGetString(json, "direction",   "NOTR");
   g_data.durum        = JsonGetString(json, "durum",       "PASIF");
   g_data.kasa         = JsonGetDouble(json, "kasa",        0.0);
   g_data.main_pnl     = JsonGetDouble(json, "main_pnl",    0.0);
   g_data.spm_count    = (int)JsonGetDouble(json, "spm_count", 0);
   g_data.fifo_net     = JsonGetDouble(json, "fifo_net",    0.0);
   g_data.fifo_target  = JsonGetDouble(json, "fifo_target", 5.0);
   g_data.global_risk  = JsonGetString(json, "global_risk", "MEDIUM");
   g_data.market_read  = JsonGetString(json, "market_read", "");
   g_data.tp1          = JsonGetDouble(json, "tp1",         0.0);
   g_data.tp2          = JsonGetDouble(json, "tp2",         0.0);
   g_data.tp3          = JsonGetDouble(json, "tp3",         0.0);
   g_data.ema_score    = (int)JsonGetDouble(json, "ema_score",   0);
   g_data.macd_score   = (int)JsonGetDouble(json, "macd_score",  0);
   g_data.adx_score    = (int)JsonGetDouble(json, "adx_score",   0);
   g_data.rsi_score    = (int)JsonGetDouble(json, "rsi_score",   0);
   g_data.bb_score     = (int)JsonGetDouble(json, "bb_score",    0);
   g_data.stoch_score  = (int)JsonGetDouble(json, "stoch_score", 0);
   g_data.atr_score    = (int)JsonGetDouble(json, "atr_score",   0);
   g_data.open_positions=(int)JsonGetDouble(json, "open_positions",0);
   g_data.daily_pnl    = JsonGetDouble(json, "daily_pnl",   0.0);
   g_data.fg_index     = (int)JsonGetDouble(json, "fg_index",0);
   g_data.fg_label     = JsonGetString(json, "fg_label",    "--");
   g_data.spread_ok    = JsonGetDouble(json, "spread_ok",   1.0) > 0.5;
   g_data.spread_ratio = JsonGetDouble(json, "spread_ratio",1.0);
   g_data.ema8         = JsonGetDouble(json, "ema8",        0.0);
   g_data.ema21        = JsonGetDouble(json, "ema21",       0.0);
   g_data.ema50        = JsonGetDouble(json, "ema50",       0.0);
   
   g_last_update = TimeCurrent();
}

//+------------------------------------------------------------------+
//  PANEL INSA
//+------------------------------------------------------------------+
void BuildPanel()
{
   int x = PanelX;
   int y = PanelY;
   int w = PanelWidth;
   
   // Ana panel arka plani
   CreateRect(PREFIX+"bg", x, y, w, 760, ColorPanel, ColorPanel, 1, 85);
   
   // Baslik
   CreateRect(PREFIX+"hdr", x, y, w, 22, ColorHeader, ColorAccent, 1, 255);
   CreateLabel(PREFIX+"hdr_title", x+6, y+4, "■ ANA BILGILER", ColorAccent, 8, true);
   CreateLabel(PREFIX+"hdr_collapse", x+w-15, y+4, "▼", ColorMuted, 8);
   
   int row = y + 26;
   int rh  = 16; // satir yüksekligi
   
   // ANA BILGILER satirlari
   string ana_labels[] = {
      "Versiyon:", "Bakiye:", "Varlik:", "Margin:",
      "Sembol:", "RSI(14):", "ADX(14):", "Spread:",
      "ATR(14):", "Pozisyon:", "Trend:", "Durum:", "+DI/-DI:"
   };
   for(int i = 0; i < ArraySize(ana_labels); i++) {
      CreateLabel(PREFIX+"al_"+IntegerToString(i), x+6, row+i*rh, ana_labels[i], ColorMuted, 7);
   }
   
   row += ArraySize(ana_labels) * rh + 4;
   
   // Bolum ayirici - SINYAL SKORU
   CreateRect(PREFIX+"s_hdr", x, row, w, 22, ColorHeader, ColorAccent, 1, 255);
   CreateLabel(PREFIX+"s_title", x+6, row+4, "▲ SINYAL SKORU", ColorAccent, 8, true);
   row += 26;
   
   // ALIS bar track
   CreateLabel(PREFIX+"sl_buy", x+6, row, "▲ ALIS Skor:", ColorBull, 7);
   CreateRect(PREFIX+"sbar_buy_bg",   x+6,   row+12, w-12, 8, C'20,50,20', C'0,100,0', 1, 200);
   CreateRect(PREFIX+"sbar_buy_fill", x+6,   row+12, 0,    8, ColorBull, ColorBull, 0, 220);
   CreateLabel(PREFIX+"sv_buy", x+w-40, row, "0/100", ColorBull, 7);
   row += 24;
   
   // SATIS bar track
   CreateLabel(PREFIX+"sl_sell", x+6, row, "▼ SATIS Skor:", ColorBear, 7);
   CreateRect(PREFIX+"sbar_sell_bg",   x+6, row+12, w-12, 8, C'50,20,20', C'100,0,0', 1, 200);
   CreateRect(PREFIX+"sbar_sell_fill", x+6, row+12, 0,    8, ColorBear, ColorBear, 0, 220);
   CreateLabel(PREFIX+"sv_sell", x+w-40, row, "0/100", ColorBear, 7);
   row += 26;
   
   // YON etiketi
   CreateLabel(PREFIX+"yon_lbl", x+6,    row, "Yon:", ColorMuted, 7);
   CreateRect(PREFIX+"yon_tag",  x+50,   row-2, 90, 14, C'20,30,20', ColorBull, 1, 200);
   CreateLabel(PREFIX+"yon_val", x+54,   row, "NOTR", ColorBull, 7);
   row += 20;
   
   // 7 katman mini bar
   string layer_names[] = {
      "EMA Trend:", "MACD Mom.:", "ADX Guc:", 
      "RSI Sevye:", "BB Pozisyn:", "Stoch Sny:", "ATR Volat.:"
   };
   string layer_maxs[]  = {"20","20","15","15","15","10","5"};
   for(int i = 0; i < 7; i++) {
      CreateLabel(PREFIX+"ll_"+IntegerToString(i), x+6, row+i*14, layer_names[i], ColorMuted, 6);
      CreateRect(PREFIX+"lb_bg_"+IntegerToString(i),   x+85, row+i*14, w-91, 6, C'20,25,35', ColorMuted, 0, 150);
      CreateRect(PREFIX+"lb_fill_"+IntegerToString(i), x+85, row+i*14, 0,    6, ColorBull, ColorBull, 0, 200);
      CreateLabel(PREFIX+"lv_"+IntegerToString(i), x+w-28, row+i*14, "0/"+layer_maxs[i], ColorMuted, 6);
   }
   row += 7*14 + 6;
   
   // TP + INDIKTORLER bolumu
   CreateRect(PREFIX+"tp_hdr", x, row, w, 22, ColorHeader, ColorAccent, 1, 255);
   CreateLabel(PREFIX+"tp_title", x+6, row+4, "◆ TP + INDIKTORLER", ColorAccent, 8, true);
   row += 26;
   
   string tp_labels[] = {"TP1:", "TP2:", "TP3:", "TP Seviye:",
                          "Trend Guc:", "SAR:", "Mom:",
                          "Fear&Greed:", "Seans:"};
   for(int i = 0; i < ArraySize(tp_labels); i++) {
      CreateLabel(PREFIX+"tl_"+IntegerToString(i), x+6, row+i*rh, tp_labels[i], ColorMuted, 7);
   }
   row += ArraySize(tp_labels) * rh + 4;
   
   // BIDIR-GRID bolumu
   CreateRect(PREFIX+"g_hdr", x, row, w, 22, ColorHeader, ColorAccent, 1, 255);
   CreateLabel(PREFIX+"g_title", x+6, row+4, "⊞ BIDIR-GRID v3.1.0", ColorAccent, 8, true);
   row += 26;
   
   string grid_labels[] = {
      "Gunluk:", "Islemler:", "Bugün:", "Ana P/L:",
      "BUY/SELL:", "SPM/DCA/HG:", "Kasa:", "Acik P/L:",
      "FIFO Net:", "Hedef:", "Ilerleme:"
   };
   for(int i = 0; i < ArraySize(grid_labels); i++) {
      CreateLabel(PREFIX+"gl_"+IntegerToString(i), x+6, row+i*rh, grid_labels[i], ColorMuted, 7);
   }
   row += ArraySize(grid_labels) * rh + 4;
   
   // FIFO ilerleme cubugu
   CreateRect(PREFIX+"fifo_bg",   x+6, row,   w-12, 10, C'15,20,40', ColorAccent, 1, 200);
   CreateRect(PREFIX+"fifo_fill", x+6, row,   0,    10, ColorAccent, ColorAccent, 0, 220);
   row += 14;
   
   string bidir_labels[] = {"BiDir:", "Volatilite:", "Grid:"};
   for(int i = 0; i < 3; i++) {
      CreateLabel(PREFIX+"bl_"+IntegerToString(i), x+6, row+i*rh, bidir_labels[i], ColorMuted, 7);
   }
   row += 3*rh + 4;
   
   // Alt bar - EA bilgisi
   CreateRect(PREFIX+"footer", x, row, w, 18, ColorHeader, ColorMuted, 1, 200);
   CreateLabel(PREFIX+"footer_txt", x+6, row+3, "EA: v3.8.0 Safety  |  2027-04-21", ColorMuted, 6);
   
   // Sag ust - son guncelleme
   CreateLabel(PREFIX+"lastupdate", x, y-14, "MIA baglaniyor...", ColorMuted, 7);
   
   g_panel_built = true;
}

//+------------------------------------------------------------------+
//  PANEL GUNCELLE - Her timer tick'inde
//+------------------------------------------------------------------+
void UpdatePanel()
{
   if(!g_panel_built) return;
   
   int x = PanelX;
   int y = PanelY;
   int w = PanelWidth;
   int rh = 16;
   
   // Son guncelleme zamani
   string upd_str = (g_last_update > 0) 
      ? "Son: " + TimeToString(g_last_update, TIME_MINUTES|TIME_SECONDS)
      : "MIA baglaniyor...";
   ObjectSetString(0, PREFIX+"lastupdate", OBJPROP_TEXT, upd_str);
   
   // ANA BILGILER degerleri
   int row = y + 26;
   
   SetLabelText(PREFIX+"al_0", x, row+0*rh,  "Versiyon:", "BytamerFX v3.8.0", ColorAccent);
   SetLabelText(PREFIX+"al_1", x, row+1*rh,  "Bakiye:",   "$"+DoubleToString(g_data.balance,2),
                g_data.daily_pnl >= 0 ? ColorBull : ColorBear);
   SetLabelText(PREFIX+"al_2", x, row+2*rh,  "Varlik:",   "$"+DoubleToString(g_data.equity,2), ColorText);
   SetLabelText(PREFIX+"al_3", x, row+3*rh,  "Margin:",
                DoubleToString(g_data.margin_level,0)+"%",
                g_data.margin_level < 300 ? ColorBear : ColorBull);
   SetLabelText(PREFIX+"al_4", x, row+4*rh,  "Sembol:",   g_symbol, ColorAccent);
   SetLabelText(PREFIX+"al_5", x, row+5*rh,  "RSI(14):",
                DoubleToString(g_data.rsi,1), RsiColor(g_data.rsi));
   SetLabelText(PREFIX+"al_6", x, row+6*rh,  "ADX(14):",
                DoubleToString(g_data.adx,1), g_data.adx > 25 ? ColorBull : ColorNeutral);
   
   // Spread - kirmizi ise yuksek uyarisi
   color sp_col = g_data.spread_ok ? ColorText : ColorBear;
   string sp_str = DoubleToString(g_data.spread_pts,0) + " pts";
   if(!g_data.spread_ok) sp_str += " [YUKSEK!]";
   SetLabelText(PREFIX+"al_7", x, row+7*rh,  "Spread:", sp_str, sp_col);
   
   SetLabelText(PREFIX+"al_8", x, row+8*rh,  "ATR(14):",
                DoubleToString(g_data.atr,5), ColorText);
   SetLabelText(PREFIX+"al_9", x, row+9*rh,  "Pozisyon:",
                IntegerToString(g_data.open_positions)+" (SPM:"+IntegerToString(g_data.spm_count)+")",
                ColorText);
   SetLabelText(PREFIX+"al_10", x, row+10*rh, "Trend:", TrendText(g_data.trend),
                TrendColor(g_data.trend));
   
   // Durum tag
   color dur_col = (g_data.durum == "AKTIF") ? ColorBull : ColorMuted;
   SetLabelText(PREFIX+"al_11", x, row+11*rh, "Durum:", g_data.durum, dur_col);
   
   SetLabelText(PREFIX+"al_12", x, row+12*rh, "+DI/-DI:", "-- / --", ColorNeutral);
   
   row += 13*rh + 30; // Sinyal skoru bolumu baslangic offset
   
   // SINYAL SKORU
   int bar_w = w - 12;
   int buy_fill  = (int)(bar_w * g_data.buy_score  / 100.0);
   int sell_fill = (int)(bar_w * g_data.sell_score / 100.0);
   
   ObjectSetInteger(0, PREFIX+"sbar_buy_fill",  OBJPROP_XSIZE, buy_fill);
   ObjectSetInteger(0, PREFIX+"sbar_sell_fill", OBJPROP_XSIZE, sell_fill);
   
   ObjectSetString(0, PREFIX+"sv_buy",  OBJPROP_TEXT, IntegerToString(g_data.buy_score)+"/100");
   ObjectSetString(0, PREFIX+"sv_sell", OBJPROP_TEXT, IntegerToString(g_data.sell_score)+"/100");
   
   // Yon tag
   string yon_txt;
   color  yon_col;
   if(g_data.buy_score > g_data.sell_score && g_data.buy_score > 40) {
      yon_txt = "▲ ALIS ["+IntegerToString(g_data.buy_score)+"]";
      yon_col = ColorBull;
   } else if(g_data.sell_score > g_data.buy_score && g_data.sell_score > 40) {
      yon_txt = "▼ SATIS ["+IntegerToString(g_data.sell_score)+"]";
      yon_col = ColorBear;
   } else {
      yon_txt = "NOTR";
      yon_col = ColorNeutral;
   }
   ObjectSetString(0,  PREFIX+"yon_val", OBJPROP_TEXT, yon_txt);
   ObjectSetInteger(0, PREFIX+"yon_val", OBJPROP_COLOR, yon_col);
   ObjectSetInteger(0, PREFIX+"yon_tag", OBJPROP_BORDER_COLOR, yon_col);
   
   // 7 katman bar
   int layer_vals[] = {g_data.ema_score, g_data.macd_score, g_data.adx_score,
                        g_data.rsi_score, g_data.bb_score, g_data.stoch_score, g_data.atr_score};
   int layer_maxs[] = {20, 20, 15, 15, 15, 10, 5};
   string layer_maxs_s[] = {"20","20","15","15","15","10","5"};
   
   for(int i = 0; i < 7; i++) {
      int fill = (int)((w - 91) * layer_vals[i] / (double)layer_maxs[i]);
      fill = MathMax(0, MathMin(w-91, fill));
      ObjectSetInteger(0, PREFIX+"lb_fill_"+IntegerToString(i), OBJPROP_XSIZE, fill);
      ObjectSetString(0,  PREFIX+"lv_"+IntegerToString(i), OBJPROP_TEXT,
                      IntegerToString(layer_vals[i])+"/"+layer_maxs_s[i]);
   }
   
   // TP satirlari offsetini hesapla
   row += 7*14 + 6 + 26; // katman satirlari + yon + section header
   
   // TP + INDIKTORLER
   double price = SymbolInfoDouble(g_symbol, SYMBOL_BID);
   SetLabelText(PREFIX+"tl_0", x, row+0*rh, "TP1:",
                g_data.tp1 > 0 ? DoubleToString(g_data.tp1, _Digits) : "--", clrGold);
   SetLabelText(PREFIX+"tl_1", x, row+1*rh, "TP2:",
                g_data.tp2 > 0 ? DoubleToString(g_data.tp2, _Digits) : "--", clrGold);
   SetLabelText(PREFIX+"tl_2", x, row+2*rh, "TP3:",
                g_data.tp3 > 0 ? DoubleToString(g_data.tp3, _Digits) : "--", clrGold);
   SetLabelText(PREFIX+"tl_3", x, row+3*rh, "TP Seviye:", "--", ColorText);
   
   string trend_str;
   color  trend_col;
   if(g_data.adx > 35)      { trend_str = "GUCLU";   trend_col = ColorBull; }
   else if(g_data.adx > 20) { trend_str = "ORTA";    trend_col = clrGold; }
   else                      { trend_str = "ZAYIF";   trend_col = ColorMuted; }
   SetLabelText(PREFIX+"tl_4", x, row+4*rh, "Trend Guc:", trend_str, trend_col);
   
   // SAR degerini gosterge handle'indan al
   string sar_str = "--";
   if(g_sar_handle != INVALID_HANDLE) {
      double sar_buf[];
      if(CopyBuffer(g_sar_handle, 0, 0, 1, sar_buf) > 0) {
         sar_str = DoubleToString(sar_buf[0], _Digits);
         bool sar_above = sar_buf[0] > price;
         color sar_col = sar_above ? ColorBear : ColorBull;
         SetLabelText(PREFIX+"tl_5", x, row+5*rh, "SAR:", 
                      sar_str+" "+(sar_above?"▼ ASAGI":"▲ YUKARI"), sar_col);
      }
   } else {
      SetLabelText(PREFIX+"tl_5", x, row+5*rh, "SAR:", sar_str, ColorText);
   }
   
   SetLabelText(PREFIX+"tl_6", x, row+6*rh, "Mom:",
                DoubleToString(g_data.rsi,0)+".00 / "+
                (g_data.rsi > 50 ? "YUKARI" : "ASAGI"), ColorText);
   SetLabelText(PREFIX+"tl_7", x, row+7*rh, "Fear&Greed:",
                IntegerToString(g_data.fg_index)+" ("+g_data.fg_label+")",
                g_data.fg_index > 70 ? ColorBear : g_data.fg_index < 30 ? ColorBull : clrGold);
   SetLabelText(PREFIX+"tl_8", x, row+8*rh, "Seans:", g_data.session, ColorAccent);
   
   row += 9*rh + 30;
   
   // BIDIR-GRID degerleri
   color daily_col = g_data.daily_pnl >= 0 ? ColorBull : ColorBear;
   SetLabelText(PREFIX+"gl_0", x, row+0*rh, "Gunluk:",
                "$"+DoubleToString(g_data.daily_pnl,2), daily_col);
   SetLabelText(PREFIX+"gl_1", x, row+1*rh, "Islemler:", "B:0 / S:0", ColorText);
   SetLabelText(PREFIX+"gl_2", x, row+2*rh, "Bugun:",
                IntegerToString(g_data.open_positions)+" Islem", ColorText);
   SetLabelText(PREFIX+"gl_3", x, row+3*rh, "Ana P/L:",
                "$"+DoubleToString(g_data.main_pnl,2),
                g_data.main_pnl >= 0 ? ColorBull : ColorBear);
   SetLabelText(PREFIX+"gl_4", x, row+4*rh, "BUY/SELL:", "B:0 / S:0", ColorText);
   SetLabelText(PREFIX+"gl_5", x, row+5*rh, "SPM/DCA/HG:",
                IntegerToString(g_data.spm_count)+"/0/0", clrGold);
   SetLabelText(PREFIX+"gl_6", x, row+6*rh, "Kasa:",
                "$"+DoubleToString(g_data.kasa,2)+" ("+IntegerToString(g_data.spm_count)+")",
                ColorBull);
   
   double open_pnl = g_data.main_pnl;
   SetLabelText(PREFIX+"gl_7", x, row+7*rh, "Acik P/L:",
                "$"+DoubleToString(open_pnl,2),
                open_pnl >= 0 ? ColorBull : ColorBear);
   SetLabelText(PREFIX+"gl_8", x, row+8*rh, "FIFO Net:",
                "$"+DoubleToString(g_data.fifo_net,2),
                g_data.fifo_net >= 0 ? ColorBull : ColorBear);
   SetLabelText(PREFIX+"gl_9", x, row+9*rh, "Hedef:", "$5.00", ColorText);
   
   double progress = (g_data.fifo_target > 0) 
      ? MathMin(100.0, g_data.fifo_net / g_data.fifo_target * 100.0) : 0;
   progress = MathMax(0, progress);
   SetLabelText(PREFIX+"gl_10", x, row+10*rh, "Ilerleme:",
                DoubleToString(progress,1)+"%", ColorText);
   
   // FIFO cubugu
   int fifo_fill = (int)((w-12) * progress / 100.0);
   ObjectSetInteger(0, PREFIX+"fifo_fill", OBJPROP_XSIZE, fifo_fill);
   color fifo_col = (progress >= 100) ? ColorBull : ColorAccent;
   ObjectSetInteger(0, PREFIX+"fifo_fill", OBJPROP_COLOR, fifo_col);
   ObjectSetInteger(0, PREFIX+"fifo_fill", OBJPROP_BORDER_COLOR, fifo_col);
   
   row += 11*rh + 18;
   
   // BiDir/Vol/Grid
   color bidir_col = (g_data.durum == "AKTIF") ? ColorBull : clrGold;
   SetLabelText(PREFIX+"bl_0", x, row+0*rh, "BiDir:",
                (g_data.durum == "AKTIF") ? "HAZIR" : "BEKLE", bidir_col);
   SetLabelText(PREFIX+"bl_1", x, row+1*rh, "Volatilite:",
                g_data.adx > 30 ? "YUKSEK" : "NORMAL", ColorText);
   SetLabelText(PREFIX+"bl_2", x, row+2*rh, "Grid:",
                DoubleToString(g_data.atr * 100 / MathMax(0.0001, SymbolInfoDouble(g_symbol,SYMBOL_BID)), 5),
                ColorText);
}

//+------------------------------------------------------------------+
//  GOSTERGE CIZGILERI - BB, SAR, EMA
//+------------------------------------------------------------------+
void DrawIndicatorLines()
{
   // Bollinger Bands
   if(ShowBB && g_bb_handle != INVALID_HANDLE) {
      int bars = 200;
      double bb_upper[], bb_lower[], bb_mid[];
      ArraySetAsSeries(bb_upper, true);
      ArraySetAsSeries(bb_lower, true);
      ArraySetAsSeries(bb_mid,   true);
      
      if(CopyBuffer(g_bb_handle, 1, 0, bars, bb_upper) > 0 &&
         CopyBuffer(g_bb_handle, 2, 0, bars, bb_lower) > 0 &&
         CopyBuffer(g_bb_handle, 0, 0, bars, bb_mid)   > 0) {
         
         // Cizgi nesneleri zaten varsa sil ve yeniden olustur yerine
         // Trend cizgisi olarak birer nokta cizelim
         DrawBufferLine("MIA_BB_UP",  bb_upper, bars, clrDodgerBlue,  1, STYLE_DOT);
         DrawBufferLine("MIA_BB_MID", bb_mid,   bars, clrSteelBlue,   1, STYLE_DOT);
         DrawBufferLine("MIA_BB_LO",  bb_lower, bars, clrDodgerBlue,  1, STYLE_DOT);
      }
   }
   
   // Parabolic SAR - noktalar
   if(ShowSAR && g_sar_handle != INVALID_HANDLE) {
      int bars = 100;
      double sar_buf[];
      ArraySetAsSeries(sar_buf, true);
      if(CopyBuffer(g_sar_handle, 0, 0, bars, sar_buf) > 0) {
         DrawSARDots(sar_buf, bars);
      }
   }
   
   // EMA cizgileri
   if(ShowEMA) {
      int bars = 200;
      if(g_ema8_handle != INVALID_HANDLE) {
         double buf[];
         ArraySetAsSeries(buf, true);
         if(CopyBuffer(g_ema8_handle, 0, 0, bars, buf) > 0)
            DrawBufferLine("MIA_EMA8", buf, bars, clrOrange, 1, STYLE_SOLID);
      }
      if(g_ema21_handle != INVALID_HANDLE) {
         double buf[];
         ArraySetAsSeries(buf, true);
         if(CopyBuffer(g_ema21_handle, 0, 0, bars, buf) > 0)
            DrawBufferLine("MIA_EMA21", buf, bars, clrDodgerBlue, 1, STYLE_SOLID);
      }
      if(g_ema50_handle != INVALID_HANDLE) {
         double buf[];
         ArraySetAsSeries(buf, true);
         if(CopyBuffer(g_ema50_handle, 0, 0, bars, buf) > 0)
            DrawBufferLine("MIA_EMA50", buf, bars, clrMagenta, 2, STYLE_SOLID);
      }
   }
}

//+------------------------------------------------------------------+
//  SAR NOKTALARI
//+------------------------------------------------------------------+
void DrawSARDots(const double &sar[], int bars)
{
   datetime times[];
   double   highs[], lows[];
   ArraySetAsSeries(times, true);
   ArraySetAsSeries(highs, true);
   ArraySetAsSeries(lows,  true);
   
   int copied = CopyTime(_Symbol, PERIOD_M15, 0, bars, times);
   CopyHigh(_Symbol, PERIOD_M15, 0, bars, highs);
   CopyLow(_Symbol,  PERIOD_M15, 0, bars, lows);
   
   for(int i = 0; i < MathMin(bars, copied); i++) {
      string nm = "MIA_SAR_"+IntegerToString(i);
      double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      bool above = sar[i] > (highs[i] + lows[i]) / 2.0;
      
      if(ObjectFind(0, nm) < 0) {
         ObjectCreate(0, nm, OBJ_ARROW, 0, 0, 0);
         ObjectSetInteger(0, nm, OBJPROP_ARROWCODE, 159);  // dolu daire
         ObjectSetInteger(0, nm, OBJPROP_WIDTH, 1);
         ObjectSetInteger(0, nm, OBJPROP_BACK, true);
      }
      ObjectSetInteger(0, nm, OBJPROP_TIME,  times[i]);
      ObjectSetDouble(0,  nm, OBJPROP_PRICE, sar[i]);
      ObjectSetInteger(0, nm, OBJPROP_COLOR, above ? clrRed : clrLime);
   }
}

//+------------------------------------------------------------------+
//  SINYAL OKLARI
//+------------------------------------------------------------------+
void DrawSignalArrows()
{
   // Son alis/satis sinyali okunu goster
   int max_score = MathMax(g_data.buy_score, g_data.sell_score);
   if(max_score < 45) return;
   
   bool is_buy = g_data.buy_score > g_data.sell_score;
   string nm = "MIA_SIGNAL_ARROW";
   
   datetime t = iTime(_Symbol, PERIOD_M15, 1);
   double   p = is_buy 
      ? iLow(_Symbol,  PERIOD_M15, 1) - 5 * _Point
      : iHigh(_Symbol, PERIOD_M15, 1) + 5 * _Point;
   
   if(ObjectFind(0, nm) < 0)
      ObjectCreate(0, nm, OBJ_ARROW, 0, 0, 0);
   
   ObjectSetInteger(0, nm, OBJPROP_TIME,      t);
   ObjectSetDouble(0,  nm, OBJPROP_PRICE,     p);
   ObjectSetInteger(0, nm, OBJPROP_ARROWCODE, is_buy ? 233 : 234);  // yukari/asagi ok
   ObjectSetInteger(0, nm, OBJPROP_COLOR,     is_buy ? clrLime : clrRed);
   ObjectSetInteger(0, nm, OBJPROP_WIDTH,     2);
}

//+------------------------------------------------------------------+
//  YARDIMCI: Buffer'dan cizgi ciz (segment segment)
//+------------------------------------------------------------------+
void DrawBufferLine(string name, const double &buf[], int bars,
                    color clr, int width, ENUM_LINE_STYLE style)
{
   datetime times[];
   ArraySetAsSeries(times, true);
   int copied = CopyTime(_Symbol, PERIOD_M15, 0, bars, times);
   if(copied <= 0) return;
   
   // Her bar icin ayri nokta (trend cizgisi yontemi)
   for(int i = 0; i < MathMin(bars-1, copied-1); i++) {
      string seg = name + "_" + IntegerToString(i);
      if(ObjectFind(0, seg) < 0) {
         ObjectCreate(0, seg, OBJ_TREND, 0, 0, 0, 0, 0);
         ObjectSetInteger(0, seg, OBJPROP_RAY_RIGHT, false);
         ObjectSetInteger(0, seg, OBJPROP_BACK, true);
         ObjectSetInteger(0, seg, OBJPROP_SELECTABLE, false);
      }
      ObjectSetInteger(0, seg, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, seg, OBJPROP_WIDTH, width);
      ObjectSetInteger(0, seg, OBJPROP_STYLE, style);
      ObjectSetInteger(0, seg, OBJPROP_TIME,  times[i+1]);
      ObjectSetDouble(0,  seg, OBJPROP_PRICE, buf[i+1]);
      ObjectSetInteger(0, seg, OBJPROP_TIME,  times[i],   1);
      ObjectSetDouble(0,  seg, OBJPROP_PRICE, buf[i], 1);
   }
}

//+------------------------------------------------------------------+
//  NESNE OLUSTURMA YARDIMCILARI
//+------------------------------------------------------------------+
void CreateRect(string name, int x, int y, int w, int h,
                color bg, color border, int border_w, uchar alpha)
{
   if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE,   x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE,   y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE,       w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE,       h);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR,     bg);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR,border);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, name, OBJPROP_WIDTH,       border_w);
   ObjectSetInteger(0, name, OBJPROP_BACK,        false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE,  false);
   ObjectSetInteger(0, name, OBJPROP_CORNER,      CORNER_LEFT_UPPER);
}

void CreateLabel(string name, int x, int y, string text,
                 color clr, int font_size, bool bold = false)
{
   if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE,  x+4);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE,  y+1);
   ObjectSetString(0,  name, OBJPROP_TEXT,        text);
   ObjectSetInteger(0, name, OBJPROP_COLOR,       clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE,    font_size);
   ObjectSetString(0,  name, OBJPROP_FONT,        bold ? "Arial Bold" : "Courier New");
   ObjectSetInteger(0, name, OBJPROP_CORNER,      CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_BACK,        false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE,  false);
}

void SetLabelText(string lbl_name, int x, int row,
                  string label, string value, color val_color)
{
   // Deger label'ini bul ve guncelle
   string val_name = lbl_name + "_v";
   if(ObjectFind(0, val_name) < 0) {
      CreateLabel(val_name, x + 100, row, value, val_color, 7);
   } else {
      ObjectSetString(0,  val_name, OBJPROP_TEXT,  value);
      ObjectSetInteger(0, val_name, OBJPROP_COLOR, val_color);
      ObjectSetInteger(0, val_name, OBJPROP_YDISTANCE, row+1);
   }
}

void DeleteAllObjects()
{
   int total = ObjectsTotal(0);
   for(int i = total-1; i >= 0; i--) {
      string nm = ObjectName(0, i);
      if(StringFind(nm, PREFIX) == 0 || StringFind(nm, "MIA_BB") == 0 ||
         StringFind(nm, "MIA_SAR") == 0 || StringFind(nm, "MIA_EMA") == 0 ||
         StringFind(nm, "MIA_SIGNAL") == 0)
         ObjectDelete(0, nm);
   }
   g_panel_built = false;
}

//+------------------------------------------------------------------+
//  JSON PARSE YARDIMCILARI
//+------------------------------------------------------------------+
double JsonGetDouble(const string &json, const string key, double def_val)
{
   string search = "\"" + key + "\":";
   int pos = StringFind(json, search);
   if(pos < 0) return def_val;
   
   pos += StringLen(search);
   // Bosluklari atla
   while(pos < StringLen(json) && StringGetCharacter(json, pos) == ' ') pos++;
   
   string val = "";
   for(int i = pos; i < StringLen(json); i++) {
      ushort c = StringGetCharacter(json, i);
      if(c == ',' || c == '}' || c == ']') break;
      val += ShortToString(c);
   }
   StringTrimRight(val);
   StringTrimLeft(val);
   if(val == "true")  return 1.0;
   if(val == "false") return 0.0;
   return StringToDouble(val);
}

string JsonGetString(const string &json, const string key, const string def_val)
{
   string search = "\"" + key + "\":\"";
   int pos = StringFind(json, search);
   if(pos < 0) return def_val;
   
   pos += StringLen(search);
   string val = "";
   for(int i = pos; i < StringLen(json); i++) {
      ushort c = StringGetCharacter(json, i);
      if(c == '"') break;
      val += ShortToString(c);
   }
   return val;
}

//+------------------------------------------------------------------+
//  YARDIMCI FONKSIYONLAR
//+------------------------------------------------------------------+
color RsiColor(double rsi)
{
   if(rsi > 70) return ColorBear;
   if(rsi < 30) return ColorBull;
   if(rsi > 50) return clrGold;
   return ColorAccent;
}

string TrendText(string trend)
{
   if(trend == "STRONG_BULL") return "▲▲ YUKARI (BUY)";
   if(trend == "BULL")        return "▲ YUKARI (BUY)";
   if(trend == "NEUTRAL")     return "→ YATAY";
   if(trend == "BEAR")        return "▼ ASAGI (SELL)";
   if(trend == "STRONG_BEAR") return "▼▼ ASAGI (SELL)";
   return trend;
}

color TrendColor(string trend)
{
   if(StringFind(trend, "BULL") >= 0)   return ColorBull;
   if(StringFind(trend, "BEAR") >= 0)   return ColorBear;
   return ColorNeutral;
}
//+------------------------------------------------------------------+
