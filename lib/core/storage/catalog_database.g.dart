// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'catalog_database.dart';

// ignore_for_file: type=lint
class $CatalogQueriesTable extends CatalogQueries
    with TableInfo<$CatalogQueriesTable, CatalogQuery> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CatalogQueriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _queryKeyMeta = const VerificationMeta(
    'queryKey',
  );
  @override
  late final GeneratedColumn<String> queryKey = GeneratedColumn<String>(
    'query_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nextCursorMeta = const VerificationMeta(
    'nextCursor',
  );
  @override
  late final GeneratedColumn<String> nextCursor = GeneratedColumn<String>(
    'next_cursor',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _fetchedAtMeta = const VerificationMeta(
    'fetchedAt',
  );
  @override
  late final GeneratedColumn<DateTime> fetchedAt = GeneratedColumn<DateTime>(
    'fetched_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [queryKey, nextCursor, fetchedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'catalog_queries';
  @override
  VerificationContext validateIntegrity(
    Insertable<CatalogQuery> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('query_key')) {
      context.handle(
        _queryKeyMeta,
        queryKey.isAcceptableOrUnknown(data['query_key']!, _queryKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_queryKeyMeta);
    }
    if (data.containsKey('next_cursor')) {
      context.handle(
        _nextCursorMeta,
        nextCursor.isAcceptableOrUnknown(data['next_cursor']!, _nextCursorMeta),
      );
    }
    if (data.containsKey('fetched_at')) {
      context.handle(
        _fetchedAtMeta,
        fetchedAt.isAcceptableOrUnknown(data['fetched_at']!, _fetchedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_fetchedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {queryKey};
  @override
  CatalogQuery map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CatalogQuery(
      queryKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}query_key'],
      )!,
      nextCursor: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}next_cursor'],
      ),
      fetchedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}fetched_at'],
      )!,
    );
  }

  @override
  $CatalogQueriesTable createAlias(String alias) {
    return $CatalogQueriesTable(attachedDatabase, alias);
  }
}

