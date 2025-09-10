'use client';

import React, { useState, useEffect } from 'react';
import { Modal } from '@/components/ui/Modal';
import { Button } from '@/components/ui/Button';
import { Input } from '@/components/ui/Input';
import FirestoreService from '@/lib/firestore';
import { Job, Customer } from '@/types';

interface JobFormProps {
  isOpen: boolean;
  onClose: () => void;
  onSave: (job: Job) => void;
  job?: Partial<Job>;
}

export const JobForm: React.FC<JobFormProps> = ({ isOpen, onClose, onSave, job }) => {
  const [formData, setFormData] = useState<Partial<Job>>({
    customerName: '',
    address: '',
    phone: '',
    email: '',
    jobType: '',
    status: 'pending',
    priority: 'medium',
    notes: '',
    totalCost: 0,
    ...job
  });
  const [customers, setCustomers] = useState<Customer[]>([]);
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    if (isOpen) {
      loadCustomers();
    }
  }, [isOpen]);

  const loadCustomers = async () => {
    try {
      const customersData = await FirestoreService.getCustomers();
      setCustomers(customersData);
    } catch (error) {
      console.error('Error loading customers:', error);
    }
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setLoading(true);

    try {
      const jobId = await FirestoreService.saveJob(formData);
      const savedJob = await FirestoreService.getJob(jobId);
      if (savedJob) {
        onSave(savedJob);
      }
      onClose();
    } catch (error) {
      console.error('Error saving job:', error);
      alert('Error saving job. Please try again.');
    } finally {
      setLoading(false);
    }
  };

  const handleCustomerSelect = (customer: Customer) => {
    setFormData({
      ...formData,
      customerName: customer.name,
      address: customer.address || '',
      phone: customer.phone || '',
      email: customer.email || ''
    });
  };

  return (
    <Modal isOpen={isOpen} onClose={onClose} title={job?.id ? 'Edit Job' : 'Create New Job'}>
      <form onSubmit={handleSubmit} className="space-y-4">
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">Customer</label>
          <div className="space-y-2">
            <Input
              value={formData.customerName || ''}
              onChange={(e) => setFormData({ ...formData, customerName: e.target.value })}
              placeholder="Customer name"
              required
            />
            {customers.length > 0 && (
              <div className="max-h-32 overflow-y-auto border border-gray-200 rounded-md">
                {customers
                  .filter(c => c.name.toLowerCase().includes((formData.customerName || '').toLowerCase()))
                  .slice(0, 5)
                  .map(customer => (
                    <button
                      key={customer.id}
                      type="button"
                      onClick={() => handleCustomerSelect(customer)}
                      className="w-full text-left px-3 py-2 hover:bg-gray-50 text-sm"
                    >
                      <div className="font-medium">{customer.name}</div>
                      <div className="text-gray-500 text-xs">{customer.address}</div>
                    </button>
                  ))}
              </div>
            )}
          </div>
        </div>

        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">Job Type</label>
          <select
            value={formData.jobType || ''}
            onChange={(e) => setFormData({ ...formData, jobType: e.target.value })}
            className="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
            required
          >
            <option value="">Select job type</option>
            <option value="plumbing">Plumbing</option>
            <option value="electrical">Electrical</option>
            <option value="carpentry">Carpentry</option>
            <option value="painting">Painting</option>
            <option value="flooring">Flooring</option>
            <option value="roofing">Roofing</option>
            <option value="hvac">HVAC</option>
            <option value="general_maintenance">General Maintenance</option>
            <option value="other">Other</option>
          </select>
        </div>

        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">Address</label>
          <Input
            value={formData.address || ''}
            onChange={(e) => setFormData({ ...formData, address: e.target.value })}
            placeholder="Job address"
            required
          />
        </div>

        <div className="grid grid-cols-2 gap-4">
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">Phone</label>
            <Input
              type="tel"
              value={formData.phone || ''}
              onChange={(e) => setFormData({ ...formData, phone: e.target.value })}
              placeholder="Phone number"
            />
          </div>
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">Email</label>
            <Input
              type="email"
              value={formData.email || ''}
              onChange={(e) => setFormData({ ...formData, email: e.target.value })}
              placeholder="Email address"
            />
          </div>
        </div>

        <div className="grid grid-cols-2 gap-4">
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">Status</label>
            <select
              value={formData.status || 'pending'}
              onChange={(e) => setFormData({ ...formData, status: e.target.value as Job['status'] })}
              className="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
            >
              <option value="pending">Pending</option>
              <option value="in_progress">In Progress</option>
              <option value="completed">Completed</option>
              <option value="cancelled">Cancelled</option>
            </select>
          </div>
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">Priority</label>
            <select
              value={formData.priority || 'medium'}
              onChange={(e) => setFormData({ ...formData, priority: e.target.value as Job['priority'] })}
              className="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
            >
              <option value="low">Low</option>
              <option value="medium">Medium</option>
              <option value="high">High</option>
            </select>
          </div>
        </div>

        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">Estimated Cost</label>
          <Input
            type="number"
            step="0.01"
            min="0"
            value={formData.totalCost || ''}
            onChange={(e) => setFormData({ ...formData, totalCost: parseFloat(e.target.value) || 0 })}
            placeholder="0.00"
          />
        </div>

        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">Notes</label>
          <textarea
            value={formData.notes || ''}
            onChange={(e) => setFormData({ ...formData, notes: e.target.value })}
            placeholder="Additional notes about the job"
            rows={3}
            className="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
          />
        </div>

        <div className="flex justify-end space-x-3 pt-4">
          <Button type="button" variant="secondary" onClick={onClose}>
            Cancel
          </Button>
          <Button type="submit" disabled={loading}>
            {loading ? 'Saving...' : (job?.id ? 'Update Job' : 'Create Job')}
          </Button>
        </div>
      </form>
    </Modal>
  );
};
