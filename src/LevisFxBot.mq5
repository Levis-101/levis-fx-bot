//+------------------------------------------------------------------+
//| LevisFxBot.mq5                                                   |
//| Automated Asian Gold Trading System - Version 5.0.0              |
//| PHASE 2 COMPLETE: Multi-Confluence Aggregator Implemented        |
//+------------------------------------------------------------------+
#property copyright "Levis Mwaniki"
#property version   "5.0.0"
#property strict
#property description "Deterministic rule-based EA for XAUUSD Asian session (00:00-17:00)"

// --- PHASE 1 & 2 MODULES ---
#include <Trade\Trade.mqh>
#include <PositionInfo.mqh>
#include "SessionRange.mqh"
#include "RetestCounter.mqh"
#include "SwingStructure.mqh"
#include "FairValueGap.mqh"      // FVG Module
#include "VWAPBias.mqh"          // VWAP Module

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
input int    LondonEndHour     = 17;     // Trading stops after this hour

// Detection Parameters 
input ENUM_TIMEFRAMES RangeTF  = PERIOD_M5;  
input int    TouchTolerancePts = 50;     
input int    SwingBars         = 2;      
input int    FVGLookbackBars   = 10;     // Bars to check for FVG

// Risk Management & Execution (Phase 4/5)
input double RiskPerTrade      = 2.0;    // % of balance to risk per trade
input double FixedLotSize      = 0.01;   // Fallback lot size
input int    StopLevelBuffer   = 2;      // Extra pips buffer for SL

// Trend Filters (Phase 2)
input ENUM_TIMEFRAMES HTF_Timeframe   = PERIOD_H4; 
input int    ATRPeriod           = 14;         
input double ATRMultiplierSL     = 1.5;        
input double ATRMultiplierTP     = 2.0;        

// Confluence Filters (Phase 2 - Finalized)
input int    MinConfluenceChecks = 2;        // Minimum checks required to execute
input bool   RequireFVG          = false;    
input bool   RequireVWAPBias     = false;    

// Trading Management (Phase 4/5)
input int    BreakEvenTriggerR = 1;      // Move SL to BE at +1R
input bool   TrailAfterBE      = true;   
input int    TrailingStopPips  = 100;    

// Retest & Logging
input bool   EnableAlerts      = true;
input bool   EnableLogging     = true;
input bool   ShowRangeLines    = true;

//========== GLOBAL OBJECTS & VARIABLES ==========
CSessionRange *m_session = NULL;
CRetestCounter *m_retest = NULL;
SwingStructure *m_swing  = NULL;
FairValueGap *m_fvg      = NULL;
VWAPBias *m_vwap         = NULL; // <--- NEW VWAP Instance

ulong positionTicket = 0; 
double entryPrice, slPrice, tpPrice;

//+------------------------------------------------------------------+
//| UTILITY FUNCTIONS                                                |
//+------------------------------------------------------------------+
void Log(string message) {
    if (EnableLogging) PrintFormat("LevisFxBot | %s", message);
}

//+------------------------------------------------------------------+
//| Get High-Timeframe Trend (20 EMA bias)                           |
//+------------------------------------------------------------------+
ENUM_TREND GetHTFTrend() {
    int ma_handle = iEMA(_Symbol, HTF_Timeframe, 20, PRICE_CLOSE);
    if (ma_handle == INVALID_HANDLE) return TREND_NEUTRAL;
    double ma_buffer[1], close_buffer[1];
    if (CopyBuffer(ma_handle, 0, 1, 1, ma_buffer) != 1 || CopyClose(_Symbol, HTF_Timeframe, 1, 1, close_buffer) != 1) return TREND_NEUTRAL;
    
    return (close_buffer[0] > ma_buffer[0]) ? TREND_BULLISH : 
           (close_buffer[0] < ma_buffer[0]) ? TREND_BEARISH : TREND_NEUTRAL;
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
    
    double lotSize = riskAmount / valuePerLot;
    
    // Normalize Lot Size
    double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

    lotSize = MathMax(minLot, MathMin(maxLot, lotSize));
    lotSize = MathRound(lotSize / step) * step;
    
    return lotSize;
}

//+------------------------------------------------------------------+
//| Order Execution (ATR-based SL/TP & Dynamic Lot Size)             |
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
    double tpDistance = slDistance * (ATRMultiplierTP / ATRMultiplierSL); // R:R target
    double bufferPrice = StopLevelBuffer * _Point;

    // 2. Determine Final SL/TP Prices
    double slPrice, tpPrice;
    if (isLong) {
        slPrice = entry - slDistance - bufferPrice;
        tpPrice = entry + tpDistance;
    } else {
        slPrice = entry + slDistance + bufferPrice;
        tpPrice = entry - tpDistance;
    }
    
    // 3. Dynamic Lot Size Calculation
    double slInPriceUnits = MathAbs(entry - slPrice);
    double lots = CalculateLotSize(slInPriceUnits);
    
    if (lots < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN)) lots = FixedLotSize;
    
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
        Log(StringFormat("ORDER EXECUTED: %s %.2f @ %.5f. SL: %.5f TP: %.5f", 
            isLong ? "BUY" : "SELL", lots, entry, slPrice, tpPrice));
    }
}

