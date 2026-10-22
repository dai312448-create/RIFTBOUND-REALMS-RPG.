-- REALITY: FELONY Build 0.5 — Supabase setup
-- Run this entire file in Supabase Dashboard > SQL Editor as project owner.
-- Never put a service_role key in the website. The game only uses the public anon/publishable key.

create extension if not exists pgcrypto;

create table if not exists public.rf_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  username text not null unique,
  gilt_shards bigint not null default 300 check (gilt_shards >= 0),
  highest_floor integer not null default 0 check (highest_floor between 0 and 99),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.rf_player_ids (
  user_id uuid not null references auth.users(id) on delete cascade,
  id_key text not null,
  id_data jsonb not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, id_key)
);

create table if not exists public.rf_coop_rooms (
  id uuid primary key default gen_random_uuid(),
  room_code text not null unique,
  host_id uuid not null references auth.users(id) on delete cascade,
  guest_id uuid references auth.users(id) on delete set null,
  status text not null default 'waiting' check (status in ('waiting','active','cleared','closed')),
  floor integer not null default 1 check (floor between 1 and 99),
  state jsonb not null default '{}'::jsonb,
  revision integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists rf_profiles_leaderboard_idx on public.rf_profiles (gilt_shards desc, highest_floor desc);
create index if not exists rf_rooms_waiting_idx on public.rf_coop_rooms (status, created_at) where status = 'waiting';
create index if not exists rf_ids_user_updated_idx on public.rf_player_ids (user_id, updated_at desc);

-- New accounts start with 300 Gilt Shards, only once per account.
create or replace function public.rf_create_profile_for_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  base_name text;
  safe_name text;
begin
  base_name := coalesce(nullif(trim(new.raw_user_meta_data->>'username'), ''), nullif(split_part(coalesce(new.email, ''), '@', 1), ''), 'Wanderer');
  base_name := regexp_replace(base_name, '[^[:alnum:]_ -]', '', 'g');
  safe_name := left(coalesce(nullif(base_name, ''), 'Wanderer'), 18) || '-' || lower(substr(replace(new.id::text, '-', ''), 1, 5));
  insert into public.rf_profiles (user_id, username, gilt_shards, highest_floor)
  values (new.id, safe_name, 300, 0)
  on conflict (user_id) do nothing;
  return new;
end;
$$;

drop trigger if exists rf_auth_user_created on auth.users;
create trigger rf_auth_user_created
after insert on auth.users
for each row execute procedure public.rf_create_profile_for_new_auth_user();

alter table public.rf_profiles enable row level security;
alter table public.rf_player_ids enable row level security;
alter table public.rf_coop_rooms enable row level security;

grant select on public.rf_profiles to anon, authenticated;
grant insert, update on public.rf_profiles to authenticated;
grant select, insert, update, delete on public.rf_player_ids to authenticated;
grant select, insert, update on public.rf_coop_rooms to authenticated;

drop policy if exists "public leaderboard read" on public.rf_profiles;
create policy "public leaderboard read" on public.rf_profiles
  for select to anon, authenticated using (true);
drop policy if exists "users can insert own profile" on public.rf_profiles;
create policy "users can insert own profile" on public.rf_profiles
  for insert to authenticated with check (auth.uid() = user_id);
drop policy if exists "users can update own profile" on public.rf_profiles;
create policy "users can update own profile" on public.rf_profiles
  for update to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "users can read own IDs" on public.rf_player_ids;
create policy "users can read own IDs" on public.rf_player_ids
  for select to authenticated using (auth.uid() = user_id);
drop policy if exists "users can insert own IDs" on public.rf_player_ids;
create policy "users can insert own IDs" on public.rf_player_ids
  for insert to authenticated with check (auth.uid() = user_id);
drop policy if exists "users can update own IDs" on public.rf_player_ids;
create policy "users can update own IDs" on public.rf_player_ids
  for update to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
drop policy if exists "users can delete own IDs" on public.rf_player_ids;
create policy "users can delete own IDs" on public.rf_player_ids
  for delete to authenticated using (auth.uid() = user_id);

drop policy if exists "authenticated users can read rooms" on public.rf_coop_rooms;
create policy "authenticated users can read rooms" on public.rf_coop_rooms
  for select to authenticated using (true);
drop policy if exists "users can create rooms as host" on public.rf_coop_rooms;
create policy "users can create rooms as host" on public.rf_coop_rooms
  for insert to authenticated with check (auth.uid() = host_id);
drop policy if exists "participants can update room and players can join waiting rooms" on public.rf_coop_rooms;
drop policy if exists "room host updates own rooms" on public.rf_coop_rooms;
create policy "room host updates own rooms" on public.rf_coop_rooms
  for update to authenticated
  using (host_id = auth.uid())
  with check (host_id = auth.uid());
drop policy if exists "room guest updates joined rooms" on public.rf_coop_rooms;
create policy "room guest updates joined rooms" on public.rf_coop_rooms
  for update to authenticated
  using (guest_id = auth.uid())
  with check (guest_id = auth.uid() and host_id <> auth.uid());

-- Secure join: a player can occupy only the guest slot; they cannot take ownership of a room.
create or replace function public.rf_join_coop_room(
  p_room_code text default null,
  p_hp integer default 300,
  p_username text default 'Player'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  r public.rf_coop_rooms;
  new_state jsonb;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  select * into r
  from public.rf_coop_rooms
  where status = 'waiting'
    and guest_id is null
    and host_id <> auth.uid()
    and (p_room_code is null or room_code = upper(trim(p_room_code)))
  order by created_at
  limit 1
  for update skip locked;
  if not found then
    raise exception 'No waiting room was found';
  end if;
  new_state := coalesce(r.state, '{}'::jsonb);
  new_state := jsonb_set(
    new_state,
    '{hpByUser}',
    coalesce(new_state->'hpByUser', '{}'::jsonb) || jsonb_build_object(auth.uid()::text, greatest(1, least(5000, coalesce(p_hp, 300)))),
    true
  );
  new_state := jsonb_set(
    new_state,
    '{logs}',
    coalesce(new_state->'logs', '[]'::jsonb) || jsonb_build_array(left(coalesce(nullif(trim(p_username), ''), 'A player'), 24) || ' đã tham gia phòng.'),
    true
  );
  update public.rf_coop_rooms
    set guest_id = auth.uid(), status = 'active', state = new_state,
        revision = revision + 1, updated_at = now()
    where id = r.id
    returning * into r;
  return to_jsonb(r);
end;
$$;
revoke all on function public.rf_join_coop_room(text, integer, text) from public;
grant execute on function public.rf_join_coop_room(text, integer, text) to authenticated;

-- Security note: this is a client-side game prototype. Auth/RLS separates accounts and IDs,
-- but a browser game cannot prevent a determined player from editing client-side currency.
-- For a competitive production release, move reward calculation and wallet changes to server-side RPC/Edge Functions.
