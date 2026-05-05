# SpendWise iOS

App universale SwiftUI per la gestione delle finanze personali — iOS 17+ / macOS 14+.

## Stack Tecnologico
- **SwiftUI** (iOS 17+ / macOS 14+)
- **Firebase iOS SDK** — FirebaseAuth + FirebaseFirestore
- **GoogleSignIn-iOS** — autenticazione con Google
- **Swift Charts** — grafici nativi
- **URLSession + async/await** — chiamate API
- **Google Gemini REST API** — insights AI

---

## Setup

### 1. Prerequisiti
- Xcode 15+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
- Account Firebase con progetto configurato

### 2. Configurare Firebase

1. Vai su [Firebase Console](https://console.firebase.google.com)
2. Crea un progetto (o usa quello esistente del progetto React)
3. Aggiungi un'app iOS con Bundle ID: `com.spendwise.app`
4. Scarica il file `GoogleService-Info.plist`
5. Copialo in `/SpendWise/` (stessa cartella di `SpendWiseApp.swift`)
6. Per macOS: aggiungi anche un'app macOS e scarica il relativo plist

```bash
cp ~/Downloads/GoogleService-Info.plist SpendWise/
```

### 3. Configurare Google Sign-In

Dal file `GoogleService-Info.plist`, copia:
- `CLIENT_ID` → valore di `GIDClientID` 
- `REVERSED_CLIENT_ID` → schema URL per il redirect

Aggiorna `project.yml` se necessario o imposta le variabili d'ambiente Xcode:
```
GID_CLIENT_ID = <il tuo CLIENT_ID>
GOOGLE_REVERSED_CLIENT_ID = <il tuo REVERSED_CLIENT_ID>
```

### 4. Generare il Progetto Xcode

```bash
cd /Users/admin/Downloads/SpendWise-iOS
xcodegen generate
```

Questo creerà `SpendWise.xcodeproj`.

### 5. Aprire in Xcode

```bash
open SpendWise.xcodeproj
```

Swift Package Manager scaricherà automaticamente le dipendenze.

### 6. Configurare le API (in-app)

Una volta avviata l'app, vai in **Impostazioni** e configura:

| Impostazione | Descrizione |
|---|---|
| **Chiave API Gemini** | Ottieni da [Google AI Studio](https://aistudio.google.com/app/apikey) |
| **URL Backend** | URL del tuo server Express (default: `http://localhost:3001`) |
| **App ID Enable Banking** | ID applicazione Enable Banking |
| **Private Key Enable Banking** | Chiave privata Enable Banking |

---

## Struttura del Progetto

```
SpendWise/
├── SpendWiseApp.swift          # App entry point, Firebase config
├── ContentView.swift           # Root view con TabView
├── Models/
│   ├── Transaction.swift       # Modello transazione (Codable + @DocumentID)
│   ├── AppCategory.swift       # Modello categoria con defaults
│   └── BankAccount.swift       # Modello conto bancario
├── Services/
│   ├── AuthService.swift       # Firebase Auth + Google Sign-In
│   ├── FirestoreService.swift  # Firestore CRUD + Listeners
│   ├── BankAPIService.swift    # Open Banking REST API
│   └── AIService.swift         # Google Gemini AI
├── ViewModels/
│   ├── AuthViewModel.swift     # Auth state management
│   └── DashboardViewModel.swift # Main app state
├── Views/
│   ├── Auth/LoginView.swift    # Schermata login
│   ├── Dashboard/              # Dashboard principale
│   ├── Transactions/           # Lista transazioni
│   ├── Insights/               # Grafici e AI
│   ├── Bank/                   # Open Banking
│   ├── Settings/               # Impostazioni
│   └── Components/             # Componenti riutilizzabili
└── Utilities/
    ├── Formatters.swift        # Formatter euro, date, colori
    └── Constants.swift         # Costanti app
```

---

## Funzionalità

### Dashboard
- Riepilogo entrate/uscite/saldo del mese corrente
- Grafico a barre degli ultimi 6 mesi (Swift Charts)
- Lista transazioni recenti con swipe-to-delete/edit

### Transazioni
- Lista completa con ricerca e filtri per tipo/categoria
- Aggiunta/modifica/eliminazione transazioni
- Raggruppamento per mese con totali
- Transazioni ricorrenti

### Insights
- Grafico a torta uscite per categoria
- Grafico area trend mensile
- 3 consigli finanziari personalizzati via Gemini AI

### Banca
- Collegamento conti bancari tramite Open Banking (Enable Banking)
- Visualizzazione saldi con alert warning/danger
- Supporto carte di credito con limite e utilizzo

### Impostazioni
- Gestione profilo utente Google
- Configurazione API Gemini
- Configurazione backend Open Banking
- Gestione categorie personalizzate
- Reset dati

---

## Note per la Compilazione

### Firestore Codable
I modelli usano `@DocumentID` e `@ServerTimestamp` da `FirebaseFirestoreSwift`.

### macOS Support
Le view usano `#if os(macOS)` dove necessario per pattern specifici (es. apertura URL, root view controller).

### URL Scheme
Per il callback OAuth bancario, l'app usa lo scheme `spendwise://bank-callback`. Configura il redirect URL nel tuo backend Express con questo valore.

---

## Backend Express (Riferimento)

Il server Express proxy deve girare separatamente. Vedi il progetto React originale per il server. In sviluppo usa `http://localhost:3001`.

Per produzione, imposta l'URL del server nelle Impostazioni dell'app.
