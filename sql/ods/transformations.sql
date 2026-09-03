-- =========================================================================
-- ODS_MATCH_EVENTS - Transformations
-- =========================================================================


WITH
    match_info AS (
        SELECT
            match_id
        FROM statsbomb_raw_events
        LIMIT 1
    ),
    coords_extracted AS (
        SELECT
            e.match_id,
            e.index,
            e.type,
            NULLIF(split_part
                        (replace(replace(e.location, '[', ''), ']', ''), ',', 1)
                , '')::NUMERIC(5,1) AS x,
            NULLIF(trim(split_part
                            (replace(replace(e.location, '[', ''), ']', ''), ',', 2))
                , '')::NUMERIC(5,1) AS y,
            COALESCE(e.pass_end_location,
                     e.carry_end_location,
                     e.shot_end_location
            ) AS end_location_raw
        FROM statsbomb_raw_events e
        WHERE e.match_id = (SELECT match_id FROM match_info)
    ),
    final_coords AS (
        SELECT
            c.*,
            NULLIF(split_part
                            (replace(replace(end_location_raw, '[', ''), ']', ''), ',', 1)
                , '')::NUMERIC(5,1) AS end_x,
            NULLIF(trim(split_part
                            (replace(replace(end_location_raw, '[', ''), ']', ''), ',', 2))
                , '')::NUMERIC(5,1) AS end_y
        FROM coords_extracted c
    )
SELECT
    type,
    x,
    y,
    end_x,
    end_y
FROM final_coords
WHERE x IS NOT NULL;



CREATE OR REPLACE FUNCTION get_match_starters(p_match_id INT)
    RETURNS TABLE (
                      match_id INT,
                      team_name VARCHAR,
                      player_id VARCHAR,
                      player_name VARCHAR,
                      jersey_number INT
                  )
AS $$
DECLARE
    r_row RECORD;
    v_lineup_json JSON;
    v_player_item JSON;
BEGIN
    FOR r_row IN
        SELECT
            e.team,
            e.tactics
        FROM statsbomb_raw_events e
        WHERE e.match_id = p_match_id
          AND e.type = 'Starting XI'
        LOOP
            v_lineup_json := REPLACE(r_row.tactics, '''', '"')::json -> 'lineup';

            FOR v_player_item IN SELECT json_array_elements(v_lineup_json)
                LOOP
                    match_id      := p_match_id;
                    team_name     := r_row.team;
                    player_id     := (v_player_item -> 'player' ->> 'id')::VARCHAR;
                    player_name   := (v_player_item -> 'player' ->> 'name')::VARCHAR;
                    jersey_number := (v_player_item ->> 'jersey_number')::INT;

                    RETURN NEXT;
                END LOOP;
        END LOOP;
END;
$$ LANGUAGE plpgsql;



SELECT
    *
FROM get_match_starters(3825848);
