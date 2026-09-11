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
            /* Handling a malformed tactics string. Basically, catch the cast, warn, and move on to
               the next team */
            BEGIN
                v_lineup_json := REPLACE(r_row.tactics, '''', '"')::json -> 'lineup';
            EXCEPTION WHEN invalid_text_representation THEN
                RAISE WARNING
                    'get_match_starters: match_id=%, team=%: malformed tactics JSON, skipping lineup for this team',
                    p_match_id, r_row.team;
                CONTINUE;
            END;

            /* NULL tactics (no Starting XI JSON at all)*/
            IF v_lineup_json IS NULL THEN
                RAISE WARNING
                    'get_match_starters: match_id=%, team=%: no tactics/lineup JSON present, jersey numbers unavailable for this team',
                    p_match_id, r_row.team;
                CONTINUE;
            END IF;

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
