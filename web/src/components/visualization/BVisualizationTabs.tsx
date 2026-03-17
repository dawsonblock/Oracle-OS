import { useState } from 'react';
import { Tabs, TabsList, Tab, TabsContent } from './tabs/BVisualizationTabsUI';
import OverviewTab from './tabs/OverviewTab';
import AnalyticsTab from './tabs/AnalyticsTab';
import ChartsTab from './tabs/ChartsTab';
import ReportsTab from './tabs/ReportsTab';

export const BVisualizationTabs = () => {
  const [activeTab, setActiveTab] = useState<'overview' | 'analytics' | 'charts' | 'reports'>('overview');

  return (
    <div className="space-y-6">
      <div className="bg-white rounded-xl shadow-sm border border-gray-200">
        <TabsList>
          <Tab
            value="overview"
            active={activeTab === 'overview'}
            onClick={() => setActiveTab('overview')}
            className="px-4 py-3 text-sm font-medium transition-all"
          >
            Overview
          </Tab>
          <Tab
            value="analytics"
            active={activeTab === 'analytics'}
            onClick={() => setActiveTab('analytics')}
            className="px-4 py-3 text-sm font-medium transition-all"
          >
            Analytics
          </Tab>
          <Tab
            value="charts"
            active={activeTab === 'charts'}
            onClick={() => setActiveTab('charts')}
            className="px-4 py-3 text-sm font-medium transition-all"
          >
            Charts
          </Tab>
          <Tab
            value="reports"
            active={activeTab === 'reports'}
            onClick={() => setActiveTab('reports')}
            className="px-4 py-3 text-sm font-medium transition-all"
          >
            Reports
          </Tab>
        </TabsList>
      </div>

      <TabsContent className="space-y-4">
        {activeTab === 'overview' && <OverviewTab />}
        {activeTab === 'analytics' && <AnalyticsTab />}
        {activeTab === 'charts' && <ChartsTab />}
        {activeTab === 'reports' && <ReportsTab />}
      </TabsContent>
    </div>
  );
};
