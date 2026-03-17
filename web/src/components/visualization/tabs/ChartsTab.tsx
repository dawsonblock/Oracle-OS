import { BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer } from 'recharts';

export const ChartsTab = () => {
  const data = [
    { name: 'Jan', messages: 400, users: 240, satisfaction: 85 },
    { name: 'Feb', messages: 300, users: 139, satisfaction: 92 },
    { name: 'Mar', messages: 200, users: 980, satisfaction: 78 },
    { name: 'Apr', messages: 278, users: 390, satisfaction: 89 },
    { name: 'May', messages: 189, users: 480, satisfaction: 91 },
    { name: 'Jun', messages: 239, users: 380, satisfaction: 87 },
  ];

  return (
    <div className="space-y-6">
      <div className="bg-white rounded-xl shadow-sm border border-gray-200 p-6">
        <h2 className="text-xl font-semibold text-gray-800 mb-4">Usage Analytics</h2>
        <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
          <div className="space-y-4">
            <h3 className="text-lg font-medium text-gray-800">Messages Over Time</h3>
            <ResponsiveContainer width="100%" height={300}>
              <BarChart data={data}>
                <CartesianGrid strokeDasharray="3 3" />
                <XAxis dataKey="name" />
                <YAxis />
                <Tooltip />
                <Legend />
                <Bar dataKey="messages" fill="#3b82f6" />
              </BarChart>
            </ResponsiveContainer>
          </div>
          <div className="space-y-4">
            <h3 className="text-lg font-medium text-gray-800">Active Users</h3>
            <ResponsiveContainer width="100%" height={300}>
              <BarChart data={data}>
                <CartesianGrid strokeDasharray="3 3" />
                <XAxis dataKey="name" />
                <YAxis />
                <Tooltip />
                <Legend />
                <Bar dataKey="users" fill="#10b981" />
              </BarChart>
            </ResponsiveContainer>
          </div>
        </div>
      </div>
      
      <div className="bg-white rounded-xl shadow-sm border border-gray-200 p-6">
        <h2 className="text-xl font-semibold text-gray-800 mb-4">Satisfaction Trends</h2>
        <ResponsiveContainer width="100%" height={350}>
          <BarChart data={data}>
            <CartesianGrid strokeDasharray="3 3" />
            <XAxis dataKey="name" />
            <YAxis />
            <Tooltip />
            <Legend />
            <Bar dataKey="satisfaction" fill="#f59e0b" />
          </BarChart>
        </ResponsiveContainer>
      </div>
    </div>
  );
};
