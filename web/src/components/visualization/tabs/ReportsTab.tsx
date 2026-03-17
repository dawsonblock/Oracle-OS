export const ReportsTab = () => {
  return (
    <div className="space-y-6">
      <div className="bg-white rounded-xl shadow-sm border border-gray-200 p-6">
        <h2 className="text-xl font-semibold text-gray-800 mb-4">Generate Reports</h2>
        <div className="space-y-4">
          <div className="flex items-start space-x-3">
            <div className="h-8 w-8 bg-primary-100 rounded-lg flex items-center justify-center text-primary-600 flex-shrink-0">
              <svg className="h-4 w-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M9 5h6M9 9h6m-6 4h6M5 17h14a2 2 0 002-2V5a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z"></path>
              </svg>
            </div>
            <div className="flex-1">
              <h3 className="font-medium text-gray-800">Conversation Export</h3>
              <p className="text-sm text-gray-500">Export chat history as JSON, CSV, or PDF</p>
              <button className="mt-2 px-4 py-2 bg-primary-600 text-white rounded-lg hover:bg-primary-700 transition-colors text-sm">
                Export Conversations
              </button>
            </div>
          </div>
          <div className="flex items-start space-x-3">
            <div className="h-8 w-8 bg-primary-100 rounded-lg flex items-center justify-center text-primary-600 flex-shrink-0">
              <svg className="h-4 w-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M12 8c-1.657 0-3 .895-3 2s1.343 2 3 2 3-.895 3-2-1.343-2-3-2zm0 10c-1.657 0-3 .895-3 2s1.343 2 3 2 3-.895 3-2-1.343-2-3-2z"></path>
              </svg>
            </div>
            <div className="flex-1">
              <h3 className="font-medium text-gray-800">Analytics Report</h3>
              <p className="text-sm text-gray-500">Generate detailed analytics and insights report</p>
              <button className="mt-2 px-4 py-2 bg-primary-600 text-white rounded-lg hover:bg-primary-700 transition-colors text-sm">
                Generate Analytics
              </button>
            </div>
          </div>
          <div className="flex items-start space-x-3">
            <div className="h-8 w-8 bg-primary-100 rounded-lg flex items-center justify-center text-primary-600 flex-shrink-0">
              <svg className="h-4 w-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M9 12h6m2 0a2 2 0 100-4 2 2 0 000 4z"></path>
              </svg>
            </div>
            <div className="flex-1">
              <h3 className="font-medium text-gray-800">User Feedback Summary</h3>
              <p className="text-sm text-gray-500">Compile user feedback and satisfaction metrics</p>
              <button className="mt-2 px-4 py-2 bg-primary-600 text-white rounded-lg hover:bg-primary-700 transition-colors text-sm">
                Generate Feedback Report
              </button>
            </div>
          </div>
        </div>
      </div>
      
      <div className="bg-white rounded-xl shadow-sm border border-gray-200 p-6">
        <h2 className="text-xl font-semibold text-gray-800 mb-4">Scheduled Reports</h2>
        <div className="space-y-3">
          <div className="flex items-center justify-between p-3 bg-gray-50 rounded-lg">
            <div className="flex items-center space-x-3">
              <div className="h-6 w-6 bg-primary-100 rounded-lg flex items-center justify-center text-primary-600 flex-shrink-0">
                <svg className="h-4 w-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V9a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z"></path>
                </svg>
              </div>
              <div>
                <h3 className="font-medium text-gray-800">Daily Summary Report</h3>
                <p className="text-sm text-gray-500">Every day at 8:00 AM</p>
              </div>
              <div className="flex items-center space-x-2">
                <button className="px-2 py-1 bg-primary-100 text-primary-800 text-xs rounded hover:bg-primary-200">Edit</button>
                <button className="px-2 py-1 bg-primary-100 text-primary-800 text-xs rounded hover:bg-primary-200">Delete</button>
              </div>
            </div>
            <div className="w-2 h-2 bg-primary-200 rounded-full"></div>
          </div>
          <div className="flex items-center justify-between p-3 bg-gray-50 rounded-lg">
            <div className="flex items-center space-x-3">
              <div className="h-6 w-6 bg-primary-100 rounded-lg flex items-center justify-center text-primary-600 flex-shrink-0">
                <svg className="h-4 w-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V9a2 2 0 00-2-2H5a2 2 0 00-2-2v10a2 2 0 002 2z"></path>
                </svg>
              </div>
              <div>
                <h3 className="font-medium text-gray-800">Weekly Analytics</h3>
                <p className="text-sm text-gray-500">Every Monday at 9:00 AM</p>
              </div>
              <div className="flex items-center space-x-2">
                <button className="px-2 py-1 bg-primary-100 text-primary-800 text-xs rounded hover:bg-primary-200">Edit</button>
                <button className="px-2 py-1 bg-primary-100 text-primary-800 text-xs rounded hover:bg-primary-200">Delete</button>
              </div>
            </div>
            <div className="w-2 h-2 bg-primary-200 rounded-full"></div>
          </div>
        </div>
      </div>
    </div>
  );
};
