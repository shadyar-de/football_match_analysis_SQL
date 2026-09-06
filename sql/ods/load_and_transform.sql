/* =============================================================================
   FOOTBALL MATCH ANALYTICS PIPELINE - ODS_MATCH_EVENTS
   =============================================================================

   Source: statsbomb_raw_events
   Target grain: one spatial source event, plus one derived Foul Committed row
   for every source SET PIECE / FREE KICK event when native foul events are
   unavailable.

   Main transformations performed:
     1. Parses location text into numeric x/y and end_x/end_y coordinates.
     2. Standardises event types, outcomes, card values, and pass flags.
     3. Adds player IDs, shirt numbers, and starter status from Starting XI data.
     4. Derives zone, progressive-pass, final-third-entry, and timing fields.
     5. Adds fallback Foul Committed events only for feeds without native fouls.
     6. Re-numbers events sequentially after all derived rows are included.

   The supplied source already uses StatsBomb's 120 x 80 pitch coordinates.
   Conditional normalisation also supports a future feed with 0-1 coordinates.
============================================================================= */

/*-----------------------------------------------------------------------------
  1. ODS TARGET TABLE
  DDL lives in create_target_table.sql (single source of truth). Run that
  script first. It defines ods_match_events with PRIMARY KEY (match_id, id).
----------------------------------------------------------------------------- */
CREATE INDEX IF NOT EXISTS ix_ods_match_events_match_team_player
    ON ods_match_events (match_id, team_name, player_name);

CREATE INDEX IF NOT EXISTS ix_ods_match_events_match_type
    ON ods_match_events (match_id, type_name);


/*-----------------------------------------------------------------------------
   2. EXTRACT STARTING-XI PLAYER DETAILS
   The raw tactics field is JSON-like text. This function turns it into a
   player lookup containing player ID, player name, team, and jersey number.
   The load function in section 3 calls this to resolve jersey_number and
   starter status.
-----------------------------------------------------------------------------*/
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

