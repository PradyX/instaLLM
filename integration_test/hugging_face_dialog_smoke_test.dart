import 'package:integration_test/integration_test.dart';

import '../test/model_selection/hugging_face_repository_dialog_test.dart'
    as dialog_tests;

/// Drive Models → Add Model → Hugging Face → Close → reopen in the real
/// macOS Flutter engine, without reading model storage or downloading files.
/// Run with scripts/test_macos.sh integration_test/hugging_face_dialog_smoke_test.dart.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  dialog_tests.registerOpeningLifecycleTest();
}
