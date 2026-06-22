import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:http/http.dart' as http;

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _maskedKey = '—';
  bool _hasKey = false;
  bool _isSyncing = false;
  bool _isFetchingCredits = false;
  String _syncStatus = '';
  Color _syncColor = Colors.transparent;

  // remove.bg credit info
  int? _creditsTotal;
  int? _creditsSubscription;
  int? _creditsPayg;
  int? _freeCalls;

  @override
  void initState() {
    super.initState();
    _loadAndSync();
  }

  /// Mask an API key — show first 4 chars, then ••••, then last 4 chars.
  String _maskKey(String key) {
    if (key.length <= 8) return '••••••••';
    final start = key.substring(0, 4);
    final end = key.substring(key.length - 4);
    return '$start ••••••••••••• $end';
  }

  Future<String> _getStoredKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('REMOVE_BG_API_KEY') ?? '';
  }

  Future<void> _loadKey() async {
    final key = await _getStoredKey();
    if (!mounted) return;
    setState(() {
      _hasKey = key.isNotEmpty;
      _maskedKey = key.isNotEmpty ? _maskKey(key) : '(Not synced yet)';
    });
  }

  Future<void> _loadAndSync() async {
    await _loadKey();
    await _syncFromCloud(silent: true);
  }

  /// Fetch account credits from remove.bg account API.
  Future<void> _fetchCredits() async {
    final key = await _getStoredKey();
    if (key.isEmpty) return;

    setState(() => _isFetchingCredits = true);
    try {
      final response = await http.get(
        Uri.parse('https://api.remove.bg/v1.0/account'),
        headers: {'X-Api-Key': key},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final attrs = data['data']['attributes'] as Map<String, dynamic>;
        final credits = attrs['credits'] as Map<String, dynamic>;
        final api = attrs['api'] as Map<String, dynamic>? ?? {};
        if (mounted) {
          setState(() {
            _creditsTotal = credits['total'] as int?;
            _creditsSubscription = credits['subscription'] as int?;
            _creditsPayg = credits['payg'] as int?;
            _freeCalls = api['free_calls'] as int?;
          });
        }
      }
    } catch (e) {
      debugPrint('Failed to fetch remove.bg credits: $e');
    } finally {
      if (mounted) setState(() => _isFetchingCredits = false);
    }
  }

  Future<void> _syncFromCloud({bool silent = false}) async {
    setState(() {
      _isSyncing = true;
      _syncStatus = '';
    });

    try {
      final response = await http.get(
        Uri.parse('https://panditji-printing-panditjihotel.vercel.app/config.json'),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final cloudKey = data['remove_bg_api_key']?.toString() ?? '';
        if (cloudKey.isNotEmpty) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('REMOVE_BG_API_KEY', cloudKey);
          if (mounted && !silent) {
            setState(() {
              _syncStatus = '✓ Synced successfully';
              _syncColor = Colors.green;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('API key synced!', style: TextStyle(fontWeight: FontWeight.bold)),
                backgroundColor: Colors.green.shade700,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        } else {
          if (mounted && !silent) {
            setState(() {
              _syncStatus = 'No key found in config';
              _syncColor = Colors.orange;
            });
          }
        }
      } else {
        throw Exception('HTTP ${response.statusCode}');
      }
    } catch (e) {
      if (mounted && !silent) {
        setState(() {
          _syncStatus = 'Sync failed — check internet';
          _syncColor = Colors.red;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sync failed. Check internet.'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
      await _loadKey();
      await _fetchCredits(); // Always refresh credit count after sync
    }
  }

  /// Credit bar colour: green > 20, orange 5-20, red < 5
  Color _creditColor(int? total) {
    if (total == null) return Colors.grey;
    if (total > 20) return Colors.green;
    if (total >= 5) return Colors.orange;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final totalCredits = _creditsTotal ?? 0;
    final subCredits = _creditsSubscription ?? 0;
    final paygCredits = _creditsPayg ?? 0;
    final freeLeft = _freeCalls;
    final hasCreditsData = _creditsTotal != null;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          const Text('Settings', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
            'The remove.bg API key is synced automatically from the cloud whenever the app starts.',
            style: TextStyle(color: Colors.grey.shade600, height: 1.5),
          ),
          const SizedBox(height: 24),

          // ── API Key Card ─────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.withAlpha(50)),
              boxShadow: [BoxShadow(color: Colors.black.withAlpha(13), blurRadius: 10, offset: const Offset(0, 4))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: (_hasKey ? Colors.green : Colors.orange).withAlpha(30),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(LucideIcons.key, size: 18, color: _hasKey ? Colors.green : Colors.orange),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Remove.bg API Key', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      Text(
                        _hasKey ? 'Active' : 'Not configured',
                        style: TextStyle(
                          fontSize: 12,
                          color: _hasKey ? Colors.green : Colors.orange,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  _isSyncing
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : IconButton(
                          icon: const Icon(LucideIcons.refresh_cw, size: 20),
                          tooltip: 'Sync from cloud',
                          onPressed: () => _syncFromCloud(silent: false),
                        ),
                ]),
                const SizedBox(height: 16),

                // Masked key display — SelectionContainer.disabled blocks copy
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withAlpha(10) : Colors.black.withAlpha(6),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey.withAlpha(40)),
                  ),
                  child: Row(
                    children: [
                      const Icon(LucideIcons.lock, size: 14, color: Colors.grey),
                      const SizedBox(width: 8),
                      SelectionContainer.disabled(
                        child: Text(
                          _maskedKey,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 13,
                            letterSpacing: 1.5,
                            color: _hasKey ? cs.onSurface.withAlpha(200) : Colors.grey,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                if (_syncStatus.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(
                        _syncColor == Colors.green ? LucideIcons.circle_check : LucideIcons.circle_alert,
                        size: 14, color: _syncColor,
                      ),
                      const SizedBox(width: 6),
                      Text(_syncStatus, style: TextStyle(fontSize: 12, color: _syncColor, fontWeight: FontWeight.w500)),
                    ],
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ── Credits Card ─────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: hasCreditsData
                    ? _creditColor(totalCredits).withAlpha(80)
                    : Colors.grey.withAlpha(50),
              ),
              boxShadow: [BoxShadow(color: Colors.black.withAlpha(13), blurRadius: 10, offset: const Offset(0, 4))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _creditColor(_creditsTotal).withAlpha(25),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(LucideIcons.zap, size: 18, color: _creditColor(_creditsTotal)),
                  ),
                  const SizedBox(width: 12),
                  const Text('API Credits Remaining', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const Spacer(),
                  if (_isFetchingCredits)
                    const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  else
                    IconButton(
                      icon: const Icon(LucideIcons.refresh_cw, size: 18),
                      tooltip: 'Refresh credits',
                      onPressed: _hasKey ? _fetchCredits : null,
                    ),
                ]),
                const SizedBox(height: 16),

                if (!hasCreditsData && !_isFetchingCredits)
                  Text(
                    _hasKey ? 'Tap ↻ to load credit info' : 'Sync a key first to see credits',
                    style: const TextStyle(color: Colors.grey, fontSize: 13),
                  )
                else if (hasCreditsData) ...[
                  // Total credits large display
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '$totalCredits',
                        style: TextStyle(
                          fontSize: 48,
                          fontWeight: FontWeight.bold,
                          color: _creditColor(_creditsTotal),
                          height: 1,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          'credits left',
                          style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Breakdown chips
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      if (subCredits > 0)
                        _buildCreditChip('Subscription', subCredits, Colors.blue),
                      if (paygCredits > 0)
                        _buildCreditChip('Pay-as-you-go', paygCredits, Colors.purple),
                      if (freeLeft != null && freeLeft > 0)
                        _buildCreditChip('Free calls', freeLeft, Colors.green),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Warning if low
                  if (totalCredits < 5)
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.red.withAlpha(20),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.withAlpha(60)),
                      ),
                      child: Row(children: [
                        const Icon(LucideIcons.triangle_alert, color: Colors.red, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            totalCredits == 0
                                ? 'Credits exhausted! Update your API key in config.json.'
                                : 'Only $totalCredits credit${totalCredits == 1 ? '' : 's'} left — top up soon.',
                            style: const TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.w500),
                          ),
                        ),
                      ]),
                    )
                  else if (totalCredits < 20)
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.orange.withAlpha(20),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange.withAlpha(60)),
                      ),
                      child: Row(children: [
                        const Icon(LucideIcons.info, color: Colors.orange, size: 16),
                        const SizedBox(width: 8),
                        Text(
                          '$totalCredits credits remaining — consider renewing soon.',
                          style: const TextStyle(color: Colors.orange, fontSize: 12, fontWeight: FontWeight.w500),
                        ),
                      ]),
                    ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ── Info Banner ──────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.withAlpha(20),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue.withAlpha(60)),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(LucideIcons.info, color: Colors.blue, size: 16),
                  SizedBox(width: 8),
                  Text('How auto-sync works', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.blue)),
                ]),
                SizedBox(height: 10),
                Text(
                  '• Key is fetched from Vercel every time the app loads\n'
                  '• No manual entry — just update config.json & push to GitHub\n'
                  '• Background removal uses remove.bg with AI-quality cutouts\n'
                  '• Falls back to local chroma-key if offline or credits run out',
                  style: TextStyle(height: 1.8, fontSize: 13, color: Colors.blue),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ── How to update remotely ───────────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.withAlpha(40)),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(LucideIcons.terminal, size: 16),
                  SizedBox(width: 8),
                  Text('Updating the key remotely', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                ]),
                SizedBox(height: 12),
                Text(
                  '1. Open  Panditji Printing Services/public/config.json\n'
                  '2. Update the "remove_bg_api_key" value\n'
                  '3. Push to GitHub → Vercel auto-deploys in ~30s\n'
                  '4. Reopen this app — key syncs automatically on startup',
                  style: TextStyle(height: 2.0, fontSize: 13, color: Colors.grey),
                ),
              ],
            ),
          ),

          const SizedBox(height: 48),
        ],
      ),
    );
  }

  Widget _buildCreditChip(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(
            '$label: $count',
            style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
