//+------------------------------------------------------------------+
//|                                             ChartDashboard.mqh   |
//|                              Copyright 2026, By T@MER            |
//|                              https://www.bytamer.com             |
//+------------------------------------------------------------------+
//| BytamerFX v1.2.0 - 4 Panel Chart Dashboard + Chart Overlay       |
//| Real-time EA information display with indicator overlays          |
//| Panels: ANA BILGILER, SINYAL SKOR, TP+INDIKATOR, SPM+FIFO       |
//| Overlay: Bollinger Bands, Parabolic SAR, Momentum                |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, By T@MER"
#property link      "https://www.bytamer.com"
#property strict

#ifndef CHART_DASHBOARD_MQH
#define CHART_DASHBOARD_MQH

#include "Config.mqh"
#include "SignalEngine.mqh"
#include "PositionManager.mqh"
#include "SpreadFilter.mqh"

//+------------------------------------------------------------------+
//| Color Constants                                                   |
//+------------------------------------------------------------------+
#define CLR_PANEL_BG        C'25,25,35'
#define CLR_PANEL_BORDER    C'60,60,80'
#define CLR_HEADER          C'0,200,255'
#define CLR_LABEL           C'180,180,200'
#define CLR_VALUE           C'255,255,255'
#define CLR_POSITIVE        C'0,200,100'
#define CLR_NEGATIVE        C'255,60,60'
#define CLR_WARNING         C'255,200,0'
#define CLR_PROGRESS_FILL   C'0,150,255'
#define CLR_PROGRESS_BG     C'40,40,55'
#define CLR_BUY_DIR         C'0,200,100'
#define CLR_SELL_DIR        C'255,60,60'

//+------------------------------------------------------------------+
//| Layout Constants                                                  |
//+------------------------------------------------------------------+
#define DASH_FONT           "Consolas"
#define DASH_FONT_SIZE      9
#define DASH_HEADER_SIZE    10
#define DASH_PANEL_W        300
#define DASH_PANEL_X        10
#define DASH_LINE_H         17
#define DASH_INDENT         10
#define DASH_VAL_X          155

//+------------------------------------------------------------------+
//| Indicator Overlay Constants                                       |
//+------------------------------------------------------------------+
#define IND_OVERLAY_BARS    50
#define IND_OVERLAY_COOLDOWN 2

//+------------------------------------------------------------------+
//| CChartDashboard                                                   |
//+------------------------------------------------------------------+
class CChartDashboard
{
private:
   //--- Data source pointers
   CSignalEngine*    m_engine;
   CPositionManager* m_posMgr;
   CSpreadFilter*    m_spread;
   string            m_symbol;
   ENUM_SYMBOL_CATEGORY m_category;
   bool              m_enabled;
   long              m_chartId;
   int               m_subWindow;

   //--- Layout
   int m_panelX, m_panelY, m_panelW, m_panelH;

   //--- Indicator handles (chart overlay)
   int               m_hSAR;
   int               m_hMomentum;
   int               m_hBB;

   //--- Overlay throttling
   datetime          m_lastOverlayDraw;

