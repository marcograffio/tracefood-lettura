# PROTOCOLLO DI SVILUPPO - TRACCIAFOOD

Questo documento definisce le regole ferree per mantenere il sistema scalabile, replicabile e sicuro.

## 1. Principi di Sviluppo
- **Database First:** Ogni nuova funzionalità deve essere prima validata nello schema SQL. Non si crea logica nel frontend se non supportata da funzioni `security definer` o policy RLS.
- **Sicurezza per Default:** Ogni nuova tabella deve avere l'RLS abilitato al momento della creazione.
- **Normalizzazione:** Non aggiungere colonne "catch-all" (es. `indirizzo`). Usa sempre colonne atomiche (es. `via`, `cap`, `citta`).
- **Standardizzazione:** Il `codice_univoco` dei tenant deve sempre rispettare il pattern `^AZ-[0-9]{4}$`.

## 2. Flusso di Lavoro (Agente - Founder)
1. **Richiesta:** Il Founder espone la necessità.
2. **Analisi:** L'Agente valuta l'impatto sul DB e sulla sicurezza.
3. **Esecuzione (SQL):** L'Agente fornisce lo script SQL (modulo).
4. **Validazione (Founder):** Il Founder esegue lo script e riporta l'esito.
5. **Implementazione (Frontend):** Solo dopo la conferma SQL, l'Agente modifica HTML/JS.

## 3. Deployment di una Nuova Funzionalità
- Non eseguire mai script SQL in produzione senza test (staged) su un ambiente di prova.
- Ogni funzione PL/pgSQL deve avere `set search_path = ''` e `security definer`.
- Ogni operazione di modifica deve essere tracciata nella tabella `preparation_audit` tramite trigger.

## 4. Manutenzione
- Periodicamente, verificare i log nella tabella `preparation_audit` per individuare tentativi di accesso non autorizzati o inconsistenze.
- Mantenere la documentazione (`database.md`, `design-system.md`) sincronizzata con il codice reale.
