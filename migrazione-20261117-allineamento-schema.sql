-- Allineamento schema TracciaFood (database esistente, generazione precedente).
-- Additivo e idempotente: crea solo cio' che manca, non elimina dati.
-- I QR gia' stampati NON vengono rigenerati: il formato legacy resta valido.
--
-- Eseguire nell'SQL Editor di Supabase e incollare l'output della sezione VERIFICA.

begin;

create schema if not exists extensions;
-- GoTrue richiede stringhe vuote, non NULL, sui token di auth.users
do $$
declare
  c text;
begin
  for c in
    select unnest(array[
      'confirmation_token','recovery_token','email_change_token_new','email_change',
      'email_change_token_current','phone_change','phone_change_token','reauthentication_token'
    ])
  loop
    if exists (
      select 1 from information_schema.columns
      where table_schema = 'auth' and table_name = 'users' and column_name = c
    ) then
      execute pg_catalog.format('update auth.users set %I = %L where %I is null', c, '', c);
    end if;
  end loop;
end;
$$;

create extension if not exists pgcrypto with schema extensions;

-- Pre-flight: tabelle base obbligatorie
do $$
begin
  if to_regclass('public.tenants') is null
     or to_regclass('public.users') is null
     or to_regclass('public.preparations') is null then
    raise exception 'Pre-flight: tabelle base mancanti (tenants/users/preparations)';
  end if;
end;
$$;

-- 1. Tabelle mancanti
create table if not exists public.user_tenants (
  user_profile_id uuid not null references public.users(id) on delete cascade,
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  first_accessed_at timestamptz,
  last_accessed_at timestamptz,
  creato_il timestamptz not null default now(),
  primary key (user_profile_id, tenant_id)
);
-- Colonne anagrafiche che possono mancare nelle versioni piu vecchie di tenants
alter table public.tenants add column if not exists partita_iva text;
alter table public.tenants add column if not exists via text;
alter table public.tenants add column if not exists numero_civico text;
alter table public.tenants add column if not exists cap text;
alter table public.tenants add column if not exists citta text;
alter table public.tenants add column if not exists provincia text;
alter table public.tenants add column if not exists telefono text;
alter table public.tenants add column if not exists cellulare text;
alter table public.tenants add column if not exists email_contatto text;
alter table public.tenants add column if not exists codice_sdi text;
alter table public.tenants add column if not exists settore_merceologico text;
alter table public.tenants add column if not exists stato text default 'attivo';
alter table public.tenants add column if not exists deleted_at timestamptz;
alter table public.tenants add column if not exists creato_il timestamptz default now();

create table if not exists public.tracciafood_schema_migrations (
  version text primary key,
  applied_at timestamptz not null default now()
);
alter table public.tracciafood_schema_migrations enable row level security;
revoke all on public.tracciafood_schema_migrations from public, anon, authenticated;
-- 2. Pool QR e tracciamento stampa
create table if not exists public.qr_pool (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  preparation_id uuid unique references public.preparations(id) on delete set null,
  codice_univoco text not null unique,
  stato text not null default 'disponibile' check (stato in ('disponibile', 'assegnato', 'scaduto')),
  creato_il timestamptz not null default now(),
  assegnato_il timestamptz
);
alter table public.qr_pool add column if not exists assegnato_il timestamptz;
alter table public.qr_pool add column if not exists lotto_stampa uuid;
alter table public.qr_pool add column if not exists stampato_il timestamptz;
alter table public.qr_pool add column if not exists stampato_da uuid references public.users(id) on delete set null;
alter table public.qr_pool add column if not exists annullato_il timestamptz;

-- Colonne che potrebbero mancare nelle versioni piu vecchie del pool
alter table public.qr_pool add column if not exists tenant_id uuid;
alter table public.qr_pool add column if not exists preparation_id uuid;
alter table public.qr_pool add column if not exists codice_univoco text;
alter table public.qr_pool add column if not exists stato text default 'disponibile';
alter table public.qr_pool add column if not exists creato_il timestamptz default now();

