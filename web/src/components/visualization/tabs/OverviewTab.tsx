export const OverviewTab = () => {
  return (
    <div className="space-y-6">
      <div className="bg-white rounded-xl shadow-sm border border-gray-200 p-6">
        <h2 className="text-xl font-semibold text-gray-800 mb-4">Overview Dashboard</h2>
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
          <div className="bg-primary-50 p-4 rounded-lg border border-primary-200">
            <h3 className="text-sm font-medium text-primary-600">Total Conversations</h3>
            <p className="text-2xl font-bold text-primary-600 mt-2">1,234</p>
          </div>
          <div className="bg-primary-50 p-4 rounded-lg border border-primary-200">
            <h3 className="text-sm font-medium text-primary-600">Messages Today</h3>
            <p className="text-2xl font-bold text-primary-600 mt-2">56</p>
          </div>
          <div className="bg-primary-50 p-4 rounded-lg border border-primary-200">
            <h3 className="text-sm font-medium text-primary-600">Active Users</h3>
            <p className="text-2xl font-bold text-primary-600 mt-2">12</p>
          </div>
          <div className="bg-primary-50 p-4 rounded-lg border border-primary-200">
            <h3 className="text-sm font-medium text-primary-600">AI Response Time</h3>
            <p className="text-2xl font-bold text-primary-600 mt-2">1.2s</p>
          </div>
        </div>
      </div>
      
      <div className="bg-white rounded-xl shadow-sm border border-gray-200 p-6">
        <h2 className="text-xl font-semibold text-gray-800 mb-4">Recent Activity</h2>
        <div className="space-y-4">
          <div className="flex items-start space-x-3 p-3 bg-gray-50 rounded-lg">
            <div className="h-8 w-8 bg-primary-100 rounded-lg flex items-center justify-center text-primary-600">
              <svg className="h-4 w-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M12 8c-1.657 0-3 .895-3 2s1.343 2 3 2 3-.895 3-2-1.343-2-3-2zm0 10c-1.657 0-3 .895-3 2s1.343 2 3 2 3-.895 3-2-1.343-2-3-2z"></path>
              </svg>
            </div>
            <div className="flex-1">
              <h3 className="font-medium text-gray-800">New conversation started</h3>
              <p className="text-sm text-gray-500">2 minutes ago</p>
            </div>
          </div>
          <div className="flex items-start space-x-3 p-3 bg-gray-50 rounded-lg">
            <div className="h-8 w-8 bg-primary-100 rounded-lg flex items-center justify-center text-primary-600">
              <svg className="h-4 w-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M9 12h6m2 0a2 2 0 100-4 2 2 0 000 4z"></path>
              </svg>
            </div>
            <div className="flex-1">
              <h3 className="font-medium text-gray-800">AI model updated</h3>
              <p className="text-sm text-gray-500">15 minutes ago</p>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};
