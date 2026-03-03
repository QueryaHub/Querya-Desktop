import 'package:flutter/material.dart' as material show Center;
import 'package:querya_desktop/shared/widgets/widgets.dart';

class ResultsTab extends StatelessWidget {
  const ResultsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return material.Center(
      child: Text('Results').muted(),
    );
  }
}
