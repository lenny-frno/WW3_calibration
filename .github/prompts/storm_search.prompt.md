---
mode: 'agent'
tools: ['fetch', 'editFiles']
description: 'Search the web for 10 major storms in Norwegian Sea / North Sea / Barents Sea (2010–2025) suitable for WW3 calibration periods'
---

# Task: Find 10 calibration storms — Norwegian/North/Barents Sea (2010–2025)

You are assisting a WW3 (WAVEWATCH III) ocean wave modeller who needs historical storm
periods to calibrate the model. Your task is to find **10 well-documented storms** that:

- Occurred between **2010 and 2025** (inclusive)
- Were located in the **Norwegian Sea**, **North Sea**, or **Barents Sea**
- Had **strong sustained winds** (≥ Beaufort 9 / ≥ 47 kt / ≥ 24 m/s) over open water
- Lasted **at least 3 days**, at most **10 days** (defined as the period of strong winds affecting the basin)
- Are documented in publicly accessible meteorological records

These storms will be used as calibration periods for a CARRA2 reanalysis-forced WW3 run,
so storms well-covered by the CARRA2 domain (European Arctic and North Atlantic) are preferred.

---

## Where to search

Search the following sources, in order of preference:

1. **Norwegian Meteorological Institute** — storm archive and reports: https://www.met.no
2. **KNMI (Royal Netherlands Meteorological Institute)** — North Sea storm catalogue
3. **UK Met Office** named storms: https://www.metoffice.gov.uk/weather/warnings-and-advice/uk-storm-centre/
4. **ECMWF ERA5 storm track databases** — search for intense extra-tropical cyclones
5. **Wikipedia** — "List of European windstorms", filter by area and year
6. **NOAA / IBTrACS** for any Arctic cyclones
7. Scientific literature: search Google Scholar for "Norwegian Sea cyclone 2010–2025 significant wave height"

---

## Output required

For each storm produce one entry in the following format (exactly):

```
### Storm N: <Name or descriptor>

- **Date range**: YYYYMMDD – YYYYMMDD  (3–10 days, the active strong-wind period)
- **Area**: Norwegian Sea / North Sea / Barents Sea (pick primary basin)
- **Peak winds**: ~ XX m/s or Bft YY
- **Notable impacts**: (brief, e.g. "flooding in western Norway", "wave buoy recorded 14m Hs")
- **Sources**: (URL or publication)
```

---

## After listing all 10 storms, append this section

```bash
# ============================================================
# manage_periods.sh commands — paste on HPC to register periods
# ============================================================
cd /nobackup/forsk/sm_lenal/WW3/NewHindcast_CARRA2/experiments/calibration

bash scripts/manage_periods.sh add <storm_name_snake_case> \
  --start YYYYMMDD --end YYYYMMDD \
  --description "<short description>" \
  --tags "storm,calibration,<basin>"

# ... (one block per storm)
```

Use `snake_case` names like `storm_xaver_2013`, `storm_dagmar_2011`, etc.

---

## Quality criteria

- Prefer storms with available wave buoy or satellite altimeter records (easier to validate WW3 output against)
- Prefer storms where CARRA2 reanalysis coverage is confirmed (European Arctic region)
- Avoid purely tropical cyclones or storms entirely outside the target basins
- If a storm spans more than 10 days, pick the 7–10 most intense days as the period

Write the output into a new file: `periods/storm_catalogue.md` in the workspace.
