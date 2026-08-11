# Scrigno — app nativa Mac + iPhone

Password manager locale, KDBX4 (compatibile KeePass), con autofill nativo su
iPhone. Nessun server, nessun account: il vault è un file `.kdbx` che tieni
tu (consigliato: dentro iCloud Drive).

## 0. Prova prima la parte critica (consigliato, 2 minuti)

Prima ancora di aprire Xcode, puoi verificare che tutta la crittografia
funzioni sul tuo Mac:

```
cd ScrignoApp/VaultCore
swift test
```

Questo compila ed esegue `VaultCore` da riga di comando (il pacchetto che fa
tutto il lavoro pesante: cifratura, KDF, lettura/scrittura del formato KDBX)
e lo confronta con vettori di test calcolati con librerie indipendenti
(PyCryptodome, zlib, argon2-cffi) e con un vault reale già verificato con tre
implementazioni diverse. Se questi test passano, il resto è "solo" interfaccia.

## 1. Genera il progetto Xcode

Serve [XcodeGen](https://github.com/yonaskolb/XcodeGen) (genera il
`.xcodeproj` da `project.yml`, molto più comodo da mantenere/modificare che
un progetto Xcode binario):

```
brew install xcodegen
cd ScrignoApp
xcodegen generate
open Scrigno.xcodeproj
```

## 2. Configura la firma (una tantum)

In Xcode, per **ciascuno dei tre target** (`Scrigno-macOS`, `Scrigno-iOS`,
`ScrignoAutoFill`) apri **Signing & Capabilities**:

1. Seleziona il tuo team Apple (il tuo Apple ID gratuito va benissimo per
   l'app Mac e per testare su iPhone; con l'Apple ID gratuito l'app sul
   telefono va ri-firmata ogni 7 giorni — con un account developer a 99€/anno
   resta installata indefinitamente).
2. Se Xcode cambia automaticamente il Bundle Identifier (perché
   `com.antonioscirica.*` non è disponibile con il tuo account gratuito),
   lascialo fare — ma allora vai anche in `project.yml`, cambia
   `bundleIdPrefix` e i due riferimenti a `group.com.antonioscirica.scrigno`,
   e rilancia `xcodegen generate`.

Poi, solo su **Scrigno-iOS** e **ScrignoAutoFill** (i due target iOS devono
condividere gli stessi due identificatori):

3. **+ Capability → App Groups** → crea/seleziona
   `group.com.antonioscirica.scrigno` (stesso nome su entrambi i target).
4. **+ Capability → Keychain Sharing** → aggiungi
   `com.antonioscirica.scrigno.shared` (stesso nome su entrambi i target).

Questi due punti sono ciò che permette all'estensione AutoFill di leggere lo
stesso vault e la stessa master password (protetta da Face ID) dell'app
principale.

Infine, solo su **Scrigno-macOS** e **ScrignoSafariExtension** (l'estensione
Safari, vedi punto 5 sotto — devono condividere lo stesso identificatore):

5. **+ Capability → Keychain Sharing** → aggiungi
   `com.antonioscirica.hush.bridge` (stesso nome su entrambi i target).
6. Solo su `ScrignoSafariExtension`: **+ Capability → App Sandbox** (se non è
   già lì da sé) → sotto "Network" spunta **Outgoing Connections (Client)**.
