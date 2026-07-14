import { Priority, Reminder } from '@/types/reminder';

function priorityRank(priority: Priority | null): number {
  switch (priority) {
    case 'high':
      return 0;
    case 'medium':
      return 1;
    case 'low':
      return 2;
    default:
      return 3;
  }
}

export function isDueTodayOrOverdue(reminder: Reminder): boolean {
  if (!reminder.deadline) return false;
  const endOfToday = new Date();
  endOfToday.setHours(23, 59, 59, 999);
  return new Date(reminder.deadline).getTime() <= endOfToday.getTime();
}

export function byUrgency(a: Reminder, b: Reminder): number {
  const rankDiff = priorityRank(a.priority) - priorityRank(b.priority);
  if (rankDiff !== 0) return rankDiff;
  const aTime = a.deadline ? new Date(a.deadline).getTime() : Infinity;
  const bTime = b.deadline ? new Date(b.deadline).getTime() : Infinity;
  return aTime - bTime;
}
