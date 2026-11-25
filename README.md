# GoHealth för iPhone

Ett SwiftUI-projekt för iOS 17 eller senare med mätvärden från HealthKit och inloggning via Supabase. Bilddiagnostik har en separat bildtjänst; Terra används inte.

## Öppna och kör

1. Installera Xcode från Mac App Store. Xcode med iOS SDK behövs för full kompilering.
2. Öppna `GoHealth.xcodeproj` i Xcode.
3. Välj GoHealth-target → Signing & Capabilities, välj ditt utvecklarteam och vid behov ett unikt Bundle Identifier. HealthKit är redan konfigurerat i projektet.
4. Välj en ansluten iPhone som kör iOS 17 eller senare och kör appen. HealthKit-signering måste stödjas av ditt team/provisioning.
5. Tryck på **Anslut Apple Hälsa** och välj de uppgifter du vill tillåta.

## Vad appen visar

- Senaste läsbara pulsmätning med källa och mättid. Tryck på **Senaste puls** för hela pulshistoriken från alla läsbara källor i Apple Hälsa, utan datumgräns. Dra ned för att uppdatera. Detta är inte vilopuls.
- Vilopuls med hela historiken via ett tryck på **Vilopuls**, från alla läsbara källor utan datumgräns.
- Steg idag via HealthKits statistikfråga.
- Registrerad sömn senaste 24 timmarna. Överlappande sömnintervall slås ihop; vaken tid och tid i säng räknas inte som sömn.

Apple Hälsa kan innehålla flera källor. Denna första version filtrerar inte allt till Garmin. Saknade data visas som ett streck, inte som noll. HealthKit avslöjar inte om läsbehörighet nekats; en slutförd behörighetsdialog innebär inte att alla värden är åtkomliga.

## Betaprofil för UI och UX

**Beta-login** i Debug-versionen öppnar en ifylld testprofil utan anslutning till Apple Hälsa. Både Beta-login och Hoppa över på inloggningssteget leder till steg 3. Steg 3–6 genomförs eller hoppas över ett i taget. På steg 4 används Fortsätt med testdata i stället för en riktig anslutning. Mätvärden, aktivitet, organöversikter och historik använder syntetiska värden. Alla 17 mätkort har 30 dagars historik; pulsvyn har 120 mätningar. Fyra träningspass och en ifylld hälsoprofil ingår. Återhämtningsvyn använder sitt separata syntetiska exempel. Uppdatering behåller testläget. Testprofilen använder endast minne och sin separata inställningsdomän och överför inga mätvärden till Supabase eller Apple Hälsa. Logga ut och välj Beta-login för att börja om.

## Andning och lungfunktion

Under **Andning → Lungfunktion** visas FEV₁ och FVC i liter, FEV₁/FVC i procent samt PEF i liter/minut, med kort historik. FEV₁, FVC och PEF läses från Apple Hälsa efter användarens medgivande. Appen mäter inte dessa själv; värden behöver registreras från spirometri eller en PEF-mätare.

FEV₁/FVC beräknas enbart för entydiga FEV₁-/FVC-par med exakt samma starttid, sluttid, källversion och enhet. Om matchningen saknas eller är tvetydig visas inget beräknat värde. Noll, negativa eller icke ändliga volymer och FEV₁ större än FVC används inte. Värden utan kliniskt referensunderlag visas som **Mätt**, inte som normala. Testprofilens värden är syntetiska.

Beräkningslogiken kan testas från mappen `GoHealth-iOS`:

```sh
swiftc GoHealth/Spirometry.swift Tests/SpirometryTests.swift -o /tmp/gohealth-spirometry-tests
/tmp/gohealth-spirometry-tests
```

## Nuvarande avgränsning

HealthKit läses på användarens initiativ och mätvärdena synkroniseras ännu inte till Supabase. Supabase används för inloggning. Bilddiagnostik har separat autentiserad import och visning; se status nedan. Ingen klinisk larmfunktion är implementerad.

Release-bygge med iOS Simulator SDK kan verifieras med Xcode. Garmin-dataflödet måste verifieras på en fysisk iPhone.

Nästa steg för HealthKit: verifiera Garmin-värden på fysisk iPhone och implementera en separat, autentiserad inkrementell synkronisering.

## Bilddiagnostik

Bildvisaren förbereder bildserien med en synlig förloppsindikator före bläddring. Hämtning sker med högst fyra parallella anrop och avkodning körs i bakgrunden. Färdiga bilder hålls i en separat minnesbuffert per visare med högst 192 MiB avkodade bilddata; ingen bildcache sparas på disk. Den aktuella testseriens 500 bilder ryms i bufferten. Reglaget byter därefter bild synkront ur minnet, utan avsiktlig paus, nätverksanrop eller svart mellanbild. Bildnumret följer den faktiskt visade bilden. Stora serier och minnesvarningar använder en mindre rörlig buffert; en ännu oladdad bild kan då behöva hämtas medan den förra behålls. Bufferten töms när bildvisaren stängs, och sena svar från tidigare serier/bildfönster ignoreras.

Huvudlös verifiering av bildbuffert och bläddring, från projektroten:

