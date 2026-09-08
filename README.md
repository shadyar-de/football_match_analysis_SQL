# Football Match Events Analytics Pipeline

This project is part of the training Kanidata provides for its Graduate Data
Engineering Programme, delivered as a real client engagement. 

**DE-02 Team Alpha** (Zahraa Zaher, Shadyar Radha, Arya Burhan).

A football analytics company tracks every event in every match it covers
(passes, shots, dribbles, recoveries, fouls, ...). Today, each analyst
wrangles ~2,600 raw, unnormalised StatsBomb rows by hand before they can build
a single match report. This project replaces that manual step with a
re-runnable pipeline: one clean, typed source-of-truth table
(`ods_match_events`) and a reporting layer of views on top of it that feed the
client's eighteen match-report visuals -- filterable by match, team, and
player, with no SQL rewriting required.

## Pipeline at a Glance

```text
statsbomb_raw_events (raw StatsBomb event dump, one match's worth of rows)
        │
        ▼
match_metadata            -- seeds match_id / competition_id / season_id
        │                      (these are not present on the raw event rows)
        ▼
load_ods_match_events(id)  -- transformation function: parses coordinates,
        │                      standardises event types/outcomes, resolves
        │                      player_id & jersey_number from Starting XI,
        │                      derives zone/progressive/final-third flags,
        │                      derives fallback fouls, assigns sequential id
        ▼
ods_match_events           -- single source of truth, one row per event,
        │                      indexed on (match_id, team_name, player_id)
        │                      and (match_id, type_name)
        ▼
Reporting layer (views, sql/ods/visuals.sql)
        │
        ▼
18 analyst-facing report_* visuals -- filter by match_id / team_name /
                                     player_id, no SQL changes needed
```

## Running the Pipeline

Run in this order (each script is idempotent and safe to re-run):

1. `sql/ods/create_table.sql` -- creates `ods_match_events` if it doesn't exist.
2. `sql/ods/match_metadata.sql` -- creates `match_metadata` and seeds the
   sample match (`source_match_id = 3825848`). **A match must have a row here
   before it can be loaded.**
3. `sql/ods/load_and_transform.sql` -- creates the indexes, the
   `get_match_starters()` helper, and the `load_ods_match_events()`
   transformation function, then calls it for the seeded match and runs the
   post-load validation checks.
4. `sql/ods/visuals.sql` -- creates the reporting layer (all `report_*` views).

### Loading a new match

1. Add a row to `match_metadata` for the new `source_match_id` (see the
   `INSERT ... ON CONFLICT DO NOTHING` pattern in `match_metadata.sql`).
2. Run `SELECT load_ods_match_events(<source_match_id>);`

No other script changes. The function deletes and reloads only that match's
rows in `ods_match_events`, so it never touches other matches and is safe to
re-run if the source data needed a fix.

## The Data Model: `ods_match_events`

One row per event, grain = one spatial event from the raw feed, plus one
derived `Foul Committed` row per opponent's `SET PIECE`/`FREE KICK` event
*only* when the feed has no native foul events (see "Known data caveats"
below). Primary key: `(match_id, id)`.

Key transformations (full column-by-column mapping is in the project's
`ODS_Column_Mapping` reference):

- **Coordinates** -- `location` / `*_end_location` string fields like
  `"[61.0, 40.1]"` are parsed into numeric `x`/`y` and `end_x`/`end_y`, scaled
  to StatsBomb's 0-120 / 0-80 pitch. A future 0-1-range feed is already
  supported via a conditional scale-up.
- **Event taxonomy** -- `type_name` / `sub_type_name` / `outcome_name` are
  derived from the source `type` + subtype columns (`pass_type`,
  `shot_type`, `duel_type`, ...) into one consistent StatsBomb-style label
  per event. Inconsistent string values (e.g., `Ball Receipt*`) are mapped
  to standard values (`Ball Receipt`). `outcome_name IS NULL` on a `Pass` is
  the convention used throughout the reporting layer for "successful pass" --
  no separate flag.
- **Player identity** -- `player_id` and `jersey_number` are resolved by
  joining the match's `Starting XI` tactics payload (parsed in
  `get_match_starters()`) onto events.
- **Derived football flags** -- `zone_third`, `is_progressive` (advanced ≥10
  yards and ended past the halfway line), and `is_final_third_entry`
  (started at/behind x=80, ended beyond it) are computed once here so every
  downstream view reads a flag instead of re-deriving it. Logic is centralized
  to avoid duplication.
