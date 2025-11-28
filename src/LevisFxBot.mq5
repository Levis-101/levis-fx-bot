//+------------------------------------------------------------------+
//| LevisFxBot.mq5                                                   |
//| Automated Asian Gold Trading System - Phase 2: HTF & ATR         |
//| FIX: Integrated ATR-based SL/TP and HTF Trend Filter             |
//+------------------------------------------------------------------+
#property copyright "Levis Mwaniki"
#property version   "3.0.0"
#property strict
#property description "Deterministic rule-based EA for XAUUSD Asian session (00:00-17:00)"

#include <Trade\Trade.mqh>
#include <PositionInfo.mqh>
#include "SessionRange.mqh"
#include "RetestCounter.mqh"
#include "SwingStructure.mqh"

CTrade Trade;
CPositionInfo Position;

// Trend Enum for Clarity
enum ENUM_TREND {
    TREND_BULLISH = 1,
    TREND_BEARISH = -1,
    TREND_NEUTRAL = 0
};

//========== INPUT PARAMETERS ==========

// Session Configuration (Phase 1)
input int    AsianStartHour    = 0;      // Asian session start (server time)
input int    AsianEndHour      = 8;      // Asian session end (server time)
input int    LondonEndHour     = 17;     // Trading stops after this hour

// Detection Parameters (Phase 1/2)
input ENUM_TIMEFRAMES RangeTF  = PERIOD_M5;  // Timeframe for range calc
input int    TouchTolerancePts = 50;     // Touch tolerance in points
input int    SwingBars         = 2;      // Bars needed on each side for confirmed swing (Fractal)

// Risk Management & Execution (Phase 4/5)
input double RiskPerTrade      = 2.0;    // % of balance to risk per trade (from default.ini)
input double FixedLotSize      = 0.01;   // Fallback lot size if R-risk fails
input int    BreakEvenTriggerR = 1;      // Move SL to BE at +1R
input bool   TrailAfterBE      = true;   // Trail only after BE
input int    TrailingStopPips  = 100;    // Trail distance in points (in points)
input int    StopLevelBuffer   = 2;      // Extra pips buffer for SL

// Trend Filters (Phase 2 - NEW)
input ENUM_TIMEFRAMES HTF_Timeframe   = PERIOD_H4;  // H4 trend filter (from default.ini)
input int    ATRPeriod           = 14;         // ATR period (from default.ini)
input double ATRMultiplierSL     = 1.5;        // ATR multiplier for SL (from default.ini)
input double ATRMultiplierTP     = 2.0;        // ATR multiplier for TP (R:R target)

// Retest & Logging
input bool   EnableAlerts      = true;
input bool   EnableLogging     = true;
input bool   ShowRangeLines    = true;

//========== GLOBAL OBJECTS & VARIABLES ==========
CSessionRange *m_session = NULL;
CRetestCounter *m_retest = NULL;
SwingStructure *m_swing  = NULL;

ulong positionTicket = 0; // The primary ticket for the current trade
double entryPrice, slPrice, tpPrice;

//+------------------------------------------------------------------+
//| Logging Function                                                 |
//+------------------------------------------------------------------+
void Log(string message) {
    if (EnableLogging) PrintFormat("LevisFxBot | %s", message);
}

//+------------------------------------------------------------------+
//| NEW: Get High-Timeframe Trend (using simple EMA cross)           |
//+------------------------------------------------------------------+
ENUM_TREND GetHTFTrend() {
    // We will use a simple 20-period Exponential Moving Average (EMA) on the HTF 
    // to determine the overall bias.
    int ma_handle = iEMA(_Symbol, HTF_Timeframe, 20, PRICE_CLOSE);
    if (ma_handle == INVALID_HANDLE) {
        Log("Error creating EMA handle for HTF trend check.");
        return TREND_NEUTRAL;
    }
    
    double ma_buffer[1];
    double close_buffer[1];
    
    // Get current bar's EMA and Close price on HTF (H4)
    if (CopyBuffer(ma_handle, 0, 1, 1, ma_buffer) != 1 || CopyClose(_Symbol, HTF_Timeframe, 1, 1, close_buffer) != 1) {
        return TREND_NEUTRAL;
    }
    
    double ma = ma_buffer[0];
    double close = close_buffer[0];

    // Bullish: Price > MA
    if (close > ma) return TREND_BULLISH;
    // Bearish: Price < MA
    if (close < ma) return TREND_BEARISH;
    
    return TREND_NEUTRAL;
}

