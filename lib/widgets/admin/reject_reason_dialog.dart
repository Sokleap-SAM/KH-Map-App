import 'package:flutter/material.dart';

import '../../utils/constants/colors.dart';

/// Prompts the admin for a required rejection reason before rejecting a place
/// request. Returns the trimmed reason, or null if the admin cancelled.
///
/// The reason is stored on the request and shown to the submitter so they can
/// see why the place was rejected and fix/re-submit it.
Future<String?> showRejectReasonDialog(
  BuildContext context, {
  required String placeName,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _RejectReasonDialog(placeName: placeName),
  );
}

class _RejectReasonDialog extends StatefulWidget {
  final String placeName;

  const _RejectReasonDialog({required this.placeName});

  @override
  State<_RejectReasonDialog> createState() => _RejectReasonDialogState();
}

class _RejectReasonDialogState extends State<_RejectReasonDialog> {
  final TextEditingController _controller = TextEditingController();
  String? _errorText;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final reason = _controller.text.trim();
    if (reason.isEmpty) {
      setState(() => _errorText = 'សូមបញ្ជាក់មូលហេតុនៃការបដិសេធ');
      return;
    }
    Navigator.of(context).pop(reason);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text('បដិសេធ «${widget.placeName}»'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'សូមសរសេររបាយការណ៍ថាហេតុអ្វីបានជាបដិសេធ ដើម្បីឲ្យអ្នកស្នើអាចមើលឃើញ '
            'និងកែសម្រួល។',
            style: TextStyle(fontSize: 13, color: Colors.black54),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _controller,
            autofocus: true,
            minLines: 3,
            maxLines: 5,
            maxLength: 1000,
            textInputAction: TextInputAction.newline,
            onChanged: (_) {
              if (_errorText != null) setState(() => _errorText = null);
            },
            decoration: InputDecoration(
              hintText: 'ឧ. រូបភាពមិនច្បាស់ / ទីតាំងមិនត្រឹមត្រូវ ...',
              errorText: _errorText,
              border: const OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('បោះបង់'),
        ),
        FilledButton(
          onPressed: _submit,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.alertBorderColor,
          ),
          child: const Text('បដិសេធ'),
        ),
      ],
    );
  }
}
