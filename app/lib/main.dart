import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const CoupleCopilotApp());
}

class CoupleCopilotApp extends StatelessWidget {
  const CoupleCopilotApp({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme =
        ColorScheme.fromSeed(seedColor: const Color(0xFFE66FA6));
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Couple Copilot',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: colorScheme,
        scaffoldBackgroundColor: const Color(0xFFF8F6F8),
        appBarTheme: const AppBarTheme(centerTitle: false),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        ),
      ),
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
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _HeroCard(
              title: '今天也一起把关系变好一点',
              subtitle: 'Daily logging · Conflict mediation · Weekly check',
              icon: Icons.favorite_rounded,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            _EntryCard(
              title: '日常记录',
              subtitle: 'Daily journaling timeline',
              icon: Icons.book_rounded,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const DailyPage()),
                );
              },
            ),
            const SizedBox(height: 12),
            const _EntryCard(
              title: '冲突调解',
              subtitle: 'Conflict mediation workflow (next)',
              icon: Icons.balance_rounded,
            ),
            const SizedBox(height: 12),
            const _EntryCard(
              title: '每周体检',
              subtitle: 'Weekly relationship health check (next)',
              icon: Icons.monitor_heart_rounded,
            ),
          ],
        ),
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
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('日常记录'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loading ? null : _loadTimeline,
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('创建记录', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _coupleIdCtrl,
                    decoration: const InputDecoration(labelText: 'couple_id'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _authorIdCtrl,
                    decoration:
                        const InputDecoration(labelText: 'author_user_id'),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: _eventType,
                    items: const [
                      DropdownMenuItem(
                          value: 'interaction', child: Text('interaction')),
                      DropdownMenuItem(value: 'date', child: Text('date')),
                      DropdownMenuItem(value: 'gift', child: Text('gift')),
                      DropdownMenuItem(value: 'other', child: Text('other')),
                    ],
                    onChanged: (v) =>
                        setState(() => _eventType = v ?? 'interaction'),
                    decoration: const InputDecoration(labelText: 'event_type'),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.mood_rounded),
                        const SizedBox(width: 8),
                        const Text('mood'),
                        Expanded(
                          child: Slider(
                            value: _moodScore.toDouble(),
                            min: 1,
                            max: 5,
                            divisions: 4,
                            label: '$_moodScore',
                            onChanged: (v) =>
                                setState(() => _moodScore = v.toInt()),
                          ),
                        ),
                        Text('$_moodScore',
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _contentCtrl,
                    decoration: const InputDecoration(labelText: 'content'),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _mediaUrlsCtrl,
                    decoration: const InputDecoration(
                      labelText: 'media urls (逗号或换行分隔)',
                      hintText: 'http://.../a.jpg\nhttp://.../b.mp4',
                    ),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _loading ? null : _createDaily,
                      icon: const Icon(Icons.send_rounded),
                      label: Text(_loading ? '处理中...' : '提交记录'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Text('时间线', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                Text('${_items.length} 条',
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 8),
            if (_items.isEmpty)
              const _EmptyStateCard(text: '还没有记录，先创建第一条吧')
            else
              ..._items.map((item) {
                final medias = (item['media'] as List?) ?? [];
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            _Tag(
                                text:
                                    item['event_type']?.toString() ?? 'other'),
                            const SizedBox(width: 8),
                            _Tag(text: 'mood ${item['mood_score']}'),
                            const Spacer(),
                            if ((item['memos_status'] ?? '')
                                .toString()
                                .isNotEmpty)
                              Text(
                                'MemOS: ${item['memos_status']}',
                                style: TextStyle(
                                  color: item['memos_status'] == 'synced'
                                      ? Colors.green
                                      : Colors.orange,
                                  fontSize: 12,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(item['content']?.toString() ?? ''),
                        if (medias.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: medias.map((m) {
                              final mm = Map<String, dynamic>.from(m as Map);
                              final type =
                                  mm['media_type']?.toString() ?? 'image';
                              return Chip(
                                avatar: Icon(
                                  type == 'video'
                                      ? Icons.videocam_rounded
                                      : Icons.image_rounded,
                                  size: 16,
                                ),
                                label: Text(type),
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
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;

  const _HeroCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          colors: [color.withValues(alpha: 0.9), color.withValues(alpha: 0.65)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: Colors.white,
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(subtitle,
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EntryCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback? onTap;

  const _EntryCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: CircleAvatar(
          radius: 18,
          child: Icon(icon, size: 18),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle),
        trailing:
            onTap != null ? const Icon(Icons.chevron_right_rounded) : null,
      ),
    );
  }
}

class _EmptyStateCard extends StatelessWidget {
  final String text;

  const _EmptyStateCard({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
    );
  }
}

class _Tag extends StatelessWidget {
  final String text;

  const _Tag({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .primaryContainer
            .withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(text,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}
