create table if not exists match_metadata (
    source_match_id varchar(50),
    match_id              VARCHAR(50)   NOT NULL,
    competition_id        VARCHAR(50),
    season_id             VARCHAR(50)

    --constraint fk_key references statsbomb_raw_events(match_id)
    );


insert into match_metadata (source_match_id,match_id, competition_id, season_id)
values
(
 3825848,
 3825848,
 'LA_LIGA', --
 '2015_2016'
);
--NOTE
-- Rubén Iván Martínez Andrade wore the number
-- 13 jersey as a goalkeeper during his stint with L
-- evante UD, specifically in the 2015–16 La Liga season.

select * from match_metadata