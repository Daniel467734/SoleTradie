import {
  collection,
  doc,
  getDocs,
  getDoc,
  addDoc,
  updateDoc,
  deleteDoc,
  query,
  where,
  orderBy,
  limit,
  writeBatch,
  onSnapshot,
  Timestamp,
} from 'firebase/firestore';
import { auth, db } from '@/lib/firebase';
import { Job, Customer, Estimate, Invoice, PriceBookItem, Settings, EstimateTemplate, DashboardStats } from '@/types';

class FirestoreService {
  private static getUserId(): string | null {
    return auth.currentUser?.uid || null;
  }

  private static isAuthenticated(): boolean {
    return !!auth.currentUser;
  }

  // Jobs
  static async getJobs(): Promise<Job[]> {
    const userId = this.getUserId();
    if (!userId) throw new Error('User not authenticated');

    const q = query(
      collection(db, 'users', userId, 'jobs'),
      orderBy('dateCreated', 'desc')
    );
    const snapshot = await getDocs(q);
    return snapshot.docs.map(doc => ({ id: doc.id, ...doc.data() } as Job));
  }

  static async getJob(id: string): Promise<Job | null> {
    const userId = this.getUserId();
    if (!userId) throw new Error('User not authenticated');

    const docRef = doc(db, 'users', userId, 'jobs', id);
    const snapshot = await getDoc(docRef);
    return snapshot.exists() ? { id: snapshot.id, ...snapshot.data() } as Job : null;
  }

  static async saveJob(job: Partial<Job>): Promise<string> {
    const userId = this.getUserId();
    if (!userId) throw new Error('User not authenticated');

    const jobData = {
      ...job,
      userId,
      dateCreated: job.dateCreated || new Date().toISOString(),
    };

    if (job.id) {
      const docRef = doc(db, 'users', userId, 'jobs', job.id);
      await updateDoc(docRef, jobData);
      return job.id;
    } else {
      const docRef = await addDoc(collection(db, 'users', userId, 'jobs'), jobData);
      return docRef.id;
    }
  }

  static async deleteJob(id: string): Promise<void> {
    const userId = this.getUserId();
    if (!userId) throw new Error('User not authenticated');

    await deleteDoc(doc(db, 'users', userId, 'jobs', id));
  }

  // Customers
  static async getCustomers(): Promise<Customer[]> {
    const userId = this.getUserId();
    if (!userId) throw new Error('User not authenticated');

    const q = query(
      collection(db, 'users', userId, 'customers'),
      orderBy('name')
    );
    const snapshot = await getDocs(q);
    return snapshot.docs.map(doc => ({ id: doc.id, ...doc.data() } as Customer));
  }

  static async getCustomer(id: string): Promise<Customer | null> {
    const userId = this.getUserId();
    if (!userId) throw new Error('User not authenticated');

    const docRef = doc(db, 'users', userId, 'customers', id);
    const snapshot = await getDoc(docRef);
    return snapshot.exists() ? { id: snapshot.id, ...snapshot.data() } as Customer : null;
  }

  static async saveCustomer(customer: Partial<Customer>): Promise<string> {
    const userId = this.getUserId();
    if (!userId) throw new Error('User not authenticated');

    const customerData = {
      ...customer,
      userId,
      dateCreated: customer.dateCreated || new Date().toISOString(),
      totalJobs: customer.totalJobs || 0,
      totalSpent: customer.totalSpent || 0,
    };

    if (customer.id) {
      const docRef = doc(db, 'users', userId, 'customers', customer.id);
      await updateDoc(docRef, customerData);
      return customer.id;
    } else {
      const docRef = await addDoc(collection(db, 'users', userId, 'customers'), customerData);
      return docRef.id;
    }
  }

  static async deleteCustomer(id: string): Promise<void> {
    const userId = this.getUserId();
    if (!userId) throw new Error('User not authenticated');

    await deleteDoc(doc(db, 'users', userId, 'customers', id));
  }

  // Estimates
  static async getEstimates(): Promise<Estimate[]> {
    const userId = this.getUserId();
    if (!userId) throw new Error('User not authenticated');

    const q = query(
      collection(db, 'users', userId, 'estimates'),
      orderBy('dateCreated', 'desc')
    );
    const snapshot = await getDocs(q);
    return snapshot.docs.map(doc => ({ id: doc.id, ...doc.data() } as Estimate));
  }

  static async saveEstimate(estimate: Partial<Estimate>): Promise<string> {
    const userId = this.getUserId();
    if (!userId) throw new Error('User not authenticated');

    const estimateData = {
      ...estimate,
      userId,
      dateCreated: estimate.dateCreated || new Date().toISOString(),
    };

    if (estimate.id) {
      const docRef = doc(db, 'users', userId, 'estimates', estimate.id);
      await updateDoc(docRef, estimateData);
      return estimate.id;
    } else {
      const docRef = await addDoc(collection(db, 'users', userId, 'estimates'), estimateData);
      return docRef.id;
    }
  }