-- Serve per gli ON CONFLICT dei trigger QR
do $$
begin
  if exists (
    select 1 from public.qr_pool
    where codice_univoco is not null
    group by codice_univoco
    having count(*) > 1
  ) then
    raise exception 'Pre-flight: qr_pool contiene codici duplicati, risolverli prima di migrare';
  end if;
end;
$$;

create unique index if not exists qr_pool_codice_univoco_uidx
  on public.qr_pool (codice_univoco);

-- 3. Tabelle ingredienti (solo se mancanti)
create table if not exists public.ingredient_lots (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  ingrediente text not null,
  numero_lotto text not null,
  fornitore text,
  documento_riferimento text,
  ricevuto_il date,
  scade_il date,
  quantita numeric check (quantita is null or quantita >= 0),
  unita text,
  note text,
  creato_da uuid references public.users(id) on delete set null,
  creato_il timestamptz not null default now()
);
create table if not exists public.preparation_ingredients (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  preparation_id uuid not null,
  ingredient_lot_id uuid,
  ingrediente text not null,
  quantita numeric check (quantita is null or quantita >= 0),
  unita text,
  note text,
  creato_da uuid references public.users(id) on delete set null,
  creato_il timestamptz not null default now(),
  constraint preparation_ingredients_preparation_fk
    foreign key (preparation_id, tenant_id)
    references public.preparations(id, tenant_id) on delete cascade,
  constraint preparation_ingredients_lot_fk
    foreign key (ingredient_lot_id, tenant_id)
    references public.ingredient_lots(id, tenant_id)
);
alter table public.preparation_ingredients add column if not exists tenant_id uuid;
alter table public.preparation_ingredients add column if not exists ingredient_lot_id uuid;
alter table public.preparation_ingredients add column if not exists ingrediente text;
alter table public.preparation_ingredients add column if not exists quantita numeric;
alter table public.preparation_ingredients add column if not exists unita text;
alter table public.preparation_ingredients add column if not exists note text;
alter table public.preparation_ingredients add column if not exists creato_da uuid;
alter table public.preparation_ingredients add column if not exists creato_il timestamptz default now();

alter table public.ingredient_lots add column if not exists tenant_id uuid;
alter table public.ingredient_lots add column if not exists ingrediente text;
alter table public.ingredient_lots add column if not exists numero_lotto text;
alter table public.ingredient_lots add column if not exists creato_il timestamptz default now();

alter table public.ingredients add column if not exists tenant_id uuid;
alter table public.ingredients add column if not exists nome text;
alter table public.ingredients add column if not exists lotto text;
alter table public.ingredients add column if not exists foto_url text;
alter table public.ingredients add column if not exists creato_il timestamptz default now();
create unique index if not exists preparations_id_tenant_uidx
  on public.preparations (id, tenant_id);
create unique index if not exists ingredient_lots_id_tenant_uidx
  on public.ingredient_lots (id, tenant_id);
create index if not exists qr_pool_lotto_stampa_idx
  on public.qr_pool (lotto_stampa);
-- 4. Rimozione trigger QR legacy
drop trigger if exists preparations_prepare_qr on public.preparations;
drop trigger if exists preparations_assign_qr on public.preparations;
drop trigger if exists preparations_sync_qr on public.preparations;
drop trigger if exists preparations_release_qr on public.preparations;
drop trigger if exists genera_qr_preparazione on public.preparations;
drop trigger if exists libera_qr_preparazione on public.preparations;
drop trigger if exists assign_preparation_qr on public.preparations;

-- 5. Funzioni: ricreate per allineare firme e logica
drop function if exists public.record_tenant_access(uuid);
drop function if exists public.generate_qr_batch(uuid, integer);
drop function if exists public.mark_qr_batch_printed(uuid);
drop function if exists public.confirm_qr_preparation(uuid, uuid, uuid, text, text, text, text);
drop function if exists public.svuota_cestino_preparazioni();
drop function if exists public.svuota_cestino_preparazioni(uuid);
drop function if exists public.crea_nuovo_ristorante(text, text, text, text, text, text, text, text, text, text, text, text, text, text, text);
drop function if exists public.qr_checksum(text);
drop function if exists public.qr_random_body(integer);
drop function if exists public.qr_build_code(text);
drop function if exists public.prepare_preparation_qr();
drop function if exists public.assign_preparation_qr();
drop function if exists public.sync_preparation_qr();
drop function if exists public.release_preparation_qr();

