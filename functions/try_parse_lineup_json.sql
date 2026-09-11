/* -----------------------------------------------------------------------------
   Safely parse one team's tactics JSON. Returns NULL (with a warning) on
   malformed or missing JSON instead of raising an error.
----------------------------------------------------------------------------- */
CREATE OR REPLACE FUNCTION try_parse_lineup_json(
    p_match_id INT,
    p_team     VARCHAR,
    p_tactics  TEXT
)
    RETURNS JSON
    LANGUAGE plpgsql
AS $$
DECLARE
    v_result JSON;
BEGIN
    BEGIN
        v_result := REPLACE(p_tactics, '''', '"')::json -> 'lineup';
    EXCEPTION WHEN invalid_text_representation THEN
        RAISE WARNING
            'get_match_starters: match_id=%, team=%: malformed tactics JSON, skipping lineup for this team',
            p_match_id, p_team;
        RETURN NULL;
    END;

    IF v_result IS NULL THEN
        RAISE WARNING
            'get_match_starters: match_id=%, team=%: no tactics/lineup JSON present, jersey numbers unavailable for this team',
            p_match_id, p_team;
    END IF;

    RETURN v_result;
END;
$$;