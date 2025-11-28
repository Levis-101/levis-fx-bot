//+------------------------------------------------------------------+
//| LevisFxBot.mq5                                                   |
//| Automated Asian Gold Trading System - Phase 1: Core Detection    |
//| Alerts-only prototype: Session range + retest counter            |
//| FIX: Integrated modular classes & Implemented Two-Phase Logic    |
//+------------------------------------------------------------------+
#property copyright "Levis Mwaniki"
#property version   "1.1.0"
#property strict
#property description "Deterministic rule-based EA for XAUUSD Asian session (00:00-17:00)"

#include <Trade\Trade.mqh>
#include "SessionRange.mqh"   // NEW: Session Range Class
#include "RetestCounter.mqh"  // NEW: Retest Counter Class
#include "SwingStructure.mqh" // NEW: Structure Class (for future use)

//========== INPUT PARAMETERS ==========

// Session Configuration
input int    AsianStartHour    = 0;      // Asian session start (server time)
input int    AsianStartMinute  = 0;
input int    AsianEndHour      = 8;      // Asian session end (server time)
input int    AsianEndMinute    = 0;
input int    LondonEndHour     = 17;     // NEW: Trading stops after this hour (End of London)

// Detection Parameters
input int    TouchTolerancePts = 50;     // Touch tolerance in points
input int    MinConfirmBars    = 1;      // Candles to confirm touch
input ENUM_TIMEFRAMES RangeTF  = PERIOD_M5;  // Timeframe for range calc

// Retest & Logging
input int    MaxRetestsToTrack = 5;      // Max retest count to track (handled in CRetestCounter)
input bool   EnableAlerts      = true;
input bool   EnableLogging     = true;

// Chart Display
input bool   ShowRangeLines    = true;   // Display Asian High/Low lines
input color  HighLineColor     = clrRed;
input color  LowLineColor      = clrBlue;
input ENUM_LINE_STYLE LineStyle = STYLE_SOLID;
input int    LineWidth         = 2;
input color  SessionBoxColor   = clrYellow;

//========== GLOBAL OBJECTS ==========

// Class Instances
CSessionRange *m_session = NULL;
CRetestCounter *m_retest = NULL;
SwingStructure *m_swing  = NULL; // Swing structure for future use (Phase 3)

// Chart Objects
string objHighLine = "AsianHighLine";
string objLowLine = "AsianLowLine";
string objSessionBox = "AsianSessionBox";
string objComment = "BotInfoComment";

//+------------------------------------------------------------------+
//| Logging Function                                                 |
//+------------------------------------------------------------------+
void Log(string message) {
    if (EnableLogging) PrintFormat("LevisFxBot | %s", message);
}

//+------------------------------------------------------------------+
//| Chart Drawing Functions                                          |
//+------------------------------------------------------------------+
void DrawRangeLines() {
    if(m_session == NULL || !m_session.IsValid()) return;
    
    // Draw High Line
    if (ObjectFind(0, objHighLine) == -1) {
        ObjectCreate(0, objHighLine, OBJ_HLINE, 0, 0, m_session.GetSessionHigh());
        ObjectSetInteger(0, objHighLine, OBJPROP_COLOR, HighLineColor);
        ObjectSetInteger(0, objHighLine, OBJPROP_STYLE, LineStyle);
        ObjectSetInteger(0, objHighLine, OBJPROP_WIDTH, LineWidth);
        ObjectSetString(0, objHighLine, OBJPROP_TEXT, "Asian High");
    } else {
        ObjectSetDouble(0, objHighLine, OBJPROP_PRICE, m_session.GetSessionHigh());
    }

    // Draw Low Line
    if (ObjectFind(0, objLowLine) == -1) {
        ObjectCreate(0, objLowLine, OBJ_HLINE, 0, 0, m_session.GetSessionLow());
        ObjectSetInteger(0, objLowLine, OBJPROP_COLOR, LowLineColor);
        ObjectSetInteger(0, objLowLine, OBJPROP_STYLE, LineStyle);
        ObjectSetInteger(0, objLowLine, OBJPROP_WIDTH, LineWidth);
        ObjectSetString(0, objLowLine, OBJPROP_TEXT, "Asian Low");
    } else {
        ObjectSetDouble(0, objLowLine, OBJPROP_PRICE, m_session.GetSessionLow());
    }
}

