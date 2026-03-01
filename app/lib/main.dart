import 'package:flutter/material.dart';

void main() {
  runApp(const CoupleCopilotApp());
}

class CoupleCopilotApp extends StatelessWidget {
  const CoupleCopilotApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Couple Copilot',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.pink),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Couple Relationship Copilot')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          ListTile(title: Text('日常记录'), subtitle: Text('Daily journaling timeline')),
          ListTile(title: Text('冲突调解'), subtitle: Text('Conflict mediation workflow')),
          ListTile(title: Text('每周体检'), subtitle: Text('Weekly relationship health check')),
        ],
      ),
    );
  }
}
