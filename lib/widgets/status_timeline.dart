import 'package:flutter/material.dart';

class StatusTimeline extends StatelessWidget {
  final List<Map<String, dynamic>> events; // {status, note, location, created_at}
  const StatusTimeline({super.key, required this.events});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (events.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: const [BoxShadow(blurRadius:8, color: Color(0x11000000), offset: Offset(0,3))]),
        child: const Text('No tracking updates yet.'),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: const [BoxShadow(blurRadius:8, color: Color(0x11000000), offset: Offset(0,3))]),
      child: ListView.separated(
        shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
        itemCount: events.length, separatorBuilder: (_, __) => const SizedBox(height: 0),
        itemBuilder: (_, i) {
          final e = events[i];
          final ts = DateTime.tryParse('${e['created_at']}')?.toLocal();
          final isLatest = i == events.length - 1;
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SizedBox(width: 16),
            Column(children: [
              Container(width:14, height:14, decoration: BoxDecoration(color: isLatest?Colors.green:Colors.grey, shape: BoxShape.circle)),
              if (i != 0) Container(width:2, height:48, color: Colors.grey.shade300),
            ]),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right:16, bottom:12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${e['status']}'.replaceAll('_',' ').toUpperCase(), style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w800)),
                  if ((e['note'] ?? '').toString().isNotEmpty) Padding(padding: const EdgeInsets.only(top:2), child: Text('${e['note']}', style: theme.textTheme.bodyMedium)),
                  if ((e['location'] ?? '').toString().isNotEmpty) Padding(padding: const EdgeInsets.only(top:2), child: Text('${e['location']}', style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey))),
                  if (ts != null) Padding(padding: const EdgeInsets.only(top:2), child: Text('$ts', style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey))),
                ]),
              ),
            ),
          ]);
        },
      ),
    );
  }
}
