with passing as (
select 
    r.team, r.full_name,r.status,r.gsis_id,
    sum(case when p.sack < 1 and p.fumble_lost < 1 then 1 else 0 end) as attempts,
    count(p.*) as dropbacks,
    sum(p.sack) as sacks,
    sum(p.interception) as interceptions,
    sum(p.touchdown) as touchdowns,
    sum(p.incomplete_pass) as incompletions,
    sum(p.yards_gained) as yards_gained,
    sum(p.fumble_lost) as fumbles_lost
    from nfl2020.roster as r inner join
nfl2020.pbp_passing as p on r.gsis_id = p.gsis_id
where r.position = 'QB'
    group by 1,2,3,4
    ),
    avg_interceptions_attempts as (
        select sum(interceptions)/sum(attempts) as overall_interception_rate, sum(attempts)/32 as avg_attempts,
        sum(case when attempts < 30 then interceptions else 0 end)/sum(case when attempts < 30 then attempts else 0 end) as under_30_interception_rate
    from passing
    ),
    over_30_interception_rates as (

    select p.team, p.full_name, p.attempts,p.interceptions, aia.overall_interception_rate,
    aia.avg_attempts,
    case when interceptions = 0 then (aia.overall_interception_rate*aia.avg_attempts*(1-(p.attempts/aia.avg_attempts)) + p.interceptions)/aia.avg_attempts
    else
    p.interceptions/p.attempts end as interception_rate,
    aia.under_30_interception_rate, p.gsis_id
    from passing as p inner join
    avg_interceptions_attempts as aia on 1=1
    where attempts>30
        ),
        player_heights as (
            select split_part(height,'-',1)::int as feet,
    split_part(height,'-',2)::int/12 as inches,
    split_part(height,'-',1)::int + split_part(height,'-',2)::int/12  as height,
            r.full_name, r.team,r.gsis_id

    from nfl2020.roster as r
            where r.position = 'QB'
        ),
    height_interception_rate as (
    select r.height,
    ps.interception_rate as interception_rate,r.full_name, r.team

    from player_heights as r inner join
    over_30_interception_rates as ps on ps.gsis_id = r.gsis_id 

        ),
        height_interception_regr as (
        select 

        REGR_SLOPE(h.interception_rate, h.height) as height_interception_slope,
    regr_intercept(h.interception_rate,h.height) as height_interception_int
    from height_interception_rate as h
            ),
            under_30_interception_rates as (
            select r.full_name, r.team,r.height,
            r.height*height_interception_slope + height_interception_int + .00806 as interception_rate,
                coalesce(p.attempts, 0) as attempts from
            player_heights as r left join
            passing as p on p.gsis_id = r.gsis_id inner join
            height_interception_regr as hir on 1=1
            where (p.attempts< 30 or p.attempts is null)
                ),
                all_qb_interception_rates as (
                select * from 
                (select full_name, team, height,attempts, interception_rate
                from under_30_interception_rates) as under_30
                UNION ALL
                select * from 
                (select a.full_name, a.team, h.height,a.attempts, a.interception_rate from over_30_interception_rates as a
                inner join player_heights as h on a.gsis_id = h.gsis_id) as over_30
                    ),
        atts_per_qb as (
select 
r.team, r.full_name,
    r.status,
    case when status <> 'Injured Reserve' then 0 else 1 end as inj_status,
p.sack as sack

from nfl2020.roster as r left join
nfl2020.pbp_passing as  p on p.gsis_id = r.gsis_id
where r.position = 'QB'
    
    ),
    expected_snaps_injured as (

    select 
    REGR_SLOPE(inj_status, sack) as injured_pct_slope
    from atts_per_qb
            
            
        
        ),
        prob_getting_injured as (
        select p.full_name, (sacks/attempts)*aia.avg_attempts*injured_pct_slope as pct_injured,
        (sacks/attempts)
        from passing as p inner join
        expected_snaps_injured on 1=1 inner join
        avg_interceptions_attempts as aia on 1=1
        where p.attempts > 30
            ),
    passing_stats as (

    select p.team, p.full_name, touchdowns/attempts as td_rate,
    (fumbles_lost+interceptions)/dropbacks as turnover_rate,
    yards_gained/attempts as yards_per_attempt,
    interceptions/dropbacks as interception_rate,p.gsis_id,attempts
    from passing as p inner join
        nfl2020.roster as r on p.gsis_id = r.gsis_id
    where attempts>30
        and (r.status <> 'Injured Reserve')
    
    
    

),
team_snaps as (

    select count(*) as team_snaps,r.team from nfl2020.pbp_passing as p inner join
    nfl2020.roster as r on p.gsis_id = r.gsis_id
    group by r.team
    
),

