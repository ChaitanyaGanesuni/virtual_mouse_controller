import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/content/models.dart';
import '../../core/search/concepts.dart';
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
  List<ConceptEntry> _related = const [];

  /// The topic being browsed (from the topic list or a "Related to" chip).
  ConceptEntry? _topic;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _run(String q) {
    final search = ref.read(searchServiceProvider);
    setState(() {
      _topic = null;
      _hits = search.search(q);
      _related = q.trim().isEmpty ? const [] : search.conceptsOf(q);
    });
  }

  void _openTopic(ConceptEntry topic) {
    final search = ref.read(searchServiceProvider);
    setState(() {
      _topic = topic;
      _hits = search.topic(topic.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final repo = ref.watch(contentRepositoryProvider);
    final settings = ref.watch(settingsProvider);
    final script = settings.verseScript;
    final lang = settings.uiLanguage;
    final theme = Theme.of(context);
    final query = _controller.text.trim();

    String fieldName(MatchField f) => switch (f) {
      MatchField.reference => l.matchReference,
      MatchField.sanskrit => l.matchSanskrit,
      MatchField.transliteration => l.matchTransliteration,
      MatchField.teluguScript => l.matchTelugu,
      MatchField.translation => l.matchTranslation,
      MatchField.explanation => l.matchExplanation,
      MatchField.concept => l.matchConcept,
      MatchField.keywords => l.matchKeywords,
    };

    String topicLabel(ConceptEntry c) => c.termSa.isEmpty ? c.name(lang) : '${c.name(lang)} (${c.termSa})';

    /// Start of the verse's translation, for results found by meaning.
    String? translation(Verse verse) {
      final ts = verse.texts.where((t) => t.kind == 'translation');
      return (ts.where((t) => t.language == settings.translationLanguage).firstOrNull ??
              ts.where((t) => t.language == 'en').firstOrNull)
          ?.body;
    }

    Widget results() => ListView.separated(
      // A new list per topic or query, so it starts at the top.
      key: ValueKey(_topic?.id ?? 'query:$query'),
      itemCount: _hits.length + 1,
      separatorBuilder: (_, i) => i == 0 ? const SizedBox.shrink() : const Divider(indent: 20, endIndent: 20),
      itemBuilder: (context, i) {
        if (i == 0) {
          if (_topic != null) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(topicLabel(_topic!), style: theme.textTheme.titleMedium),
                  if (_topic!.definition != null && lang == 'en') ...[
                    const SizedBox(height: 4),
                    Text(_topic!.definition!, style: theme.textTheme.bodySmall),
                  ],
                  const SizedBox(height: 4),
                  Text(l.topicVerses, style: theme.textTheme.labelSmall),
                ],
              ),
            );
          }
          if (_related.isEmpty) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('${l.relatedTo}:', style: theme.textTheme.labelMedium),
                for (final c in _related)
                  ActionChip(label: Text(topicLabel(c)), onPressed: () => _openTopic(c)),
              ],
            ),
          );
        }
        final hit = _hits[i - 1];
        final verse = repo.verse(hit.verseId)!;
        final excerpt = hit.snippet == null && hit.field != MatchField.transliteration
            ? translation(verse)
            : null;
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
                _Snippet(hit.snippet!)
              else if (excerpt != null)
                Text(excerpt, maxLines: 2, overflow: TextOverflow.ellipsis),
              Text('${verse.id} · ${fieldName(hit.field)}', style: theme.textTheme.bodySmall),
            ],
          ),
          onTap: () => context.push('/verse/${verse.id}'),
        );
      },
    );

    Widget topics() {
      final all = ref.read(searchServiceProvider).topics().toList()
        ..sort((a, b) => a.name(lang).toLowerCase().compareTo(b.name(lang).toLowerCase()));
      return ListView(
        key: const ValueKey('topics'),
        padding: const EdgeInsets.all(20),
        children: [
          Text(l.searchByMeaning, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 20),
          Text(l.browseTopics, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final c in all) ActionChip(label: Text(topicLabel(c)), onPressed: () => _openTopic(c)),
            ],
          ),
        ],
      );
    }

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
          if (query.isNotEmpty || _topic != null)
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
      body: _topic != null
          ? results()
          : query.isEmpty
          ? topics()
          : _hits.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.searchNoResults, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(l.searchByMeaning, style: theme.textTheme.bodySmall),
                ],
              ),
            )
          : results(),
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
