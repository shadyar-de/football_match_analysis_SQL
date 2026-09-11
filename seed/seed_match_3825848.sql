/* -----------------------------------------------------------------------------
   SEED DATA -- match 3825848 (La Liga, 2015/2016)

   One file per match, one CALL per file. Safe to re-run --
   sp_seed_match_metadata uses ON CONFLICT DO NOTHING internally.

   Add a new match by adding a new file here (seed_match_<id>.sql), not by
   editing this one.
----------------------------------------------------------------------------- */
CALL sp_seed_match_metadata(3825848, '3825848', 'LA_LIGA', '2015_2016');