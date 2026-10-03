part of '../estimate_builder_screen.dart';

extension _EstimateBuilderDragExt on _EstimateBuilderScreenState {
  void _onDragPointerMove(PointerMoveEvent event) {
    if (!_isDraggingSectionItem) return;
    _dragPointerPosition = event.localPosition;
  }

  void _onDragPointerDown(PointerDownEvent event) {
    if (_isDraggingSectionItem) {
      _dragPointerPosition = event.localPosition;
    }
  }

  void _onDragPointerUp(PointerUpEvent event) {
    _dragPointerPosition = null;
  }

  void _onDragPointerCancel(PointerCancelEvent event) {
    _dragPointerPosition = null;
  }

  void _startDragAutoScroll() {
    if (_dragAutoScrollTimer != null) return;
    _isDraggingSectionItem = true;
    _dragAutoScrollTimer =
        Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (!_isDraggingSectionItem) return;
      _performDragAutoScroll();
    });
  }

  void _stopDragAutoScroll() {
    _isDraggingSectionItem = false;
    _dragPointerPosition = null;
    _dragAutoScrollTimer?.cancel();
    _dragAutoScrollTimer = null;
  }

  void _performDragAutoScroll() {
    if (!_isDraggingSectionItem || _dragPointerPosition == null) return;
    final pointerY = _dragPointerPosition!.dy;
    final viewportHeight = _dragAutoScrollViewportHeight;
    if (viewportHeight <= 0) return;
    const edgeMargin = 120.0;
    const maxScrollSpeed = 18.0;
    double scrollDelta = 0.0;
    if (pointerY < edgeMargin) {
      scrollDelta = -maxScrollSpeed * (1.0 - (pointerY / edgeMargin));
    } else if (pointerY > viewportHeight - edgeMargin) {
      scrollDelta = maxScrollSpeed *
          ((pointerY - (viewportHeight - edgeMargin)) / edgeMargin);
    }
    if (scrollDelta.abs() < 0.5) return;
    final newOffset = (_mainScrollController.offset + scrollDelta)
        .clamp(0.0, _mainScrollController.position.maxScrollExtent);
    if (newOffset != _mainScrollController.offset) {
      _mainScrollController.jumpTo(newOffset);
    }
  }
}
