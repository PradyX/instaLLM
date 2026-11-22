import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:installm/features/share/domain/shared_text_receiver.dart';

/// The share-sheet receiver, replaceable in tests.
final sharedTextReceiverProvider = Provider<SharedTextReceiver>(
  (ref) => PlatformSharedTextReceiver(),
);
