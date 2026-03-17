export const AnalyticsTab = () => {
  return (
    <div className="space-y-6">
      <div className="bg-white rounded-xl shadow-sm border border-gray-200 p-6">
        <h2 className="text-xl font-semibold text-gray-800 mb-4">Conversation Analytics</h2>
        <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
          <div className="space-y-4">
            <h3 className="text-lg font-medium text-gray-800">Message Length Distribution</h3>
            <div className="bg-gray-50 p-4 rounded-lg">
              <div className="flex items-center justify-between mb-2">
                <span className="text-sm font-medium text-gray-600">Short (0-50 chars)</span>
                <span className="text-sm font-medium text-primary-600">45%</span>
              </div>
              <div className="w-full bg-gray-200 rounded-full h-2.5">
                <div className="bg-primary-500 h-2.5 rounded-full" style={{ width: '45%' }}></div>
              </div>
            </div>
            <div className="flex items-center justify-between mb-2">
              <span className="text-sm font-medium text-gray-600">Medium (51-150 chars)</span>
              <span className="text-sm font-medium text-primary-600">35%</span>
            </div>
            <div className="w-full bg-gray-200 rounded-full h-2.5">
              <div className="bg-primary-500 h-2.5 rounded-full" style={{ width: '35%' }}></div>
            </div>
            <div className="flex items-center justify-between mb-2">
              <span className="text-sm font-medium text-gray-600">Long (151+ chars)</span>
              <span className="text-sm font-medium text-primary-600">20%</span>
            </div>
            <div className="w-full bg-gray-200 rounded-full h-2.5">
              <div className="bg-primary-500 h-2.5 rounded-full" style={{ width: '20%' }}></div>
            </div>
          </div>
          <div className="space-y-4">
            <h3 className="text-lg font-medium text-gray-800">Response Time Trends</h3>
            <div className="bg-gray-50 p-4 rounded-lg">
              <div className="flex items-center justify-between mb-2">
                <span className="text-sm font-medium text-gray-600">Average Response Time</span>
                <span className="text-sm font-medium text-primary-600">1.2s</span>
              </div>
              <div className="w-full bg-gray-200 rounded-full h-2.5">
                <div className="bg-primary-500 h-2.5 rounded-full" style={{ width: '70%' }}></div>
              </div>
            </div>
            <div className="flex items-center justify-between mb-2">
              <span className="text-sm font-medium text-gray-600">Fastest Response</span>
              <span className="text-sm font-medium text-primary-600">0.3s</span>
              </div>
            <div className="w-full bg-gray-200 rounded-full h-2.5">
              <div className="bg-primary-500 h-2.5 rounded-full" style={{ width: '90%' }}></div>
            </div>
            <div className="flex items-center justify-between mb-2">
              <span className="text-sm font-medium text-gray-600">Slowest Response</span>
              <span className="text-sm font-medium text-primary-600">3.1s</span>
            </div>
            <div className="w-full bg-gray-200 rounded-full h-2.5">
              <div className="bg-primary-500 h-2.5 rounded-full" style={{ width: '40%' }}></div>
            </div>
          </div>
        </div>
      </div>
      
      <div className="bg-white rounded-xl shadow-sm border border-gray-200 p-6">
        <h2 className="text-xl font-semibold text-gray-800 mb-4">User Engagement Metrics</h2>
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          <div className="bg-primary-50 p-4 rounded-lg border border-primary-200 text-center">
            <div className="text-2xl font-bold text-primary-600 mb-2">87%</div>
            <p className="text-sm font-medium text-gray-600">User Satisfaction</p>
          </div>
          <div className="bg-primary-50 p-4 rounded-lg border border-primary-200 text-center">
            <div className="text-2xl font-bold text-primary-600 mb-2">4.2</div>
            <p className="text-sm font-medium text-gray-600">Avg. Session Length (min)</p>
          </div>
          <div className="bg-primary-50 p-4 rounded-lg border border-primary-200 text-center">
            <div className="text-2xl font-bold text-primary-600 mb-2">92%</div>
            <p className="text-sm font-medium text-gray-600">Return User Rate</p>
          </div>
        </div>
      </div>
    </div>
  );
};
