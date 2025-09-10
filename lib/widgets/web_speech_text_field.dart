import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'dart:async';

/// A free voice-to-text widget using the device's built-in speech recognition
/// No API keys required - uses the platform's native speech recognition
class WebSpeechTextField extends StatefulWidget {
  final TextEditingController controller;
  final String labelText;
  final String? hintText;
  final int maxLines;
  final bool continuousListening;

  const WebSpeechTextField({
    super.key,
    required this.controller,
    required this.labelText,
    this.hintText,
    this.maxLines = 1,
    this.continuousListening = false,
  });

  @override
  State<WebSpeechTextField> createState() => _WebSpeechTextFieldState();
}

class _WebSpeechTextFieldState extends State<WebSpeechTextField> {
  late stt.SpeechToText _speech;
  bool _isListening = false;
  bool _isAvailable = false;
  String _currentWords = '';
  Timer? _sessionTimer;
  Timer? _restartTimer;
  int _sessionCount = 0;
  bool _hasError = false;
  String _errorMessage = '';
  
  // Session management for long recordings
  static const Duration _maxSessionDuration = Duration(minutes: 3);
  static const Duration _restartDelay = Duration(seconds: 2);

  @override
  void initState() {
    super.initState();
    _initSpeech();
  }

  @override
  void dispose() {
    _stopListening();
    _sessionTimer?.cancel();
    _restartTimer?.cancel();
    super.dispose();
  }

  Future<void> _initSpeech() async {
    _speech = stt.SpeechToText();
    bool available = await _speech.initialize(
      onStatus: _onStatusChanged,
      onError: _onError,
      debugLogging: false,
    );
    
    setState(() {
      _isAvailable = available;
    });

    if (!available) {
      setState(() {
        _hasError = true;
        _errorMessage = 'Speech recognition not available on this device';
      });
    }
  }

  void _onStatusChanged(String status) {
    setState(() {
      if (status == 'listening') {
        _isListening = true;
        _hasError = false;
        _errorMessage = '';
      } else if (status == 'notListening') {
        _isListening = false;
        // Auto-restart for continuous listening
        if (widget.continuousListening && !_hasError) {
          _scheduleRestart();
        }
      }
    });
  }

  void _onError(dynamic error) {
    setState(() {
      _isListening = false;
      _hasError = true;
      _errorMessage = 'Error: ${error.errorMsg ?? error.toString()}';
    });
    
    // Auto-restart on recoverable errors
    if (widget.continuousListening && _isRecoverableError(error.errorMsg)) {
      _scheduleRestart();
    }
  }

  bool _isRecoverableError(String? errorMsg) {
    if (errorMsg == null) return false;
    final recoverableErrors = [
      'network',
      'timeout',
      'audio',
      'no_match',
      'recognizer_busy'
    ];
    return recoverableErrors.any((err) => errorMsg.toLowerCase().contains(err));
  }

  void _scheduleRestart() {
    _restartTimer?.cancel();
    _restartTimer = Timer(_restartDelay, () {
      if (mounted && widget.continuousListening && !_isListening) {
        _startListening();
      }
    });
  }

  Future<void> _startListening() async {
    if (!_isAvailable || _isListening) return;

    // Cancel any existing timers
    _sessionTimer?.cancel();
    _restartTimer?.cancel();

    try {
      _sessionCount++;
      setState(() {
        _hasError = false;
        _errorMessage = '';
      });

      await _speech.listen(
        onResult: _onSpeechResult,
        listenFor: _maxSessionDuration,
        pauseFor: const Duration(seconds: 3),
        partialResults: true,
        localeId: 'en_NZ', // New Zealand English
        listenMode: stt.ListenMode.confirmation,
        cancelOnError: true,
        onSoundLevelChange: (level) {
          // Visual feedback could be added here
        },
      );

      // Set up session timeout
      _sessionTimer = Timer(_maxSessionDuration, () {
        if (_isListening) {
          _stopListening();
          if (widget.continuousListening) {
            _scheduleRestart();
          }
        }
      });

    } catch (e) {
      setState(() {
        _hasError = true;
        _errorMessage = 'Failed to start listening: $e';
      });
    }
  }

  void _onSpeechResult(result) {
    setState(() {
      _currentWords = result.recognizedWords;
      
      // Update the text field
      if (result.finalResult) {
        // Append to existing text with proper spacing
        String existingText = widget.controller.text;
        if (existingText.isNotEmpty && !existingText.endsWith(' ')) {
          existingText += ' ';
        }
        widget.controller.text = existingText + _currentWords;
        _currentWords = '';
        
        // Move cursor to end
        widget.controller.selection = TextSelection.fromPosition(
          TextPosition(offset: widget.controller.text.length),
        );
      }
    });
  }

  Future<void> _stopListening() async {
    _sessionTimer?.cancel();
    _restartTimer?.cancel();
    
    if (_speech.isListening) {
      await _speech.stop();
    }
    
    setState(() {
      _isListening = false;
    });
  }

  void _toggleListening() {
    if (_isListening) {
      _stopListening();
    } else {
      _startListening();
    }
  }

  void _clearError() {
    setState(() {
      _hasError = false;
      _errorMessage = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Main text field
        TextField(
          controller: widget.controller,
          decoration: InputDecoration(
            labelText: widget.labelText,
            hintText: widget.hintText,
            border: const OutlineInputBorder(),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Session info
                if (_sessionCount > 0)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text(
                      'S$_sessionCount',
                      style: const TextStyle(fontSize: 10, color: Colors.grey),
                    ),
                  ),
                // Voice button
                IconButton(
                  onPressed: _isAvailable ? _toggleListening : null,
                  icon: Icon(
                    _isListening ? Icons.mic : Icons.mic_none,
                    color: _isListening ? Colors.red : (_isAvailable ? Colors.blue : Colors.grey),
                  ),
                  tooltip: _isListening ? 'Stop Recording' : 'Start Recording',
                ),
              ],
            ),
          ),
          maxLines: widget.maxLines,
        ),
        
        // Status indicators
        if (_isListening || _currentWords.isNotEmpty || _hasError) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _hasError ? Colors.red.shade50 : Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _hasError ? Colors.red.shade200 : Colors.blue.shade200,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Status row
                Row(
                  children: [
                    Icon(
                      _hasError ? Icons.error : (_isListening ? Icons.mic : Icons.mic_none),
                      color: _hasError ? Colors.red : Colors.blue,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _hasError 
                            ? 'Error occurred' 
                            : (_isListening ? 'Listening...' : 'Ready'),
                        style: TextStyle(
                          color: _hasError ? Colors.red : Colors.blue,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    if (_hasError)
                      TextButton(
                        onPressed: _clearError,
                        child: const Text('Dismiss'),
                      ),
                  ],
                ),
                
                // Current words being spoken
                if (_currentWords.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Current: $_currentWords',
                    style: const TextStyle(
                      fontStyle: FontStyle.italic,
                      color: Colors.grey,
                    ),
                  ),
                ],
                
                // Error message
                if (_hasError && _errorMessage.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    _errorMessage,
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                  ),
                ],
                
                // Session info for continuous listening
                if (widget.continuousListening && _sessionCount > 0) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Session $_sessionCount • Auto-restart enabled • Max 3min per session',
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                ],
              ],
            ),
          ),
        ],
        
        // Help text for new users
        if (!_isAvailable) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: const Row(
              children: [
                Icon(Icons.info, color: Colors.orange, size: 16),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Speech recognition not available. Check device permissions or try the cloud voice option.',
                    style: TextStyle(fontSize: 12, color: Colors.orange),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
