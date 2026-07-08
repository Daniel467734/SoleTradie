/// GUIDE: How to fix bottom button cutoff issues in Flutter
/// 
/// **Problem:** Buttons at the bottom of SingleChildScrollView are cut off by keyboard/navigation bar
/// 
/// **Solution 1: Use BottomButtonBar (Recommended)**
/// ```dart
/// ScreenWithBottomButtons(
///   body: SingleChildScrollView(
///     child: Column(children: [...content...]),
///   ),
///   bottomButtons: [
///     ElevatedButton(onPressed: () {}, child: Text('Save')),
///     ElevatedButton(onPressed: () {}, child: Text('Cancel')),
///   ],
/// )
/// ```
/// 
/// **Solution 2: Add bottom padding to SingleChildScrollView**
/// ```dart
/// SingleChildScrollView(
///   padding: EdgeInsets.only(
///     bottom: MediaQuery.of(context).viewInsets.bottom + 120,
///   ),
///   child: Column(...),
/// )
/// ```
/// 
/// **Solution 3: Use ListView with shrinkWrap**
/// ```dart
/// ListView(
///   shrinkWrap: true,
///   padding: EdgeInsets.only(
///     bottom: MediaQuery.of(context).viewInsets.bottom + 100,
///   ),
///   children: [...],
/// )
/// ```
/// 
/// **Solution 4: Move buttons outside of scrollable area**
/// ```dart
/// Scaffold(
///   body: SingleChildScrollView(
///     child: Column(...content...),
///   ),
///   bottomSheet: Container(
///     padding: EdgeInsets.all(16),
///     child: Row(
///       children: [button1, button2],
///     ),
///   ),
/// )
/// ```
/// 
/// **Common affected screens:**
/// - customer_form_screen.dart
/// - pricebook_screen.dart
/// - settings_screen.dart
/// - estimate_builder_screen.dart
/// - Any screen with SingleChildScrollView + bottom buttons

class BottomCutoffFixGuide {}
