//+------------------------------------------------------------------+
//| LevisFxBot.mq5                                                   |
//| Automated Asian Gold Trading System - Version 4.0.0              |
//| FIX: Fully Modular Class Structure (Phase 2 Preparation)         |
//| NEW: Fair Value Gap (FVG) Filter Integrated                      |
//+------------------------------------------------------------------+
#property copyright "Levis Mwaniki"
#property version   "4.0.0"
#property strict
#property description "Deterministic rule-based EA for XAUUSD Asian session (00:00-17:00)"

// --- PHASE 1 & 2 MODULES ---
#include <Trade\Trade.mqh>
#include <PositionInfo.mqh>
#include "SessionRange.mqh"
#include "RetestCounter.mqh"
#include "SwingStructure.mqh"
#include "FairValueGap.mqh"  // <--- NEW FVG MODULE

CTrade Trade;
CPositionInfo Position;

// Trend Enum for Clarity
enum ENUM_TREND {
    TREND_BULLISH = 1,
    TREND_BEARISH = -1,
    TREND_NEUTRAL = 0
};

//========== INPUT PARAMETERS (Aligned with default.ini) ==========

// Session Configuration
input int    AsianStartHour    = 0;      
input int    AsianEndHour      = 8;      
input int    LondonEndHour     = 17;     // For future logic (e.g., closing trades)

// Detection Parameters 
input ENUM_TIMEFRAMES RangeTF  = PERIOD_M5;  
input int    TouchTolerancePts = 50;     
input int    FVGLookbackBars   = 10;     // NEW: Bars to check for FVG
input int    SwingBars         = 2;      // Based on typical SwingStructure needs

// Risk Management & Execution (Phase 4/5)
input double RiskPerTrade      = 2.0;    
input double FixedLotSize      = 0.01;   
input int    BreakEvenTriggerR = 1;      
input bool   TrailAfterBE      = true;   
input int    TrailingStopPips  = 100;    
input int    StopLevelBuffer   = 2;      

// Trend Filters (Phase 2)
input ENUM_TIMEFRAMES HTF_Timeframe   = PERIOD_H4; 
input int    ATRPeriod           = 14;         
input double ATRMultiplierSL     = 1.5;        
input double ATRMultiplierTP     = 2.0;        

// Confluence Filter (Phase 2)
input bool   RequireFVG          = false;    // NEW: Enable/Disable FVG filter
// input bool   RequireVWAPBias     = false;    // For next step
// input int    MinConfluenceChecks = 2;        // For next step

// Retest & Logging
input bool   EnableAlerts      = true;
input bool   EnableLogging     = true;
input bool   ShowRangeLines    = true;

//========== GLOBAL OBJECTS & VARIABLES ==========
CSessionRange *m_session = NULL;
CRetestCounter *m_retest = NULL;
SwingStructure *m_swing  = NULL;
FairValueGap *m_fvg      = NULL; // <--- FVG Instance

ulong positionTicket = 0; 

//+------------------------------------------------------------------+
//| UTILITY FUNCTIONS (Simplified)                                   |
//+------------------------------------------------------------------+
void Log(string message) {
    if (EnableLogging) PrintFormat("LevisFxBot | %s", message);
}

//+------------------------------------------------------------------+
//| Get High-Timeframe Trend (Placeholder for simple EMA bias)       |
//+------------------------------------------------------------------+
ENUM_TREND GetHTFTrend() {
    int ma_handle = iEMA(_Symbol, HTF_Timeframe, 20, PRICE_CLOSE);
    if (ma_handle == INVALID_HANDLE) return TREND_NEUTRAL;
    
    double ma_buffer[1], close_buffer[1];
    if (CopyBuffer(ma_handle, 0, 1, 1, ma_buffer) != 1 || 
        CopyClose(_Symbol, HTF_Timeframe, 1, 1, close_buffer) != 1) return TREND_NEUTRAL;
    
    return (close_buffer[0] > ma_buffer[0]) ? TREND_BULLISH : 
           (close_buffer[0] < ma_buffer[0]) ? TREND_BEARISH : TREND_NEUTRAL;
}

//+------------------------------------------------------------------+
//| ORDER EXECUTION (Placeholder - to be finalized in Phase 4)       |
//+------------------------------------------------------------------+
void ExecuteMarketOrder(bool isLong, double entry) {
    // --- TEMPORARY PLACEHOLDER LOGIC ---
    if (PositionSelect(_Symbol)) return; 
    
    // Use fixed lot size for now
    double lots = FixedLotSize; 
    
    // Placeholder SL/TP calculation (e.g., fixed pips)
    double slPips = 100; // 100 points
    double tpPips = 200; // 200 points
    
    double slPrice, tpPrice;
    
    if (isLong) {
        slPrice = entry - slPips * _Point;
        tpPrice = entry + tpPips * _Point;
        Trade.Buy(lots, _Symbol, entry, slPrice, tpPrice);
    } else {
        slPrice = entry + slPips * _Point;
        tpPrice = entry - tpPips * _Point;
        Trade.Sell(lots, _Symbol, entry, slPrice, tpPrice);
    }
    
    if (Trade.ResultRetcode() == TRADE_RETCODE_DONE) {
        Log(StringFormat("ORDER EXECUTED: %s %.2f @ %.5f. SL: %.5f TP: %.5f", 
            isLong ? "BUY" : "SELL", lots, entry, slPrice, tpPrice));
    } else {
        Log(StringFormat("Order failed. Error: %d", Trade.ResultDeal()));
    }
    // --- END TEMPORARY LOGIC ---
}

