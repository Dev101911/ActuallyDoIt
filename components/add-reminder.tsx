import { forwardRef, useImperativeHandle, useState } from 'react';
import { Pressable, StyleSheet, useColorScheme } from 'react-native';

import { ReminderForm } from '@/components/reminder-form';
import { ThemedText } from '@/components/themed-text';
import { Colors } from '@/constants/theme';
import { Reminder, ReminderInput } from '@/types/reminder';

export type AddReminderHandle = {
  edit: (reminder: Reminder) => void;
};

export const AddReminder = forwardRef<
  AddReminderHandle,
  {
    onAdd: (input: ReminderInput) => void;
    onUpdate: (id: string, input: ReminderInput) => void;
  }
>(function AddReminder({ onAdd, onUpdate }, ref) {
  const theme = Colors[useColorScheme() ?? 'light'];
  const [visible, setVisible] = useState(false);
  const [editingReminder, setEditingReminder] = useState<Reminder | null>(null);

  useImperativeHandle(ref, () => ({
    edit: (reminder) => {
      setEditingReminder(reminder);
      setVisible(true);
    },
  }));

  const openNew = () => {
    setEditingReminder(null);
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

  return (
    <>
      <Pressable onPress={openNew} hitSlop={8} style={[styles.addButton, { backgroundColor: theme.tint }]}>
        <ThemedText lightColor={Colors.dark.text} darkColor={Colors.light.text} type="defaultSemiBold">
          + Add
        </ThemedText>
      </Pressable>

      <ReminderForm
        visible={visible}
        reminder={editingReminder}
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
