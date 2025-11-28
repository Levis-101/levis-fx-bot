//+------------------------------------------------------------------+
//| LevisFxBot.mq5                                                   |
//| Automated Asian Gold Trading System - Version 11.0.0             |
//| PHASE 5: Volatility Adaptation Implemented                       |
//+------------------------------------------------------------------+
#property copyright "Levis Mwaniki"
#property version   "11.0.0"
#property strict
#property description "Deterministic rule-based EA for XAUUSD Asian session (00:00-17:00)"

// --- MODULES ---
// *** IMPORTANT: These custom files must be in MQL5/Include/ ***
#include <Trade\Trade.mqh>
#include <PositionInfo.mqh>
#include "SessionRange.mqh"
#include "RetestCounter.mqh"
#include "SwingStructure.mqh"
#include "FairValueGap.mqh"     
#include "VWAPBias.mqh"         

CTrade Trade;
CPositionInfo Position;

// Trend/Regime Enums (MUST match those in .mqh files)
enum ENUM_TREND {
    TREND_BULLISH = 1,
    TREND_BEARISH = -1,
    TREND_NEUTRAL = 0
};

enum ENUM_VOLATILITY_REGIME {
    REGIME_LOW_VOL = 0,
    REGIME_HIGH_VOL = 1
};

//========== INPUT PARAMETERS (Version 11.0.0) ==========

// Session Configuration
input int    AsianStartHour    = 0;     
input int    AsianEndHour      = 8;     
input int    LondonEndHour     = 17;    

// Detection Parameters 
input ENUM_TIMEFRAMES RangeTF  = PERIOD_M5;  
input int    TouchTolerancePts = 50;    
input int    SwingBars         = 2;     
input int    FVGLookbackBars   = 10;    

// Entry Confirmation (Phase 3)
input int    MaxEntryDistancePts = 150;   

// Execution Mode (Phase 4)
input bool   SemiAutoMode      = false;   

// Risk Management & Cooldown (Phase 4)
input double RiskPerTrade      = 2.0;   
input double FixedLotSize      = 0.01;  
input int    StopLevelBuffer   = 2;     
input int    MaxDailyTrades    = 3;       
input double MaxDailyLoss      = 5.0;     
input int    DailyCooldownMinutes = 60;  

// Trend Filters (Phase 2)
input ENUM_TIMEFRAMES HTF_Timeframe   = PERIOD_H4; 
input int    ATRPeriod             = 14;          
input double ATRMultiplierSL       = 1.5;         
input double ATRMultiplierTP       = 2.0;         

// Confluence Filters (Phase 2)
input int    MinConfluenceChecks = 2;       
input bool   RequireFVG            = false;   
input bool   RequireVWAPBias       = false;   

// Volatility Adaptation (Phase 5 - NEW)
input int    MinRangePtsForHighVol = 500; // Min range size (in points) to consider the day highly volatile (e.g., 50 pips)
input int    ExtraConfluenceForHighVol = 1; // Extra confluence checks required during High Volatility

// Trading Management (Phase 4)
input int    BreakEvenTriggerR = 1;     
input bool   TrailAfterBE      = true;  
input int    TrailingStopPips  = 100;   

// Retest & Logging
input bool   EnableAlerts      = true;
input bool   EnableLogging     = true;
input bool   ShowRangeLines    = true;

//========== GLOBAL OBJECTS & RISK TRACKING VARIABLES ==========
CSessionRange *m_session = NULL;
CRetestCounter *m_retest = NULL;
SwingStructure *m_swing  = NULL;
FairValueGap *m_fvg      = NULL;
VWAPBias *m_vwap         = NULL; 

// Risk Tracking Variables
datetime m_lastTradeDay        = 0;       
int      m_dailyTradeCount     = 0;       
double   m_currentDailyPnL     = 0.0;     
datetime m_cooldownEndTime     = 0;       
bool     m_tradingBlocked      = false;   

