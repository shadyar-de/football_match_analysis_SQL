/* =============================================================================
   MATCH METADATA
   =============================================================================

   Supplies match_id, competition_id, and season_id -- the three values the
   column mapping documents as "not present in the source event rows,
   injected at load time from metadata." This table is that metadata source:
   one row per match, keyed by the match's raw StatsBomb id.

   Load order: this table must be seeded for a match before
   load_ods_match_events() is called for it.
============================================================================= */

CREATE TABLE IF NOT EXISTS match_metadata
(
    source_match_id INTEGER     NOT NULL,
    match_id        VARCHAR(50) NOT NULL,
    competition_id  VARCHAR(50) NOT NULL,
    season_id       VARCHAR(50) NOT NULL,

    CONSTRAINT pk_match_metadata
        PRIMARY KEY (source_match_id)
);

/* -----------------------------------------------------------------------------
   SEED DATA
   One INSERT per match that's been loaded. Safe to re-run -- ON CONFLICT
   means running this file again will not create a duplicate row.
----------------------------------------------------------------------------- */
INSERT INTO
    match_metadata
(
    source_match_id,
    match_id,
    competition_id,
    season_id
)
VALUES (3825848, '3825848', 'LA_LIGA', '2015_2016')
ON CONFLICT (source_match_id) DO NOTHING;

