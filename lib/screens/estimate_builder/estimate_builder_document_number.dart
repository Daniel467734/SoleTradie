part of '../estimate_builder_screen.dart';

extension _EstimateBuilderDocumentNumberExt on _EstimateBuilderScreenState {
  Future<String> _getNextDocumentNumber() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final yy = (now.year % 100).toString().padLeft(2, '0');
    final mm = now.month.toString().padLeft(2, '0');
    final dd = now.day.toString().padLeft(2, '0');
    final dateKey = '$yy$mm$dd'; // e.g. 260903

    final lastDate = prefs.getString('last_document_date') ?? '';
    int counter = 1;
    if (lastDate == dateKey) {
      counter = (prefs.getInt('last_document_counter') ?? 0) + 1;
    } else {
      counter = 1;
    }

    await prefs.setString('last_document_date', dateKey);
    await prefs.setInt('last_document_counter', counter);

    return '$dateKey${counter.toString()}';
  }
}
