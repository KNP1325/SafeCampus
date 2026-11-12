import 'package:flutter/material.dart';

import '../services/safety_locations_service.dart';

class SafetyLocationDialog extends StatefulWidget {
  const SafetyLocationDialog({super.key, this.location});

  final SafetyLocation? location;

  @override
  State<SafetyLocationDialog> createState() => _SafetyLocationDialogState();
}

class _SafetyLocationDialogState extends State<SafetyLocationDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.location?.name);
  late final _description = TextEditingController(
    text: widget.location?.description,
  );

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.location == null ? 'Add safety location' : 'Edit safety location',
    ),
    content: Form(
      key: _formKey,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Name'),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Enter a name.'
                  : null,
            ),
            TextFormField(
              controller: _description,
              decoration: const InputDecoration(
                labelText: 'Location description',
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Enter a description.'
                  : null,
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('CANCEL'),
      ),
      FilledButton(
        onPressed: () {
          if (_formKey.currentState!.validate()) {
            Navigator.pop(context, (
              name: _name.text.trim(),
              description: _description.text.trim(),
            ));
          }
        },
        child: const Text('SAVE'),
      ),
    ],
  );
}