  // Invoices
  static async getInvoices(): Promise<Invoice[]> {
    const userId = this.getUserId();
    if (!userId) throw new Error('User not authenticated');

    const q = query(
      collection(db, 'users', userId, 'invoices'),
      orderBy('dateCreated', 'desc')
    );
    const snapshot = await getDocs(q);
    return snapshot.docs.map(doc => ({ id: doc.id, ...doc.data() } as Invoice));
  }

  static async saveInvoice(invoice: Partial<Invoice>): Promise<string> {
    const userId = this.getUserId();
    if (!userId) throw new Error('User not authenticated');

    const invoiceData = {
      ...invoice,
      userId,
      dateCreated: invoice.dateCreated || new Date().toISOString(),
    };

    if (invoice.id) {
      const docRef = doc(db, 'users', userId, 'invoices', invoice.id);
      await updateDoc(docRef, invoiceData);
      return invoice.id;
    } else {
      const docRef = await addDoc(collection(db, 'users', userId, 'invoices'), invoiceData);
      return docRef.id;
    }
  }

  // Price Book
  static async getPriceBookItems(): Promise<PriceBookItem[]> {
    const userId = this.getUserId();
    if (!userId) throw new Error('User not authenticated');

    const q = query(
      collection(db, 'users', userId, 'priceBook'),
      orderBy('name')
    );
    const snapshot = await getDocs(q);
    return snapshot.docs.map(doc => ({ id: doc.id, ...doc.data() } as PriceBookItem));
  }

  static async savePriceBookItem(item: Partial<PriceBookItem>): Promise<string> {
    const userId = this.getUserId();
    if (!userId) throw new Error('User not authenticated');

    const itemData = {
      ...item,
      userId,
      lastUpdated: new Date().toISOString(),
    };

    if (item.id) {
      const docRef = doc(db, 'users', userId, 'priceBook', item.id);
      await updateDoc(docRef, itemData);
      return item.id;
    } else {
      const docRef = await addDoc(collection(db, 'users', userId, 'priceBook'), itemData);
      return docRef.id;
    }
  }

  // Settings
  static async getSettings(): Promise<Settings | null> {
    const userId = this.getUserId();
    if (!userId) throw new Error('User not authenticated');

    const docRef = doc(db, 'users', userId, 'settings', 'main');
    const snapshot = await getDoc(docRef);
    return snapshot.exists() ? { id: snapshot.id, ...snapshot.data() } as Settings : null;
  }

  static async saveSettings(settings: Partial<Settings>): Promise<void> {
    const userId = this.getUserId();
    if (!userId) throw new Error('User not authenticated');

    const settingsData = {
      ...settings,
      userId,
    };

    const docRef = doc(db, 'users', userId, 'settings', 'main');
    await updateDoc(docRef, settingsData);
  }

  // Dashboard Analytics
  static async getDashboardStats(): Promise<DashboardStats> {
    const userId = this.getUserId();
    if (!userId) throw new Error('User not authenticated');

    const [jobs, invoices, customers, estimates] = await Promise.all([
      this.getJobs(),
      this.getInvoices(),
      this.getCustomers(),
      this.getEstimates(),
    ]);

    const currentMonth = new Date().getMonth();
    const currentYear = new Date().getFullYear();

    const completedJobs = jobs.filter(job => job.status === 'completed');
    const pendingJobs = jobs.filter(job => job.status === 'pending' || job.status === 'in_progress');
    
    const totalRevenue = completedJobs.reduce((sum, job) => sum + (job.totalCost || 0), 0);
    
    const monthlyRevenue = completedJobs
      .filter(job => {
        const date = new Date(job.dateCompleted || job.dateCreated);
        return date.getMonth() === currentMonth && date.getFullYear() === currentYear;
      })
      .reduce((sum, job) => sum + (job.totalCost || 0), 0);

    const pendingEstimates = estimates.filter(est => est.status === 'draft' || est.status === 'sent').length;
    const overdueInvoices = invoices.filter(inv => {
      if (inv.status === 'paid') return false;
      const dueDate = new Date(inv.dueDate);
      return dueDate < new Date();
    }).length;

    return {
      totalJobs: jobs.length,
      completedJobs: completedJobs.length,
      pendingJobs: pendingJobs.length,
      totalRevenue,
      monthlyRevenue,
      activeCustomers: customers.length,
      pendingEstimates,
      overdueInvoices,
    };
  }

  // Real-time listeners
  static subscribeToJobs(callback: (jobs: Job[]) => void): () => void {
    const userId = this.getUserId();
    if (!userId) throw new Error('User not authenticated');

    const q = query(
      collection(db, 'users', userId, 'jobs'),
      orderBy('dateCreated', 'desc')
    );

    return onSnapshot(q, (snapshot) => {
      const jobs = snapshot.docs.map(doc => ({ id: doc.id, ...doc.data() } as Job));
      callback(jobs);
    });
  }

  static subscribeToCustomers(callback: (customers: Customer[]) => void): () => void {
    const userId = this.getUserId();
    if (!userId) throw new Error('User not authenticated');

    const q = query(
      collection(db, 'users', userId, 'customers'),
      orderBy('name')
    );

    return onSnapshot(q, (snapshot) => {
      const customers = snapshot.docs.map(doc => ({ id: doc.id, ...doc.data() } as Customer));
      callback(customers);
    });
  }
}

export default FirestoreService;
