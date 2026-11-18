# PLAYBOOK OPERATIVO - TRACCIAFOOD

## 1. Stack Tecnologico
- **Frontend**: HTML5, CSS3, JavaScript ES6+.
- **Backend**: Supabase (PostgreSQL + Auth + Storage).
- **Librerie esterne**: qrcodejs, html5-qrcode, @supabase/supabase-js.
- **Hosting**: Cloudflare Pages (deploy automatico da GitHub).
- **Nessun framework**: niente React, Vue, Angular, Bootstrap, Tailwind.

## 2. Struttura File
- `index.html` → App ristoratore (frontend).
- `style.css` → Stili condivisi (include il Design System Blindato).
- `supabase-config.js` → URL e anon key Supabase (`window.SUPABASE_CONFIG`).
- `config.js` → Istanza `supabaseClient` condivisa.
- `state.js` → Stato globale dell'app (utente, azienda attiva, cache preparazioni).
- `auth.js` → Login, registrazione, recupero password, logout, reset sessione.
- `app.js` → Logica app ristoratore.
- `admin.html` → Pannello Superadmin (creazione aziende, lotti QR).
- `files/migrazione-20261117-allineamento-schema.sql` → Migrazione di allineamento schema + QR con checksum.
- `manifest.json` → Configurazione PWA.
- `sw.js` → Service Worker (cache asset offline).

## 3. Flusso di Lavoro dell'Agente
1. Leggi i file di regole (`.clinerules/` e `files/`).
2. Analizza il comando ricevuto.
3. Identifica SOLO i file necessari alla modifica.
4. Scrivi il codice rispettando il Design System.
5. Esegui i test indicati nel comando.
6. Se i test falliscono, correggi e riprova.
7. Consegna con conferma: "Fatto. Test superati: X/Y."

## 4. Divieti Assoluti
- ❌ Non usare `display: flex` per affiancare tasti (solo `.tile-grid`).
- ❌ Non usare stili inline (`style="..."`) nel HTML.
- ❌ Non creare nuove classi CSS se esistono già le classi del Design System.
- ❌ Non rimuovere campi obbligatori senza richiesta esplicita.
- ❌ Non aggiungere campi non richiesti.
- ❌ Non modificare il database direttamente (vedi regola 9).
- ❌ Non chiedere conferme all'utente prima di eseguire: esegui, poi mostra il risultato.

## 5. Comunicazione
- Nessuna spiegazione del codice.
- Nessuna scusa.
- Solo conferma: "Fatto. Test superati: X/Y." oppure la richiesta del dato mancante.
- Se un comando è ambiguo, chiedi solo il dato mancante.

## 6. Design System
Per tutte le regole visive (classi consentite, colori, struttura dei tasti), fai riferimento al file `design-system.md`. Non improvvisare stili, non modificare i colori, non cambiare le dimensioni standard.

Nota di conformità documentale: nel repository attuale i file `design-system.md` e `database.md` non esistono. La documentazione vigente è quindi riferita ai file reali presenti:
- `style.css` per il Design System visivo applicativo e i colori/strutture già implementate.
- `supabase-schema.sql` per lo schema del database attualmente presente nel progetto.
- `files/playbook-operativo.md` e `files/qa-checklist.md` per la procedura operativa e i criteri di qualità.
Se il team vuole completare la specifica originaria, serve aggiungere `design-system.md` e `database.md` come documenti dedicati, separati dal codice attuale.

## 7. Database
Per lo schema del database, le tabelle e le policy RLS, fai riferimento al file `database.md`. Non modificare la struttura senza autorizzazione.

### 7.1 Ruoli e accesso
- `cliente`: entra nell'app (`index.html`) e vede solo le aziende presenti in `user_tenants` per il suo profilo.
- `superadmin`: entra nella console (`admin.html`) e **può usare anche l'app** per le sole aziende a cui è associato in `user_tenants`. Non riceve privilegi aggiuntivi dentro l'app.
- Nessun accesso è consentito su aziende non associate, indipendentemente dal ruolo.

