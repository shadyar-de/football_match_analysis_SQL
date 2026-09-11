# Football Match Events Analytics Pipeline

This project is part of the training Kanidata provides for its Graduate Data Engineering Programme, delivered as a real client engagement.

**DE-02 Team Alpha** (Zahraa Zaher, Shadyar Radha, Arya Burhan)

---

## Overview

A football analytics company tracks every event across its matches (passes, shots, dribbles, recoveries, fouls, etc.). Historically, analysts manually wrangled ~2,600 raw, unnormalised StatsBomb rows per match before producing a single report.

This project replaces manual wrangling with a **fully automated, idempotent, and re-runnable SQL pipeline**. It extracts and parses raw JSON dumps into a clean, typed source-of-truth table (`ods_match_events`) and provisions a 18-visual reporting view layer that enables analysts to filter by match, team, and player without rewriting SQL.

---

## Project Structure

```text
football_match_analysis_SQL/
├── functions/
│   ├── get_match_starters.sql
│   ├── load_match_events.sql
│   └── transform_match_events.sql
├── procedures/
│   ├── sp_run_pipeline.sql
│   └── sp_seed_match_metadata.sql
├── schema/
│   ├── match_metadata.sql
│   └── ods_match_events.sql
├── seed/
│   └── seed_match_3825848.sql
├── validation/
│   └── post_load_checks.sql
├── views/
│   └── visuals.sql
├── .gitignore
├── README.md
└── run_all.sql               -- Master pipeline execution script

Pipeline Architecture

statsbomb_raw_events (Raw StatsBomb payload dump)
        │
        ├─── get_match_starters()  ──► Extracts lineup from "Starting XI" tactics JSON
        │                              (Resolves player_id, jersey_number, team)
        ▼
transform_match_events()           ──► Cleans coordinates (x, y, end_x, end_y),
        │                              standardises event taxonomy, parses time,
        │                              filters out non-spatial metadata rows
        ▼
sp_run_pipeline(p_source_match_id) ──► IDEMPOTENT LOADER:
        │                              1. Verifies match exists in match_metadata
        │                              2. Purges existing match records (DELETE WHERE match_id)
        │                              3. Loads transformed data into ods_match_events
        ▼
ods_match_events                   ──► Single source of truth (indexed on match, team, player, type)
        │
        ├──► post_load_checks.sql  ──► Audits row counts, unmapped types, and pitch coordinate bounds
        │
        ▼
Reporting Layer (views/*.sql)       ──► 18 client match-report views (filterable via WHERE)

Running the Pipeline

Full Execution via run_all.sql

Run the master script in DataGrip or psql:

-- 1. Seed match metadata
\i seed/seed_match_3825848.sql

-- 2. Execute the transformation and ingestion orchestrator
CALL sp_run_pipeline(p_source_match_id => 3825848);

-- 3. Run automated post-load integrity checks
\i validation/post_load_checks.sql

Loading a New Match

Because the pipeline is built around scoped entity idempotency, adding another
match or re-processing an existing one is identical:

1.  Register the new match in match_metadata:
    INSERT INTO match_metadata (source_match_id, competition_id, season_id)
    VALUES (3825849, 43, 106)
    ON CONFLICT (source_match_id) DO NOTHING;
2.  Ingest the match's raw JSON dump into statsbomb_raw_events.
3.  Call the pipeline orchestrator:
    CALL sp_run_pipeline(3825849);

If source data is patched upstream, simply run CALL sp_run_pipeline(<match_id>);
again. It will automatically wipe and cleanly reload only that match's rows in
ods_match_events without affecting any other matches.

Key Transformations & Engineering Edge Cases

1. Spatial Grain vs. Metadata Events

The target ods_match_events table enforces a strictly spatial grain (one pitch
event with coordinates):

  - Events kept: Pass, Shot, Dribble, Ball Receipt, Duel, Clearance, Foul
    Committed, etc.
  - Events filtered: Non-spatial match metadata rows lacking coordinates
    (Starting XI, Half Start, Half End, Substitution, Tactical Shift, Injury
    Stoppage, Player On, Player Off) are deliberately excluded from
    ods_match_events.
  - Starting XI JSON tactics arrays are parsed separately in
    get_match_starters() to build the player-jersey lookup map before raw event
    transformation.

2. PostgreSQL Keyword Disambiguation

In PostgreSQL function signatures (RETURNS TABLE), timestamp is a reserved data
type keyword. In transform_match_events(), the column is declared with double
quotes ("timestamp" VARCHAR(10)) to ensure the engine treats it as a column
identifier rather than an unnamed data type.

3. Coordinates & Scalability

  - Coordinates in raw text (location = "[61.0, 40.1]") are parsed into x, y,
    end_x, and end_y as NUMERIC(5, 1).
  - Pitch coordinates adhere to StatsBomb's 120×80 yard dimension standard.

4. Derived Football Metrics

Flags are centralized in the ODS layer to avoid expensive runtime recalculations
across views:

  - is_progressive: True when a pass advances \ge 10 yards toward the opponent's
    goal and ends past the halfway line.
  - is_final_third_entry: True when an event originates at or behind x=80 and
    concludes beyond x>80.
  - zone_third: Categorised into 'Defensive Third', 'Middle Third', or 'Final
    Third'.

Data Quality & Validation

validation/post_load_checks.sql runs immediately after pipeline execution:

1.  Coordinate Sanity: Verifies all records stay within pitch bounds
    (0 \le x \le 120, 0 \le y \le 80).
2.  Taxonomy Audits: Validates raw event types against the taxonomy mapping.
    Non-spatial metadata events are filtered out of the check so warnings only
    fire if an actual, unhandled in-game event type is detected.
3.  Player Identity Completeness: Verifies that starters mapped correctly to
    jersey_number and player_id.

Reporting Layer (Views)

All eighteen analyst match-report visuals run off live, indexed views
(ods/visuals.sql):

| \# | Report Visual       | View Name                       | Shared Logic / Notes                     |
| -- | ------------------- | ------------------------------- | ---------------------------------------- |
| 1  | Title Page          | `report_title_page`             | High-level match summary                 |
| 2  | Average Locations   | `report_average_locations`      | Player average $(x, y)$ positions        |
| 3  | Shot Map            | `report_shot_map`               | Coordinates, xG, and shot outcome        |
| 4  | Pass Network        | `report_pass_network`           | Passer-receiver link volume              |
| 5  | Possession Losses   | `report_possession_losses`      | Dispossessions, miscontrols, lost balls  |
| 6  | Ball Recoveries     | `report_ball_recoveries`        | Defensive recoveries                     |
| 7  | Dribbles            | `report_dribbles`               | Dribble attempts and success rate        |
| 8  | Crosses             | `report_crosses`                | Cross completions by wing                |
| 9  | Fouls Committed     | `report_fouls_committed`        | Native + derived set-piece fouls         |
| 10 | Defensive Actions   | `report_defensive_actions`      | Built on `int_defensive_actions`         |
| 11 | Progressive Passes  | `report_advancing_passes`       | Filtered on `WHERE is_progressive`       |
| 12 | Corner Kicks        | `report_corner_kicks`           | Corner set pieces and deliveries         |
| 13 | Possession Zones    | `report_possession_zones`       | Pitch thirds possession percentage       |
| 14 | Final Third Entries | `report_advancing_passes`       | Filtered on `WHERE is_final_third_entry` |
| 15 | Territory Chart     | `report_territory_chart`        | Territorial dominance breakdown          |
| 16 | Passes per Minute   | `report_passes_per_minute`      | Tempo timeline                           |
| 17 | Pass Accuracy       | `report_pass_accuracy_timeline` | Success rate across intervals            |
| 18 | Match Statistics    | `report_match_statistics`       | High-level team comparisons              |

Querying Views

Every view is indexed on match_id, team_name, and player_id:

-- Query Shot Map for one match
SELECT * FROM report_shot_map 
WHERE match_id = '3825848';

-- Query Average Locations for a specific team
SELECT * FROM report_average_locations 
WHERE match_id = '3825848' AND team_name = 'Levante UD';