// Импорт платформо-зависимых функций
import 'dart:io' show Platform, File, Directory;
// Импорт утилит для работы с путями
import 'package:path/path.dart';
// Импорт основного пакета для работы с SQLite
import 'package:sqflite/sqflite.dart';
// Импорт основных классов Flutter
import 'package:flutter/foundation.dart';
// Импорт FFI реализации для desktop платформ
import 'package:sqflite_common_ffi/sqflite_ffi.dart' if (dart.library.html) '';
// Импорт модели сообщения
import '../models/message.dart';

// Класс сервиса для работы с базой данных
class DatabaseService {
  // Единственный экземпляр класса (Singleton)
  static final DatabaseService _instance = DatabaseService._internal();
  // Экземпляр базы данных
  static Database? _database;

  // Фабричный метод для получения экземпляра
  factory DatabaseService() {
    return _instance;
  }

  // Приватный конструктор для реализации Singleton
  DatabaseService._internal();

  // Геттер для получения экземпляра базы данных
  Future<Database> get database async {
    if (_database != null) return _database!; // Возврат существующей БД
    _database = await _initDatabase(); // Инициализация новой БД
    return _database!;
  }

  // Метод инициализации базы данных
  Future<Database> _initDatabase() async {
    // Инициализация FFI для desktop платформ
    if (Platform.isWindows || Platform.isLinux) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    // Получение пути к базе данных
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'chat_cache.db'); // Имя файла базы данных
    print('Database path: $path');
    print('Database will be saved at: ${File(path).absolute.path}');
    print('Directory contents: ${Directory(dbPath).listSync()}');

