//+------------------------------------------------------------------+
//| LevisFxBot.mq5                                                   |
//| Automated Asian Gold Trading System - Version 10.0.0             |
//| PHASE 4: Semi-Auto Signal Enhanced with SL/TP/Lot Size           |
//+------------------------------------------------------------------+
#property copyright "Levis Mwaniki"
#property version   "10.0.0"
#property strict
#property description "Deterministic rule-based EA for XAUUSD Asian session (00:00-17:00)"

// --- PHASE 1, 2, 3 MODULES ---
#include <Trade\Trade.mqh>
#include <PositionInfo.mqh>
#include "SessionRange.mqh"
#include "RetestCounter.mqh"
#include "SwingStructure.mqh"
#include "FairValueGap.mqh"      
#include "VWAPBias.mqh"          

CTrade Trade;
CPositionInfo Position;

// Trend Enum for Clarity
enum ENUM_TREND {
    TREND_BULLISH = 1,
    TREND_BEARISH = -1,
    TREND_NEUTRAL = 0
};

//========== INPUT PARAMETERS (Version 10.0.0) ==========

// Session Configuration
input int    AsianStartHour    = 0;      
input int    AsianEndHour      = 8;      
input int    LondonEndHour     = 17;     // Time to close all open positions

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
input int    StopLevelBuffer   = 2;      // Buffer points for SL/BE
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

// Trading Management (Phase 4)
input int    BreakEvenTriggerR = 1;      // Move SL to BE at +1R
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
//| UTILITY FUNCTIONS                                                |
//+------------------------------------------------------------------+
void Log(string message) {
    if (EnableLogging) PrintFormat("LevisFxBot | %s", message);
}

//+------------------------------------------------------------------+
//| Helper: Calculate Lot Size (Dynamic Risk)                        |
//| (Logic remains the same as previous versions)                    |
//+------------------------------------------------------------------+
double CalculateLotSize(double slInPriceUnits) {
    if (slInPriceUnits <= 0) return FixedLotSize;
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double riskAmount = balance * (RiskPerTrade / 100.0);
    double valuePerLot = MarketInfo(_Symbol, MODE_TICKVALUE) * (slInPriceUnits / MarketInfo(_Symbol, MODE_TICKSIZE));
    double lotSize = riskAmount / valuePerLot;
    double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    lotSize = MathMax(minLot, MathMin(maxLot, lotSize));
    lotSize = MathRound(lotSize / step) * step;
    return lotSize;
}

//+------------------------------------------------------------------+
//| Helper: Calculates SL, TP, and Lot size based on ATR and Risk    |
//| (NEW function to centralize calculations)                        |
//+------------------------------------------------------------------+
bool CalculateTradeParameters(bool isLong, double entry, double &slPrice, double &tpPrice, double &lots) {
    // 1. Calculate ATR for Volatility-Adjusted SL
    int atr_handle = iATR(_Symbol, RangeTF, ATRPeriod);
    double atr_buffer[1];
    if (CopyBuffer(atr_handle, 0, 1, 1, atr_buffer) != 1) {
        // Log("ERROR: Failed to get ATR data."); // Keep logging minimal here
        return false;
    }
    double currentATR = atr_buffer[0];
    
    // Calculate SL distance based on ATR
    double slDistance = currentATR * ATRMultiplierSL;
    double tpDistance = slDistance * (ATRMultiplierTP / ATRMultiplierSL); // R:R target
    double bufferPrice = StopLevelBuffer * _Point;

    // 2. Determine Final SL/TP Prices
    if (isLong) {
        slPrice = entry - slDistance - bufferPrice;
        tpPrice = entry + tpDistance;
    } else {
        slPrice = entry + slDistance + bufferPrice;
        tpPrice = entry - tpDistance;
    }
    
    // 3. Dynamic Lot Size Calculation
    double slInPriceUnits = MathAbs(entry - slPrice);
    lots = CalculateLotSize(slInPriceUnits);
    
    if (lots < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN)) lots = FixedLotSize;
    
    // 4. Normalize prices
    slPrice = NormalizeDouble(slPrice, _Digits);
    tpPrice = NormalizeDouble(tpPrice, _Digits);
    
    return true;
}


//+------------------------------------------------------------------+
//| Generates alert/log when a signal is detected (UPDATED)          |
//| Now includes calculated SL/TP/Lot Size                           |
//+------------------------------------------------------------------+
void GenerateTradeSignal(bool isLong, double entryPrice, string setupType, int confirmedChecks, int requiredChecks) {
    double slPrice, tpPrice, lots;
    
    // Calculate the necessary trade parameters for the alert
    if (!CalculateTradeParameters(isLong, entryPrice, slPrice, tpPrice, lots)) {
        Log("ERROR: Failed to calculate trade parameters for signal. Generating minimal alert.");
        string action = isLong ? "BUY" : "SELL";
        string message = StringFormat("--- **%s SIGNAL READY** --- Entry: %.5f. Confluence: %d/%d.",
                                      action, entryPrice, confirmedChecks, requiredChecks);
        if (EnableAlerts) Alert(message);
        return;
    }

    string action = isLong ? "BUY" : "SELL";
    string message = StringFormat("--- **%s SIGNAL READY** --- %s setup detected at %.5f.\n", action, setupType, entryPrice);
    message += StringFormat("CONFLUENCE: %d/%d checks confirmed.\n", confirmedChecks, requiredChecks);
    message += StringFormat("ATR-BASED TARGETS (%.1f:%.1f R:R):\n", ATRMultiplierTP, ATRMultiplierSL);
    message += StringFormat("  > ENTRY: %.5f\n", entryPrice);
    message += StringFormat("  > SL: %.5f\n", slPrice);
    message += StringFormat("  > TP: %.5f\n", tpPrice);
    message += StringFormat("LOT SIZE (%.2f%% Risk): %.2f", RiskPerTrade, lots);
    
    Log(message);
    if (EnableAlerts) Alert(message);
}

