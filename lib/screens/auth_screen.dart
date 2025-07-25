import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/database_service.dart';
import '../api/openrouter_client.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _apiKeyController = TextEditingController();
  final _pinController = TextEditingController();
  bool _isFirstLogin = true;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _checkExistingAuth();
  }

  Future<void> _checkExistingAuth() async {
    final db = DatabaseService();
    print('Checking for existing auth data...');
    final authData = await db.getFirstAuthData();
    print('Auth data found: ${authData != null}');
    if (authData != null && authData['pin_code'] != null) {
      print('Existing auth data with PIN found');
      setState(() {
        _isFirstLogin = false;
        _apiKeyController.text = authData['api_key'];
      });
    } else {
      print('No valid auth data found in database');
      setState(() {
        _isFirstLogin = true;
      });
    }
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final db = DatabaseService();

      if (_isFirstLogin) {
        // Определение типа ключа
        final provider =
            OpenRouterClient.identifyKeyType(_apiKeyController.text);
        if (provider == 'Unknown') {
          throw Exception('Неверный формат API ключа');
        }

        // Проверка баланса через API
        final client = OpenRouterClient();
        final balanceStr = await client.getBalance();
        final balance =
            double.tryParse(balanceStr.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0;

        if (balance <= 0) {
          throw Exception('Недостаточно средств на балансе');
        }

        // Генерация 4-значного PIN
        final pin = _generatePin();

        // Сохранение данных
        await db.saveAuthData(
          apiKey: _apiKeyController.text,
          pinCode: pin,
          providerType: provider,
          balance: balance,
        );

        // Показать PIN пользователю
        _showPinDialog(pin);
      } else {
        // Проверка PIN
        final isValid =
            await db.checkPin(_apiKeyController.text, _pinController.text);

        if (!isValid) {
          throw Exception('Неверный PIN код');
        }

        // Переход в основное приложение
        _navigateToApp();
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  String _generatePin() {
    final random = Random();
    return List.generate(4, (_) => random.nextInt(10)).join();
  }

  void _showPinDialog(String pin) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ваш PIN код'),
        content: Text('Запомните ваш PIN: $pin'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _navigateToApp();
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _navigateToApp() {
    Navigator.pushReplacementNamed(context, '/chat');
  }

  void _resetAuth() {
    setState(() {
      _isFirstLogin = true;
      _apiKeyController.clear();
      _pinController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Аутентификация')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              if (_isFirstLogin)
                TextFormField(
                  controller: _apiKeyController,
                  decoration: const InputDecoration(
                    labelText: 'API ключ',
                    hintText: 'Введите ваш API ключ',
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Пожалуйста, введите API ключ';
                    }
                    return null;
                  },
                ),
              if (!_isFirstLogin)
                TextFormField(
                  controller: _pinController,
                  decoration: const InputDecoration(
                    labelText: 'PIN код',
                    hintText: 'Введите ваш 4-значный PIN',
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(4),
                  ],
                  validator: (value) {
                    if (value == null || value.length != 4) {
                      return 'PIN должен состоять из 4 цифр';
                    }
                    return null;
                  },
                ),
              if (_errorMessage != null)
                Text(
                  _errorMessage!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _isLoading ? null : _handleSubmit,
                child: _isLoading
                    ? const CircularProgressIndicator()
                    : Text(_isFirstLogin ? 'Войти' : 'Продолжить'),
              ),
              if (!_isFirstLogin)
                TextButton(
                  onPressed: _resetAuth,
                  child: const Text('Сбросить ключ'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _pinController.dispose();
    super.dispose();
  }
}
