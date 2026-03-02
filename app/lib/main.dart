import 'package:dio/dio.dart';
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
        children: [
          ListTile(
            title: const Text('日常记录'),
            subtitle: const Text('Daily journaling timeline'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const DailyPage()));
            },
          ),
          const ListTile(
            title: Text('冲突调解'),
            subtitle: Text('Conflict mediation workflow (next)'),
          ),
          const ListTile(
            title: Text('每周体检'),
            subtitle: Text('Weekly relationship health check (next)'),
          ),
        ],
      ),
    );
  }
}

class DailyPage extends StatefulWidget {
  const DailyPage({super.key});

  @override
  State<DailyPage> createState() => _DailyPageState();
}

class _DailyPageState extends State<DailyPage> {
  final _dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:8000'));

  final _coupleIdCtrl = TextEditingController();
  final _authorIdCtrl = TextEditingController();
  final _contentCtrl = TextEditingController();
  final _mediaUrlsCtrl = TextEditingController();

  int _moodScore = 4;
  String _eventType = 'interaction';
  bool _loading = false;
  List<Map<String, dynamic>> _items = [];

  @override
  void dispose() {
    _coupleIdCtrl.dispose();
    _authorIdCtrl.dispose();
    _contentCtrl.dispose();
    _mediaUrlsCtrl.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _buildMediaListFromInput(String raw) {
    final urls = raw
        .split(RegExp(r'[\n,]'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    return urls.asMap().entries.map((entry) {
      final idx = entry.key;
      final url = entry.value;
      final lower = url.toLowerCase();
      final isVideo = lower.endsWith('.mp4') ||
          lower.endsWith('.mov') ||
          lower.endsWith('.webm');
      return {
        'media_type': isVideo ? 'video' : 'image',
        'url': url,
        'sort_order': idx,
      };
    }).toList();
  }

  Future<void> _createDaily() async {
    if (_coupleIdCtrl.text.isEmpty ||
        _authorIdCtrl.text.isEmpty ||
        _contentCtrl.text.isEmpty) {
      _toast('couple_id / author_user_id / content 不能为空');
      return;
    }

    setState(() => _loading = true);
    try {
      final media = _buildMediaListFromInput(_mediaUrlsCtrl.text);
      await _dio.post(
        '/daily',
        data: {
          'couple_id': _coupleIdCtrl.text.trim(),
          'author_user_id': _authorIdCtrl.text.trim(),
          'event_type': _eventType,
          'mood_score': _moodScore,
          'content': _contentCtrl.text.trim(),
          'media': media,
        },
      );
      _contentCtrl.clear();
      _mediaUrlsCtrl.clear();
      _toast('记录成功');
      await _loadTimeline();
    } on DioException catch (e) {
      _toast('提交失败: ${e.response?.data ?? e.message}');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadTimeline() async {
    if (_coupleIdCtrl.text.isEmpty) {
      _toast('先输入 couple_id');
      return;
    }

    setState(() => _loading = true);
    try {
      final resp = await _dio.get(
        '/daily/timeline',
        queryParameters: {'couple_id': _coupleIdCtrl.text.trim(), 'limit': 30},
      );

      final items = (resp.data['items'] as List?) ?? [];
      setState(() {
        _items = items.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      });
    } on DioException catch (e) {
      _toast('加载失败: ${e.response?.data ?? e.message}');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('日常记录'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _loadTimeline,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _coupleIdCtrl,
            decoration: const InputDecoration(labelText: 'couple_id'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _authorIdCtrl,
            decoration: const InputDecoration(labelText: 'author_user_id'),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _eventType,
            items: const [
              DropdownMenuItem(
                value: 'interaction',
                child: Text('interaction'),
              ),
              DropdownMenuItem(value: 'date', child: Text('date')),
              DropdownMenuItem(value: 'gift', child: Text('gift')),
              DropdownMenuItem(value: 'other', child: Text('other')),
            ],
            onChanged: (v) => setState(() => _eventType = v ?? 'interaction'),
            decoration: const InputDecoration(labelText: 'event_type'),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('mood_score'),
              Expanded(
                child: Slider(
                  value: _moodScore.toDouble(),
                  min: 1,
                  max: 5,
                  divisions: 4,
                  label: '$_moodScore',
                  onChanged: (v) => setState(() => _moodScore = v.toInt()),
                ),
              ),
              Text('$_moodScore'),
            ],
          ),
          TextField(
            controller: _contentCtrl,
            decoration: const InputDecoration(labelText: 'content'),
            maxLines: 3,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _mediaUrlsCtrl,
            decoration: const InputDecoration(
              labelText: 'media urls (逗号或换行分隔)',
              hintText: 'http://.../a.jpg\nhttp://.../b.mp4',
            ),
            maxLines: 3,
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _loading ? null : _createDaily,
            icon: const Icon(Icons.send),
            label: Text(_loading ? '处理中...' : '提交记录'),
          ),
          const SizedBox(height: 20),
          const Divider(),
          const Text('时间线', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ..._items.map((item) {
            final medias = (item['media'] as List?) ?? [];
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${item['event_type']} · mood ${item['mood_score']}'),
                    const SizedBox(height: 4),
                    Text(item['content']?.toString() ?? ''),
                    if ((item['memos_status'] ?? '').toString().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text('MemOS: ${item['memos_status']}'),
                    ],
                    if (medias.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: medias.map((m) {
                          final mm = Map<String, dynamic>.from(m as Map);
                          return Chip(
                            label: Text('${mm['media_type']}: ${mm['url']}'),
                          );
                        }).toList(),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
