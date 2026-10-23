import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pactick/data/local/local_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Directory directory;
  late String databasePath;
  late LocalDatabase store;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('pactick-open-');
    databasePath = '${directory.path}/workspace.db';
    store = LocalDatabase(
      databasePath: databasePath,
      factory: _AndroidExecuteContractFactory(),
    );
  });
  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });

  test(
    'opening and reopening enable secure deletion and foreign keys',
    () async {
      expect(await store.listWorkspaceIds(), [DocumentStore.localAccountId]);
      var db = await databaseFactoryFfi.openDatabase(databasePath);
      expect(await db.rawQuery('PRAGMA secure_delete'), [
        {'secure_delete': 1},
      ]);
      expect(await db.rawQuery('PRAGMA foreign_keys'), [
        {'foreign_keys': 1},
      ]);
      await db.rawQuery('PRAGMA secure_delete = OFF');
      expect(await db.rawQuery('PRAGMA secure_delete'), [
        {'secure_delete': 0},
      ]);
      await store.close();

      expect(await store.listWorkspaceIds(), [DocumentStore.localAccountId]);
      db = await databaseFactoryFfi.openDatabase(databasePath);
      expect(await db.rawQuery('PRAGMA secure_delete'), [
        {'secure_delete': 1},
      ]);
      expect(await db.rawQuery('PRAGMA foreign_keys'), [
        {'foreign_keys': 1},
      ]);
    },
  );

  test(
    'schema 2 upgrades without changing documents, settings or outbox',
    () async {
      await store.putDocument('task', 'upgrade-sentinel', {
        'id': 'upgrade-sentinel',
        'title': '保留升级前的本机任务',
        'status': 'open',
      });
      await store.writeSetting('upgrade-sentinel', '保留升级前的设置');
      var db = await databaseFactoryFfi.openDatabase(databasePath);
      // Version 2 has the same four ordinary tables, without private_vaults.
      await db.execute('DROP TABLE private_vaults');
      await db.setVersion(2);
      const tables = [
        'documents',
        'pending_operations',
        'app_settings',
        'sync_state',
      ];
      final before = <String, List<Map<String, Object?>>>{
        for (final table in tables) table: await db.query(table),
      };
      expect(before['pending_operations'], hasLength(1));
      await store.close();

      expect(await store.readDocuments('task'), hasLength(1));
      db = await databaseFactoryFfi.openDatabase(databasePath);
      expect(await db.getVersion(), 3);
      for (final table in tables) {
        expect(await db.query(table), before[table], reason: table);
      }
      expect(
        await store.readPrivateVault(DocumentStore.localAccountId),
        isNull,
      );
      expect(await db.query('private_vaults'), isEmpty);
      expect(await db.rawQuery('PRAGMA secure_delete'), [
        {'secure_delete': 1},
      ]);
    },
  );
}

/// FFI tolerates result-returning statements in execute, while Android's
/// sqflite driver calls SQLiteDatabase.execSQL, which rejects those statements.
/// Keep real SQLite persistence while enforcing that platform contract.
class _AndroidExecuteContractFactory implements DatabaseFactory {
  @override
  Future<Database> openDatabase(String path, {OpenDatabaseOptions? options}) =>
      databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: options?.version,
          onConfigure: (db) async {
            await options?.onConfigure?.call(
              _AndroidExecuteContractDatabase(db),
            );
          },
          onCreate: options?.onCreate,
          onUpgrade: options?.onUpgrade,
          onDowngrade: options?.onDowngrade,
          onOpen: options?.onOpen,
          readOnly: options?.readOnly,
          singleInstance: options?.singleInstance,
        ),
      );

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError(invocation.memberName.toString());
}

class _AndroidExecuteContractDatabase implements Database {
  _AndroidExecuteContractDatabase(this.database);
  final Database database;

  @override
  Future<void> execute(String sql, [List<Object?>? arguments]) async {
    if (sql.trimLeft().toUpperCase().startsWith('PRAGMA')) {
      final rows = await database.rawQuery(sql, arguments);
      if (rows.isNotEmpty) {
        throw StateError(
          'Queries can be performed using query or rawQuery methods only',
        );
      }
      return;
    }
    await database.execute(sql, arguments);
  }

  @override
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) => database.rawQuery(sql, arguments);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError(invocation.memberName.toString());
}
