/* -----------------------------------------------------------------------------
   SEED ONE MATCH INTO match_metadata

   Takes the values that used to be hardcoded as a literal INSERT ... VALUES
   in match_metadata.sql and turns them into parameters. ON CONFLICT DO
   NOTHING keeps this safe to re-run for a match that's already seeded --
   same idempotency guarantee the original INSERT had.

   Example:
     CALL sp_seed_match_metadata(3825848, '3825848', 'LA_LIGA', '2015_2016');
----------------------------------------------------------------------------- */
CREATE OR REPLACE PROCEDURE sp_seed_match_metadata(
    p_source_match_id INTEGER,
    p_match_id        VARCHAR(50),
    p_competition_id  VARCHAR(50),
    p_season_id       VARCHAR(50)
)
    LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO match_metadata (source_match_id, match_id, competition_id, season_id)
    VALUES (p_source_match_id, p_match_id, p_competition_id, p_season_id)
    ON CONFLICT (source_match_id) DO NOTHING;
END;
$$;