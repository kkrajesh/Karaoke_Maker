import 'package:flutter/material.dart';
import '../../theme/voxpro_theme.dart';
import '../../../services/performance_profile_service.dart';

class ABLoopEditorDialog extends StatefulWidget {
  final Duration totalDuration;
  final Duration initialA;
  final Duration initialB;
  final Function(Duration a, Duration b) onSave;

  const ABLoopEditorDialog({
    Key? key,
    required this.totalDuration,
    required this.initialA,
    required this.initialB,
    required this.onSave,
  }) : super(key: key);

  @override
  State<ABLoopEditorDialog> createState() => _ABLoopEditorDialogState();
}

class _ABLoopEditorDialogState extends State<ABLoopEditorDialog> {
  late Duration _currentA;
  late Duration _currentB;

  @override
  void initState() {
    super.initState();
    _currentA = widget.initialA;
    _currentB = widget.initialB;
  }

  void _adjustA(int msDelta) {
    setState(() {
      final newA = _currentA.inMilliseconds + msDelta;
      if (newA >= 0 && newA < _currentB.inMilliseconds) {
        _currentA = Duration(milliseconds: newA);
      }
    });
  }

  void _adjustB(int msDelta) {
    setState(() {
      final newB = _currentB.inMilliseconds + msDelta;
      if (newB > _currentA.inMilliseconds && newB <= widget.totalDuration.inMilliseconds) {
        _currentB = Duration(milliseconds: newB);
      }
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
      title: const Text('Edit A-B Loop'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RangeSlider(
              activeColor: VoxProTheme.accent,
              inactiveColor: VoxProTheme.border,
              min: 0,
              max: widget.totalDuration.inMilliseconds.toDouble(),
              values: RangeValues(
                _currentA.inMilliseconds.toDouble(),
                _currentB.inMilliseconds.toDouble(),
              ),
              onChanged: (RangeValues values) {
                setState(() {
                  _currentA = Duration(milliseconds: values.start.toInt());
                  _currentB = Duration(milliseconds: values.end.toInt());
                });
              },
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildAdjuster('Start (A)', _currentA, _adjustA),
                _buildAdjuster('End (B)', _currentB, _adjustB),
              ],
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
            widget.onSave(_currentA, _currentB);
            Navigator.of(context).pop();
          },
          child: const Text('Save'),
        ),
      ],
    );
  }

  Widget _buildAdjuster(String label, Duration val, Function(int) onAdjust) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: VoxProTheme.textSecondary, fontSize: 12)),
        const SizedBox(height: 4),
        Text(_formatMs(val), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.remove, size: 16),
              onPressed: () => onAdjust(-100), // -100ms
              visualDensity: VisualDensity.compact,
            ),
            IconButton(
              icon: const Icon(Icons.add, size: 16),
              onPressed: () => onAdjust(100), // +100ms
              visualDensity: VisualDensity.compact,
            ),
          ],
        )
      ],
    );
  }
}
