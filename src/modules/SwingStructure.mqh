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
    
public:
    double lastHigh;
    double lastLow;
    bool isHigherHigh;
    bool isHigherLow;
    bool isLowerHigh;
    bool isLowerLow;
    
    //+------------------------------------------------------------------+
    //| Constructor                                                      |
    //+------------------------------------------------------------------+
    SwingStructure(string symbol, ENUM_TIMEFRAMES timeframe, int lookbackBars) {
        m_symbol = symbol;
        m_timeframe = timeframe;
        m_lookbackBars = lookbackBars;
        
        lastHigh = 0.0;
        lastLow = 0.0;
        
        // Initialize indicator handles for high/low (using iCustom placeholder for simplicity)
        m_highHandle = iHigh(m_symbol, m_timeframe);
        m_lowHandle = iLow(m_symbol, m_timeframe);

        if (m_highHandle == INVALID_HANDLE || m_lowHandle == INVALID_HANDLE) {
            Print("ERROR: SwingStructure failed to initialize price handles.");
        }
    }

    //+------------------------------------------------------------------+
    //| Destructor                                                       |
    //+------------------------------------------------------------------+
    ~SwingStructure() {
        // Since we are using built-in price indicators, no need to explicitly release standard handles
    }

    //+------------------------------------------------------------------+
    //| UpdateStructure (The function the main EA is looking for)        |
    //| Detects the most recent HH/LL/LH/HL based on lookback.           |
    //+------------------------------------------------------------------+
    void UpdateStructure() {
        if (m_highHandle == INVALID_HANDLE || m_lowHandle == INVALID_HANDLE) return;
        
        double highs[];
        double lows[];
        
        // Copy high and low prices for the last N bars
        if (CopyBuffer(m_highHandle, 0, 1, m_lookbackBars, highs) != m_lookbackBars) return;
        if (CopyBuffer(m_lowHandle, 0, 1, m_lookbackBars, lows) != m_lookbackBars) return;
        
        // Find the absolute highest high and lowest low in the lookback period (excluding current bar)
        double periodHigh = highs[ArrayMaximum(highs, 0, m_lookbackBars)];
        double periodLow = lows[ArrayMinimum(lows, 0, m_lookbackBars)];
        
        // Get the current close price
        double closePrice = iClose(m_symbol, m_timeframe, 0);

        // --- Logic to check for new HH/LL/LH/HL (simplified CHoCH logic) ---
        
        // Reset flags
        isHigherHigh = false;
        isHigherLow = false;
        isLowerHigh = false;
        isLowerLow = false;

        // Check for new High/Low relative to the previous detected swing points
        // We use the most recent swing points (lastHigh, lastLow) if they exist.
        if (lastHigh == 0.0 || lastLow == 0.0) {
            // First run: establish initial high/low
            lastHigh = periodHigh;
            lastLow = periodLow;
            return;
        }

        // 1. Higher High (HH) - Price breaks period high and closes above
        if (closePrice > lastHigh) {
            isHigherHigh = true;
            lastHigh = closePrice;
        } 
        
        // 2. Lower Low (LL) - Price breaks period low and closes below
        else if (closePrice < lastLow) {
            isLowerLow = true;
            lastLow = closePrice;
        }

        // 3. Higher Low (HL) - Current price above lastLow, but below lastHigh
        else if (closePrice > lastLow && closePrice < lastHigh) {
            // Check if price is making a higher low than the current lastLow
            if (closePrice > lastLow) {
                isHigherLow = true;
            } else if (closePrice < lastHigh) {
                isLowerHigh = true;
            }
        }
    }
    
    // The previous printCurrentSwing function can be added back if needed for debug

    //+------------------------------------------------------------------+
    //| Get Info (for debugging)                                         |
    //+------------------------------------------------------------------+
    string GetInfo() {
        string output = StringFormat("Swing: H:%.5f L:%.5f | HH:%s HL:%s | LH:%s LL:%s",
            lastHigh, lastLow,
            isHigherHigh ? "T" : "F", isHigherLow ? "T" : "F",
            isLowerHigh ? "T" : "F", isLowerLow ? "T" : "F");
        return output;
    }
};
//+------------------------------------------------------------------+
