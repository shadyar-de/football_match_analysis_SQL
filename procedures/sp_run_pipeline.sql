/* -----------------------------------------------------------------------------
   PIPELINE ENTRY POINT -- run the full load for one match.

   Assumes match_metadata has already been seeded for p_source_match_id (see
   seed/seed_match_*.sql and sp_seed_match_metadata.sql). load_ods_match_events
   itself fails fast with a clear RAISE EXCEPTION if it hasn't been.

   This is the single call site run_all.sql and any manual invocation uses.
   If the pipeline ever grows a second post-load step (refresh a materialized
   view, log completion, notify downstream), it goes here once instead of at
   every caller.

   load_ods_match_events is a FUNCTION (RETURNS VOID), not a PROCEDURE -- from
   inside this procedure body it's invoked with PERFORM, not CALL. CALL is
   reserved for other procedures.

   Example:
     CALL sp_run_pipeline(3825848);
----------------------------------------------------------------------------- */
CREATE OR REPLACE PROCEDURE sp_run_pipeline(p_source_match_id INTEGER)
    LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM load_ods_match_events(p_source_match_id);
END;
$$;