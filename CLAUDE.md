# Movete

App nativa iOS per il trasporto pubblico di Roma. SwiftUI, iOS 17+, zero backend.

- Progetto Xcode: `ios/Movete.xcodeproj` (generato da `ios/project.yml` con xcodegen)
- Scheme: `Movete`
- Bundle ID: `com.movete.roma`
- Simulator UDID (iPhone 16 Pro, iOS 18.5): `F0856EB2-7A49-4620-9AF1-EB1321B8CFE2`
- Build: `cd ios && xcodegen generate && xcodebuild build -project Movete.xcodeproj -scheme Movete -destination 'platform=iOS Simulator,id=F0856EB2-7A49-4620-9AF1-EB1321B8CFE2' -configuration Debug CODE_SIGNING_ALLOWED=NO`

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
