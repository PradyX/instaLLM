import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:installm/features/share/domain/shared_content_receiver.dart';

/// The share-sheet receiver, replaceable in tests.
final sharedContentReceiverProvider = Provider<SharedContentReceiver>(
  (ref) => PlatformSharedContentReceiver(),
);
