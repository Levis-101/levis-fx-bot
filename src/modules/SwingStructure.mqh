//+------------------------------------------------------------------+
//| SwingStructure.mqh                                                |
//| Module: Confirmed Swing Point Detection (Fractal-Based)          |
//| Phase 3: CHoCH and Structure Logic                               |
//+------------------------------------------------------------------+
#property copyright "Levis Mwaniki"
#property version   "1.1.0"
#property strict

//+------------------------------------------------------------------+
//| Swing Structure Class                                            |
//| Tracks confirmed swing high/low points and determines structure. |
//+------------------------------------------------------------------+
class SwingStructure {
private:
    // Core structure points
    double m_lastHigh;      // Last confirmed swing high
    double m_lastLow;       // Last confirmed swing low
    
    // Parameters for confirmation
    ENUM_TIMEFRAMES m_timeframe;
    int m_swingBars;        // Bars required on either side (e.g., 2 for standard Fractal)
    string m_symbol;
    
    // Bar data buffers
    double m_highs[];
    double m_lows[];
    
    // Internal tracking for comparison
    double m_previousHigh;
    double m_previousLow;
    
    //+------------------------------------------------------------------+
    //| Check if a bar is a confirmed Fractal High                       |
    //| Requires m_swingBars lower highs to the left and right.          |
    //+------------------------------------------------------------------+
    bool IsFractalHighConfirmed(int index) {
        // We need (m_swingBars * 2) + 1 bars in the array
        if (index < m_swingBars || index >= ArraySize(m_highs) - m_swingBars) return false;
        
        double currentHigh = m_highs[index];
        
        // Check bars to the left
        for (int i = 1; i <= m_swingBars; i++) {
            if (m_highs[index + i] >= currentHigh) return false;
        }
        
        // Check bars to the right
        for (int i = 1; i <= m_swingBars; i++) {
            if (m_highs[index - i] >= currentHigh) return false;
        }
        
        return true;
    }

    //+------------------------------------------------------------------+
    //| Check if a bar is a confirmed Fractal Low                        |
    //| Requires m_swingBars higher lows to the left and right.          |
    //+------------------------------------------------------------------+
    bool IsFractalLowConfirmed(int index) {
        // We need (m_swingBars * 2) + 1 bars in the array
        if (index < m_swingBars || index >= ArraySize(m_lows) - m_swingBars) return false;
        
        double currentLow = m_lows[index];
        
        // Check bars to the left
        for (int i = 1; i <= m_swingBars; i++) {
            if (m_lows[index + i] <= currentLow) return false;
        }
        
        // Check bars to the right
        for (int i = 1; i <= m_swingBars; i++) {
            if (m_lows[index - i] <= currentLow) return false;
        }
        
        return true;
    }
    
public:
    // Structure analysis flags (for HH/HL/LL/LH detection)
    bool isHigherHigh;
    bool isHigherLow;
    bool isLowerHigh;
    bool isLowerLow;

    //+------------------------------------------------------------------+
    //| Constructor                                                      |
    //+------------------------------------------------------------------+
    SwingStructure(ENUM_TIMEFRAMES tf = PERIOD_M15, int bars = 2, string symbol = NULL) {
        m_timeframe = tf;
        m_swingBars = bars;
        m_symbol = symbol == NULL ? _Symbol : symbol;

        m_lastHigh = 0.0;
        m_lastLow = 0.0;
        m_previousHigh = 0.0;
        m_previousLow = 0.0;
        
        isHigherHigh = false;
        isHigherLow = false;
        isLowerHigh = false;
        isLowerLow = false;
    }

