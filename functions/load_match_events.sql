/* -----------------------------------------------------------------------------
   RE-RUNNABLE MATCH TRANSFORMATION AND LOAD

   Inputs:
     - p_match_id: the raw StatsBomb match id (source_match_id in
       match_metadata / match_id in statsbomb_raw_events).

   match_id, competition_id, and season_id are NOT passed in as parameters.
   They are looked up from match_metadata, which is the single source of
   truth for that metadata (see match_metadata.sql). This removes the need
   for a database-level FK from match_metadata to statsbomb_raw_events
   (impossible anyway, since match_id there is not unique -- see note in
   match_metadata.sql) and instead enforces the load-order dependency in
   code: a match must be seeded in match_metadata before it can be loaded.

   Re-run behaviour: deletes and reloads only the requested match, so it is
   safe to correct source data and run the load again.

   All row computation lives in transform_match_events() -- this function is
   now resolve -> delete -> insert -> validate.

   Example:
     SELECT load_ods_match_events(3825848);
----------------------------------------------------------------------------- */
CREATE OR REPLACE FUNCTION load_ods_match_events(
    p_match_id INTEGER
)
    RETURNS VOID
    LANGUAGE plpgsql
AS $$
DECLARE
    v_match_id       VARCHAR(50);
    v_competition_id VARCHAR(50);
    v_season_id      VARCHAR(50);
    v_has_unmapped_types BOOLEAN;
BEGIN
    /* STEP 1 - RESOLVE METADATA
       match_metadata is the single source of truth for match_id,
       competition_id, and season_id. Fail if the match hasn't
       been registered there yet */
    SELECT
        match_id,
        competition_id,
        season_id
    INTO v_match_id, v_competition_id, v_season_id
    FROM match_metadata
    WHERE source_match_id = p_match_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'No match_metadata row for source_match_id=%. Seed match_metadata before loading.',
            p_match_id;
    END IF;

    /* STEP 2 - REMOVE THE PREVIOUS VERSION OF THIS MATCH
       This makes the load idempotent: running the same match again does not
       create duplicate ODS rows or affect any other match. Keyed off the
       resolved v_match_id (the ODS match_id), not the raw source id. */
    DELETE FROM ods_match_events
    WHERE match_id = v_match_id;

    /* STEP 3 - COMPUTE AND INSERT
       All parsing/derivation logic lives in transform_match_events(). */
    INSERT INTO ods_match_events (
        id,
        match_id,
        competition_id,
        season_id,
        team_name,
        player_name,
        player_id,
        jersey_number,
        pass_recipient_name,
        type_name,
        sub_type_name,
        outcome_name,
        pass_cross,
        play_pattern_name,
        card_type,
        x,
        y,
        end_x,
        end_y,
        zone_third,
        is_progressive,
        is_final_third_entry,
        xg,
        period,
        frame,
        duration,
        minute,
        second,
        timestamp
    )
    SELECT * FROM transform_match_events(p_match_id, v_match_id, v_competition_id, v_season_id);

    /* STEP 4 - FLAG UNMAPPED EVENT TYPES
       The type_name CASE inside transform_match_events() falls through to the
       raw StatsBomb label for any source type this pipeline doesn't recognise
       yet. That keeps the load from breaking, but it also means a brand-new
       event type (e.g. next season) silently stops appearing in every
       reporting view that filters on a specific type_name. */
    SELECT EXISTS (
        SELECT 1
        FROM ods_match_events
        WHERE match_id = v_match_id
          AND type_name NOT IN (
                                'Pass', 'Shot', 'Interception', 'Ball Recovery', 'Ball Receipt',
                                'Tackle', 'Dribble', 'Miscontrol', 'Dispossessed', 'Clearance',
                                'Ball Out', 'Foul Committed', 'Ball Lost', 'Starting XI', 'Half Start',
                                'Half End', 'Substitution', 'Player On', 'Player Off', 'Injury Stoppage',
                                'Tactical Shift', 'Bad Behaviour'
            )
    ) INTO v_has_unmapped_types;

    IF v_has_unmapped_types THEN
        RAISE WARNING
            'load_ods_match_events: match_id=% has one or more unmapped event types -- check the CASE in transform_match_events() for new StatsBomb types.',
            v_match_id;
    END IF;
END;
$$;