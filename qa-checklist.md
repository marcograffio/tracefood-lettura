# QA Checklist e Definizione di Finito

## Scopo
Definire i controlli oggettivi e verificabili per stabilire quando un lavoro è da considerarsi "finito".

## Regole di esecuzione
Da ora in poi, ogni volta che finisco un lavoro, prima di mostrare qualsiasi cosa:
1. Eseguo ogni controllo.
2. Correggo ciò che fallisce.
3. Eseguo di nuovo i controlli.
4. Ti fornisco una riga PASS o FAIL per ogni controllo, con le prove usate.
5. Elenco tutto ciò che non ho potuto verificare e spiego perché.

Se più di due controlli falliscono al primo giro, mi fermo e ti dico quale parte del processo l'ha causato, invece di rattoppare l'output.

## Controlli specifici per il progetto
1. **Controllo Passaggi:** Il file `files/playbook-operativo.md` contiene esattamente 9 passaggi numerati nella sezione "B. Utilizzo quotidiano".
2. **Controllo Segnaposto:** Nel file `files/playbook-operativo.md` sono presenti almeno 5 segnaposto tra parentesi quadre.
3. **Controllo Termini Vietati:** Nei file `SKILL.md` e `files/playbook-operativo.md` non compaiono le parole "chiaro", "professionale", "alta qualità", "ottimale", "facile".
4. **Controllo Corrispondenza Requisiti:** I file contengono i termini esatti: "Zero-Trace", "Multitasking", "Offline-first", "Modalità Ispezione".
5. **Controllo Storico:** Il playbook contiene il segnaposto `[NUMERO_STORICO:` oppure `app.js` legge lo storico da `preparation_audit` limitandolo a 3 eventi.
6. **Controllo Indice:** Il file `files/INDEX.md` contiene esattamente una riga nella tabella che punta a `playbook-operativo.md` e una che punta a `qa-checklist.md`.
