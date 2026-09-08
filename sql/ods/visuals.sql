-- =========================================================================
-- INTERNAL REUSABLE LOGIC
-- =========================================================================

-- REUSABILITY VIEW 1
-- Centralizes the "Successful Pass Convention" (#4, #11, #14)
CREATE OR REPLACE VIEW int_successful_passes AS
SELECT
    *
FROM ods_match_events
WHERE type_name = 'Pass'
  AND outcome_name IS NULL;


-- REUSABILITY VIEW 2
-- Centralizes pitch sides and the penalty box logic (#13, #14, #15).
CREATE OR REPLACE VIEW int_pitch_geography AS
SELECT
    match_id,
    id,
    x,
    y,
    zone_third AS pitch_third,
    CASE
        WHEN y < 40 THEN 'Left'
        ELSE 'Right'
        END AS pitch_side,
    (x >= 102 AND y BETWEEN 18 AND 62) AS is_in_box
FROM ods_match_events
WHERE x IS NOT NULL;

-- REUSABILITY VIEW 3
-- Consolidates defensive events for maps and stats (#10, #18)
CREATE OR REPLACE VIEW int_defensive_actions AS
SELECT
    *
FROM ods_match_events
WHERE type_name IN ('Tackle', 'Interception', 'Clearance');

-- =========================================================================
-- GROUP 1: MATCH IDENTIFICATION
-- =========================================================================

-- Visual #1: Title Page
CREATE OR REPLACE VIEW report_title_page AS
SELECT
    match_id,
    string_agg(DISTINCT team_name, ' vs ') AS match_fixture,
    competition_id,
    season_id
FROM ods_match_events
GROUP BY match_id, competition_id, season_id;

-- =========================================================================
-- GROUP 2: PLAYER POSITIONING
-- =========================================================================

-- Visual #2: Average Locations
CREATE OR REPLACE VIEW report_average_locations AS
SELECT
    match_id,
    team_name,
    player_id,
    player_name,
    AVG(x) AS avg_x,
    AVG(y) AS avg_y,
    COUNT(id) AS event_count
FROM ods_match_events
WHERE player_id IS NOT NULL
GROUP BY match_id, team_name, player_id, player_name;

-- =========================================================================
-- GROUP 3: DEFENSIVE & RECOVERY ACTIONS
-- =========================================================================

-- Visual #6: Ball Recoveries
CREATE OR REPLACE VIEW report_ball_recoveries AS
SELECT
    match_id,
    team_name,
    player_id,
    player_name,
    type_name,
    x,
    y,
    period,
    minute
FROM ods_match_events
WHERE type_name = 'Ball Recovery';

-- Visual #10: Defensive Actions Map (uses REUSABILITY VIEW 3)
CREATE OR REPLACE VIEW report_defensive_actions AS
SELECT
    match_id,
    team_name,
    player_id,
    player_name,
    type_name,
    x,
    y,
    outcome_name
FROM int_defensive_actions;

-- Visual #9: Fouls Committed
CREATE OR REPLACE VIEW report_fouls_committed AS
SELECT
    match_id,
    team_name,
    player_id,
    player_name,
    type_name,
    x,
    y,
    card_type
FROM ods_match_events
WHERE type_name = 'Foul Committed';


-- =========================================================================
-- GROUP 4: PASSING ANALYSIS
-- =========================================================================

-- Visual #4: Pass Network (uses REUSABILITY VIEW 1)
CREATE OR REPLACE VIEW report_pass_network AS

SELECT
    'position' AS result_type,
    match_id,
    team_name,
    player_id,
    player_name,
    NULL AS pass_recipient_name,
    AVG(x) AS x,
    AVG(y) AS y,
    COUNT(*) AS pass_count
FROM int_successful_passes
GROUP BY
    match_id,
    team_name,
    player_id,
    player_name

UNION ALL

SELECT
    'connection' AS result_type,
    match_id,
    team_name,
    player_id,
    player_name,
    pass_recipient_name,  -- Using the only available column from your schema
    NULL AS x,
    NULL AS y,
    COUNT(*) AS pass_count
FROM int_successful_passes
WHERE pass_recipient_name IS NOT NULL
GROUP BY
    match_id,
    team_name,
    player_id,
    player_name,
    pass_recipient_name
HAVING COUNT(*) > 3;

-- Visual #11: Progressive Passes && Visual #14: Final Third Entries
-- (both use REUSABILITY VIEW 1)

CREATE OR REPLACE VIEW report_advancing_passes AS
SELECT
    match_id,
    team_name,
    player_id,
    player_name,
    x,
    y,
    end_x,
    end_y,
    is_progressive,
    is_final_third_entry
FROM int_successful_passes
WHERE is_progressive OR is_final_third_entry;


-- Visual #8: Crosses
CREATE OR REPLACE VIEW report_crosses AS
SELECT
    match_id,
    team_name,
    player_id,
    player_name,
    pass_cross,
    outcome_name,
    x,
    y,
    end_x,
    end_y
FROM ods_match_events
WHERE type_name = 'Pass'
  AND pass_cross = TRUE;

-- Visual #12: Corner Kicks
CREATE OR REPLACE VIEW report_corner_kicks AS
SELECT
    match_id,
    team_name,
    player_id,
    player_name,
    type_name,
    play_pattern_name,
    x,
    y,
    end_x,
    end_y,
    outcome_name
FROM ods_match_events
WHERE type_name = 'Pass' AND play_pattern_name = 'From Corner';


-- =========================================================================
-- GROUP 5: ATTACKING & CREATIVE ACTIONS
-- =========================================================================

-- Visual #3: Shot Map
CREATE OR REPLACE VIEW report_shot_map AS
SELECT
    match_id,
    team_name,
    player_id,
    player_name,
    type_name,
    x,
    y,
    end_x,
    end_y,
    xg,
    outcome_name
FROM ods_match_events
WHERE type_name = 'Shot';

-- Visual #7: Dribbles
CREATE OR REPLACE VIEW report_dribbles AS
SELECT
    match_id,
    team_name,
    player_id,
    player_name,
    type_name,
    x,
    y,
    end_x,
    end_y,
    outcome_name
FROM ods_match_events
WHERE type_name = 'Dribble';


-- =========================================================================
-- GROUP 6: POSSESSION & TERRITORY
-- =========================================================================

-- Visual #5: Losses of Possession
CREATE OR REPLACE VIEW report_possession_losses AS
SELECT
    match_id,
    team_name,
    type_name,
    outcome_name,
    x,
    y
FROM ods_match_events
WHERE type_name IN ('Dispossessed', 'Miscontrol')
   OR (type_name = 'Pass' AND outcome_name = 'Incomplete');


-- Visual #13: Possession Zones (uses REUSABILITY VIEW 2)
CREATE OR REPLACE VIEW report_possession_zones AS
WITH zone_data AS (
    SELECT
        e.match_id,
        e.team_name,
        CASE
            WHEN g.pitch_third = 'Defensive third' THEN 20
            WHEN g.pitch_third = 'Middle third'    THEN 60
            ELSE 100
            END AS x,
        CASE
            WHEN g.pitch_side = 'Left' THEN 20 ELSE 60
            END AS y,
        COUNT(e.id) AS event_count
    FROM ods_match_events e
             JOIN int_pitch_geography g
                  ON e.match_id = g.match_id
                      AND e.id = g.id
    WHERE e.type_name IN ('Pass', 'Ball Receipt', 'Carry')
    GROUP BY e.match_id, e.team_name, g.pitch_third, g.pitch_side
)
SELECT
    match_id,
    team_name,
    x,
    y,
    event_count,
    ROUND(100.0 * event_count / SUM(event_count) OVER (PARTITION BY match_id, team_name), 2) AS pct_of_total_possession
FROM zone_data;


-- Visual #15: Territory Chart (5-Minute Bins)
CREATE OR REPLACE VIEW report_territory_chart AS
SELECT
    match_id,
    team_name,
    ((minute - 1) / 5) * 5 AS minute_bin,
    AVG(x) AS avg_x_position
FROM ods_match_events
WHERE x IS NOT NULL
GROUP BY match_id, team_name, minute_bin;


-- =========================================================================
-- GROUP 7: PERFORMANCE SUMMARY & TIMELINES
-- =========================================================================

-- Visual #17: Pass Accuracy
CREATE OR REPLACE VIEW report_pass_accuracy_timeline AS
WITH minute_stats AS (
    SELECT
        match_id,
        team_name,
        minute,
        COUNT(*) AS passes_in_minute,
        COUNT(*) FILTER (WHERE outcome_name IS NULL) AS success_in_minute
    FROM ods_match_events
    WHERE type_name = 'Pass'
    GROUP BY match_id, team_name, minute
)
SELECT
    match_id,
    team_name,
    minute,
    passes_in_minute AS total_passes,
    ROUND(
            100.0 *
            SUM(success_in_minute) OVER (PARTITION BY match_id, team_name ORDER BY minute) /
            SUM(passes_in_minute) OVER (PARTITION BY match_id, team_name ORDER BY minute),
            2
    ) AS cumulative_accuracy
FROM minute_stats;


-- Visual #16: Passes per Minute
-- Same per-team, per-minute pass totals #17 already computes -- reused here
-- rather than re-scanning ods_match_events a second time for the same count.
CREATE OR REPLACE VIEW report_passes_per_minute AS
SELECT
    match_id,
    team_name,
    'Pass'::VARCHAR(50) AS type_name,
    minute,
    total_passes AS pass_count
FROM report_pass_accuracy_timeline;


-- Visual #18: Match Statistics
CREATE OR REPLACE VIEW report_match_statistics AS
SELECT
    match_id,
    team_name,
    COUNT(*) FILTER (WHERE type_name = 'Pass')                                      AS total_passes,
    COUNT(*) FILTER (WHERE type_name = 'Pass' AND outcome_name IS NULL)             AS accurate_passes,
    ROUND(
            100.0 * COUNT(*) FILTER (WHERE type_name = 'Pass' AND outcome_name IS NULL)
                / NULLIF(COUNT(*) FILTER (WHERE type_name = 'Pass'), 0),
            2
    )                                                                               AS pass_accuracy_pct,
    COUNT(*) FILTER (WHERE type_name = 'Shot')                                      AS total_shots,
    COUNT(*) FILTER (WHERE type_name = 'Shot' AND outcome_name = 'Goal')            AS goals,
    COUNT(*) FILTER (WHERE type_name = 'Shot' AND outcome_name IN ('Goal', 'Saved')) AS shots_on_target,
    COUNT(*) FILTER (WHERE type_name = 'Pass' AND play_pattern_name = 'From Corner') AS corners,
    COUNT(*) FILTER (WHERE type_name = 'Foul Committed')                            AS fouls_committed,
    COUNT(*) FILTER (WHERE type_name = 'Ball Recovery')                            AS ball_recoveries,
    COUNT(*) FILTER (WHERE type_name = 'Tackle')                                   AS total_tackles,
    COUNT(*) FILTER (WHERE type_name = 'Interception')                            AS interceptions,
    COUNT(*) FILTER (WHERE type_name = 'Clearance')                               AS clearances
FROM ods_match_events
GROUP BY match_id, team_name;