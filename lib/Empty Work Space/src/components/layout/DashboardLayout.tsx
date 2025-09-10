'use client';

import React, { useState } from 'react';
import { Sidebar } from '@/components/layout/Sidebar';
import { Header } from '@/components/layout/Header';
import { Dashboard } from '@/components/dashboard/Dashboard';
import { 
  JobsView, 
  CustomersView, 
  EstimatesView, 
  InvoicesView, 
  PriceBookView, 
  SettingsView 
} from '@/components/views/PlaceholderViews';

type ViewType = 'dashboard' | 'jobs' | 'customers' | 'estimates' | 'invoices' | 'pricebook' | 'settings';

export const DashboardLayout: React.FC = () => {
  const [currentView, setCurrentView] = useState<ViewType>('dashboard');
  const [sidebarOpen, setSidebarOpen] = useState(true);

  const renderView = () => {
    switch (currentView) {
      case 'dashboard':
        return <Dashboard />;
      case 'jobs':
        return <JobsView />;
      case 'customers':
        return <CustomersView />;
      case 'estimates':
        return <EstimatesView />;
      case 'invoices':
        return <InvoicesView />;
      case 'pricebook':
        return <PriceBookView />;
      case 'settings':
        return <SettingsView />;
      default:
        return <Dashboard />;
    }
  };

  return (
    <div className="h-screen bg-gray-50 flex overflow-hidden">
      <Sidebar 
        currentView={currentView} 
        setCurrentView={setCurrentView}
        isOpen={sidebarOpen}
        setIsOpen={setSidebarOpen}
      />
      
      <div className="flex-1 flex flex-col overflow-hidden">
        <Header 
          toggleSidebar={() => setSidebarOpen(!sidebarOpen)}
        />
        
        <main className="flex-1 relative overflow-y-auto focus:outline-none">
          <div className="py-6">
            <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
              {renderView()}
            </div>
          </div>
        </main>
      </div>
    </div>
  );
};
