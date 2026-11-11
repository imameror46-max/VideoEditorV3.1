import 'dart:io';
import 'dart:math';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'engine.dart';
import 'models.dart';

const orange = Color(0xFFFF6B3D);
const grey = TextStyle(color: Color(0xFFB0B0B0), fontSize: 13);

void main() => runApp(const App());

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Gabung Media',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          useMaterial3: true,
          colorSchemeSeed: orange,
          scaffoldBackgroundColor: const Color(0xFF121212),
        ),
        home: const Home(),
      );
}

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  int step = 0;
  Fmt? fmt;
  final items = <Media>[];
  final bg = Bg();
  final sounds = <Sound>[];
  bool auto = true;
  double total = 60;
  double manualDur = 5;
  bool busy = false;
  String status = '';
  double prog = 0;
  int _rev = 0; // memaksa kolom waktu dibuat ulang saat nilai diubah dari luar

  List<List<Media>> get frames => buildFrames(items);
  double get frameDur => auto ? total / max(1, frames.length) : manualDur;

  // ---------- aksi ----------
  Future<void> addMedia() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.media, allowMultiple: true);
    if (r == null) return;
    for (final f in r.files) {
      final p = f.path;
      if (p == null || items.length >= kMaxItems) continue;
      final v = isVideoPath(p);
      items.add(Media(p, v, v ? await probeDuration(p) : 0));
    }
    if (mounted) setState(() {});
  }

  Future<void> addSound() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.audio, allowMultiple: true);
    if (r == null) return;
    for (final f in r.files) {
      if (f.path == null) continue;
      sounds.add(Sound(f.path!, f.name, await probeDuration(f.path!)));
    }
    if (sounds.isNotEmpty) total = sounds.map((s) => s.stop).reduce(max);
    if (mounted) setState(() => _rev++);
  }

  Future<void> pickBg() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.image);
    final p = r?.files.single.path;
    if (p != null) setState(() => bg.image = p);
  }

  Future<void> _export() async {
    setState(() {
      busy = true;
      status = 'Menyiapkan…';
      prog = 0;
    });
    String msg;
    try {
      await renderVideo(
        fmt: fmt!,
        items: items,
        bg: bg,
        sounds: sounds,
        total: total,
        auto: auto,
        manualDur: manualDur,
        onProgress: (m, v) {
          if (mounted) setState(() {
            status = m;
            prog = v;
          });
        },
      );
      msg = 'Selesai! Video tersimpan di Galeri.';
    } catch (e) {
      msg = 'Gagal: $e';
    }
    if (!mounted) return;
    setState(() => busy = false);
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        content: SingleChildScrollView(child: SelectableText(msg)),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
      ),
    );
  }

  bool get _canNext => switch (step) { 0 => fmt != null, 1 => items.isNotEmpty, _ => true };

  void _next() => step < 3 ? setState(() => step++) : _export();

  // ---------- kerangka ----------
  @override
  Widget build(BuildContext context) {
    const titles = ['Pilih Format', 'Muat Foto / Video', 'Pilih Latar', 'Suara & Durasi'];
    return Scaffold(
      appBar: AppBar(title: Text('${step + 1}/4  ${titles[step]}')),
      body: busy ? _busy() : _body(),
      bottomNavigationBar: busy
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  if (step > 0) ...[
                    Expanded(child: OutlinedButton(onPressed: () => setState(() => step--), child: const Text('Kembali'))),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: _canNext ? _next : null,
                      child: Text(step == 3 ? 'Gabungkan & Ekspor' : 'Lanjut'),
                    ),
                  ),
                ]),
              ),
            ),
    );
  }

  Widget _body() => switch (step) {
        0 => _formatStep(),
        1 => _mediaStep(),
        2 => _bgStep(),
        _ => _soundStep(),
      };

  Widget _busy() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            LinearProgressIndicator(value: prog),
            const SizedBox(height: 16),
            Text(status),
            const SizedBox(height: 24),
            OutlinedButton(onPressed: cancelRender, child: const Text('Batalkan')),
          ]),
        ),
      );

  // ---------- 1: format ----------
  Widget _formatStep() => Padding(
        padding: const EdgeInsets.all(16),
        child: GridView.count(
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          children: [
            for (final f in formats)
              InkWell(
                onTap: () => setState(() => fmt = f),
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(width: 2, color: fmt == f ? orange : const Color(0xFF333333)),
                  ),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    SizedBox(
                      width: 90,
                      height: 90,
                      child: Center(
                        child: AspectRatio(
                          aspectRatio: f.w / f.h,
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border.all(width: 2, color: fmt == f ? orange : Colors.grey),
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(f.label, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  ]),
                ),
              ),
          ],
        ),
      );

  // ---------- 2: muat media ----------
  Widget _mediaStep() {
    final leads = <int>{};
    var i = 0;
    while (i < items.length) {
      leads.add(i);
      i += max(1, items[i].multi);
    }
    return Column(children: [
      Expanded(
        child: ReorderableListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: items.length,
          onReorder: (a, b) => setState(() {
            if (b > a) b--;
            items.insert(b, items.removeAt(a));
          }),
          itemBuilder: (c, idx) => Card(key: items[idx].key, child: _mediaTile(idx, items[idx], leads.contains(idx))),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        child: OutlinedButton.icon(
          onPressed: items.length >= kMaxItems ? null : addMedia,
          icon: const Icon(Icons.add),
          label: Text('Tambah foto / video (${items.length}/$kMaxItems)'),
        ),
      ),
    ]);
  }

  Widget _mediaTile(int idx, Media m, bool lead) => Padding(
        padding: const EdgeInsets.all(10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${idx + 1}', style: const TextStyle(color: orange, fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(width: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(width: 56, height: 56, child: _thumb(m, cover: true)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(m.path.split('/').last, maxLines: 1, overflow: TextOverflow.ellipsis),
              if (!lead)
                const Text('Ikut frame multi di atasnya', style: grey)
              else ...[
                Wrap(spacing: 6, children: [
                  for (final n in const [1, 2, 4, 6, 8])
                    ChoiceChip(
                      label: Text('${n}x'),
                      selected: m.multi == n,
                      onSelected: (_) => setState(() => m.multi = n),
                    ),
                ]),
                if (m.multi == 1)
                  Row(children: [
                    const Text('Zoom', style: grey),
                    Expanded(child: Slider(value: m.zoom, min: 0.5, max: 2, onChanged: (v) => setState(() => m.zoom = v))),
                    Text('${m.zoom.toStringAsFixed(1)}x', style: grey),
                  ]),
              ],
            ]),
          ),
          IconButton(onPressed: () => setState(() => items.remove(m)), icon: const Icon(Icons.close)),
        ]),
      );

  Widget _thumb(Media m, {bool cover = false}) => m.isVideo
      ? Container(color: Colors.blueGrey.shade800, child: const Icon(Icons.movie))
      : Image.file(File(m.path), fit: cover ? BoxFit.cover : BoxFit.contain, cacheWidth: 400);

  // ---------- 3: latar ----------
  Widget _bgStep() {
    final f = fmt!;
    const colors = [0xFFFFFFFF, 0xFF9E9E9E, 0xFFE8501F, 0xFF1E3A8A, 0xFF111111, 0xFF2E7D32];
    return ListView(padding: const EdgeInsets.all(16), children: [
      Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 360),
          child: AspectRatio(aspectRatio: f.w / f.h, child: _preview(frames.first)),
        ),
      ),
      const SizedBox(height: 16),
      const Text('Template warna', style: grey),
      const SizedBox(height: 8),
      Wrap(spacing: 10, children: [
        for (final c in colors)
          GestureDetector(
            onTap: () => setState(() {
              bg.color = c;
              bg.image = null;
            }),
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Color(c),
                shape: BoxShape.circle,
                border: Border.all(width: 3, color: bg.image == null && bg.color == c ? Colors.white : Colors.grey.shade700),
              ),
            ),
          ),
      ]),
      const SizedBox(height: 12),
      OutlinedButton.icon(onPressed: pickBg, icon: const Icon(Icons.image), label: const Text('Muat latar dari perangkat')),
    ]);
  }

  Widget _preview(List<Media> g) => Container(
        clipBehavior: Clip.hardEdge,
        decoration: BoxDecoration(
          color: Color(bg.color),
          image: bg.image == null ? null : DecorationImage(image: FileImage(File(bg.image!)), fit: BoxFit.cover),
        ),
        child: LayoutBuilder(builder: (c, box) {
          final n = g.first.multi;
          if (n == 1) {
            final z = g.first.zoom;
            return OverflowBox(
              maxWidth: box.maxWidth * kMargin * z,
              maxHeight: box.maxHeight * kMargin * z,
              child: SizedBox(
                width: box.maxWidth * kMargin * z,
                height: box.maxHeight * kMargin * z,
                child: _thumb(g.first),
              ),
            );
          }
          final cols = gridCols(n), rows = gridRows(n);
          return Padding(
            padding: EdgeInsets.symmetric(horizontal: box.maxWidth * 0.06, vertical: box.maxHeight * 0.06),
            child: Column(children: [
              for (var r = rows - 1; r >= 0; r--) // baris atas dulu di layar
                Expanded(
                  child: Row(children: [
                    for (var col = 0; col < cols; col++)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(2),
                          child: r * cols + col < g.length ? _thumb(g[r * cols + col]) : const SizedBox(),
                        ),
                      ),
                  ]),
                ),
            ]),
          );
        }),
      );

  // ---------- 4: suara & durasi ----------
  Widget _timeField(String label, double v, ValueChanged<double> on, String k) => TextFormField(
        key: ValueKey('$k$_rev'),
        initialValue: fmtTime(v),
        keyboardType: TextInputType.datetime,
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), isDense: true),
        onChanged: (t) => setState(() => on(parseTime(t, v))),
      );

  Widget _soundStep() {
    final fr = frames.length;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Auto Duration'),
              value: auto,
              onChanged: (v) => setState(() => auto = v),
            ),
            auto
                ? _timeField('Durasi video (m:ss)', total, (v) => total = v, 'total')
                : _timeField('Durasi per frame (m:ss)', manualDur, (v) => manualDur = v, 'per'),
            const SizedBox(height: 8),
            Text(
              '$fr frame × ${frameDur.toStringAsFixed(2)} dtk = ${fmtTime(frameDur * fr)}. '
              'Semua video dalam frame (termasuk multi) otomatis dipercepat/diperlambat agar pas ${frameDur.toStringAsFixed(2)} dtk.',
              style: grey,
            ),
          ]),
        ),
      ),
      for (var i = 0; i < sounds.length; i++)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(children: [
              Row(children: [
                Text('Suara ${i + 1}', style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                Expanded(child: Text(sounds[i].name, maxLines: 1, overflow: TextOverflow.ellipsis, style: grey)),
                IconButton(onPressed: () => setState(() => sounds.removeAt(i)), icon: const Icon(Icons.close)),
              ]),
              const SizedBox(height: 4),
              Row(children: [
                Expanded(child: _timeField('Masuk', sounds[i].start, (v) => sounds[i].start = v, 's${sounds[i].hashCode}m')),
                const SizedBox(width: 8),
                Expanded(child: _timeField('Stop', sounds[i].stop, (v) => sounds[i].stop = v, 's${sounds[i].hashCode}s')),
              ]),
            ]),
          ),
        ),
      OutlinedButton.icon(onPressed: addSound, icon: const Icon(Icons.add), label: const Text('Tambah Suara')),
      if (sounds.isNotEmpty)
        TextButton(
          onPressed: () => setState(() {
            total = sounds.map((s) => s.stop).reduce(max);
            _rev++;
          }),
          child: const Text('Samakan durasi video dengan akhir suara'),
        ),
    ]);
  }
}
