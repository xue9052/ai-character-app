/// 主循环视频队列：多段轮播；仅一段时由播放器 seek 循环，不做双机预载同 URL。
class MainLoopPlaylist {
  MainLoopPlaylist(this.mainVideos) : assert(mainVideos.isNotEmpty);

  final List<String> mainVideos;
  int _index = 0;

  bool get isSingle => mainVideos.length == 1;

  String get current => mainVideos[_index];

  /// 下一条主循环；仅一段时返回 null（禁止 standby 预载同一 URL）。
  String? get next {
    if (isSingle) return null;
    return mainVideos[(_index + 1) % mainVideos.length];
  }

  void advance() {
    if (isSingle) return;
    _index = (_index + 1) % mainVideos.length;
  }

  void reset() => _index = 0;
}
