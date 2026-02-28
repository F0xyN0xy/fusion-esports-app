import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'config.dart';
import 'main.dart';

class FeedbackSystem {
  static const String _feedbackWebhook = '${Config.baseUrl}/api/feedback';

  /// Show feedback dialog
  static void showFeedbackDialog(BuildContext context, {DiscordUser? user}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _FeedbackSheet(user: user),
    );
  }

  /// Show bug report dialog
  static void showBugReportDialog(BuildContext context,
      {DiscordUser? user, String? currentScreen}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) =>
          _BugReportSheet(user: user, currentScreen: currentScreen),
    );
  }
}

class _FeedbackSheet extends StatefulWidget {
  final DiscordUser? user;

  const _FeedbackSheet({this.user});

  @override
  State<_FeedbackSheet> createState() => _FeedbackSheetState();
}

class _FeedbackSheetState extends State<_FeedbackSheet> {
  final _formKey = GlobalKey<FormState>();
  final _feedbackController = TextEditingController();
  String _category = 'general';
  bool _isSubmitting = false;
  double _rating = 0;

  final List<Map<String, dynamic>> _categories = [
    {'id': 'general', 'name': 'General Feedback', 'icon': Icons.chat_bubble},
    {'id': 'feature', 'name': 'Feature Request', 'icon': Icons.lightbulb},
    {'id': 'ui', 'name': 'UI/Design', 'icon': Icons.palette},
    {'id': 'performance', 'name': 'Performance', 'icon': Icons.speed},
  ];

  @override
  void dispose() {
    _feedbackController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    try {
      final payload = {
        'type': 'feedback',
        'timestamp': DateTime.now().toIso8601String(),
        'userId': widget.user?.id,
        'username': widget.user?.username,
        'category': _category,
        'rating': _rating,
        'message': _feedbackController.text,
      };

      final response = await http.post(
        Uri.parse(FeedbackSystem._feedbackWebhook),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200) {
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Thanks for your feedback! 🚀'),
              backgroundColor: Color(0xFF6C63FF),
            ),
          );
        }
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF12121A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        left: 20,
        right: 20,
        top: 20,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Send Feedback',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: Colors.white54),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _categories.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final cat = _categories[index];
                  final isSelected = _category == cat['id'];

