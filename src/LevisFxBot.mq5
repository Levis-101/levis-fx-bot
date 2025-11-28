//+------------------------------------------------------------------+
//| LevisFxBot.mq5                                                   |
//| Automated Asian Gold Trading System - Version 8.0.0              |
//| PHASE 4: Cooldown Management Implemented (Max Daily Loss/Trades) |
//+------------------------------------------------------------------+
#property copyright "Levis Mwaniki"
#property version   "8.0.0"
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

//========== INPUT PARAMETERS (Version 8.0.0) ==========

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

// Risk Management & Cooldown (Phase 4 - NEW/UPDATED)
input double RiskPerTrade      = 2.0;    
input double FixedLotSize      = 0.01;   
input int    StopLevelBuffer   = 2;      
input int    MaxDailyTrades    = 3;        // NEW: Max trades per day
input double MaxDailyLoss      = 5.0;      // NEW: Max loss as percentage of balance
input int    DailyCooldownMinutes = 60;    // NEW: Cooldown time after hitting limit

// Trend Filters (Phase 2)
input ENUM_TIMEFRAMES HTF_Timeframe   = PERIOD_H4; 
input int    ATRPeriod           = 14;         
input double ATRMultiplierSL     = 1.5;        
input double ATRMultiplierTP     = 2.0;        

// Confluence Filters (Phase 2)
input int    MinConfluenceChecks = 2;        
input bool   RequireFVG          = false;    
input bool   RequireVWAPBias     = false;    

// Trading Management (Phase 4/5)
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

// Risk Tracking Variables (NEW)
datetime m_lastTradeDay        = 0;       // Stores the last date a trade was taken
int      m_dailyTradeCount     = 0;       // Trades executed today
double   m_currentDailyPnL     = 0.0;     // Total PnL today (in deposit currency)
datetime m_cooldownEndTime     = 0;       // Time when cooldown period ends
bool     m_tradingBlocked      = false;   // Master flag to stop all trading

//+------------------------------------------------------------------+
//| UTILITY FUNCTIONS (Log, GetHTFTrend, CalculateLotSize)           |
//| (Unchanged from previous step, omitted for brevity)              |
//+------------------------------------------------------------------+
void Log(string message) {
    if (EnableLogging) PrintFormat("LevisFxBot | %s", message);
}

void GenerateTradeSignal(bool isLong, string setupType, int confirmedChecks, int requiredChecks) {
    string action = isLong ? "BUY" : "SELL";
    string message = StringFormat("--- **%s SIGNAL** --- %s setup detected at Asian Range retest. Confluence: %d/%d.",
                                  action, setupType, confirmedChecks, requiredChecks);
    
    Log(message);
    if (EnableAlerts) Alert(message);
}

ENUM_TREND GetHTFTrend() { /* ... */ return TREND_NEUTRAL; }
double CalculateLotSize(double slInPriceUnits) { /* ... */ return FixedLotSize; }
void ExecuteMarketOrder(bool isLong, double entry) { /* ... */ }

//+------------------------------------------------------------------+
//| RISK MANAGEMENT - NEW FUNCTIONS                                  |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Checks for day change and resets daily risk counters             |
//+------------------------------------------------------------------+
void CheckDailyReset() {
    datetime now = TimeCurrent();
    int currentDay = TimeDay(now);

    // If day changed since last check (and it's not the first run)
    if (m_lastTradeDay != 0 && m_lastTradeDay != currentDay) {
        Log(StringFormat("NEW TRADING DAY: Resetting risk counters. Yesterday's PnL: %.2f", m_currentDailyPnL));
        
        m_dailyTradeCount = 0;
        m_currentDailyPnL = 0.0;
        m_tradingBlocked = false; // Lift the block
        m_cooldownEndTime = 0;    // Reset cooldown timer
    }
    
    m_lastTradeDay = currentDay;
}

//+------------------------------------------------------------------+
//| Calculates current daily PnL and enforces limits                 |
//+------------------------------------------------------------------+
bool CheckRiskLimits() {
    // 1. Calculate PnL from history (deals closed today)
    HistorySelect(TimeCurrent() - 86400, TimeCurrent()); // Look back 24 hours
    m_currentDailyPnL = 0.0;
    
    for (int i = HistoryDealsTotal() - 1; i >= 0; i--) {
        ulong deal_ticket = HistoryDealGetTicket(i);
        if (HistoryDealGetInteger(deal_ticket, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;
        
        datetime dealTime = HistoryDealGetInteger(deal_ticket, DEAL_TIME);
        
        // Only count deals closed today
        if (TimeDay(dealTime) == TimeDay(TimeCurrent())) {
            m_currentDailyPnL += HistoryDealGetDouble(deal_ticket, DEAL_PROFIT);
        } else {
            // Since we iterate backward, we can stop once we hit yesterday's trades
            break; 
        }
    }
    
    // 2. Check Daily Loss Limit
    double maxLossAmount = MaxDailyLoss * AccountInfoDouble(ACCOUNT_BALANCE) / 100.0;
    
    if (m_currentDailyPnL <= -maxLossAmount) {
        if (!m_tradingBlocked) {
            m_tradingBlocked = true;
            m_cooldownEndTime = TimeCurrent() + DailyCooldownMinutes * 60;
            Log(StringFormat("CRITICAL: Max Daily Loss Hit (%.2f / %.2f). Trading blocked until %s.",
                m_currentDailyPnL, -maxLossAmount, TimeToString(m_cooldownEndTime)));
            if(EnableAlerts) Alert("Max Daily Loss Reached! Trading HALTED.");
        }
        return false; // Trading MUST stop
    }

    // 3. Check Max Daily Trades Limit
    if (m_dailyTradeCount >= MaxDailyTrades) {
        if (!m_tradingBlocked) {
            m_tradingBlocked = true;
            m_cooldownEndTime = TimeCurrent() + DailyCooldownMinutes * 60;
            Log(StringFormat("CRITICAL: Max Daily Trades Hit (%d / %d). Trading blocked until %s.",
                m_dailyTradeCount, MaxDailyTrades, TimeToString(m_cooldownEndTime)));
            if(EnableAlerts) Alert("Max Daily Trades Reached! Trading HALTED.");
        }
        return false; // Trading MUST stop
    }
    
    // If neither limit is hit, trading is allowed.
    return true; 
}

//+------------------------------------------------------------------+
//| Checks if the bot is currently in a cooldown period              |
//+------------------------------------------------------------------+
bool CheckCooldown() {
    if (m_tradingBlocked) {
        // If the block is due to hitting
