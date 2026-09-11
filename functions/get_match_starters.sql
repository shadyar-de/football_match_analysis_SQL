/* -----------------------------------------------------------------------------
   Expand every team's Starting XI into one row per player. The malformed/
   missing-JSON case is fully delegated to try_parse_lineup_json(),
   and json_array_elements() returns zero rows for a NULL input, so a bad team
   simply contributes nothing instead of needing a CONTINUE to skip it.
----------------------------------------------------------------------------- */
CREATE OR REPLACE FUNCTION get_match_starters(p_match_id INT)
    RETURNS TABLE (
                      match_id INT,
                      team_name VARCHAR,
                      player_id VARCHAR,
                      player_name VARCHAR,
                      jersey_number INT
                  )
    LANGUAGE sql
AS $$
SELECT
    p_match_id,
    e.team,
    (element -> 'player' ->> 'id')::VARCHAR,
    (element -> 'player' ->> 'name')::VARCHAR,
    (element ->> 'jersey_number')::INT
FROM statsbomb_raw_events e
         CROSS JOIN LATERAL json_array_elements(
        try_parse_lineup_json(p_match_id, e.team, e.tactics)
                            ) AS element
WHERE e.match_id = p_match_id
  AND e.type = 'Starting XI';
$$;
