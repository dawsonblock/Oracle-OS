import { MessageItem } from './MessageItem';

export const MessageList = ({ messages }: { messages: Array<{
  id: string;
  content: string;
  role: 'user' | 'assistant';
  timestamp: Date;
}> }) => {
  return (
    <div className="flex-1 overflow-y-auto p-4 space-y-2">
      {messages.map(message => (
        <MessageItem key={message.id} message={message} />
      ))}
      <div className="h-8" />
    </div>
  );
};
