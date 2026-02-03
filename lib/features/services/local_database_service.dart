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
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE telemetry (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            raceId TEXT,
            uid TEXT,
            lat REAL,
            lng REAL,
            speed REAL,
            heading REAL,
            timestamp INTEGER,
            synced INTEGER DEFAULT 0
          )
        ''');
      },
    );
  }

  Future<int> insertPoint(Map<String, dynamic> point) async {
    final db = await database;
    return await db.insert('telemetry', point);
  }

  Future<List<Map<String, dynamic>>> getUnsyncedPoints(String raceId) async {
    final db = await database;
    return await db.query(
      'telemetry',
      where: 'raceId = ? AND synced = 0',
      whereArgs: [raceId],
    );
  }

  Future<void> markAsSynced(List<int> ids) async {
    final db = await database;
    await db.update(
      'telemetry',
      {'synced': 1},
      where: 'id IN (${ids.join(',')})',
    );
  }

  Future<void> clearSynced() async {
    final db = await database;
    await db.delete('telemetry', where: 'synced = 1');
  }
}
