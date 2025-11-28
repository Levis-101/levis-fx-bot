//+------------------------------------------------------------------+
//| VWAPBias.mqh                                                     |
//| Module: Volume Weighted Average Price (VWAP) Bias Detector       |
//| Phase 2: Confluence & Filters                                    |
//+------------------------------------------------------------------+
#property copyright "Levis Mwaniki"
#property version   "1.0.0"
#property strict

//+------------------------------------------------------------------+
//| VWAP Bias Class                                                  |
//| Determines price bias relative to the current daily VWAP.        |
//+------------------------------------------------------------------+
class VWAPBias {
private:
    string m_symbol;
    int m_vwapHandle;
    ENUM_TIMEFRAMES m_calcTF = PERIOD_M5; // VWAP works best on lower timeframes

public:
    //+------------------------------------------------------------------+
    //| Constructor                                                      |
    //+------------------------------------------------------------------+
    VWAPBias(string symbol = NULL) {
        m_symbol = symbol == NULL ? _Symbol : symbol;
        
        // Use the built-in VWAP indicator (requires "Examples\Indicators\VWAP.ex5" to be present)
        m_vwapHandle = iCustom(m_symbol, m_calcTF, "Examples\\Indicators\\VWAP.ex5");
        
        if (m_vwapHandle == INVALID_HANDLE) {
            Print("ERROR: Could not initialize VWAP indicator handle. Ensure VWAP.ex5 is present.");
        }
    }
    
    //+------------------------------------------------------------------+
    //| Destructor                                                       |
    //+------------------------------------------------------------------+
    ~VWAPBias() {
        if (m_vwapHandle != INVALID_HANDLE) IndicatorRelease(m_vwapHandle);
    }

    //+------------------------------------------------------------------+
    //| Get VWAP value at the current bar (index 0)                      |
    //+------------------------------------------------------------------+
    double GetVWAPValue() {
        if (m_vwapHandle == INVALID_HANDLE) return 0.0;
        
        double vwap_buffer[1];
        
        // Copy VWAP value from buffer 0 for the current bar (index 0)
        if (CopyBuffer(m_vwapHandle, 0, 0, 1, vwap_buffer) == 1) {
            return vwap_buffer[0];
        }
        
        return 0.0;
    }

    //+------------------------------------------------------------------+
    //| Check if current price is above (Bullish: 1) or below (Bearish: -1) VWAP|
    //+------------------------------------------------------------------+
    int GetBias() {
        double vwap = GetVWAPValue();
        if (vwap == 0.0) return 0;

        double currentPrice = SymbolInfoDouble(m_symbol, SYMBOL_BID);
        
        if (currentPrice > vwap) return 1; 
        if (currentPrice < vwap) return -1;
        
        return 0; // Neutral
    }
};
//+------------------------------------------------------------------+