                  return GestureDetector(
                    onTap: () => setState(() => _category = cat['id']),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFF6C63FF).withOpacity(0.2)
                            : const Color(0xFF1A1A2E),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isSelected
                              ? const Color(0xFF6C63FF)
                              : Colors.white12,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            cat['icon'],
                            size: 16,
                            color: isSelected
                                ? const Color(0xFF6C63FF)
                                : Colors.white54,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            cat['name'],
                            style: TextStyle(
                              color: isSelected ? Colors.white : Colors.white54,
                              fontSize: 12,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text(
                  'App Rating:',
                  style: TextStyle(color: Colors.white54, fontSize: 14),
                ),
                const SizedBox(width: 12),
                ...List.generate(5, (index) {
                  return GestureDetector(
                    onTap: () => setState(() => _rating = index + 1),
                    child: Icon(
                      index < _rating ? Icons.star : Icons.star_border,
                      color: index < _rating ? Colors.amber : Colors.white24,
                      size: 24,
                    ),
                  );
                }),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _feedbackController,
              maxLines: 4,
              maxLength: 500,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Tell us what you think...',
                hintStyle: const TextStyle(color: Colors.white30),
                filled: true,
                fillColor: const Color(0xFF1A1A2E),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF6C63FF)),
                ),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter your feedback';
                }
                if (value.length < 10) {
                  return 'Feedback must be at least 10 characters';
                }
                return null;
              },
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6C63FF),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  disabledBackgroundColor:
                      const Color(0xFF6C63FF).withOpacity(0.3),
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Text(
                        'Send Feedback',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BugReportSheet extends StatefulWidget {
  final DiscordUser? user;
  final String? currentScreen;

  const _BugReportSheet({this.user, this.currentScreen});

  @override
  State<_BugReportSheet> createState() => _BugReportSheetState();
}

class _BugReportSheetState extends State<_BugReportSheet> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _stepsController = TextEditingController();
  String _severity = 'medium';
  bool _isSubmitting = false;

  final List<Map<String, dynamic>> _severityLevels = [
    {'id': 'low', 'name': 'Low', 'color': Colors.green, 'desc': 'Minor issue'},
    {
      'id': 'medium',
      'name': 'Medium',
      'color': Colors.orange,
      'desc': 'Affects usage'
    },
    {
      'id': 'high',
      'name': 'High',
      'color': Colors.red,
      'desc': 'Breaks feature'
    },
    {
      'id': 'critical',
      'name': 'Critical',
      'color': Colors.purple,
      'desc': 'App crashes'
    },
  ];

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _stepsController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    try {
      final payload = {
        'type': 'bug',
        'timestamp': DateTime.now().toIso8601String(),
        'userId': widget.user?.id,
        'username': widget.user?.username,
        'severity': _severity,
        'title': _titleController.text,
        'description': _descriptionController.text,
        'steps': _stepsController.text,
        'screen': widget.currentScreen,
      };

      final response = await http.post(
        Uri.parse(FeedbackSystem._feedbackWebhook),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200) {
        if (mounted) {
          Navigator.pop(context);
          _showSuccessDialog();
        }
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF12121A),
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green),
            SizedBox(width: 8),
            Text('Bug Reported!', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: const Text(
          'Thanks for helping improve the app!',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF12121A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        left: 20,
        right: 20,
        top: 20,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.bug_report, color: Colors.red),
                      SizedBox(width: 8),
                      Text(
                        'Report Bug',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white54),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Current screen: ${widget.currentScreen ?? 'Unknown'}',
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
              const SizedBox(height: 16),
              const Text(
                'Severity Level',
                style: TextStyle(color: Colors.white54, fontSize: 14),
              ),
              const SizedBox(height: 8),
              Row(
                children: _severityLevels.map((level) {
                  final isSelected = _severity == level['id'];
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _severity = level['id']),
                      child: Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? (level['color'] as Color).withOpacity(0.2)
                              : const Color(0xFF1A1A2E),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isSelected
                                ? (level['color'] as Color)
                                : Colors.transparent,
                          ),
                        ),
                        child: Column(
                          children: [
                            Text(
                              level['name'],
                              style: TextStyle(
                                color: isSelected
                                    ? level['color']
                                    : Colors.white54,
                                fontSize: 12,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                            Text(
                              level['desc'],
                              style: const TextStyle(
                                color: Colors.white38,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _titleController,
                style: const TextStyle(color: Colors.white),
                decoration:
                    _inputDecoration('Bug Title', 'Short summary of the issue'),
                validator: (value) =>
                    value?.trim().isEmpty == true ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descriptionController,
                maxLines: 3,
                style: const TextStyle(color: Colors.white),
                decoration: _inputDecoration(
                    'Description', 'What happened? What did you expect?'),
                validator: (value) =>
                    value?.trim().isEmpty == true ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _stepsController,
                maxLines: 3,
                style: const TextStyle(color: Colors.white),
                decoration: _inputDecoration('Steps to Reproduce',
                    '1. Go to...\n2. Click on...\n3. Error occurs'),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: _isSubmitting ? null : _submit,
                  icon: _isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Icon(Icons.send),
                  label: Text(
                    _isSubmitting ? 'Sending...' : 'Submit Bug Report',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.withOpacity(0.8),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    disabledBackgroundColor: Colors.red.withOpacity(0.3),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label, String hint) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white54),
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.white30, fontSize: 12),
      filled: true,
      fillColor: const Color(0xFF1A1A2E),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF6C63FF)),
      ),
    );
  }
}