/* -----------------------------------------------------------------------------
   3. RE-RUNNABLE MATCH TRANSFORMATION AND LOAD

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
BEGIN
    /* STEP 3.0 - RESOLVE METADATA
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

    /* STEP 3.1 - REMOVE THE PREVIOUS VERSION OF THIS MATCH
       This makes the load idempotent: running the same match again does not
       create duplicate ODS rows or affect any other match. Keyed off the
       resolved v_match_id (the ODS match_id), not the raw source id. */
    DELETE FROM ods_match_events
    WHERE match_id = v_match_id;

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
    WITH
        /* STEP 3.2 - READ AND STANDARDISE THE RAW SOURCE FIELDS
           - Converts literal text 'null' values to SQL NULL.
           - Bridges the mapping PDF's friendly names to actual StatsBomb columns:
             pass_type, pass_outcome, shot_outcome, foul_committed_card, etc.
           - Chooses the correct end-location field based on Pass, Carry, or Shot.
           - Converts period-relative StatsBomb timestamps into total match seconds. */
        source_events AS (
            SELECT
                NULLIF(e."index"::TEXT, 'null')::INTEGER AS source_frame,
                NULLIF(e.team::TEXT, 'null')::VARCHAR(100) AS team_name,
                NULLIF(e.player::TEXT, 'null')::VARCHAR(100) AS player_name,
                NULLIF(e.player_id::TEXT, 'null')::VARCHAR(50) AS raw_player_id,
                NULLIF(e.pass_recipient::TEXT, 'null')::VARCHAR(100) AS pass_recipient_name,
                NULLIF(e.type::TEXT, 'null')::VARCHAR(100) AS raw_type,
                NULLIF(e.pass_type::TEXT, 'null')::VARCHAR(100) AS raw_pass_type,
                NULLIF(e.duel_type::TEXT, 'null')::VARCHAR(100) AS raw_duel_type,
                NULLIF(e.shot_type::TEXT, 'null')::VARCHAR(100) AS raw_shot_type,
                NULLIF(e.pass_outcome::TEXT, 'null')::VARCHAR(100) AS raw_pass_outcome,
                NULLIF(e.shot_outcome::TEXT, 'null')::VARCHAR(100) AS raw_shot_outcome,
                COALESCE(NULLIF(NULLIF(LOWER(TRIM(e.pass_cross::TEXT)), ''), 'null')::BOOLEAN, FALSE) AS raw_pass_cross,
                NULLIF(e.play_pattern::TEXT, 'null')::VARCHAR(100) AS raw_play_pattern,
                COALESCE(
                        NULLIF(e.foul_committed_card::TEXT, 'null'),
                        NULLIF(e.bad_behaviour_card::TEXT, 'null')
                )::VARCHAR(100) AS raw_card_type,
                NULLIF(NULLIF(TRIM(e.location::TEXT), ''), 'null') AS location_raw,
                CASE
                    WHEN UPPER(TRIM(e.type::TEXT)) = 'PASS'  THEN NULLIF(e.pass_end_location::TEXT, 'null')
                    WHEN UPPER(TRIM(e.type::TEXT)) = 'CARRY' THEN NULLIF(e.carry_end_location::TEXT, 'null')
                    WHEN UPPER(TRIM(e.type::TEXT)) = 'SHOT'  THEN NULLIF(e.shot_end_location::TEXT, 'null')
                    END AS end_location_raw,
                NULLIF(e.shot_statsbomb_xg::TEXT, 'null')::NUMERIC(5,4) AS xg,
                NULLIF(e.period::TEXT, 'null')::INTEGER AS period,
                /* StatsBomb timestamps reset each period; convert to match seconds. */
                (
                    EXTRACT(EPOCH FROM e.timestamp::TIME)
                        + CASE NULLIF(e.period::TEXT, 'null')::INTEGER
                              WHEN 1 THEN 0
                              WHEN 2 THEN 45 * 60
                              WHEN 3 THEN 90 * 60
                              WHEN 4 THEN 105 * 60
                              ELSE 0
                        END
                    )::NUMERIC(10,2) AS duration
            FROM statsbomb_raw_events AS e
            WHERE e.match_id = p_match_id
              -- The ODS is a spatial event table.  This removes Starting XI and
              -- other non-pitch metadata events while retaining all mapped events.
              AND NULLIF(NULLIF(TRIM(e.location::TEXT), ''), 'null') IS NOT NULL
        ),
        /* STEP 3.3 - PARSE COORDINATES
           Converts strings such as '[61.0, 40.1]' into numeric raw_x and raw_y.
           End coordinates are parsed from pass_end_location, carry_end_location,
           or shot_end_location selected in the preceding step. */
        parsed_coordinates AS (
            SELECT
                s.*,
                NULLIF(TRIM(SPLIT_PART(TRIM(BOTH '[]' FROM s.location_raw), ',', 1)), '')::NUMERIC AS raw_x,
                NULLIF(TRIM(SPLIT_PART(TRIM(BOTH '[]' FROM s.location_raw), ',', 2)), '')::NUMERIC AS raw_y,
                NULLIF(TRIM(SPLIT_PART(TRIM(BOTH '[]' FROM s.end_location_raw), ',', 1)), '')::NUMERIC AS raw_end_x,
                NULLIF(TRIM(SPLIT_PART(TRIM(BOTH '[]' FROM s.end_location_raw), ',', 2)), '')::NUMERIC AS raw_end_y
            FROM source_events AS s
        ),
        /* STEP 3.4 - NORMALISE COORDINATES AND STANDARDISE SOURCE LABELS
           Keeps the supplied 120 x 80 StatsBomb coordinates unchanged. If a future
           feed sends a 0-1 range, scales it to the same 120 x 80 pitch. */
        coordinates AS (
            SELECT
                p.*,
                CASE WHEN p.raw_x BETWEEN 0 AND 1 THEN p.raw_x * 120 ELSE p.raw_x END::NUMERIC(5,1) AS x,
                CASE WHEN p.raw_y BETWEEN 0 AND 1 THEN p.raw_y * 80  ELSE p.raw_y END::NUMERIC(5,1) AS y,
                CASE WHEN p.raw_end_x BETWEEN 0 AND 1 THEN p.raw_end_x * 120 ELSE p.raw_end_x END::NUMERIC(5,1) AS end_x,
                CASE WHEN p.raw_end_y BETWEEN 0 AND 1 THEN p.raw_end_y * 80  ELSE p.raw_end_y END::NUMERIC(5,1) AS end_y,
                NULLIF(UPPER(TRIM(p.raw_type)), '') AS source_type,
                NULLIF(UPPER(REPLACE(TRIM(p.raw_pass_type), '-', ' ')), '') AS source_pass_type,
                NULLIF(UPPER(REPLACE(TRIM(p.raw_duel_type), '-', ' ')), '') AS source_duel_type,
                NULLIF(UPPER(REPLACE(TRIM(p.raw_shot_type), '-', ' ')), '') AS source_shot_type,
                NULLIF(UPPER(TRIM(p.raw_pass_outcome)), '') AS source_pass_outcome,
                NULLIF(UPPER(TRIM(p.raw_shot_outcome)), '') AS source_shot_outcome
            FROM parsed_coordinates AS p
        ),
        /* STEP 3.5 - BUILD THE BASE ODS EVENT ROWS
           - Joins Starting XI details for jersey number and starter status.
           - Maps raw event fields to type_name, sub_type_name, and outcome_name.
           - Sets successful-pass outcome_name to NULL, as required by the brief.
           - Derives pass_cross, play_pattern_name, zone_third, progressive and
             final-third flags, xG, minute, second, and timestamp. */
        base_events AS (
            SELECT
                c.source_frame,
                FALSE AS is_derived_foul,
                c.team_name,
                c.player_name,
                COALESCE(st.player_id, c.raw_player_id) AS player_id,
                st.jersey_number,
                (st.player_id IS NOT NULL) AS is_starter,
                c.pass_recipient_name,
                c.source_type,
                COALESCE(
                        c.source_pass_type,
                        c.source_duel_type,
                        c.source_shot_type
                ) AS source_subtype,
                CASE
                    WHEN c.source_type = 'PASS'
                        AND c.source_pass_type = 'INTERCEPTION'
                        AND c.source_pass_outcome = 'INCOMPLETE' THEN 'Ball Lost'
                    WHEN c.source_type = 'PASS' AND c.source_pass_type = 'INTERCEPTION' THEN 'Interception'
                    WHEN c.source_type = 'PASS' THEN 'Pass'
                    WHEN c.source_type = 'SHOT' THEN 'Shot'
                    WHEN c.source_type = 'INTERCEPTION' THEN 'Interception'
                    WHEN c.source_type = 'BALL RECOVERY' THEN 'Ball Recovery'
                    WHEN c.source_type = 'BALL RECEIPT*' THEN 'Ball Receipt'
                    WHEN (c.source_type = 'TACKLE'
                        OR (c.source_type = 'DUEL' AND c.source_duel_type = 'TACKLE')) THEN 'Tackle'
                    WHEN c.source_type = 'DRIBBLE' THEN 'Dribble'
                    WHEN c.source_type IN ('BALL LOST', 'MISCONTROL') THEN 'Miscontrol'
                    WHEN c.source_type = 'DISPOSSESSED' THEN 'Dispossessed'
                    WHEN c.source_type = 'CLEARANCE' THEN 'Clearance'
                    WHEN c.source_type = 'BALL OUT'
                        AND COALESCE(c.source_pass_type, c.source_duel_type, c.source_shot_type) = 'CLEARANCE' THEN 'Clearance'
                    WHEN c.source_type = 'BALL OUT' THEN 'Ball Out'
                    WHEN c.source_type = 'FOUL COMMITTED' THEN 'Foul Committed'
                    ELSE c.raw_type::VARCHAR(50)
                    END AS type_name,
                COALESCE(
                        c.source_pass_type,
                        c.source_duel_type,
                        c.source_shot_type
                )::VARCHAR(50) AS sub_type_name,
                CASE
                    -- NULL is the reporting convention for a successful pass.
                    WHEN c.source_type = 'PASS' AND c.source_pass_outcome IS NULL THEN NULL
                    WHEN c.source_type = 'PASS' THEN 'Incomplete'
                    WHEN c.source_type = 'SHOT'
                        AND c.source_shot_outcome = 'GOAL' THEN 'Goal'
                    WHEN c.source_type = 'SHOT'
                        AND c.source_shot_outcome IN ('ON TARGET', 'SAVED', 'SAVED TO POST', 'SAVED OFF TARGET') THEN 'Saved'
                    WHEN c.source_type = 'SHOT' THEN 'Off Target'
                    END::VARCHAR(50) AS outcome_name,
                c.raw_pass_cross AS pass_cross,
                COALESCE(
                        c.raw_play_pattern,
                        CASE
                            WHEN c.source_pass_type IN ('CORNER', 'CORNER KICK') THEN 'From Corner'
                            WHEN c.source_pass_type = 'FREE KICK' THEN 'From Free Kick'
                            WHEN c.source_pass_type IN ('THROW IN', 'THROWIN') THEN 'From Throw In'
                            WHEN c.source_pass_type = 'GOAL KICK' THEN 'From Goal Kick'
                            WHEN c.source_pass_type = 'PENALTY' THEN 'From Penalty'
                            ELSE 'Regular Play'
                            END
                )::VARCHAR(50) AS play_pattern_name,
                REGEXP_REPLACE(c.raw_card_type, ' Card$', '')::VARCHAR(20) AS card_type,
                c.x,
                c.y,
                c.end_x,
                c.end_y,
                CASE
                    WHEN c.x < 40 THEN 'Defensive third'
                    WHEN c.x < 80 THEN 'Middle third'
                    WHEN c.x >= 80 THEN 'Attacking third'
                    END::VARCHAR(20) AS zone_third,
                COALESCE(
                        c.source_type IN ('PASS', 'CARRY')
                            AND c.end_x - c.x >= 10
                            AND c.end_x > 60,
                        FALSE
                ) AS is_progressive,
                COALESCE(c.x <= 80 AND c.end_x > 80, FALSE) AS is_final_third_entry,
                c.xg,
                c.period,
                c.duration,
                FLOOR(c.duration / 60)::INTEGER + 1 AS minute,
                MOD(FLOOR(c.duration)::INTEGER, 60) AS second
            FROM coordinates AS c
                     LEFT JOIN get_match_starters(p_match_id) AS st
                               ON st.team_name = c.team_name
                                   AND st.player_name = c.player_name
        ),
        /* STEP 3.6 - IDENTIFY THE TWO MATCH TEAMS
           Used only by the fallback foul derivation to find the opposing team. */
        match_teams AS (
            SELECT DISTINCT team_name
            FROM base_events
            WHERE team_name IS NOT NULL
        ),
        /* STEP 3.7 - DERIVE FOULS ONLY WHEN THE SOURCE HAS NO NATIVE FOULS
           The mapping PDF says a Set Piece / Free Kick means the other team
           committed a foul. The supplied StatsBomb data already has native
           Foul Committed rows, so this fallback stays inactive for this match and
           prevents foul totals from being doubled. */
        foul_events AS (
            SELECT
                b.source_frame,
                TRUE AS is_derived_foul,
                opponent.team_name,
                NULL::VARCHAR(100) AS player_name,
                NULL::VARCHAR(50) AS player_id,
                NULL::INTEGER AS jersey_number,
                FALSE AS is_starter,
                NULL::VARCHAR(100) AS pass_recipient_name,
                'SET PIECE'::VARCHAR AS source_type,
                'FREE KICK'::VARCHAR AS source_subtype,
                'Foul Committed'::VARCHAR(50) AS type_name,
                'FREE KICK'::VARCHAR(50) AS sub_type_name,
                NULL::VARCHAR(50) AS outcome_name,
                FALSE AS pass_cross,
                'From Free Kick'::VARCHAR(50) AS play_pattern_name,
                b.card_type,
                b.x,
                b.y,
                NULL::NUMERIC(5,1) AS end_x,
                NULL::NUMERIC(5,1) AS end_y,
                b.zone_third,
                FALSE AS is_progressive,
                FALSE AS is_final_third_entry,
                NULL::NUMERIC(5,4) AS xg,
                b.period,
                b.duration,
                b.minute,
                b.second
            FROM base_events AS b
                     INNER JOIN match_teams AS opponent
                                ON opponent.team_name <> b.team_name
            -- The mapping PDF describes this fallback as Set Piece + Free Kick.
            -- The supplied StatsBomb feed represents it as Pass + pass_type Free
            -- Kick.  Its native Foul Committed events are preferred when present
            -- so a match never double-counts fouls.
            WHERE (
                (b.source_type = 'SET PIECE' AND b.source_subtype = 'FREE KICK')
                    OR (b.source_type = 'PASS' AND b.source_subtype = 'FREE KICK')
                )
              AND NOT EXISTS (
                SELECT 1
                FROM base_events AS native_foul
                WHERE native_foul.source_type = 'FOUL COMMITTED'
            )
        ),
        /* STEP 3.8 - COMBINE SOURCE AND FALLBACK-DERIVED EVENTS */
        all_events AS (
            SELECT * FROM base_events
            UNION ALL
            SELECT * FROM foul_events
        ),
        /* STEP 3.9 - ASSIGN THE FINAL SEQUENTIAL EVENT ID
           IDs are assigned only after all derived events exist and are sorted by
           duration, as required by the column mapping. */
        ordered_events AS (
            SELECT
                        ROW_NUMBER() OVER (
                    ORDER BY duration, source_frame, is_derived_foul DESC, team_name
                    )::INTEGER AS id,
                        *
            FROM all_events
        )
    SELECT
        id,
        v_match_id,
        v_competition_id,
        v_season_id,
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
        source_frame,
        duration,
        minute,
        second,
        LPAD(minute::TEXT, 2, '0') || ':' || LPAD(second::TEXT, 2, '0')
    FROM ordered_events;
