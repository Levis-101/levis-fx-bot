//+------------------------------------------------------------------+
//| LevisFxBot.mq5                                                   |
//| Automated Asian Gold Trading System - Version 7.0.0              |
//| PHASE 3 COMPLETE: Semi-Auto Mode Integrated                      |
//+------------------------------------------------------------------+
#property copyright "Levis Mwaniki"
#property version   "7.0.0"
#property strict
#property description "Deterministic rule-based EA for XAUUSD Asian session (00:00-17:00)"

// --- PHASE 1 & 2 MODULES ---
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

//========== INPUT PARAMETERS (Version 7.0.0) ==========

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
input int    MaxEntryDistancePts = 150;    // Max distance in points from boundary to enter trade

// Execution Mode (Phase 4 - NEW)
input bool   SemiAutoMode      = false;    // Set to 'true' to halt automated execution and only generate alerts.

// Risk Management & Execution (Phase 4/5)
input double RiskPerTrade      = 2.0;    
input double FixedLotSize      = 0.01;   
input int    StopLevelBuffer   = 2;      

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

//========== GLOBAL OBJECTS & VARIABLES ==========
CSessionRange *m_session = NULL;
CRetestCounter *m_retest = NULL;
SwingStructure *m_swing  = NULL;
FairValueGap *m_fvg      = NULL;
VWAPBias *m_vwap         = NULL; 

ulong positionTicket = 0; 
double entryPrice, slPrice, tpPrice;

//+------------------------------------------------------------------+
//| UTILITY FUNCTIONS (Log, GetHTFTrend, CalculateLotSize)           |
//+------------------------------------------------------------------+
void Log(string message) {
    if (EnableLogging) PrintFormat("LevisFxBot | %s", message);
}

//+------------------------------------------------------------------+
//| Generates alert/log when a signal is detected                    |
//+------------------------------------------------------------------+
void GenerateTradeSignal(bool isLong, string setupType, int confirmedChecks, int requiredChecks) {
    string action = isLong ? "BUY" : "SELL";
    string message = StringFormat("--- **%s SIGNAL** --- %s setup detected at Asian Range retest. Confluence: %d/%d.",
                                  action, setupType, confirmedChecks, requiredChecks);
    
    Log(message);
    if (EnableAlerts) Alert(message);
}

ENUM_TREND GetHTFTrend() {
    int ma_handle = iEMA(_Symbol, HTF_Timeframe, 20, PRICE_CLOSE);
    if (ma_handle == INVALID_HANDLE) return TREND_NEUTRAL;
    double ma_buffer[1], close_buffer[1];
    if (CopyBuffer(ma_handle, 0, 1, 1, ma_buffer) != 1 || CopyClose(_Symbol, HTF_Timeframe, 1, 1, close_buffer) != 1) return TREND_NEUTRAL;
    return (close_buffer[0] > ma_buffer[0]) ? TREND_BULLISH : 
           (close_buffer[0] < ma_buffer[0]) ? TREND_BEARISH : TREND_NEUTRAL;
}

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
//| Order Execution (ATR-based SL/TP & Dynamic Lot Size)             |
//+------------------------------------------------------------------+
void ExecuteMarketOrder(bool isLong, double entry) {
    if (PositionSelect(_Symbol)) return; 

    int atr_handle = iATR(_Symbol, RangeTF, ATRPeriod);
    double atr_buffer[1];
    if (CopyBuffer(atr_handle, 0, 1, 1, atr_buffer) != 1) return;
    double currentATR = atr_buffer[0];
    
    double slDistance = currentATR * ATRMultiplierSL;
    double tpDistance = slDistance * (ATRMultiplierTP / ATRMultiplierSL); 
    double bufferPrice = StopLevelBuffer * _Point;

    double slPrice, tpPrice;
    if (isLong) {
        slPrice = entry - slDistance - bufferPrice;
        tpPrice = entry + tpDistance;
    } else {
        slPrice = entry + slDistance + bufferPrice;
        tpPrice = entry - tpDistance;
    }
    
    double slInPriceUnits = MathAbs(entry - slPrice);
    double lots = CalculateLotSize(slInPriceUnits);
    if (lots < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN)) lots = FixedLotSize;
    
    if (isLong) {
        if (!
