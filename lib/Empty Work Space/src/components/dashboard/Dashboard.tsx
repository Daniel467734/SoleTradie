'use client';

import React, { useState, useEffect } from 'react';
import { auth } from '@/lib/firebase';
import { useAuthState } from 'react-firebase-hooks/auth';
import FirestoreService from '@/lib/firestore';
import { DashboardStats } from '@/types';

export const Dashboard: React.FC = () => {
  const [user, loading] = useAuthState(auth);
  const [stats, setStats] = useState<DashboardStats>({
    totalJobs: 0,
    completedJobs: 0,
    pendingJobs: 0,
    totalRevenue: 0,
    monthlyRevenue: 0,
    activeCustomers: 0,
    pendingEstimates: 0,
    overdueInvoices: 0
  });
  const [dataLoading, setDataLoading] = useState(true);

  useEffect(() => {
    if (!user) {
      setDataLoading(false);
      return;
    }

    const loadDashboardData = async () => {
      try {
        const dashboardStats = await FirestoreService.getDashboardStats();
        setStats(dashboardStats);
      } catch (error) {
        console.error('Error loading dashboard data:', error);
        // Keep showing zeros if there's an error
      } finally {
        setDataLoading(false);
      }
    };

    loadDashboardData();
  }, [user]);

  if (loading) {
    return <div className="text-center py-8">Loading dashboard...</div>;
  }

  return (
    <div className="space-y-6">
      <div className="border-b border-gray-200 pb-4">
        <h1 className="text-2xl font-bold text-gray-900">Dashboard</h1>
        <p className="text-gray-600">Overview of your business metrics and activities</p>
      </div>
      
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6">
        <div className="bg-white p-6 rounded-lg shadow-sm border border-gray-200">
          <h3 className="text-sm font-medium text-gray-500">Total Jobs</h3>
          <p className="text-2xl font-bold text-gray-900">
            {dataLoading ? '...' : stats.totalJobs}
          </p>
          <p className="text-sm text-gray-600">
            {dataLoading ? 'Loading...' : `${stats.completedJobs} completed, ${stats.pendingJobs} pending`}
          </p>
        </div>
        
        <div className="bg-white p-6 rounded-lg shadow-sm border border-gray-200">
          <h3 className="text-sm font-medium text-gray-500">Active Customers</h3>
          <p className="text-2xl font-bold text-gray-900">
            {dataLoading ? '...' : stats.activeCustomers}
          </p>
          <p className="text-sm text-gray-600">Current customer base</p>
        </div>
        
        <div className="bg-white p-6 rounded-lg shadow-sm border border-gray-200">
          <h3 className="text-sm font-medium text-gray-500">Pending Estimates</h3>
          <p className="text-2xl font-bold text-gray-900">
            {dataLoading ? '...' : stats.pendingEstimates}
          </p>
          <p className="text-sm text-gray-600">Awaiting customer approval</p>
        </div>
        
        <div className="bg-white p-6 rounded-lg shadow-sm border border-gray-200">
          <h3 className="text-sm font-medium text-gray-500">Monthly Revenue</h3>
          <p className="text-2xl font-bold text-gray-900">
            {dataLoading ? '...' : `$${stats.monthlyRevenue.toLocaleString()}`}
          </p>
          <p className="text-sm text-gray-600">Current month earnings</p>
        </div>
      </div>

      {/* Additional Stats Row */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6">
        <div className="bg-white p-6 rounded-lg shadow-sm border border-gray-200">
          <h3 className="text-sm font-medium text-gray-500">Total Revenue</h3>
          <p className="text-2xl font-bold text-green-600">
            {dataLoading ? '...' : `$${stats.totalRevenue.toLocaleString()}`}
          </p>
          <p className="text-sm text-gray-600">All-time earnings</p>
        </div>
        
        <div className="bg-white p-6 rounded-lg shadow-sm border border-gray-200">
          <h3 className="text-sm font-medium text-gray-500">Completed Jobs</h3>
          <p className="text-2xl font-bold text-blue-600">
            {dataLoading ? '...' : stats.completedJobs}
          </p>
          <p className="text-sm text-gray-600">Successfully finished</p>
        </div>
        
        <div className="bg-white p-6 rounded-lg shadow-sm border border-gray-200">
          <h3 className="text-sm font-medium text-gray-500">Pending Jobs</h3>
          <p className="text-2xl font-bold text-yellow-600">
            {dataLoading ? '...' : stats.pendingJobs}
          </p>
          <p className="text-sm text-gray-600">In progress or scheduled</p>
        </div>
        
        <div className="bg-white p-6 rounded-lg shadow-sm border border-gray-200">
          <h3 className="text-sm font-medium text-gray-500">Overdue Invoices</h3>
          <p className="text-2xl font-bold text-red-600">
            {dataLoading ? '...' : stats.overdueInvoices}
          </p>
          <p className="text-sm text-gray-600">Require attention</p>
        </div>
      </div>
      
        <div className="bg-blue-50 border border-blue-200 rounded-lg p-4">
          <div className="flex">
            <div className="flex-shrink-0">
              <svg className="h-5 w-5 text-blue-400" viewBox="0 0 20 20" fill="currentColor">
                <path fillRule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z" clipRule="evenodd" />
              </svg>
            </div>
            <div className="ml-3">
              <h3 className="text-sm font-medium text-blue-800">
                Getting Started
              </h3>
              <div className="mt-2 text-sm text-blue-700">
                <p>
                  Start by adding your first customer, then create jobs and estimates. 
                  Your data syncs automatically with your mobile app.
                </p>
              </div>
            </div>
          </div>
        </div>
    </div>
  );
};
