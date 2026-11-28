import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:installm/core/storage/catalog_cache.dart';
import 'package:installm/core/storage/catalog_database.dart';
import 'package:installm/features/model_selection/domain/llm_model.dart';

LlmModel _model(String id, {String parameterSize = '1B'}) => LlmModel(
  id: id,
  name: id,
  parameterSize: parameterSize,
  description: 'cached row',
  capabilities: const [],
  downloadUrl: 'https://huggingface.co/$id/resolve/main/$id-Q4_K_M.gguf',
  promptFormatId: 'chatml',
);

void main() {
  late CatalogDatabase database;
  late CatalogCache cache;

  setUp(() {
    database = CatalogDatabase(NativeDatabase.memory());
    cache = CatalogCache(database);
  });

  tearDown(() => database.close());

  test('reads back nothing before anything is written', () async {
    expect(await cache.read('default'), isNull);
  });

  test('reads a replaced page back in list order', () async {
    await cache.replace(
      'default',
      models: [_model('a'), _model('b')],
      nextCursor: 'cursor-1',
    );

    final hit = await cache.read('default');

    expect(hit, isNotNull);
    expect([for (final model in hit!.models) model.id], ['a', 'b']);
    expect(hit.nextCursor, 'cursor-1');
    expect(
      DateTime.now().difference(hit.fetchedAt),
      lessThan(const Duration(minutes: 1)),
    );
  });

  test('appends a page after the ones already stored', () async {
    await cache.replace('default', models: [_model('a')], nextCursor: 'c1');
    await cache.append('default', models: [_model('b')], nextCursor: 'c2');

    final hit = await cache.read('default');

    expect([for (final model in hit!.models) model.id], ['a', 'b']);
    expect(hit.nextCursor, 'c2');
  });

  test('appending the same model twice does not duplicate the row', () async {
    await cache.replace('default', models: [_model('a')], nextCursor: 'c1');
    await cache.append('default', models: [_model('a')], nextCursor: 'c2');

    final hit = await cache.read('default');

    expect([for (final model in hit!.models) model.id], ['a']);
  });

  test('replacing drops the rows of the page that was there', () async {
    await cache.replace(
      'default',
      models: [_model('a'), _model('b')],
      nextCursor: 'c1',
    );
    await cache.replace('default', models: [_model('c')], nextCursor: null);

    final hit = await cache.read('default');

    expect([for (final model in hit!.models) model.id], ['c']);
    expect(hit.nextCursor, isNull);
    final stored = await database.select(database.catalogModels).get();
    expect([for (final row in stored) row.id], ['c']);
  });

  test('keeps an imported page at the time it was read', () async {
    final fetchedAt = DateTime.now().subtract(const Duration(days: 9));
    await cache.replace(
      'default',
      models: [_model('a')],
      nextCursor: null,
      fetchedAt: fetchedAt,
    );

    final hit = await cache.read('default');

    // SQLite keeps times to the second.
    expect(hit!.fetchedAt.difference(fetchedAt).inSeconds.abs(), lessThan(2));
  });

  test('forget removes the query and its models', () async {
    await cache.replace('default', models: [_model('a')], nextCursor: 'c1');
    await cache.forget('default');

    expect(await cache.read('default'), isNull);
    expect(await database.select(database.catalogModels).get(), isEmpty);
  });

  test('a row that no longer parses is skipped, not fatal', () async {
    await cache.replace(
      'default',
      models: [_model('a'), _model('b')],
      nextCursor: 'c1',
    );
    await (database.update(database.catalogModels)
          ..where((row) => row.id.equals('a')))
        .write(const CatalogModelsCompanion(payload: Value('not json')));

    final hit = await cache.read('default');

    expect([for (final model in hit!.models) model.id], ['b']);
  });
}