// (The position management functions like TrailStop and CheckBreakEven are omitted for brevity but should be present)
// ...

//+------------------------------------------------------------------+
//| TRADE TRIGGER LOGIC (CHoCH + Multi-Confluence Aggregator)        |
//+------------------------------------------------------------------+
void CheckTradeTriggers() {
    if (!m_session.IsValid() || !m_retest.HasNewTouch() || PositionSelect(_Symbol)) return;

    m_swing.updateStructure(); 
    
    TouchEvent lastTouch;
    if (!m_retest.GetLastTouch(lastTouch)) return;
    double entryPrice = SymbolInfoDouble(_Symbol, lastTouch.isHigh ? SYMBOL_ASK : SYMBOL_BID);

    // Confluence variables
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
    
    Log(StringFormat("CHoCH detected for %s setup. Checking Confluence Filters.", setupType));


    // --- 2. HTF Trend Filter Check ---
    ENUM_TREND htfTrend = GetHTFTrend();
    if (htfTrend == TREND_NEUTRAL || htfTrend == requiredTrend) {
        confluenceCount++;
        Log("FILTER CONFIRMED: HTF Trend Aligned (Filter 1/3)");
    } else {
        Log(StringFormat("FILTER FAILED: HTF Trend Counter (HTF:%s, Req:%s)", EnumToString(htfTrend), EnumToString(requiredTrend)));
    }


    // --- 3. FVG Filter Check ---
    if (RequireFVG) {
        if (m_fvg.IsFVGPresent(entryPrice, requiredTrend, TouchTolerancePts)) {
            confluenceCount++;
            Log("FILTER CONFIRMED: FVG Present near entry (Filter 2/3)");
        } else {
            Log("FILTER FAILED: No FVG detected.");
        }
    } else {
        confluenceCount++; // Counts as confirmed if not required
    }


    // --- 4. VWAP Bias Filter Check ---
    if (RequireVWAPBias) {
        ENUM_TREND vwapBias = (ENUM_TREND)m_vwap.GetBias();
        if (vwapBias == TREND_NEUTRAL || vwapBias == requiredTrend) {
            confluenceCount++;
            Log("FILTER CONFIRMED: VWAP Bias Aligned (Filter 3/3)");
        } else {
            Log(StringFormat("FILTER FAILED: VWAP Bias Counter (VWAP:%s, Req:%s)", EnumToString(vwapBias), EnumToString(requiredTrend)));
        }
    } else {
        confluenceCount++; // Counts as confirmed if not required
    }
    
    
    // --- 5. Multi-Confluence Aggregator ---
    if (confluenceCount >= MinConfluenceChecks) {
        Log(StringFormat("AGGREGATOR PASSED: %d/%d checks confirmed. Executing %s.", 
            confluenceCount, MinConfluenceChecks, setupType));
        ExecuteMarketOrder(requiredTrend == TREND_BULLISH, entryPrice);
    } else {
        Log(StringFormat("AGGREGATOR FAILED: Only %d/%d checks confirmed. Trade skipped.", 
            confluenceCount, MinConfluenceChecks));
    }
    
    // Acknowledge touch regardless of trade result to move on to next bar
    m_retest.AcknowledgeTouch();
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {
    // --- Initialize Trading Class ---
    Trade.SetExpertMagicNumber(123456);
    Trade.SetMarginMode();

    // --- Initialize Custom Modules ---
    m_session = new CSessionRange(AsianStartHour, 0, AsianEndHour, 0); 
    m_session.SetTimeframe(RangeTF);
    m_session.SetSymbol(_Symbol);

    m_retest = new CRetestCounter(TouchTolerancePts, 1); 
    m_retest.SetTimeframe(RangeTF);

    m_swing = new SwingStructure(RangeTF, SwingBars, _Symbol);
    
    m_fvg = new FairValueGap(RangeTF, FVGLookbackBars, _Symbol); 
    
    m_vwap = new VWAPBias(_Symbol); // <--- NEW VWAP INIT

    Log("=== LevisFxBot Initialized (Trading Enabled) === Version 5.0.0");
    Log(StringFormat("Phase 2 Aggregator: Min Checks Required = %d", MinConfluenceChecks));
    
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
    if(m_fvg != NULL) delete m_fvg;
    if(m_vwap != NULL) delete m_vwap; // <--- NEW VWAP CLEANUP
    Comment(""); 
}

//+------------------------------------------------------------------+
//| Expert tick function (The core loop)                             |
//+------------------------------------------------------------------+
void OnTick() {
    if (m_session == NULL || m_retest == NULL || m_swing == NULL || m_fvg == NULL || m_vwap == NULL) return; 

    // 1. Calculate/recalculate session range
    if(m_session.CalculateRange()) {
        m_retest.SetLevels(m_session.GetHigh(), m_session.GetLow());
        m_retest.Reset();
        // Log(m_session.GetInfo()); // Optional logging
    }
    
    // 2. Check for new touches/retests
    m_retest.CheckForTouches(10);
    
    // 3. Check for trade triggers (applies all filters)
    CheckTradeTriggers();

    // 4. Manage existing position (BreakEven/Trailing - Phase 4)
    // TrailStop();
    // CheckBreakEven();
}
//+------------------------------------------------------------------+
