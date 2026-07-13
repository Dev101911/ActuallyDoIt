import { useRef } from 'react';
import { FlatList, StyleSheet, useColorScheme } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { AddReminder, AddReminderHandle } from '@/components/add-reminder';
import { ReminderRow } from '@/components/reminder-row';
import { ThemedText } from '@/components/themed-text';
import { ThemedView } from '@/components/themed-view';
import { Colors } from '@/constants/theme';
import { useReminders } from '@/hooks/use-reminders';

export default function RemindersScreen() {
  const { reminders, addReminder, updateReminder, toggleReminder, deleteReminder } = useReminders();
  const theme = Colors[useColorScheme() ?? 'light'];
  const addReminderRef = useRef<AddReminderHandle>(null);

  return (
    <ThemedView style={styles.container}>
      <SafeAreaView style={styles.safeArea}>
        <ThemedView style={styles.headerRow}>
          <ThemedText type="title" style={styles.title}>
            Reminders
          </ThemedText>
          <AddReminder ref={addReminderRef} onAdd={addReminder} onUpdate={updateReminder} />
        </ThemedView>

        <FlatList
          style={styles.list}
          contentContainerStyle={styles.listContent}
          data={reminders}
          keyExtractor={(item) => item.id}
          ListEmptyComponent={
            <ThemedText
              lightColor={theme.textSecondary}
              darkColor={theme.textSecondary}
              style={styles.emptyText}>
              No reminders yet. Add one above.
            </ThemedText>
          }
          renderItem={({ item }) => (
            <ReminderRow
              reminder={item}
              onToggle={() => toggleReminder(item.id)}
              onPress={() => addReminderRef.current?.edit(item)}
              onDelete={() => deleteReminder(item.id)}
            />
          )}
        />
      </SafeAreaView>
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
  headerRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  title: {
    textAlign: 'left',
  },
  list: {
    flex: 1,
  },
  listContent: {
    gap: 8,
  },
  emptyText: {
    textAlign: 'center',
    marginTop: 24,
  },
});