//+------------------------------------------------------------------+
//| Helper: Calculate Lot Size (Dynamic Risk)                        |
//+------------------------------------------------------------------+
double CalculateLotSize(double slInPriceUnits) {
    if (slInPriceUnits <= 0) return FixedLotSize;
    
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double riskAmount = balance * (RiskPerTrade / 100.0);
    
    // Calculate currency value of 1 Lot over the SL distance
    double valuePerLot = MarketInfo(_Symbol, MODE_TICKVALUE) * (slInPriceUnits / MarketInfo(_Symbol, MODE_TICKSIZE));
    
    // Lot size calculation: RiskAmount / ValuePerLot
    double lotSize = riskAmount / valuePerLot;
    
    // Normalize Lot Size
    double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

    if (lotSize < minLot) lotSize = minLot;
    if (lotSize > maxLot) lotSize = maxLot;
    
    lotSize = MathRound(lotSize / step) * step;
    
    return lotSize;
}

//+------------------------------------------------------------------+
//| Order Execution (Now uses ATR for SL/TP)                         |
//+------------------------------------------------------------------+
void ExecuteMarketOrder(bool isLong, double entry) {
    if (PositionSelect(_Symbol)) {
        Log("Trade skipped: Position already open.");
        return;
    }

    // 1. Calculate ATR for Volatility-Adjusted SL
    int atr_handle = iATR(_Symbol, RangeTF, ATRPeriod);
    double atr_buffer[1];
    if (CopyBuffer(atr_handle, 0, 1, 1, atr_buffer) != 1) {
        Log("ERROR: Failed to get ATR data. Cannot execute trade.");
        return;
    }
    double currentATR = atr_buffer[0];
    
    // Calculate SL distance based on ATR
    double slDistance = currentATR * ATRMultiplierSL;
    double tpDistance = slDistance * (ATRMultiplierTP / ATRMultiplierSL); // TP is based on R:R ratio

    // Apply StopLevelBuffer (in points converted to price)
    double bufferPrice = StopLevelBuffer * _Point;

    // 2. Determine Final SL/TP Prices
    if (isLong) {
        slPrice = entry - slDistance - bufferPrice;
        tpPrice = entry + tpDistance;
    } else {
        slPrice = entry + slDistance + bufferPrice;
        tpPrice = entry - tpDistance;
    }
    
    // 3. Dynamic Lot Size Calculation (based on ATR SL distance)
    double slInPriceUnits = MathAbs(entry - slPrice);
    double lots = CalculateLotSize(slInPriceUnits);
    
    if (lots < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN)) {
         Log("ERROR: Lot size too small or risk calculation failed. Using Fixed Lot Size.");
         lots = FixedLotSize;
    }
    
    // 4. Execute Trade
    if (isLong) {
        if (!Trade.Buy(lots, _Symbol, entry, slPrice, tpPrice)) {
            Log(StringFormat("Buy failed. Error: %d", Trade.ResultDeal()));
        }
    } else {
        if (!Trade.Sell(lots, _Symbol, entry, slPrice, tpPrice)) {
            Log(StringFormat("Sell failed. Error: %d", Trade.ResultDeal()));
        }
    }
    
    if (Trade.ResultRetcode() == TRADE_RETCODE_DONE) {
        positionTicket = Trade.ResultDeal();
        Log(StringFormat("ORDER EXECUTED: %s %.2f @ %.5f. SL: %.5f (ATR SL:%.2f) TP: %.5f", 
            isLong ? "BUY" : "SELL", lots, entry, slPrice, currentATR, tpPrice));
    }
}

// (The remaining Trade Management functions: TrailStop, CheckBreakEven, and helper functions are unchanged for brevity)

