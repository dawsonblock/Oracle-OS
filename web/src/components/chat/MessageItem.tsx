import { formatDistanceToNow } from 'date-fns';

export const MessageItem = ({ message }: { message: {
  id: string;
  content: string;
  role: 'user' | 'assistant';
  timestamp: Date;
} }) => {
  const isUser = message.role === 'user';
  
  return (
    <div className={`chat-message ${isUser ? 'user-message' : 'assistant-message'} `}>
      <div className="flex items-start space-x-3">
        {!isUser && (
          <div className="h-8 w-8 flex-shrink-0 bg-primary-100 rounded-lg flex items-center justify-center text-primary-600">
            <svg className="h-4 w-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M12 8c-1.657 0-3 .895-3 2s1.343 2 3 2 3-.895 3-2-1.343-2-3-2zm0 10c-1.657 0-3 .895-3 2s1.343 2 3 2 3-.895 3-2-1.343-2-3-2z"></path>
            </svg>
          </div>
        )}
        <div className="flex-1">
          <div className="message-content whitespace-pre-wrap break-words">{message.content}</div>
          <div className="message-time text-xs text-gray-500 mt-1">
            {formatDistanceToNow(message.timestamp, { addSuffix: true })}
          </div>
        </div>
      </div>
    </div>
  );
};
