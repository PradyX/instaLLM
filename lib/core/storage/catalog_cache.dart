import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:installm/core/storage/catalog_database.dart';
import 'package:installm/features/model_selection/domain/llm_model.dart';

/// A cached catalog: the models, the cursor that continues it, and when it was
/// read.
class CachedCatalog {
  const CachedCatalog({
    required this.models,
    required this.nextCursor,
    required this.fetchedAt,
  });

  final List<LlmModel> models;
  final String? nextCursor;
  final DateTime fetchedAt;
}

/// Stores the model catalog in SQLite through drift.
///
/// Replaces the single encrypted JSON blob this used to keep: a page append is
/// now a few inserts instead of rewriting every page, the order is a column
/// rather than list position, and a corrupt or outdated schema can be dropped
/// without touching user data.
class CatalogCache {
  CatalogCache(this._db);

  final CatalogDatabase _db;

  /// The models a query holds, in list order, or null when nothing is cached.
  Future<CachedCatalog?> read(String queryKey) async {
    final query = await (_db.select(
      _db.catalogQueries,
    )..where((row) => row.queryKey.equals(queryKey))).getSingleOrNull();
    if (query == null) return null;

    final pages =
        await (_db.select(_db.catalogPages)
              ..where((row) => row.queryKey.equals(queryKey))
              ..orderBy([(row) => OrderingTerm.asc(row.position)]))
            .get();
    if (pages.isEmpty) return null;

    final ids = [for (final page in pages) page.modelId];
    final stored = await (_db.select(
      _db.catalogModels,
    )..where((row) => row.id.isIn(ids))).get();
    final byId = {for (final model in stored) model.id: model.payload};

    final models = <LlmModel>[];
    for (final id in ids) {
      final payload = byId[id];
      if (payload == null) continue;
      try {
        final decoded = jsonDecode(payload);
        if (decoded is Map<String, dynamic>) {
          models.add(LlmModel.fromJson(decoded));
        }
      } catch (_) {
        // A row that no longer parses is skipped rather than failing the list.
      }
    }
    if (models.isEmpty) return null;

    return CachedCatalog(
      models: models,
      nextCursor: query.nextCursor,
      fetchedAt: query.fetchedAt,
    );
  }

  /// Replaces everything cached for [queryKey] with [models].
  /// [fetchedAt] is when the page was read from the network. It defaults to now
  /// and is set explicitly when an older cache is imported, so an import does
  /// not look like a fresh read.
  Future<void> replace(
    String queryKey, {
    required List<LlmModel> models,
    required String? nextCursor,
    DateTime? fetchedAt,
  }) async {
    final unique = _uniqueById(models);
    await _db.transaction(() async {
      await _deletePages(queryKey);
      await _insertModels(unique);
      await _writePages(queryKey, unique, startAt: 0);
      await _writeQuery(queryKey, nextCursor, fetchedAt: fetchedAt);
      await _dropOrphanModels();
    });
  }

  /// Adds [models] after the ones already cached for [queryKey].
  Future<void> append(
    String queryKey, {
    required List<LlmModel> models,
    required String? nextCursor,
  }) async {
    await _db.transaction(() async {
      final existing = await (_db.select(
        _db.catalogPages,
      )..where((row) => row.queryKey.equals(queryKey))).get();
      // A page overlaps the one before it when a repository appears in both
      // pipelines, so a model already listed here is not listed twice.
      final listed = {for (final page in existing) page.modelId};
      final fresh = [
        for (final model in _uniqueById(models))
          if (listed.add(model.id)) model,
      ];
      var position = 0;
      for (final page in existing) {
        if (page.position >= position) position = page.position + 1;
      }
      await _insertModels(fresh);
      await _writePages(queryKey, fresh, startAt: position);
      await _writeQuery(queryKey, nextCursor);
      await _dropOrphanModels();
    });
  }

  List<LlmModel> _uniqueById(List<LlmModel> models) {
    final byId = <String, LlmModel>{};
    for (final model in models) {
      byId[model.id] = model;
    }
    return byId.values.toList(growable: false);
  }

  /// Forgets [queryKey] and any model no other query still points at.
  Future<void> forget(String queryKey) async {
    await _db.transaction(() async {
      await _deletePages(queryKey);
      await (_db.delete(
        _db.catalogQueries,
      )..where((row) => row.queryKey.equals(queryKey))).go();
      await _dropOrphanModels();
    });
  }

  Future<void> _deletePages(String queryKey) => (_db.delete(
    _db.catalogPages,
  )..where((row) => row.queryKey.equals(queryKey))).go();

  Future<void> _insertModels(List<LlmModel> models) async {
    for (final model in models) {
      await _db
          .into(_db.catalogModels)
          .insert(
            CatalogModelsCompanion.insert(
              id: model.id,
              name: model.name,
              payload: jsonEncode(model.toJson()),
            ),
            onConflict: DoUpdate(
              (old) => CatalogModelsCompanion(
                name: Value(model.name),
                payload: Value(jsonEncode(model.toJson())),
              ),
            ),
          );
    }
  }

  Future<void> _writePages(
    String queryKey,
    List<LlmModel> models, {
    required int startAt,
  }) async {
    var position = startAt;
    for (final model in models) {
      await _db
          .into(_db.catalogPages)
          .insertOnConflictUpdate(
            CatalogPagesCompanion.insert(
              queryKey: queryKey,
              position: position,
              modelId: model.id,
            ),
          );
      position++;
    }
  }

  Future<void> _writeQuery(
    String queryKey,
    String? nextCursor, {
    DateTime? fetchedAt,
  }) async {
    await _db
        .into(_db.catalogQueries)
        .insertOnConflictUpdate(
          CatalogQueriesCompanion.insert(
            queryKey: queryKey,
            nextCursor: Value(nextCursor),
            fetchedAt: fetchedAt ?? DateTime.now(),
          ),
        );
  }

  /// Removes models no cached query points at any more, so a replaced page does
  /// not leave its old rows behind.
  Future<void> _dropOrphanModels() async {
    final referenced = await _db.select(_db.catalogPages).get();
    final keep = {for (final page in referenced) page.modelId};
    final stored = await _db.select(_db.catalogModels).get();
    final orphans = [
      for (final model in stored)
        if (!keep.contains(model.id)) model.id,
    ];
    if (orphans.isEmpty) return;
    await (_db.delete(
      _db.catalogModels,
    )..where((row) => row.id.isIn(orphans))).go();
  }
}