pct_snaps as (

    select t.team_snaps,r.full_name, r.team,count(p.*) as snaps from nfl2020.roster as r inner join
    nfl2020.pbp_passing as p on r.gsis_id = p.gsis_id inner join
    team_snaps as t on t.team = r.team
    group by 1,2,3

)
-- select * from passing_stats
,
passing_ranks as (
select full_name, row_number() over ( order by td_rate desc) as td_rank,
row_number() over ( order by turnover_rate desc) as turnover_rank,
row_number() over ( order by yards_per_attempt desc) as yards_per_attempt_rank,attempts

from passing_stats
    ),
    name_rank_pct_snaps as(
    select passing_ranks.full_name, (td_rank + (59-turnover_rank) + yards_per_attempt_rank)/(58*3) as avg_rank_percentile,
    pct_snaps.snaps/pct_snaps.team_snaps as pct_snaps, attempts
    
    from passing_ranks inner join 
    nfl2020.roster as r on r.full_name = passing_ranks.full_name inner join
    pct_snaps on pct_snaps.full_name = r.full_name
        where r.position = 'QB'
        ),
    -- regre_slae(y,x)
    pct_snaps_regression as (
    select REGR_SLOPE(pct_snaps, avg_rank_percentile) as slope
    from name_rank_pct_snaps
        where attempts > 30
        ),
            pct_snaps_intercept as (
    select REGR_INTERCEPT(pct_snaps, avg_rank_percentile) as intercept
    from name_rank_pct_snaps
                where attempts >30
        ),
        expected_snaps_not_benched as (
        select full_name,avg_rank_percentile, pct_snaps, psr.slope as not_benched_pct_slope,psi.intercept as not_benched_pct_int,
        least(avg_rank_percentile*slope + intercept+.21,1) as expected_snaps_not_benched
        from name_rank_pct_snaps
        inner join
        pct_snaps_regression as psr on 1=1 inner join
        pct_snaps_intercept as psi on 1=1
            ),
            total_expected_snaps as (
            select esnb.full_name,esnb.expected_snaps_not_benched,pgi.pct_injured,
            esnb.expected_snaps_not_benched*(1-pgi.pct_injured) as total_pct_snaps
            from expected_snaps_not_benched as esnb inner join
            prob_getting_injured as pgi on esnb.full_name = pgi.full_name
                ),
                first_start as (
                    
                    select r.full_name, r.team, min(pbp.game_date) as min_start
                    from 
                    nfl2020.roster as r left join
                    nfl2020.pbp_passing as p on r.gsis_id = p.gsis_id left join
                nfl2020.pbp as pbp on p.pbp_id = pbp.pbp_id 
                    where r.position = 'QB'
                    group by 1,2
                
                ),
                depth_chart_rank as (
                select f.full_name, row_number() over (partition by team order by (1-t.total_pct_snaps),min_start asc) as depth_chart_rank, f.team
                from first_start as f left join
                    total_expected_snaps as t on f.full_name = t.full_name
                    ),
                    team_snaps_by_depth as (
                    select d.team, 
                        max(case when d.depth_chart_rank = 1 and s.total_pct_snaps is not null
                            then s.total_pct_snaps
                        else null end) as first_string_pct_snaps,
                       max(case when d.depth_chart_rank = 2 then s.total_pct_snaps
                        else null end) as second_string_pct_snaps,
                      max(case when d.depth_chart_rank = 3 then s.total_pct_snaps
                        else null end) as third_string_pct_snaps
                        from depth_chart_rank as d inner join
                        total_expected_snaps as s on d.full_name = s.full_name
                        group by 1
                        ),
                        final_expected_snaps as (
            select d.full_name, d.team, d.depth_chart_rank, 
            case when d.depth_chart_rank = 1 then first_string_pct_snaps
            when d.depth_chart_rank = 2 and second_string_pct_snaps is not null
            then (1-first_string_pct_snaps)*second_string_pct_snaps else 0 end as expected_snaps
            from  depth_chart_rank as d inner join
            team_snaps_by_depth as t on d.team = t.team
                            ),
                leftover_team_snaps as (
            select s.team, 1-sum(s.expected_snaps) as leftover_snaps,
            sum(case when s.expected_snaps = 0 then 1 else 0 end) as remaining_qbs
            from final_expected_snaps as s group by s.team
                    ),
                    all_qb_expected_snaps as (
                    select f.full_name, f.team,
                    case when f.expected_snaps = 0 then t.leftover_snaps/t.remaining_qbs
                    else f.expected_snaps end as expected_snaps
                    from final_expected_snaps as f inner join
                    leftover_team_snaps as t on f.team = t.team
            )
            select a.full_name, a.team,
            a.interception_rate, b.expected_snaps*aia.avg_attempts as expected_snaps,
            1- pow(1-a.interception_rate,b.expected_snaps*aia.avg_attempts) as chance_of_throwing_int
            from all_qb_interception_rates as a inner join
            
                    all_qb_expected_snaps as b on a.full_name = b.full_name inner join
                    avg_interceptions_attempts as aia on 1=1