CREATE TABLE IF NOT EXISTS ods_match_events (
    id INTEGER PRIMARY KEY,
    --using INTEGER because the mapping specifically requires id INTEGER,
    -- generated using ROW_NUMBER() after sorting and adding foul rows.
    match_id VARCHAR(50) NOT NULL,
    competition_id VARCHAR(50),
    season_id VARCHAR(50),
    team_name VARCHAR(100),
    player_name VARCHAR(100),
    player_id VARCHAR(50),
    jersey_number INTEGER,
    pass_recipient_name VARCHAR(100),
    type_name VARCHAR(50),
    sub_type_name VARCHAR(50),
    outcome_name VARCHAR(50),
    pass_cross BOOLEAN,
    play_pattern_name VARCHAR(50),
    card_type VARCHAR(20),

    x NUMERIC(5, 1),
    y NUMERIC(5, 1),
    end_x NUMERIC(5, 1),
    end_y NUMERIC(5, 1),

    zone_third VARCHAR(20),
    is_progressive BOOLEAN,
    is_final_third_entry BOOLEAN,
    xg NUMERIC(5, 4),

    period INTEGER,
    frame INTEGER,
    duration NUMERIC(10, 2),
    minute INTEGER,
    second INTEGER,
    timestamp VARCHAR(10),

    CONSTRAINT chk_ods_match_events_id
        CHECK (id > 0),

    CONSTRAINT chk_ods_match_events_coordinates
        CHECK (
            (x IS NULL OR x BETWEEN 0 AND 120)
            AND
            (y IS NULL OR y BETWEEN 0 AND 80)
            AND
            (end_x IS NULL OR end_x BETWEEN 0 AND 120)
            AND
            (end_y IS NULL OR end_y BETWEEN 0 AND 80)
        )

);



-- STORY 3.1 — IMPLEMENT PASS-BASED VISUALS  --

CREATE OR REPLACE VIEW vw_pass_network AS -- counts how many times a player passes to another player
SELECT
    team_name,
    player_name AS passer,
    pass_recipient_name AS receiver,
    COUNT(*) AS pass_count
FROM ods_match_events
WHERE type_name = 'Pass'
  AND player_name IS NOT NULL
  AND pass_recipient_name IS NOT NULL
GROUP BY
    team_name,
    player_name,
    pass_recipient_name;


-- counts how many progressive passes each team made.

CREATE OR REPLACE VIEW vw_progressive_passes AS
SELECT
    team_name,
    COUNT(*) AS progressive_passes
FROM ods_match_events
WHERE type_name = 'Pass'
  AND is_progressive = TRUE
GROUP BY team_name;


-- count how many passes each team made that entered the final third of the pitch.

CREATE OR REPLACE VIEW vw_final_third_entries AS
SELECT
    team_name,
    COUNT(*) AS final_third_entries
FROM ods_match_events
WHERE type_name = 'Pass'
  AND is_final_third_entry = TRUE
GROUP BY team_name;


-- count how many Passes per Minute of each team.

CREATE OR REPLACE VIEW vw_passes_per_minute AS
SELECT
    team_name,
    minute,
    COUNT(*) AS pass_count
FROM ods_match_events
WHERE type_name = 'Pass'
  AND minute IS NOT NULL
GROUP BY
    team_name,
    minute
ORDER BY
    team_name,
    minute;


-- count and calculate each teams pass accuracy percentage.

CREATE OR REPLACE VIEW vw_pass_accuracy AS
SELECT
    team_name,
    COUNT(*) AS total_passes,
    COUNT(*) FILTER (
        WHERE outcome_name IS NULL
    ) AS successful_passes,
    ROUND(
        COUNT(*) FILTER (
            WHERE outcome_name IS NULL
        ) * 100.0 / NULLIF(COUNT(*), 0),
        2
    ) AS pass_accuracy_percentage
FROM ods_match_events
WHERE type_name = 'Pass'
GROUP BY team_name;


-- count how many crosses each team made.

CREATE OR REPLACE VIEW vw_crosses AS
SELECT
    team_name,
    COUNT(*) AS crosses
FROM ods_match_events
WHERE type_name = 'Pass'
  AND pass_cross = TRUE
GROUP BY team_name;


-- Count how many Corner Kicks

CREATE OR REPLACE VIEW vw_corner_kicks AS
SELECT
    team_name,
    COUNT(*) AS corner_kicks
FROM ods_match_events
WHERE play_pattern_name = 'From Corner'
GROUP BY team_name;


-- for testing them --

SELECT COUNT(*) AS total_events
FROM ods_match_events;


SELECT COUNT(*) AS total_raw_events
FROM de02_team_alpha.statsbomb_raw_events;


SELECT *
FROM de02_team_alpha.statsbomb_raw_events
LIMIT 5;
---------------