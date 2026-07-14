import { useRef } from 'react';
import { ScrollView, StyleSheet, useColorScheme } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { ReminderEditor, ReminderEditorHandle } from '@/components/reminder-editor';
import { ReminderRow } from '@/components/reminder-row';
import { ThemedText } from '@/components/themed-text';
import { ThemedView } from '@/components/themed-view';
import { Colors } from '@/constants/theme';
import { useReminders } from '@/hooks/use-reminders';
import { REMINDER_LISTS } from '@/types/reminder-list';
import { byUrgency, isDueTodayOrOverdue } from '@/utils/reminders';

const MAX_ITEMS_PER_LIST = 5;

export default function TodayScreen() {
  const { reminders, addReminder, updateReminder, toggleReminder, deleteReminder } = useReminders();
  const theme = Colors[useColorScheme() ?? 'light'];
  const editorRef = useRef<ReminderEditorHandle>(null);

  const sections = REMINDER_LISTS.map((list) => ({
    list,
    items: reminders
      .filter((r) => r.listId === list.id && !r.completed && isDueTodayOrOverdue(r))
      .sort(byUrgency)
      .slice(0, MAX_ITEMS_PER_LIST),
  })).filter((section) => section.items.length > 0);

  return (
    <ThemedView style={styles.container}>
      <SafeAreaView style={styles.safeArea}>
        <ThemedText type="title" style={styles.title}>
          Today
        </ThemedText>

        <ScrollView contentContainerStyle={styles.content}>
          {sections.length === 0 ? (
            <ThemedText lightColor={theme.textSecondary} darkColor={theme.textSecondary} style={styles.emptyText}>
              Nothing urgent today.
            </ThemedText>
          ) : (
            sections.map(({ list, items }) => (
              <ThemedView key={list.id} style={styles.section}>
                <ThemedText type="subtitle" style={styles.sectionTitle}>
                  {list.name}
                </ThemedText>
                <ThemedView style={styles.sectionItems}>
                  {items.map((item) => (
                    <ReminderRow
                      key={item.id}
                      reminder={item}
                      onToggle={() => toggleReminder(item.id)}
                      onPress={() => editorRef.current?.edit(item)}
                      onDelete={() => deleteReminder(item.id)}
                    />
                  ))}
                </ThemedView>
              </ThemedView>
            ))
          )}
        </ScrollView>
      </SafeAreaView>

      <ReminderEditor ref={editorRef} onAdd={addReminder} onUpdate={updateReminder} />
    </ThemedView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    alignItems: 'center',
  },
  safeArea: {
    flex: 1,
    width: '100%',
    maxWidth: 800,
    paddingHorizontal: 24,
    paddingTop: 24,
    gap: 16,
  },
  title: {
    textAlign: 'left',
  },
  content: {
    gap: 24,
    paddingBottom: 24,
  },
  section: {
    gap: 8,
  },
  sectionTitle: {
    fontSize: 16,
  },
  sectionItems: {
    gap: 8,
  },
  emptyText: {
    textAlign: 'center',
    marginTop: 24,
  },
});