create or replace function public.is_superadmin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.users u
    where u.user_id = (select auth.uid())
      and (u.is_superadmin or u.ruolo = 'superadmin')
  );
$$;
revoke all on function public.is_superadmin() from public, anon;
grant execute on function public.is_superadmin() to authenticated;

create or replace function public.qr_checksum(p_body text)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  alphabet constant text := '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
  v_value integer := 0;
  v_index integer;
  i integer;
begin
  if p_body is null or pg_catalog.length(p_body) = 0 then
    return null;
  end if;

  for i in 1..pg_catalog.length(p_body) loop
    v_index := pg_catalog.strpos(alphabet, pg_catalog.substr(p_body, i, 1)) - 1;
    if v_index < 0 then
      return null;
    end if;
    v_value := (v_value * 32 + v_index) % 97;
  end loop;

  return pg_catalog.lpad(v_value::text, 2, '0');
end;
$$;

create or replace function public.qr_random_body(p_length integer default 8)
returns text
language plpgsql
set search_path = ''
as $$
declare
  alphabet constant text := '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
  v_bytes bytea;
  v_body text := '';
  i integer;
begin
  v_bytes := extensions.gen_random_bytes(greatest(coalesce(p_length, 8), 4));
  for i in 0..p_length - 1 loop
    v_body := v_body || pg_catalog.substr(alphabet, (pg_catalog.get_byte(v_bytes, i) % 32) + 1, 1);
  end loop;
  return v_body;
end;
$$;
revoke all on function public.qr_random_body(integer) from public, anon, authenticated;

create or replace function public.qr_build_code(p_company_code text)
returns text
language plpgsql
set search_path = ''
as $$
declare
  v_body text;
begin
  if nullif(pg_catalog.btrim(p_company_code), '') is null then
    raise exception 'Codice azienda mancante'
      using errcode = '22023';
  end if;

  v_body := public.qr_random_body(8);
  return pg_catalog.upper(pg_catalog.btrim(p_company_code)) || '-' || v_body || '-' || public.qr_checksum(v_body);
end;
$$;
revoke all on function public.qr_checksum(text) from public, anon, authenticated;
revoke all on function public.qr_build_code(text) from public, anon, authenticated;

create or replace function public.prepare_preparation_qr()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_company_code text;
  v_qr_id uuid;
begin
  select t.codice_univoco
  into v_company_code
  from public.tenants t
  where t.id = new.tenant_id;

  if v_company_code is null then
    raise exception 'Azienda non valida per il QR'
      using errcode = '22023';
  end if;

  if new.qr_code_univoco is null
     or new.qr_code_univoco not like v_company_code || '-%' then
    new.qr_code_univoco := public.qr_build_code(v_company_code);
    return new;
  end if;

  select q.id
  into v_qr_id
  from public.qr_pool q
  where q.tenant_id = new.tenant_id
    and q.codice_univoco = new.qr_code_univoco
    and q.stato = 'disponibile'
    and q.preparation_id is null
  for update;

  if v_qr_id is null then
    raise exception 'QR non disponibile per questa azienda'
      using errcode = '22023';
  end if;

  return new;
end;
$$;
revoke all on function public.prepare_preparation_qr() from public, anon, authenticated;

create or replace function public.assign_preparation_qr()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_qr_id uuid;
begin
  update public.qr_pool
  set preparation_id = new.id,
      stato = 'assegnato',
      assegnato_il = pg_catalog.now()
  where tenant_id = new.tenant_id
    and codice_univoco = new.qr_code_univoco
    and stato = 'disponibile'
    and preparation_id is null
  returning id into v_qr_id;

  if v_qr_id is not null then
    return new;
  end if;

  -- Codice generato automaticamente dal trigger BEFORE: la riga di pool non esiste.
  insert into public.qr_pool (
    tenant_id,
    preparation_id,
    codice_univoco,
    stato,
    assegnato_il
  )
  values (
    new.tenant_id,
    new.id,
    new.qr_code_univoco,
    'assegnato',
    pg_catalog.now()
  )
  on conflict (codice_univoco) do nothing
  returning id into v_qr_id;

  if v_qr_id is null then
    raise exception 'QR non disponibile per questa azienda'
      using errcode = '22023';
  end if;

  return new;
