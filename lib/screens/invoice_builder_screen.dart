import 'package:flutter/material.dart';
export 'package:flutter/src/widgets/navigator.dart';


class EstimateBuilderScreen extends StatelessWidget {
  final String jobId;
  final String jobTitle;
  final String jobType;
  final List priceBook;
  final dynamic currentEstimate;

  const EstimateBuilderScreen({
    super.key,
    required this.jobId,
    required this.jobTitle,
    required this.jobType,
    required this.priceBook,
    this.currentEstimate,
  });

  @override
  Widget build(BuildContext context) {
    // Your existing build method here
    return Container(); // Replace with your actual widget tree
  }
}

// Example: Call this function after picking a customer to navigate to EstimateBuilderScreen
void navigateToEstimateBuilderScreen(BuildContext context, dynamic selectedCustomer, List priceBook) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => EstimateBuilderScreen(
        jobId: UniqueKey().toString(),
        jobTitle: selectedCustomer.name,
        jobType: 'Estimate',
        priceBook: priceBook, // This should be the up-to-date list!
        currentEstimate: null,
      ),
    ),
  );
}