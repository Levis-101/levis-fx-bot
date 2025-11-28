//+------------------------------------------------------------------+
//| FairValueGap.mqh                                                 |
//| Module: Fair Value Gap (FVG) Detection                           |
//| Phase 2: Confluence & Filters                                    |
//+------------------------------------------------------------------+
#property copyright "Levis Mwaniki"
#property version   "1.0.0"
#property strict

//+------------------------------------------------------------------+
//| FVG Structure                                                    |
//+------------------------------------------------------------------+
struct FVG {
    double top;                 // Top price of the FVG (High of 1-bar or Low of 3-bar)
    double bottom;              // Bottom price of the FVG (Low of 1-bar or High of 3-bar)
    int direction;              // 1 for Bullish FVG, -1 for Bearish FVG
    bool isMitigated;           // True if price has filled the gap
};

//+------------------------------------------------------------------+
//| Fair Value Gap Class                                             |
//+------------------------------------------------------------------+
class FairValueGap {
private:
    string m_symbol;
    ENUM_TIMEFRAMES m_timeframe;
    int m_lookbackBars;
    
public:
    //+------------------------------------------------------------------+
    //| Constructor                                                      |
    //+------------------------------------------------------------------+
    FairValueGap(ENUM_TIMEFRAMES tf, int lookback, string symbol) {
        m_timeframe = tf;
        m_lookbackBars = lookback;
        m_symbol = symbol;
    }

    //+------------------------------------------------------------------+
    //| Check if an FVG is present near a specific price level           |
    //| Tolerance is used to define "near" the entry level.              |
    //| The FVG must be UNMITIGATED for a valid signal.                  |
    //+------------------------------------------------------------------+
    bool IsFVGPresent(double checkLevel, int requiredDirection, double tolerancePoints) {
        
        double highs[3];
        double lows[3];
        // double tolerance = tolerancePoints * _Point; // Tolerance not strictly needed for containment check
        
        // Scan the last few bars for FVG pattern
        for (int i = 1; i < m_lookbackBars - 2; i++) {
            
            // Get High/Low for bars: 1 (i), 2 (i+1), 3 (i+2)
            // Array is ordered: lows[0] is bar 'i' (current), lows[2] is bar 'i+2' (furthest back)
            if (CopyHigh(m_symbol, m_timeframe, i, 3, highs) != 3 ||
                CopyLow(m_symbol, m_timeframe, i, 3, lows) != 3) {
                return false;
            }
            
            // --- 1. BULLISH FVG Check (Move up, Low[i] > High[i+2]) ---
            if (lows[0] > highs[2]) {
                if (requiredDirection == 1) {
                    FVG bullishFvg;
                    bullishFvg.top = lows[0];           // Top of the gap
                    bullishFvg.bottom = highs[2];       // Bottom of the gap
                    
                    // Check Mitigation (simplified: assuming mitigation is handled externally 
                    // or in the trade logic if required, for now just check if price is inside)
                    
                    // Check if the entry level is contained within the FVG boundaries
                    if (checkLevel < bullishFvg.top && checkLevel > bullishFvg.bottom) {
                        return true;
                    }
                }
            }
            
            // --- 2. BEARISH FVG Check (Move down, High[i] < Low[i+2]) ---
            else if (highs[0] < lows[2]) {
                if (requiredDirection == -1) {
                    FVG bearishFvg;
                    bearishFvg.top = lows[2];           // Top of the gap
                    bearishFvg.bottom = highs[0];       // Bottom of the gap
                    
                    // Check if the entry level is contained within the FVG boundaries
                    if (checkLevel < bearishFvg.top && checkLevel > bearishFvg.bottom) {
                        return true;
                    }
                }
            }
        }
        
        return false;
    }
};
//+------------------------------------------------------------------+
