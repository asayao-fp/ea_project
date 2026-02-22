# ea_project

MT5 (MetaTrader 5) EA (Expert Advisor) project managed on GitHub.

## Goals
- Develop a safety-first EA for H1 timeframe
- Run on XMTrader demo first (balance: 1,000,000 JPY equivalent suggested)
- Trade USDJPY and EURUSD
- Market orders only (first iteration)

## Repository layout
- `src/experts/` - EA source (.mq5)
- `presets/` - MT5 input presets (.set)
- `docs/` - notes, results, and design documents

## Quick start
1. Open MetaEditor (MT5)
2. Copy the EA from `src/experts/` into your MT5 data folder:
   - `MQL5/Experts/`
3. Compile in MetaEditor
4. Attach to an H1 chart (USDJPY / EURUSD)

## Safety notes
This project is educational and does not guarantee profits. Use demo forward-testing, small lots, and strict loss limits.