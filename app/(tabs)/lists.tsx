import { useRouter } from 'expo-router';
import { Pressable, StyleSheet, useColorScheme, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { IconSymbol } from '@/components/ui/icon-symbol';
import { ThemedText } from '@/components/themed-text';
import { ThemedView } from '@/components/themed-view';
import { Colors } from '@/constants/theme';
import { useReminders } from '@/hooks/use-reminders';
import { REMINDER_LISTS } from '@/types/reminder-list';

export default function ListsScreen() {
  const { reminders } = useReminders();
  const theme = Colors[useColorScheme() ?? 'light'];
  const router = useRouter();

  return (
    <ThemedView style={styles.container}>
      <SafeAreaView style={styles.safeArea}>
        <ThemedText type="title" style={styles.title}>
          Lists
        </ThemedText>

        <ThemedView style={styles.cards}>
          {REMINDER_LISTS.map((list) => {
            const openCount = reminders.filter((r) => r.listId === list.id && !r.completed).length;
            return (
              <Pressable
                key={list.id}
                onPress={() => router.push({ pathname: '/list/[id]', params: { id: list.id } })}
                style={[styles.card, { backgroundColor: theme.backgroundElement }]}>
                <IconSymbol name={list.icon} size={28} color={theme.tint} />
                <View style={styles.cardText}>
                  <ThemedText type="defaultSemiBold">{list.name}</ThemedText>
                  <ThemedText lightColor={theme.textSecondary} darkColor={theme.textSecondary}>
                    {openCount} open
                  </ThemedText>
                </View>
                <IconSymbol name="chevron.right" size={20} color={theme.textSecondary} />
              </Pressable>
            );
          })}
        </ThemedView>
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
  title: {
    textAlign: 'left',
  },
  cards: {
    gap: 8,
  },
  card: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 16,
    paddingHorizontal: 16,
    paddingVertical: 16,
    borderRadius: 16,
  },
  cardText: {
    flex: 1,
    gap: 2,
  },
});
