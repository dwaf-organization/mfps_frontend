import 'package:flutter/material.dart';

class IncontinenceBottomSheet extends StatefulWidget {
  final DateTime date;
  final bool initialValue;

  const IncontinenceBottomSheet({
    super.key,
    required this.date,
    required this.initialValue,
  });

  @override
  State<IncontinenceBottomSheet> createState() =>
      _IncontinenceBottomSheetState();
}

class _IncontinenceBottomSheetState extends State<IncontinenceBottomSheet> {
  late bool _hasIncontinence;

  @override
  void initState() {
    super.initState();
    _hasIncontinence = widget.initialValue;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: EdgeInsets.fromLTRB(
        24,
        16,
        24,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${widget.date.month}월 ${widget.date.day}일',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 16),

          SwitchListTile(
            title: const Text('실금 발생'),
            value: _hasIncontinence,
            activeThumbColor: Colors.white,
            activeTrackColor: const Color(0xFF6183EE),
            inactiveThumbColor: Colors.white,
            inactiveTrackColor: const Color(0xFFE5E7EB),
            onChanged: (v) {
              setState(() {
                _hasIncontinence = v;
              });
            },
          ),

          const SizedBox(height: 20),

          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  '취소',
                  style: TextStyle(color: Color(0xFF6B7280)),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6183EE),
                ),
                onPressed: () {
                  Navigator.pop(context, _hasIncontinence);
                },
                child: const Text('저장', style: TextStyle(color: Colors.black)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
