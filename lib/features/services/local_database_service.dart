import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class LocalDatabaseService {
  static final LocalDatabaseService _instance =
      LocalDatabaseService._internal();
  factory LocalDatabaseService() => _instance;
  LocalDatabaseService._internal();

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'speed_data_telemetry.db');

    return await openDatabase(
      path,
      version: 3,
      onCreate: (db, version) async {
        await _createTelemetryTable(db);
        await _createLapClosuresTable(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('ALTER TABLE telemetry ADD COLUMN eventId TEXT');
          await db.execute('ALTER TABLE telemetry ADD COLUMN session TEXT');
          await db.execute('ALTER TABLE telemetry ADD COLUMN altitude REAL');
          await db.execute('''
            CREATE INDEX IF NOT EXISTS idx_telemetry_sync
            ON telemetry (synced, raceId, uid, session, timestamp)
          ''');
        }
        if (oldVersion < 3) {
          await _createLapClosuresTable(db);
        }
      },
    );
  }

  Future<void> _createTelemetryTable(Database db) async {
    await db.execute('''
      CREATE TABLE telemetry (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        raceId TEXT,
        eventId TEXT,
        uid TEXT,
        session TEXT,
        lat REAL,
        lng REAL,
        speed REAL,
        heading REAL,
        altitude REAL,
        timestamp INTEGER,
        synced INTEGER DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_telemetry_sync
      ON telemetry (synced, raceId, uid, session, timestamp)
    ''');
  }

  Future<void> _createLapClosuresTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS local_lap_closures (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        raceId TEXT,
        eventId TEXT,
        uid TEXT,
        session TEXT,
        closureId TEXT,
        payloadJson TEXT,
        sfCrossedAtMs INTEGER,
        capturedAtMs INTEGER,
        synced INTEGER DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_local_lap_closure_unique
      ON local_lap_closures (closureId)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_local_lap_closure_sync
      ON local_lap_closures (synced, raceId, uid, session, sfCrossedAtMs, id)
    ''');
  }

  Future<int> insertPoint(Map<String, dynamic> point) async {
    final db = await database;
    return await db.insert('telemetry', point);
  }

  Future<List<Map<String, dynamic>>> getUnsyncedPoints({
    required String raceId,
    required String uid,
    String? sessionId,
    int limit = 500,
  }) async {
    final db = await database;
    final whereParts = <String>[
      'raceId = ?',
      'uid = ?',
      'synced = 0',
    ];
    final whereArgs = <Object?>[raceId, uid];
    if (sessionId != null && sessionId.isNotEmpty) {
      whereParts.add('session = ?');
      whereArgs.add(sessionId);
    }
    return await db.query(
      'telemetry',
      where: whereParts.join(' AND '),
      whereArgs: whereArgs,
      orderBy: 'timestamp ASC, id ASC',
      limit: limit,
    );
  }

  Future<void> markAsSynced(List<int> ids) async {
    if (ids.isEmpty) return;
    final db = await database;
    await db.update(
      'telemetry',
      {'synced': 1},
      where: 'id IN (${ids.join(',')})',
    );
  }

  Future<int> insertLapClosure(Map<String, dynamic> lapClosure) async {
    final db = await database;
    return await db.insert(
      'local_lap_closures',
      lapClosure,
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<List<Map<String, dynamic>>> getUnsyncedLapClosures({
    required String raceId,
    required String uid,
    String? sessionId,
    int limit = 500,
  }) async {
    final db = await database;
    final whereParts = <String>[
      'raceId = ?',
      'uid = ?',
      'synced = 0',
    ];
    final whereArgs = <Object?>[raceId, uid];
    if (sessionId != null && sessionId.isNotEmpty) {
      whereParts.add('session = ?');
      whereArgs.add(sessionId);
    }
    return await db.query(
      'local_lap_closures',
      where: whereParts.join(' AND '),
      whereArgs: whereArgs,
      orderBy: 'sfCrossedAtMs ASC, id ASC',
      limit: limit,
    );
  }

  Future<void> markLapClosuresAsSynced(List<int> ids) async {
    if (ids.isEmpty) return;
    final db = await database;
    await db.update(
      'local_lap_closures',
      {'synced': 1},
      where: 'id IN (${ids.join(',')})',
    );
  }

  Future<void> markLapClosuresAsSyncedByClosureIds(
      List<String> closureIds) async {
    if (closureIds.isEmpty) return;
    final db = await database;
    final placeholders = List.filled(closureIds.length, '?').join(',');
    await db.update(
      'local_lap_closures',
      {'synced': 1},
      where: 'closureId IN ($placeholders)',
      whereArgs: closureIds,
    );
  }

  Future<void> clearSynced() async {
    final db = await database;
    await db.delete('telemetry', where: 'synced = 1');
    await db.delete('local_lap_closures', where: 'synced = 1');
  }
}
