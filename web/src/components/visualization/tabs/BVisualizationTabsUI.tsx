import { ReactNode } from 'react';

interface TabsProps {
  children: ReactNode;
  className?: string;
}

interface TabsListProps {
  children: ReactNode;
  className?: string;
}

interface TabProps {
  children: ReactNode;
  value: string;
  active: boolean;
  onClick: () => void;
  className?: string;
}

interface TabsContentProps {
  children: ReactNode;
  className?: string;
}

export const Tabs = ({ children, className = '' }: TabsProps) => (
  <div className={className}>{children}</div>
);

export const TabsList = ({ children, className = '' }: TabsListProps) => (
  <div className={`flex border-b border-gray-200 ${className}`}>{children}</div>
);

export const Tab = ({ 
  children, 
  value, 
  active, 
  onClick, 
  className = '' 
}: TabProps) => (
  <button
    onClick={onClick}
    className={`flex items-center text-sm font-medium 
      ${active 
        ? 'text-primary-600 border-b-2 border-primary-500' 
        : 'text-gray-500 hover:text-gray-700'}
      px-3 py-2 transition-colors ${className}`}
  >
    {children}
  </button>
);

export const TabsContent = ({ children, className = '' }: TabsContentProps) => (
  <div className={className}>{children}</div>
);
