import AsyncStorage from '@react-native-async-storage/async-storage';
import { useCallback, useEffect, useState } from 'react';

import { Reminder, ReminderInput } from '@/types/reminder';

const STORAGE_KEY = 'reminders';

export function useReminders() {
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
        title: input.title,
        details: input.details ?? null,
        expectedMinutes: input.expectedMinutes ?? null,
        deadline: input.deadline ?? null,
        priority: input.priority ?? null,
        alertFrequencyMinutes: input.alertFrequencyMinutes ?? null,
        completed: false,
        createdAt: new Date().toISOString(),
      };
      persist([reminder, ...reminders]);
    },
    [reminders, persist],
  );

  const updateReminder = useCallback(
    (id: string, input: ReminderInput) => {
      persist(
        reminders.map((r) =>
          r.id === id
            ? {
                ...r,
                title: input.title,
                details: input.details ?? null,
                expectedMinutes: input.expectedMinutes ?? null,
                deadline: input.deadline ?? null,
                priority: input.priority ?? null,
                alertFrequencyMinutes: input.alertFrequencyMinutes ?? null,
              }
            : r,
        ),
      );
    },
    [reminders, persist],
  );

  const toggleReminder = useCallback(
    (id: string) => {
      persist(reminders.map((r) => (r.id === id ? { ...r, completed: !r.completed } : r)));
    },
    [reminders, persist],
  );

  const deleteReminder = useCallback(
    (id: string) => {
      persist(reminders.filter((r) => r.id !== id));
    },
    [reminders, persist],
  );

  return { reminders, isLoaded, addReminder, updateReminder, toggleReminder, deleteReminder };
}
