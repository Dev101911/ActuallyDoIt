export type Priority = 'low' | 'medium' | 'high';

export type Reminder = {
  id: string;
  listId: string;
  title: string;
  details: string | null;
  expectedMinutes: number | null;
  deadline: string | null;
  priority: Priority | null;
  alertFrequencyMinutes: number | null;
  recurrenceIntervalDays: number | null;
  completed: boolean;
  createdAt: string;
};

export type ReminderInput = {
  listId: string;
  title: string;
  details?: string | null;
  expectedMinutes?: number | null;
  deadline?: string | null;
  priority?: Priority | null;
  alertFrequencyMinutes?: number | null;
  recurrenceIntervalDays?: number | null;
};
