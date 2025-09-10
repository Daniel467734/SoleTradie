// Types matching your Flutter mobile app models

export interface Job {
  id: string;
  customerName: string;
  address: string;
  phone?: string;
  email?: string;
  jobType: string;
  status: 'pending' | 'in_progress' | 'completed' | 'cancelled';
  priority: 'low' | 'medium' | 'high';
  dateCreated: string;
  dateScheduled?: string;
  dateCompleted?: string;
  estimatedDuration?: number;
  actualDuration?: number;
  totalCost?: number;
  notes?: string;
  photos?: string[];
  userId: string;
}

export interface Customer {
  id: string;
  name: string;
  email?: string;
  phone?: string;
  address?: string;
  suburb?: string;
  postcode?: string;
  state?: string;
  country?: string;
  notes?: string;
  dateCreated: string;
  lastJobDate?: string;
  totalJobs: number;
  totalSpent: number;
  userId: string;
}

export interface EstimateItem {
  id: string;
  name: string;
  description?: string;
  section: string;
  quantity: number;
  unitPrice: number;
  totalPrice: number;
  category: 'labour' | 'materials' | 'callout' | 'discount' | 'other';
  isMarkup?: boolean;
  markupPercentage?: number;
  wholesalePrice?: number;
  retailPrice?: number;
  supplierCost?: number;
  idNumber?: string;
}

export interface Estimate {
  id: string;
  jobId: string;
  customerName: string;
  items: EstimateItem[];
  subtotal: number;
  gst: number;
  total: number;
  status: 'draft' | 'sent' | 'accepted' | 'rejected';
  dateCreated: string;
  dateSent?: string;
  dateAccepted?: string;
  validUntil?: string;
  notes?: string;
  userId: string;
}

export interface Invoice {
  id: string;
  jobId: string;
  estimateId?: string;
  invoiceNumber: string;
  customerName: string;
  customerAddress: string;
  items: EstimateItem[];
  subtotal: number;
  gst: number;
  total: number;
  status: 'draft' | 'sent' | 'paid' | 'overdue' | 'cancelled';
  dateCreated: string;
  dateSent?: string;
  datePaid?: string;
  dueDate: string;
  paymentTerms: string;
  notes?: string;
  userId: string;
}

export interface PriceBookItem {
  id: string;
  idNumber: string;
  name: string;
  description?: string;
  category: string;
  unit: string;
  wholesalePrice: number;
  retailPrice: number;
  markupPercentage: number;
  supplier?: string;
  lastUpdated: string;
  userId: string;
}

export interface Settings {
  id: string;
  businessName: string;
  businessAddress: string;
  businessPhone: string;
  businessEmail: string;
  abn?: string;
  gstRate: number;
  defaultMarkup: number;
  invoiceTerms: string;
  estimateValidDays: number;
  userId: string;
}

export interface EstimateTemplate {
  id: string;
  name: string;
  description?: string;
  items: EstimateItem[];
  category: string;
  dateCreated: string;
  userId: string;
}

export interface DashboardStats {
  totalJobs: number;
  completedJobs: number;
  pendingJobs: number;
  totalRevenue: number;
  monthlyRevenue: number;
  activeCustomers: number;
  pendingEstimates: number;
  overdueInvoices: number;
}
