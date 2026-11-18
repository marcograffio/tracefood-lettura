BEGIN;

-- Riallinea SOLO il trigger di assegnazione QR.
-- Il trigger corretto aggiorna una riga esistente di qr_pool (i codici sono generati
-- da prepare_preparation_qr nel formato AZIENDA-XXXXXXXX e NON vanno creati qui).
-- Riferimento: supabase-schema.sql.

LOCK TABLE public.preparations IN SHARE ROW EXCLUSIVE MODE;

DO $$
DECLARE
  active_trigger record;
BEGIN
  FOR active_trigger IN
    SELECT t.tgname
    FROM pg_catalog.pg_trigger AS t
    JOIN pg_catalog.pg_proc AS p ON p.oid = t.tgfoid
    WHERE t.tgrelid = 'public.preparations'::regclass
      AND NOT t.tgisinternal
      AND (t.tgtype & 4) <> 0
      AND p.prosrc ILIKE '%insert into public.qr_pool%'
      AND p.prosrc NOT ILIKE '%update public.qr_pool%'
  LOOP
    EXECUTE pg_catalog.format(
      'DROP TRIGGER %I ON public.preparations',
      active_trigger.tgname
    );
  END LOOP;
END;
$$;

DROP TRIGGER IF EXISTS preparations_assign_qr ON public.preparations;

CREATE OR REPLACE FUNCTION public.assign_preparation_qr()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  UPDATE public.qr_pool
  SET preparation_id = NEW.id,
      stato = 'assegnato',
      assegnato_il = pg_catalog.now()
  WHERE tenant_id = NEW.tenant_id
    AND codice_univoco = NEW.qr_code_univoco
    AND stato = 'disponibile'
    AND preparation_id IS NULL;

  IF NOT FOUND THEN
    INSERT INTO public.qr_pool (
      tenant_id,
      preparation_id,
      codice_univoco,
      stato,
      assegnato_il
    )
    VALUES (
      NEW.tenant_id,
      NEW.id,
      NEW.qr_code_univoco,
      'assegnato',
      pg_catalog.now()
    );
  END IF;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.assign_preparation_qr() FROM public, anon, authenticated;

CREATE TRIGGER preparations_assign_qr
AFTER INSERT ON public.preparations
FOR EACH ROW
EXECUTE FUNCTION public.assign_preparation_qr();

COMMIT;