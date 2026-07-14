import AsyncStorage from '@react-native-async-storage/async-storage';
import { createContext, ReactNode, useCallback, useContext, useEffect, useState } from 'react';

import { Reminder, ReminderInput } from '@/types/reminder';

const STORAGE_KEY = 'reminders';

function nextOccurrenceDeadline(intervalDays: number): string {
  const next = new Date();
  next.setDate(next.getDate() + intervalDays);
  return next.toISOString();
}

type RemindersContextValue = {
  reminders: Reminder[];
  isLoaded: boolean;
  addReminder: (input: ReminderInput) => void;
  updateReminder: (id: string, input: ReminderInput) => void;
  toggleReminder: (id: string) => void;
  deleteReminder: (id: string) => void;
};

const RemindersContext = createContext<RemindersContextValue | null>(null);

// Tab screens stay mounted when you switch tabs, so this state has to live above
// them in a single shared provider — otherwise each screen's own copy goes stale
// the moment another screen writes to storage.
export function RemindersProvider({ children }: { children: ReactNode }) {
  const [reminders, setReminders] = useState<Reminder[]>([]);
  const [isLoaded, setIsLoaded] = useState(false);

  useEffect(() => {
    AsyncStorage.getItem(STORAGE_KEY)
      .then((raw) => {
        if (raw) setReminders(JSON.parse(raw));
      })
      .finally(() => setIsLoaded(true));
  }, []);

  const persist = useCallback((next: Reminder[]) => {
    setReminders(next);
    AsyncStorage.setItem(STORAGE_KEY, JSON.stringify(next));
  }, []);

  const addReminder = useCallback(
    (input: ReminderInput) => {
      const reminder: Reminder = {
        id: Date.now().toString(),
        listId: input.listId,
        title: input.title,
        details: input.details ?? null,
        expectedMinutes: input.expectedMinutes ?? null,
        deadline: input.deadline ?? null,
        priority: input.priority ?? null,
        alertFrequencyMinutes: input.alertFrequencyMinutes ?? null,
        recurrenceIntervalDays: input.recurrenceIntervalDays ?? null,
        completed: false,
        createdAt: new Date().toISOString(),
      };
      setReminders((prev) => {
        const next = [reminder, ...prev];
        AsyncStorage.setItem(STORAGE_KEY, JSON.stringify(next));
        return next;
      });
    },
    [],
  );

  const updateReminder = useCallback((id: string, input: ReminderInput) => {
    setReminders((prev) => {
      const next = prev.map((r) =>
        r.id === id
          ? {
              ...r,
              title: input.title,
              details: input.details ?? null,
              expectedMinutes: input.expectedMinutes ?? null,
              deadline: input.deadline ?? null,
              priority: input.priority ?? null,
              alertFrequencyMinutes: input.alertFrequencyMinutes ?? null,
              recurrenceIntervalDays: input.recurrenceIntervalDays ?? null,
            }
          : r,
      );
      AsyncStorage.setItem(STORAGE_KEY, JSON.stringify(next));
      return next;
    });
  }, []);

  const toggleReminder = useCallback((id: string) => {
    setReminders((prev) => {
      const next = prev.map((r) => {
        if (r.id !== id) return r;
        // Recurring items never stay checked off — completing one just rolls its deadline forward.
        if (!r.completed && r.recurrenceIntervalDays != null) {
          return { ...r, completed: false, deadline: nextOccurrenceDeadline(r.recurrenceIntervalDays) };
        }
        return { ...r, completed: !r.completed };
      });
      AsyncStorage.setItem(STORAGE_KEY, JSON.stringify(next));
      return next;
    });
  }, []);

  const deleteReminder = useCallback((id: string) => {
    setReminders((prev) => {
      const next = prev.filter((r) => r.id !== id);
      AsyncStorage.setItem(STORAGE_KEY, JSON.stringify(next));
      return next;
    });
  }, []);

  return (
    <RemindersContext.Provider
      value={{ reminders, isLoaded, addReminder, updateReminder, toggleReminder, deleteReminder }}>
      {children}
    </RemindersContext.Provider>
  );
}

export function useReminders() {
  const context = useContext(RemindersContext);
  if (!context) throw new Error('useReminders must be used within a RemindersProvider');
  return context;
}
