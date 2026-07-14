import { forwardRef, useImperativeHandle, useState } from 'react';
import { Pressable, StyleSheet, useColorScheme } from 'react-native';

import { ReminderForm } from '@/components/reminder-form';
import { ThemedText } from '@/components/themed-text';
import { Colors } from '@/constants/theme';
import { getReminderList } from '@/types/reminder-list';
import { Reminder, ReminderInput } from '@/types/reminder';

export type ReminderEditorHandle = {
  edit: (reminder: Reminder) => void;
};

/**
 * Owns the add/edit modal for reminders. Renders a "+ Add" button when
 * `addButtonListId` is given (creating items in that list); either way, callers
 * can trigger the edit flow for an existing reminder via the exposed ref.
 */
export const ReminderEditor = forwardRef<
  ReminderEditorHandle,
  {
    onAdd: (input: ReminderInput) => void;
    onUpdate: (id: string, input: ReminderInput) => void;
    addButtonListId?: string;
  }
>(function ReminderEditor({ onAdd, onUpdate, addButtonListId }, ref) {
  const theme = Colors[useColorScheme() ?? 'light'];
  const [visible, setVisible] = useState(false);
  const [editingReminder, setEditingReminder] = useState<Reminder | null>(null);
  const [activeListId, setActiveListId] = useState(addButtonListId ?? '');

  useImperativeHandle(ref, () => ({
    edit: (reminder) => {
      setEditingReminder(reminder);
      setActiveListId(reminder.listId);
      setVisible(true);
    },
  }));

  const openNew = () => {
    if (!addButtonListId) return;
    setEditingReminder(null);
    setActiveListId(addButtonListId);
    setVisible(true);
  };

  const handleSave = (input: ReminderInput) => {
    if (editingReminder) {
      onUpdate(editingReminder.id, input);
    } else {
      onAdd(input);
    }
    setVisible(false);
  };

  const allowRecurrence = getReminderList(activeListId)?.allowRecurrence ?? false;

  return (
    <>
      {addButtonListId && (
        <Pressable onPress={openNew} hitSlop={8} style={[styles.addButton, { backgroundColor: theme.tint }]}>
          <ThemedText lightColor={Colors.dark.text} darkColor={Colors.light.text} type="defaultSemiBold">
            + Add
          </ThemedText>
        </Pressable>
      )}

      <ReminderForm
        visible={visible}
        reminder={editingReminder}
        listId={activeListId}
        allowRecurrence={allowRecurrence}
        onSave={handleSave}
        onCancel={() => setVisible(false)}
      />
    </>
  );
});

const styles = StyleSheet.create({
  addButton: {
    paddingHorizontal: 16,
    paddingVertical: 10,
    borderRadius: 20,
  },
});
