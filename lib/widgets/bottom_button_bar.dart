import 'package:flutter/material.dart';

/// Helper widget to prevent buttons from being cut off at bottom of screen
class BottomButtonBar extends StatelessWidget {
  final List<Widget> buttons;
  final double spacing;
  final EdgeInsets padding;

  const BottomButtonBar({
    super.key,
    required this.buttons,
    this.spacing = 12.0,
    this.padding = const EdgeInsets.all(16.0),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding.copyWith(
        bottom: padding.bottom + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (int i = 0; i < buttons.length; i++) ...[
            buttons[i],
            if (i < buttons.length - 1) SizedBox(height: spacing),
          ],
        ],
      ),
    );
  }
}

/// Wrapper for screens with bottom buttons
/// Usage: Scaffold( body: ScreenContent(...), bottomSheet: BottomButtonSheet(...) )
class ScreenWithBottomButtons extends StatelessWidget {
  final Widget body;
  final List<Widget> bottomButtons;
  final AppBar? appBar;
  final FloatingActionButton? floatingActionButton;

  const ScreenWithBottomButtons({
    super.key,
    required this.body,
    required this.bottomButtons,
    this.appBar,
    this.floatingActionButton,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: appBar,
      body: Stack(
        children: [
          // Main content with padding for buttons
          SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 120.0),
              child: body,
            ),
          ),
          // Floating button bar at bottom
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Material(
              elevation: 8,
              child: BottomButtonBar(buttons: bottomButtons),
            ),
          ),
        ],
      ),
      floatingActionButton: floatingActionButton,
    );
  }
}
