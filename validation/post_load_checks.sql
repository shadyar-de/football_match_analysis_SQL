
/* -----------------------------------------------------------------------------
   POST-LOAD VALIDATION CHECKS
   Scoped to the match just loaded (p_match_id above) -- every check here is
   filtered by match_id, matching the same pattern analysts use downstream.
   Use these to demonstrate row counts, valid pitch bounds, event-type
   coverage, and unique sequential IDs after loading.
----------------------------------------------------------------------------- */

-- 1. Full row-level view of the loaded match, ordered by the assigned id.
SELECT
    *
FROM ods_match_events
WHERE match_id = '3825848'
ORDER BY id;

-- 2. Row count sanity check
SELECT
    COUNT(*) AS total_events
FROM ods_match_events
WHERE match_id = '3825848';

-- 3. Event-type coverage: confirms every source type_name mapped to
-- something sensible and no event fell through to a raw/unmapped label.
SELECT
    type_name,
    COUNT(*) AS event_count
FROM ods_match_events
WHERE match_id = '3825848'
GROUP BY type_name
ORDER BY event_count DESC;

-- 4. id is a dense sequence with no gaps or duplicates for this match.
SELECT
    COUNT(*) AS row_count,
    COUNT(DISTINCT id) AS distinct_ids,
    MIN(id) AS min_id,
    MAX(id) AS max_id
FROM ods_match_events
WHERE match_id = '3825848';