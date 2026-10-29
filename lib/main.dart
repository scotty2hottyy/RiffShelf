import 'package:flutter/material.dart';

void main() => runApp(const RiffShelfApp());

class RiffShelfApp extends StatelessWidget {
  const RiffShelfApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'RiffShelf',
      home: Scaffold(
        body: Center(child: Text('Welcome to RiffShelf')),
      ),
    );
  }
}