//+------------------------------------------------------------------+
//| Trade Trigger Logic (CHoCH at Retest + HTF Filter)               |
//+------------------------------------------------------------------+
void CheckTradeTriggers() {
    if (!m_session.IsValid() || !m_retest.HasNewTouch() || PositionSelect(_Symbol)) return;

    m_swing.updateStructure(); // Update confirmed structure points
    ENUM_TREND htfTrend = GetHTFTrend();

    TouchEvent lastTouch;
    if (!m_retest.GetLastTouch(lastTouch)) return;
    double entryPrice = SymbolInfoDouble(_Symbol, lastTouch.isHigh ? SYMBOL_ASK : SYMBOL_BID);

    // --- BEARISH SETUP (Touch High) ---
    if (lastTouch.isHigh) {
        Log(StringFormat("Bearish Check: HTF Trend is %d, CHoCH flags: LL=%s LH=%s", htfTrend, (string)m_swing.isLowerLow, (string)m_swing.isLowerHigh));

        // Confluence: HTF must be Bearish OR Neutral (avoid strong counter-trend)
        if (htfTrend == TREND_BULLISH) {
             Log("FILTERED: Bearish setup rejected. Counter-trend to HTF (Bullish).");
             return;
        }

        // Trigger: Price touched high, AND structure has flipped bearish (CHoCH)
        if (m_swing.isLowerLow || m_swing.isLowerHigh) {
            Log("TRIGGER: Bearish CHoCH confirmed at Asian High retest. Executing SHORT.");
            
            ExecuteMarketOrder(false, entryPrice); // Short Trade
            m_retest.AcknowledgeTouch();
            return;
        }
    }

    // --- BULLISH SETUP (Touch Low) ---
    if (lastTouch.isLow) {
        Log(StringFormat("Bullish Check: HTF Trend is %d, CHoCH flags: HH=%s HL=%s", htfTrend, (string)m_swing.isHigherHigh, (string)m_swing.isHigherLow));

        // Confluence: HTF must be Bullish OR Neutral
        if (htfTrend == TREND_BEARISH) {
            Log("FILTERED: Bullish setup rejected. Counter-trend to HTF (Bearish).");
            return;
        }

        // Trigger: Price touched low, AND structure has flipped bullish (CHoCH)
        if (m_swing.isHigherHigh || m_swing.isHigherLow) {
            Log("TRIGGER: Bullish CHoCH confirmed at Asian Low retest. Executing LONG.");
            
            ExecuteMarketOrder(true, entryPrice); // Long Trade
            m_retest.AcknowledgeTouch();
            return;
        }
    }
}

// (The remaining setup and cleanup functions are unchanged for brevity)

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {
    // Session class 
    m_session = new CSessionRange(AsianStartHour, 0, AsianEndHour, 0, RangeTF, _Symbol);
    
    // Retest class 
    m_retest = new CRetestCounter(TouchTolerancePts, 1); 
    
    // Swing class 
    m_swing = new SwingStructure(RangeTF, SwingBars, _Symbol);

    // Trade object
    Trade.SetExpertMagicNumber(123456);
    
    Log("=== LevisFxBot Initialized (Trading Enabled) === Version 3.0.0");
    Log(StringFormat("HTF Trend Filter: %s | ATR SL Multiplier: %.1f", EnumToString(HTF_Timeframe), ATRMultiplierSL));
    
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//| (Content omitted for brevity - should contain proper cleanup)    |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
    if(m_session != NULL) delete m_session;
    if(m_retest != NULL) delete m_retest;
    if(m_swing != NULL) delete m_swing;
    Comment(""); 
}

//+------------------------------------------------------------------+
//| Expert tick function (The core logic)                            |
//| (Content omitted for brevity - logic remains the same)           |
//+------------------------------------------------------------------+
void OnTick() {
    // ... (Your existing OnTick logic for Phases 1 & 3) ...
    // Note: TrailStop and CheckBreakEven functions from the previous iteration must be placed here.
    
    datetime now = TimeCurrent();
    MqlDateTime dt;
    TimeToStruct(now, dt);

    // --- PHASE 3: DAILY COOLDOWN/RESET ---
    if (dt.hour >= LondonEndHour) {
        if (m_session.IsValid()) {
             m_session.Reset();
             m_retest.Reset();
        }
        return; 
    }

    // --- PHASE 1: ASIAN SESSION (BUILD RANGE) ---
    if (dt.hour >= AsianStartHour && dt.hour < AsianEndHour) {
        m_session.Calculate();
        m_retest.SetLevels(m_session.GetSessionHigh(), m_session.GetSessionLow());
    } 
    // --- PHASE 2: LONDON SESSION (HUNT RETESTS) ---
    else if (dt.hour >= AsianEndHour && dt.hour < LondonEndHour) {
        
        if (!m_session.IsValid()) return;

        m_retest.CheckTouch(now);
        
        CheckTradeTriggers(); // Execution
        
        // Risk Management
        if (PositionSelect(_Symbol)) {
            // CheckBreakEven() and TrailStop() logic must be present here
        }
    }
    
    // Update Chart Visuals (if ShowRangeLines is true)
}
//+------------------------------------------------------------------+