    //+------------------------------------------------------------------+
    //| Main structure update function - Called on new bar/tick          |
    //+------------------------------------------------------------------+
    void updateStructure() {
        // 1. Prepare data (use the required number of bars for confirmation)
        int requiredBars = (m_swingBars * 2) + 2; // +1 for the center bar, +1 for safety
        
        // --- Highs ---
        if (CopyHigh(m_symbol, m_timeframe, 0, requiredBars, m_highs) < requiredBars) return;
        ArraySetAsSeries(m_highs, true);
        
        // --- Lows ---
        if (CopyLow(m_symbol, m_timeframe, 0, requiredBars, m_lows) < requiredBars) return;
        ArraySetAsSeries(m_lows, true);
        
        // 2. Look for new confirmed swing points on the most recent bars
        
        // Check for confirmed High (start at index m_swingBars, moving back)
        for (int i = m_swingBars; i < requiredBars; i++) {
            if (IsFractalHighConfirmed(i)) {
                double newHigh = m_highs[i];
                
                // Only update if this is a new, different swing point
                if (newHigh > m_lastHigh || MathAbs(newHigh - m_lastHigh) > _Point * 10) { 
                    // Found a new confirmed swing high
                    m_previousHigh = m_lastHigh;
                    m_lastHigh = newHigh;
                    
                    // Update structure flags
                    isHigherHigh = (m_lastHigh > m_previousHigh);
                    isLowerHigh = (m_lastHigh < m_previousHigh && m_lastHigh > m_lastLow); // Must be above last low for L.H.
                    
                    return; // Stop after finding the first recent confirmed swing
                }
            }
        }
        
        // Check for confirmed Low (start at index m_swingBars, moving back)
        for (int i = m_swingBars; i < requiredBars; i++) {
            if (IsFractalLowConfirmed(i)) {
                double newLow = m_lows[i];
                
                // Only update if this is a new, different swing point
                if (newLow < m_lastLow || m_lastLow == 0.0 || MathAbs(newLow - m_lastLow) > _Point * 10) {
                    // Found a new confirmed swing low
                    m_previousLow = m_lastLow;
                    m_lastLow = newLow;
                    
                    // Update structure flags
                    isLowerLow = (m_lastLow < m_previousLow);
                    isHigherLow = (m_lastLow > m_previousLow && m_lastLow < m_lastHigh); // Must be below last high for H.L.
                    
                    return; // Stop after finding the first recent confirmed swing
                }
            }
        }
    }

    //+------------------------------------------------------------------+
    //| CHoCH Detection Logic (Primary structure flip)                   |
    //+------------------------------------------------------------------+
    bool IsChochConfirmed(bool targetBullish) {
        if (targetBullish) {
            // Bullish CHoCH: Market was making lower lows/highs (bearish), then it breaks the last Lower High (LH) to make a Higher High (HH)
            // CHoCH is confirmed when a new HH is made after a sequence of LL/LH.
            // Simplified check: A flip from bearish to bullish structure
            return isHigherHigh && m_previousHigh < m_previousLow; // Placeholder for full logic
        } else {
            // Bearish CHoCH: Market was making higher highs/lows (bullish), then it breaks the last Higher Low (HL) to make a Lower Low (LL)
            // CHoCH is confirmed when a new LL is made after a sequence of HH/HL.
            // Simplified check: A flip from bullish to bearish structure
            return isLowerLow && m_previousLow > m_previousHigh; // Placeholder for full logic
        }
    }

    //+------------------------------------------------------------------+
    //| Public Getters                                                   |
    //+------------------------------------------------------------------+
    double GetLastHigh() { return m_lastHigh; }
    double GetLastLow() { return m_lastLow; }
    
    //+------------------------------------------------------------------+
    //| Debug Info                                                       |
    //+------------------------------------------------------------------+
    string GetInfo() {
        string structure = "UNDETERMINED";
        if (isHigherHigh && m_lastLow > m_previousLow) structure = "BULLISH (HH/HL)";
        else if (isLowerLow && m_lastHigh < m_previousHigh) structure = "BEARISH (LL/LH)";
        else if (isLowerHigh && m_lastLow > m_previousLow) structure = "CONSOLIDATION/PULLBACK (LH/HL)";
        else if (isHigherLow && m_lastHigh < m_previousHigh) structure = "CONSOLIDATION/PULLBACK (HH/HL)";
        
        return StringFormat("Structure: %s | Last H: %.5f | Last L: %.5f", 
            structure, m_lastHigh, m_lastLow);
    }
};
//+------------------------------------------------------------------+
