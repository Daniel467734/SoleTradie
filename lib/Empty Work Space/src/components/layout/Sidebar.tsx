import React from 'react';

type ViewType = 'dashboard' | 'jobs' | 'customers' | 'estimates' | 'invoices' | 'pricebook' | 'settings';

interface SidebarProps {
  currentView: ViewType;
  setCurrentView: (view: ViewType) => void;
  isOpen: boolean;
  setIsOpen: (open: boolean) => void;
}

export const Sidebar: React.FC<SidebarProps> = ({ 
  currentView, 
  setCurrentView, 
  isOpen 
}) => {
  const menuItems: Array<{ id: ViewType; name: string; icon: string }> = [
    { id: 'dashboard', name: 'Dashboard', icon: '📊' },
    { id: 'jobs', name: 'Jobs', icon: '🔨' },
    { id: 'customers', name: 'Customers', icon: '👥' },
    { id: 'estimates', name: 'Estimates', icon: '📋' },
    { id: 'invoices', name: 'Invoices', icon: '💰' },
    { id: 'pricebook', name: 'Price Book', icon: '📖' },
    { id: 'settings', name: 'Settings', icon: '⚙️' },
  ];

  return (
    <div className={`bg-gray-900 text-white w-64 min-h-screen p-4 ${isOpen ? 'block' : 'hidden'} lg:block`}>
      <div className="mb-8">
        <h2 className="text-xl font-bold">Tradesperson</h2>
        <p className="text-gray-400 text-sm">Business Manager</p>
      </div>
      
      <nav className="space-y-2">
        {menuItems.map((item) => (
          <button
            key={item.id}
            onClick={() => setCurrentView(item.id)}
            className={`w-full text-left px-4 py-2 rounded-lg flex items-center space-x-3 transition-colors ${
              currentView === item.id
                ? 'bg-blue-600 text-white'
                : 'text-gray-300 hover:bg-gray-800 hover:text-white'
            }`}
          >
            <span className="text-lg">{item.icon}</span>
            <span>{item.name}</span>
          </button>
        ))}
      </nav>
    </div>
  );
};
