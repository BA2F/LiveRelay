import 'dart:typed_data';

class MediumEntry {
  const MediumEntry({required this.name, required this.length});

  final String name;
  final int length;
}

/// A flat, named namespace the device-transfer flow reads and writes through.
/// It deliberately exposes no filesystem paths so a platform adapter (for
/// example Android SAF document trees) can implement it later without the
/// application layer changing.
abstract interface class TransferMedium {
  /// Human-readable identity of the chosen medium, for reports.
  String get label;

  Future<List<MediumEntry>> list();

  /// Reads at most [maxBytes] from the start of a file, for package sniffing.
  Future<Uint8List> readPrefix(String name, int maxBytes);

  /// Reads a whole package. The caller wipes the returned bytes.
  Future<Uint8List> read(String name);

  /// Writes a file through a temporary name so an interrupted write can never
  /// be mistaken for a complete package.
  Future<void> writeAtomic(String name, Uint8List bytes);
}
