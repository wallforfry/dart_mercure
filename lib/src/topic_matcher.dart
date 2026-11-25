/// Selects the topics a subscription receives updates for.
final class TopicMatcher {
  /// Matches the topic equal to [pattern]; `*` matches every topic.
  const TopicMatcher.exact(this.pattern) : queryParameter = 'match';

  /// Matches the topics accepted by the URL Pattern [pattern], such as
  /// `https://example.com/books/:id`.
  const TopicMatcher.urlPattern(this.pattern)
    : queryParameter = 'match_urlpattern';

  /// The topic or pattern to match.
  final String pattern;

  /// The subscription query parameter carrying this matcher.
  final String queryParameter;

  @override
  bool operator ==(Object other) =>
      other is TopicMatcher &&
      other.pattern == pattern &&
      other.queryParameter == queryParameter;

  @override
  int get hashCode => Object.hash(pattern, queryParameter);

  @override
  String toString() => '$queryParameter=$pattern';
}

/// The hub accepts between 1 and 100 matchers per subscription.
const maxMatchersPerSubscription = 100;

/// Groups [matchers] into subscription query parameters.
Map<String, List<String>> matcherQueryParameters(List<TopicMatcher> matchers) {
  if (matchers.isEmpty || matchers.length > maxMatchersPerSubscription) {
    throw ArgumentError.value(
      matchers,
      'matchers',
      'must hold between 1 and $maxMatchersPerSubscription matchers',
    );
  }
  return {
    for (final parameter in {for (final m in matchers) m.queryParameter})
      parameter: [
        for (final m in matchers)
          if (m.queryParameter == parameter) m.pattern,
      ],
  };
}
