# Movete

App nativa iOS per il trasporto pubblico di Roma. SwiftUI, iOS 17+, zero backend.

- Progetto Xcode: `ios/Movete.xcodeproj` (generato da `ios/project.yml` con xcodegen)
- Scheme: `Movete`
- Bundle ID: `com.movete.roma`
- Simulatore: `movete-dev` (iPhone 16 Pro, iOS 18.5)
- Build: `cd ios && xcodegen generate && xcodebuild build -project Movete.xcodeproj -scheme Movete -destination 'platform=iOS Simulator,name=movete-dev' -configuration Debug CODE_SIGNING_ALLOWED=NO`

## Pipeline

`python3 pipeline/build.py roma` — scarica GTFS, produce output split in `output/roma/`

## Dati

- GTFS statico: romamobilita.it (5 agenzie, 434 linee, 5217 fermate)
- GTFS-RT: vehicle positions, trip updates, service alerts (solo ATAC + Roma TPL)
- Output: core.json (1.3 MB) + stops/*.json (on-demand) + routes/*.json (shape on-demand)

## IMPORTANTE

- Dopo aggiunta/rimozione file Swift: `cd ios && xcodegen generate`
- Questo NON e' TransitKit e NON e' DoVe
- Non usare skill `dove-ios-workflow` o `dove-android-workflow`

---

## PREREQUISITI DI SVILUPPO MOBILE

### IDB Companion

```bash
# Verifica/installa
which idb && idb list-targets
# Se mancante:
brew tap facebook/fb && brew install facebook/fb/idb-companion
pip3 install fb-idb
```

### Maestro (E2E flows)

```bash
# Verifica/installa
which maestro || curl -Ls "https://get.maestro.mobile.dev" | bash
maestro --version
```

---

## WORKFLOW FUNZIONALE — Accessibility First

Per navigazione e verifica funzionale usa l'albero di accessibilità, non screenshot.

```bash
UDID=$(xcrun simctl list devices | grep "movete-dev" | grep -oE '[A-F0-9-]{36}' | head -1)

# Leggi albero accessibilità (~300 token vs ~1500 di uno screenshot)
idb ui describe-all --udid $UDID | python3 -m json.tool

# Tap per coordinate (trova le coordinate con describe-all)
idb ui tap --udid $UDID <x> <y>

# Input testo
idb ui text --udid $UDID "testo"

# Swipe verticale
idb ui swipe --udid $UDID 200 600 200 200
```

---

## WORKFLOW E2E — Maestro

```bash
# Esegui un flow
maestro test flows/smoke_test.yaml

# Esegui tutti i flow
maestro test flows/

# Watch mode durante sviluppo
maestro test --watch flows/nome_flow.yaml
```

I flow YAML sono in `flows/`. Genera o aggiorna quando cambia un flusso utente.

---

## VERIFICA VISIVA — Screenshot Protocol

Usa screenshot **solo** per verifica design/estetica.

```bash
UDID=$(xcrun simctl list devices | grep "movete-dev" | grep -oE '[A-F0-9-]{36}' | head -1)

# Full screen compresso (~4x meno token del PNG raw)
xcrun simctl io $UDID screenshot /tmp/s.png && sips -Z 800 /tmp/s.png --out /tmp/s_small.png

# Crop su componente specifico (molto più efficiente per review di dettagli UI)
xcrun simctl io $UDID screenshot /tmp/s.png && sips -c <altezza> <larghezza> /tmp/s.png --out /tmp/component.png
```

Dopo ogni modifica UI: screenshot "prima" e "dopo" con descrizione esplicita di cosa è cambiato.

---

## DEFINITION OF DONE — FEATURE UI

- [ ] Build senza errori né warning nuovi (`xcodegen generate` se servito)
- [ ] Elementi interattivi nuovi hanno `.accessibilityIdentifier()`
- [ ] Verifica funzionale via accessibility tree (`idb ui describe-all`)
- [ ] Screenshot "prima" e "dopo" allegati per ogni modifica UI visibile
- [ ] Flow Maestro in `flows/` aggiornato se il flusso utente è cambiato
- [ ] Nessun crash: `xcrun simctl spawn $UDID log stream --level error`
