-- Artikel Arena: secret-code progress sync. Run once in Supabase > SQL Editor.
-- The table is locked (RLS on, no policies). The app can only use the four functions below,
-- and only with the SHA-256 hash of a secret code. The code itself never reaches the server.

create table if not exists public.progress (
  code_hash  text primary key check (char_length(code_hash) = 64),
  data       jsonb not null,
  updated_at timestamptz not null default now()
);
alter table public.progress enable row level security;

create or replace function public.aa_load(h text) returns jsonb
language sql security definer set search_path = public as $$
  select jsonb_build_object('data', data, 'updated_at', updated_at) from public.progress where code_hash = h
$$;

create or replace function public.aa_save(h text, d jsonb) returns void
language plpgsql security definer set search_path = public as $$
begin
  if char_length(h) <> 64 then raise exception 'bad code'; end if;
  if pg_column_size(d) > 150000 then raise exception 'too large'; end if;
  insert into public.progress(code_hash, data) values (h, d)
  on conflict (code_hash) do update set data = excluded.data, updated_at = now();
end $$;

create or replace function public.aa_delete(h text) returns void
language sql security definer set search_path = public as $$
  delete from public.progress where code_hash = h
$$;

revoke all on function public.aa_load(text), public.aa_save(text, jsonb), public.aa_delete(text) from public;
grant execute on function public.aa_load(text), public.aa_save(text, jsonb), public.aa_delete(text) to anon, authenticated;
