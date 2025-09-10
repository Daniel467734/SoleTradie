import 'package:flutter/material.dart';

/// WhisperVoiceTextField - OpenAI Whisper API Integration
/// 
/// This widget is temporarily disabled due to package compatibility issues.
/// The 'record' package has Linux compatibility problems with record_linux 0.7.2
/// that prevent the app from building successfully.
/// 
/// For now, please use WebSpeechTextField which provides:
/// - Completely free voice-to-text (no API costs)
/// - Uses device's built-in speech recognition
/// - Excellent reliability for long sessions
/// - Optimized for New Zealand English
/// 
/// This will be re-enabled once the record package issues are resolved.
class WhisperVoiceTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final int maxLines;

  const WhisperVoiceTextField({
    super.key,
    required this.controller,
    this.hintText = '',
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: hintText,
            border: const OutlineInputBorder(),
            suffixIcon: Tooltip(
              message: 'Whisper Voice Input (Temporarily Disabled)',
              child: IconButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Whisper voice input temporarily disabled due to package conflicts. '
                        'Use WebSpeech voice input instead - it\'s free and works great!',
                      ),
                      duration: Duration(seconds: 4),
                    ),
                  );
                },
                icon: const Icon(
                  Icons.mic_off,
                  color: Colors.grey,
                ),
              ),
            ),
          ),
          maxLines: maxLines,
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.orange.shade50,
            border: Border.all(color: Colors.orange.shade300),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline, 
                   color: Colors.orange.shade700, 
                   size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Whisper voice temporarily unavailable. Try WebSpeech voice input - it\'s free and reliable!',
                  style: TextStyle(
                    color: Colors.orange.shade700,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
