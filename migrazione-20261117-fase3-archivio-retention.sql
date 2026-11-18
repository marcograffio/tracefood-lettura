-- Fase 3: archivio con QR storico, retention configurabile, pulizia dei pesi.
-- Idempotente. Eseguito il 2026-11-17 sul progetto ctstjhpisuonwpztgumc.
-- Contiene: colonne, vincolo, indice, confirm_qr_preparation aggiornata,
--           prune_preparation_payload().
--
-- La schedulazione cron NON e' inclusa perche' cron.schedule va eseguita una
-- sola volta: job 'prune-preparations', '0 3 * * *', attivo (jobid 2).
-- Comando gia' eseguito:
--   select cron.schedule('prune-preparations', '0 3 * * *',
--                        'select public.prune_preparation_payload();');

begin;

-- 1. Colonne
alter table public.preparation_ingredients add column if not exists foto_url text;
alter table public.preparations add column if not exists esaurita_il timestamptz;
alter table public.preparations add column if not exists qr_code_storico text;
alter table public.tenants add column if not exists storico_giorni integer not null default 5;
alter table public.tenants add column if not exists retention_foto_giorni integer not null default 15;

-- 2. Vincolo di coerenza (idempotente)
alter table public.tenants drop constraint if exists tenants_retention_coerente;
alter table public.tenants
  add constraint tenants_retention_coerente
  check (retention_foto_giorni >= storico_giorni);

-- 3. Indice per storico e pulizia
create index if not exists preparations_tenant_esaurita_idx
  on public.preparations (tenant_id, esaurita_il)
  where esaurita_il is not null;

-- 4. Chiusura scheda: conserva il codice QR nello storico
drop function if exists public.confirm_qr_preparation(uuid, uuid, uuid, text, text, text, text);
create or replace function public.confirm_qr_preparation(
  p_tenant_id uuid,
  p_qr_id uuid,
  p_preparation_id uuid,
  p_nome text,
  p_data_preparazione text,
  p_note text,
  p_foto_url text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_profile_id uuid;
  v_qr_code text;
  v_qr_state text;
  v_current_preparation_id uuid;
  v_result_id uuid;
begin
  select u.id
  into v_profile_id
  from public.users u
  where u.user_id = (select auth.uid());

  if v_profile_id is null or not exists (
    select 1
    from public.user_tenants ut
    where ut.user_profile_id = v_profile_id
      and ut.tenant_id = p_tenant_id
  ) then
    raise exception 'Azienda non autorizzata'
      using errcode = '42501';
  end if;

  if nullif(pg_catalog.btrim(p_nome), '') is null then
    raise exception 'Il nome della preparazione è obbligatorio'
      using errcode = '22023';
  end if;

  select q.codice_univoco, q.stato, q.preparation_id
  into v_qr_code, v_qr_state, v_current_preparation_id
  from public.qr_pool q
  where q.id = p_qr_id
    and q.tenant_id = p_tenant_id
  for update;

  if not found or v_qr_state = 'scaduto' then
    raise exception 'QR non valido o scaduto'
      using errcode = '22023';
  end if;

  if p_preparation_id is not null and not exists (
    select 1
    from public.preparations p
    where p.id = p_preparation_id
      and p.tenant_id = p_tenant_id
      and not p.is_deleted
  ) then
    raise exception 'Preparazione non valida per questa azienda'
      using errcode = '22023';
  end if;

  if v_qr_state = 'assegnato' and v_current_preparation_id is null then
    raise exception 'Stato QR non coerente con il suo abbinamento'
      using errcode = '22023';
  end if;
  if v_qr_state = 'disponibile' and v_current_preparation_id is not null then
    raise exception 'Stato QR non coerente con il suo abbinamento'
      using errcode = '22023';
  end if;

  -- Riuso contenitore: la scheda precedente viene chiusa e archiviata,
  -- conservando il codice QR per la tracciabilità ASL.
  if v_current_preparation_id is not null
     and v_current_preparation_id is distinct from p_preparation_id then
    update public.preparations
    set stato = 'esaurita',
        esaurita_il = pg_catalog.coalesce(esaurita_il, pg_catalog.now()),
        qr_code_storico = v_qr_code,
        qr_code_univoco = null
    where id = v_current_preparation_id
      and tenant_id = p_tenant_id
      and qr_code_univoco = v_qr_code;

    if not found then
      raise exception 'Abbinamento QR non coerente'
        using errcode = '22023';
    end if;
  end if;

  if p_preparation_id is null then
    insert into public.preparations (
      tenant_id,
      creato_da,
      nome_pietanza,
      data_preparazione,
      note,
      foto_url,
      qr_code_univoco
    )
    values (
      p_tenant_id,
      v_profile_id,
      pg_catalog.btrim(p_nome),
      nullif(pg_catalog.btrim(p_data_preparazione), ''),
      nullif(pg_catalog.btrim(p_note), ''),
      nullif(p_foto_url, ''),
      v_qr_code
    )
    returning id into v_result_id;
  else
    update public.preparations
    set nome_pietanza = pg_catalog.btrim(p_nome),
        data_preparazione = nullif(pg_catalog.btrim(p_data_preparazione), ''),
        note = nullif(pg_catalog.btrim(p_note), ''),
        foto_url = nullif(p_foto_url, ''),
        qr_code_univoco = v_qr_code
    where id = p_preparation_id
      and tenant_id = p_tenant_id
      and not is_deleted
    returning id into v_result_id;

    if v_result_id is null then
      raise exception 'Preparazione non trovata'
        using errcode = '22023';
    end if;
  end if;

  return v_result_id;
end;
$$;

revoke all on function public.confirm_qr_preparation(uuid, uuid, uuid, text, text, text, text) from public, anon;
grant execute on function public.confirm_qr_preparation(uuid, uuid, uuid, text, text, text, text) to authenticated;

-- 5. Pulizia dei pesi (solo foto, mai righe)
create or replace function public.prune_preparation_payload()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_photos integer := 0;
  v_ingredient_photos integer := 0;
begin
  update public.preparations p
  set foto_url = null
  from public.tenants t
  where t.id = p.tenant_id
    and p.foto_url is not null
    and p.esaurita_il is not null
    and p.esaurita_il < pg_catalog.now() - pg_catalog.make_interval(days => t.retention_foto_giorni);
  get diagnostics v_photos = row_count;

  update public.preparation_ingredients pi
  set foto_url = null
  from public.preparations p
  join public.tenants t on t.id = p.tenant_id
  where pi.preparation_id = p.id
    and pi.foto_url is not null
    and p.esaurita_il is not null
    and p.esaurita_il < pg_catalog.now() - pg_catalog.make_interval(days => t.retention_foto_giorni);
  get diagnostics v_ingredient_photos = row_count;

  return v_photos + v_ingredient_photos;
end;
$$;

revoke all on function public.prune_preparation_payload() from public, anon, authenticated;

notify pgrst, 'reload schema';

commit;

-- ===== VERIFICA =====
-- Il job di pulizia esiste ed e' attivo?
--   select jobid, jobname, schedule, active from cron.job
--    where jobname = 'prune-preparations';
--
-- Le finestre configurate per azienda?
--   select nome_azienda, storico_giorni, retention_foto_giorni
--     from public.tenants order by creato_il;
--
-- Esito del job:
--   select jobid, status, start_time, return_message
--     from cron.job_run_details where jobid = 2
--    order by start_time desc limit 5;