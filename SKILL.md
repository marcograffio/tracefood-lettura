# SKILL.md

## Scopo
Gestire l'intero ciclo di vita di un'app SaaS basilare, iper-efficiente, offline-first, multitasking, Zero-Trace e con tracciabilità utente per la tracciabilità alimentare (HACCP).

## Quando usarlo
- **Cliente finale:** al ricevimento merci, al termine di ogni preparazione, e durante i controlli ASL/NAS.
- **Gestore SaaS:** onboarding, gestione rinnovi/sospensioni e supporto tecnico.

## Principi di Design
- **Un solo flusso:** niente menu complessi.
- **Offline-first:** l'app funziona al 100% senza internet.
- **Multitasking:** più schede preparazione contemporaneamente.
- **Zero-Trace:** fotocamera interna, nessuna foto nel rullino.
- **Modalità Ispezione:** la scheda critica resta accessibile anche senza connessione.
- **Utente Loggato:** ogni azione è tracciata con nome e data.
- **Identificazione a Vista:** etichetta fisica con nome + QR code.
- **Tolleranza all'errore:** ogni campo è modificabile manualmente.

## Input
- **Cliente:** smartphone, stampante, etichette, DDT/fatture, ricette.
- **Gestore SaaS:** dati cliente, abbonamento, pagamento automatico, supporto.

## Nota operativa
- Per i passaggi dettagliati e le decisioni sul campo, fare riferimento a: `files/playbook-operativo.md`.
- Per i controlli di qualità e la definizione di "finito", fare riferimento a: `files/qa-checklist.md`.

## Casi limite (generali)
- **Internet assente:** l'app funziona in locale. Sincronizzazione automatica.
- **Controllo ASL/NAS senza internet:** modalità ispezione attiva.
- **Telefono personale del cuoco:** l'app non salva foto nel rullino (Zero-Trace).
- **Responsive:** frontend e backend funzionanti da smartphone, tablet e PC.
- **Etichette premium:** funzione in stand-by.
