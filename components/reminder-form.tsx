import DateTimePicker, { DateTimePickerEvent } from '@react-native-community/datetimepicker';
import { useEffect, useState } from 'react';
import {
  KeyboardAvoidingView,
  Modal,
  Platform,
  Pressable,
  ScrollView,
  StyleSheet,
  Switch,
  TextInput,
  useColorScheme,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { ThemedText } from '@/components/themed-text';
import { ThemedView } from '@/components/themed-view';
import { Colors } from '@/constants/theme';
import { Priority, Reminder, ReminderInput } from '@/types/reminder';

const PRIORITIES: { label: string; value: Priority }[] = [
  { label: 'Low', value: 'low' },
  { label: 'Medium', value: 'medium' },
  { label: 'High', value: 'high' },
];

function emptyForm(): ReminderInput {
  return {
    title: '',
    details: '',
    expectedMinutes: null,
    deadline: null,
    priority: null,
    alertFrequencyMinutes: null,
  };
}

function fromReminder(reminder: Reminder): ReminderInput {
  return {
    title: reminder.title,
    details: reminder.details ?? '',
    expectedMinutes: reminder.expectedMinutes,
    deadline: reminder.deadline,
    priority: reminder.priority,
    alertFrequencyMinutes: reminder.alertFrequencyMinutes,
  };
}

export function ReminderForm({
  visible,
  reminder,
  onSave,
  onCancel,
}: {
  visible: boolean;
  reminder: Reminder | null;
  onSave: (input: ReminderInput) => void;
  onCancel: () => void;
}) {
  const colorScheme = useColorScheme();
  const theme = Colors[colorScheme ?? 'light'];
  const [form, setForm] = useState<ReminderInput>(emptyForm());
  // Android has no inline "compact" picker, so date/time are picked via separate native dialogs.
  const [pendingDeadlineDate, setPendingDeadlineDate] = useState<Date | null>(null);
  const [androidPickerMode, setAndroidPickerMode] = useState<'date' | 'time' | null>(null);

  useEffect(() => {
    if (visible) {
      setForm(reminder ? fromReminder(reminder) : emptyForm());
      setAndroidPickerMode(null);
      setPendingDeadlineDate(null);
    }
  }, [visible, reminder]);

  const canSave = form.title.trim().length > 0;

  const handleSave = () => {
    if (!canSave) return;
    onSave({
      ...form,
      title: form.title.trim(),
      details: form.details?.trim() ? form.details.trim() : null,
    });
  };

  const hasDeadline = form.deadline != null;

  const toggleDeadline = (value: boolean) => {
    if (value) {
      setForm((f) => ({ ...f, deadline: f.deadline ?? new Date().toISOString() }));
    } else {
      setForm((f) => ({ ...f, deadline: null }));
      setAndroidPickerMode(null);
    }
  };

  const handleIOSChange = (event: DateTimePickerEvent, selected: Date | undefined) => {
    if (selected) setForm((f) => ({ ...f, deadline: selected.toISOString() }));
  };

  const openAndroidPicker = (mode: 'date' | 'time') => {
    setPendingDeadlineDate(form.deadline ? new Date(form.deadline) : new Date());
    setAndroidPickerMode(mode);
  };

  const handleAndroidChange = (event: DateTimePickerEvent, selected: Date | undefined) => {
    const mode = androidPickerMode;
    setAndroidPickerMode(null);
    if (event.type !== 'set' || !selected || !mode) return;
    setForm((f) => {
      const base = f.deadline ? new Date(f.deadline) : new Date();
      if (mode === 'date') {
        base.setFullYear(selected.getFullYear(), selected.getMonth(), selected.getDate());
      } else {
        base.setHours(selected.getHours(), selected.getMinutes(), 0, 0);
      }
      return { ...f, deadline: base.toISOString() };
    });
  };

  return (
    <Modal visible={visible} animationType="slide" presentationStyle="pageSheet" onRequestClose={onCancel}>
      <ThemedView style={styles.container}>
        <SafeAreaView style={styles.safeArea}>
          <ThemedView style={styles.header}>
            <Pressable onPress={onCancel} hitSlop={8}>
              <ThemedText lightColor={theme.textSecondary} darkColor={theme.textSecondary}>
                Cancel
              </ThemedText>
            </Pressable>
            <ThemedText type="defaultSemiBold">{reminder ? 'Edit Reminder' : 'New Reminder'}</ThemedText>
            <Pressable onPress={handleSave} hitSlop={8} disabled={!canSave}>
              <ThemedText
                lightColor={canSave ? theme.tint : theme.textSecondary}
                darkColor={canSave ? theme.tint : theme.textSecondary}
                type="defaultSemiBold">
                Save
              </ThemedText>
            </Pressable>
          </ThemedView>

          <KeyboardAvoidingView
            style={styles.keyboardAvoiding}
            behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
            <ScrollView
              contentContainerStyle={styles.form}
              keyboardShouldPersistTaps="handled"
              keyboardDismissMode="interactive">
              <ThemedView style={styles.field}>
                <ThemedText lightColor={theme.textSecondary} darkColor={theme.textSecondary} style={styles.label}>
                  Title
                </ThemedText>
                <TextInput
                  value={form.title}
                  onChangeText={(title) => setForm((f) => ({ ...f, title }))}
                  placeholder="What needs to get done?"
                  placeholderTextColor={theme.textSecondary}
                  style={[styles.input, { color: theme.text, backgroundColor: theme.backgroundElement }]}
                  autoFocus
                />
              </ThemedView>

              <ThemedView style={styles.field}>
                <ThemedText lightColor={theme.textSecondary} darkColor={theme.textSecondary} style={styles.label}>
                  Details
                </ThemedText>
                <TextInput
                  value={form.details ?? ''}
                  onChangeText={(details) => setForm((f) => ({ ...f, details }))}
                  placeholder="Optional notes"
                  placeholderTextColor={theme.textSecondary}
                  style={[
                    styles.input,
                    styles.multilineInput,
                    { color: theme.text, backgroundColor: theme.backgroundElement },
                  ]}
                  multiline
                />
              </ThemedView>

              <ThemedView style={styles.field}>
                <ThemedText lightColor={theme.textSecondary} darkColor={theme.textSecondary} style={styles.label}>
                  Expected time to complete (minutes)
                </ThemedText>
                <TextInput
                  value={form.expectedMinutes != null ? String(form.expectedMinutes) : ''}
                  onChangeText={(text) =>
                    setForm((f) => ({
                      ...f,
                      expectedMinutes: text.trim() ? Number(text.replace(/[^0-9]/g, '')) : null,
                    }))
                  }
                  placeholder="Optional"
                  placeholderTextColor={theme.textSecondary}
                  keyboardType="number-pad"
                  style={[styles.input, { color: theme.text, backgroundColor: theme.backgroundElement }]}
                />
              </ThemedView>

              <ThemedView style={styles.field}>
                <ThemedView style={styles.toggleRow}>
                  <ThemedText
                    lightColor={theme.textSecondary}
                    darkColor={theme.textSecondary}
                    style={styles.label}>
                    Deadline
                  </ThemedText>
                  <Switch value={hasDeadline} onValueChange={toggleDeadline} trackColor={{ true: theme.tint }} />
                </ThemedView>

                {hasDeadline && form.deadline && Platform.OS === 'ios' && (
                  <DateTimePicker
                    value={new Date(form.deadline)}
                    mode="datetime"
                    display="compact"
                    themeVariant={colorScheme === 'dark' ? 'dark' : 'light'}
                    onChange={handleIOSChange}
                  />
                )}

                {hasDeadline && form.deadline && Platform.OS === 'android' && (
                  <ThemedView style={styles.row}>
                    <Pressable
                      onPress={() => openAndroidPicker('date')}
                      style={[styles.deadlineButton, { backgroundColor: theme.backgroundElement }]}>
                      <ThemedText>
                        {new Date(form.deadline).toLocaleDateString([], { dateStyle: 'medium' })}
                      </ThemedText>
                    </Pressable>
                    <Pressable
                      onPress={() => openAndroidPicker('time')}
                      style={[styles.deadlineButton, { backgroundColor: theme.backgroundElement }]}>
                      <ThemedText>
                        {new Date(form.deadline).toLocaleTimeString([], { timeStyle: 'short' })}
                      </ThemedText>
                    </Pressable>
                  </ThemedView>
                )}

                {Platform.OS === 'android' && androidPickerMode && (
                  <DateTimePicker
                    value={pendingDeadlineDate ?? new Date()}
                    mode={androidPickerMode}
                    onChange={handleAndroidChange}
                  />
                )}
              </ThemedView>

              <ThemedView style={styles.field}>
                <ThemedText lightColor={theme.textSecondary} darkColor={theme.textSecondary} style={styles.label}>
                  Priority
                </ThemedText>
                <ThemedView style={styles.row}>
                  {PRIORITIES.map((p) => {
                    const selected = form.priority === p.value;
                    return (
                      <Pressable
                        key={p.value}
                        onPress={() => setForm((f) => ({ ...f, priority: selected ? null : p.value }))}
                        style={[
                          styles.chip,
                          { backgroundColor: theme.backgroundElement },
                          selected && { backgroundColor: theme.tint },
                        ]}>
                        <ThemedText
                          lightColor={selected ? Colors.dark.text : theme.text}
                          darkColor={selected ? Colors.light.text : theme.text}>
                          {p.label}
                        </ThemedText>
                      </Pressable>
                    );
                  })}
                </ThemedView>
              </ThemedView>

              <ThemedView style={styles.field}>
                <ThemedText lightColor={theme.textSecondary} darkColor={theme.textSecondary} style={styles.label}>
                  Remind me every (minutes)
                </ThemedText>
                <TextInput
                  value={form.alertFrequencyMinutes != null ? String(form.alertFrequencyMinutes) : ''}
                  onChangeText={(text) =>
                    setForm((f) => ({
                      ...f,
                      alertFrequencyMinutes: text.trim() ? Number(text.replace(/[^0-9]/g, '')) : null,
                    }))
                  }
                  placeholder="Optional"
                  placeholderTextColor={theme.textSecondary}
                  keyboardType="number-pad"
                  style={[styles.input, { color: theme.text, backgroundColor: theme.backgroundElement }]}
                />
              </ThemedView>
            </ScrollView>
          </KeyboardAvoidingView>
        </SafeAreaView>
      </ThemedView>
    </Modal>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  safeArea: {
    flex: 1,
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 20,
    paddingVertical: 16,
  },
  keyboardAvoiding: {
    flex: 1,
  },
  form: {
    paddingHorizontal: 20,
    paddingBottom: 40,
    gap: 20,
  },
  field: {
    gap: 8,
  },
  label: {
    fontSize: 13,
    textTransform: 'uppercase',
    letterSpacing: 0.5,
  },
  input: {
    fontSize: 16,
    paddingHorizontal: 16,
    paddingVertical: 12,
    borderRadius: 12,
  },
  multilineInput: {
    minHeight: 80,
    textAlignVertical: 'top',
  },
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
  },
  toggleRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  deadlineButton: {
    paddingHorizontal: 16,
    paddingVertical: 12,
    borderRadius: 12,
  },
  chip: {
    paddingHorizontal: 16,
    paddingVertical: 8,
    borderRadius: 20,
  },
});