void DrawSessionBox() {
    if(m_session == NULL || !m_session.IsValid()) return;
    
    // Draw session box from start to end time
    if (ObjectFind(0, objSessionBox) == -1) {
        ObjectCreate(0, objSessionBox, OBJ_RECTANGLE, 0, m_session.GetSessionStart(), m_session.GetSessionHigh(), m_session.GetSessionEnd(), m_session.GetSessionLow());
        ObjectSetInteger(0, objSessionBox, OBJPROP_FILL, 1);
        ObjectSetInteger(0, objSessionBox, OBJPROP_BACK, 1);
        ObjectSetInteger(0, objSessionBox, OBJPROP_COLOR, SessionBoxColor);
        ObjectSetInteger(0, objSessionBox, OBJPROP_STYLE, STYLE_DOT);
        ObjectSetInteger(0, objSessionBox, OBJPROP_WIDTH, 1);
        ObjectSetInteger(0, objSessionBox, OBJPROP_ALPHA, 20); // Make it translucent
    } else {
        // Update box coordinates (important for the Asian session's dynamic range)
        ObjectSetInteger(0, objSessionBox, OBJPROP_TIME1, m_session.GetSessionStart());
        ObjectSetDouble(0, objSessionBox, OBJPROP_PRICE1, m_session.GetSessionHigh());
        ObjectSetInteger(0, objSessionBox, OBJPROP_TIME2, m_session.GetSessionEnd());
        ObjectSetDouble(0, objSessionBox, OBJPROP_PRICE2, m_session.GetSessionLow());
    }
}

void UpdateChartInfo() {
    // 1. Draw/Update Lines & Box
    DrawRangeLines();
    DrawSessionBox();
    
    // 2. Update status comment on chart
    string commentText = "=== LevisFxBot v1.1 ===\n";
    
    // Session Status
    if (m_session.IsActive()) {
        commentText += "Status: RANGE BUILDING (Asian)\n";
    } else if (m_session.IsValid()) {
        commentText += "Status: RETEST HUNTING (London)\n";
    } else {
        commentText += StringFormat("Status: COOLDOWN. Resumes at %02d:00.\n", AsianStartHour);
    }
    
    // Session Data
    if (m_session.IsValid()) {
        commentText += StringFormat("Asian Range: %.2f Pips\n", m_session.GetRange() / _Point);
        commentText += m_session.GetInfo() + "\n";
        commentText += m_retest.GetInfo();
    }
    
    Comment(commentText);
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {
    // --- Initialize Classes ---
    // Session class handles its own internal time/symbol/timeframe setup
    m_session = new CSessionRange(AsianStartHour, AsianStartMinute, AsianEndHour, AsianEndMinute, RangeTF, _Symbol);
    
    // Retest class needs tolerance and confirmation settings
    m_retest = new CRetestCounter(TouchTolerancePts, MinConfirmBars);
    
    // Swing class (for future use in Phase 3)
    m_swing = new SwingStructure();

    Log("=== LevisFxBot Initialized === (Two-Phase Logic Active)");
    Log(StringFormat("Trading Window: %02d:00 to %02d:00 Server Time", AsianStartHour, LondonEndHour));
    
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
    Log("=== LevisFxBot Shut Down ===");
    
    // Clean up chart objects
    if(ShowRangeLines) {
        ObjectDelete(0, objHighLine);
        ObjectDelete(0, objLowLine);
        ObjectDelete(0, objSessionBox);
    }
    
    // Cleanup Classes
    if(m_session != NULL) delete m_session;
    if(m_retest != NULL) delete m_retest;
    if(m_swing != NULL) delete m_swing;
    
    Comment(""); // Clear chart comment
}

//+------------------------------------------------------------------+
//| Expert tick function (The core logic)                            |
//+------------------------------------------------------------------+
void OnTick() {
    if (m_session == NULL || m_retest == NULL) return; 

    datetime now = TimeCurrent();
    MqlDateTime dt;
    TimeToStruct(now, dt);

    // --- PHASE 3: DAILY COOLDOWN/RESET ---
    if (dt.hour >= LondonEndHour) {
        if (m_session.IsValid()) {
             Log(StringFormat("--- End of Trading Window (%02d:00). Resetting for next session. ---", LondonEndHour));
             m_session.Reset(); // Clear session data
             m_retest.Reset();  // Clear retest counts
        }
        // Always stop processing for the day
        if(ShowRangeLines) Comment(StringFormat("LevisFxBot: COOLDOWN. Trading resumes at %02d:00.", AsianStartHour));
        return; 
    }

    // --- PHASE 1: ASIAN SESSION (BUILD RANGE) ---
    if (dt.hour >= AsianStartHour && dt.hour < AsianEndHour) {
        
        // 1. Dynamic Range Calculation
        m_session.Calculate();
        
        // 2. Set Retest Levels Dynamically (needed for visual retest tracking)
        m_retest.SetLevels(m_session.GetSessionHigh(), m_session.GetSessionLow());
        
        // Log(m_session.GetInfo()); // Optional: spam log to see range build

    } 
    // --- PHASE 2: LONDON SESSION (HUNT RETESTS) ---
    else if (dt.hour >= AsianEndHour && dt.hour < LondonEndHour) {
        
        // Ensure range was set during Asian hours
        if (!m_session.IsValid()) {
            // This case handles the bot starting during London hours
            Log("WARNING: Trading window is open, but Asian session range was not set. Awaiting next session.");
            return;
        }

        // 1. Levels are locked (m_session.Calculate() is NOT called)
        
        // 2. Check for new touches/retests on the locked levels
