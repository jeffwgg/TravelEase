# TravelEase: Accessible Travel Assistance for Deaf Travelers

**TravelEase** is an accessible travel communication, assistance, and institutional improvement system designed specifically for deaf and hard-of-hearing travelers. 

The system consists of:
1. **Mobile Application (B2C)**: A cross-platform mobile app for individual travelers.
2. **Web Dashboard (B2B)**: An institutional dashboard for public services, airport management, hotels, transit hubs, and tourist attractions.

---

## 🛠️ Technology Stack

### Mobile Application (`/mobile`)
- **Framework**: [Flutter](https://flutter.dev/) (Dart 3.10+)
- **Architecture**: MVVM (Model-View-ViewModel) Pattern
- **Navigation**: `go_router`
- **Typography & Theme**: Google Fonts (`Inter`), Custom Accessibility-First Design Tokens

### Web Dashboard (`/web`)
- **Framework**: [React.js](https://react.dev/) (v19) with [Vite](https://vite.dev/)
- **Routing**: `react-router-dom` (v7)
- **Styling**: Vanilla CSS with CSS Custom Properties / Design System Tokens

---

## 📁 Project Structure

```
TravelEase/
├── docs/                   # System requirements, architecture diagrams, proposal
├── mobile/                 # Flutter Mobile Application
│   ├── lib/
│   │   ├── core/           # Theme, App Router, Design Tokens
│   │   ├── models/         # Data Models
│   │   ├── viewmodels/     # ViewModels
│   │   └── views/          # Flutter UI Views (20 Views)
│   ├── pubspec.yaml        # Flutter dependencies
│   └── README.md
├── web/                    # React Institutional Web Dashboard
│   ├── src/
│   │   ├── components/     # Reusable UI components
│   │   ├── pages/          # Dashboard Pages (11 Pages)
│   │   ├── App.jsx         # Router & Layout Setup
│   │   ├── index.css       # Core CSS Design System
│   │   └── main.jsx        # Entry point
│   ├── package.json        # NPM dependencies
│   └── vite.config.js
└── README.md               # Root Documentation
```

---

## 🚀 How to Run the Projects

### Prerequisites

Ensure you have the following installed on your machine:
- [Node.js](https://nodejs.org/) (v18.0 or higher) & `npm`
- [Flutter SDK](https://docs.flutter.dev/get-started/install) (v3.38+ recommended)
- Android Studio / Xcode (for running mobile simulators) or Chrome (for Flutter Web preview)

---

### 📱 1. Running the Mobile Application (Flutter)

1. Open your terminal and navigate to the `mobile` directory:
   ```bash
   cd mobile
   ```

2. Fetch Flutter packages/dependencies:
   ```bash
   flutter pub get
   ```

3. Check available devices (simulators, connected devices, or Chrome):
   ```bash
   flutter devices
   ```

4. Launch the application:
   ```bash
   # Run on an iOS Simulator or connected Android device
   flutter run

   # Or run on Chrome for a quick web preview of the mobile app
   flutter run -d chrome
   ```

---

### 🖥️ 2. Running the Web Dashboard (React)

1. Open your terminal and navigate to the `web` directory:
   ```bash
   cd web
   ```

2. Install Node dependencies:
   ```bash
   npm install
   ```

3. Start the development server:
   ```bash
   npm run dev
   ```

4. Open your browser and navigate to:
   ```
   http://localhost:5173
   ```

5. (Optional) To build the production bundle:
   ```bash
   npm run build
   ```

---

## 📋 Overview of Included Views & Pages

### Mobile App (20 Views)
- **User & Profile**: Authentication, Profile Management, Accessibility Preferences
- **SOS & Safety**: Emergency Contacts, Emergency Communication Card
- **Location & Alerts**: Venue Identification, Announcements, Environmental Sound Alerts, Queue Tracking, Notifications
- **Communication Engine**: Sign Translation Camera (BIM/ASL), Speech-to-Sign, Two-Way Dialogue Console
- **Sign Reference**: Sign Dictionary, Favorite Phrases, Interactive Sign Media Viewer
- **Assistance & Support**: Assistance Request Submission, Live Request Tracking, Staff Chat, Accessibility Barrier Reporting

### Web Dashboard (11 Pages)
- **Overview & Auth**: Staff Login (`/auth`), Organization Profile & Staff Access (`/profile`)
- **Real-Time Operations**: Announcement Broadcast Manager (`/announcements`), Queue Counter Console (`/queue`), Assistance Request Dispatch (`/requests`), Staff Chat Console (`/chat`)
- **Analytics & Reporting**: Accessibility Heatmaps & Analytics (`/analytics`), Staff Service Performance (`/performance`), Custom Audit Report Generator (`/reports`)
- **Content Management**: Sign Dictionary Asset Manager (`/sign-dictionary`), Sign Feedback Review Console (`/sign-feedback`)
