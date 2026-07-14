import { IconSymbolName } from '@/components/ui/icon-symbol';

export type ReminderListMeta = {
  id: string;
  name: string;
  icon: IconSymbolName;
  allowRecurrence: boolean;
};

export const REMINDER_LISTS: ReminderListMeta[] = [
  { id: 'chores', name: 'Chores', icon: 'arrow.triangle.2.circlepath', allowRecurrence: true },
  { id: 'tasks', name: 'Tasks', icon: 'list.bullet', allowRecurrence: false },
];

export function getReminderList(id: string): ReminderListMeta | undefined {
  return REMINDER_LISTS.find((list) => list.id === id);
}