//--- UTILITY FUNCTIONS (Implementations required to compile) ---

void Log(string message) { 
    if (EnableLogging) Print(message); 
}

void GenerateTradeSignal(bool isBuy, double entry, string setup, int current, int required) {
    if (EnableAlerts) {
        Alert(StringFormat("SIGNAL: %s Setup ready. Confluence %d/%d. Entry: %.5f", setup, current, required, entry));
    }
}

// FIX: 'isMoveUp' renamed to 'isBuy' to match function parameter
void ExecuteMarketOrder(bool isBuy, double entry) { 
    Log(StringFormat("EXECUTE: %s order at %.5f", isBuy ? "BUY" : "SELL", entry)); 
    // In a real EA, you would call Trade.Buy() or Trade.Sell() here
}

bool CheckRiskLimits() { 
    // Placeholder implementation 
    return true; 
} 

void CheckDailyReset() {
    // Placeholder implementation 
} 

//+------------------------------------------------------------------+
//| Detects current volatility regime based on Asian Range size      |
//+------------------------------------------------------------------+
ENUM_VOLATILITY_REGIME GetVolatilityRegime() {
    if (m_session == NULL || !m_session.IsValid()) return REGIME_LOW_VOL;
    
    // Get range in points (Range() returns price difference, divide by _Point)
    double rangeInPoints = m_session.GetRange() / _Point;
    
    if (rangeInPoints >= MinRangePtsForHighVol) {
        return REGIME_HIGH_VOL;
    } else {
        return REGIME_LOW_VOL;
    }
}

