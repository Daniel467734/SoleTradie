import 'package:shared_preferences/shared_preferences.dart';
import '../templates/pdf_receipt_templates.dart' show openAiApiKey;

/// Resolves the OpenAI API key to use for all AI features (receipt
/// scanner, PDF-to-Build conversion, etc.).
///
/// Priority:
///  1. A key entered by the user in Settings (stored in SharedPreferences
///     under `openai_api_key`) - this is what makes AI features work on an
///     installed phone build without needing to rebuild the app.
///  2. The `--dart-define=OPENAI_API_KEY=sk-...` value baked in at build
///     time (used for local `flutter run` development).
///
/// Never hardcode a real key in source - this repo is public on GitHub.
class OpenAiKeyService {
  static const _prefsKey = 'openai_api_key';

  static Future<String> getKey() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_prefsKey)?.trim();
    if (stored != null && stored.isNotEmpty) {
      return stored;
    }
    return openAiApiKey;
  }

  static Future<void> setKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, key.trim());
  }

  static Future<String> getStoredKeyForDisplay() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefsKey) ?? '';
  }
}
