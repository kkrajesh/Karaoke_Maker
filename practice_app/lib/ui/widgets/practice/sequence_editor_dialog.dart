import 'package:flutter/material.dart';
import '../../theme/voxpro_theme.dart';
import '../../../services/performance_profile_service.dart';

class SequenceEditorDialog extends StatefulWidget {
  final Duration totalDuration;
  final NamedSequence? initialSequence;
  final Function(NamedSequence) onSave;

  const SequenceEditorDialog({
    Key? key,
    required this.totalDuration,
    this.initialSequence,
    required this.onSave,
  }) : super(key: key);

  @override
  State<SequenceEditorDialog> createState() => _SequenceEditorDialogState();
}

class _SequenceEditorDialogState extends State<SequenceEditorDialog> {
  late TextEditingController _nameController;
  late List<PlaybackSegment> _segments;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialSequence?.name ?? 'New Sequence');
    _segments = widget.initialSequence?.segments.map((e) => PlaybackSegment(start: e.start, end: e.end)).toList() ?? [];
    if (_segments.isEmpty) {
      _segments.add(PlaybackSegment(start: Duration.zero, end: Duration(seconds: 10)));
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _addSegment() {
    if (_segments.length >= 5) return;
    setState(() {
      Duration start = _segments.last.end;
      Duration end = start + const Duration(seconds: 10);
      if (end > widget.totalDuration) end = widget.totalDuration;
      _segments.add(PlaybackSegment(start: start, end: end));
    });
  }

  String _formatMs(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    final ms = (d.inMilliseconds % 1000).toString().padLeft(3, '0').substring(0, 1);
    return "$m:$s.$ms";
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: VoxProTheme.cardBg,
      title: const Text('Edit Sequence'),
      content: SizedBox(
        width: 500,
        height: 400,
        child: Column(
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Sequence Name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                itemCount: _segments.length,
                itemBuilder: (context, index) {
                  final seg = _segments[index];
                  return Card(
                    color: Colors.white.withOpacity(0.05),
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Segment ${index + 1}', style: const TextStyle(fontWeight: FontWeight.bold)),
                              if (_segments.length > 1)
                                IconButton(
                                  icon: const Icon(Icons.delete, color: Colors.redAccent, size: 18),
                                  onPressed: () {
                                    setState(() {
                                      _segments.removeAt(index);
                                    });
                                  },
                                ),
                            ],
                          ),
                          RangeSlider(
                            activeColor: VoxProTheme.accent,
                            inactiveColor: VoxProTheme.border,
                            min: 0,
                            max: widget.totalDuration.inMilliseconds.toDouble(),
                            values: RangeValues(
                              seg.start.inMilliseconds.toDouble(),
                              seg.end.inMilliseconds.toDouble(),
                            ),
                            onChanged: (RangeValues values) {
                              setState(() {
                                seg.start = Duration(milliseconds: values.start.toInt());
                                seg.end = Duration(milliseconds: values.end.toInt());
                              });
                            },
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _buildAdjuster('Start', seg, true),
                              _buildAdjuster('End', seg, false),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            if (_segments.length < 5)
              TextButton.icon(
                onPressed: _addSegment,
                icon: const Icon(Icons.add),
                label: const Text('Add Segment'),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel', style: TextStyle(color: VoxProTheme.textSecondary)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: VoxProTheme.accent, foregroundColor: Colors.black),
          onPressed: () {
            if (_nameController.text.trim().isEmpty) return;
            widget.onSave(NamedSequence(name: _nameController.text.trim(), segments: _segments));
            Navigator.of(context).pop();
          },
          child: const Text('Save Sequence'),
        ),
      ],
    );
  }

  Widget _buildAdjuster(String label, PlaybackSegment seg, bool isStart) {
    final val = isStart ? seg.start : seg.end;
    return Row(
      children: [
        Text('$label: ', style: const TextStyle(color: VoxProTheme.textSecondary, fontSize: 12)),
        IconButton(
          icon: const Icon(Icons.remove, size: 16),
          onPressed: () {
            setState(() {
              int newMs = val.inMilliseconds - 100;
              if (isStart) {
                if (newMs >= 0 && newMs < seg.end.inMilliseconds) seg.start = Duration(milliseconds: newMs);
              } else {
                if (newMs > seg.start.inMilliseconds) seg.end = Duration(milliseconds: newMs);
              }
            });
          },
          visualDensity: VisualDensity.compact,
        ),
        Text(_formatMs(val), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        IconButton(
          icon: const Icon(Icons.add, size: 16),
          onPressed: () {
            setState(() {
              int newMs = val.inMilliseconds + 100;
              if (isStart) {
                if (newMs < seg.end.inMilliseconds) seg.start = Duration(milliseconds: newMs);
              } else {
                if (newMs <= widget.totalDuration.inMilliseconds) seg.end = Duration(milliseconds: newMs);
              }
            });
          },
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }
}