//+------------------------------------------------------------------+
//| TRADE TRIGGER LOGIC (UPDATED for Dynamic Confluence)             |
//+------------------------------------------------------------------+
void CheckTradeTriggers() {
    // HARD RISK GATES
    if (m_tradingBlocked) return; 

    // Safety checks for object pointers and trade criteria
    if (m_session == NULL || m_retest == NULL || m_swing == NULL || m_fvg == NULL || m_vwap == NULL) return;
    if (!m_session.IsValid() || !m_retest.HasNewTouch() || PositionSelect(_Symbol)) return;

    m_swing.UpdateStructure(); // Call the correct function name
    
    TouchEvent lastTouch;
    if (!m_retest.GetLastTouch(lastTouch)) return;
    
    // Determine the entry price and direction based on which range boundary was touched
    double entryPrice = SymbolInfoDouble(_Symbol, lastTouch.isHigh ? SYMBOL_ASK : SYMBOL_BID);
    bool isBuy = !lastTouch.isHigh; // If range High was touched, we SELL (isBuy=false). If Low was touched, we BUY (isBuy=true).
    
    int confluenceCount = 0;
    bool structureFlip = false;
    ENUM_TREND requiredTrend = isBuy ? TREND_BULLISH : TREND_BEARISH;
    string setupType = isBuy ? "BULLISH" : "BEARISH";
    
    // --- 1. Structure Flip (CHoCH) Check ---
    if (requiredTrend == TREND_BEARISH && (m_swing.isLowerLow || m_swing.isLowerHigh)) {
        structureFlip = true;
    } else if (requiredTrend == TREND_BULLISH && (m_swing.isHigherHigh || m_swing.isHigherLow)) {
        structureFlip = true;
    }

    if (!structureFlip) {
        m_retest.AcknowledgeTouch();
        return; 
    }
    
    Log(StringFormat("CHoCH detected for %s setup. Checking Entry Confirmation and Confluence Filters.", setupType));

    // --- 2. Entry Confirmation (Max Entry Distance) Filter ---
    // (Placeholder for distance check - logic omitted for brevity, assumes filter passes)

    // --- 3, 4, 5. Confluence Checks ---
    // FVG Check
    FVGInfo fvgInfo;
    if (RequireFVG && m_fvg.FVGExists(requiredTrend, fvgInfo)) {
        confluenceCount++;
        Log("Confluence Check 1: FVG Found.");
    }
    
    // VWAP Check
    if (RequireVWAPBias && m_vwap.GetBias() == requiredTrend) {
        confluenceCount++;
        Log("Confluence Check 2: VWAP Bias Confirmed.");
    }
    // HTF Trend Check (Assumed additional check if implemented)
    // if (GetHTFTrend() == requiredTrend) { confluenceCount++; }


    // --- 6. Multi-Confluence Aggregator (Dynamic Adjustment) ---
    int effectiveMinChecks = MinConfluenceChecks;
    ENUM_VOLATILITY_REGIME regime = GetVolatilityRegime();

    // Dynamic Adjustment (Phase 5)
    if (regime == REGIME_HIGH_VOL) {
        effectiveMinChecks += ExtraConfluenceForHighVol;
        Log(StringFormat("VOLATILITY REGIME: High Vol detected (Range: %.0f Pts). Increasing required checks to %d.", 
            m_session.GetRange() / _Point, effectiveMinChecks));
    }
    
    if (confluenceCount >= effectiveMinChecks) {
        
        if (SemiAutoMode) {
            // SEMI-AUTO MODE: Generate signal
            GenerateTradeSignal(isBuy, entryPrice, setupType, confluenceCount, effectiveMinChecks);
        } else {
            // FULLY-AUTO MODE: Execute trade
            Log(StringFormat("AGGREGATOR PASSED: %s setup executing. Confluence: %d/%d.", 
                setupType, confluenceCount, effectiveMinChecks));
            ExecuteMarketOrder(isBuy, entryPrice);
        }
    } else {
        Log(StringFormat("AGGREGATOR FAILED: Only %d/%d checks confirmed. Trade skipped. (Required: %d)", 
            confluenceCount, effectiveMinChecks, effectiveMinChecks));
    }
    
    m_retest.AcknowledgeTouch();
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() { 
    // --- 1. Initialize custom modules ---
    m_session = new CSessionRange(_Symbol, RangeTF, AsianStartHour, AsianEndHour, LondonEndHour);
    m_retest = new CRetestCounter(_Symbol, RangeTF, TouchTolerancePts);
    m_swing = new SwingStructure(_Symbol, RangeTF, SwingBars);
    m_fvg = new FairValueGap(_Symbol, RangeTF, FVGLookbackBars); 
    m_vwap = new VWAPBias(_Symbol, HTF_Timeframe, 20 * _Point); 

    // --- 2. Set Trade parameters ---
    Trade.SetExpertMagicNumber(123456);
    Trade.SetMarginMode();

    return(INIT_SUCCEEDED); 
}

//+------------------------------------------------------------------+
//| Expert deinitialization function (Cleanup)                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
    if (m_session != NULL) { delete m_session; m_session = NULL; }
    if (m_retest != NULL) { delete m_retest; m_retest = NULL; }
    if (m_swing != NULL) { delete m_swing; m_swing = NULL; }
    if (m_fvg != NULL) { delete m_fvg; m_fvg = NULL; }
    if (m_vwap != NULL) { delete m_vwap; m_vwap = NULL; }
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick() {
    // Check Daily Risk Reset and Cooldown Status
    CheckDailyReset();
    // CheckCooldownStatus(); // Placeholder if implemented

    // --- 1. Update Session Data (must run first) ---
    if (m_session != NULL) m_session.Update();
    
    // --- 2. Update Retest Counter ---
    if (m_retest != NULL && m_session != NULL && m_session.IsValid()) {
        m_retest.Update(m_session.GetHigh(), m_session.GetLow());
    }
    
    // --- 3. Check for trade setup ---
    CheckTradeTriggers();

    // --- 4. Manage open positions (BreakEven/Trailing Stop) ---
    // ManagePositions(); // Placeholder if implemented
}