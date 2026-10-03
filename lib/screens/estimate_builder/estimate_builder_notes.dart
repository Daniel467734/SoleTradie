part of '../estimate_builder_screen.dart';

extension _EstimateBuilderNotesExt on _EstimateBuilderScreenState {
  String? _loadBuilderNoteFromJob() {
    return widget.job.notes
      ?.firstWhereOrNull((note) =>
        note.startsWith(_EstimateBuilderScreenState._builderNotePrefix))
      ?.substring(_EstimateBuilderScreenState._builderNotePrefix.length);
  }

  void _syncBuilderNoteToJob() {
    final text = _jobNotesController.text.trim();
    final notes = widget.job.notes ?? <String>[];
    final existingIndex =
      notes.indexWhere((note) =>
        note.startsWith(_EstimateBuilderScreenState._builderNotePrefix));
    if (text.isEmpty) {
      if (existingIndex != -1) {
        notes.removeAt(existingIndex);
      }
    } else {
      final noteText = '${_EstimateBuilderScreenState._builderNotePrefix}$text';
      if (existingIndex != -1) {
        notes[existingIndex] = noteText;
      } else {
        notes.add(noteText);
      }
    }
    widget.job.notes = notes;
  }

  Future<void> _saveJobNotes() async {
    _syncBuilderNoteToJob();
    await _persistJobToDisk();
  }
}
