import 'dart:async';
import 'dart:html';

import 'package:audioplayers_platform_interface/api/release_mode.dart';
import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';

class WrappedPlayer {
  final String playerId;
  final AudioplayersPlugin plugin;

  double? pausedAt;
  double currentVolume = 1.0;
  double currentPlaybackRate = 1.0;
  ReleaseMode currentReleaseMode = ReleaseMode.release;
  String? currentUrl;
  bool isPlaying = false;

  AudioElement? player;
  StreamSubscription? playerTimeUpdateSubscription;

  WrappedPlayer(this.plugin, this.playerId);

  void setUrl(String url) {
    currentUrl = url;

    stop();
    recreateNode();
    if (isPlaying) {
      resume();
    }
  }

  void setVolume(double volume) {
    currentVolume = volume;
    player?.volume = volume;
  }

  void setPlaybackRate(double rate) {
    currentPlaybackRate = rate;
    player?.playbackRate = rate;
  }

  void recreateNode() {
    if (currentUrl == null) {
      return;
    }
    player = AudioElement(currentUrl);
    player?.loop = shouldLoop();
    player?.volume = currentVolume;
    player?.playbackRate = currentPlaybackRate;
    playerTimeUpdateSubscription = player?.onTimeUpdate.listen(
      (_) => plugin.channel.invokeMethod<int>(
        'audio.onCurrentPosition',
        {
          'playerId': playerId,
          'value': (1000 * (player?.currentTime ?? 0)).round(),
        },
      ),
    );
  }

  bool shouldLoop() => currentReleaseMode == ReleaseMode.loop;

  void setReleaseMode(ReleaseMode releaseMode) {
    currentReleaseMode = releaseMode;
    player?.loop = shouldLoop();
  }

  void release() {
    _cancel();
    player = null;

    playerTimeUpdateSubscription?.cancel();
    playerTimeUpdateSubscription = null;
  }

  void start(double position) {
    isPlaying = true;
    if (currentUrl == null) {
      return; // nothing to play yet
    }
    if (player == null) {
      recreateNode();
    }
    player?.play();
    player?.currentTime = position;
  }

  void resume() {
    start(pausedAt ?? 0);
  }

  void pause() {
    pausedAt = player?.currentTime as double?;
    _cancel();
  }

  void stop() {
    pausedAt = 0;
    _cancel();
  }

  void seek(int position) {
    player?.currentTime = position / 1000.0;
  }

  void _cancel() {
    isPlaying = false;
    player?.pause();
    if (currentReleaseMode == ReleaseMode.release) {
      player = null;
    }
  }
}

class AudioplayersPlugin {
  final MethodChannel channel;

  // players by playerId
  Map<String, WrappedPlayer> players = {};

  AudioplayersPlugin(this.channel);

  static void registerWith(Registrar registrar) {
    final channel = MethodChannel(
      'xyz.luan/audioplayers',
      const StandardMethodCodec(),
      registrar,
    );

    final instance = AudioplayersPlugin(channel);
    channel.setMethodCallHandler(instance.handleMethodCall);
  }

  WrappedPlayer getOrCreatePlayer(String playerId) {
    return players.putIfAbsent(playerId, () => WrappedPlayer(this, playerId));
  }

  Future<WrappedPlayer> setSourceUrl(String playerId, String url) async {
    final player = getOrCreatePlayer(playerId);

    if (player.currentUrl == url) {
      return player;
    }

    player.setUrl(url);
    return player;
  }

  ReleaseMode parseReleaseMode(String value) {
    return ReleaseMode.values.firstWhere((e) => e.toString() == value);
  }

  Future<dynamic> handleMethodCall(MethodCall call) async {
    final method = call.method;
    switch (method) {
      case 'changeLogLevel':
        {
          // no-op for now
          return 1;
        }
    }

    final args = call.arguments as Map<dynamic, dynamic>;
    final playerId = args['playerId'] as String;
    switch (method) {
      case 'setSourceUrl':
        {
          final url = args['url'] as String;
          await setSourceUrl(playerId, url);
          return 1;
        }
      case 'getCurrentPosition':
        {
          final position = getOrCreatePlayer(playerId).player?.currentTime;
          if (position == null) {
            return null;
          }
          return (position * 1000).toInt();
        }
      case 'getDuration':
        {
          final duration = getOrCreatePlayer(playerId).player?.duration;
          if (duration == null) {
            return null;
          }
          return (duration * 1000).toInt();
        }
      case 'pause':
        {
          getOrCreatePlayer(playerId).pause();
          return 1;
        }
      case 'stop':
        {
          getOrCreatePlayer(playerId).stop();
          return 1;
        }
      case 'resume':
        {
          getOrCreatePlayer(playerId).resume();
          return 1;
        }
      case 'setVolume':
        {
          final volume = args['volume'] as double? ?? 1.0;
          getOrCreatePlayer(playerId).setVolume(volume);
          return 1;
        }
      case 'setReleaseMode':
        {
          final releaseMode = parseReleaseMode(args['releaseMode'] as String);
          getOrCreatePlayer(playerId).setReleaseMode(releaseMode);
          return 1;
        }
      case 'release':
        {
          getOrCreatePlayer(playerId).release();
          return 1;
        }
      case 'setPlaybackRate':
        {
          final rate = args['playbackRate'] as double? ?? 1.0;
          getOrCreatePlayer(playerId).setPlaybackRate(rate);
          return 1;
        }
      case 'seek':
        {
          final position = args['position'] as int? ?? 0;
          getOrCreatePlayer(playerId).seek(position);
          return 1;
        }
      default:
        throw PlatformException(
          code: 'Unimplemented',
          details:
              "The audioplayers plugin for web doesn't implement the method '$method'",
        );
    }
  }
}
