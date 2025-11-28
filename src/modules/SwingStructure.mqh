//+------------------------------------------------------------------+
//| SwingStructure.mqh                                                |
//| Module: Advanced Swing Structure Detection                       |
//| Phase 3: Trigger & Breakout (Updated)                            |
//+------------------------------------------------------------------+
#property copyright "Levis Mwaniki"
#property version   "3.0.0"
#property strict

//+------------------------------------------------------------------+
//| Swing Structure Class                                            |
//| Tracks recent swing points based on user-defined bar lookback    |
//+------------------------------------------------------------------+
class SwingStructure {
private:
    string m_symbol;
    ENUM_TIMEFRAMES m_timeframe;
    int m_lookbackBars;
    int m_highHandle;
    int m_lowHandle;
    
public: // <-- CRITICAL: Must be public
    double lastHigh;
    double lastLow;
    bool isHigherHigh;
    bool isHigherLow;
    bool isLowerHigh;
    bool isLowerLow;
    
    //+------------------------------------------------------------------+
    //| Constructor (V3.0.0 - Matches LevisFxBot.mq5 V11.0.0)            |
    //| Parameters: symbol, timeframe, lookbackBars                      |
    //+------------------------------------------------------------------+
    SwingStructure(string symbol, ENUM_TIMEFRAMES timeframe, int lookbackBars) {
        m_symbol = symbol;
        m_timeframe = timeframe;
        m_lookbackBars = lookbackBars;
        
        lastHigh = 0.0;
        lastLow = 0.0;
        isHigherHigh = false;
        isHigherLow = false;
        isLowerHigh = false;
        isLowerLow = false;
        
        // Initialize indicator handles for high/low
        m_highHandle = iHigh(m_symbol, m_timeframe);
        m_lowHandle = iLow(m_symbol, m_timeframe);

        if (m_highHandle == INVALID_HANDLE || m_lowHandle == INVALID_HANDLE) {
            Print("ERROR: SwingStructure failed to initialize price handles.");
        }
    }

    //+------------------------------------------------------------------+
    //| Destructor                                                       |
    //+------------------------------------------------------------------+
    ~SwingStructure() { }

    //+------------------------------------------------------------------+
    //| UpdateStructure (The function the main EA calls)                 |
    //+------------------------------------------------------------------+
    void UpdateStructure() {
        if (m_highHandle == INVALID_HANDLE || m_lowHandle == INVALID_HANDLE) return;
        
        double highs[];
        double lows[];
        
        // Copy high and low prices for the last N bars (excluding current bar)
        if (CopyBuffer(m_highHandle, 0, 1, m_lookbackBars, highs) != m_lookbackBars) return;
        if (CopyBuffer(m_lowHandle, 0, 1, m_lookbackBars, lows) != m_lookbackBars) return;
        
        double periodHigh = highs[ArrayMaximum(highs, 0, m_lookbackBars)];
        double periodLow = lows[ArrayMinimum(lows, 0, m_lookbackBars)];
        
        double closePrice = iClose(m_symbol, m_timeframe, 0);

        // Reset flags
        isHigherHigh = false;
        isHigherLow = false;
        isLowerHigh = false;
        isLowerLow = false;

        // First run: establish initial high/low
        if (lastHigh == 0.0 || lastLow == 0.0) {
            lastHigh = periodHigh;
            lastLow = periodLow;
            return;
        }

        // Logic to detect CHoCH/Structure Flip
        if (closePrice > lastHigh) {
            isHigherHigh = true;
            lastHigh = closePrice;
            lastLow = periodLow; // Reset swing low reference
        } 
        else if (closePrice < lastLow) {
            isLowerLow = true;
            lastLow = closePrice;
            lastHigh = periodHigh; // Reset swing high reference
        }
        else if (closePrice > lastLow) {
            // Price is between HH and LL
            isHigherLow = true; // Potentially a Higher Low being formed
        }
        else if (closePrice < lastHigh) {
            isLowerHigh = true; // Potentially a Lower High being formed
        }
    }
};
//+------------------------------------------------------------------+
