import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

class VoiceTextField extends StatefulWidget {
  final TextEditingController controller;
  final String labelText;
  final String hintText;
  final int? maxLines;
  final int? minLines;
  final bool enabled;
  final InputDecoration? decoration;
  final VoidCallback? onChanged;
  final VoidCallback? onEditingComplete;
  final VoidCallback? onListeningStopped;
  final bool continuousListening; // New parameter for continuous listening mode

  const VoiceTextField({
    super.key,
    required this.controller,
    required this.labelText,
    this.hintText = '',
    this.maxLines = 1,
    this.minLines,
    this.enabled = true,
    this.decoration,
    this.onChanged,
    this.onEditingComplete,
    this.onListeningStopped,
    this.continuousListening = false, // Default to false for backwards compatibility
  });

  @override
  State<VoiceTextField> createState() => _VoiceTextFieldState();
}

class _VoiceTextFieldState extends State<VoiceTextField> {
  late stt.SpeechToText _speech;
  bool _isListening = false;
  bool _speechEnabled = false;
  String _lastWords = '';
  String _speechStatus = 'Ready'; // Add speech status tracking
  int _retryCount = 0;
  static const int _maxRetries = 3;
  bool _isRestarting = false;
  DateTime? _lastRestartTime;
  static const Duration _minRestartInterval = Duration(seconds: 2);

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    _initSpeech();
  }

  // Initialize speech recognition with comprehensive setup
  void _initSpeech() async {
    try {
      _speechEnabled = await _speech.initialize(
        onStatus: _handleSpeechStatus,
        onError: _handleSpeechError,
        debugLogging: true,
      );
      
      if (_speechEnabled) {
        print('🎤 Speech recognition initialized successfully');
        
        // Get available locales for debugging
        List<stt.LocaleName> locales = await _speech.locales();
        print('🎤 Available locales: ${locales.length}');
        
        // Check current locale
        stt.LocaleName? systemLocale = await _speech.systemLocale();
        print('🎤 System locale: ${systemLocale?.localeId ?? "Unknown"}');
      } else {
        print('🎤 Failed to initialize speech recognition');
      }
      
      if (mounted) {
        setState(() {
          _speechEnabled = _speechEnabled;
        });
      }
    } catch (e, stackTrace) {
      print('🎤 Error initializing speech: $e');
      print('🎤 Stack trace: $stackTrace');
      if (mounted) {
        setState(() {
          _speechEnabled = false;
        });
      }
    }
  }

  // Handle speech status changes
  void _handleSpeechStatus(String status) {
    print('🎤 Speech Status: $status');
    
    switch (status) {
      case 'listening':
        if (mounted) {
          setState(() {
            _speechStatus = 'Listening...';
          });
        }
        break;
      case 'notListening':
        if (mounted) {
          setState(() {
            _speechStatus = 'Not listening';
          });
        }
        
        // If we should be listening but stopped, try to restart
        if (_isListening && !_isRestarting) {
          print('🎤 Unexpected stop - attempting restart...');
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted && _isListening) _restartListening();
          });
        }
        break;
      case 'done':
        if (mounted) {
          setState(() {
            _speechStatus = 'Done';
          });
        }
        break;
    }
  }

  // Handle speech errors with comprehensive recovery
  void _handleSpeechError(error) {
    print('🎤 Speech Error: ${error.errorMsg} (${error.permanent})');
    
    if (mounted) {
      setState(() {
        _speechStatus = 'Error: ${error.errorMsg}';
      });
    }
    
    // Handle different error types
    if (error.permanent) {
      print('🎤 Permanent error - stopping speech recognition');
      if (mounted) {
        setState(() {
          _isListening = false;
          _speechEnabled = false;
        });
      }
      
      // Show user-friendly error message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Voice recognition error: ${error.errorMsg}'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } else {
      // Temporary error - try to recover
      _retryCount++;
      if (_retryCount <= _maxRetries && _isListening) {
        print('🎤 Temporary error - retry attempt $_retryCount/$_maxRetries');
        Future.delayed(Duration(seconds: _retryCount), () {
          if (mounted && _isListening) _restartListening();
        });
      } else {
        print('🎤 Max retries exceeded - stopping');
        if (mounted) {
          setState(() {
            _isListening = false;
          });
        }
      }
    }
  }

  // Result handler for speech recognition
  void _onSpeechResult(val) {
    print('🎤 Speech result: ${val.recognizedWords} (final: ${val.finalResult})');
    
    if (mounted) {
      setState(() {
        _lastWords = val.recognizedWords;
        if (val.finalResult) {
          // Append to existing text if there's any
          String newText = val.recognizedWords.trim();
          if (newText.isNotEmpty) {
            if (widget.controller.text.isNotEmpty) {
              // Add space before new text if the existing text doesn't end with space or punctuation
              String existingText = widget.controller.text;
              if (!existingText.endsWith(' ') && !existingText.endsWith('.') && 
                  !existingText.endsWith(',') && !existingText.endsWith('!') && 
                  !existingText.endsWith('?')) {
                existingText += ' ';
              }
              widget.controller.text = existingText + newText;
            } else {
              widget.controller.text = newText;
            }
            widget.onChanged?.call();
          }
        }
      });
    }
  }

  // Start a fresh listening session with proper configuration
  Future<void> _startListeningSession() async {
    if (!_speechEnabled || !mounted) return;
    
    try {
      // Get system locale for listening
      stt.LocaleName? systemLocale = await _speech.systemLocale();
      
      await _speech.listen(
        onResult: _onSpeechResult,
        listenFor: widget.continuousListening 
          ? const Duration(minutes: 30)  // Long session for continuous mode
          : const Duration(seconds: 30), // Standard session
        pauseFor: const Duration(seconds: 5),
        partialResults: true,
        localeId: systemLocale?.localeId,
        listenMode: stt.ListenMode.confirmation,
        cancelOnError: false,
        sampleRate: 16000,
      );
      
      print('🎤 Started listening session (continuous: ${widget.continuousListening})');
      
      if (mounted) {
        setState(() {
          _speechStatus = 'Listening...';
        });
      }
      
    } catch (e) {
      print('🎤 Error starting listening session: $e');
      rethrow;
    }
  }

  void _restartListening() async {
    if (!mounted || !_isListening || _isRestarting) return;
    
    // Prevent too frequent restarts
    final now = DateTime.now();
    if (_lastRestartTime != null && 
        now.difference(_lastRestartTime!) < _minRestartInterval) {
      print('🎤 Restart throttled - too soon since last restart');
      return;
    }
    
    _isRestarting = true;
    _lastRestartTime = now;
    
    print('🎤 Restarting speech recognition...');
    try {
      // Stop current session completely
      if (_speech.isListening) {
        await _speech.stop();
        print('🎤 Stopped existing session');
      }
      
      // Wait for proper cleanup
      await Future.delayed(const Duration(milliseconds: 1000));
      
      // Check if we should still be listening and widget is still mounted
      if (!mounted || !_isListening) {
        print('🎤 Restart cancelled - no longer listening or widget disposed');
        _isRestarting = false;
        return;
      }
      
      // Re-initialize if needed (helps with long sessions)
      if (_retryCount > 1) {
        print('🎤 Re-initializing speech engine for reliability...');
        await _speech.stop();
        _speech = stt.SpeechToText();
        final available = await _speech.initialize(
          onStatus: _handleSpeechStatus,
          onError: _handleSpeechError,
          debugLogging: true,
        );
        
        if (!available) {
          print('🎤 Failed to re-initialize speech engine');
          if (mounted) {
            setState(() {
              _speechEnabled = false;
              _isListening = false;
            });
          }
          _isRestarting = false;
          return;
        }
      }
      
      // Start fresh listening session
      await _startListeningSession();
      
    } catch (e, stackTrace) {
      print('🎤 Error during restart: $e');
      print('🎤 Stack trace: $stackTrace');
      
      if (mounted) {
        setState(() {
          _isListening = false;
          _speechEnabled = false;
        });
        
        // Try full re-initialization as last resort
        if (_retryCount < _maxRetries) {
          print('🎤 Attempting full re-initialization...');
          Future.delayed(const Duration(seconds: 3), () {
            if (mounted) _initSpeech();
          });
        }
      }
    } finally {
      _isRestarting = false;
    }
  }

  void _startListening() async {
    if (!_speechEnabled) {
      print('Speech not enabled, cannot start listening');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Speech recognition not available')),
        );
      }
      return;
    }
    
    // Check if already listening
    if (_speech.isListening) {
      print('Already listening, stopping first...');
      await _speech.stop();
      await Future.delayed(const Duration(milliseconds: 500));
    }

    print('Starting speech recognition...');
    setState(() {
      _isListening = true;
      _lastWords = '';
    });

    // Reset retry count on successful start
    _retryCount = 0;

    try {
      await _speech.listen(
        onResult: (val) {
          print('Speech result: ${val.recognizedWords} (final: ${val.finalResult})');
          setState(() {
            _lastWords = val.recognizedWords;
            if (val.finalResult) {
              // Append to existing text if there's any
              String newText = val.recognizedWords.trim();
              if (newText.isNotEmpty) {
                if (widget.controller.text.isNotEmpty) {
                  // Add space before new text if the existing text doesn't end with space or punctuation
                  String existingText = widget.controller.text;
                  if (!existingText.endsWith(' ') && !existingText.endsWith('.') && 
                      !existingText.endsWith(',') && !existingText.endsWith('!') && 
                      !existingText.endsWith('?')) {
                    existingText += ' ';
                  }
                  widget.controller.text = existingText + newText;
                } else {
                  widget.controller.text = newText;
                }
                widget.onChanged?.call();
              }
              
              // In continuous mode, don't stop listening
              if (!widget.continuousListening) {
                _isListening = false;
                print('Single session complete, stopped listening');
              } else {
                print('Continuous mode: continuing to listen...');
              }
            }
          });
        },
        listenFor: widget.continuousListening 
            ? const Duration(minutes: 30) // Much longer duration for continuous mode
            : const Duration(minutes: 5), // Increased from 30 seconds to 5 minutes
        pauseFor: widget.continuousListening
            ? const Duration(seconds: 3) // Longer pause for continuous mode to handle natural pauses
            : const Duration(seconds: 5), // Increased pause time
        localeId: 'en_US',
        partialResults: true,
        onSoundLevelChange: (level) {
          // Visual feedback for sound level (optional)
          // print('Sound level: $level');
        },
        cancelOnError: false, // Don't cancel on error to be more robust
        listenMode: stt.ListenMode.confirmation,
      );
      print('Speech listening started successfully');
    } catch (e) {
      print('Error starting speech recognition: $e');
      setState(() {
        _isListening = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to start voice input: $e'),
            action: SnackBarAction(
              label: 'Retry',
              onPressed: () => _startListening(),
            ),
          ),
        );
      }
    }
  }

  void _stopListening() async {
    print('Stopping speech recognition...');
    try {
      await _speech.stop();
      setState(() {
        _isListening = false;
        _lastWords = '';
      });
      print('Speech recognition stopped successfully');
    } catch (e) {
      print('Error stopping speech recognition: $e');
      setState(() {
        _isListening = false;
        _lastWords = '';
      });
    } finally {
      if (mounted) {
        widget.onListeningStopped?.call();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(textCapitalization: TextCapitalization.sentences, 
          controller: widget.controller,
          decoration: widget.decoration ?? InputDecoration(
            labelText: widget.labelText,
            hintText: widget.hintText,
            border: const OutlineInputBorder(),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Voice input button
                IconButton(
                  onPressed: _speechEnabled && widget.enabled
                      ? (_isListening ? _stopListening : _startListening)
                      : null,
                  icon: Icon(
                    _isListening 
                        ? (widget.continuousListening ? Icons.stop : Icons.mic)
                        : Icons.mic_none,
                    color: _isListening 
                        ? Colors.red 
                        : (_speechEnabled ? Colors.blue : Colors.grey),
                  ),
                  tooltip: _isListening 
                      ? (widget.continuousListening ? 'Stop continuous recording' : 'Stop listening')
                      : (widget.continuousListening ? 'Start continuous recording' : 'Start voice input'),
                ),
                // Test microphone button (for debugging)
                if (!_speechEnabled)
                  IconButton(
                    onPressed: () {
                      print('Testing speech recognition...');
                      _initSpeech();
                    },
                    icon: const Icon(Icons.refresh, size: 20),
                    tooltip: 'Retry speech setup',
                  ),
                // Clear button
                if (widget.controller.text.isNotEmpty)
                  IconButton(
                    onPressed: widget.enabled ? () {
                      widget.controller.clear();
                      widget.onChanged?.call();
                    } : null,
                    icon: const Icon(Icons.clear, size: 20),
                    tooltip: 'Clear text',
                  ),
              ],
            ),
          ),
          minLines: widget.minLines ?? widget.maxLines,
          maxLines: widget.maxLines == null ? null : math.max(widget.maxLines!, widget.minLines ?? 1),
          keyboardType: (widget.maxLines == null || (widget.maxLines ?? 1) > 1)
              ? TextInputType.multiline
              : TextInputType.text,
          enabled: widget.enabled,
          onChanged: (_) => widget.onChanged?.call(),
          onEditingComplete: widget.onEditingComplete,
        ),
        // Status indicators
        if (_isListening && _lastWords.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.blue.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.hearing, size: 16, color: Colors.blue[700]),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      widget.continuousListening 
                          ? 'Recording: $_lastWords'
                          : 'Listening: $_lastWords',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blue[700],
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        // Speech status indicator
        if (_speechStatus != 'Ready' && _speechStatus.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _speechStatus.startsWith('Error') 
                    ? Colors.red.withOpacity(0.1)
                    : Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: _speechStatus.startsWith('Error')
                      ? Colors.red.withOpacity(0.3)
                      : Colors.green.withOpacity(0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _speechStatus.startsWith('Error') ? Icons.error_outline : Icons.mic,
                    size: 16,
                    color: _speechStatus.startsWith('Error') ? Colors.red[700] : Colors.green[700],
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      _speechStatus,
                      style: TextStyle(
                        fontSize: 12,
                        color: _speechStatus.startsWith('Error') ? Colors.red[700] : Colors.green[700],
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (_isListening && widget.continuousListening)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.red.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.red[600]!),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Continuous recording active - tap stop (🛑) to end',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.red[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (!_speechEnabled && widget.enabled)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.orange.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.mic_off, size: 16, color: Colors.orange[700]),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Voice input not available - tap refresh (🔄) to retry',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.orange[700],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  @override
  void dispose() {
    _speech.stop();
    super.dispose();
  }
}
