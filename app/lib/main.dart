import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const CoupleCopilotApp());
}

class CoupleCopilotApp extends StatelessWidget {
  const CoupleCopilotApp({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(seedColor: const Color(0xFFE66FA6));
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Couple Copilot',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: colorScheme,
        scaffoldBackgroundColor: const Color(0xFFF8F6F8),
        appBarTheme: const AppBarTheme(centerTitle: false),
      ),
      home: const AppShell(),
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

enum AppStage { loading, needLogin, needBind, ready }

class _AppShellState extends State<AppShell> {
  final _api = ApiClient();
  AppStage _stage = AppStage.loading;
  bool _busy = false;
  String? _nickname;
  String? _partnerNickname;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    setState(() => _busy = true);
    try {
      await _api.loadSession();
      if (_api.accessToken == null && _api.refreshToken == null) {
        setState(() => _stage = AppStage.needLogin);
        return;
      }

      var me = await _api.me();
      if (me == null) {
        final refreshed = await _api.refresh();
        if (!refreshed) {
          await _api.clearSession();
          setState(() => _stage = AppStage.needLogin);
          return;
        }
        me = await _api.me();
      }

      if (me == null) {
        await _api.clearSession();
        setState(() => _stage = AppStage.needLogin);
        return;
      }

      final meData = me;
      _nickname = meData.user.nickname;
      _partnerNickname = meData.relationship.partnerNickname;
      setState(() {
        _stage = meData.relationship.status == 'bound' ? AppStage.ready : AppStage.needBind;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _onLoginSuccess(LoginResult result) async {
    await _api.saveSession(
      accessToken: result.accessToken,
      refreshToken: result.refreshToken,
    );
    _nickname = result.user.nickname;
    setState(() {
      _stage = result.user.bindStatus == 'bound' ? AppStage.ready : AppStage.needBind;
    });
  }

  Future<void> _refreshProfile() async {
    final me = await _api.me();
    if (me == null) return;
    _nickname = me.user.nickname;
    _partnerNickname = me.relationship.partnerNickname;
    setState(() {
      _stage = me.relationship.status == 'bound' ? AppStage.ready : AppStage.needBind;
    });
  }

  Future<void> _logout() async {
    await _api.clearSession();
    setState(() {
      _nickname = null;
      _partnerNickname = null;
      _stage = AppStage.needLogin;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_stage == AppStage.loading || _busy) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    switch (_stage) {
      case AppStage.needLogin:
        return LoginPage(api: _api, onSuccess: _onLoginSuccess);
      case AppStage.needBind:
        return BindPage(
          api: _api,
          nickname: _nickname ?? '你',
          onBound: _refreshProfile,
          onLogout: _logout,
        );
      case AppStage.ready:
        return HomePage(
          nickname: _nickname ?? '你',
          partnerNickname: _partnerNickname,
          api: _api,
          onProfileChanged: _refreshProfile,
          onLogout: _logout,
        );
      case AppStage.loading:
        return const SizedBox.shrink();
    }
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.api, required this.onSuccess});

  final ApiClient api;
  final Future<void> Function(LoginResult result) onSuccess;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _accountCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  String _type = 'email';
  bool _loading = false;
  String? _devCode;

  @override
  void dispose() {
    _accountCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    if (_accountCtrl.text.trim().isEmpty) {
      _toast('请输入邮箱或手机号');
      return;
    }
    setState(() => _loading = true);
    try {
      final code = await widget.api.sendCode(_accountCtrl.text.trim(), _type);
      setState(() => _devCode = code);
      _toast('验证码已发送');
    } on DioException catch (e) {
      _toast('发送失败：${e.response?.data ?? e.message}');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _login() async {
    if (_accountCtrl.text.trim().isEmpty || _codeCtrl.text.trim().isEmpty) {
      _toast('请输入账号和验证码');
      return;
    }
    setState(() => _loading = true);
    try {
      final result = await widget.api.login(_accountCtrl.text.trim(), _codeCtrl.text.trim());
      await widget.onSuccess(result);
    } on DioException catch (e) {
      _toast('登录失败：${e.response?.data ?? e.message}');
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
      appBar: AppBar(title: const Text('登录')), 
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('先登录，再绑定伴侣，不需要填写任何内部ID。'),
            const SizedBox(height: 16),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'email', label: Text('邮箱')),
                ButtonSegment(value: 'phone', label: Text('手机号')),
              ],
              selected: {_type},
              onSelectionChanged: (v) => setState(() => _type = v.first),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _accountCtrl,
              decoration: InputDecoration(
                labelText: _type == 'email' ? '邮箱' : '手机号',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _codeCtrl,
                    decoration: const InputDecoration(
                      labelText: '验证码',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton(
                  onPressed: _loading ? null : _sendCode,
                  child: const Text('发送验证码'),
                ),
              ],
            ),
            if (_devCode != null) ...[
              const SizedBox(height: 10),
              Text('开发环境验证码：$_devCode', style: const TextStyle(color: Colors.orange)),
            ],
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _loading ? null : _login,
              icon: const Icon(Icons.login_rounded),
              label: Text(_loading ? '登录中...' : '登录'),
            )
          ],
        ),
      ),
    );
  }
}

class BindPage extends StatefulWidget {
  const BindPage({
    super.key,
    required this.api,
    required this.nickname,
    required this.onBound,
    required this.onLogout,
  });

