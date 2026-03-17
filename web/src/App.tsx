import { BrowserRouter, Routes, Route } from 'react-router-dom';
import MainLayout from './components/layout/MainLayout';
import ChatInterface from './components/chat/ChatInterface';
import BVisualizationTabs from './components/visualization/BVisualizationTabs';

function App() {
  return (
    <BrowserRouter>
      <MainLayout>
        <Routes>
          <Route path="/" element={<ChatInterface />} />
          <Route path="/visualization" element={<BVisualizationTabs />} />
        </Routes>
      </MainLayout>
    </BrowserRouter>
  );
}

export default App;
