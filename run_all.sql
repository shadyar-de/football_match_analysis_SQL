-- =============================================================================
-- RUN ALL -- football_match_analysis_SQL entry point
-- Run with: psql -f run_all.sql -d your_db
-- (or `\i run_all.sql` from an interactive psql session)
-- =============================================================================

-- SCHEMA
\i schema/ods_match_events.sql
\i schema/match_metadata.sql

-- FUNCTIONS
\i functions/try_parse_lineup_json.sql
\i functions/get_match_starters.sql
\i functions/transform_match_events.sql
\i functions/load_ods_match_events.sql

-- PROCEDURES
\i procedures/sp_seed_match_metadata.sql
\i procedures/sp_run_pipeline.sql

-- REPORTING VIEWS
\i views/visuals.sql

-- SEED + RUN -- add one \i line per match here as you load more
\i seed/seed_match_3825848.sql
CALL sp_run_pipeline(3825848);

-- VALIDATE
\i validation/post_load_checks.sql