end;
$$;
revoke all on function public.assign_preparation_qr() from public, anon, authenticated;

create or replace function public.sync_preparation_qr()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.qr_code_univoco is not distinct from new.qr_code_univoco then
    return new;
  end if;

  if old.qr_code_univoco is not null then
    update public.qr_pool
    set preparation_id = null,
        stato = 'disponibile',
        assegnato_il = null
    where tenant_id = old.tenant_id
      and preparation_id = old.id
      and codice_univoco = old.qr_code_univoco;
  end if;

  if new.qr_code_univoco is not null then
    update public.qr_pool
    set preparation_id = new.id,
        stato = 'assegnato',
        assegnato_il = pg_catalog.now()
    where tenant_id = new.tenant_id
      and codice_univoco = new.qr_code_univoco
      and stato = 'disponibile'
      and preparation_id is null;

    if not found then
      raise exception 'QR non disponibile per questa azienda'
        using errcode = '22023';
    end if;
  end if;

  return new;
end;
$$;
revoke all on function public.sync_preparation_qr() from public, anon, authenticated;

create or replace function public.release_preparation_qr()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.qr_pool
  set preparation_id = null,
      stato = 'disponibile',
      assegnato_il = null
  where tenant_id = old.tenant_id
    and codice_univoco = old.qr_code_univoco;

  return old;
end;
$$;
revoke all on function public.release_preparation_qr() from public, anon, authenticated;

