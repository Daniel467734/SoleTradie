import { initializeApp, getApps } from 'firebase/app';
import { getAuth } from 'firebase/auth';
import { getFirestore, enableNetwork, disableNetwork } from 'firebase/firestore';
import { getAnalytics } from 'firebase/analytics';

const firebaseConfig = {
  apiKey: "AIzaSyDrGDZ_-6mC3AlInwU3FOgp1EX2moDtmmo",
  authDomain: "soletradie-ab850.firebaseapp.com",
  projectId: "soletradie-ab850",
  storageBucket: "soletradie-ab850.firebasestorage.app",
  messagingSenderId: "126990067919",
  appId: "1:126990067919:web:8091d2cb70813e987e2fba",
  measurementId: "G-6PPLPSEJDZ"
};

// Initialize Firebase
const app = getApps().length === 0 ? initializeApp(firebaseConfig) : getApps()[0];

// Initialize Firebase services
export const auth = getAuth(app);
export const db = getFirestore(app);

// Initialize Analytics (only in browser)
let analytics;
if (typeof window !== 'undefined') {
  analytics = getAnalytics(app);
}
export { analytics };

// Enable offline persistence
if (typeof window !== 'undefined') {
  // Only run on client side
  enableNetwork(db).catch((error) => {
    console.warn('Firebase offline persistence failed:', error);
  });
}

export default app;
