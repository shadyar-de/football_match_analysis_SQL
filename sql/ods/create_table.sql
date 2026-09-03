CREATE TABLE IF NOT EXISTS ods_match_events (
    id INTEGER PRIMARY KEY,
    --using INTEGER because the mapping specifically requires id INTEGER, generated using ROW_NUMBER() after sorting and adding foul rows.
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
