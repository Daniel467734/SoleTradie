import 'package:flutter/material.dart';

void main() => runApp(MaterialApp(home: TestTile()));

class TestTile extends StatelessWidget {
  const TestTile({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListTile(
        title: Text('Test'),
        onTap: () => print('Tapped'),
      ),
    );
  }
}