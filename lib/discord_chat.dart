import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'config.dart';
import 'main.dart';

class DiscordChatSystem {
  static const String _getMessagesUrl =
      '${Config.baseUrl}/.netlify/functions/get_messages';
  static const String _sendMessageUrl =
      '${Config.baseUrl}/.netlify/functions/send_messages';

  static const String _chatChannelId = '1476303134576873614';

  // Poll messages every 3 seconds
  static Stream<List<ChatMessage>> get messagesStream async* {
    while (true) {
      try {
        final messages = await fetchMessages();
        yield messages;
      } catch (e) {
        yield [];
      }
      await Future.delayed(const Duration(seconds: 3));
    }
  }

  static Future<List<ChatMessage>> fetchMessages() async {
    final response = await http.get(
      Uri.parse('$_getMessagesUrl?channelId=$_chatChannelId&limit=50'),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final messages =
          (data as List).map((m) => ChatMessage.fromJson(m)).toList();
      messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      return messages;
    }
    throw Exception('Failed to fetch: ${response.statusCode}');
  }

  static Future<void> sendMessage({
    required DiscordUser user,
    required String text,
  }) async {
    if (text.trim().isEmpty) return;

    final response = await http.post(
      Uri.parse(_sendMessageUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'channelId': _chatChannelId,
        'message': text.trim(),
        'username': user.nickname,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to send: ${response.statusCode}');
    }
  }
}

class ChatMessage {
  final String id;
  final String userId;
  final String username;
  final String? avatar;
  final String text;
  final DateTime timestamp;
  final bool isBot;

  ChatMessage({
    required this.id,
    required this.userId,
    required this.username,
    this.avatar,
    required this.text,
    required this.timestamp,
    this.isBot = false,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'],
      userId: json['authorId'],
      username: json['author'],
      avatar: json['avatar'],
      text: json['content'],
      timestamp: DateTime.parse(json['timestamp']),
      isBot: json['isBot'] ?? false,
    );
  }

  String get displayName => username;

  String get formattedTime {
    final now = DateTime.now();
    final diff = now.difference(timestamp);

    if (diff.inDays > 0) {
      return '${timestamp.day}/${timestamp.month} ${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
    }
    return '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
  }
}

class DiscordChatPage extends StatefulWidget {
  final DiscordUser user;

  const DiscordChatPage({super.key, required this.user});

  @override
  State<DiscordChatPage> createState() => _DiscordChatPageState();
}

class _DiscordChatPageState extends State<DiscordChatPage> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  List<ChatMessage> _messages = [];
  bool _isSending = false;
  StreamSubscription? _pollSubscription;

  @override
  void initState() {
    super.initState();
    _startPolling();
  }

  @override
  void dispose() {
    _pollSubscription?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _startPolling() {
    _pollSubscription = DiscordChatSystem.messagesStream.listen((messages) {
      if (mounted) {
        setState(() => _messages = messages);
        _scrollToBottom();
      }
    });
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    setState(() => _isSending = true);

    try {
      await DiscordChatSystem.sendMessage(
        user: widget.user,
        text: text,
      );
      _messageController.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF12121A),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.chat_bubble, color: Color(0xFF5865F2), size: 20),
                SizedBox(width: 8),
                Text('Team Chat'),
              ],
            ),
            Text(
              'via Discord Bot',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ],
        ),
        actions: [
          StreamBuilder<List<ChatMessage>>(
            stream: DiscordChatSystem.messagesStream,
            builder: (context, snapshot) {
              final isConnected = snapshot.hasData;
              return Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: isConnected ? Colors.green : Colors.red,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isConnected ? 'Live' : 'Retrying...',
                      style: TextStyle(
                        color: isConnected ? Colors.green : Colors.red,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            color: const Color(0xFF5865F2).withValues(alpha: 0.15),
            child: const Row(
              children: [
                Icon(Icons.smart_toy, color: Color(0xFF5865F2), size: 16),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Synced with Discord. Updates every 3 seconds.',
                    style: TextStyle(color: Color(0xFF5865F2), fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _messages.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.chat_bubble_outline,
                            color: Colors.white24, size: 48),
                        SizedBox(height: 16),
                        Text(
                          'No messages yet\nStart the conversation!',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white38),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final msg = _messages[index];
                      final isMe = msg.userId == widget.user.id;
                      final showAvatar = !isMe &&
                          (index == 0 ||
                              _messages[index - 1].userId != msg.userId);

                      return _ChatBubble(
                        message: msg,
                        isMe: isMe,
                        showAvatar: showAvatar,
                      );
                    },
                  ),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF12121A),
              border: Border(
                top: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
              ),
            ),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      focusNode: _focusNode,
                      maxLines: null,
                      textCapitalization: TextCapitalization.sentences,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Message...',
                        hintStyle: const TextStyle(color: Colors.white30),
                        filled: true,
                        fillColor: const Color(0xFF1A1A2E),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 48,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _isSending ? null : _sendMessage,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF5865F2),
                        foregroundColor: Colors.white,
                        shape: const CircleBorder(),
                        padding: EdgeInsets.zero,
                      ),
                      child: _isSending
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
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isMe;
  final bool showAvatar;

  const _ChatBubble({
    required this.message,
    required this.isMe,
    required this.showAvatar,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(
          bottom: showAvatar ? 16 : 4,
          left: isMe ? 64 : 0,
          right: isMe ? 0 : 64,
        ),
        child: Column(
          crossAxisAlignment:
              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (!isMe && showAvatar)
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (message.avatar != null)
                      CircleAvatar(
                        radius: 14,
                        backgroundImage: NetworkImage(message.avatar!),
                      )
                    else
                      CircleAvatar(
                        radius: 14,
                        backgroundColor: const Color(0xFF5865F2),
                        child: Text(
                          message.displayName[0].toUpperCase(),
                          style: const TextStyle(
                              fontSize: 12, color: Colors.white),
                        ),
                      ),
                    const SizedBox(width: 8),
                    Text(
                      message.displayName,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: isMe ? const Color(0xFF5865F2) : const Color(0xFF1A1A2E),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(!isMe && !showAvatar ? 4 : 16),
                  topRight: const Radius.circular(16),
                  bottomLeft: const Radius.circular(16),
                  bottomRight: Radius.circular(isMe ? 4 : 16),
                ),
              ),
              child: Text(
                message.text,
                style: TextStyle(
                  color: isMe ? Colors.white : Colors.white70,
                  fontSize: 14,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 2, left: 4, right: 4),
              child: Text(
                message.formattedTime,
                style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 10,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
