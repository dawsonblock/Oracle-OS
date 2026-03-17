import { Link } from 'react-router-dom';

export const Header = () => {
  return (
    <header className="bg-white border-b border-gray-200">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 flex flex-wrap items-center justify-between py-4">
        <div className="flex items-center space-x-3">
          <div className="h-8 w-8 bg-gradient-to-br from-blue-500 to-cyan-500 rounded-lg flex items-center justify-center text-white font-bold">
            AI
          </div>
          <h1 className="text-xl font-semibold text-gray-800">Oracle AI Assistant</h1>
        </div>
        <nav className="hidden md:flex space-x-4">
          <Link to="/" className="text-gray-600 hover:text-gray-900 transition-colors font-medium">
            Chat
          </Link>
          <Link to="/visualization" className="text-gray-600 hover:text-gray-900 transition-colors font-medium">
            Visualization
          </Link>
        </nav>
        <div className="flex items-center space-x-3">
          <button className="p-2 rounded-lg hover:bg-gray-100 transition-colors">
            <svg className="h-5 w-5 text-gray-600" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
              <path d="M21 15a2 2 0 01-2 2H7l-4 4V5a2 2 0 012-2h14a2 2 0 012 2z"></path>
            </svg>
          </button>
          <button className="p-2 rounded-lg hover:bg-gray-100 transition-colors">
            <svg className="h-5 w-5 text-gray-600" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
              <circle cx="12" cy="12" r="10"></circle>
              <line x1="12" y1="8" x2="12" y2="12"></line>
              <line x1="12" y1="16" x2="12.01" y2="16"></line>
            </svg>
          </button>
        </div>
      </div>
    </header>
  );
};
