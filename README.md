# GoHealth iOS

SwiftUI-appen för GoHealth. Öppna `GoHealth.xcodeproj` i Xcode och välj schemat **GoHealth**.

- Välj en iPhone-simulator för att bygga lokalt. För en fysisk iPhone väljer du ditt utvecklarteam under **Signing & Capabilities**.
- Lägg till `GOHEALTH_SUPABASE_URL` och `GOHEALTH_SUPABASE_PUBLISHABLE_KEY` som användardefinierade bygginställningar för GoHealth-targeten. Använd projektets publika klientnyckel och lägg till `gohealth://auth/callback` bland tillåtna redirect-adresser i Supabase Auth.
- Det separata legacy-bild-API:t kan konfigureras med `GOHEALTH_IMAGING_API_URL`. Publicerade CT-bilagor hämtas från Supabase Storage.

Offlinebilder från Radiopaedia distribueras separat. `Tests/BundledImagingDemoTests.swift` kräver den lokala testserien.
