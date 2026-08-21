create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default 'Player',
  total_points integer not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists public.gameweeks (
  id integer primary key,
  season text not null,
  starts_at timestamptz not null,
  ends_at timestamptz,
  status text not null default 'open' check (status in ('upcoming','open','locked','complete'))
);

create table if not exists public.fixtures (
  id uuid primary key default gen_random_uuid(),
  gameweek_id integer not null references public.gameweeks(id),
  kickoff timestamptz not null,
  home_team text not null,
  away_team text not null,
  home_score integer,
  away_score integer,
  status text not null default 'scheduled' check (status in ('scheduled','live','finished','postponed')),
  unique(gameweek_id,home_team,away_team)
);

create table if not exists public.predictions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  fixture_id uuid not null references public.fixtures(id) on delete cascade,
  gameweek_id integer not null references public.gameweeks(id),
  prediction text not null check (prediction in ('HOME','DRAW','AWAY')),
  booster boolean not null default false,
  points integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(user_id,fixture_id)
);

create table if not exists public.leagues (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  owner_id uuid not null references public.profiles(id) on delete cascade,
  invite_code text not null unique default upper(substr(encode(gen_random_bytes(6),'hex'),1,10)),
  created_at timestamptz not null default now()
);

create table if not exists public.league_members (
  league_id uuid not null references public.leagues(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key(league_id,user_id)
);

create index if not exists fixtures_gw_kickoff on public.fixtures(gameweek_id,kickoff);
create index if not exists predictions_user_gw on public.predictions(user_id,gameweek_id);

create or replace view public.leaderboard as
select id, display_name, total_points
from public.profiles
order by total_points desc, created_at asc;

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  insert into public.profiles(id,display_name)
  values(new.id,coalesce(split_part(new.email,'@',1),'Player'));
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
for each row execute procedure public.handle_new_user();

create or replace function public.enforce_prediction_rules()
returns trigger language plpgsql as $$
declare locked_at timestamptz; existing_booster boolean;
begin
  select starts_at into locked_at from public.gameweeks where id=new.gameweek_id;
  if now() >= locked_at then raise exception 'This gameweek is locked'; end if;
  if new.booster then
    select exists(select 1 from public.predictions p where p.user_id=new.user_id and p.gameweek_id=new.gameweek_id and p.booster=true and p.id<>new.id) into existing_booster;
    if existing_booster then raise exception 'Booster already used in this gameweek'; end if;
  end if;
  return new;
end $$;

drop trigger if exists prediction_rules on public.predictions;
create trigger prediction_rules before insert or update on public.predictions
for each row execute procedure public.enforce_prediction_rules();

create or replace function public.score_fixture(p_fixture_id uuid)
returns void language plpgsql security definer set search_path=public as $$
declare r record;
begin
  select * into r from public.fixtures where id=p_fixture_id and status='finished';
  if not found then raise exception 'Fixture is not finished'; end if;
  update public.predictions p
  set points = case
    when (r.home_score > r.away_score and p.prediction='HOME')
      or (r.home_score = r.away_score and p.prediction='DRAW')
      or (r.home_score < r.away_score and p.prediction='AWAY')
    then case when p.booster then 2 else 1 end
    else 0 end,
    updated_at=now()
  where p.fixture_id=p_fixture_id;
  update public.profiles pr
  set total_points=coalesce((select sum(points) from public.predictions p where p.user_id=pr.id),0)
  where id in(select user_id from public.predictions where fixture_id=p_fixture_id);
end $$;

alter table public.profiles enable row level security;
alter table public.gameweeks enable row level security;
alter table public.fixtures enable row level security;
alter table public.predictions enable row level security;
alter table public.leagues enable row level security;
alter table public.league_members enable row level security;

create policy profiles_read on public.profiles for select to authenticated using(true);
create policy profiles_update_own on public.profiles for update to authenticated using(id=auth.uid()) with check(id=auth.uid());
create policy gameweeks_read on public.gameweeks for select to authenticated using(true);
create policy fixtures_read on public.fixtures for select to authenticated using(true);
create policy predictions_read_own on public.predictions for select to authenticated using(user_id=auth.uid());
create policy predictions_insert_own on public.predictions for insert to authenticated with check(user_id=auth.uid());
create policy predictions_update_own on public.predictions for update to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid());
create policy leagues_read on public.leagues for select to authenticated using(owner_id=auth.uid() or exists(select 1 from public.league_members m where m.league_id=id and m.user_id=auth.uid()));
create policy leagues_insert on public.leagues for insert to authenticated with check(owner_id=auth.uid());
create policy members_read on public.league_members for select to authenticated using(user_id=auth.uid() or exists(select 1 from public.leagues l where l.id=league_id and l.owner_id=auth.uid()));
create policy members_insert_self on public.league_members for insert to authenticated with check(user_id=auth.uid());

insert into public.gameweeks(id,season,starts_at,ends_at,status)
values(1,'2026/27','2026-08-21T20:00:00+01:00','2026-08-24T22:30:00+01:00','open')
on conflict(id) do nothing;

insert into public.fixtures(gameweek_id,kickoff,home_team,away_team) values
(1,'2026-08-21T20:00:00+01:00','Arsenal','Coventry City'),
(1,'2026-08-22T12:30:00+01:00','Hull City','Manchester United'),
(1,'2026-08-22T15:00:00+01:00','Everton','Crystal Palace'),
(1,'2026-08-22T15:00:00+01:00','Ipswich Town','Sunderland'),
(1,'2026-08-22T15:00:00+01:00','Nottingham Forest','Leeds United'),
(1,'2026-08-22T17:30:00+01:00','Brentford','Tottenham Hotspur'),
(1,'2026-08-23T14:00:00+01:00','Brighton','Aston Villa'),
(1,'2026-08-23T14:00:00+01:00','Manchester City','AFC Bournemouth'),
(1,'2026-08-23T16:30:00+01:00','Newcastle United','Liverpool'),
(1,'2026-08-24T20:00:00+01:00','Fulham','Chelsea')
on conflict(gameweek_id,home_team,away_team) do nothing;
