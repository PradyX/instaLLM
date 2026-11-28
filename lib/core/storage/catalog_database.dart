import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'catalog_database.g.dart';

/// One row per catalog the app has read, keyed by the request that produced it.
///
/// The cursor lives here with the page it belongs to, so paging can resume
/// after a restart instead of starting over from the first page.
class CatalogQueries extends Table {
  TextColumn get queryKey => text()();
  TextColumn get nextCursor => text().nullable()();
  DateTimeColumn get fetchedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {queryKey};
}

/// A model as it was read from Hugging Face.
///
/// The payload is the same JSON an installed model round-trips through
/// [LlmModel.toJson], so the row cannot fall behind the model class field by
/// field. `id` and `name` are columns because they are what a person or a
/// future query can search.
class CatalogModels extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get payload => text()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Which models a query holds, in the order the list shows them.
class CatalogPages extends Table {
  TextColumn get queryKey => text()();
  IntColumn get position => integer()();
  TextColumn get modelId => text()();

  @override
  Set<Column> get primaryKey => {queryKey, position};
}

@DriftDatabase(tables: [CatalogQueries, CatalogModels, CatalogPages])
class CatalogDatabase extends _$CatalogDatabase {
  CatalogDatabase(super.e);

  /// The catalog database in the app's own storage.
  ///
  /// Drift opens it on a background isolate, which keeps a page insert off the
  /// frame that renders the list.
  CatalogDatabase.app() : super(driftDatabase(name: 'instalm_catalog'));

  @override
  int get schemaVersion => 1;

  /// Drops every cached catalog. Used when the stored shape cannot be read.
  Future<void> clear() => transaction(() async {
    await delete(catalogPages).go();
    await delete(catalogModels).go();
    await delete(catalogQueries).go();
  });
}
