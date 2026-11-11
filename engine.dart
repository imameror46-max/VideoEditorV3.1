import 'dart:io';
import 'dart:math';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'models.dart';

const kFps = 30;
// Jika muncul error "Unknown encoder libx264", ganti dengan:
// ['-c:v', 'h264_mediacodec', '-b:v', '6M', '-pix_fmt', 'yuv420p']
const kVideoArgs = ['-c:v', 'libx264', '-preset', 'veryfast', '-crf', '23', '-pix_fmt', 'yuv420p'];

Future<double> probeDuration(String path) async {
  final s = await FFprobeKit.getMediaInformation(path);
  final info = await s.getMediaInformation();
  return double.tryParse(info?.getDuration() ?? '') ?? 0;
}

Future<void> cancelRender() => FFmpegKit.cancel();

Future<void> _run(List<String> args) async {
  final s = await FFmpegKit.executeWithArguments(args);
  final rc = await s.getReturnCode();
  if (ReturnCode.isSuccess(rc)) return;
  if (ReturnCode.isCancel(rc)) throw Exception('Dibatalkan');
  final out = (await s.getOutput()) ?? '';
  throw Exception(out.length > 700 ? out.substring(out.length - 700) : out);
}

class Cell {
  final double cx, cy, bw, bh;
  Cell(this.cx, this.cy, this.bw, this.bh);
}

/// Posisi tiap media. Urutan multi: kiri-bawah -> kanan-bawah -> kiri-atas -> kanan-atas.
List<Cell> layout(Fmt f, List<Media> g) {
  final w = f.w.toDouble(), h = f.h.toDouble();
  final n = g.first.multi;
  if (n == 1) {
    final z = g.first.zoom;
    return [Cell(w / 2, h / 2, w * kMargin * z, h * kMargin * z)];
  }
  final cols = gridCols(n), rows = gridRows(n);
  const gap = 10.0;
  final iw = w * kMargin, ih = h * kMargin;
  final ox = (w - iw) / 2, oy = (h - ih) / 2;
  final cw = (iw - gap * (cols - 1)) / cols;
  final ch = (ih - gap * (rows - 1)) / rows;
  return [
    for (var k = 0; k < g.length; k++)
      Cell(ox + (k % cols) * (cw + gap) + cw / 2,
          oy + (rows - 1 - k ~/ cols) * (ch + gap) + ch / 2, cw, ch)
  ];
}

Future<String> renderVideo({
  required Fmt fmt,
  required List<Media> items,
  required Bg bg,
  required List<Sound> sounds,
  required double total,
  required bool auto,
  required double manualDur,
  required void Function(String msg, double v) onProgress,
}) async {
  final frames = buildFrames(items);
  final d = auto ? total / frames.length : manualDur; // durasi tiap frame
  final t = d * frames.length; // durasi total
  final tmp = await getTemporaryDirectory();
  final dir = Directory('${tmp.path}/render');
  if (dir.existsSync()) dir.deleteSync(recursive: true);
  dir.createSync(recursive: true);
  final w = fmt.w, h = fmt.h;
  final segs = <String>[];

  for (var f = 0; f < frames.length; f++) {
    onProgress('Frame ${f + 1} dari ${frames.length}', f / (frames.length + 1));
    final g = frames[f];
    final args = <String>['-y'];
    if (bg.image != null) {
      args.addAll(['-loop', '1', '-framerate', '$kFps', '-t', '$d', '-i', bg.image!]);
    } else {
      final c = (bg.color & 0xFFFFFF).toRadixString(16).padLeft(6, '0');
      args.addAll(['-f', 'lavfi', '-t', '$d', '-i', 'color=c=0x$c:s=${w}x$h:r=$kFps']);
    }
    for (final m in g) {
      if (m.isVideo) {
        args.addAll(['-i', m.path]);
      } else {
        args.addAll(['-loop', '1', '-framerate', '$kFps', '-t', '$d', '-i', m.path]);
      }
    }
    final fc = StringBuffer();
    fc.write(bg.image != null
        ? '[0:v]scale=$w:$h:force_original_aspect_ratio=increase,crop=$w:$h,setsar=1,fps=$kFps[bg0];'
        : '[0:v]setsar=1[bg0];');
    final cells = layout(fmt, g);
    var prev = 'bg0';
    for (var k = 0; k < g.length; k++) {
      final m = g[k], c = cells[k];
      // Video dipercepat/diperlambat agar tepat sepanjang durasi frame
      final r = (m.isVideo && m.dur > 0) ? d / m.dur : 1.0;
      final bw = max(2, c.bw.round()), bh = max(2, c.bh.round());
      fc.write('[${k + 1}:v]setpts=(PTS-STARTPTS)*${r.toStringAsFixed(5)},fps=$kFps,'
          'scale=$bw:$bh:force_original_aspect_ratio=decrease:force_divisible_by=2,setsar=1[m$k];');
      fc.write('[$prev][m$k]overlay=x=${c.cx.toStringAsFixed(1)}-w/2:'
          'y=${c.cy.toStringAsFixed(1)}-h/2:eof_action=pass[o$k];');
      prev = 'o$k';
    }
    var graph = fc.toString();
    graph = graph.substring(0, graph.length - 1);
    final out = '${dir.path}/seg$f.mp4';
    args.addAll(['-filter_complex', graph, '-map', '[$prev]', '-t', '$d', '-r', '$kFps', '-an', ...kVideoArgs, out]);
    await _run(args);
    segs.add(out);
  }

  onProgress('Menggabungkan frame…', frames.length / (frames.length + 1));
  File('${dir.path}/list.txt').writeAsStringSync(segs.map((p) => "file '$p'").join('\n'));
  final joined = '${dir.path}/joined.mp4';
  await _run(['-y', '-f', 'concat', '-safe', '0', '-i', '${dir.path}/list.txt', '-c', 'copy', joined]);

  final result = '${tmp.path}/Gabung_${DateTime.now().millisecondsSinceEpoch}.mp4';
  final used = sounds.where((s) => min(s.stop, t) - s.start > 0).toList();
  if (used.isEmpty) {
    File(joined).copySync(result);
  } else {
    onProgress('Memasang suara…', 0.97);
    final args = <String>['-y', '-i', joined];
    final fc = StringBuffer();
    for (var k = 0; k < used.length; k++) {
      final s = used[k];
      args.addAll(['-i', s.path]);
      final len = min(s.stop, t) - s.start;
      final ms = (s.start * 1000).round();
      fc.write('[${k + 1}:a]atrim=0:${len.toStringAsFixed(3)},asetpts=PTS-STARTPTS,adelay=$ms|$ms[a$k];');
    }
    for (var k = 0; k < used.length; k++) {
      fc.write('[a$k]');
    }
    fc.write('amix=inputs=${used.length}:duration=longest:normalize=0[aout]');
    args.addAll(['-filter_complex', fc.toString(), '-map', '0:v', '-map', '[aout]',
      '-c:v', 'copy', '-c:a', 'aac', '-b:a', '192k', '-t', t.toStringAsFixed(3), result]);
    await _run(args);
  }
  await Gal.putVideo(result);
  onProgress('Selesai', 1);
  return result;
}
