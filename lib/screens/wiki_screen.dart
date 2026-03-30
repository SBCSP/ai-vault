import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../providers/version_provider.dart';
import '../widgets/markdown_response.dart';

/// In-app wiki viewer. Loads markdown pages from bundled assets
/// defined in wiki/wiki.json.
class WikiScreen extends StatefulWidget {
  final bool embedded;
  const WikiScreen({super.key, this.embedded = false});

  @override
  State<WikiScreen> createState() => _WikiScreenState();
}

class _WikiScreenState extends State<WikiScreen> {
  List<_WikiSection> _sections = [];
  String? _selectedFile;
  String _pageContent = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadIndex();
  }

  Future<void> _loadIndex() async {
    try {
      final jsonStr = await rootBundle.loadString('wiki/wiki.json');
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      final sections = (json['sections'] as List<dynamic>).map((s) {
        final sec = s as Map<String, dynamic>;
        final pages = (sec['pages'] as List<dynamic>).map((p) {
          final page = p as Map<String, dynamic>;
          return _WikiPage(
            title: page['title'] as String,
            file: page['file'] as String,
          );
        }).toList();
        return _WikiSection(
          title: sec['title'] as String,
          icon: sec['icon'] as String? ?? 'article',
          pages: pages,
        );
      }).toList();

      setState(() {
        _sections = sections;
        _loading = false;
      });

      // Auto-select the first page
      if (sections.isNotEmpty && sections.first.pages.isNotEmpty) {
        _loadPage(sections.first.pages.first);
      }
    } catch (e) {
      setState(() {
        _loading = false;
        _pageContent = 'Failed to load wiki index: $e';
      });
    }
  }

  Future<void> _loadPage(_WikiPage page) async {
    setState(() {
      _selectedFile = page.file;
      _pageContent = '';
    });

    try {
      final content = await rootBundle.loadString('wiki/${page.file}');
      setState(() => _pageContent = content);
    } catch (e) {
      setState(() => _pageContent = 'Failed to load page: $e');
    }
  }

  IconData _iconFromName(String name) {
    return switch (name) {
      'rocket_launch' => Icons.rocket_launch,
      'auto_awesome' => Icons.auto_awesome,
      'shield' => Icons.shield,
      'settings' => Icons.settings,
      _ => Icons.article,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final body = _loading
          ? const Center(child: CircularProgressIndicator())
          : Row(
              children: [
                // Sidebar navigation
                SizedBox(
                  width: 240,
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border(
                        right: BorderSide(
                          color: theme.colorScheme.outlineVariant
                              .withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                    child: ListView(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      children: _sections.map((section) {
                        return _SidebarSection(
                          section: section,
                          selectedFile: _selectedFile,
                          icon: _iconFromName(section.icon),
                          onPageTap: _loadPage,
                        );
                      }).toList(),
                    ),
                  ),
                ),
                // Content area
                Expanded(
                  child: _pageContent.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.menu_book,
                                  size: 48,
                                  color: theme.colorScheme.primary
                                      .withValues(alpha: 0.4)),
                              const SizedBox(height: 12),
                              Text('Select a page',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  )),
                            ],
                          ),
                        )
                      : SingleChildScrollView(
                          padding: const EdgeInsets.all(24),
                          child: Center(
                            child: ConstrainedBox(
                              constraints:
                                  const BoxConstraints(maxWidth: 720),
                              child: MarkdownResponse(
                                data: _pageContent,
                                selectable: true,
                              ),
                            ),
                          ),
                        ),
                ),
              ],
            );

    if (widget.embedded) {
      return body;
    }

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.menu_book, size: 20, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            const Text('Wiki'),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'v$appVersion',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
      body: body,
    );
  }
}

class _SidebarSection extends StatelessWidget {
  final _WikiSection section;
  final String? selectedFile;
  final IconData icon;
  final ValueChanged<_WikiPage> onPageTap;

  const _SidebarSection({
    required this.section,
    required this.selectedFile,
    required this.icon,
    required this.onPageTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Icon(icon, size: 16, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                section.title.toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        ),
        ...section.pages.map((page) {
          final isSelected = selectedFile == page.file;
          return Material(
            color: isSelected
                ? theme.colorScheme.primaryContainer.withValues(alpha: 0.5)
                : Colors.transparent,
            child: InkWell(
              onTap: () => onPageTap(page),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Container(
                      width: 4,
                      height: 20,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? theme.colorScheme.primary
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        page.title,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight:
                              isSelected ? FontWeight.w600 : FontWeight.normal,
                          color: isSelected
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }
}

class _WikiSection {
  final String title;
  final String icon;
  final List<_WikiPage> pages;

  _WikiSection({
    required this.title,
    required this.icon,
    required this.pages,
  });
}

class _WikiPage {
  final String title;
  final String file;

  _WikiPage({required this.title, required this.file});
}