```sh
swiftc -O GoHealth-iOS/GoHealth/ImagingFrameBuffer.swift GoHealth-iOS/Tests/ImagingFrameBufferTests.swift -o /tmp/gohealth-buffer-tests
/tmp/gohealth-buffer-tests
swiftc -O GoHealth-iOS/GoHealth/ImagingFrameBuffer.swift GoHealth-iOS/GoHealth/RadiologyPlayback.swift GoHealth-iOS/Tests/RadiologyPlaybackTests.swift -o /tmp/gohealth-playback-tests
/tmp/gohealth-playback-tests
```

Testerna verifierar bland annat 500-bilders förladdning, 10 000 omedelbara bildval utan nya HTTP-anrop, högst fyra samtidiga hämtningar, minnesgräns och skydd mot avbrutna/sena svar. Mätning av de verkliga 500 JPEG-testbilderna på utvecklingsdatorn gav 145,9 MiB avkodade bilddata. Detta är ett test av minnesbufferten, inte en mätning av skärmens bildfrekvens på fysisk iPhone.

På **Hem** finns en större bilddiagnostikikon i mörk plommon-/magentagradient med grå text nere till höger om avataren. Bildbiblioteket expanderar från ikonen över innehållsytan i Hem; profilheader och nedre NAV-bar ligger kvar. Bildserier öppnas med en toning inom samma vy. Stängknappen eller Hem-knappen drar ihop bildvyn tillbaka mot ikonen. Minskad rörelse använder en kort toning. **Mer → Bilddiagnostik** finns kvar som separat ingång till samma bildbibliotek, med testserier i betaprofilen och kontots egna undersökningar när bildtjänsten är ansluten.

**Beta-login → Hem → bilddiagnostik** visar nu de 500 förinstallerade JPEG-testbilderna från Radiopaedia på både fysisk iPhone och simulator. Bilderna installeras tillsammans med Debug-versionen, cirka 32 MB, och behöver varken internet eller datorns bildserver. Bildordning, källhänvisning och kontrollsummor finns i appresurserna. Betaprofilen läser inga personliga undersökningar och erbjuder inte serverimport. Vanliga inloggade konton använder fortsatt den separata, autentiserade bildtjänsten; se [drift- och integrationsbeskrivningen](../radiology/README.md).

Även **DT · Radiopaedia testserie** finns nu i den lokala betaprofilen: 500 hämtade JPEG-visningsbilder från fall 240575, med ordning och källhänvisning bevarade. Serien används för UI/testvisning och har ingen fysisk DICOM-geometri, HU-kalibrering, valbara DT-fönster eller AI-analys. Ett portabelt paket med bilder och metadata finns i `artifacts/radiology/GoHealth-Radiopaedia-240575-testbilder.zip` i projektroten. Extern användning kräver klarlagda rättigheter.

För att visa bilderna på en iPhone måste den uppdaterade Debug-betan installeras på telefonen via Xcode. Ingen installation på en fysisk telefon har utförts av denna ändring. TestFlight/App Store-arkiv använder normalt Release, där Beta-login och testbilderna inte ingår. Bildpaketet kopieras av en separat byggfas endast i Debug, med exakta in-/utfilslistror och bibehållet skriptskydd. Riktiga konton behöver en driftsatt HTTPS-bildserver angiven i `GOHEALTH_IMAGING_API_URL`. Supabase-katalog och privata buckets är skapade; servervalet är uppskjutet. Ingen AI-modell är aktiverad och bildvisaren är inte validerad för diagnostiska beslut.

Verifiera offlinepaketet från projektroten, utan bildserver:

```sh
swiftc -O GoHealth-iOS/GoHealth/ImagingFrameBuffer.swift GoHealth-iOS/GoHealth/BundledImagingDemo.swift GoHealth-iOS/Tests/BundledImagingDemoTests.swift -o /tmp/gohealth-offline-tests
/tmp/gohealth-offline-tests GoHealth-iOS/GoHealth/RadiologyDemo
```

Testet kan även ges sökvägen till en byggd `GoHealth.app`; då kontrolleras verklig Bundle-resursuppslagning, metadata, kontrollsummor och avkodning av samtliga 500 bilder. Okända bild-ID:n, nätverksadresser, otillåtna filsökvägar och felaktiga kontrollsummor avvisas.

## Automatiskt återhämtningsindex

Välj **Återhämtningsindex · automatiskt**. Appen läser HRV/vilopuls/sömn och registrerad träning från Apple Hälsa utan manuellt formulär. Den nya, separata sensormodellen räknas på din iPhone och sparar lokal historik med filskydd. Ändrade HealthKit-data och återgång till appen uppdaterar vyn. Inga personliga data skickas till webbdemon.

SDNN/RMSSD hålls i olika baslinjer, RMSSD är availability-gatat till iOS 27+. Minst 21 jämförbara dagar och tillräcklig teknisk datakvalitet behövs. **Visa syntetiskt exempel** är isolerat i en separat fil.

Kör `npm run build:ios-demo` efter modell-/UI-ändringar och `npm run test:ios-demo` för den automatiska simulatorverifieringen. Se [README](../README.md) och [modellen/integrationerna](../docs/recovery.md).
