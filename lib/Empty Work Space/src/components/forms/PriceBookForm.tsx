'use client';

import React, { useState } from 'react';
import { Modal } from '@/components/ui/Modal';
import { Button } from '@/components/ui/Button';
import { Input } from '@/components/ui/Input';
import FirestoreService from '@/lib/firestore';
import { PriceBookItem } from '@/types';

interface PriceBookFormProps {
  isOpen: boolean;
  onClose: () => void;
  onSave: (item: PriceBookItem) => void;
  item?: Partial<PriceBookItem>;
}

export const PriceBookForm: React.FC<PriceBookFormProps> = ({ isOpen, onClose, onSave, item }) => {
  const [formData, setFormData] = useState<Partial<PriceBookItem>>({
    idNumber: '',
    name: '',
    description: '',
    category: '',
    unit: '',
    wholesalePrice: 0,
    retailPrice: 0,
    markupPercentage: 0,
    supplier: '',
    ...item
  });
  const [loading, setLoading] = useState(false);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setLoading(true);

    try {
      // Calculate markup percentage if not set
      const calculatedMarkup = formData.wholesalePrice && formData.retailPrice 
        ? ((formData.retailPrice - formData.wholesalePrice) / formData.wholesalePrice) * 100
        : formData.markupPercentage || 0;

      const dataToSave = {
        ...formData,
        markupPercentage: calculatedMarkup
      };

      const itemId = await FirestoreService.savePriceBookItem(dataToSave);
      // Since we don't have a getPriceBookItem method, we'll construct the saved item
      const savedItem: PriceBookItem = {
        id: itemId,
        ...dataToSave,
        lastUpdated: new Date().toISOString(),
        userId: '', // Will be set by the service
      } as PriceBookItem;
      
      onSave(savedItem);
      onClose();
    } catch (error) {
      console.error('Error saving price book item:', error);
      alert('Error saving item. Please try again.');
    } finally {
      setLoading(false);
    }
  };

  const handleWholesaleChange = (value: number) => {
    setFormData(prev => {
      const newData = { ...prev, wholesalePrice: value };
      if (prev.markupPercentage) {
        newData.retailPrice = value * (1 + prev.markupPercentage / 100);
      }
      return newData;
    });
  };

  const handleRetailChange = (value: number) => {
    setFormData(prev => {
      const newData = { ...prev, retailPrice: value };
      if (prev.wholesalePrice && prev.wholesalePrice > 0) {
        newData.markupPercentage = ((value - prev.wholesalePrice) / prev.wholesalePrice) * 100;
      }
      return newData;
    });
  };

  const handleMarkupChange = (value: number) => {
    setFormData(prev => {
      const newData = { ...prev, markupPercentage: value };
      if (prev.wholesalePrice) {
        newData.retailPrice = prev.wholesalePrice * (1 + value / 100);
      }
      return newData;
    });
  };

  return (
    <Modal isOpen={isOpen} onClose={onClose} title={item?.id ? 'Edit Price Book Item' : 'Add New Item'}>
      <form onSubmit={handleSubmit} className="space-y-4">
        <div className="grid grid-cols-2 gap-4">
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">Item ID/Code</label>
            <Input
              value={formData.idNumber || ''}
              onChange={(e) => setFormData({ ...formData, idNumber: e.target.value })}
              placeholder="SKU or item code"
            />
          </div>
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">Category</label>
            <select
              value={formData.category || ''}
              onChange={(e) => setFormData({ ...formData, category: e.target.value })}
              className="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
              required
            >
              <option value="">Select category</option>
              <option value="Materials">Materials</option>
              <option value="Labor">Labor</option>
              <option value="Tools">Tools</option>
              <option value="Equipment">Equipment</option>
              <option value="Services">Services</option>
              <option value="Other">Other</option>
            </select>
          </div>
        </div>

        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">Item Name *</label>
          <Input
            value={formData.name || ''}
            onChange={(e) => setFormData({ ...formData, name: e.target.value })}
            placeholder="Item or service name"
            required
          />
        </div>

        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">Description</label>
          <textarea
            value={formData.description || ''}
            onChange={(e) => setFormData({ ...formData, description: e.target.value })}
            placeholder="Item description"
            rows={2}
            className="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
          />
        </div>

        <div className="grid grid-cols-2 gap-4">
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">Unit</label>
            <select
              value={formData.unit || ''}
              onChange={(e) => setFormData({ ...formData, unit: e.target.value })}
              className="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
              required
            >
              <option value="">Select unit</option>
              <option value="each">Each</option>
              <option value="hour">Hour</option>
              <option value="day">Day</option>
              <option value="meter">Meter</option>
              <option value="square_meter">Square Meter</option>
              <option value="linear_meter">Linear Meter</option>
              <option value="kilogram">Kilogram</option>
              <option value="litre">Litre</option>
              <option value="box">Box</option>
              <option value="pack">Pack</option>
            </select>
          </div>
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">Supplier</label>
            <Input
              value={formData.supplier || ''}
              onChange={(e) => setFormData({ ...formData, supplier: e.target.value })}
              placeholder="Supplier name"
            />
          </div>
        </div>

        <div className="grid grid-cols-3 gap-4">
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">Wholesale Price</label>
            <Input
              type="number"
              step="0.01"
              min="0"
              value={formData.wholesalePrice || ''}
              onChange={(e) => handleWholesaleChange(parseFloat(e.target.value) || 0)}
              placeholder="0.00"
            />
          </div>
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">Markup %</label>
            <Input
              type="number"
              step="0.1"
              min="0"
              value={formData.markupPercentage?.toFixed(1) || ''}
              onChange={(e) => handleMarkupChange(parseFloat(e.target.value) || 0)}
              placeholder="0.0"
            />
          </div>
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">Retail Price *</label>
            <Input
              type="number"
              step="0.01"
              min="0"
              value={formData.retailPrice || ''}
              onChange={(e) => handleRetailChange(parseFloat(e.target.value) || 0)}
              placeholder="0.00"
              required
            />
          </div>
        </div>

        <div className="flex justify-end space-x-3 pt-4">
          <Button type="button" variant="secondary" onClick={onClose}>
            Cancel
          </Button>
          <Button type="submit" disabled={loading}>
            {loading ? 'Saving...' : (item?.id ? 'Update Item' : 'Add Item')}
          </Button>
        </div>
      </form>
    </Modal>
  );
};