- **Timing** -- StatsBomb timestamps reset every period; `duration` is
  normalised to total match seconds, then `minute`/`second`/`timestamp` are
  derived from that.

## Ingestion Approach

- **`match_id`, `competition_id`, `season_id`** are not present on the raw
  event rows. They live in `match_metadata`, keyed by the raw StatsBomb
  `source_match_id`, and are looked up inside `load_ods_match_events()` at
  load time. A match must be seeded in `match_metadata` before it can be
  loaded -- this is enforced in code (the function raises an exception if the
  match isn't registered), since a DB-level foreign key isn't possible here
  (`match_id` isn't unique in the raw event table).
- **`player_id` / `jersey_number`** come from the `Starting XI` event's
  `tactics` JSON payload, which StatsBomb includes per match. This is
  extracted once per match by `get_match_starters()` into a lookup table of
  `(team_name, player_name) -> (player_id, jersey_number)`, which is then
  left-joined onto every event by player name.

### Data Quality & Validation
- **Error Handling:** The load function catches and handles malformed or missing JSON in the `Starting XI` tactics payload without crashing the pipeline.
- **Validation:** Post-load validation checks evaluate the dataset. Warnings are raised for unmapped event types, ensuring new or unexpected raw data is flagged rather than silently passing to the reporting layer.

## The Reporting Layer

`sql/ods/visuals.sql` defines three internal reusable views
(`int_successful_passes`, `int_pitch_geography`, `int_defensive_actions`) that
centralise logic several visuals share, plus sixteen `report_*` views that
cover all eighteen visuals (Progressive Passes and Final Third Entries share
one view, `report_advancing_passes`, since they read the same rows and differ
only by which boolean flag is set; Passes per Minute reuses the per-minute
totals already computed by the Pass Accuracy view instead of re-scanning the
table).

| # | Visual | View |
|---|---|---|
| 1 | Title Page | `report_title_page` |
| 2 | Average Locations | `report_average_locations` |
| 3 | Shot Map | `report_shot_map` |
| 4 | Pass Network | `report_pass_network` |
| 5 | Losses of Possession | `report_possession_losses` |
| 6 | Ball Recoveries | `report_ball_recoveries` |
| 7 | Dribbles | `report_dribbles` |
| 8 | Crosses | `report_crosses` |
| 9 | Fouls Committed | `report_fouls_committed` |
| 10 | Defensive Actions | `report_defensive_actions` |
| 11 | Progressive Passes | `report_advancing_passes` (`WHERE is_progressive`) |
| 12 | Corner Kicks | `report_corner_kicks` |
| 13 | Possession Zones | `report_possession_zones` |
| 14 | Final Third Entries | `report_advancing_passes` (`WHERE is_final_third_entry`) |
| 15 | Territory Chart | `report_territory_chart` |
| 16 | Passes per Minute | `report_passes_per_minute` |
| 17 | Pass Accuracy | `report_pass_accuracy_timeline` |
| 18 | Match Statistics | `report_match_statistics` |

### Why views (and not materialised views) right now

Because the table has indexes on `(match_id, team_name, player_id)` and `(match_id, type_name)`, and every reporting view filters on `match_id`, each query only scans a few thousand indexed rows for that match — not the whole table. That's already fast, so a live view gives you up-to-date results at essentially no extra cost. A materialized view would only pay off once queries got expensive enough to need pre-computed results, and right now it would just add a refresh step and risk serving stale data while the underlying transformation logic is still being refined.


## Filterability

Every `report_*` view can be filtered by `match_id`, `team_name`, and
`player_id` (where the visual has a player grain) with a plain `WHERE` --
no view edits, no rewritten SQL:

```sql
-- One match, all shots
SELECT * FROM report_shot_map WHERE match_id = '3825848';

-- One match, one team, all shots
SELECT * FROM report_shot_map WHERE match_id = '3825848' AND team_name = 'Levante UD';

-- One match, one player
SELECT * FROM report_average_locations
WHERE match_id = '3825848' AND player_id = '6739';

-- One match, whole pass network
SELECT * FROM report_pass_network WHERE match_id = '3825848';
```

## Next Steps

- Load a second match end-to-end to confirm the pipeline runs unmodified.