import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/shared/widgets/widgets.dart';

/// Reusable Host & Port input row for database connection forms (#1364).
class ConnectionHostPortSection extends StatelessWidget {
  const ConnectionHostPortSection({
    super.key,
    required this.hostController,
    required this.portController,
    this.hostPlaceholder = 'localhost',
    this.portPlaceholder = '5432',
    this.hostLabel = 'Host',
    this.portLabel = 'Port',
    this.hostFlex = 3,
    this.portFlex = 2,
    this.gap = 16,
  });

  final material.TextEditingController hostController;
  final material.TextEditingController portController;
  final String hostPlaceholder;
  final String portPlaceholder;
  final String hostLabel;
  final String portLabel;
  final int hostFlex;
  final int portFlex;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return material.Row(
      crossAxisAlignment: material.CrossAxisAlignment.start,
      children: [
        material.Expanded(
          flex: hostFlex,
          child: material.Column(
            crossAxisAlignment: material.CrossAxisAlignment.stretch,
            mainAxisSize: material.MainAxisSize.min,
            children: [
              Text(hostLabel).small().semiBold(),
              const Gap(8),
              TextField(
                controller: hostController,
                placeholder: Text(hostPlaceholder),
              ),
            ],
          ),
        ),
        Gap(gap),
        material.Expanded(
          flex: portFlex,
          child: material.Column(
            crossAxisAlignment: material.CrossAxisAlignment.stretch,
            mainAxisSize: material.MainAxisSize.min,
            children: [
              Text(portLabel).small().semiBold(),
              const Gap(8),
              TextField(
                controller: portController,
                placeholder: Text(portPlaceholder),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