//+------------------------------------------------------------------+
//| Order Execution (UPDATED to use CalculateTradeParameters)        |
//+------------------------------------------------------------------+
void ExecuteMarketOrder(bool isLong, double entry) {
    if (PositionSelect(_Symbol)) return; 

    double slPrice, tpPrice, lots;
    if (!CalculateTradeParameters(isLong, entry, slPrice, tpPrice, lots)) {
        Log("ERROR: Cannot execute trade. Failed to calculate parameters.");
        return;
    }
    
    if (isLong) {
        if (!Trade.Buy(lots, _Symbol, entry, slPrice, tpPrice)) Log(StringFormat("Buy failed. Error: %d", Trade.ResultDeal()));
    } else {
        if (!Trade.Sell(lots, _Symbol, entry, slPrice, tpPrice)) Log(StringFormat("Sell failed. Error: %d", Trade.ResultDeal()));
    }
    
    if (Trade.ResultRetcode() == TRADE_RETCODE_DONE) {
        Log(StringFormat("ORDER EXECUTED: %s %.2f @ %.5f. SL: %.5f TP: %.5f", 
            isLong ? "BUY" : "SELL", lots, entry, slPrice, tpPrice));
        // INCREMENT TRADE COUNT AFTER SUCCESSFUL EXECUTION
        m_dailyTradeCount++;
    } else {
        Log(StringFormat("Order failed. Error: %d", Trade.ResultDeal()));
    }
}

// (GetHTFTrend, CheckDailyReset, CheckRiskLimits, CheckCooldown, GetOpenPosition, CheckBreakEven, TrailStop, CheckTimeExit omitted for brevity, but must be present from V9.0.0)
// ...

//+------------------------------------------------------------------+
//| TRADE TRIGGER LOGIC (UPDATED to pass entryPrice)                 |
//+------------------------------------------------------------------+
void CheckTradeTriggers() {
    // HARD RISK GATES
    if (m_tradingBlocked) return; 
    // CheckDailyReset() must run in OnTick
    if (!CheckRiskLimits()) return; 

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
    
    // --- 6. Multi-Confluence Aggregator ---
    
    if (confluenceCount >= MinConfluenceChecks) {
        
        if (SemiAutoMode) {
            // SEMI-AUTO MODE: Generate signal with calculated prices
            GenerateTradeSignal(requiredTrend == TREND_BULLISH, entryPrice, setupType, confluenceCount, MinConfluenceChecks);
        } else {
            // FULLY-AUTO MODE: Execute trade
            Log(StringFormat("AGGREGATOR PASSED: %s setup executing. Confluence: %d/%d.", 
                setupType, confluenceCount, MinConfluenceChecks));
            ExecuteMarketOrder(requiredTrend == TREND_BULLISH, entryPrice);
        }
    } else {
        Log(StringFormat("AGGREGATOR FAILED: Only %d/%d checks confirmed. Trade skipped.", 
            confluenceCount, MinConfluenceChecks));
    }
    
    m_retest.AcknowledgeTouch();
}

//+------------------------------------------------------------------+
//| Expert initialization function (OnInit - Unchanged)              |
//+------------------------------------------------------------------+
int OnInit() { /* ... */ return(INIT_SUCCEEDED); }

//+------------------------------------------------------------------+
//| Expert deinitialization function (OnDeinit - Unchanged)          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) { /* ... */ }


//+------------------------------------------------------------------+
//| Expert tick function (OnTick - Unchanged)                        |
//+------------------------------------------------------------------+
void OnTick() {
    if (m_session == NULL || m_retest == NULL || m_swing == NULL || m_fvg == NULL || m_vwap == NULL) return; 

    // --- PHASE 4: RISK & COOLDOWN MANAGEMENT ---
    // Assume CheckDailyReset() and CheckCooldown() are called here
    
    // 1. Calculate/recalculate session range
    // ...
    
    // 2. Check for new touches/retests
    // ...
    
    // 3. Check for trade triggers
    CheckTradeTriggers();

    // 4. Manage existing position
    if (!SemiAutoMode) {
        // CheckBreakEven();
        // TrailStop();
        // CheckTimeExit();
    }
}
//+------------------------------------------------------------------+
