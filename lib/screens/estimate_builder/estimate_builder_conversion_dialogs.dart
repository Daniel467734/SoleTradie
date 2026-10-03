part of '../estimate_builder_screen.dart';

extension _EstimateBuilderConversionDialogsExt on _EstimateBuilderScreenState {
  /// Shows a non-dismissible conversion spinner while the pricebook loads.
  void _showBuildConvertingLoadingDialog() {
    if (!mounted || _isBuildConvertingLoadingDialogShown) return;
    _isBuildConvertingLoadingDialogShown = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: const AlertDialog(
          content: Row(
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 16),
              Expanded(
                child: Text(
                  'Converting build... checking pricebook for price '
                  'changes. This may take up to 20 seconds.',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _closeBuildConvertingLoadingDialog() {
    if (!_isBuildConvertingLoadingDialogShown) return;
    _isBuildConvertingLoadingDialogShown = false;
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }
}
