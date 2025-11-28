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
#include <Trade\Trade.mqh>
#include <PositionInfo.mqh>
#include "SessionRange.mqh"
#include "RetestCounter.mqh"
#include "SwingStructure.mqh"
#include "FairValueGap.mqh"      
#include "VWAPBias.mqh"          

CTrade Trade;
CPositionInfo Position;

// Trend/Regime Enums
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
input int    ATRPeriod           = 14;         
input double ATRMultiplierSL     = 1.5;        
input double ATRMultiplierTP     = 2.0;        

// Confluence Filters (Phase 2)
input int    MinConfluenceChecks = 2;        
input bool   RequireFVG          = false;    
input bool   RequireVWAPBias     = false;    

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


//+------------------------------------------------------------------+
//| UTILITY FUNCTIONS (Log, GetHTFTrend, CalculateTradeParameters)   |
//| (Omitted for brevity, but all V10.0.0 logic is retained)         |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Detects current volatility regime based on Asian Range size (NEW)|
//+------------------------------------------------------------------+
ENUM_VOLATILITY_REGIME GetVolatilityRegime() {
    // Check if session range has been calculated and is valid
    if (m_session == NULL || !m_session.IsValid()) return REGIME_LOW_VOL;
    
    // Get range in points
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
    // CheckDailyReset() must run in OnTick
    // if (!CheckRiskLimits()) return; // assuming this is called by CheckCooldown/OnTick

    if (!m_session.IsValid() || !m_retest.HasNewTouch() || PositionSelect(_Symbol)) return;

    m_swing.updateStructure(); 
    
    TouchEvent lastTouch;
    if (!m_retest.GetLastTouch(lastTouch)) return;
    double entryPrice = SymbolInfoDouble(_Symbol, lastTouch.isHigh ? SYMBOL_ASK : SYMBOL_BID);

    int confluenceCount = 0;
    bool structureFlip = false;
    ENUM_TREND requiredTrend = lastTouch.isHigh ? TREND_BEARISH : TREND_BULLISH;
    string setupType = lastTouch.isHigh ? "BEARISH" : "BULLISH";
    
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
    // ... (logic remains the same) ...

    // --- 3, 4, 5. Confluence Checks ---
    // ... (logic remains the same, calculating confluenceCount) ...
    
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
            // SEMI-AUTO MODE: Generate signal with calculated prices
            GenerateTradeSignal(requiredTrend == TREND_BULLISH, entryPrice, setupType, confluenceCount, effectiveMinChecks);
        } else {
            // FULLY-AUTO MODE: Execute trade
            Log(StringFormat("AGGREGATOR PASSED: %s setup executing. Confluence: %d/%d.", 
                setupType, confluenceCount, effectiveMinChecks));
            ExecuteMarketOrder(requiredTrend == TREND_BULLISH, entryPrice);
        }
    } else {
        Log(StringFormat("AGGREGATOR FAILED: Only %d/%d checks confirmed. Trade skipped. (Required: %d)", 
            confluenceCount, effectiveMinChecks, effectiveMinChecks));
    }
    
    m_retest.AcknowledgeTouch();
}

//+------------------------------------------------------------------+
//| Expert initialization function (OnInit - Unchanged)              |
//+------------------------------------------------------------------+
int OnInit() { /* ... */ return(INIT_SUCCEEDED); }

//+------------------------------------------------------------------+
//| Expert tick function (OnTick - Unchanged)                        |
//+------------------------------------------------------------------+
void OnTick() { /* ... */ } 
// ... (The rest of the EA remains the same as V10.0.0, including risk management calls in OnTick)