    // Открытие/создание базы данных
    print('Opening database...');
    return await openDatabase(
      path,
      version: 1,
      onCreate: (Database db, int version) async {
        try {
          print('Creating messages table...');
          await db.execute('''
            CREATE TABLE messages (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              content TEXT NOT NULL,
              is_user INTEGER NOT NULL,
              timestamp TEXT NOT NULL,
              model_id TEXT,
              tokens INTEGER,
              cost REAL
            )
          ''');
          print('Messages table created successfully');

          print('Creating auth table...');
          await db.execute('''
            CREATE TABLE auth (
              api_key TEXT PRIMARY KEY,
              pin_code TEXT NOT NULL,
              provider_type TEXT NOT NULL,
              balance REAL NOT NULL,
              last_updated TEXT NOT NULL
            )
          ''');
          print('Auth table created successfully');
        } catch (e) {
          print('Error creating tables: $e');
          rethrow;
        }
      },
    );
  }

  // Метод сохранения сообщения в базу данных
  Future<void> saveMessage(ChatMessage message) async {
    try {
      final db = await database;
      // Вставка данных в таблицу messages
      await db.insert(
        'messages',
        {
          'content': message.content, // Текст сообщения
          'is_user': message.isUser ? 1 : 0, // Преобразование bool в int
          'timestamp': message.timestamp.toIso8601String(), // Временная метка
          'model_id': message.modelId, // Идентификатор модели
          'tokens': message.tokens, // Количество токенов
          'cost': message.cost, // Стоимость запроса
        },
        conflictAlgorithm:
            ConflictAlgorithm.replace, // Стратегия при конфликтах
      );
    } catch (e) {
      debugPrint('Error saving message: $e'); // Логирование ошибок
    }
  }

  // Метод получения сообщений из базы данных
  Future<List<ChatMessage>> getMessages({int limit = 50}) async {
    try {
      final db = await database;
      // Запрос данных из таблицы messages
      final List<Map<String, dynamic>> maps = await db.query(
        'messages',
        orderBy: 'timestamp ASC', // Сортировка по времени
        limit: limit, // Ограничение количества записей
      );

      // Преобразование данных в объекты ChatMessage
      return List.generate(maps.length, (i) {
        return ChatMessage(
          content: maps[i]['content'] as String, // Текст сообщения
          isUser: maps[i]['is_user'] == 1, // Преобразование int в bool
          timestamp:
              DateTime.parse(maps[i]['timestamp'] as String), // Временная метка
          modelId: maps[i]['model_id'] as String?, // Идентификатор модели
          tokens: maps[i]['tokens'] as int?, // Количество токенов
          cost: maps[i]['cost'] as double?, // Стоимость запроса
        );
      });
    } catch (e) {
      debugPrint('Error getting messages: $e'); // Логирование ошибок
      return []; // Возврат пустого списка в случае ошибки
    }
  }

  // Метод очистки истории сообщений
  Future<void> clearHistory() async {
    try {
      final db = await database;
      await db.delete('messages'); // Удаление всех записей из таблицы
    } catch (e) {
      debugPrint('Error clearing history: $e'); // Логирование ошибок
    }
  }

  // Метод получения статистики по сообщениям
  Future<Map<String, dynamic>> getStatistics() async {
    try {
      final db = await database;

      // Получение общего количества сообщений
      final totalMessagesResult =
          await db.rawQuery('SELECT COUNT(*) as count FROM messages');
      final totalMessages = Sqflite.firstIntValue(totalMessagesResult) ?? 0;

      // Получение общего количества токенов
      final totalTokensResult = await db.rawQuery(
          'SELECT SUM(tokens) as total FROM messages WHERE tokens IS NOT NULL');
      final totalTokens = Sqflite.firstIntValue(totalTokensResult) ?? 0;

      // Получение статистики использования моделей
      final modelStats = await db.rawQuery('''
        SELECT 
          model_id,
          COUNT(*) as message_count,
          SUM(tokens) as total_tokens
        FROM messages 
        WHERE model_id IS NOT NULL 
        GROUP BY model_id
      ''');

      // Формирование данных по использованию моделей
      final modelUsage = <String, Map<String, int>>{};
      for (final stat in modelStats) {
        final modelId = stat['model_id'] as String;
        modelUsage[modelId] = {
          'count': stat['message_count'] as int, // Количество сообщений
          'tokens':
              stat['total_tokens'] as int? ?? 0, // Общее количество токенов
        };
      }

      return {
        'total_messages': totalMessages, // Общее количество сообщений
        'total_tokens': totalTokens, // Общее количество токенов
        'model_usage': modelUsage, // Статистика по моделям
      };
    } catch (e) {
      debugPrint('Error getting statistics: $e'); // Логирование ошибок
      return {
        'total_messages': 0,
        'total_tokens': 0,
        'model_usage': {},
      };
    }
  }

  // Метод сохранения данных аутентификации
  Future<void> saveAuthData({
    required String apiKey,
    required String pinCode,
    required String providerType,
    required double balance,
  }) async {
    try {
      final db = await database;
      print('Saving auth data:');
      print('API Key: ${apiKey.substring(0, 5)}...');
      print('PIN Code: $pinCode');
      print('Provider: $providerType');
      print('Balance: $balance');

      final result = await db.insert(
        'auth',
        {
          'api_key': apiKey,
          'pin_code': pinCode,
          'provider_type': providerType,
          'balance': balance,
          'last_updated': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      print('Auth data saved with result: $result');
      print('Verifying saved data...');
      final savedData = await getAuthData(apiKey);
      print('Saved data verification: ${savedData != null}');
    } catch (e) {
      debugPrint('Error saving auth data: $e');
      print('Full error: $e');
      rethrow;
    }
  }

  // Метод получения данных аутентификации
  Future<Map<String, dynamic>?> getAuthData(String apiKey) async {
    try {
      final db = await database;
      final List<Map<String, dynamic>> result = await db.query(
        'auth',
        where: 'api_key = ?',
        whereArgs: [apiKey],
        limit: 1,
      );
      return result.isNotEmpty ? result.first : null;
    } catch (e) {
      debugPrint('Error getting auth data: $e');
      return null;
    }
  }

  // Метод получения первого сохраненного ключа
  Future<Map<String, dynamic>?> getFirstAuthData() async {
    try {
      final db = await database;
      print('Querying auth table...');
      final List<Map<String, dynamic>> result = await db.query(
        'auth',
        limit: 1,
      );
      print('Found ${result.length} auth records');
      return result.isNotEmpty ? result.first : null;
    } catch (e) {
      debugPrint('Error getting first auth data: $e');
      return null;
    }
  }

  // Метод удаления данных аутентификации
  Future<void> deleteAuthData(String apiKey) async {
    try {
      final db = await database;
      await db.delete(
        'auth',
        where: 'api_key = ?',
        whereArgs: [apiKey],
      );
    } catch (e) {
      debugPrint('Error deleting auth data: $e');
    }
  }

  // Метод проверки PIN кода
  Future<bool> checkPin(String apiKey, String pin) async {
    try {
      final db = await database;
      final List<Map<String, dynamic>> result = await db.query(
        'auth',
        where: 'api_key = ? AND pin_code = ?',
        whereArgs: [apiKey, pin],
        limit: 1,
      );
      return result.isNotEmpty;
    } catch (e) {
      debugPrint('Error checking PIN: $e');
      return false;
    }
  }
}
