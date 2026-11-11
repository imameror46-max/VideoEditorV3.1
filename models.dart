import 'dart:math';
import 'package:flutter/widgets.dart';

class Fmt {
  final String label;
  final int w, h;
  const Fmt(this.label, this.w, this.h);
}

const formats = [
  Fmt('9:16', 720, 1280),
  Fmt('16:9', 1280, 720),
  Fmt('21:9', 1260, 540),
  Fmt('1:1', 720, 720),
];

const kMaxItems = 40; // batas jumlah foto/video
const kMargin = 0.88; // area isi = 88% kanvas, sisanya latar terlihat

class Media {
  final String path;
  final bool isVideo;
  final double dur; // detik (video)
  int multi = 1; // 1 / 2 / 4 / 6 / 8
  double zoom = 1.0; // hanya untuk frame tunggal
  final Key key = UniqueKey();
  Media(this.path, this.isVideo, this.dur);
}

class Sound {
  final String path, name;
  final double len;
  double start = 0;
  late double stop;
  Sound(this.path, this.name, this.len) {
    stop = len;
  }
}

class Bg {
  int color = 0xFFFFFFFF;
  String? image;
}

bool isVideoPath(String p) {
  final e = p.split('.').last.toLowerCase();
  return const ['mp4', 'mov', 'mkv', 'webm', '3gp', 'avi', 'm4v'].contains(e);
}

int gridCols(int n) => const {1: 1, 2: 2, 4: 2, 6: 3, 8: 4}[n] ?? 1;
int gridRows(int n) => n <= 2 ? 1 : 2;

/// Item bertanda multi N menggabungkan dirinya + (N-1) item berikutnya dalam 1 frame.
List<List<Media>> buildFrames(List<Media> items) {
  final out = <List<Media>>[];
  var i = 0;
  while (i < items.length) {
    final n = items[i].multi < 1 ? 1 : items[i].multi;
    final end = min(i + n, items.length);
    out.add(items.sublist(i, end));
    i = end;
  }
  return out;
}

String fmtTime(double s) {
  final t = s.round();
  return '${t ~/ 60}:${(t % 60).toString().padLeft(2, '0')}';
}

double parseTime(String s, double fallback) {
  try {
    var v = 0.0;
    for (final x in s.trim().split(':')) {
      v = v * 60 + double.parse(x);
    }
    return v;
  } catch (_) {
    return fallback;
  }
}