7. La prima volta che compili `ScrignoSafariExtension` con firma automatica,
   Xcode potrebbe dirti che il tuo Mac non è registrato nel tuo account
   sviluppatore: clicca "Register Device" nel pannello che propone, oppure
   fallo da [developer.apple.com](https://developer.apple.com/account) →
   Certificates, IDs & Profiles → Devices.

## 3. Primo avvio

- **Mac**: seleziona lo schema `Scrigno-macOS`, Cmd+R. Crea un nuovo vault o
  aprine uno esistente (anche quello creato con la web-app Scrigno.html di
  prima, se ce l'hai — è lo stesso formato).
- **iPhone**: seleziona lo schema `Scrigno-iOS`, collega l'iPhone, Cmd+R.
  Alla prima apertura crea o importa il vault; ti conviene salvarlo dentro
  **iCloud Drive** così è lo stesso file che usi anche sul Mac (Scrigno non
  sincronizza automaticamente: apri/salvi lo stesso file via iCloud Drive,
  un po' come fai già con KeePassXC/Strongbox).

## 4. Attivare l'AutoFill su iPhone

Impostazioni → Password (o Password e Account) → Riempimento automatico
password → attiva **Scrigno** (e disattiva 1Password se vuoi che Scrigno
compaia per primo). Da quel momento, nei campi utente/password di Safari e
delle app, comparirà il tasto per usare Scrigno: la prima volta ti chiede la
master password con l'opzione "Ricorda con Face ID", dopodiché sarà sempre
Face ID.

## 5. Attivare l'estensione Safari sul Mac

Safari → Impostazioni → Estensioni → attiva **Hush**. Da quel momento, in
qualunque pagina con un campo password compare un piccolo tasto 🔒: cliccalo
per scegliere quale voce compilare (utente e password insieme).

Come funziona, in breve: mentre Hush.app è aperto e sbloccato, tiene in
ascolto sulla porta 51823 di *questo* Mac soltanto (127.0.0.1, non la rete —
il telefono NON può raggiungerla). L'estensione Safari — sandboxata, non
tocca mai un file `.kdbx` — le chiede lì le voci che combaciano col sito
aperto, autenticandosi con un token generato la prima volta e condiviso via
Keychain (`com.antonioscirica.hush.bridge`) solo fra Hush.app e l'estensione.
Chiudi o blocchi Hush e il bridge si ferma: l'estensione lo trova muto, come
deve essere. Vedi `App/macOS/LocalBridge.swift` per i dettagli.

## 6. Pubblicare una nuova versione (aggiornamenti automatici)

Hush controlla da solo se c'è una versione nuova (Sparkle, vedi `SUFeedURL`
in `project.yml`) — per pubblicarne una:

1. Alza `MARKETING_VERSION` e/o `CURRENT_PROJECT_VERSION` in `project.yml`,
   poi `xcodegen generate`.
2. Archivia ed esporta, firmato Developer ID (non serve toccare Xcode):
   ```
   xcodebuild -project Scrigno.xcodeproj -scheme Scrigno-macOS -configuration Release \
     -allowProvisioningUpdates archive -archivePath build/Hush.xcarchive
   xcodebuild -exportArchive -archivePath build/Hush.xcarchive -exportPath build/export \
     -exportOptionsPlist build/exportOptions.plist -allowProvisioningUpdates
   ```
3. Impacchetta in `.dmg`:
   ```
   mkdir -p build/dmgroot && cp -R build/export/Hush.app build/dmgroot/
   ln -sf /Applications build/dmgroot/Applications
   hdiutil create -volname Hush -srcfolder build/dmgroot -ov -format UDZO build/Hush.dmg
   ```
4. Firma l'update (chiave privata nel Keychain di questo Mac, mai nel repo —
   se manca, `generate_keys` del [tool ufficiale Sparkle](https://github.com/sparkle-project/Sparkle/releases) la ricrea):
   ```
   sign_update build/Hush.dmg
   ```
5. Aggiungi una voce in `build/appcast.xml` con la firma ottenuta — inclusa
   `<description>` (HTML, dentro `CDATA`): è il changelog che la gente vede
   nel pannello di aggiornamento, senza non capisce cosa sta per installare.
   Poi carica sia `hush.dmg` che `appcast.xml` nel bucket Supabase `assets`
   (stesso posto del video demo), sovrascrivendo quelli che ci sono.

Chi ha già Hush aperto lo trova da solo entro un giorno (o subito, da
**Hush → Verifica aggiornamenti…**).

## Cosa NON fa (ancora), onestamente

- **Cronologia e campi personalizzati**: se apri con Scrigno un vault creato
  con KeePassXC/Strongbox che ha history delle modifiche o campi custom, e
  poi lo *risalvi* da Scrigno, quella roba extra va persa (i dati che vedi —
  titolo, utente, password, URL, note — restano corretti). Se non risalvi da
  Scrigno, il file originale non viene toccato.
- **File keyfile**: supportato solo in modo basilare (hash dell'intero file),
  non il formato XML v2 strutturato.
- **Versione Argon2 legacy (0x10)**: non supportata, solo la 0x13 (quella che
  usano tutti i database moderni).
- **Suggerimenti automatici (QuickType bar)**: per ora l'AutoFill funziona
  tramite il tasto "chiave" sopra la tastiera, non con suggerimenti
  automatici sopra la tastiera senza aprire nulla — è un miglioramento
  possibile in un secondo momento.
- **Sync automatica**: nessuna. È lo stesso file su iCloud Drive aperto da
  entrambi i dispositivi: se lo modifichi su un dispositivo mentre è aperto
  anche sull'altro, vince l'ultimo salvataggio (come con qualunque file
  locale su iCloud Drive — nessun merge intelligente).
- **Autofill solo su Mac (Safari) e iPhone/iPad (di sistema)**: non c'è
  un'estensione Chrome/Firefox — su Mac serve Safari. Su iPhone l'autofill
  funziona ovunque il sistema lo supporta (Safari e le app), non solo dentro
  Safari.
- **Bridge locale senza autenticazione forte**: il token che l'estensione
  Safari usa per parlare con Hush.app gira in chiaro su HTTP in loopback (mai
  fuori da questo Mac). Sufficiente per l'uso normale, ma non è pensato per
  un Mac con altri utenti che hanno una sessione attiva in parallelo.

## Struttura del progetto

```
ScrignoApp/
  VaultCore/          Swift Package: tutta la crittografia + il formato KDBX4
                       (indipendente da SwiftUI/iOS/macOS — riusabile ovunque)
  App/Shared/          Interfaccia SwiftUI condivisa Mac+iPhone
  App/macOS/           Punto d'ingresso app Mac
  App/iOS/             Punto d'ingresso app iPhone
  AutoFillExtension/    Estensione AutoFill (Credential Provider) per iPhone
  SafariExtension/
    Native/             Ponte Swift sandboxato (JS <-> bridge locale)
    Resources/           manifest.json, content/background/popup JS
  project.yml          Specifica XcodeGen (genera il .xcodeproj)
```

Sicurezza: KDBX4, AES-256, Argon2id (64 MiB, 3 iterazioni, parallelismo 4),
HMAC-SHA256 per l'integrità di ogni blocco. Argon2 usa l'implementazione di
riferimento ufficiale in C (la stessa usata da libsodium/KeePass), non
crittografia scritta da zero. AES-256/SHA/HMAC usano CommonCrypto e CryptoKit
di Apple. L'unica parte scritta a mano è ChaCha20 (richiesto dal formato
KDBX per proteggere i campi in memoria) — validata contro PyCryptodome su
200 combinazioni casuali prima di essere trascritta in Swift, poi ri-validata
nei test del pacchetto.