class CatalogQuery extends DataClass implements Insertable<CatalogQuery> {
  final String queryKey;
  final String? nextCursor;
  final DateTime fetchedAt;
  const CatalogQuery({
    required this.queryKey,
    this.nextCursor,
    required this.fetchedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['query_key'] = Variable<String>(queryKey);
    if (!nullToAbsent || nextCursor != null) {
      map['next_cursor'] = Variable<String>(nextCursor);
    }
    map['fetched_at'] = Variable<DateTime>(fetchedAt);
    return map;
  }

  CatalogQueriesCompanion toCompanion(bool nullToAbsent) {
    return CatalogQueriesCompanion(
      queryKey: Value(queryKey),
      nextCursor: nextCursor == null && nullToAbsent
          ? const Value.absent()
          : Value(nextCursor),
      fetchedAt: Value(fetchedAt),
    );
  }

  factory CatalogQuery.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CatalogQuery(
      queryKey: serializer.fromJson<String>(json['queryKey']),
      nextCursor: serializer.fromJson<String?>(json['nextCursor']),
      fetchedAt: serializer.fromJson<DateTime>(json['fetchedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'queryKey': serializer.toJson<String>(queryKey),
      'nextCursor': serializer.toJson<String?>(nextCursor),
      'fetchedAt': serializer.toJson<DateTime>(fetchedAt),
    };
  }

  CatalogQuery copyWith({
    String? queryKey,
    Value<String?> nextCursor = const Value.absent(),
    DateTime? fetchedAt,
  }) => CatalogQuery(
    queryKey: queryKey ?? this.queryKey,
    nextCursor: nextCursor.present ? nextCursor.value : this.nextCursor,
    fetchedAt: fetchedAt ?? this.fetchedAt,
  );
  CatalogQuery copyWithCompanion(CatalogQueriesCompanion data) {
    return CatalogQuery(
      queryKey: data.queryKey.present ? data.queryKey.value : this.queryKey,
      nextCursor: data.nextCursor.present
          ? data.nextCursor.value
          : this.nextCursor,
      fetchedAt: data.fetchedAt.present ? data.fetchedAt.value : this.fetchedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CatalogQuery(')
          ..write('queryKey: $queryKey, ')
          ..write('nextCursor: $nextCursor, ')
          ..write('fetchedAt: $fetchedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(queryKey, nextCursor, fetchedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CatalogQuery &&
          other.queryKey == this.queryKey &&
          other.nextCursor == this.nextCursor &&
          other.fetchedAt == this.fetchedAt);
}

class CatalogQueriesCompanion extends UpdateCompanion<CatalogQuery> {
  final Value<String> queryKey;
  final Value<String?> nextCursor;
  final Value<DateTime> fetchedAt;
  final Value<int> rowid;
  const CatalogQueriesCompanion({
    this.queryKey = const Value.absent(),
    this.nextCursor = const Value.absent(),
    this.fetchedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CatalogQueriesCompanion.insert({
    required String queryKey,
    this.nextCursor = const Value.absent(),
    required DateTime fetchedAt,
    this.rowid = const Value.absent(),
  }) : queryKey = Value(queryKey),
       fetchedAt = Value(fetchedAt);
  static Insertable<CatalogQuery> custom({
    Expression<String>? queryKey,
    Expression<String>? nextCursor,
    Expression<DateTime>? fetchedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (queryKey != null) 'query_key': queryKey,
      if (nextCursor != null) 'next_cursor': nextCursor,
      if (fetchedAt != null) 'fetched_at': fetchedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CatalogQueriesCompanion copyWith({
    Value<String>? queryKey,
    Value<String?>? nextCursor,
    Value<DateTime>? fetchedAt,
    Value<int>? rowid,
  }) {
    return CatalogQueriesCompanion(
      queryKey: queryKey ?? this.queryKey,
      nextCursor: nextCursor ?? this.nextCursor,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (queryKey.present) {
      map['query_key'] = Variable<String>(queryKey.value);
    }
    if (nextCursor.present) {
      map['next_cursor'] = Variable<String>(nextCursor.value);
    }
    if (fetchedAt.present) {
      map['fetched_at'] = Variable<DateTime>(fetchedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CatalogQueriesCompanion(')
          ..write('queryKey: $queryKey, ')
          ..write('nextCursor: $nextCursor, ')
          ..write('fetchedAt: $fetchedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CatalogModelsTable extends CatalogModels
    with TableInfo<$CatalogModelsTable, CatalogModel> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CatalogModelsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, name, payload];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'catalog_models';
  @override
  VerificationContext validateIntegrity(
    Insertable<CatalogModel> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CatalogModel map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CatalogModel(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
    );
  }

  @override
  $CatalogModelsTable createAlias(String alias) {
    return $CatalogModelsTable(attachedDatabase, alias);
  }
}

class CatalogModel extends DataClass implements Insertable<CatalogModel> {
  final String id;
  final String name;
  final String payload;
  const CatalogModel({
    required this.id,
    required this.name,
    required this.payload,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['payload'] = Variable<String>(payload);
    return map;
  }

  CatalogModelsCompanion toCompanion(bool nullToAbsent) {
    return CatalogModelsCompanion(
      id: Value(id),
      name: Value(name),
      payload: Value(payload),
    );
  }

  factory CatalogModel.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CatalogModel(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      payload: serializer.fromJson<String>(json['payload']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'payload': serializer.toJson<String>(payload),
    };
  }

  CatalogModel copyWith({String? id, String? name, String? payload}) =>
      CatalogModel(
        id: id ?? this.id,
        name: name ?? this.name,
        payload: payload ?? this.payload,
      );
  CatalogModel copyWithCompanion(CatalogModelsCompanion data) {
    return CatalogModel(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      payload: data.payload.present ? data.payload.value : this.payload,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CatalogModel(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('payload: $payload')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, payload);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CatalogModel &&
          other.id == this.id &&
          other.name == this.name &&
          other.payload == this.payload);
}

class CatalogModelsCompanion extends UpdateCompanion<CatalogModel> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> payload;
  final Value<int> rowid;
  const CatalogModelsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.payload = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CatalogModelsCompanion.insert({
    required String id,
    required String name,
    required String payload,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       payload = Value(payload);
  static Insertable<CatalogModel> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? payload,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (payload != null) 'payload': payload,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CatalogModelsCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? payload,
    Value<int>? rowid,
  }) {
    return CatalogModelsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      payload: payload ?? this.payload,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CatalogModelsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('payload: $payload, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CatalogPagesTable extends CatalogPages
    with TableInfo<$CatalogPagesTable, CatalogPage> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CatalogPagesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _queryKeyMeta = const VerificationMeta(
    'queryKey',
  );
  @override
  late final GeneratedColumn<String> queryKey = GeneratedColumn<String>(
    'query_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _modelIdMeta = const VerificationMeta(
    'modelId',
  );
  @override
  late final GeneratedColumn<String> modelId = GeneratedColumn<String>(
    'model_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [queryKey, position, modelId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'catalog_pages';
  @override
  VerificationContext validateIntegrity(
    Insertable<CatalogPage> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('query_key')) {
      context.handle(
        _queryKeyMeta,
        queryKey.isAcceptableOrUnknown(data['query_key']!, _queryKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_queryKeyMeta);
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    } else if (isInserting) {
      context.missing(_positionMeta);
    }
    if (data.containsKey('model_id')) {
      context.handle(
        _modelIdMeta,
        modelId.isAcceptableOrUnknown(data['model_id']!, _modelIdMeta),
      );
    } else if (isInserting) {
      context.missing(_modelIdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {queryKey, position};
  @override
  CatalogPage map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CatalogPage(
      queryKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}query_key'],
      )!,
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
      modelId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}model_id'],
      )!,
    );
  }

  @override
  $CatalogPagesTable createAlias(String alias) {
    return $CatalogPagesTable(attachedDatabase, alias);
  }
}

class CatalogPage extends DataClass implements Insertable<CatalogPage> {
  final String queryKey;
  final int position;
  final String modelId;
  const CatalogPage({
    required this.queryKey,
    required this.position,
    required this.modelId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['query_key'] = Variable<String>(queryKey);
    map['position'] = Variable<int>(position);
    map['model_id'] = Variable<String>(modelId);
    return map;
  }

  CatalogPagesCompanion toCompanion(bool nullToAbsent) {
    return CatalogPagesCompanion(
      queryKey: Value(queryKey),
      position: Value(position),
      modelId: Value(modelId),
    );
  }

  factory CatalogPage.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CatalogPage(
      queryKey: serializer.fromJson<String>(json['queryKey']),
      position: serializer.fromJson<int>(json['position']),
      modelId: serializer.fromJson<String>(json['modelId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'queryKey': serializer.toJson<String>(queryKey),
      'position': serializer.toJson<int>(position),
      'modelId': serializer.toJson<String>(modelId),
    };
  }

  CatalogPage copyWith({String? queryKey, int? position, String? modelId}) =>
      CatalogPage(
        queryKey: queryKey ?? this.queryKey,
        position: position ?? this.position,
        modelId: modelId ?? this.modelId,
      );
  CatalogPage copyWithCompanion(CatalogPagesCompanion data) {
    return CatalogPage(
      queryKey: data.queryKey.present ? data.queryKey.value : this.queryKey,
      position: data.position.present ? data.position.value : this.position,
      modelId: data.modelId.present ? data.modelId.value : this.modelId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CatalogPage(')
          ..write('queryKey: $queryKey, ')
          ..write('position: $position, ')
          ..write('modelId: $modelId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(queryKey, position, modelId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CatalogPage &&
          other.queryKey == this.queryKey &&
          other.position == this.position &&
          other.modelId == this.modelId);
}

class CatalogPagesCompanion extends UpdateCompanion<CatalogPage> {
  final Value<String> queryKey;
  final Value<int> position;
  final Value<String> modelId;
  final Value<int> rowid;
  const CatalogPagesCompanion({
    this.queryKey = const Value.absent(),
    this.position = const Value.absent(),
    this.modelId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CatalogPagesCompanion.insert({
    required String queryKey,
    required int position,
    required String modelId,
    this.rowid = const Value.absent(),
  }) : queryKey = Value(queryKey),
       position = Value(position),
       modelId = Value(modelId);
  static Insertable<CatalogPage> custom({
    Expression<String>? queryKey,
    Expression<int>? position,
    Expression<String>? modelId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (queryKey != null) 'query_key': queryKey,
      if (position != null) 'position': position,
      if (modelId != null) 'model_id': modelId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CatalogPagesCompanion copyWith({
    Value<String>? queryKey,
    Value<int>? position,
    Value<String>? modelId,
    Value<int>? rowid,
  }) {
    return CatalogPagesCompanion(
      queryKey: queryKey ?? this.queryKey,
      position: position ?? this.position,
      modelId: modelId ?? this.modelId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (queryKey.present) {
      map['query_key'] = Variable<String>(queryKey.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (modelId.present) {
      map['model_id'] = Variable<String>(modelId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CatalogPagesCompanion(')
          ..write('queryKey: $queryKey, ')
          ..write('position: $position, ')
          ..write('modelId: $modelId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$CatalogDatabase extends GeneratedDatabase {
  _$CatalogDatabase(QueryExecutor e) : super(e);
  $CatalogDatabaseManager get managers => $CatalogDatabaseManager(this);
  late final $CatalogQueriesTable catalogQueries = $CatalogQueriesTable(this);
  late final $CatalogModelsTable catalogModels = $CatalogModelsTable(this);
  late final $CatalogPagesTable catalogPages = $CatalogPagesTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    catalogQueries,
    catalogModels,
    catalogPages,
  ];
}

typedef $$CatalogQueriesTableCreateCompanionBuilder =
    CatalogQueriesCompanion Function({
      required String queryKey,
      Value<String?> nextCursor,
      required DateTime fetchedAt,
      Value<int> rowid,
    });
typedef $$CatalogQueriesTableUpdateCompanionBuilder =
    CatalogQueriesCompanion Function({
      Value<String> queryKey,
      Value<String?> nextCursor,
      Value<DateTime> fetchedAt,
      Value<int> rowid,
    });

class $$CatalogQueriesTableFilterComposer
    extends Composer<_$CatalogDatabase, $CatalogQueriesTable> {
  $$CatalogQueriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get queryKey => $composableBuilder(
    column: $table.queryKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nextCursor => $composableBuilder(
    column: $table.nextCursor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get fetchedAt => $composableBuilder(
    column: $table.fetchedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CatalogQueriesTableOrderingComposer
    extends Composer<_$CatalogDatabase, $CatalogQueriesTable> {
  $$CatalogQueriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get queryKey => $composableBuilder(
    column: $table.queryKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nextCursor => $composableBuilder(
    column: $table.nextCursor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get fetchedAt => $composableBuilder(
    column: $table.fetchedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CatalogQueriesTableAnnotationComposer
    extends Composer<_$CatalogDatabase, $CatalogQueriesTable> {
  $$CatalogQueriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get queryKey =>
      $composableBuilder(column: $table.queryKey, builder: (column) => column);

  GeneratedColumn<String> get nextCursor => $composableBuilder(
    column: $table.nextCursor,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get fetchedAt =>
      $composableBuilder(column: $table.fetchedAt, builder: (column) => column);
}

class $$CatalogQueriesTableTableManager
    extends
        RootTableManager<
          _$CatalogDatabase,
          $CatalogQueriesTable,
          CatalogQuery,
          $$CatalogQueriesTableFilterComposer,
          $$CatalogQueriesTableOrderingComposer,
          $$CatalogQueriesTableAnnotationComposer,
          $$CatalogQueriesTableCreateCompanionBuilder,
          $$CatalogQueriesTableUpdateCompanionBuilder,
          (
            CatalogQuery,
            BaseReferences<
              _$CatalogDatabase,
              $CatalogQueriesTable,
              CatalogQuery
            >,
          ),
          CatalogQuery,
          PrefetchHooks Function()
        > {
  $$CatalogQueriesTableTableManager(
    _$CatalogDatabase db,
    $CatalogQueriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CatalogQueriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CatalogQueriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CatalogQueriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> queryKey = const Value.absent(),
                Value<String?> nextCursor = const Value.absent(),
                Value<DateTime> fetchedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CatalogQueriesCompanion(
                queryKey: queryKey,
                nextCursor: nextCursor,
                fetchedAt: fetchedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String queryKey,
                Value<String?> nextCursor = const Value.absent(),
                required DateTime fetchedAt,
                Value<int> rowid = const Value.absent(),
              }) => CatalogQueriesCompanion.insert(
                queryKey: queryKey,
                nextCursor: nextCursor,
                fetchedAt: fetchedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CatalogQueriesTable, CatalogQuery>(table),
                  BaseReferences<
                    _$CatalogDatabase,
                    $CatalogQueriesTable,
                    CatalogQuery
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CatalogQueriesTableProcessedTableManager =
    ProcessedTableManager<
      _$CatalogDatabase,
      $CatalogQueriesTable,
      CatalogQuery,
      $$CatalogQueriesTableFilterComposer,
      $$CatalogQueriesTableOrderingComposer,
      $$CatalogQueriesTableAnnotationComposer,
      $$CatalogQueriesTableCreateCompanionBuilder,
      $$CatalogQueriesTableUpdateCompanionBuilder,
      (
        CatalogQuery,
        BaseReferences<_$CatalogDatabase, $CatalogQueriesTable, CatalogQuery>,
      ),
      CatalogQuery,
      PrefetchHooks Function()
    >;
typedef $$CatalogModelsTableCreateCompanionBuilder =
    CatalogModelsCompanion Function({
      required String id,
      required String name,
      required String payload,
      Value<int> rowid,
    });
typedef $$CatalogModelsTableUpdateCompanionBuilder =
    CatalogModelsCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String> payload,
      Value<int> rowid,
    });

class $$CatalogModelsTableFilterComposer
    extends Composer<_$CatalogDatabase, $CatalogModelsTable> {
  $$CatalogModelsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CatalogModelsTableOrderingComposer
    extends Composer<_$CatalogDatabase, $CatalogModelsTable> {
  $$CatalogModelsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CatalogModelsTableAnnotationComposer
    extends Composer<_$CatalogDatabase, $CatalogModelsTable> {
  $$CatalogModelsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);
}

class $$CatalogModelsTableTableManager
    extends
        RootTableManager<
          _$CatalogDatabase,
          $CatalogModelsTable,
          CatalogModel,
          $$CatalogModelsTableFilterComposer,
          $$CatalogModelsTableOrderingComposer,
          $$CatalogModelsTableAnnotationComposer,
          $$CatalogModelsTableCreateCompanionBuilder,
          $$CatalogModelsTableUpdateCompanionBuilder,
          (
            CatalogModel,
            BaseReferences<
              _$CatalogDatabase,
              $CatalogModelsTable,
              CatalogModel
            >,
          ),
          CatalogModel,
          PrefetchHooks Function()
        > {
  $$CatalogModelsTableTableManager(
    _$CatalogDatabase db,
    $CatalogModelsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CatalogModelsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CatalogModelsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CatalogModelsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CatalogModelsCompanion(
                id: id,
                name: name,
                payload: payload,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required String payload,
                Value<int> rowid = const Value.absent(),
              }) => CatalogModelsCompanion.insert(
                id: id,
                name: name,
                payload: payload,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CatalogModelsTable, CatalogModel>(table),
                  BaseReferences<
                    _$CatalogDatabase,
                    $CatalogModelsTable,
                    CatalogModel
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CatalogModelsTableProcessedTableManager =
    ProcessedTableManager<
      _$CatalogDatabase,
      $CatalogModelsTable,
      CatalogModel,
      $$CatalogModelsTableFilterComposer,
      $$CatalogModelsTableOrderingComposer,
      $$CatalogModelsTableAnnotationComposer,
      $$CatalogModelsTableCreateCompanionBuilder,
      $$CatalogModelsTableUpdateCompanionBuilder,
      (
        CatalogModel,
        BaseReferences<_$CatalogDatabase, $CatalogModelsTable, CatalogModel>,
      ),
      CatalogModel,
      PrefetchHooks Function()
    >;
typedef $$CatalogPagesTableCreateCompanionBuilder =
    CatalogPagesCompanion Function({
      required String queryKey,
      required int position,
      required String modelId,
      Value<int> rowid,
    });
typedef $$CatalogPagesTableUpdateCompanionBuilder =
    CatalogPagesCompanion Function({
      Value<String> queryKey,
      Value<int> position,
      Value<String> modelId,
      Value<int> rowid,
    });

class $$CatalogPagesTableFilterComposer
    extends Composer<_$CatalogDatabase, $CatalogPagesTable> {
  $$CatalogPagesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get queryKey => $composableBuilder(
    column: $table.queryKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get modelId => $composableBuilder(
    column: $table.modelId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CatalogPagesTableOrderingComposer
    extends Composer<_$CatalogDatabase, $CatalogPagesTable> {
  $$CatalogPagesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get queryKey => $composableBuilder(
    column: $table.queryKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get modelId => $composableBuilder(
    column: $table.modelId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CatalogPagesTableAnnotationComposer
    extends Composer<_$CatalogDatabase, $CatalogPagesTable> {
  $$CatalogPagesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get queryKey =>
      $composableBuilder(column: $table.queryKey, builder: (column) => column);

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  GeneratedColumn<String> get modelId =>
      $composableBuilder(column: $table.modelId, builder: (column) => column);
}

class $$CatalogPagesTableTableManager
    extends
        RootTableManager<
          _$CatalogDatabase,
          $CatalogPagesTable,
          CatalogPage,
          $$CatalogPagesTableFilterComposer,
          $$CatalogPagesTableOrderingComposer,
          $$CatalogPagesTableAnnotationComposer,
          $$CatalogPagesTableCreateCompanionBuilder,
          $$CatalogPagesTableUpdateCompanionBuilder,
          (
            CatalogPage,
            BaseReferences<_$CatalogDatabase, $CatalogPagesTable, CatalogPage>,
          ),
          CatalogPage,
          PrefetchHooks Function()
        > {
  $$CatalogPagesTableTableManager(
    _$CatalogDatabase db,
    $CatalogPagesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CatalogPagesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CatalogPagesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CatalogPagesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> queryKey = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<String> modelId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CatalogPagesCompanion(
                queryKey: queryKey,
                position: position,
                modelId: modelId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String queryKey,
                required int position,
                required String modelId,
                Value<int> rowid = const Value.absent(),
              }) => CatalogPagesCompanion.insert(
                queryKey: queryKey,
                position: position,
                modelId: modelId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CatalogPagesTable, CatalogPage>(table),
                  BaseReferences<
                    _$CatalogDatabase,
                    $CatalogPagesTable,
                    CatalogPage
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CatalogPagesTableProcessedTableManager =
    ProcessedTableManager<
      _$CatalogDatabase,
      $CatalogPagesTable,
      CatalogPage,
      $$CatalogPagesTableFilterComposer,
      $$CatalogPagesTableOrderingComposer,
      $$CatalogPagesTableAnnotationComposer,
      $$CatalogPagesTableCreateCompanionBuilder,
      $$CatalogPagesTableUpdateCompanionBuilder,
      (
        CatalogPage,
        BaseReferences<_$CatalogDatabase, $CatalogPagesTable, CatalogPage>,
      ),
      CatalogPage,
      PrefetchHooks Function()
    >;

class $CatalogDatabaseManager {
  final _$CatalogDatabase _db;
  $CatalogDatabaseManager(this._db);
  $$CatalogQueriesTableTableManager get catalogQueries =>
      $$CatalogQueriesTableTableManager(_db, _db.catalogQueries);
  $$CatalogModelsTableTableManager get catalogModels =>
      $$CatalogModelsTableTableManager(_db, _db.catalogModels);
  $$CatalogPagesTableTableManager get catalogPages =>
      $$CatalogPagesTableTableManager(_db, _db.catalogPages);
}
