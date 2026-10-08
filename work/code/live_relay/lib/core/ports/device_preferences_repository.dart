/// Local device metadata, independent of vault repositories and platform APIs.
abstract interface class DevicePreferencesRepository {
  Future<Map<String, Object?>?> read();
  Future<void> write(Map<String, Object?> data);
}
