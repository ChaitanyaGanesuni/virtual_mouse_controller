import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/content/models.dart';
import '../../core/search/search_service.dart';
import '../../l10n/app_localizations.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  List<SearchHit> _hits = const [];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _run(String q) => setState(() => _hits = ref.read(searchServiceProvider).search(q));

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final repo = ref.watch(contentRepositoryProvider);
    final script = ref.watch(settingsProvider).verseScript;
    final theme = Theme.of(context);
    final query = _controller.text.trim();

    String fieldName(MatchField f) => switch (f) {
      MatchField.reference => l.matchReference,
      MatchField.sanskrit => l.matchSanskrit,
      MatchField.transliteration => l.matchTransliteration,
      MatchField.teluguScript => l.matchTelugu,
      MatchField.translation => l.matchTranslation,
      MatchField.explanation => l.matchExplanation,
    };

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(hintText: l.searchHint, border: InputBorder.none),
          onChanged: _run,
          onSubmitted: _run,
        ),
        actions: [
          if (query.isNotEmpty)
            IconButton(
              tooltip: MaterialLocalizations.of(context).deleteButtonTooltip,
              icon: const Icon(Icons.close),
              onPressed: () {
                _controller.clear();
                _run('');
              },
            ),
        ],
      ),
      body: query.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(24),
              child: Text(l.searchMeaningLater, style: theme.textTheme.bodyMedium),
            )
          : _hits.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.searchNoResults, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(l.searchMeaningLater, style: theme.textTheme.bodySmall),
                ],
              ),
            )
          : ListView.separated(
              itemCount: _hits.length,
              separatorBuilder: (_, _) => const Divider(indent: 20, endIndent: 20),
              itemBuilder: (context, i) {
                final hit = _hits[i];
                final verse = repo.verse(hit.verseId)!;
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                  title: Text(
                    verse.textIn(script).split('\n').first,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ScriptureStyles.verse(context, script, 0.7),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (hit.field == MatchField.transliteration)
                        _IastMatch(verse.textIn(VerseScript.iast).replaceAll('\n', ' '), query)
                      else if (hit.snippet != null)
                        _Snippet(hit.snippet!),
                      Text('${verse.id} · ${fieldName(hit.field)}', style: theme.textTheme.bodySmall),
                    ],
                  ),
                  onTap: () => context.push('/verse/${verse.id}'),
                );
              },
            ),
    );
  }
}

/// Renders an FTS snippet, emphasising the «matched» part.
class _Snippet extends StatelessWidget {
  const _Snippet(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final spans = <TextSpan>[];
    final re = RegExp('«([^»]*)»');
    var last = 0;
    for (final m in re.allMatches(text)) {
      spans.add(TextSpan(text: text.substring(last, m.start)));
      spans.add(
        TextSpan(
          text: m.group(1),
          style: TextStyle(color: accent, fontWeight: FontWeight.w600),
        ),
      );
      last = m.end;
    }
    spans.add(TextSpan(text: text.substring(last)));
    return Text.rich(
      TextSpan(children: spans),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontFamilyFallback: ['NotoSerifDevanagari', 'NotoSansTelugu']),
    );
  }
}

/// IAST of the verse with the words that matched the query emphasised.
class _IastMatch extends StatelessWidget {
  const _IastMatch(this.iast, this.query);

  final String iast;
  final String query;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Text.rich(
      TextSpan(
        children: [
          for (final (word, hit) in highlightIast(iast, query))
            TextSpan(
              text: word,
              style: hit ? TextStyle(color: accent, fontWeight: FontWeight.w600) : null,
            ),
        ],
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontFamily: 'NotoSerif', fontFamilyFallback: ['NotoSerifDevanagari']),
    );
  }
}
