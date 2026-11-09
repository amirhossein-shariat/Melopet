import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../utils/format.dart';
import 'glass.dart';

/// Labeled text field with consistent spacing.
class Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData? icon;
  final String? hint;
  final bool required;
  final bool ltr;
  final TextInputType? keyboard;
  final int maxLines;
  final String? Function(String)? validator;
  final bool obscure;

  const Field(
    this.controller,
    this.label, {
    super.key,
    this.icon,
    this.hint,
    this.required = false,
    this.ltr = false,
    this.keyboard,
    this.maxLines = 1,
    this.validator,
    this.obscure = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboard,
        maxLines: maxLines,
        obscureText: obscure,
        textDirection: ltr ? TextDirection.ltr : null,
        decoration: InputDecoration(
          labelText: required ? '$label *' : label,
          hintText: hint,
          prefixIcon: icon != null ? Icon(icon) : null,
          alignLabelWithHint: maxLines > 1,
        ),
        validator: (v) {
          final s = enNum(v?.trim() ?? '');
          if (required && s.isEmpty) return '$label را وارد کنید';
          if (validator != null && s.isNotEmpty) return validator!(s);
          return null;
        },
      ),
    );
  }
}

String? mobileValidator(String s) => RegExp(r'^09\d{9}$').hasMatch(s) ? null : 'شماره موبایل معتبر نیست (09xxxxxxxxx)';
String? phoneValidator(String s) => RegExp(r'^[0-9\-\s]{6,15}$').hasMatch(s) ? null : 'شماره تلفن معتبر نیست';

/// A picked file kept in memory until upload.
class PickedBytes {
  final String name;
  final Uint8List bytes;
  PickedBytes(this.name, this.bytes);

  http.MultipartFile toMultipart(String field) => http.MultipartFile.fromBytes(field, bytes, filename: name);

  bool get isImage {
    final n = name.toLowerCase();
    return n.endsWith('.png') || n.endsWith('.jpg') || n.endsWith('.jpeg') || n.endsWith('.webp') || n.endsWith('.gif');
  }
}

Future<PickedBytes?> pickOne({bool imagesOnly = false}) async {
  final files = await FilePicker.pickFiles(type: imagesOnly ? FileType.image : FileType.any);
  if (files.isEmpty) return null;
  final f = files.first;
  return PickedBytes(f.name, await f.readAsBytes());
}

/// Image picker tile with preview.
class ImagePickTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final PickedBytes? file;
  final String? currentUrl;
  final VoidCallback onPick;
  final VoidCallback? onClear;
  final double previewHeight;

  const ImagePickTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onPick,
    this.file,
    this.currentUrl,
    this.onClear,
    this.previewHeight = 120,
  });

  @override
  Widget build(BuildContext context) {
    Widget? preview;
    if (file != null) {
      preview = Image.memory(file!.bytes, height: previewHeight, fit: BoxFit.contain);
    } else if (currentUrl != null && currentUrl!.isNotEmpty) {
      preview = Image.network(currentUrl!, height: previewHeight, fit: BoxFit.contain);
    }
    return Glass(
      margin: const EdgeInsets.only(bottom: 12),
      onTap: onPick,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const GlassIcon(Icons.add_photo_alternate_rounded, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text(subtitle, style: const TextStyle(fontSize: 12)),
                  ],
                ),
              ),
              if (onClear != null && file != null) IconButton(onPressed: onClear, icon: const Icon(Icons.close_rounded)),
            ],
          ),
          if (preview != null) ...[const SizedBox(height: 12), ClipRRect(borderRadius: BorderRadius.circular(12), child: preview)],
        ],
      ),
    );
  }
}

/// Choice chips for select fields.
class ChoiceRow extends StatelessWidget {
  final Map<String, String> options;
  final String? value;
  final ValueChanged<String> onChanged;
  const ChoiceRow({super.key, required this.options, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final e in options.entries) MPChoiceChip(label: e.value, selected: value == e.key, onSelected: (_) => onChanged(e.key)),
      ],
    );
  }
}

/// Validates [form]. When something is missing the user is TOLD (a toast naming the first problem
/// and how many there are) and the screen scrolls to the first invalid field — fields that are
/// off-screen must never fail silently.
bool validateForm(BuildContext context, GlobalKey<FormState> form) {
  final state = form.currentState;
  if (state == null) return true;
  if (state.validate()) return true;

  final problems = <({String text, BuildContext ctx})>[];
  void visit(Element e) {
    if (e is StatefulElement && e.state is FormFieldState && (e.state as FormFieldState).hasError) {
      problems.add((text: (e.state as FormFieldState).errorText ?? '', ctx: e));
      return;
    }
    e.visitChildren(visit);
  }

  form.currentContext?.visitChildElements(visit);
  if (problems.isNotEmpty) {
    final first = problems.first;
    toast(context, problems.length == 1 ? first.text : '${first.text} (و ${faNum(problems.length - 1)} مورد دیگر)', error: true);
    Scrollable.ensureVisible(first.ctx, alignment: .15, duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic);
  } else {
    toast(context, 'موارد ستاره‌دار را کامل کنید', error: true);
  }
  return false;
}
