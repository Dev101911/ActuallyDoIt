import { Stack, useLocalSearchParams, useRouter } from 'expo-router';
import { useRef } from 'react';
import { FlatList, Pressable, StyleSheet, useColorScheme } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { ReminderEditor, ReminderEditorHandle } from '@/components/reminder-editor';
import { ReminderRow } from '@/components/reminder-row';
import { ThemedText } from '@/components/themed-text';
import { ThemedView } from '@/components/themed-view';
import { IconSymbol } from '@/components/ui/icon-symbol';
import { Colors } from '@/constants/theme';
import { useReminders } from '@/hooks/use-reminders';
import { getReminderList } from '@/types/reminder-list';

export default function ListDetailScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const list = getReminderList(id ?? '');
  const router = useRouter();
  const { reminders, addReminder, updateReminder, toggleReminder, deleteReminder } = useReminders();
  const theme = Colors[useColorScheme() ?? 'light'];
  const editorRef = useRef<ReminderEditorHandle>(null);

  const items = reminders.filter((r) => r.listId === id);

  return (
    <ThemedView style={styles.container}>
      <Stack.Screen options={{ headerShown: false }} />
      <SafeAreaView style={styles.safeArea}>
        <ThemedView style={styles.headerRow}>
          <Pressable
            onPress={() => router.back()}
            hitSlop={8}
            style={styles.backButton}
            accessibilityRole="button"
            accessibilityLabel="Back">
            <IconSymbol name="chevron.left" size={22} color={theme.text} />
          </Pressable>
          <ThemedText type="title" style={styles.title} numberOfLines={1}>
            {list?.name ?? 'List'}
          </ThemedText>
          {list && <ReminderEditor ref={editorRef} onAdd={addReminder} onUpdate={updateReminder} addButtonListId={list.id} />}
        </ThemedView>

        <FlatList
          style={styles.list}
          contentContainerStyle={styles.listContent}
          data={items}
          keyExtractor={(item) => item.id}
          ListEmptyComponent={
            <ThemedText lightColor={theme.textSecondary} darkColor={theme.textSecondary} style={styles.emptyText}>
              Nothing here yet. Add one above.
            </ThemedText>
          }
          renderItem={({ item }) => (
            <ReminderRow
              reminder={item}
              onToggle={() => toggleReminder(item.id)}
              onPress={() => editorRef.current?.edit(item)}
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
    gap: 12,
  },
  backButton: {
    padding: 4,
    marginLeft: -4,
  },
  title: {
    flex: 1,
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