END;
$$;


/* -----------------------------------------------------------------------------
   4. RUN THE LOAD
   match_id, competition_id, and season_id are resolved automatically from
   match_metadata inside the function -- just pass the raw source match id.
   Seed match_metadata for this match first (see match_metadata.sql).

   SELECT load_ods_match_events(3825848);
----------------------------------------------------------------------------- */


SELECT load_ods_match_events(3825848);



/* -----------------------------------------------------------------------------
   5. POST-LOAD VALIDATION CHECKS
   Scoped to the match just loaded (p_match_id above) -- every check here is
   filtered by match_id, matching the same pattern analysts use downstream.
   Use these to demonstrate row counts, valid pitch bounds, event-type
   coverage, and unique sequential IDs after loading.
----------------------------------------------------------------------------- */

-- 5.1 Full row-level view of the loaded match, ordered by the assigned id.
SELECT
    *
FROM ods_match_events
WHERE match_id = '3825848'
ORDER BY id;

-- 5.2 Row count sanity check
SELECT
    COUNT(*) AS total_events
FROM ods_match_events
WHERE match_id = '3825848';

-- 5.3 Event-type coverage: confirms every source type_name mapped to
-- something sensible and no event fell through to a raw/unmapped label.
SELECT
    type_name,
    COUNT(*) AS event_count
FROM ods_match_events
WHERE match_id = '3825848'
GROUP BY type_name
ORDER BY event_count DESC;

-- 5.4 id is a dense sequence with no gaps or duplicates for this match.
SELECT
    COUNT(*) AS row_count,
    COUNT(DISTINCT id) AS distinct_ids,
    MIN(id) AS min_id,
    MAX(id) AS max_id
FROM ods_match_events
WHERE match_id = '3825848';