   //=================================================================
   // HELPER: Create background panel
   //=================================================================
   void CreatePanel(string name, int x, int y, int w, int h)
   {
      string objName = "BTFX_" + name;
      ObjectCreate(m_chartId, objName, OBJ_RECTANGLE_LABEL, m_subWindow, 0, 0);
      ObjectSetInteger(m_chartId, objName, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(m_chartId, objName, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(m_chartId, objName, OBJPROP_XSIZE, w);
      ObjectSetInteger(m_chartId, objName, OBJPROP_YSIZE, h);
      ObjectSetInteger(m_chartId, objName, OBJPROP_BGCOLOR, CLR_PANEL_BG);
      ObjectSetInteger(m_chartId, objName, OBJPROP_BORDER_COLOR, CLR_PANEL_BORDER);
      ObjectSetInteger(m_chartId, objName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(m_chartId, objName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(m_chartId, objName, OBJPROP_BACK, false);
      ObjectSetInteger(m_chartId, objName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(m_chartId, objName, OBJPROP_HIDDEN, true);
   }

   //=================================================================
   // HELPER: Create text label
   //=================================================================
   void CreateLabel(string name, int x, int y, string text, color clr,
                    int fontSize = DASH_FONT_SIZE, string fontName = DASH_FONT)
   {
      string objName = "BTFX_" + name;
      ObjectCreate(m_chartId, objName, OBJ_LABEL, m_subWindow, 0, 0);
      ObjectSetInteger(m_chartId, objName, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(m_chartId, objName, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(m_chartId, objName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetString(m_chartId, objName, OBJPROP_TEXT, text);
      ObjectSetString(m_chartId, objName, OBJPROP_FONT, fontName);
      ObjectSetInteger(m_chartId, objName, OBJPROP_FONTSIZE, fontSize);
      ObjectSetInteger(m_chartId, objName, OBJPROP_COLOR, clr);
      ObjectSetInteger(m_chartId, objName, OBJPROP_BACK, false);
      ObjectSetInteger(m_chartId, objName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(m_chartId, objName, OBJPROP_HIDDEN, true);
   }

   //=================================================================
   // HELPER: Create progress bar (bg + fill)
   //=================================================================
   void CreateProgressBar(string name, int x, int y, int w, int h,
                          double percent, color fillClr, color bgClr)
   {
      //--- Background bar
      string bgName = "BTFX_" + name + "_bg";
      ObjectCreate(m_chartId, bgName, OBJ_RECTANGLE_LABEL, m_subWindow, 0, 0);
      ObjectSetInteger(m_chartId, bgName, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(m_chartId, bgName, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(m_chartId, bgName, OBJPROP_XSIZE, w);
      ObjectSetInteger(m_chartId, bgName, OBJPROP_YSIZE, h);
      ObjectSetInteger(m_chartId, bgName, OBJPROP_BGCOLOR, bgClr);
      ObjectSetInteger(m_chartId, bgName, OBJPROP_BORDER_COLOR, bgClr);
      ObjectSetInteger(m_chartId, bgName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(m_chartId, bgName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(m_chartId, bgName, OBJPROP_BACK, false);
      ObjectSetInteger(m_chartId, bgName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(m_chartId, bgName, OBJPROP_HIDDEN, true);

      //--- Fill bar
      double pct = MathMax(0.0, MathMin(percent, 100.0));
      int fillW = (int)MathRound(w * pct / 100.0);
      if(fillW < 1) fillW = 1;

      string fillName = "BTFX_" + name + "_fill";
      ObjectCreate(m_chartId, fillName, OBJ_RECTANGLE_LABEL, m_subWindow, 0, 0);
      ObjectSetInteger(m_chartId, fillName, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(m_chartId, fillName, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(m_chartId, fillName, OBJPROP_XSIZE, fillW);
      ObjectSetInteger(m_chartId, fillName, OBJPROP_YSIZE, h);
      ObjectSetInteger(m_chartId, fillName, OBJPROP_BGCOLOR, fillClr);
      ObjectSetInteger(m_chartId, fillName, OBJPROP_BORDER_COLOR, fillClr);
      ObjectSetInteger(m_chartId, fillName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(m_chartId, fillName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(m_chartId, fillName, OBJPROP_BACK, false);
      ObjectSetInteger(m_chartId, fillName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(m_chartId, fillName, OBJPROP_HIDDEN, true);
   }

   //=================================================================
   // HELPER: Update label text and color
   //=================================================================
   void UpdateLabel(string name, string text, color clr)
   {
      string objName = "BTFX_" + name;
      ObjectSetString(m_chartId, objName, OBJPROP_TEXT, text);
      ObjectSetInteger(m_chartId, objName, OBJPROP_COLOR, clr);
   }

   //=================================================================
   // HELPER: Update progress bar fill
   //=================================================================
   void UpdateProgressBar(string name, double percent, color fillClr)
   {
      double pct = MathMax(0.0, MathMin(percent, 100.0));
      string bgName = "BTFX_" + name + "_bg";
      int totalW = (int)ObjectGetInteger(m_chartId, bgName, OBJPROP_XSIZE);
      if(totalW <= 0) totalW = 120;

      int fillW = (int)MathRound(totalW * pct / 100.0);
      if(fillW < 1) fillW = 1;

      string fillName = "BTFX_" + name + "_fill";
      ObjectSetInteger(m_chartId, fillName, OBJPROP_XSIZE, fillW);
      ObjectSetInteger(m_chartId, fillName, OBJPROP_BGCOLOR, fillClr);
      ObjectSetInteger(m_chartId, fillName, OBJPROP_BORDER_COLOR, fillClr);
   }

   //=================================================================
   // HELPER: Color by sign
   //=================================================================
   color ColorBySign(double value)
   {
      if(value > 0.0) return CLR_POSITIVE;
      if(value < 0.0) return CLR_NEGATIVE;
      return CLR_VALUE;
   }

   //=================================================================
   // HELPER: Category name
   //=================================================================
   string GetCategoryName(ENUM_SYMBOL_CATEGORY cat)
   {
      switch(cat)
      {
         case CAT_FOREX:   return "FOREX";
         case CAT_METAL:   return "METAL";
         case CAT_CRYPTO:  return "CRYPTO";
         case CAT_INDICES: return "INDEX";
         case CAT_STOCKS:  return "STOCK";
         case CAT_ENERGY:  return "ENERGY";
         default:          return "UNKNOWN";
      }
   }

   //=================================================================
   // HELPER: RSI color
   //=================================================================
   color GetRSIColor(double rsi)
   {
      if(rsi < 30.0 || rsi > 70.0) return CLR_WARNING;
      return CLR_VALUE;
   }

   //=================================================================
   // HELPER: ADX color
   //=================================================================
   color GetADXColor(double adx)
   {
      if(adx > 30.0)  return CLR_POSITIVE;
      if(adx >= 20.0) return CLR_WARNING;
      return CLR_NEGATIVE;
   }

   //=================================================================
   // HELPER: Trend strength string
   //=================================================================
   string GetTrendStr(ENUM_TREND_STRENGTH ts)
   {
      switch(ts)
      {
         case TREND_STRONG:   return "GUCLU";
         case TREND_MODERATE: return "ORTA";
         default:             return "ZAYIF";
      }
   }

   //=================================================================
   // HELPER: Trend strength color
   //=================================================================
   color GetTrendColor(ENUM_TREND_STRENGTH ts)
   {
      switch(ts)
      {
         case TREND_STRONG:   return CLR_POSITIVE;
         case TREND_MODERATE: return CLR_WARNING;
         default:             return CLR_NEGATIVE;
      }
   }

   //=================================================================
   // PANEL 1 CREATION: ANA BILGILER  (y=30, h=285)
   //=================================================================
   void CreatePanel1(int baseX, int baseY)
   {
      int pw = DASH_PANEL_W;
      int ph = 285;
      CreatePanel("P1", baseX, baseY, pw, ph);

      int x  = baseX + DASH_INDENT;
      int vx = baseX + DASH_VAL_X;
      int y  = baseY + 6;

      //--- Header
      CreateLabel("P1_HDR", x, y, "ANA BILGILER", CLR_HEADER, DASH_HEADER_SIZE);
      y += DASH_LINE_H + 2;

      //--- Row 1: Versiyon
      CreateLabel("P1_VER_L", x, y, "Versiyon:", CLR_LABEL);
      CreateLabel("P1_VER_V", vx, y, EA_VERSION_FULL, CLR_HEADER);
      y += DASH_LINE_H;

      //--- Row 2: Bakiye
      CreateLabel("P1_BAL_L", x, y, "Bakiye:", CLR_LABEL);
      CreateLabel("P1_BAL_V", vx, y, "$0.00", CLR_VALUE);
      y += DASH_LINE_H;

      //--- Row 3: Varlik
      CreateLabel("P1_EQ_L", x, y, "Varlik:", CLR_LABEL);
      CreateLabel("P1_EQ_V", vx, y, "$0.00", CLR_VALUE);
      y += DASH_LINE_H;

      //--- Row 4: Marjin
      CreateLabel("P1_MRG_L", x, y, "Marjin:", CLR_LABEL);
      CreateLabel("P1_MRG_V", vx, y, "0.00%", CLR_VALUE);
      y += DASH_LINE_H;

      //--- Row 5: Sembol
      CreateLabel("P1_SYM_L", x, y, "Sembol:", CLR_LABEL);
      CreateLabel("P1_SYM_V", vx, y, m_symbol, CLR_VALUE);
      y += DASH_LINE_H;

      //--- Row 6: RSI(14)
      CreateLabel("P1_RSI_L", x, y, "RSI(14):", CLR_LABEL);
      CreateLabel("P1_RSI_V", vx, y, "0.00", CLR_VALUE);
      y += DASH_LINE_H;

      //--- Row 7: ADX(14)
      CreateLabel("P1_ADX_L", x, y, "ADX(14):", CLR_LABEL);
      CreateLabel("P1_ADX_V", vx, y, "0.00", CLR_VALUE);
      y += DASH_LINE_H;

      //--- Row 8: ATR(14)
      CreateLabel("P1_ATR_L", x, y, "ATR(14):", CLR_LABEL);
      CreateLabel("P1_ATR_V", vx, y, "0.00000", CLR_VALUE);
      y += DASH_LINE_H;

      //--- Row 9: Spread
      CreateLabel("P1_SPR_L", x, y, "Spread:", CLR_LABEL);
      CreateLabel("P1_SPR_V", vx, y, "0.0 / 0.0", CLR_VALUE);
      y += DASH_LINE_H;

      //--- Row 10: Pozisyon
      CreateLabel("P1_POS_L", x, y, "Pozisyon:", CLR_LABEL);
      CreateLabel("P1_POS_V", vx, y, "0 (SPM:0)", CLR_VALUE);
      y += DASH_LINE_H;

      //--- Row 11: Trend
      CreateLabel("P1_TRD_L", x, y, "Trend:", CLR_LABEL);
      CreateLabel("P1_TRD_V", vx, y, "---", CLR_LABEL);
      y += DASH_LINE_H;

      //--- Row 12: Durum
      CreateLabel("P1_STS_L", x, y, "Durum:", CLR_LABEL);
      CreateLabel("P1_STS_V", vx, y, "Aktif", CLR_POSITIVE);
      y += DASH_LINE_H;

      //--- Row 13: +DI / -DI
      CreateLabel("P1_DI_L", x, y, "+DI / -DI:", CLR_LABEL);
      CreateLabel("P1_DI_V", vx, y, "0.0 / 0.0", CLR_VALUE);
   }

   //=================================================================
   // PANEL 2 CREATION: SINYAL SKOR  (y=325, h=290)
   //=================================================================
   void CreatePanel2(int baseX, int baseY)
   {
      int pw = DASH_PANEL_W;
      int ph = 290;
      CreatePanel("P2", baseX, baseY, pw, ph);

      int x    = baseX + DASH_INDENT;
      int vx   = baseX + DASH_VAL_X;
      int barX = baseX + DASH_INDENT;
      int barW = pw - 2 * DASH_INDENT;
      int y    = baseY + 6;

      //--- Header
      CreateLabel("P2_HDR", x, y, "SINYAL SKOR", CLR_HEADER, DASH_HEADER_SIZE);
      y += DASH_LINE_H + 2;

      //--- Buy Score
      CreateLabel("P2_BUY_L", x, y, "ALIS Skor:", CLR_LABEL);
      CreateLabel("P2_BUY_V", vx, y, "0/100", CLR_BUY_DIR);
      y += DASH_LINE_H;
      CreateProgressBar("P2_BUY_BAR", barX, y, barW, 6, 0.0, CLR_BUY_DIR, CLR_PROGRESS_BG);
      y += 10;

      //--- Sell Score
      CreateLabel("P2_SELL_L", x, y, "SATIS Skor:", CLR_LABEL);
      CreateLabel("P2_SELL_V", vx, y, "0/100", CLR_SELL_DIR);
      y += DASH_LINE_H;
      CreateProgressBar("P2_SELL_BAR", barX, y, barW, 6, 0.0, CLR_SELL_DIR, CLR_PROGRESS_BG);
      y += 12;

      //--- Dominant Direction
      CreateLabel("P2_DIR_L", x, y, "Yon:", CLR_LABEL);
      CreateLabel("P2_DIR_V", vx, y, "---", CLR_LABEL);
      y += DASH_LINE_H + 2;

      //--- Layer 1: EMA Trend (0/20)
      CreateLabel("P2_EMA_L", x, y, "EMA Trend:", CLR_LABEL);
      CreateLabel("P2_EMA_V", vx, y, "0/20", CLR_VALUE);
      y += DASH_LINE_H;
      CreateProgressBar("P2_EMA_BAR", barX, y, barW, 4, 0.0, CLR_PROGRESS_FILL, CLR_PROGRESS_BG);
      y += 8;

      //--- Layer 2: MACD Momentum (0/20)
      CreateLabel("P2_MACD_L", x, y, "MACD Mom.:", CLR_LABEL);
      CreateLabel("P2_MACD_V", vx, y, "0/20", CLR_VALUE);
      y += DASH_LINE_H;
      CreateProgressBar("P2_MACD_BAR", barX, y, barW, 4, 0.0, CLR_PROGRESS_FILL, CLR_PROGRESS_BG);
      y += 8;

      //--- Layer 3: ADX Strength (0/15)
      CreateLabel("P2_ADXS_L", x, y, "ADX Guc:", CLR_LABEL);
      CreateLabel("P2_ADXS_V", vx, y, "0/15", CLR_VALUE);
      y += DASH_LINE_H;
      CreateProgressBar("P2_ADXS_BAR", barX, y, barW, 4, 0.0, CLR_PROGRESS_FILL, CLR_PROGRESS_BG);
      y += 8;

      //--- Layer 4: RSI Level (0/15)
      CreateLabel("P2_RSIL_L", x, y, "RSI Svye:", CLR_LABEL);
      CreateLabel("P2_RSIL_V", vx, y, "0/15", CLR_VALUE);
      y += DASH_LINE_H;
      CreateProgressBar("P2_RSIL_BAR", barX, y, barW, 4, 0.0, CLR_PROGRESS_FILL, CLR_PROGRESS_BG);
      y += 8;

      //--- Layer 5: BB Position (0/15)
      CreateLabel("P2_BB_L", x, y, "BB Pozisyn:", CLR_LABEL);
      CreateLabel("P2_BB_V", vx, y, "0/15", CLR_VALUE);
      y += DASH_LINE_H;
      CreateProgressBar("P2_BB_BAR", barX, y, barW, 4, 0.0, CLR_PROGRESS_FILL, CLR_PROGRESS_BG);
      y += 8;

      //--- Layer 6: Stoch Signal (0/10)
      CreateLabel("P2_STCH_L", x, y, "Stoch Sny:", CLR_LABEL);
      CreateLabel("P2_STCH_V", vx, y, "0/10", CLR_VALUE);
      y += DASH_LINE_H;
      CreateProgressBar("P2_STCH_BAR", barX, y, barW, 4, 0.0, CLR_PROGRESS_FILL, CLR_PROGRESS_BG);
      y += 8;

      //--- Layer 7: ATR Volatility (0/5)
      CreateLabel("P2_ATRV_L", x, y, "ATR Volat:", CLR_LABEL);
      CreateLabel("P2_ATRV_V", vx, y, "0/5", CLR_VALUE);
      y += DASH_LINE_H;
      CreateProgressBar("P2_ATRV_BAR", barX, y, barW, 4, 0.0, CLR_PROGRESS_FILL, CLR_PROGRESS_BG);
   }

   //=================================================================
   // PANEL 3 CREATION: TP HEDEFLERI + INDIKATORLER  (y=625, h=165)
   //=================================================================
   void CreatePanel3(int baseX, int baseY)
   {
      int pw = DASH_PANEL_W;
      int ph = 165;
      CreatePanel("P3", baseX, baseY, pw, ph);

      int x  = baseX + DASH_INDENT;
      int vx = baseX + DASH_VAL_X;
      int y  = baseY + 6;

      //--- Header
      CreateLabel("P3_HDR", x, y, "TP + INDIKATORLER", CLR_HEADER, DASH_HEADER_SIZE);
      y += DASH_LINE_H + 2;

      //--- TP1
      CreateLabel("P3_TP1_L", x, y, "TP1:", CLR_LABEL);
      CreateLabel("P3_TP1_V", vx, y, "---", CLR_VALUE);
      y += DASH_LINE_H;

      //--- TP2
      CreateLabel("P3_TP2_L", x, y, "TP2:", CLR_LABEL);
      CreateLabel("P3_TP2_V", vx, y, "---", CLR_VALUE);
      y += DASH_LINE_H;

      //--- TP3
      CreateLabel("P3_TP3_L", x, y, "TP3:", CLR_LABEL);
      CreateLabel("P3_TP3_V", vx, y, "---", CLR_VALUE);
      y += DASH_LINE_H;

      //--- TP Level
      CreateLabel("P3_LVL_L", x, y, "TP Seviye:", CLR_LABEL);
      CreateLabel("P3_LVL_V", vx, y, "---", CLR_VALUE);
      y += DASH_LINE_H;

      //--- Trend Strength
      CreateLabel("P3_TST_L", x, y, "Trend Guc:", CLR_LABEL);
      CreateLabel("P3_TST_V", vx, y, "---", CLR_LABEL);
      y += DASH_LINE_H;

      //--- Parabolic SAR value + direction
      CreateLabel("P3_SAR_L", x, y, "SAR:", CLR_LABEL);
      CreateLabel("P3_SAR_V", vx, y, "---", CLR_VALUE);
      y += DASH_LINE_H;

      //--- Momentum value + direction
      CreateLabel("P3_MOM_L", x, y, "Mom:", CLR_LABEL);
      CreateLabel("P3_MOM_V", vx, y, "---", CLR_VALUE);
      y += DASH_LINE_H;

      //--- BB Squeeze status
      CreateLabel("P3_BSQ_L", x, y, "BB:", CLR_LABEL);
      CreateLabel("P3_BSQ_V", vx, y, "---", CLR_VALUE);
   }

   //=================================================================
   // PANEL 4 CREATION: SPM + FIFO  (y=800, h=195)
   //=================================================================
   void CreatePanel4(int baseX, int baseY)
   {
      int pw = DASH_PANEL_W;
      int ph = 195;
      CreatePanel("P4", baseX, baseY, pw, ph);

      int x    = baseX + DASH_INDENT;
      int vx   = baseX + DASH_VAL_X;
      int barX = baseX + DASH_INDENT;
      int barW = pw - 2 * DASH_INDENT;
      int y    = baseY + 6;

      //--- Header
      CreateLabel("P4_HDR", x, y, "SPM + FIFO", CLR_HEADER, DASH_HEADER_SIZE);
      y += DASH_LINE_H + 2;

      //--- Main P/L
      CreateLabel("P4_MAIN_L", x, y, "Ana P/L:", CLR_LABEL);
      CreateLabel("P4_MAIN_V", vx, y, "$0.00", CLR_VALUE);
      y += DASH_LINE_H;

      //--- Active SPM
      CreateLabel("P4_ASPM_L", x, y, "Aktif SPM:", CLR_LABEL);
      CreateLabel("P4_ASPM_V", vx, y, "0 / Katman:0", CLR_VALUE);
      y += DASH_LINE_H;

      //--- Closed SPM Profit
      CreateLabel("P4_CSPM_L", x, y, "SPM Kapal.:", CLR_LABEL);
      CreateLabel("P4_CSPM_V", vx, y, "$0.00", CLR_VALUE);
      y += DASH_LINE_H;

      //--- Open SPM Profit
      CreateLabel("P4_OSPM_L", x, y, "SPM Acik:", CLR_LABEL);
      CreateLabel("P4_OSPM_V", vx, y, "$0.00", CLR_VALUE);
      y += DASH_LINE_H;

      //--- FIFO Net
      CreateLabel("P4_NET_L", x, y, "FIFO Net:", CLR_LABEL);
      CreateLabel("P4_NET_V", vx, y, "$0.00", CLR_VALUE);
      y += DASH_LINE_H;

      //--- Target
      CreateLabel("P4_TGT_L", x, y, "Hedef:", CLR_LABEL);
      CreateLabel("P4_TGT_V", vx, y, "$0.00", CLR_VALUE);
      y += DASH_LINE_H;

      //--- Progress percentage
      CreateLabel("P4_PCT_L", x, y, "Ilerleme:", CLR_LABEL);
      CreateLabel("P4_PCT_V", vx, y, "0.0%", CLR_VALUE);
      y += DASH_LINE_H;

      //--- Progress bar
      CreateProgressBar("P4_FIFO_BAR", barX, y, barW, 8, 0.0, CLR_PROGRESS_FILL, CLR_PROGRESS_BG);
   }

   //=================================================================
   // PANEL 1 UPDATE: ANA BILGILER
   //=================================================================
   void UpdatePanel1()
   {
      //--- Account info
      double balance   = AccountInfoDouble(ACCOUNT_BALANCE);
      double equity    = AccountInfoDouble(ACCOUNT_EQUITY);
      double marginLvl = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);

      //--- Balance
      color balClr = (balance < 50.0) ? CLR_WARNING : CLR_VALUE;
      UpdateLabel("P1_BAL_V", StringFormat("$%.2f", balance), balClr);

      //--- Equity
      color eqClr = (equity < balance) ? CLR_NEGATIVE : CLR_POSITIVE;
      UpdateLabel("P1_EQ_V", StringFormat("$%.2f", equity), eqClr);

      //--- Margin level
      color mrgClr = CLR_VALUE;
      if(marginLvl > 0.0 && marginLvl < 200.0)
         mrgClr = CLR_NEGATIVE;
      else if(marginLvl > 0.0 && marginLvl < 500.0)
         mrgClr = CLR_WARNING;
      string mrgText = (marginLvl > 0.0) ? StringFormat("%.1f%%", marginLvl) : "---";
      UpdateLabel("P1_MRG_V", mrgText, mrgClr);

      //--- Symbol + category
      UpdateLabel("P1_SYM_V", StringFormat("%s [%s]", m_symbol, GetCategoryName(m_category)), CLR_VALUE);

      //--- Indicators from signal engine
      if(m_engine != NULL)
      {
         double rsi    = m_engine.GetRSI();
         double adx    = m_engine.GetADX();
         double atr    = m_engine.GetATR();
         double plusDI  = m_engine.GetPlusDI();
         double minusDI = m_engine.GetMinusDI();

         UpdateLabel("P1_RSI_V", StringFormat("%.2f", rsi), GetRSIColor(rsi));
         UpdateLabel("P1_ADX_V", StringFormat("%.2f", adx), GetADXColor(adx));
         UpdateLabel("P1_ATR_V", StringFormat("%.5f", atr), CLR_VALUE);

         //--- DI
         color diClr = (plusDI > minusDI) ? CLR_BUY_DIR : CLR_SELL_DIR;
         UpdateLabel("P1_DI_V", StringFormat("%.1f / %.1f", plusDI, minusDI), diClr);

         //--- Trend direction
         ENUM_SIGNAL_DIR trend = m_engine.GetCurrentTrend();
         if(trend == SIGNAL_BUY)
            UpdateLabel("P1_TRD_V", ">> YUKARI (BUY)", CLR_BUY_DIR);
         else if(trend == SIGNAL_SELL)
            UpdateLabel("P1_TRD_V", "<< ASAGI (SELL)", CLR_SELL_DIR);
         else
            UpdateLabel("P1_TRD_V", "-- YATAY --", CLR_LABEL);
      }

      //--- Spread
      if(m_spread != NULL)
      {
         double curSpread = m_spread.GetCurrentSpread();
         double maxSpread = m_spread.GetMaxAllowed();
         color sprClr = (curSpread <= maxSpread) ? CLR_POSITIVE : CLR_NEGATIVE;
         UpdateLabel("P1_SPR_V", StringFormat("%.1f / %.1f", curSpread, maxSpread), sprClr);
      }

      //--- Position info
      if(m_posMgr != NULL)
      {
         bool hasPos  = m_posMgr.HasPosition();
         int spmCount = m_posMgr.GetSPMCount();
         int totalPos = hasPos ? (1 + spmCount) : 0;
         UpdateLabel("P1_POS_V", StringFormat("%d (SPM:%d)", totalPos, spmCount), CLR_VALUE);

         //--- Trading status
         bool paused = m_posMgr.IsTradingPaused();
         if(paused)
            UpdateLabel("P1_STS_V", "DURDURULDU", CLR_NEGATIVE);
         else
            UpdateLabel("P1_STS_V", "Aktif", CLR_POSITIVE);
      }
   }

   //=================================================================
   // PANEL 2 UPDATE: SINYAL SKOR
   //=================================================================
   void UpdatePanel2()
   {
      if(m_engine == NULL)
         return;

      //--- Refresh breakdown data
      m_engine.UpdateBreakdown();

      ScoreBreakdown buyBD  = m_engine.GetBuyBreakdown();
      ScoreBreakdown sellBD = m_engine.GetSellBreakdown();

      //--- Buy score
      UpdateLabel("P2_BUY_V", StringFormat("%d/100", buyBD.totalScore), CLR_BUY_DIR);
      double buyPct = (buyBD.totalScore / 100.0) * 100.0;
      UpdateProgressBar("P2_BUY_BAR", buyPct, CLR_BUY_DIR);

      //--- Sell score
      UpdateLabel("P2_SELL_V", StringFormat("%d/100", sellBD.totalScore), CLR_SELL_DIR);
      double sellPct = (sellBD.totalScore / 100.0) * 100.0;
      UpdateProgressBar("P2_SELL_BAR", sellPct, CLR_SELL_DIR);

      //--- Dominant direction
      bool isBuyDom = (buyBD.totalScore >= sellBD.totalScore);
      if(buyBD.totalScore == 0 && sellBD.totalScore == 0)
         UpdateLabel("P2_DIR_V", "--- BELIRSIZ ---", CLR_LABEL);
      else if(isBuyDom)
         UpdateLabel("P2_DIR_V", StringFormat(">> ALIS [%d]", buyBD.totalScore), CLR_BUY_DIR);
      else
         UpdateLabel("P2_DIR_V", StringFormat("<< SATIS [%d]", sellBD.totalScore), CLR_SELL_DIR);

      //--- Use dominant breakdown for layer display
      ScoreBreakdown bd;
      color layerClr;
      if(isBuyDom)
      {
         bd = buyBD;
         layerClr = CLR_BUY_DIR;
      }
      else
      {
         bd = sellBD;
         layerClr = CLR_SELL_DIR;
      }

      color clrInactive    = CLR_LABEL;
      color clrBarInactive = CLR_PROGRESS_BG;

      //--- EMA Trend: max 20
      color emaClr    = (bd.emaTrend > 0) ? layerClr : clrInactive;
      color emaBarClr = (bd.emaTrend > 0) ? layerClr : clrBarInactive;
      UpdateLabel("P2_EMA_V", StringFormat("%d/20", bd.emaTrend), emaClr);
      UpdateProgressBar("P2_EMA_BAR", (bd.emaTrend / 20.0) * 100.0, emaBarClr);

      //--- MACD Momentum: max 20
      color macdClr    = (bd.macdMomentum > 0) ? layerClr : clrInactive;
      color macdBarClr = (bd.macdMomentum > 0) ? layerClr : clrBarInactive;
      UpdateLabel("P2_MACD_V", StringFormat("%d/20", bd.macdMomentum), macdClr);
      UpdateProgressBar("P2_MACD_BAR", (bd.macdMomentum / 20.0) * 100.0, macdBarClr);

      //--- ADX Strength: max 15
      color adxsClr    = (bd.adxStrength > 0) ? layerClr : clrInactive;
      color adxsBarClr = (bd.adxStrength > 0) ? layerClr : clrBarInactive;
      UpdateLabel("P2_ADXS_V", StringFormat("%d/15", bd.adxStrength), adxsClr);
      UpdateProgressBar("P2_ADXS_BAR", (bd.adxStrength / 15.0) * 100.0, adxsBarClr);

      //--- RSI Level: max 15
      color rsilClr    = (bd.rsiLevel > 0) ? layerClr : clrInactive;
      color rsilBarClr = (bd.rsiLevel > 0) ? layerClr : clrBarInactive;
      UpdateLabel("P2_RSIL_V", StringFormat("%d/15", bd.rsiLevel), rsilClr);
      UpdateProgressBar("P2_RSIL_BAR", (bd.rsiLevel / 15.0) * 100.0, rsilBarClr);

      //--- BB Position: max 15
      color bbClr    = (bd.bbPosition > 0) ? layerClr : clrInactive;
      color bbBarClr = (bd.bbPosition > 0) ? layerClr : clrBarInactive;
      UpdateLabel("P2_BB_V", StringFormat("%d/15", bd.bbPosition), bbClr);
      UpdateProgressBar("P2_BB_BAR", (bd.bbPosition / 15.0) * 100.0, bbBarClr);

      //--- Stoch Signal: max 10
      color stchClr    = (bd.stochSignal > 0) ? layerClr : clrInactive;
      color stchBarClr = (bd.stochSignal > 0) ? layerClr : clrBarInactive;
      UpdateLabel("P2_STCH_V", StringFormat("%d/10", bd.stochSignal), stchClr);
      UpdateProgressBar("P2_STCH_BAR", (bd.stochSignal / 10.0) * 100.0, stchBarClr);

      //--- ATR Volatility: max 5
      color atrvClr    = (bd.atrVolatility > 0) ? layerClr : clrInactive;
      color atrvBarClr = (bd.atrVolatility > 0) ? layerClr : clrBarInactive;
      UpdateLabel("P2_ATRV_V", StringFormat("%d/5", bd.atrVolatility), atrvClr);
      UpdateProgressBar("P2_ATRV_BAR", (bd.atrVolatility / 5.0) * 100.0, atrvBarClr);
   }

   //=================================================================
   // PANEL 3 UPDATE: TP HEDEFLERI + INDIKATORLER
   //=================================================================
   void UpdatePanel3()
   {
      if(m_posMgr == NULL)
         return;

      TPLevelInfo tp = m_posMgr.GetTPInfo();
      int digits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);

      //--- TP1
      string tp1Status;
      color  tp1Clr;
      if(tp.tp1Hit) { tp1Status = " [OK]"; tp1Clr = CLR_POSITIVE; }
      else          { tp1Status = " [-]";  tp1Clr = CLR_VALUE;    }
      if(tp.currentLevel == 1 && !tp.tp1Hit)
         tp1Clr = CLR_HEADER;
      string tp1Text = "---";
      if(tp.tp1Price > 0.0)
         tp1Text = StringFormat("%s%s", DoubleToString(tp.tp1Price, digits), tp1Status);
      UpdateLabel("P3_TP1_V", tp1Text, tp1Clr);

      //--- TP2
      string tp2Status;
      color  tp2Clr;
      if(tp.tp2Hit) { tp2Status = " [OK]"; tp2Clr = CLR_POSITIVE; }
      else          { tp2Status = " [-]";  tp2Clr = CLR_VALUE;    }
      if(tp.currentLevel == 2 && !tp.tp2Hit)
         tp2Clr = CLR_HEADER;
      string tp2Text = "---";
      if(tp.tp2Price > 0.0)
         tp2Text = StringFormat("%s%s", DoubleToString(tp.tp2Price, digits), tp2Status);
      UpdateLabel("P3_TP2_V", tp2Text, tp2Clr);

      //--- TP3
      string tp3Status;
      color  tp3Clr;
      if(tp.tpExtended) { tp3Status = " [OK]"; tp3Clr = CLR_POSITIVE; }
      else              { tp3Status = " [-]";  tp3Clr = CLR_VALUE;    }
      if(tp.currentLevel == 3 && !tp.tpExtended)
         tp3Clr = CLR_HEADER;
      string tp3Text = "---";
      if(tp.tp3Price > 0.0)
         tp3Text = StringFormat("%s%s", DoubleToString(tp.tp3Price, digits), tp3Status);
      UpdateLabel("P3_TP3_V", tp3Text, tp3Clr);

      //--- Current TP level
      string lvlText = "---";
      color  lvlClr  = CLR_LABEL;
      if(tp.currentLevel > 0)
      {
         lvlText = StringFormat("TP%d", tp.currentLevel);
         lvlClr  = CLR_HEADER;
      }
      UpdateLabel("P3_LVL_V", lvlText, lvlClr);

      //--- Trend strength
      ENUM_TREND_STRENGTH ts = tp.trendStrength;
      UpdateLabel("P3_TST_V", GetTrendStr(ts), GetTrendColor(ts));

      //--- Indicator values from overlay handles
      UpdateIndicatorPanel();
   }

   //=================================================================
   // UPDATE INDICATOR VALUES IN PANEL 3
   //=================================================================
   void UpdateIndicatorPanel()
   {
      int digits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
      double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);

      //--- Parabolic SAR
      if(m_hSAR != INVALID_HANDLE)
      {
         double sarBuf[1];
         if(CopyBuffer(m_hSAR, 0, 0, 1, sarBuf) > 0)
         {
            double sarVal = sarBuf[0];
            bool sarBullish = (bid > sarVal);
            string sarDir = sarBullish ? "YUKARI" : "ASAGI";
            color sarClr  = sarBullish ? CLR_POSITIVE : CLR_NEGATIVE;
            UpdateLabel("P3_SAR_V", StringFormat("%s %s", DoubleToString(sarVal, digits), sarDir), sarClr);
         }
         else
         {
            UpdateLabel("P3_SAR_V", "---", CLR_LABEL);
         }
      }
      else
      {
         UpdateLabel("P3_SAR_V", "---", CLR_LABEL);
      }

      //--- Momentum
      if(m_hMomentum != INVALID_HANDLE)
      {
         double momBuf[1];
         if(CopyBuffer(m_hMomentum, 0, 0, 1, momBuf) > 0)
         {
            double momVal = momBuf[0];
            bool momBullish = (momVal > 100.0);
            string momDir = momBullish ? "YUKARI" : "ASAGI";
            color momClr  = momBullish ? CLR_POSITIVE : CLR_NEGATIVE;
            UpdateLabel("P3_MOM_V", StringFormat("%.2f %s", momVal, momDir), momClr);
         }
         else
         {
            UpdateLabel("P3_MOM_V", "---", CLR_LABEL);
         }
      }
      else
      {
         UpdateLabel("P3_MOM_V", "---", CLR_LABEL);
      }

      //--- BB Squeeze detection
      if(m_hBB != INVALID_HANDLE)
      {
         double bbU[10], bbL[10];
         if(CopyBuffer(m_hBB, 1, 0, 10, bbU) >= 10 &&
            CopyBuffer(m_hBB, 2, 0, 10, bbL) >= 10)
         {
            double currentBW = bbU[9] - bbL[9];
            double bwSum = 0.0;
            for(int i = 0; i < 10; i++)
            {
               double bw = bbU[i] - bbL[i];
               if(bw > 0.0) bwSum += bw;
            }
            double bwAvg = bwSum / 10.0;

            bool isSqueeze = false;
            if(bwAvg > 0.0 && currentBW < bwAvg * 0.70)
               isSqueeze = true;

            if(isSqueeze)
               UpdateLabel("P3_BSQ_V", "SQUEEZE", CLR_WARNING);
            else
               UpdateLabel("P3_BSQ_V", "NORMAL", CLR_VALUE);
         }
         else
         {
            UpdateLabel("P3_BSQ_V", "---", CLR_LABEL);
         }
      }
      else
      {
         UpdateLabel("P3_BSQ_V", "---", CLR_LABEL);
      }
   }

   //=================================================================
   // PANEL 4 UPDATE: SPM + FIFO
   //=================================================================
   void UpdatePanel4()
   {
      if(m_posMgr == NULL)
         return;

      FIFOSummary fifo = m_posMgr.GetFIFOSummary();

      //--- Main P/L
      UpdateLabel("P4_MAIN_V", StringFormat("$%.2f", fifo.mainLoss), ColorBySign(fifo.mainLoss));

      //--- Active SPM count + layers
      UpdateLabel("P4_ASPM_V",
                  StringFormat("%d / Katman:%d", fifo.activeSPMCount, fifo.spmLayerCount),
                  CLR_VALUE);

      //--- Closed SPM profit
      UpdateLabel("P4_CSPM_V",
                  StringFormat("$%.2f (%d)", fifo.closedProfitTotal, fifo.closedCount),
                  ColorBySign(fifo.closedProfitTotal));

      //--- Open SPM profit
      UpdateLabel("P4_OSPM_V", StringFormat("$%.2f", fifo.openSPMProfit),
                  ColorBySign(fifo.openSPMProfit));

      //--- Net result
      color netClr = ColorBySign(fifo.netResult);
      if(fifo.isProfitable) netClr = CLR_POSITIVE;
      UpdateLabel("P4_NET_V", StringFormat("$%.2f", fifo.netResult), netClr);

      //--- Target
      UpdateLabel("P4_TGT_V", StringFormat("$%.2f", fifo.targetUSD), CLR_HEADER);

      //--- Progress percentage
      double progress = 0.0;
      if(fifo.targetUSD > 0.0)
         progress = (fifo.netResult / fifo.targetUSD) * 100.0;
      if(progress < 0.0) progress = 0.0;
      if(progress > 100.0) progress = 100.0;

      color pctClr = CLR_VALUE;
      if(progress >= 100.0)     pctClr = CLR_POSITIVE;
      else if(progress >= 50.0) pctClr = CLR_PROGRESS_FILL;
      else if(progress > 0.0)   pctClr = CLR_WARNING;

      UpdateLabel("P4_PCT_V", StringFormat("%.1f%%", progress), pctClr);

      //--- Progress bar
      color barClr = CLR_PROGRESS_FILL;
      if(progress >= 100.0)     barClr = CLR_POSITIVE;
      else if(progress >= 75.0) barClr = CLR_PROGRESS_FILL;
      else if(progress >= 25.0) barClr = CLR_WARNING;
      else                      barClr = CLR_NEGATIVE;
      UpdateProgressBar("P4_FIFO_BAR", progress, barClr);
   }

   //=================================================================
   // CHART OVERLAY: Draw BB lines, SAR dots on chart
   //=================================================================
   void DrawIndicatorOverlay()
   {
      //--- Throttle: only redraw every IND_OVERLAY_COOLDOWN seconds
      if(TimeCurrent() - m_lastOverlayDraw < IND_OVERLAY_COOLDOWN)
         return;

      m_lastOverlayDraw = TimeCurrent();

      //--- Delete old indicator overlay objects
      ObjectsDeleteAll(m_chartId, "BTFX_IND_", m_subWindow);

      //--- Draw Bollinger Bands overlay (last IND_OVERLAY_BARS bars)
      DrawBBOverlay();

      //--- Draw Parabolic SAR dots
      DrawSAROverlay();
   }

   //=================================================================
   // DRAW BOLLINGER BANDS OVERLAY (3 lines: upper, middle, lower)
   //=================================================================
   void DrawBBOverlay()
   {
      if(m_hBB == INVALID_HANDLE)
         return;

      int bars = IND_OVERLAY_BARS;

      //--- Copy BB buffers: 0=middle, 1=upper, 2=lower
      double bbMid[];
      double bbUp[];
      double bbLo[];
      ArraySetAsSeries(bbMid, false);
      ArraySetAsSeries(bbUp, false);
      ArraySetAsSeries(bbLo, false);

      if(CopyBuffer(m_hBB, 0, 0, bars + 1, bbMid) < bars + 1) return;
      if(CopyBuffer(m_hBB, 1, 0, bars + 1, bbUp)  < bars + 1) return;
      if(CopyBuffer(m_hBB, 2, 0, bars + 1, bbLo)  < bars + 1) return;

      //--- Draw trend line segments connecting bar[i] to bar[i+1]
      //--- Non-series arrays: index 0 = oldest, index bars = most recent (bar 0)
      for(int i = 0; i < bars; i++)
      {
         //--- Map non-series index to bar shift:
         //--- Non-series index i corresponds to bar shift = bars - i
         int barShiftCur  = bars - i;
         int barShiftNext = bars - i - 1;

         datetime timeCur  = iTime(m_symbol, PERIOD_M15, barShiftCur);
         datetime timeNext = iTime(m_symbol, PERIOD_M15, barShiftNext);

         if(timeCur == 0 || timeNext == 0)
            continue;

         //--- Upper band (DodgerBlue, STYLE_DOT)
         string nameU = StringFormat("BTFX_IND_BBU_%d", i);
         ObjectCreate(m_chartId, nameU, OBJ_TREND, m_subWindow, timeCur, bbUp[i], timeNext, bbUp[i + 1]);
         ObjectSetInteger(m_chartId, nameU, OBJPROP_COLOR, clrDodgerBlue);
         ObjectSetInteger(m_chartId, nameU, OBJPROP_STYLE, STYLE_DOT);
         ObjectSetInteger(m_chartId, nameU, OBJPROP_WIDTH, 1);
         ObjectSetInteger(m_chartId, nameU, OBJPROP_RAY_RIGHT, false);
         ObjectSetInteger(m_chartId, nameU, OBJPROP_RAY_LEFT, false);
         ObjectSetInteger(m_chartId, nameU, OBJPROP_BACK, true);
         ObjectSetInteger(m_chartId, nameU, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(m_chartId, nameU, OBJPROP_HIDDEN, true);

         //--- Middle band (Gold, STYLE_SOLID)
         string nameM = StringFormat("BTFX_IND_BBM_%d", i);
         ObjectCreate(m_chartId, nameM, OBJ_TREND, m_subWindow, timeCur, bbMid[i], timeNext, bbMid[i + 1]);
         ObjectSetInteger(m_chartId, nameM, OBJPROP_COLOR, clrGold);
         ObjectSetInteger(m_chartId, nameM, OBJPROP_STYLE, STYLE_SOLID);
         ObjectSetInteger(m_chartId, nameM, OBJPROP_WIDTH, 1);
         ObjectSetInteger(m_chartId, nameM, OBJPROP_RAY_RIGHT, false);
         ObjectSetInteger(m_chartId, nameM, OBJPROP_RAY_LEFT, false);
         ObjectSetInteger(m_chartId, nameM, OBJPROP_BACK, true);
         ObjectSetInteger(m_chartId, nameM, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(m_chartId, nameM, OBJPROP_HIDDEN, true);

         //--- Lower band (DodgerBlue, STYLE_DOT)
         string nameL = StringFormat("BTFX_IND_BBL_%d", i);
         ObjectCreate(m_chartId, nameL, OBJ_TREND, m_subWindow, timeCur, bbLo[i], timeNext, bbLo[i + 1]);
         ObjectSetInteger(m_chartId, nameL, OBJPROP_COLOR, clrDodgerBlue);
         ObjectSetInteger(m_chartId, nameL, OBJPROP_STYLE, STYLE_DOT);
         ObjectSetInteger(m_chartId, nameL, OBJPROP_WIDTH, 1);
         ObjectSetInteger(m_chartId, nameL, OBJPROP_RAY_RIGHT, false);
         ObjectSetInteger(m_chartId, nameL, OBJPROP_RAY_LEFT, false);
         ObjectSetInteger(m_chartId, nameL, OBJPROP_BACK, true);
         ObjectSetInteger(m_chartId, nameL, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(m_chartId, nameL, OBJPROP_HIDDEN, true);
      }
   }

   //=================================================================
   // DRAW PARABOLIC SAR DOTS ON CHART
   //=================================================================
   void DrawSAROverlay()
   {
      if(m_hSAR == INVALID_HANDLE)
         return;

      int bars = IND_OVERLAY_BARS;

      double sarBuf[];
      ArraySetAsSeries(sarBuf, false);

      if(CopyBuffer(m_hSAR, 0, 0, bars, sarBuf) < bars)
         return;

      for(int i = 0; i < bars; i++)
      {
         //--- Map non-series index to bar shift
         int barShift = bars - 1 - i;

         datetime barTime = iTime(m_symbol, PERIOD_M15, barShift);
         if(barTime == 0)
            continue;

         double sarVal = sarBuf[i];

         //--- Get bar close to determine SAR position relative to price
         double closePrice = iClose(m_symbol, PERIOD_M15, barShift);
         bool isBullish = (closePrice > sarVal);  // SAR below price = bullish

         string name = StringFormat("BTFX_IND_SAR_%d", i);
         ObjectCreate(m_chartId, name, OBJ_ARROW, m_subWindow, barTime, sarVal);
         ObjectSetInteger(m_chartId, name, OBJPROP_ARROWCODE, 159);  // Small circle/dot
         ObjectSetInteger(m_chartId, name, OBJPROP_COLOR, isBullish ? clrLime : clrRed);
         ObjectSetInteger(m_chartId, name, OBJPROP_WIDTH, 1);
         ObjectSetInteger(m_chartId, name, OBJPROP_BACK, true);
         ObjectSetInteger(m_chartId, name, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(m_chartId, name, OBJPROP_HIDDEN, true);
      }
   }

public:
   //+------------------------------------------------------------------+
   //| Constructor                                                       |
   //+------------------------------------------------------------------+
   CChartDashboard()
   {
      m_engine           = NULL;
      m_posMgr           = NULL;
      m_spread           = NULL;
      m_symbol           = "";
      m_category         = CAT_UNKNOWN;
      m_enabled          = false;
      m_chartId          = 0;
      m_subWindow        = 0;
      m_panelX           = DASH_PANEL_X;
      m_panelY           = 30;
      m_panelW           = DASH_PANEL_W;
      m_panelH           = 0;
      m_hSAR             = INVALID_HANDLE;
      m_hMomentum        = INVALID_HANDLE;
      m_hBB              = INVALID_HANDLE;
      m_lastOverlayDraw  = 0;
   }

   //+------------------------------------------------------------------+
   //| Destructor                                                        |
   //+------------------------------------------------------------------+
   ~CChartDashboard()
   {
      Destroy();
   }

   //+------------------------------------------------------------------+
   //| Initialize - Wire data sources, create panels, create indicators  |
   //+------------------------------------------------------------------+
   void Initialize(string symbol, ENUM_SYMBOL_CATEGORY cat,
                   CSignalEngine &engine, CPositionManager &posMgr,
                   CSpreadFilter &spread, bool enabled)
   {
      m_symbol   = symbol;
      m_category = cat;
      m_engine   = GetPointer(engine);
      m_posMgr   = GetPointer(posMgr);
      m_spread   = GetPointer(spread);
      m_enabled  = enabled;
      m_chartId  = ChartID();
      m_subWindow = 0;

      if(!m_enabled)
      {
         Print("[Dashboard] Dashboard devre disi.");
         return;
      }

      //--- Create indicator handles for chart overlay
      m_hSAR      = iSAR(m_symbol, PERIOD_M15, 0.02, 0.2);
      m_hMomentum = iMomentum(m_symbol, PERIOD_M15, 14, PRICE_CLOSE);
      m_hBB       = iBands(m_symbol, PERIOD_M15, 20, 0, 2.0, PRICE_CLOSE);

      if(m_hSAR == INVALID_HANDLE)
         Print("[Dashboard] WARNING: SAR handle creation failed");
      if(m_hMomentum == INVALID_HANDLE)
         Print("[Dashboard] WARNING: Momentum handle creation failed");
      if(m_hBB == INVALID_HANDLE)
         Print("[Dashboard] WARNING: BB handle creation failed");

      //--- Create all 4 panels with new positions and sizes
      int x = m_panelX;

      CreatePanel1(x, 30);     // y=30,  h=285
      CreatePanel2(x, 325);    // y=325, h=290
      CreatePanel3(x, 625);    // y=625, h=165
      CreatePanel4(x, 800);    // y=800, h=195

      ChartRedraw(m_chartId);

      Print(StringFormat("[Dashboard] %s [%s] Dashboard olusturuldu. Panels=4 Overlay=BB+SAR+Mom",
            m_symbol, GetCategoryName(m_category)));
   }

   //+------------------------------------------------------------------+
   //| Update - Refresh all panels + chart overlay (call every tick/timer)|
   //+------------------------------------------------------------------+
   void Update()
   {
      if(!m_enabled)
         return;

      //--- Update dashboard panels
      UpdatePanel1();
      UpdatePanel2();
      UpdatePanel3();
      UpdatePanel4();

      //--- Update chart overlay indicators (throttled to every 2 sec)
      DrawIndicatorOverlay();

      ChartRedraw(m_chartId);
   }

   //+------------------------------------------------------------------+
   //| Destroy - Remove ALL dashboard and overlay objects from chart      |
   //+------------------------------------------------------------------+
   void Destroy()
   {
      if(m_chartId == 0)
         m_chartId = ChartID();

      //--- Delete indicator overlay objects first
      ObjectsDeleteAll(m_chartId, "BTFX_IND_", m_subWindow);

      //--- Delete all dashboard objects
      ObjectsDeleteAll(m_chartId, "BTFX_", m_subWindow);

      //--- Release indicator handles
      if(m_hSAR != INVALID_HANDLE)
      {
         IndicatorRelease(m_hSAR);
         m_hSAR = INVALID_HANDLE;
      }
      if(m_hMomentum != INVALID_HANDLE)
      {
         IndicatorRelease(m_hMomentum);
         m_hMomentum = INVALID_HANDLE;
      }
      if(m_hBB != INVALID_HANDLE)
      {
         IndicatorRelease(m_hBB);
         m_hBB = INVALID_HANDLE;
      }

      ChartRedraw(m_chartId);
   }

   //+------------------------------------------------------------------+
   //| SetArrowTooltip - Set tooltip text on a named arrow object        |
   //+------------------------------------------------------------------+
   void SetArrowTooltip(string arrowName, string tooltipText)
   {
      if(m_chartId == 0)
         m_chartId = ChartID();

      if(ObjectFind(m_chartId, arrowName) >= 0)
      {
         ObjectSetString(m_chartId, arrowName, OBJPROP_TOOLTIP, tooltipText);
      }
   }
};

#endif // CHART_DASHBOARD_MQH
