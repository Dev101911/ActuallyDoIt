# ADHDoIt

An application to help people with ADHD navigate life — starting with reminders.

Built with [Expo](https://expo.dev) and [Expo Router](https://docs.expo.dev/router/introduction), targeting iOS and Android via [Expo Go](https://expo.dev/go).

## Get started

1. Install dependencies

   ```bash
   npm install
   ```

2. Start the app

   ```bash
   npx expo start
   ```

3. Scan the QR code with the Expo Go app on your phone (or press `i` / `a` in the terminal to open an iOS simulator / Android emulator).

This project uses [file-based routing](https://docs.expo.dev/router/introduction) — screens live in `app`.

## Note on Expo SDK version

This project is pinned to Expo SDK 54 (not the newest SDK) to match what the Expo Go app on the store currently supports for older phone OS versions. If your Expo Go app reports a newer SDK, you can upgrade with `npx expo install expo@latest` followed by `npx expo-doctor`.