create or replace function public.record_tenant_access(p_tenant_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_profile_id uuid;
begin
  select u.id
  into v_profile_id
  from public.users u
  where u.user_id = (select auth.uid());

  if v_profile_id is null then
    raise exception 'Profilo aziendale non trovato'
      using errcode = '42501';
  end if;

  update public.user_tenants ut
  set first_accessed_at = coalesce(ut.first_accessed_at, pg_catalog.now()),
      last_accessed_at = pg_catalog.now()
  from public.tenants t
  where ut.user_profile_id = v_profile_id
    and ut.tenant_id = p_tenant_id
    and t.id = ut.tenant_id;

  if not found then
    raise exception 'Azienda non autorizzata o non trovata'
      using errcode = '42501';
  end if;

  return true;
end;
$$;
revoke all on function public.record_tenant_access(uuid) from public, anon;
grant execute on function public.record_tenant_access(uuid) to authenticated;

create or replace function public.generate_qr_batch(
  p_tenant_id uuid,
  p_quantity integer
)
returns table(codice_univoco text, lotto_stampa uuid)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_company_code text;
  v_code text;
  v_attempt integer;
  v_lotto uuid := extensions.gen_random_uuid();
  i integer;
begin
  if not public.is_superadmin() then
    raise exception 'Operazione riservata al superadmin'
      using errcode = '42501';
  end if;

  if p_quantity is null or p_quantity < 1 or p_quantity > 500 then
    raise exception 'La quantità deve essere compresa tra 1 e 500'
      using errcode = '22023';
  end if;

  select t.codice_univoco
  into v_company_code
  from public.tenants t
  where t.id = p_tenant_id;

  if v_company_code is null then
    raise exception 'Azienda non trovata'
      using errcode = '22023';
  end if;

  for i in 1..p_quantity loop
    for v_attempt in 1..5 loop
      v_code := public.qr_build_code(v_company_code);

      begin
        insert into public.qr_pool (tenant_id, codice_univoco, stato, lotto_stampa)
        values (p_tenant_id, v_code, 'disponibile', v_lotto);
        exit;
      exception when unique_violation then
        if v_attempt = 5 then
          raise;
        end if;
      end;
    end loop;

    codice_univoco := v_code;
    lotto_stampa := v_lotto;
    return next;
  end loop;
end;
$$;
revoke all on function public.generate_qr_batch(uuid, integer) from public, anon;
grant execute on function public.generate_qr_batch(uuid, integer) to authenticated;

create or replace function public.mark_qr_batch_printed(p_lotto uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_profile_id uuid;
  v_count integer;
begin
  if not public.is_superadmin() then
    raise exception 'Operazione riservata al superadmin'
      using errcode = '42501';
  end if;

  if p_lotto is null then
    raise exception 'Lotto di stampa mancante'
      using errcode = '22023';
  end if;

  select u.id
  into v_profile_id
  from public.users u
  where u.user_id = (select auth.uid());

  update public.qr_pool
  set stampato_il = coalesce(stampato_il, pg_catalog.now()),
      stampato_da = coalesce(stampato_da, v_profile_id)
  where lotto_stampa = p_lotto;

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke all on function public.mark_qr_batch_printed(uuid) from public, anon;
grant execute on function public.mark_qr_batch_printed(uuid) to authenticated;

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

  if v_current_preparation_id is not null
     and v_current_preparation_id is distinct from p_preparation_id then
    update public.preparations
    set qr_code_univoco = null,
        stato = 'esaurita'
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

create or replace function public.svuota_cestino_preparazioni(p_tenant_id uuid default null)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid;
  v_deleted_count integer;
begin
  if p_tenant_id is null then
    select u.tenant_id
    into v_tenant_id
    from public.users u
    where u.user_id = (select auth.uid())
      and u.tenant_id is not null;
  else
    select ut.tenant_id
    into v_tenant_id
    from public.user_tenants ut
    join public.users u on u.id = ut.user_profile_id
    where u.user_id = (select auth.uid())
      and ut.tenant_id = p_tenant_id;
  end if;

  if v_tenant_id is null then
    raise exception 'Operazione riservata agli utenti di un’azienda autenticati'
      using errcode = '42501';
  end if;

  delete from public.preparations p
  where p.tenant_id = v_tenant_id
    and p.is_deleted = true;

  get diagnostics v_deleted_count = row_count;
  return v_deleted_count;
end;
$$;
revoke all on function public.svuota_cestino_preparazioni(uuid) from public, anon;
grant execute on function public.svuota_cestino_preparazioni(uuid) to authenticated;

create or replace function public.crea_nuovo_ristorante(
  p_nome_azienda text,
  p_partita_iva text,
  p_via text,
  p_numero_civico text,
  p_cap text,
  p_citta text,
  p_provincia text,
  p_telefono text,
  p_cellulare text,
  p_email_contatto text,
  p_codice_sdi text,
  p_settore text,
  p_nome_admin text,
  p_email text,
  p_password text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid;
  v_user_id uuid;
  v_company_code text;
  v_lotto uuid;
  v_i integer;
begin
  if (select auth.uid()) is null or not public.is_superadmin() then
    raise exception 'Operazione riservata al superadmin'
      using errcode = '42501';
  end if;

  if nullif(pg_catalog.btrim(p_nome_azienda), '') is null
     or nullif(pg_catalog.btrim(p_nome_admin), '') is null
     or nullif(pg_catalog.btrim(p_email), '') is null
     or p_password is null
     or length(p_password) < 6 then
    raise exception 'Dati azienda, admin, email e password validi sono obbligatori'
      using errcode = '22023';
  end if;

  insert into public.tenants (
    nome_azienda, partita_iva, via, numero_civico, cap, citta, provincia,
    telefono, cellulare, email_contatto, codice_sdi, settore_merceologico
  )
  values (
    pg_catalog.btrim(p_nome_azienda), nullif(pg_catalog.btrim(p_partita_iva), ''),
    nullif(pg_catalog.btrim(p_via), ''), nullif(pg_catalog.btrim(p_numero_civico), ''),
    nullif(pg_catalog.btrim(p_cap), ''), nullif(pg_catalog.btrim(p_citta), ''),
    nullif(pg_catalog.btrim(p_provincia), ''), nullif(pg_catalog.btrim(p_telefono), ''),
    nullif(pg_catalog.btrim(p_cellulare), ''), nullif(pg_catalog.btrim(p_email_contatto), ''),
    nullif(pg_catalog.btrim(p_codice_sdi), ''), nullif(pg_catalog.btrim(p_settore), '')
  )
  returning id into v_tenant_id;

  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
    confirmation_token, recovery_token, email_change_token_new, email_change,
    created_at, updated_at
  )
  values (
    '00000000-0000-0000-0000-000000000000',
    gen_random_uuid(),
    'authenticated',
    'authenticated',
    lower(pg_catalog.btrim(p_email)),
    extensions.crypt(p_password, extensions.gen_salt('bf')),
    now(),
    jsonb_build_object('provider', 'email', 'providers', jsonb_build_array('email')),
    jsonb_build_object('nome', pg_catalog.btrim(p_nome_admin), 'ruolo', 'cliente'),
    '', '', '', '',
    now(),
    now()
  )
  returning id into v_user_id;

  insert into public.users (user_id, tenant_id, nome, ruolo)
  values (v_user_id, v_tenant_id, pg_catalog.btrim(p_nome_admin), 'cliente');

  -- Identita' di login: senza questa riga GoTrue rifiuta l'accesso email/password.
  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'auth' and table_name = 'identities' and column_name = 'provider_id'
  ) then
    insert into auth.identities (
      id, user_id, identity_data, provider, provider_id,
      last_sign_in_at, created_at, updated_at
    )
    values (
      pg_catalog.gen_random_uuid(), v_user_id,
      jsonb_build_object('sub', v_user_id::text, 'email', lower(pg_catalog.btrim(p_email)), 'email_verified', true),
      'email', v_user_id::text,
      pg_catalog.now(), pg_catalog.now(), pg_catalog.now()
    );
  else
    insert into auth.identities (
      id, user_id, identity_data, provider,
      last_sign_in_at, created_at, updated_at
    )
    values (
      v_user_id::text, v_user_id,
      jsonb_build_object('sub', v_user_id::text, 'email', lower(pg_catalog.btrim(p_email))),
      'email',
      pg_catalog.now(), pg_catalog.now(), pg_catalog.now()
    );
  end if;

  insert into public.user_tenants (user_profile_id, tenant_id)
  select u.id, v_tenant_id
  from public.users u
  where u.user_id = v_user_id;

  -- Primo lotto di 200 QR pre-attivati per l'azienda appena creata.
  select t.codice_univoco
  into v_company_code
  from public.tenants t
  where t.id = v_tenant_id;

  v_lotto := extensions.gen_random_uuid();
  for v_i in 1..200 loop
    insert into public.qr_pool (tenant_id, codice_univoco, stato, lotto_stampa)
    values (v_tenant_id, public.qr_build_code(v_company_code), 'disponibile', v_lotto)
    on conflict (codice_univoco) do nothing;
  end loop;

  return v_tenant_id;
end;
$$;
revoke all on function public.crea_nuovo_ristorante(
  text, text, text, text, text, text, text, text, text, text,
  text, text, text, text, text
) from public, anon;
grant execute on function public.crea_nuovo_ristorante(
  text, text, text, text, text, text, text, text, text, text,
  text, text, text, text, text
) to authenticated;

-- 6. Trigger
drop trigger if exists preparations_prepare_qr on public.preparations;
create trigger preparations_prepare_qr
  before insert on public.preparations
  for each row
  execute function public.prepare_preparation_qr();
drop trigger if exists preparations_assign_qr on public.preparations;
create trigger preparations_assign_qr
  after insert on public.preparations
  for each row
  execute function public.assign_preparation_qr();
drop trigger if exists preparations_sync_qr on public.preparations;
create trigger preparations_sync_qr
  after update of qr_code_univoco on public.preparations
  for each row
  execute function public.sync_preparation_qr();
drop trigger if exists preparations_release_qr on public.preparations;
create trigger preparations_release_qr
  after delete on public.preparations
  for each row
  execute function public.release_preparation_qr();
drop trigger if exists preparations_set_updated_at on public.preparations;
create trigger preparations_set_updated_at
  before update on public.preparations
  for each row
  execute function public.set_preparation_updated_at();
drop trigger if exists preparations_audit on public.preparations;
create trigger preparations_audit
  after insert or update or delete on public.preparations
  for each row execute function public.audit_haccp_row();

-- 7. RLS e policy
alter table public.tenants enable row level security;
alter table public.users enable row level security;
alter table public.user_tenants enable row level security;
alter table public.preparations enable row level security;
alter table public.qr_pool enable row level security;
alter table public.preparation_audit enable row level security;
alter table public.ingredients enable row level security;
alter table public.ingredient_lots enable row level security;
alter table public.preparation_ingredients enable row level security;

do $$
declare p record;
begin
  for p in
    select schemaname, tablename, policyname
    from pg_policies
    where schemaname = 'public'
      and tablename in ('tenants','users','user_tenants','preparations','qr_pool',
                        'preparation_audit','ingredients','ingredient_lots','preparation_ingredients')
  loop
    execute pg_catalog.format('drop policy %I on %I.%I', p.policyname, p.schemaname, p.tablename);
  end loop;
end;
$$;

drop policy if exists tenants_read_members on public.tenants;
create policy tenants_read_members on public.tenants
  for select to authenticated
  using (
    public.is_superadmin()
    or exists (
      select 1
      from public.user_tenants ut
      join public.users u on u.id = ut.user_profile_id
      where u.user_id = (select auth.uid())
        and ut.tenant_id = tenants.id
    )
  );

drop policy if exists tenants_admin_manage on public.tenants;
create policy tenants_admin_manage on public.tenants
  for all to authenticated
  using (public.is_superadmin())
  with check (public.is_superadmin());

drop policy if exists users_read_self_or_admin on public.users;
create policy users_read_self_or_admin on public.users
  for select to authenticated
  using (user_id = (select auth.uid()) or public.is_superadmin());

drop policy if exists user_tenants_read_self_or_admin on public.user_tenants;
create policy user_tenants_read_self_or_admin on public.user_tenants
  for select to authenticated
  using (
    public.is_superadmin()
    or exists (
      select 1 from public.users u
      where u.id = user_tenants.user_profile_id
        and u.user_id = (select auth.uid())
    )
  );

drop policy if exists user_tenants_admin_manage on public.user_tenants;
create policy user_tenants_admin_manage on public.user_tenants
  for all to authenticated
  using (public.is_superadmin())
  with check (public.is_superadmin());

drop policy if exists preparations_read_tenant on public.preparations;
create policy preparations_read_tenant on public.preparations
  for select to authenticated
  using (
    public.is_superadmin()
    or exists (
      select 1
      from public.user_tenants ut
      join public.users u on u.id = ut.user_profile_id
      where u.user_id = (select auth.uid())
        and ut.tenant_id = preparations.tenant_id
    )
  );

drop policy if exists preparations_insert_tenant on public.preparations;
create policy preparations_insert_tenant on public.preparations
  for insert to authenticated
  with check (
    exists (
      select 1
      from public.user_tenants ut
      join public.users u on u.id = ut.user_profile_id
      where u.user_id = (select auth.uid())
        and ut.tenant_id = preparations.tenant_id
    )
    and exists (
      select 1 from public.users u
      where u.user_id = (select auth.uid())
        and u.id = preparations.creato_da
    )
  );

drop policy if exists preparations_update_tenant on public.preparations;
create policy preparations_update_tenant on public.preparations
  for update to authenticated
  using (
    public.is_superadmin()
    or exists (
      select 1
      from public.user_tenants ut
      join public.users u on u.id = ut.user_profile_id
      where u.user_id = (select auth.uid())
        and ut.tenant_id = preparations.tenant_id
    )
  )
  with check (
    public.is_superadmin()
    or exists (
      select 1
      from public.user_tenants ut
      join public.users u on u.id = ut.user_profile_id
      where u.user_id = (select auth.uid())
        and ut.tenant_id = preparations.tenant_id
    )
  );

drop policy if exists preparations_delete_tenant on public.preparations;
create policy preparations_delete_tenant on public.preparations
  for delete to authenticated
  using (
    (is_deleted or deleted_at is not null)
    and (
      public.is_superadmin()
      or exists (
        select 1
        from public.user_tenants ut
        join public.users u on u.id = ut.user_profile_id
        where u.user_id = (select auth.uid())
          and ut.tenant_id = preparations.tenant_id
      )
    )
  );

drop policy if exists ingredients_tenant_manage on public.ingredients;
create policy ingredients_tenant_manage on public.ingredients
  for all to authenticated
  using (
    public.is_superadmin()
    or exists (
      select 1 from public.user_tenants ut
      join public.users u on u.id = ut.user_profile_id
      where u.user_id = (select auth.uid())
        and ut.tenant_id = ingredients.tenant_id
    )
  )
  with check (
    public.is_superadmin()
    or exists (
      select 1 from public.user_tenants ut
      join public.users u on u.id = ut.user_profile_id
      where u.user_id = (select auth.uid())
        and ut.tenant_id = ingredients.tenant_id
    )
  );

drop policy if exists ingredient_lots_tenant_manage on public.ingredient_lots;
create policy ingredient_lots_tenant_manage on public.ingredient_lots
  for all to authenticated
  using (
    public.is_superadmin()
    or exists (
      select 1 from public.user_tenants ut
      join public.users u on u.id = ut.user_profile_id
      where u.user_id = (select auth.uid())
        and ut.tenant_id = ingredient_lots.tenant_id
    )
  )
  with check (
    public.is_superadmin()
    or exists (
      select 1 from public.user_tenants ut
      join public.users u on u.id = ut.user_profile_id
      where u.user_id = (select auth.uid())
        and ut.tenant_id = ingredient_lots.tenant_id
    )
  );

drop policy if exists preparation_ingredients_tenant_manage on public.preparation_ingredients;
create policy preparation_ingredients_tenant_manage on public.preparation_ingredients
  for all to authenticated
  using (
    public.is_superadmin()
    or exists (
      select 1 from public.user_tenants ut
      join public.users u on u.id = ut.user_profile_id
      where u.user_id = (select auth.uid())
        and ut.tenant_id = preparation_ingredients.tenant_id
    )
  )
  with check (
    public.is_superadmin()
    or exists (
      select 1 from public.user_tenants ut
      join public.users u on u.id = ut.user_profile_id
      where u.user_id = (select auth.uid())
        and ut.tenant_id = preparation_ingredients.tenant_id
    )
  );

drop policy if exists qr_pool_read_tenant on public.qr_pool;
create policy qr_pool_read_tenant on public.qr_pool
  for select to authenticated
  using (
    public.is_superadmin()
    or exists (
      select 1 from public.user_tenants ut
      join public.users u on u.id = ut.user_profile_id
      where u.user_id = (select auth.uid())
        and ut.tenant_id = qr_pool.tenant_id
    )
  );

drop policy if exists preparation_audit_tenant_read on public.preparation_audit;
create policy preparation_audit_tenant_read on public.preparation_audit
  for select to authenticated
  using (
    public.is_superadmin()
    or exists (
      select 1 from public.user_tenants ut
      join public.users u on u.id = ut.user_profile_id
      where u.user_id = (select auth.uid())
        and ut.tenant_id = preparation_audit.tenant_id
    )
  );

-- 8. Backfill membership
insert into public.user_tenants (user_profile_id, tenant_id)
select u.id, u.tenant_id
from public.users u
where u.tenant_id is not null
on conflict (user_profile_id, tenant_id) do nothing;

insert into public.tracciafood_schema_migrations (version)
values ('20261117_allineamento')
on conflict (version) do nothing;

notify pgrst, 'reload schema';

commit;

-- ================= VERIFICA (incollare l'output) =================
select 'user_tenants' as controllo, count(*) as valore from public.user_tenants
union all
select 'qr_pool', count(*) from public.qr_pool
union all
select 'qr disponibili', count(*) from public.qr_pool where stato = 'disponibile'
union all
select 'preparazioni', count(*) from public.preparations
union all
select 'policy pubbliche', count(*) from pg_policies where schemaname = 'public';

select p.proname,
       pg_get_function_identity_arguments(p.oid) as argomenti,
       pg_get_function_result(p.oid) as ritorno
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('record_tenant_access','generate_qr_batch','mark_qr_batch_printed',
                    'confirm_qr_preparation','svuota_cestino_preparazioni','crea_nuovo_ristorante')
order by 1, 2;

select left(qr_code_univoco, 12) as esempio, count(*)
from public.preparations
where qr_code_univoco is not null
group by 1
order by 2 desc
limit 5;
