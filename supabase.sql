-- Artikel Arena: secret-code progress sync (v2, 5-character codes + attempt limit).
-- Run in Supabase > SQL Editor (safe to re-run). The table is locked (RLS on, no policies);
-- the app only calls the functions below, with the SHA-256 hash of a code.

create table if not exists public.progress (
  code_hash  text primary key check (char_length(code_hash) = 64),
  data       jsonb not null,
  updated_at timestamptz not null default now()
);
alter table public.progress enable row level security;

-- log of failed lookups, used for the global attempt limit
create table if not exists public.aa_misses (ts timestamptz not null default now());
alter table public.aa_misses enable row level security;

create or replace function public.aa_throttle() returns void
language plpgsql security definer set search_path = public as $$
begin
  delete from public.aa_misses where ts < now() - interval '10 minutes';
  if (select count(*) from public.aa_misses where ts > now() - interval '1 minute') >= 30 then
    raise exception 'rate_limited';
  end if;
end $$;

create or replace function public.aa_load(h text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r jsonb;
begin
  perform public.aa_throttle();
  select jsonb_build_object('data', data, 'updated_at', updated_at) into r from public.progress where code_hash = h;
  if r is null then insert into public.aa_misses default values; end if;
  return r;
end $$;

-- update an EXISTING code only (a wrong guess counts as a miss)
create or replace function public.aa_save(h text, d jsonb) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform public.aa_throttle();
  if char_length(h) <> 64 then raise exception 'bad code'; end if;
  if pg_column_size(d) > 150000 then raise exception 'too large'; end if;
  update public.progress set data = d, updated_at = now() where code_hash = h;
  if not found then
    insert into public.aa_misses default values;
    raise exception 'not_found';
  end if;
end $$;

-- create a NEW code; returns false if the code is already taken
create or replace function public.aa_create(h text, d jsonb) returns boolean
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if char_length(h) <> 64 then raise exception 'bad code'; end if;
  if pg_column_size(d) > 150000 then raise exception 'too large'; end if;
  insert into public.progress(code_hash, data) values (h, d) on conflict (code_hash) do nothing;
  get diagnostics n = row_count;
  return n = 1;
end $$;

create or replace function public.aa_delete(h text) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform public.aa_throttle();
  delete from public.progress where code_hash = h;
  if not found then insert into public.aa_misses default values; end if;
end $$;

revoke all on function public.aa_throttle(), public.aa_load(text), public.aa_save(text, jsonb), public.aa_create(text, jsonb), public.aa_delete(text) from public;
grant execute on function public.aa_load(text), public.aa_save(text, jsonb), public.aa_create(text, jsonb), public.aa_delete(text) to anon, authenticated;
