-- Artikel Arena: owner reports. Run in Supabase > SQL Editor (read-only, safe).

-- 1) Summary: how many codes, how many active
select
  count(*)                                                         as toplam_kod,
  count(*) filter (where updated_at > now() - interval '24 hours') as son_24_saat,
  count(*) filter (where updated_at > now() - interval '7 days')   as bu_hafta,
  count(*) filter (where updated_at > now() - interval '30 days')  as son_30_gun,
  max(updated_at)                                                  as son_aktivite
from public.progress;

-- 2) Per code: nickname, last activity, mastered / almost-mastered counts
select
  count(*) over ()                                   as toplam_kod,
  coalesce(nullif(p.data->>'nick',''), '-')          as takma_ad,
  left(p.code_hash, 8)                               as kod_kimligi,
  p.updated_at                                       as son_aktivite,
  (p.data->>'xp')::int                               as xp,
  (select count(*) from jsonb_each(coalesce(p.data->'stats','{}'::jsonb)) e where e.value->>'st' = 'm') as artikel_master,
  (select count(*) from jsonb_each(coalesce(p.data->'stats','{}'::jsonb)) e where e.value->>'st' = 'a') as artikel_almost,
  (select count(*) from jsonb_each(coalesce(p.data->'pst','{}'::jsonb))   e where e.value->>'st' = 'm') as plural_master,
  (select count(*) from jsonb_each(coalesce(p.data->'pst','{}'::jsonb))   e where e.value->>'st' = 'a') as plural_almost
from public.progress p
order by p.updated_at desc;
