import 'package:flutter/material.dart';
import '../design/pp.dart';
import '../services/dashboard_service.dart';

class SkinDiaryBox extends StatefulWidget {
  final Map<String, dynamic>? initialData;
  final VoidCallback onSaved;

  const SkinDiaryBox({super.key, this.initialData, required this.onSaved});

  @override
  State<SkinDiaryBox> createState() => _SkinDiaryBoxState();
}

class _SkinDiaryBoxState extends State<SkinDiaryBox> {
  int _score = 3;
  List<String> _selectedTags = [];
  bool _am = false;
  bool _pm = false;
  bool _saving = false;

  final List<String> _allTags = ['Dry', 'Oily', 'Redness', 'Clear', 'Acne'];
  final List<String> _emojis = ['😫', '😕', '😐', '🙂', '🌟'];

  @override
  void initState() {
    super.initState();
    if (widget.initialData != null) {
      _score = widget.initialData!['score'] ?? 3;
      _selectedTags = List<String>.from(widget.initialData!['tags'] ?? []);
      _am = widget.initialData!['am'] ?? false;
      _pm = widget.initialData!['pm'] ?? false;
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final success = await DashboardService.saveSkinLog(
      score: _score, tags: _selectedTags, am: _am, pm: _pm
    );
    setState(() => _saving = false);
    if (success) widget.onSaved();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161213) : Colors.white,
        borderRadius: PP.r20,
        boxShadow: PP.softShadow,
        border: Border.all(color: isDark ? const Color(0xFF2A1A1F) : PP.border, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('How is your skin today?', style: PP.heading(16, color: theme.colorScheme.onSurface)),
          const SizedBox(height: 16),
          
          // Emojis
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(5, (i) => GestureDetector(
              onTap: () => setState(() => _score = i + 1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _score == i + 1 ? PP.roseTint : Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(color: _score == i + 1 ? PP.rose : Colors.transparent),
                ),
                child: Text(_emojis[i], style: const TextStyle(fontSize: 24)),
              ),
            )),
          ),
          
          const SizedBox(height: 24),
          
          // Tags
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _allTags.map((tag) {
              final isSelected = _selectedTags.contains(tag);
              return ChoiceChip(
                label: Text(tag, style: PP.label(12, color: isSelected ? Colors.white : PP.muted)),
                selected: isSelected,
                onSelected: (val) => setState(() => val ? _selectedTags.add(tag) : _selectedTags.remove(tag)),
                selectedColor: PP.rose,
                backgroundColor: isDark ? const Color(0xFF1A1015) : PP.surface,
              );
            }).toList(),
          ),

          const SizedBox(height: 24),

          // Routines
          Row(
            children: [
              _RoutineToggle(label: '☀️ AM Routine', value: _am, onChanged: (v) => setState(() => _am = v)),
              const SizedBox(width: 12),
              _RoutineToggle(label: '🌙 PM Routine', value: _pm, onChanged: (v) => setState(() => _pm = v)),
            ],
          ),

          const SizedBox(height: 28),

          // Save Button
          SizedBox(
            width: double.infinity,
            child: LuxButton(
              label: _saving ? 'Saving...' : 'Log Today\'s Entry',
              icon: Icons.edit_note_rounded,
              onPressed: _saving ? null : _save,
            ),
          ),

          const SizedBox(height: 20),
          
          // Dynamic Insight Banner
          if (_selectedTags.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 20),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: PP.goldTint.withOpacity(0.1),
                borderRadius: PP.r12,
                border: Border.all(color: PP.gold.withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  Icon(Icons.auto_awesome, color: PP.gold, size: 16),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      "Insight: Your logged '${_selectedTags.first}' markers correlate with current seasonal UV levels. Recommended: SPF 50+.",
                      style: PP.body(11, color: isDark ? Colors.white70 : PP.ink),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _RoutineToggle extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _RoutineToggle({required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(!value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: value ? PP.safe.withOpacity(0.1) : Colors.transparent,
            borderRadius: PP.r12,
            border: Border.all(color: value ? PP.safe : PP.border),
          ),
          child: Center(
            child: Text(label, style: PP.label(11, color: value ? PP.safe : PP.muted, weight: FontWeight.w600)),
          ),
        ),
      ),
    );
  }
}
