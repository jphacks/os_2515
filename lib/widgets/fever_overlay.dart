import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';

class FeverOverlay extends StatefulWidget {
  const FeverOverlay({
    super.key,
    required this.line,
    required this.assetImagePath,
    this.voiceAssetPath,          // assets/audio/... を指定すると再生
    this.onFinished,              // 退場アニメ完了時に通知
    this.enterMs = 600,
    this.exitMs = 500,
    this.fadeMs = 300,
    this.opacity = 1.0,
    this.bubbleWidth = 180,
    this.holdMsIfNoVoice = 800,   // 音声なしのときの見せ時間
    this.preDelayMs = 250,        // ★ 追加: 入場後の待機
    this.lingerMs = 700,          // ★ 追加: 再生完了後の余韻
    this.minVisibleMs = 1800,     // ★ 追加: 最低表示時間
    this.volume = 1.0,            // ★ 追加: 再生音量
  });

  final String line;
  final String assetImagePath;
  final String? voiceAssetPath;
  final VoidCallback? onFinished;
  final int enterMs;
  final int exitMs;
  final int fadeMs;
  final double opacity;
  final double bubbleWidth;
  final int holdMsIfNoVoice;

  // 追加
  final int preDelayMs;
  final int lingerMs;
  final int minVisibleMs;
  final double volume;

  @override
  State<FeverOverlay> createState() => _FeverOverlayState();
}

class _FeverOverlayState extends State<FeverOverlay> with TickerProviderStateMixin {
  late final AnimationController _in;   // 入場
  late final AnimationController _out;  // 退場
  late final Animation<Offset> _slideIn;
  late final Animation<Offset> _slideOut;
  final AudioPlayer _player = AudioPlayer();

  bool _exiting = false;
  bool _played = false;
  late final DateTime _shownAt;

  @override
  void initState() {
    super.initState();

    // Android の無音対策：コンテキスト設定（失敗してもOK）
    try {
      AudioPlayer.global.setAudioContext(AudioContext(
        android: AudioContextAndroid(
          contentType: AndroidContentType.music,
          usageType: AndroidUsageType.media,
          audioFocus: AndroidAudioFocus.gainTransientMayDuck,
          isSpeakerphoneOn: false,
          stayAwake: false,
        ),
      ));
    } catch (_) {}

    _in  = AnimationController(vsync: this, duration: Duration(milliseconds: widget.enterMs));
    _out = AnimationController(vsync: this, duration: Duration(milliseconds: widget.exitMs));

    _slideIn  = Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
      .animate(CurvedAnimation(parent: _in, curve: Curves.easeOutCubic));
    _slideOut = Tween<Offset>(begin: Offset.zero, end: const Offset(1, 0))
      .animate(CurvedAnimation(parent: _out, curve: Curves.easeInCubic));

    _shownAt = DateTime.now();
    _in.forward();

    // 入場完了を待ってから音声再生
    _in.addStatusListener((status) async {
      if (status == AnimationStatus.completed && !_played) {
        _played = true;
        await _startVoiceThenExit();
      }
    });

    // 退場完了でコールバック
    _out.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onFinished?.call();
      }
    });

    // デバッグ: 再生状態を監視（必要なら）
    // _player.onPlayerStateChanged.listen((s) => debugPrint('player state: $s'));
  }

  Future<void> _startVoiceThenExit() async {
    if (!mounted) return;

    // 1) 入場後の余白
    if (widget.preDelayMs > 0) {
      await Future.delayed(Duration(milliseconds: widget.preDelayMs));
    }

    // 2) 音声再生（あれば）
    bool played = false;
    if (widget.voiceAssetPath != null) {
      try {
        await _player.setReleaseMode(ReleaseMode.stop);
        await _player.setVolume(widget.volume.clamp(0.0, 1.0));
        await _player.play(AssetSource(widget.voiceAssetPath!));
        played = true;

        // 再生完了を待つ（30秒でタイムアウト）
        await _player.onPlayerComplete.first.timeout(
          const Duration(seconds: 30),
          onTimeout: () => null,
        );
      } catch (e) {
        // print("audio play failed: $e");
        played = false;
      }
    } else {
      // 音声なしならホールド
      await Future.delayed(Duration(milliseconds: widget.holdMsIfNoVoice));
    }

    // 3) 余韻で滞在
    if (played && widget.lingerMs > 0) {
      await Future.delayed(Duration(milliseconds: widget.lingerMs));
    }

    // 4) 最低表示時間の保証
    final elapsed = DateTime.now().difference(_shownAt).inMilliseconds;
    final remain = widget.minVisibleMs - elapsed;
    if (remain > 0) {
      await Future.delayed(Duration(milliseconds: remain));
    }

    // 5) 退場へ
    if (!_exiting) {
      _exiting = true;
      try { await _player.stop(); } catch (_) {}
      if (mounted) _out.forward();
    }
  }

  @override
  void dispose() {
    _player.dispose();
    _in.dispose();
    _out.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: true, // 背面の操作はそのまま通す
      child: AnimatedOpacity(
        opacity: widget.opacity,
        duration: Duration(milliseconds: widget.fadeMs),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Align(
              alignment: Alignment.bottomRight,
              child: AnimatedBuilder(
                animation: Listenable.merge([_in, _out]),
                builder: (_, __) => SlideTransition(
                  position: _out.isAnimating ? _slideOut : _slideIn,
                  child: Image.asset(
                    widget.assetImagePath,
                    height: MediaQuery.of(context).size.height * 0.55,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
            // セリフふきだし（左上）
            Positioned(
              left: 24,
              top: 110,
              child: _SpeechBubble(width: widget.bubbleWidth, text: widget.line),
            ),
          ],
        ),
      ),
    );
  }
}

class _SpeechBubble extends StatelessWidget {
  const _SpeechBubble({required this.width, required this.text});
  final double width;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: width,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [BoxShadow(blurRadius: 8, color: Colors.black26)],
          ),
          child: Text(text, style: const TextStyle(fontSize: 18, height: 1.2, color: Colors.black87)),
        ),
        Positioned(
          bottom: -8, left: 18,
          child: Transform.rotate(
            angle: 0.6,
            child: Container(width: 16, height: 16, color: Colors.white),
          ),
        ),
      ],
    );
  }
}
