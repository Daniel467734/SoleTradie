# Tradesperson Business Manager - Web Application

A comprehensive web-based business management solution for tradespeople that integrates seamlessly with the mobile Flutter app through Firebase Firestore.

## Features

### 🎯 Core Business Management
- **Dashboard** - Real-time overview of business metrics, pending jobs, and financial summaries
- **Job Management** - Create, track, and manage jobs with status updates and scheduling
- **Customer Management** - Comprehensive customer database with job history and contact details
- **Estimate Builder** - Professional estimate creation with itemized pricing and PDF generation
- **Invoice Generation** - Convert estimates to invoices with payment tracking
- **Price Book** - Centralized pricing database with markup calculations

### 🔥 Firebase Integration
- **Real-time Sync** - All data syncs instantly between web and mobile apps
- **Offline Support** - Works offline with automatic sync when online
- **User Authentication** - Secure login with Firebase Auth
- **Cloud Storage** - Reliable data storage with Firestore
- **User Isolation** - Data is scoped per user for privacy and security

### 💻 Desktop-Optimized UI
- **Responsive Design** - Optimized for desktop screens with mobile responsiveness
- **Modern Interface** - Clean, intuitive design built with Tailwind CSS
- **Fast Performance** - Server-side rendering with Next.js
- **Professional PDFs** - Generate and download estimates/invoices as PDFs

## Tech Stack

- **Framework**: Next.js 14 with App Router
- **Language**: TypeScript
- **Styling**: Tailwind CSS
- **Database**: Firebase Firestore
- **Authentication**: Firebase Auth
- **PDF Generation**: jsPDF + html2canvas
- **Charts**: Recharts
- **Icons**: Heroicons + Lucide React

## Project Structure

```
src/
├── app/                 # Next.js App Router pages
├── components/          # React components
│   ├── auth/           # Authentication components
│   ├── dashboard/      # Dashboard widgets
│   ├── jobs/          # Job management
│   ├── customers/     # Customer management
│   ├── estimates/     # Estimate builder
│   ├── invoices/      # Invoice management
│   ├── layout/        # Layout components
│   ├── pricebook/     # Price book management
│   ├── settings/      # Settings management
│   └── ui/            # Reusable UI components
├── lib/                # Utility libraries
│   ├── firebase.ts    # Firebase configuration
│   └── firestore.ts   # Firestore service layer
└── types/              # TypeScript type definitions
```

## Getting Started

### Prerequisites

- Node.js 18+ and npm
- Firebase project (same as mobile app)
- Firebase configuration keys

### Installation

1. **Install dependencies:**
   ```bash
   npm install --legacy-peer-deps
   ```

2. **Configure Firebase:**
   Update `src/lib/firebase.ts` with your Firebase project configuration:
   ```typescript
   const firebaseConfig = {
     apiKey: "your-api-key",
     authDomain: "your-project.firebaseapp.com",
     projectId: "your-project-id",
     storageBucket: "your-project.appspot.com",
     messagingSenderId: "your-sender-id",
     appId: "your-app-id"
   };
   ```

3. **Run the development server:**
   ```bash
   npm run dev
   ```

4. **Open your browser:**
   Navigate to [http://localhost:3000](http://localhost:3000)

## Data Integration with Mobile App

This web application shares the same Firestore database structure as the Flutter mobile app:

### Collections Structure
```
users/{userId}/
├── jobs/              # Job records
├── customers/         # Customer information
├── estimates/         # Estimate documents
├── invoices/          # Invoice records
├── priceBook/         # Price book items
└── settings/          # User settings
```

### Real-time Sync
- Changes made on mobile instantly appear on web
- Changes made on web instantly appear on mobile
- Offline changes sync automatically when connection is restored

## Key Features

### Dashboard
- Real-time business metrics
- Monthly revenue tracking
- Job status overview
- Pending estimates and overdue invoices

### Job Management
- Create and track jobs by status
- Schedule jobs with calendar integration
- Customer assignment and contact details
- Photo attachments and notes

### Estimate Builder
- Professional estimate creation
- Itemized pricing with categories
- Automatic GST calculations
- PDF generation for client delivery

### Customer Management
- Comprehensive customer database
- Job history tracking
- Contact information management
- Customer analytics

### Price Book
- Centralized item pricing
- Markup percentage calculations
- Category organization
- Bulk import/export capabilities

## Development

### Available Scripts

- `npm run dev` - Start development server
- `npm run build` - Build for production
- `npm run start` - Start production server
- `npm run lint` - Run ESLint

### Environment Setup

Create a `.env.local` file for local development:
```
NEXT_PUBLIC_FIREBASE_API_KEY=your-api-key
NEXT_PUBLIC_FIREBASE_AUTH_DOMAIN=your-project.firebaseapp.com
NEXT_PUBLIC_FIREBASE_PROJECT_ID=your-project-id
```

## Deployment

The application can be deployed to:
- **Vercel** (recommended for Next.js)
- **Netlify**
- **Firebase Hosting**
- **Docker containers**

For Vercel deployment:
```bash
npm run build
npx vercel --prod
```

## Security

- User authentication required for all operations
- Data scoped per authenticated user
- Firestore security rules enforce user isolation
- HTTPS enforced in production

## Support

For issues or questions:
1. Check the mobile app's Firebase configuration
2. Ensure Firestore security rules allow web access
3. Verify authentication is working correctly

## License

This project is part of the Tradesperson Business Management suite.