  final ApiClient api;
  final String nickname;
  final Future<void> Function() onBound;
  final Future<void> Function() onLogout;

  @override
  State<BindPage> createState() => _BindPageState();
}

class _BindPageState extends State<BindPage> {
  final _inviteCodeCtrl = TextEditingController();
  bool _loading = false;
  String? _myInviteCode;
  DateTime? _expiresAt;

  @override
  void dispose() {
    _inviteCodeCtrl.dispose();
    super.dispose();
  }

  Future<void> _createInvite() async {
    setState(() => _loading = true);
    try {
      final result = await widget.api.createInvite();
      setState(() {
        _myInviteCode = result.code;
        _expiresAt = result.expiresAt;
      });
    } on DioException catch (e) {
      _toast('创建失败：${e.response?.data ?? e.message}');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _joinInvite() async {
    final code = _inviteCodeCtrl.text.trim();
    if (code.isEmpty) {
      _toast('请输入邀请码');
      return;
    }
    setState(() => _loading = true);
    try {
      await widget.api.joinInvite(code);
      await widget.onBound();
    } on DioException catch (e) {
      _toast('绑定失败：${e.response?.data ?? e.message}');
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
        title: const Text('关系绑定'),
        actions: [
          IconButton(
            tooltip: '退出登录',
            onPressed: _loading ? null : widget.onLogout,
            icon: const Icon(Icons.logout_rounded),
          )
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('嗨，${widget.nickname}。先完成情侣绑定后再进入首页。'),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('方式A：邀请伴侣'),
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: _loading ? null : _createInvite,
                      child: const Text('生成邀请码'),
                    ),
                    if (_myInviteCode != null) ...[
                      const SizedBox(height: 10),
                      SelectableText('邀请码：$_myInviteCode', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      if (_expiresAt != null)
                        Text('有效期至：${_expiresAt!.toLocal()}'),
                    ]
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('方式B：输入邀请码'),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _inviteCodeCtrl,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        hintText: '例如 A1B2C3',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      onPressed: _loading ? null : _joinInvite,
                      icon: const Icon(Icons.link_rounded),
                      label: Text(_loading ? '处理中...' : '确认绑定'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({
    super.key,
    required this.nickname,
    required this.partnerNickname,
    required this.api,
    required this.onProfileChanged,
    required this.onLogout,
  });

  final String nickname;
  final String? partnerNickname;
  final ApiClient api;
  final Future<void> Function() onProfileChanged;
  final Future<void> Function() onLogout;

  Future<void> _unbind(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('确认解绑？'),
        content: const Text('解绑后将回到绑定页。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('确认')),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await api.unbind();
      await onProfileChanged();
    } on DioException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('解绑失败：${e.response?.data ?? e.message}')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Couple Relationship Copilot'),
        actions: [
          IconButton(
            tooltip: '解绑关系',
            onPressed: () => _unbind(context),
            icon: const Icon(Icons.link_off_rounded),
          ),
          IconButton(
            tooltip: '退出登录',
            onPressed: onLogout,
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _HeroCard(
              title: '你好，$nickname',
              subtitle: partnerNickname == null ? '已登录' : '已与 $partnerNickname 绑定',
              icon: Icons.favorite_rounded,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            const _EntryCard(
              title: '日常记录',
              subtitle: '下一步接接口改为自动使用登录态',
              icon: Icons.book_rounded,
            ),
            const SizedBox(height: 12),
            const _EntryCard(
              title: '冲突调解',
              subtitle: '下一步去掉手填ID后接入',
              icon: Icons.balance_rounded,
            ),
            const SizedBox(height: 12),
            const _EntryCard(
              title: '每周体检',
              subtitle: 'MVP 预留',
              icon: Icons.monitor_heart_rounded,
            ),
          ],
        ),
      ),
    );
  }
}

class ApiClient {
  ApiClient()
      : _dio = Dio(
          BaseOptions(
            baseUrl: 'http://127.0.0.1:8000',
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 15),
          ),
        );

  final Dio _dio;
  String? accessToken;
  String? refreshToken;

  Future<void> loadSession() async {
    final prefs = await SharedPreferences.getInstance();
    accessToken = prefs.getString('access_token');
    refreshToken = prefs.getString('refresh_token');
  }

  Future<void> saveSession({required String accessToken, required String refreshToken}) async {
    this.accessToken = accessToken;
    this.refreshToken = refreshToken;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('access_token', accessToken);
    await prefs.setString('refresh_token', refreshToken);
  }

  Future<void> clearSession() async {
    accessToken = null;
    refreshToken = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('access_token');
    await prefs.remove('refresh_token');
  }

  Map<String, String> _authHeaders() {
    if (accessToken == null) return {};
    return {'Authorization': 'Bearer $accessToken'};
  }

  Future<String?> sendCode(String account, String type) async {
    final resp = await _dio.post('/auth/send-code', data: {'account': account, 'type': type});
    return resp.data['dev_code']?.toString();
  }

  Future<LoginResult> login(String account, String code) async {
    final resp = await _dio.post('/auth/login', data: {'account': account, 'code': code});
    return LoginResult.fromJson(Map<String, dynamic>.from(resp.data as Map));
  }

  Future<bool> refresh() async {
    if (refreshToken == null) return false;
    try {
      final resp = await _dio.post('/auth/refresh', data: {'refresh_token': refreshToken});
      accessToken = resp.data['access_token']?.toString();
      final prefs = await SharedPreferences.getInstance();
      if (accessToken != null) {
        await prefs.setString('access_token', accessToken!);
      }
      return accessToken != null;
    } on DioException {
      return false;
    }
  }

  Future<MeResult?> me() async {
    if (accessToken == null) return null;
    try {
      final resp = await _dio.get('/auth/me', options: Options(headers: _authHeaders()));
      return MeResult.fromJson(Map<String, dynamic>.from(resp.data as Map));
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) return null;
      rethrow;
    }
  }

  Future<InviteResult> createInvite() async {
    final resp = await _dio.post('/relationship/invite', options: Options(headers: _authHeaders()));
    return InviteResult.fromJson(Map<String, dynamic>.from(resp.data as Map));
  }

  Future<void> joinInvite(String code) async {
    await _dio.post(
      '/relationship/join',
      data: {'invite_code': code},
      options: Options(headers: _authHeaders()),
    );
  }

  Future<void> unbind() async {
    await _dio.post(
      '/relationship/unbind',
      data: {'confirm_text': 'UNBIND'},
      options: Options(headers: _authHeaders()),
    );
  }
}

class LoginResult {
  LoginResult({
    required this.accessToken,
    required this.refreshToken,
    required this.user,
  });

  final String accessToken;
  final String refreshToken;
  final LoginUser user;

  factory LoginResult.fromJson(Map<String, dynamic> json) {
    return LoginResult(
      accessToken: json['access_token'].toString(),
      refreshToken: json['refresh_token'].toString(),
      user: LoginUser.fromJson(Map<String, dynamic>.from(json['user'] as Map)),
    );
  }
}

class LoginUser {
  LoginUser({required this.nickname, required this.bindStatus});

  final String nickname;
  final String bindStatus;

  factory LoginUser.fromJson(Map<String, dynamic> json) {
    return LoginUser(
      nickname: json['nickname']?.toString() ?? '',
      bindStatus: json['bind_status']?.toString() ?? 'unbound',
    );
  }
}

class MeResult {
  MeResult({required this.user, required this.relationship});

  final MeUser user;
  final RelationshipInfo relationship;

  factory MeResult.fromJson(Map<String, dynamic> json) {
    return MeResult(
      user: MeUser.fromJson(Map<String, dynamic>.from(json['user'] as Map)),
      relationship: RelationshipInfo.fromJson(Map<String, dynamic>.from(json['relationship'] as Map)),
    );
  }
}

class MeUser {
  MeUser({required this.nickname});

  final String nickname;

  factory MeUser.fromJson(Map<String, dynamic> json) {
    return MeUser(nickname: json['nickname']?.toString() ?? '');
  }
}

class RelationshipInfo {
  RelationshipInfo({required this.status, this.partnerNickname});

  final String status;
  final String? partnerNickname;

  factory RelationshipInfo.fromJson(Map<String, dynamic> json) {
    return RelationshipInfo(
      status: json['status']?.toString() ?? 'unbound',
      partnerNickname: json['partner_nickname']?.toString(),
    );
  }
}

class InviteResult {
  InviteResult({required this.code, required this.expiresAt});

  final String code;
  final DateTime? expiresAt;

  factory InviteResult.fromJson(Map<String, dynamic> json) {
    return InviteResult(
      code: json['invite_code']?.toString() ?? '',
      expiresAt: json['expires_at'] == null ? null : DateTime.tryParse(json['expires_at'].toString()),
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
                Text(subtitle, style: const TextStyle(color: Colors.white70, fontSize: 12)),
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

  const _EntryCard({required this.title, required this.subtitle, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: CircleAvatar(radius: 18, child: Icon(icon, size: 18)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle),
      ),
    );
  }
}