//+------------------------------------------------------------------+
//| TRADE TRIGGER LOGIC (FVG, HTF Filters applied here)              |
//+------------------------------------------------------------------+
void CheckTradeTriggers() {
    // 1. Check if session is valid and a new touch/retest has occurred
    if (!m_session.IsValid() || !m_retest.HasNewTouch() || PositionSelect(_Symbol)) return;

    // 2. Update market state
    m_swing.updateStructure(); 
    ENUM_TREND htfTrend = GetHTFTrend();

    TouchEvent lastTouch;
    if (!m_retest.GetLastTouch(lastTouch)) return;
    double entryPrice = SymbolInfoDouble(_Symbol, lastTouch.isHigh ? SYMBOL_ASK : SYMBOL_BID);

    // --- BEARISH SETUP (Touch High) ---
    if (lastTouch.isHigh) {
        // HTF Filter: Bearish OR Neutral
        if (htfTrend == TREND_BULLISH) {
             Log("FILTERED: Bearish setup rejected. Counter-trend to HTF (Bullish).");
             m_retest.AcknowledgeTouch();
             return;
        }
        
        // FVG Filter (NEW)
        if (RequireFVG) {
            if (!m_fvg.IsFVGPresent(entryPrice, TREND_BEARISH, TouchTolerancePts)) {
                Log("FILTERED: Bearish setup rejected. No BEARISH FVG detected near entry.");
                m_retest.AcknowledgeTouch();
                return;
            }
        }

        // CHoCH Trigger: Structure flip (Placeholder for Phase 3 condition)
        if (m_swing.isLowerLow || m_swing.isLowerHigh) {
            Log("TRIGGER: Bearish CHoCH + Confluence confirmed at Asian High retest. Executing SHORT.");
            ExecuteMarketOrder(false, entryPrice);
            m_retest.AcknowledgeTouch();
            return;
        }
    }

    // --- BULLISH SETUP (Touch Low) ---
    if (lastTouch.isLow) {
        // HTF Filter: Bullish OR Neutral
        if (htfTrend == TREND_BEARISH) {
            Log("FILTERED: Bullish setup rejected. Counter-trend to HTF (Bearish).");
            m_retest.AcknowledgeTouch();
            return;
        }

        // FVG Filter (NEW)
        if (RequireFVG) {
            if (!m_fvg.IsFVGPresent(entryPrice, TREND_BULLISH, TouchTolerancePts)) {
                Log("FILTERED: Bullish setup rejected. No BULLISH FVG detected near entry.");
                m_retest.AcknowledgeTouch();
                return;
            }
        }

        // CHoCH Trigger: Structure flip (Placeholder for Phase 3 condition)
        if (m_swing.isHigherHigh || m_swing.isHigherLow) {
            Log("TRIGGER: Bullish CHoCH + Confluence confirmed at Asian Low retest. Executing LONG.");
            ExecuteMarketOrder(true, entryPrice);
            m_retest.AcknowledgeTouch();
            return;
        }
    }
    
    // Acknowledge touch if no trade was taken, but logic was checked
    // This prevents re-checking the same touch event multiple times
    m_retest.AcknowledgeTouch(); 
}

// (Chart display functions like UpdateChartInfo() are omitted for brevity in this update)

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {
    // --- Initialize Trading Class ---
    Trade.SetExpertMagicNumber(123456);
    Trade.SetMarginMode();

    // --- Initialize Custom Modules (using the classes from your .mqh files) ---
    
    // 1. Session Range (Phase 1)
    m_session = new CSessionRange(AsianStartHour, 0, AsianEndHour, 0); 
    m_session.SetTimeframe(RangeTF);
    m_session.SetSymbol(_Symbol);

    // 2. Retest Counter (Phase 1)
    m_retest = new CRetestCounter(TouchTolerancePts, 1); 
    m_retest.SetTimeframe(RangeTF);

    // 3. Swing Structure (Phase 1)
    m_swing = new SwingStructure(RangeTF, SwingBars, _Symbol);
    
    // 4. Fair Value Gap (Phase 2 - NEW)
    m_fvg = new FairValueGap(RangeTF, FVGLookbackBars, _Symbol); 

    Log("=== LevisFxBot Initialized (Trading Enabled) === Version 4.0.0");
    Log(StringFormat("HTF Filter: %s | FVG Required: %s", EnumToString(HTF_Timeframe), RequireFVG ? "YES" : "NO"));
    
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
    // --- Clean up modules ---
    if(m_session != NULL) delete m_session;
    if(m_retest != NULL) delete m_retest;
    if(m_swing != NULL) delete m_swing;
    if(m_fvg != NULL) delete m_fvg; // <--- NEW FVG CLEANUP
    Comment(""); 
}

//+------------------------------------------------------------------+
//| Expert tick function (The core loop)                             |
//+------------------------------------------------------------------+
void OnTick() {
    if (m_session == NULL || m_retest == NULL || m_swing == NULL || m_fvg == NULL) return; 

    // 1. Calculate/recalculate session range
    if(m_session.CalculateRange()) {
        // If a new session range is calculated, update the retest levels
        m_retest.SetLevels(m_session.GetHigh(), m_session.GetLow());
        m_retest.Reset();
        Log(m_session.GetInfo());
    }
    
    // 2. Check for new touches/retests
    m_retest.CheckForTouches(10);
    
    // 3. Check for trade triggers (applies FVG and HTF filters)
    CheckTradeTriggers();

    // 4. Manage existing position (Placeholder for Phase 4)
    // TrailStop();
    // CheckBreakEven();
}
//+------------------------------------------------------------------+