Nota di conformità documentale: il file `database.md` non è presente nel repository. L’unico riferimento attuale allo schema è `supabase-schema.sql`, che va considerato il documento di fatto del modello dati in uso. Se la documentazione completa deve essere separata dal codice, va creato un `database.md` con schema, tabelle, policy e regole di manutenzione.

## 8. Regole di Business (Eliminazione)

### 8.1 Eliminazione dalla lista principale
- Quando l'utente clicca "Elimina" su una scheda attiva (visibile nella lista principale):
  - Il prodotto viene spostato nel cestino (impostando `deleted_at` o `is_deleted`).
  - **NON mostrare nessun popup di conferma.**
  - **L'interfaccia deve nascondere la scheda immediatamente.**

### 8.2 Eliminazione dal cestino
- Quando l'utente clicca "Elimina" su una scheda già presente nel cestino:
  - **Mostrare un popup di conferma** (`confirm("Sei sicuro di voler eliminare definitivamente questo prodotto?")`) prima di procedere.
  - Se l'utente conferma, eseguire l'eliminazione fisica dal database.

### 8.3 Nota per l'Agente
- Non usare `window.confirm()` nella lista principale.
- Usa `window.confirm()` solo per le schede nel cestino.

### 8.4 Ciclo di vita del QR (contenitore)
- Il QR identifica il **contenitore fisico**, non la pietanza.
- `disponibile` → mai usato: alla scansione apre una nuova preparazione.
- `assegnato` → collegato a una preparazione attiva: alla scansione si apre la preparazione con le opzioni "tieni così", "modifica" o "riusa contenitore".
- `scaduto` → etichetta annullata: rifiutata, mai riutilizzata.
- "Riusa contenitore" chiude la preparazione corrente come `esaurita` e ne crea una nuova con lo stesso QR (la storia resta consultabile).
- I codici sono emessi **solo dal superadmin**: primo lotto da 200 alla creazione dell'azienda, altri lotti dal pannello. L'azienda vede solo il contatore dei QR disponibili.
- Formato: `AZIENDA-XXXXXXXX-CC` (8 caratteri base32 senza I/L/O/U + 2 cifre di checksum). Prefisso e checksum si validano senza rete; i codici legacy restano accettati.

## 9. Gestione Modifiche al Database

### 9.1 Regola Generale
Se un comando richiede modifiche alla struttura del database (nuove tabelle, nuove colonne, nuove funzioni SQL, nuove policy RLS), l'agente **non deve eseguire direttamente** queste modifiche (non ha accesso al SQL Editor di Supabase).

### 9.2 Procedura Obbligatoria
Invece di eseguire, l'agente deve:
1.  Generare lo **script SQL completo** per la modifica.
2.  Scrivere un messaggio chiaro all'utente: *"Per procedere, esegui questo script nel SQL Editor di Supabase: [script]. Fammi sapere quando hai finito."*
3.  **FERMARSI** e attendere la conferma dell'utente.
4.  Solo dopo la conferma, procedere con le modifiche al codice frontend (HTML/CSS/JS).

### 9.3 Divieti
- ❌ Non tentare di eseguire comandi SQL direttamente.
- ❌ Non procedere con il frontend finché il database non è aggiornato.
- ❌ Non assumere che l'utente abbia eseguito lo script senza conferma esplicita.

## 10. Formato Output per Codice SQL

### 10.1 Regola Assoluta
Quando l'agente genera codice SQL (migrazioni, funzioni, policy), l'output deve contenere **SOLO** il codice SQL, senza alcuna spiegazione, senza markdown, senza testo introduttivo o conclusivo.

### 10.2 Formato Corretto
```sql
BEGIN;
-- codice SQL puro
COMMIT;
Ecco la migrazione da eseguire...
```sql
BEGIN;
...

### 10.4 Divieti
- ❌ Nessun testo prima del codice.
- ❌ Nessun testo dopo il codice.
- ❌ Nessun blocco markdown (```sql).
- ❌ Solo SQL puro, pronto per essere copiato e incollato.