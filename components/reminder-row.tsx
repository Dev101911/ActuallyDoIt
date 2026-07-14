import { Pressable, StyleSheet, useColorScheme } from 'react-native';

import { ThemedText } from '@/components/themed-text';
import { ThemedView } from '@/components/themed-view';
import { Colors } from '@/constants/theme';
import { Priority, Reminder } from '@/types/reminder';

const PRIORITY_LABEL: Record<Priority, string> = {
  high: 'High',
  medium: 'Medium',
  low: 'Low',
};

const PRIORITY_COLOR: Record<Priority, string> = {
  high: '#E5484D',
  medium: '#F5A623',
  low: '#30A46C',
};

export function ReminderRow({
  reminder,
  onToggle,
  onPress,
  onDelete,
}: {
  reminder: Reminder;
  onToggle: () => void;
  onPress: () => void;
  onDelete: () => void;
}) {
  const theme = Colors[useColorScheme() ?? 'light'];
  const meta: string[] = [];
  if (reminder.deadline) {
    meta.push(new Date(reminder.deadline).toLocaleString([], { dateStyle: 'medium', timeStyle: 'short' }));
  }
  if (reminder.expectedMinutes != null) meta.push(`${reminder.expectedMinutes} min`);
  if (reminder.alertFrequencyMinutes != null) meta.push(`remind every ${reminder.alertFrequencyMinutes} min`);
  if (reminder.recurrenceIntervalDays != null) meta.push(`repeats every ${reminder.recurrenceIntervalDays}d`);

  return (
    <ThemedView style={[styles.row, { backgroundColor: theme.backgroundElement }]}>
      <Pressable
        onPress={onToggle}
        hitSlop={8}
        accessibilityRole="checkbox"
        accessibilityState={{ checked: reminder.completed }}
        accessibilityLabel={`Mark ${reminder.title} as ${reminder.completed ? 'incomplete' : 'complete'}`}>
        <ThemedView
          style={[
            styles.checkbox,
            { borderColor: theme.textSecondary },
            reminder.completed && { backgroundColor: theme.text, borderColor: theme.text },
          ]}
        />
      </Pressable>
      <Pressable style={styles.rowMain} onPress={onPress}>
        <ThemedView style={styles.titleLine}>
          <ThemedText
            lightColor={reminder.completed ? Colors.light.textSecondary : undefined}
            darkColor={reminder.completed ? Colors.dark.textSecondary : undefined}
            style={reminder.completed && styles.completedText}>
            {reminder.title}
          </ThemedText>
          {reminder.priority && (
            <ThemedView style={styles.priorityBadge}>
              <ThemedView style={[styles.priorityDot, { backgroundColor: PRIORITY_COLOR[reminder.priority] }]} />
              <ThemedText lightColor={theme.textSecondary} darkColor={theme.textSecondary} style={styles.metaText}>
                {PRIORITY_LABEL[reminder.priority]}
              </ThemedText>
            </ThemedView>
          )}
        </ThemedView>
        {reminder.details ? (
          <ThemedText
            lightColor={theme.textSecondary}
            darkColor={theme.textSecondary}
            numberOfLines={1}
            style={styles.detailsText}>
            {reminder.details}
          </ThemedText>
        ) : null}
        {meta.length > 0 && (
          <ThemedText lightColor={theme.textSecondary} darkColor={theme.textSecondary} style={styles.metaText}>
            {meta.join(' · ')}
          </ThemedText>
        )}
      </Pressable>
      <Pressable onPress={onDelete} hitSlop={8}>
        <ThemedText lightColor={theme.textSecondary} darkColor={theme.textSecondary} style={styles.deleteText}>
          Delete
        </ThemedText>
      </Pressable>
    </ThemedView>
  );
}

const styles = StyleSheet.create({
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 16,
    paddingVertical: 16,
    borderRadius: 16,
    gap: 16,
  },
  rowMain: {
    flex: 1,
    gap: 4,
  },
  titleLine: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  priorityBadge: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 4,
  },
  priorityDot: {
    width: 8,
    height: 8,
    borderRadius: 4,
  },
  detailsText: {
    fontSize: 13,
  },
  metaText: {
    fontSize: 12,
  },
  checkbox: {
    width: 20,
    height: 20,
    borderRadius: 6,
    borderWidth: 2,
  },
  completedText: {
    textDecorationLine: 'line-through',
  },
  deleteText: {
    fontSize: 14,
  },
});
