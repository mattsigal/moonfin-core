import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:moonfin_design/moonfin_design.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../../util/platform_detection.dart';
import '../../../../util/focus/dpad_keys.dart';
import '../../../screens/book/discover/discover_book_detail_screen.dart';
import '../../../screens/book/discover/librivox_authors_screen.dart';
import '../../../screens/book/discover/librivox_book_detail_screen.dart';
import '../../adaptive/sf_symbol.dart';
import 'book_discovery_models.dart';

const _bookAccent = bookDiscoverAccent;

class BookDiscoverTab extends StatefulWidget {
  final String libraryId;
  final bool isAudiobook;
  final FocusNode? firstFocusNode;
  final FocusNode? settingsMenuFocusNode;
  final VoidCallback? onSettingsUpPressed;
  final double leftPadding;

  const BookDiscoverTab({
    super.key,
    required this.libraryId,
    required this.isAudiobook,
    required this.leftPadding,
    this.firstFocusNode,
    this.settingsMenuFocusNode,
    this.onSettingsUpPressed,
  });

  @override
  State<BookDiscoverTab> createState() => _BookDiscoverTabState();
}

class _BookDiscoverTabState extends State<BookDiscoverTab> {
  final Dio _discoverDio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 7),
      receiveTimeout: const Duration(seconds: 12),
    ),
  );

  List<String> _discoverGenres = const ['fantasy', 'romance', 'science_fiction'];
  final Map<String, List<DiscoverBook>> _discoverBooksByGenre = {};
  final Map<String, ScrollController> _discoverRowControllers = {};
  final Set<String> _discoverLoadingGenres = {};
  final Set<String> _discoverFailedGenres = {};
  bool _discoverInitialized = false;
  bool _discoverBootstrapping = false;

  List<String> _discoverAudiobookGenres = const [
    'Science Fiction',
    'Fantasy Fiction',
    'Mystery & Detective Stories',
  ];
  final Map<String, List<LibrivoxBook>> _discoverAudiobooksByGenre = {};
  final Map<String, ScrollController> _discoverAudiobookRowControllers = {};
  final Set<String> _discoverAudiobookLoadingGenres = {};
  final Set<String> _discoverAudiobookFailedGenres = {};
  bool _discoverAudiobookInitialized = false;
  bool _discoverAudiobookBootstrapping = false;
  final Map<String, String?> _librivoxCoverCache = {};
  final Map<String, List<FocusNode>> _genreFocusNodesMap = {};
  bool _isGenreSheetShowing = false;
  bool _isAudiobookGenreSheetShowing = false;

  List<FocusNode> _focusNodesForGenre(String genre, int count) {
    return _genreFocusNodesMap.putIfAbsent(
      genre,
      () => List.generate(
        count,
        (index) => FocusNode(debugLabel: 'Discover_${genre}_$index'),
      ),
    );
  }

  double _calculateAdjustedCardWidth(double maxWidth, double baseCardWidth) {
    const spacing = 12.0;
    final n = ((maxWidth + spacing) / (baseCardWidth + spacing)).floor();
    final count = n.clamp(1, 99);
    return (maxWidth - (count - 1) * spacing) / count;
  }

  void _focusRow(String genre, bool goDown) {
    final genresList = widget.isAudiobook ? _discoverAudiobookGenres : _discoverGenres;
    final genreIndex = genresList.indexOf(genre);
    if (genreIndex == -1) return;

    final items = widget.isAudiobook
        ? (_discoverAudiobooksByGenre[genre] ?? const [])
        : (_discoverBooksByGenre[genre] ?? const []);
    final hasFailed = widget.isAudiobook
        ? _discoverAudiobookFailedGenres.contains(genre)
        : _discoverFailedGenres.contains(genre);
    final isLoading = widget.isAudiobook
        ? _discoverAudiobookLoadingGenres.contains(genre)
        : _discoverLoadingGenres.contains(genre);

    if (items.isNotEmpty || hasFailed) {
      final controller = widget.isAudiobook
          ? _discoverAudiobookRowControllers[genre]
          : _discoverRowControllers[genre];
      if (controller != null && controller.hasClients) {
        controller.jumpTo(0.0);
      }

      final isFirstRow = genreIndex == 0;
      if (isFirstRow) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          widget.firstFocusNode?.requestFocus();
        });
      } else {
        final nodes = _focusNodesForGenre(genre, items.length);
        if (nodes.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            nodes[0].requestFocus();
          });
        }
      }
    } else if (isLoading) {
      final nextIndex = goDown ? genreIndex + 1 : genreIndex - 1;
      if (nextIndex >= 0 && nextIndex < genresList.length) {
        _focusRow(genresList[nextIndex], goDown);
      }
    }
  }

  @override
  void initState() {
    super.initState();
    unawaited(_loadDiscoverPreferences());
    if (widget.isAudiobook) {
      unawaited(_bootstrapAudiobookDiscovery());
    } else {
      unawaited(_bootstrapDiscovery());
    }
  }

  @override
  void dispose() {
    for (final controller in _discoverRowControllers.values) {
      controller.dispose();
    }
    for (final controller in _discoverAudiobookRowControllers.values) {
      controller.dispose();
    }
    for (final nodesList in _genreFocusNodesMap.values) {
      for (final node in nodesList) {
        node.dispose();
      }
    }
    _genreFocusNodesMap.clear();
    _discoverDio.close(force: true);
    super.dispose();
  }

  Future<void> _loadDiscoverPreferences() async {
    final prefs = await SharedPreferences.getInstance();

    final storedSubjects = prefs
        .getStringList(bookDiscoverSubjectsPrefKey)
        ?.where(bookDiscoverGenrePool.contains)
        .toSet()
        .toList();

    final storedAudiobookGenres = prefs
        .getStringList(bookDiscoverAudiobookGenresPrefKey)
        ?.where(librivoxGenrePool.contains)
        .toSet()
        .toList();

    if (!mounted) return;

    final nextSubjects = (storedSubjects == null || storedSubjects.isEmpty)
        ? _discoverGenres
        : (storedSubjects
            ..sort(
              (a, b) => displayBookGenre(a).compareTo(displayBookGenre(b)),
            ));
    final nextAudiobookGenres =
        (storedAudiobookGenres == null || storedAudiobookGenres.isEmpty)
        ? _discoverAudiobookGenres
        : (storedAudiobookGenres..sort());

    final subjectsChanged =
        nextSubjects.length != _discoverGenres.length ||
        nextSubjects.any((s) => !_discoverGenres.contains(s));
    final audiobookChanged =
        nextAudiobookGenres.length != _discoverAudiobookGenres.length ||
        nextAudiobookGenres.any((g) => !_discoverAudiobookGenres.contains(g));

    if (!subjectsChanged && !audiobookChanged) return;

    setState(() {
      if (subjectsChanged) {
        _discoverGenres = nextSubjects;
        _discoverInitialized = false;
        _discoverBooksByGenre.clear();
        _discoverLoadingGenres.clear();
        _discoverFailedGenres.clear();
        for (final controller in _discoverRowControllers.values) {
          controller.dispose();
        }
        _discoverRowControllers.clear();
      }

      if (audiobookChanged) {
        _discoverAudiobookGenres = nextAudiobookGenres;
        _discoverAudiobookInitialized = false;
        _discoverAudiobooksByGenre.clear();
        _discoverAudiobookLoadingGenres.clear();
        _discoverAudiobookFailedGenres.clear();
        for (final controller in _discoverAudiobookRowControllers.values) {
          controller.dispose();
        }
        _discoverAudiobookRowControllers.clear();
      }
    });

    if (subjectsChanged && !widget.isAudiobook) {
      unawaited(_bootstrapDiscovery());
    }
    if (audiobookChanged && widget.isAudiobook) {
      unawaited(_bootstrapAudiobookDiscovery());
    }
  }

  Future<void> _bootstrapDiscovery() async {
    if (_discoverBootstrapping) return;
    _discoverBootstrapping = true;
    try {
      await Future.wait(
        _discoverGenres.map(
          (subject) => _loadDiscoverPage(subject, reset: true),
        ),
      );
      if (mounted) {
        setState(() => _discoverInitialized = true);
      }
    } finally {
      _discoverBootstrapping = false;
    }
  }

  ScrollController _controllerForDiscoverSubject(String subject) {
    return _discoverRowControllers.putIfAbsent(subject, ScrollController.new);
  }

  Future<void> _scrollDiscoverSubjectRow(String subject, int direction) async {
    final controller = _controllerForDiscoverSubject(subject);
    if (!controller.hasClients) return;

    final viewport = controller.position.viewportDimension;
    final scrollAmount = (viewport * 0.84).clamp(180.0, 420.0);
    final target = (controller.offset + (scrollAmount * direction)).clamp(
      0.0,
      controller.position.maxScrollExtent,
    );
    if ((target - controller.offset).abs() < 1) return;

    await controller.animateTo(
      target,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _loadDiscoverPage(String subject, {bool reset = false}) async {
    if (_discoverLoadingGenres.contains(subject)) return;

    setState(() {
      _discoverLoadingGenres.add(subject);
      _discoverFailedGenres.remove(subject);
      if (reset) {
        _discoverBooksByGenre[subject] = <DiscoverBook>[];
      }
    });

    try {
      final subjectKey = Uri.decodeComponent(subject);
      final response = await _discoverDio.get<Map<String, dynamic>>(
        'https://openlibrary.org/search.json',
        queryParameters: {
          'q': 'subject_key:"$subjectKey"',
          'sort': 'trending',
          'limit': bookDiscoverPageSize,
          'page': 1,
        },
      );
      final data = response.data ?? const <String, dynamic>{};
      final docs = (data['docs'] as List?) ?? const [];
      final parsed = docs
          .whereType<Map>()
          .map(
            (w) =>
                DiscoverBook.fromOpenLibraryMap(Map<String, dynamic>.from(w)),
          )
          .where((book) => book.title.trim().isNotEmpty)
          .toList();

      if (!mounted) return;
      setState(() {
        _discoverBooksByGenre[subject] = parsed;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _discoverFailedGenres.add(subject));
    } finally {
      if (mounted) {
        setState(() => _discoverLoadingGenres.remove(subject));
      }
    }
  }

  Future<void> _showDiscoverGenreSheet() async {
    if (_isGenreSheetShowing) return;
    _isGenreSheetShowing = true;
    List<String>? result;
    try {
      final temp = {..._discoverGenres};
      final sortedSubjects = bookDiscoverGenrePool.toList()
        ..sort((a, b) => displayBookGenre(a).compareTo(displayBookGenre(b)));
      result = await showGeneralDialog<List<String>>(
        context: context,
        barrierDismissible: true,
        barrierLabel: AppLocalizations.of(context).close,
        barrierColor: Colors.black54,
        transitionDuration: const Duration(milliseconds: 260),
        pageBuilder: (context, _, _) => _GenreDialogContent(
          title: AppLocalizations.of(context).discoverySubjects,
          subtitle: AppLocalizations.of(context).pickDiscoverySubjects,
          allGenres: sortedSubjects,
          initialSelectedGenres: temp.toList(),
          displayFn: displayBookGenre,
        ),
        transitionBuilder: (context, animation, _, child) {
          return SlideTransition(
            position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
                .animate(
                  CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
                ),
            child: child,
          );
        },
      );
    } finally {
      _isGenreSheetShowing = false;
    }

    if (result == null || result.isEmpty || !mounted) return;
    final sortedResult = result.toList()
      ..sort((a, b) => displayBookGenre(a).compareTo(displayBookGenre(b)));
    final changed =
        sortedResult.length != _discoverGenres.length ||
        sortedResult.any((s) => !_discoverGenres.contains(s));
    if (!changed) return;

    setState(() {
      _discoverGenres = sortedResult;
      _discoverInitialized = false;
      _discoverBooksByGenre.clear();
      _discoverLoadingGenres.clear();
      _discoverFailedGenres.clear();
      for (final controller in _discoverRowControllers.values) {
        controller.dispose();
      }
      _discoverRowControllers.clear();
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(bookDiscoverSubjectsPrefKey, sortedResult);
    await _bootstrapDiscovery();
  }

  Future<void> _bootstrapAudiobookDiscovery() async {
    if (_discoverAudiobookBootstrapping) return;
    _discoverAudiobookBootstrapping = true;
    try {
      await Future.wait(
        _discoverAudiobookGenres.map(
          (genre) => _loadAudiobookDiscoverPage(genre, reset: true),
        ),
      );
      if (mounted) {
        setState(() => _discoverAudiobookInitialized = true);
      }
    } finally {
      _discoverAudiobookBootstrapping = false;
    }
  }

  ScrollController _controllerForAudiobookDiscoverGenre(String genre) {
    return _discoverAudiobookRowControllers.putIfAbsent(
      genre,
      ScrollController.new,
    );
  }

  Future<void> _scrollAudiobookDiscoverRow(String genre, int direction) async {
    final controller = _controllerForAudiobookDiscoverGenre(genre);
    if (!controller.hasClients) return;

    final viewport = controller.position.viewportDimension;
    final scrollAmount = (viewport * 0.84).clamp(180.0, 420.0);
    final target = (controller.offset + (scrollAmount * direction)).clamp(
      0.0,
      controller.position.maxScrollExtent,
    );
    if ((target - controller.offset).abs() < 1) return;

    await controller.animateTo(
      target,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _loadAudiobookDiscoverPage(
    String genre, {
    bool reset = false,
  }) async {
    if (_discoverAudiobookLoadingGenres.contains(genre)) return;

    setState(() {
      _discoverAudiobookLoadingGenres.add(genre);
      _discoverAudiobookFailedGenres.remove(genre);
      if (reset) {
        _discoverAudiobooksByGenre[genre] = <LibrivoxBook>[];
      }
    });

    try {
      final response = await _discoverDio.get<Map<String, dynamic>>(
        'https://librivox.org/api/feed/audiobooks/',
        queryParameters: {
          'format': 'json',
          'genre': genre,
          'sort_field': 'popularity',
          'sort_order': 'desc',
          'limit': bookDiscoverPageSize,
        },
      );
      final data = response.data ?? const <String, dynamic>{};
      final books = (data['books'] as List?) ?? const [];
      final parsed = books
          .whereType<Map>()
          .map((b) => LibrivoxBook.fromMap(Map<String, dynamic>.from(b)))
          .where((book) => book.title.isNotEmpty)
          .toList();

      if (!mounted) return;
      setState(() {
        _discoverAudiobooksByGenre[genre] = parsed;
      });
      unawaited(_fetchCoversForBooks(parsed));
    } catch (_) {
      if (!mounted) return;
      setState(() => _discoverAudiobookFailedGenres.add(genre));
    } finally {
      if (mounted) {
        setState(() => _discoverAudiobookLoadingGenres.remove(genre));
      }
    }
  }

  Future<void> _fetchCoversForBooks(List<LibrivoxBook> books) async {
    const batchSize = 8;
    final unresolved = <LibrivoxBook>[];
    final immediateUpdates = <String, String?>{};

    for (final book in books) {
      if (_librivoxCoverCache.containsKey(book.id) ||
          immediateUpdates.containsKey(book.id)) {
        continue;
      }
      final archiveCover = _archiveCoverUrlForBook(book);
      if (archiveCover != null) {
        immediateUpdates[book.id] = archiveCover;
        continue;
      }
      final isbnCover = _isbnCoverUrlForBook(book);
      if (isbnCover != null) {
        immediateUpdates[book.id] = isbnCover;
        continue;
      }
      unresolved.add(book);
    }

    if (mounted && immediateUpdates.isNotEmpty) {
      setState(() => _librivoxCoverCache.addAll(immediateUpdates));
    }

    for (var i = 0; i < unresolved.length; i += batchSize) {
      if (!mounted) return;
      final batch = unresolved.skip(i).take(batchSize).toList();
      final results = await Future.wait(
        batch.map(_searchOpenLibraryCoverForBook),
      );
      if (!mounted) return;
      setState(() {
        for (var j = 0; j < batch.length; j++) {
          _librivoxCoverCache[batch[j].id] = results[j];
        }
      });
    }
  }

  String? _archiveCoverUrlForBook(LibrivoxBook book) {
    final archiveUrl = book.archiveUrl;
    if ((archiveUrl ?? '').isEmpty) return null;
    final uri = Uri.tryParse(archiveUrl!);
    final segments = uri?.pathSegments.where((s) => s.isNotEmpty).toList();
    final identifier = segments?.isNotEmpty == true ? segments!.last : null;
    if (identifier == null || identifier.isEmpty) return null;
    return 'https://archive.org/services/img/$identifier';
  }

  String? _isbnCoverUrlForBook(LibrivoxBook book) {
    final isbn = book.preferredIsbn;
    if (isbn == null || isbn.isEmpty) return null;
    return 'https://covers.openlibrary.org/b/isbn/$isbn-M.jpg?default=false';
  }

  Future<String?> _searchOpenLibraryCoverForBook(LibrivoxBook book) async {
    try {
      final response = await _discoverDio.get<Map<String, dynamic>>(
        'https://openlibrary.org/search.json',
        queryParameters: {
          'q': '${book.title} ${book.authorName}',
          'limit': 1,
          'fields': 'cover_i',
        },
      );
      final docs = (response.data?['docs'] as List?) ?? const [];
      final coverId = docs.whereType<Map>().firstOrNull?['cover_i'] as num?;
      return coverId != null
          ? 'https://covers.openlibrary.org/b/id/${coverId.toInt()}-M.jpg'
          : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _showAudiobookGenreSheet() async {
    if (_isAudiobookGenreSheetShowing) return;
    _isAudiobookGenreSheetShowing = true;
    List<String>? result;
    try {
      final temp = {..._discoverAudiobookGenres};
      final l10n = AppLocalizations.of(context);
      final sortedGenres = librivoxGenrePool.toList()..sort();
      result = await showGeneralDialog<List<String>>(
        context: context,
        barrierDismissible: true,
        barrierLabel: l10n.closeGenrePanel,
        barrierColor: Colors.black54,
        transitionDuration: const Duration(milliseconds: 260),
        pageBuilder: (context, _, _) => _GenreDialogContent(
          title: AppLocalizations.of(context).audiobookGenres,
          subtitle: AppLocalizations.of(context).pickAudiobookGenres,
          allGenres: sortedGenres,
          initialSelectedGenres: temp.toList(),
          displayFn: (s) => s,
        ),
        transitionBuilder: (context, animation, _, child) {
          return SlideTransition(
            position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
                .animate(
                  CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
                ),
            child: child,
          );
        },
      );
    } finally {
      _isAudiobookGenreSheetShowing = false;
    }

    if (result == null || result.isEmpty || !mounted) return;
    final sortedResult = result.toList()..sort();
    final changed =
        sortedResult.length != _discoverAudiobookGenres.length ||
        sortedResult.any((s) => !_discoverAudiobookGenres.contains(s));
    if (!changed) return;

    setState(() {
      _discoverAudiobookGenres = sortedResult;
      _discoverAudiobookInitialized = false;
      _discoverAudiobooksByGenre.clear();
      _discoverAudiobookLoadingGenres.clear();
      _discoverAudiobookFailedGenres.clear();
      for (final controller in _discoverAudiobookRowControllers.values) {
        controller.dispose();
      }
      _discoverAudiobookRowControllers.clear();
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(bookDiscoverAudiobookGenresPrefKey, sortedResult);
    await _bootstrapAudiobookDiscovery();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile =
        PlatformDetection.useMobileUi || MediaQuery.sizeOf(context).width < 600;
    final paddingVal = isMobile ? 16.0 : widget.leftPadding;
    return Padding(
      padding: EdgeInsets.fromLTRB(paddingVal, 0, paddingVal, 0),
      child: widget.isAudiobook
          ? _buildAudiobookDiscoverCard(isMobile: isMobile)
          : _buildDiscoverCard(isMobile: isMobile),
    );
  }

  Widget _buildBookIconButton({
    required IconData icon,
    required VoidCallback onTap,
    Color? backgroundColor,
    Color? foregroundColor,
    FocusNode? focusNode,
    VoidCallback? onUpPressed,
    VoidCallback? onDownPressed,
  }) {
    return _BookIconButton(
      icon: icon,
      onTap: onTap,
      backgroundColor: backgroundColor,
      foregroundColor: foregroundColor,
      focusNode: focusNode,
      onUpPressed: onUpPressed,
      onDownPressed: onDownPressed,
    );
  }

  Widget _buildDiscoverCard({required bool isMobile}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final containerBgColor = isDark
        ? AppColorScheme.onSurface.withValues(alpha: 0.05)
        : const Color(0xFFEFF6FF);
    final titleTextColor = isDark
        ? AppColorScheme.onSurface
        : const Color(0xFF13233A);
    final subtitleTextColor = isDark
        ? AppColorScheme.onSurface.withValues(alpha: 0.6)
        : const Color(0xFF5C7290);
    final chipBgColor = isDark
        ? AppColorScheme.onSurface.withValues(alpha: 0.08)
        : const Color(0xFFDDEEFF);
    final chipFgColor = isDark
        ? AppColorScheme.onSurface
        : const Color(0xFF1D3654);

    final innerPadding = EdgeInsets.symmetric(horizontal: isMobile ? 18.0 : 28.0);

    return Container(
      decoration: BoxDecoration(
        color: containerBgColor,
        borderRadius: AppRadius.circular(32),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A0F2E4D),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      padding: EdgeInsets.symmetric(
        vertical: isMobile ? 22 : 30,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: innerPadding,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppLocalizations.of(context).discover,
                        style: TextStyle(
                          color: titleTextColor,
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        AppLocalizations.of(context).trendingTitlesOpenLibrary,
                        style: TextStyle(
                          color: subtitleTextColor,
                          fontSize: 14,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _buildBookIconButton(
                  icon: Icons.tune_rounded,
                  onTap: _showDiscoverGenreSheet,
                  focusNode: widget.settingsMenuFocusNode,
                  onUpPressed: widget.onSettingsUpPressed,
                  onDownPressed: () => _focusRow(_discoverGenres.first, true),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: innerPadding,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _discoverGenres
                  .map(
                    (genre) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: chipBgColor,
                        borderRadius: AppRadius.circular(999),
                      ),
                      child: Text(
                        displayBookGenre(genre),
                        style: TextStyle(
                          color: chipFgColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          const SizedBox(height: 14),
          if (_discoverBootstrapping && !_discoverInitialized)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 28),
              child: Center(
                child: CircularProgressIndicator(color: _bookAccent),
              ),
            )
          else
            ..._discoverGenres.map((genre) => _buildDiscoverGenreRow(genre)),
        ],
      ),
    );
  }

  Widget _buildDiscoverGenreRow(String genre) {
    final items = _discoverBooksByGenre[genre] ?? const <DiscoverBook>[];
    final isLoading = _discoverLoadingGenres.contains(genre);
    final hasFailed = _discoverFailedGenres.contains(genre);
    final rowController = _controllerForDiscoverSubject(genre);
    final canScrollRow = items.length > 2 && !isLoading;

    final isMobile =
        PlatformDetection.useMobileUi || MediaQuery.sizeOf(context).width < 600;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleTextColor = isDark
        ? AppColorScheme.onSurface
        : const Color(0xFF13233A);
    final subtitleTextColor = isDark
        ? AppColorScheme.onSurface.withValues(alpha: 0.6)
        : const Color(0xFF5C7290);

    final genresList = _discoverGenres;
    final genreIndex = genresList.indexOf(genre);
    final isFirstRow = genreIndex == 0;
    final isLastRow = genreIndex == genresList.length - 1;
    final prevGenre = isFirstRow ? null : genresList[genreIndex - 1];
    final nextGenre = isLastRow ? null : genresList[genreIndex + 1];

    final innerPadding = EdgeInsets.symmetric(horizontal: isMobile ? 18.0 : 28.0);
    final horizontalPadding = isMobile ? 18.0 : 28.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportWidth = constraints.maxWidth - 2 * horizontalPadding;
        final adjustedCardWidth = _calculateAdjustedCardWidth(viewportWidth, 140.0);
        final nodes = _focusNodesForGenre(genre, items.isNotEmpty ? items.length : 1);

        return Padding(
          padding: const EdgeInsets.only(top: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: innerPadding,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        displayBookGenre(genre),
                        style: TextStyle(
                          color: titleTextColor,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      AppLocalizations.of(context).booksCount(items.length),
                      style: TextStyle(
                        color: subtitleTextColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (PlatformDetection.isDesktop) ...[
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: AppLocalizations.of(context).scrollLeft,
                        onPressed: canScrollRow
                            ? () => _scrollDiscoverSubjectRow(genre, -1)
                            : null,
                        style: IconButton.styleFrom(
                          backgroundColor: isDark
                              ? AppColorScheme.accent
                              : const Color(0xFF16304D),
                          foregroundColor: isDark
                              ? AppColorScheme.onAccent
                              : Colors.white,
                          disabledBackgroundColor: isDark
                              ? AppColorScheme.onSurface.withValues(alpha: 0.1)
                              : const Color(0xFFD7E3F0),
                          disabledForegroundColor: isDark
                              ? AppColorScheme.onSurface.withValues(alpha: 0.3)
                              : const Color(0xFF90A5BC),
                        ),
                        icon: const AdaptiveIcon(Icons.chevron_left_rounded),
                      ),
                      IconButton(
                        tooltip: AppLocalizations.of(context).scrollRight,
                        onPressed: canScrollRow
                            ? () => _scrollDiscoverSubjectRow(genre, 1)
                            : null,
                        style: IconButton.styleFrom(
                          backgroundColor: isDark
                              ? AppColorScheme.accent
                              : const Color(0xFF16304D),
                          foregroundColor: isDark
                              ? AppColorScheme.onAccent
                              : Colors.white,
                          disabledBackgroundColor: isDark
                              ? AppColorScheme.onSurface.withValues(alpha: 0.1)
                              : const Color(0xFFD7E3F0),
                          disabledForegroundColor: isDark
                              ? AppColorScheme.onSurface.withValues(alpha: 0.3)
                              : const Color(0xFF90A5BC),
                        ),
                        icon: const AdaptiveIcon(Icons.chevron_right_rounded),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (items.isEmpty && isLoading)
                Padding(
                  padding: innerPadding,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                      child: CircularProgressIndicator(color: _bookAccent),
                    ),
                  ),
                )
              else if (items.isEmpty && hasFailed)
                Padding(
                  padding: innerPadding,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          AppLocalizations.of(context).couldNotLoadSubject,
                          style: TextStyle(color: subtitleTextColor),
                        ),
                      ),
                      Focus(
                        focusNode: isFirstRow ? widget.firstFocusNode : nodes[0],
                        onKeyEvent: (node, event) {
                          if (isActivateKey(event)) {
                            _loadDiscoverPage(genre, reset: true);
                            return KeyEventResult.handled;
                          }
                          if (event.isActionable) {
                            if (event.logicalKey.isUpKey) {
                              if (isFirstRow) {
                                widget.settingsMenuFocusNode?.requestFocus();
                              } else {
                                _focusRow(prevGenre!, false);
                              }
                              return KeyEventResult.handled;
                            }
                            if (event.logicalKey.isDownKey && !isLastRow) {
                              _focusRow(nextGenre!, true);
                              return KeyEventResult.handled;
                            }
                          }
                          return KeyEventResult.ignored;
                        },
                        child: TextButton(
                          onPressed: () => _loadDiscoverPage(genre, reset: true),
                          child: Text(AppLocalizations.of(context).retry),
                        ),
                      ),
                    ],
                  ),
                )
              else
                SizedBox(
                  height: 248,
                  child: ListView.separated(
                    padding: innerPadding.copyWith(top: 4.0, bottom: 4.0),
                    clipBehavior: Clip.hardEdge,
                    controller: rowController,
                    scrollDirection: Axis.horizontal,
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 12),
                    itemBuilder: (context, index) => SizedBox(
                      width: adjustedCardWidth,
                      child: _buildDiscoverBookCard(
                        items[index],
                        focusNode: (isFirstRow && index == 0) ? widget.firstFocusNode : nodes[index],
                        onUpPressed: () {
                          if (isFirstRow) {
                            widget.settingsMenuFocusNode?.requestFocus();
                          } else {
                            _focusRow(prevGenre!, false);
                          }
                        },
                        onDownPressed: isLastRow
                            ? null
                            : () {
                                _focusRow(nextGenre!, true);
                              },
                        onLeftPressed: (index == 0)
                            ? null
                            : () {
                                if (isFirstRow && index == 1) {
                                  widget.firstFocusNode?.requestFocus();
                                } else {
                                  nodes[index - 1].requestFocus();
                                }
                              },
                        onRightPressed: (index == items.length - 1)
                            ? null
                            : () => nodes[index + 1].requestFocus(),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              if (isLoading && items.isNotEmpty)
                const SizedBox(
                  height: 30,
                  child: Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: _bookAccent,
                    ),
                  ),
                )
              else
                const SizedBox(height: 4),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDiscoverBookCard(
    DiscoverBook item, {
    FocusNode? focusNode,
    VoidCallback? onUpPressed,
    VoidCallback? onDownPressed,
    VoidCallback? onLeftPressed,
    VoidCallback? onRightPressed,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleTextColor = isDark
        ? AppColorScheme.onSurface
        : const Color(0xFF13233A);
    final subtitleTextColor = isDark
        ? AppColorScheme.onSurface.withValues(alpha: 0.6)
        : const Color(0xFF5C7290);

    return _DiscoverBookCard(
      book: item,
      titleTextColor: titleTextColor,
      subtitleTextColor: subtitleTextColor,
      focusNode: focusNode,
      onUpPressed: onUpPressed,
      onDownPressed: onDownPressed,
      onLeftPressed: onLeftPressed,
      onRightPressed: onRightPressed,
    );
  }

  Widget _buildAudiobookDiscoverCard({required bool isMobile}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final containerBgColor = isDark
        ? AppColorScheme.onSurface.withValues(alpha: 0.05)
        : const Color(0xFFEFF6FF);
    final titleTextColor = isDark
        ? AppColorScheme.onSurface
        : const Color(0xFF13233A);
    final subtitleTextColor = isDark
        ? AppColorScheme.onSurface.withValues(alpha: 0.6)
        : const Color(0xFF5C7290);
    final chipBgColor = isDark
        ? AppColorScheme.onSurface.withValues(alpha: 0.08)
        : const Color(0xFFDDEEFF);
    final chipFgColor = isDark
        ? AppColorScheme.onSurface
        : const Color(0xFF1D3654);

    final innerPadding = EdgeInsets.symmetric(horizontal: isMobile ? 18.0 : 28.0);

    return Container(
      decoration: BoxDecoration(
        color: containerBgColor,
        borderRadius: AppRadius.circular(32),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A0F2E4D),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      padding: EdgeInsets.symmetric(
        vertical: isMobile ? 22 : 30,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: innerPadding,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppLocalizations.of(context).discoverAudiobooks,
                        style: TextStyle(
                          color: titleTextColor,
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        AppLocalizations.of(context).librivoxDescription,
                        style: TextStyle(
                          color: subtitleTextColor,
                          fontSize: 14,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _buildBookIconButton(
                  icon: Icons.people_alt_rounded,
                  onTap: () {
                    final allBooks = _discoverAudiobooksByGenre.values
                        .expand((b) => b)
                        .toList();
                    final unique = {
                      for (final b in allBooks) b.id: b,
                    }.values.toList();
                    if (unique.isEmpty) return;
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => LibrivoxAuthorsScreen(
                          books: unique,
                          coverCache: Map.unmodifiable(_librivoxCoverCache),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(width: 4),
                _buildBookIconButton(
                  icon: Icons.tune_rounded,
                  onTap: _showAudiobookGenreSheet,
                  focusNode: widget.settingsMenuFocusNode,
                  onUpPressed: widget.onSettingsUpPressed,
                  onDownPressed: () => _focusRow(_discoverAudiobookGenres.first, true),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: innerPadding,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _discoverAudiobookGenres
                  .map(
                    (genre) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: chipBgColor,
                        borderRadius: AppRadius.circular(999),
                      ),
                      child: Text(
                        genre,
                        style: TextStyle(
                          color: chipFgColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          const SizedBox(height: 14),
          if (_discoverAudiobookBootstrapping && !_discoverAudiobookInitialized)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 28),
              child: const Center(
                child: CircularProgressIndicator(color: _bookAccent),
              ),
            )
          else
            ..._discoverAudiobookGenres.map(_buildAudiobookDiscoverGenreRow),
        ],
      ),
    );
  }

  Widget _buildAudiobookDiscoverGenreRow(String genre) {
    final items = _discoverAudiobooksByGenre[genre] ?? const <LibrivoxBook>[];
    final isLoading = _discoverAudiobookLoadingGenres.contains(genre);
    final hasFailed = _discoverAudiobookFailedGenres.contains(genre);
    final rowController = _controllerForAudiobookDiscoverGenre(genre);
    final canScrollRow = items.length > 2 && !isLoading;

    final isMobile =
        PlatformDetection.useMobileUi || MediaQuery.sizeOf(context).width < 600;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleTextColor = isDark
        ? AppColorScheme.onSurface
        : const Color(0xFF13233A);
    final subtitleTextColor = isDark
        ? AppColorScheme.onSurface.withValues(alpha: 0.6)
        : const Color(0xFF5C7290);

    final genresList = _discoverAudiobookGenres;
    final genreIndex = genresList.indexOf(genre);
    final isFirstRow = genreIndex == 0;
    final isLastRow = genreIndex == genresList.length - 1;
    final prevGenre = isFirstRow ? null : genresList[genreIndex - 1];
    final nextGenre = isLastRow ? null : genresList[genreIndex + 1];

    final innerPadding = EdgeInsets.symmetric(horizontal: isMobile ? 18.0 : 28.0);
    final horizontalPadding = isMobile ? 18.0 : 28.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportWidth = constraints.maxWidth - 2 * horizontalPadding;
        final adjustedCardWidth = _calculateAdjustedCardWidth(viewportWidth, 150.0);
        final nodes = _focusNodesForGenre(genre, items.isNotEmpty ? items.length : 1);

        return Padding(
          padding: const EdgeInsets.only(top: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: innerPadding,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        genre,
                        style: TextStyle(
                          color: titleTextColor,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      AppLocalizations.of(context).titlesCount(items.length),
                      style: TextStyle(
                        color: subtitleTextColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (PlatformDetection.isDesktop) ...[
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: AppLocalizations.of(context).scrollLeft,
                        onPressed: canScrollRow
                            ? () => _scrollAudiobookDiscoverRow(genre, -1)
                            : null,
                        style: IconButton.styleFrom(
                          backgroundColor: isDark
                              ? AppColorScheme.accent
                              : const Color(0xFF16304D),
                          foregroundColor: isDark
                              ? AppColorScheme.onAccent
                              : Colors.white,
                          disabledBackgroundColor: isDark
                              ? AppColorScheme.onSurface.withValues(alpha: 0.1)
                              : const Color(0xFFD7E3F0),
                          disabledForegroundColor: isDark
                              ? AppColorScheme.onSurface.withValues(alpha: 0.3)
                              : const Color(0xFF90A5BC),
                        ),
                        icon: const AdaptiveIcon(Icons.chevron_left_rounded),
                      ),
                      IconButton(
                        tooltip: AppLocalizations.of(context).scrollRight,
                        onPressed: canScrollRow
                            ? () => _scrollAudiobookDiscoverRow(genre, 1)
                            : null,
                        style: IconButton.styleFrom(
                          backgroundColor: isDark
                              ? AppColorScheme.accent
                              : const Color(0xFF16304D),
                          foregroundColor: isDark
                              ? AppColorScheme.onAccent
                              : Colors.white,
                          disabledBackgroundColor: isDark
                              ? AppColorScheme.onSurface.withValues(alpha: 0.1)
                              : const Color(0xFFD7E3F0),
                          disabledForegroundColor: isDark
                              ? AppColorScheme.onSurface.withValues(alpha: 0.3)
                              : const Color(0xFF90A5BC),
                        ),
                        icon: const AdaptiveIcon(Icons.chevron_right_rounded),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (items.isEmpty && isLoading)
                Padding(
                  padding: innerPadding,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                      child: CircularProgressIndicator(color: _bookAccent),
                    ),
                  ),
                )
              else if (items.isEmpty && hasFailed)
                Padding(
                  padding: innerPadding,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          AppLocalizations.of(context).couldNotLoadGenre,
                          style: TextStyle(color: subtitleTextColor),
                        ),
                      ),
                      Focus(
                        focusNode: isFirstRow ? widget.firstFocusNode : nodes[0],
                        onKeyEvent: (node, event) {
                          if (isActivateKey(event)) {
                            _loadAudiobookDiscoverPage(genre, reset: true);
                            return KeyEventResult.handled;
                          }
                          if (event.isActionable) {
                            if (event.logicalKey.isUpKey) {
                              if (isFirstRow) {
                                widget.settingsMenuFocusNode?.requestFocus();
                              } else {
                                _focusRow(prevGenre!, false);
                              }
                              return KeyEventResult.handled;
                            }
                            if (event.logicalKey.isDownKey && !isLastRow) {
                              _focusRow(nextGenre!, true);
                              return KeyEventResult.handled;
                            }
                          }
                          return KeyEventResult.ignored;
                        },
                        child: TextButton(
                          onPressed: () => _loadAudiobookDiscoverPage(genre, reset: true),
                          child: Text(AppLocalizations.of(context).retry),
                        ),
                      ),
                    ],
                  ),
                )
              else
                SizedBox(
                  height: 208,
                  child: ListView.separated(
                    padding: innerPadding.copyWith(top: 4.0, bottom: 4.0),
                    clipBehavior: Clip.hardEdge,
                    controller: rowController,
                    scrollDirection: Axis.horizontal,
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 12),
                    itemBuilder: (context, index) => SizedBox(
                      width: adjustedCardWidth,
                      child: _buildLibrivoxBookCard(
                        items[index],
                        focusNode: (isFirstRow && index == 0) ? widget.firstFocusNode : nodes[index],
                        onUpPressed: () {
                          if (isFirstRow) {
                            widget.settingsMenuFocusNode?.requestFocus();
                          } else {
                            _focusRow(prevGenre!, false);
                          }
                        },
                        onDownPressed: isLastRow
                            ? null
                            : () {
                                _focusRow(nextGenre!, true);
                              },
                        onLeftPressed: (index == 0)
                            ? null
                            : () {
                                if (isFirstRow && index == 1) {
                                  widget.firstFocusNode?.requestFocus();
                                } else {
                                  nodes[index - 1].requestFocus();
                                }
                              },
                        onRightPressed: (index == items.length - 1)
                            ? null
                            : () => nodes[index + 1].requestFocus(),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              if (isLoading && items.isNotEmpty)
                const SizedBox(
                  height: 30,
                  child: Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: _bookAccent,
                    ),
                  ),
                )
              else
                const SizedBox(height: 4),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAudiobookCoverPlaceholder(Color color, String duration) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color, color.withAlpha(180)],
        ),
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const AdaptiveIcon(Icons.headphones_rounded, color: Colors.white, size: 32),
          if (duration.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.black.withAlpha(50),
                borderRadius: AppRadius.circular(999),
              ),
              child: Text(
                duration,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLibrivoxBookCard(
    LibrivoxBook book, {
    FocusNode? focusNode,
    VoidCallback? onUpPressed,
    VoidCallback? onDownPressed,
    VoidCallback? onLeftPressed,
    VoidCallback? onRightPressed,
  }) {
    final colorIndex =
        book.id.hashCode.abs() % audiobookPlaceholderColors.length;
    final placeholderColor = audiobookPlaceholderColors[colorIndex];
    final coverUrl = _librivoxCoverCache[book.id];
    final resolvedCover = coverUrl;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleTextColor = isDark
        ? AppColorScheme.onSurface
        : const Color(0xFF13233A);
    final subtitleTextColor = isDark
        ? AppColorScheme.onSurface.withValues(alpha: 0.6)
        : const Color(0xFF5C7290);

    final allBooksById = <String, LibrivoxBook>{};
    for (final bookList in _discoverAudiobooksByGenre.values) {
      for (final discoveredBook in bookList) {
        allBooksById[discoveredBook.id] = discoveredBook;
      }
    }
    final allBooks = allBooksById.values.toList();

    return _LibrivoxBookCard(
      book: book,
      coverUrl: resolvedCover,
      allBooks: allBooks,
      coverCache: Map.of(_librivoxCoverCache),
      placeholder: _buildAudiobookCoverPlaceholder(placeholderColor, book.formattedDuration),
      titleTextColor: titleTextColor,
      subtitleTextColor: subtitleTextColor,
      focusNode: focusNode,
      onUpPressed: onUpPressed,
      onDownPressed: onDownPressed,
      onLeftPressed: onLeftPressed,
      onRightPressed: onRightPressed,
    );
  }
}

class _BookIconButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final FocusNode? focusNode;
  final VoidCallback? onUpPressed;
  final VoidCallback? onDownPressed;

  const _BookIconButton({
    required this.icon,
    required this.onTap,
    this.backgroundColor,
    this.foregroundColor,
    this.focusNode,
    this.onUpPressed,
    this.onDownPressed,
  });

  @override
  State<_BookIconButton> createState() => _BookIconButtonState();
}

class _BookIconButtonState extends State<_BookIconButton> {
  bool _focused = false;
  final FocusNode _parentFocusNode = FocusNode(debugLabel: 'BookIconButtonParent');

  @override
  void dispose() {
    _parentFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = widget.backgroundColor ?? (isDark ? AppColorScheme.onSurface.withValues(alpha: 0.1) : const Color(0x1FEAF4FF));
    final fg = widget.foregroundColor ?? (isDark ? AppColorScheme.onSurface : const Color(0xFFEAF4FF));

    return Focus(
      focusNode: _parentFocusNode,
      onKeyEvent: (node, event) {
        if (event.isActionable) {
          if (event.logicalKey.isUpKey && widget.onUpPressed != null) {
            widget.onUpPressed!();
            return KeyEventResult.handled;
          }
          if (event.logicalKey.isDownKey && widget.onDownPressed != null) {
            widget.onDownPressed!();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: InkWell(
        focusNode: widget.focusNode,
        onFocusChange: (f) {
          setState(() => _focused = f);
        },
        onTap: widget.onTap,
        borderRadius: AppRadius.circular(20),
        focusColor: Colors.transparent,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: AppRadius.circular(20),
            border: Border.all(
              color: _focused ? AppColorScheme.accent : fg.withValues(alpha: 0.11),
              width: 3.0,
            ),
          ),
          child: Center(
            child: AdaptiveIcon(widget.icon, color: fg),
          ),
        ),
      ),
    );
  }
}

class _DiscoverBookCard extends StatefulWidget {
  final DiscoverBook book;
  final Color titleTextColor;
  final Color subtitleTextColor;
  final FocusNode? focusNode;
  final VoidCallback? onUpPressed;
  final VoidCallback? onDownPressed;
  final VoidCallback? onLeftPressed;
  final VoidCallback? onRightPressed;

  const _DiscoverBookCard({
    required this.book,
    required this.titleTextColor,
    required this.subtitleTextColor,
    this.focusNode,
    this.onUpPressed,
    this.onDownPressed,
    this.onLeftPressed,
    this.onRightPressed,
  });

  @override
  State<_DiscoverBookCard> createState() => _DiscoverBookCardState();
}

class _DiscoverBookCardState extends State<_DiscoverBookCard> {
  bool _focused = false;
  final FocusNode _parentFocusNode = FocusNode(debugLabel: 'DiscoverCardParent');

  @override
  void initState() {
    super.initState();
    _focused = widget.focusNode?.hasFocus ?? false;
    widget.focusNode?.addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(covariant _DiscoverBookCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode?.removeListener(_handleFocusChange);
      widget.focusNode?.addListener(_handleFocusChange);
      _focused = widget.focusNode?.hasFocus ?? false;
    }
  }

  @override
  void dispose() {
    _parentFocusNode.dispose();
    widget.focusNode?.removeListener(_handleFocusChange);
    super.dispose();
  }

  void _handleFocusChange() {
    if (mounted) {
      setState(() => _focused = widget.focusNode?.hasFocus ?? false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _parentFocusNode,
      onKeyEvent: (node, event) {
        if (event.isActionable) {
          if (event.logicalKey.isUpKey && widget.onUpPressed != null) {
            widget.onUpPressed!();
            return KeyEventResult.handled;
          }
          if (event.logicalKey.isDownKey && widget.onDownPressed != null) {
            widget.onDownPressed!();
            return KeyEventResult.handled;
          }
          if (event.logicalKey.isLeftKey) {
            if (widget.onLeftPressed != null) {
              widget.onLeftPressed!();
            }
            return KeyEventResult.handled;
          }
          if (event.logicalKey.isRightKey) {
            if (widget.onRightPressed != null) {
              widget.onRightPressed!();
            }
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: InkWell(
        focusNode: widget.focusNode,
        onFocusChange: (focused) {
          if (focused) {
            Scrollable.ensureVisible(
              context,
              duration: const Duration(milliseconds: 200),
              alignment: 0.5,
              curve: Curves.easeOutCubic,
            );
          }
        },
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => DiscoverBookDetailScreen(book: widget.book),
          ),
        ),
        borderRadius: AppRadius.circular(18),
        focusColor: Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                decoration: BoxDecoration(
                  borderRadius: AppRadius.circular(18),
                  border: Border.all(
                    color: _focused ? AppColorScheme.accent : Colors.transparent,
                    width: 3.0,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: AppRadius.circular(15),
                  child: widget.book.coverUrl == null
                      ? Container(
                          color: const Color(0xFF2C77B7),
                          alignment: Alignment.center,
                          padding: const EdgeInsets.all(10),
                          child: const AdaptiveIcon(
                            Icons.auto_stories_rounded,
                            color: Colors.white,
                            size: 30,
                        ),
                      )
                      : CachedNetworkImage(
                          imageUrl: widget.book.coverUrl!,
                          fit: BoxFit.cover,
                          errorWidget: (_, _, _) => Container(
                            color: const Color(0xFF2C77B7),
                            alignment: Alignment.center,
                            child: const AdaptiveIcon(
                              Icons.auto_stories_rounded,
                              color: Colors.white,
                            ),
                          ),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            HoverMarqueeText(
              text: widget.book.title,
              style: TextStyle(
                color: widget.titleTextColor,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 2),
            HoverMarqueeText(
              text: widget.book.author,
              style: TextStyle(color: widget.subtitleTextColor, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _LibrivoxBookCard extends StatefulWidget {
  final LibrivoxBook book;
  final String? coverUrl;
  final List<LibrivoxBook> allBooks;
  final Map<String, String?> coverCache;
  final Widget placeholder;
  final Color titleTextColor;
  final Color subtitleTextColor;
  final FocusNode? focusNode;
  final VoidCallback? onUpPressed;
  final VoidCallback? onDownPressed;
  final VoidCallback? onLeftPressed;
  final VoidCallback? onRightPressed;

  const _LibrivoxBookCard({
    required this.book,
    required this.coverUrl,
    required this.allBooks,
    required this.coverCache,
    required this.placeholder,
    required this.titleTextColor,
    required this.subtitleTextColor,
    this.focusNode,
    this.onUpPressed,
    this.onDownPressed,
    this.onLeftPressed,
    this.onRightPressed,
  });

  @override
  State<_LibrivoxBookCard> createState() => _LibrivoxBookCardState();
}

class _LibrivoxBookCardState extends State<_LibrivoxBookCard> {
  bool _focused = false;
  final FocusNode _parentFocusNode = FocusNode(debugLabel: 'LibrivoxCardParent');

  @override
  void initState() {
    super.initState();
    _focused = widget.focusNode?.hasFocus ?? false;
    widget.focusNode?.addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(covariant _LibrivoxBookCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode?.removeListener(_handleFocusChange);
      widget.focusNode?.addListener(_handleFocusChange);
      _focused = widget.focusNode?.hasFocus ?? false;
    }
  }

  @override
  void dispose() {
    _parentFocusNode.dispose();
    widget.focusNode?.removeListener(_handleFocusChange);
    super.dispose();
  }

  void _handleFocusChange() {
    if (mounted) {
      setState(() => _focused = widget.focusNode?.hasFocus ?? false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasCover = widget.coverUrl != null;
    return Focus(
      focusNode: _parentFocusNode,
      onKeyEvent: (node, event) {
        if (event.isActionable) {
          if (event.logicalKey.isUpKey && widget.onUpPressed != null) {
            widget.onUpPressed!();
            return KeyEventResult.handled;
          }
          if (event.logicalKey.isDownKey && widget.onDownPressed != null) {
            widget.onDownPressed!();
            return KeyEventResult.handled;
          }
          if (event.logicalKey.isLeftKey) {
            if (widget.onLeftPressed != null) {
              widget.onLeftPressed!();
            }
            return KeyEventResult.handled;
          }
          if (event.logicalKey.isRightKey) {
            if (widget.onRightPressed != null) {
              widget.onRightPressed!();
            }
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: InkWell(
        focusNode: widget.focusNode,
        onFocusChange: (focused) {
          if (focused) {
            Scrollable.ensureVisible(
              context,
              duration: const Duration(milliseconds: 200),
              alignment: 0.5,
              curve: Curves.easeOutCubic,
            );
          }
        },
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => LibrivoxBookDetailScreen(
                book: widget.book,
                coverUrl: widget.coverUrl,
                allBooks: widget.allBooks,
                coverCache: widget.coverCache,
              ),
            ),
          );
        },
        borderRadius: AppRadius.circular(18),
        focusColor: Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                decoration: BoxDecoration(
                  borderRadius: AppRadius.circular(18),
                  border: Border.all(
                    color: _focused ? AppColorScheme.accent : Colors.transparent,
                    width: 3.0,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: AppRadius.circular(15),
                  child: hasCover
                      ? CachedNetworkImage(
                          imageUrl: widget.coverUrl!,
                          fit: BoxFit.cover,
                          errorWidget: (_, _, _) => widget.placeholder,
                        )
                      : widget.placeholder,
                ),
              ),
            ),
            const SizedBox(height: 8),
            HoverMarqueeText(
              text: widget.book.title,
              style: TextStyle(
                color: widget.titleTextColor,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 2),
            HoverMarqueeText(
              text: widget.book.authorName,
              style: TextStyle(color: widget.subtitleTextColor, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _GenreDialogContent extends StatefulWidget {
  final String title;
  final String subtitle;
  final List<String> allGenres;
  final List<String> initialSelectedGenres;
  final String Function(String) displayFn;

  const _GenreDialogContent({
    required this.title,
    required this.subtitle,
    required this.allGenres,
    required this.initialSelectedGenres,
    required this.displayFn,
  });

  @override
  State<_GenreDialogContent> createState() => _GenreDialogContentState();
}

class _GenreDialogContentState extends State<_GenreDialogContent> {
  late Set<String> _selected;
  final FocusNode _closeFocusNode = FocusNode(debugLabel: 'GenreClose');
  final List<FocusNode> _genreFocusNodes = [];
  final FocusNode _applyFocusNode = FocusNode(debugLabel: 'GenreApply');
  int _lastFocusedGenreIndex = 0;

  @override
  void initState() {
    super.initState();
    _selected = {...widget.initialSelectedGenres};
    for (int i = 0; i < widget.allGenres.length; i++) {
      final node = FocusNode(debugLabel: 'GenreItem_$i');
      node.addListener(() {
        if (node.hasFocus) {
          _lastFocusedGenreIndex = i;
        }
      });
      _genreFocusNodes.add(node);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_genreFocusNodes.isNotEmpty) {
        _genreFocusNodes[0].requestFocus();
      } else {
        _applyFocusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _closeFocusNode.dispose();
    for (final node in _genreFocusNodes) {
      node.dispose();
    }
    _applyFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final width = MediaQuery.of(context).size.width.clamp(400.0, 520.0).toDouble();

    final backgroundColor = isDark
        ? AppColorScheme.background
        : const Color(0xFFF0F7FF);
    final titleTextColor = isDark
        ? AppColorScheme.onSurface
        : const Color(0xFF13233A);
    final subtitleTextColor = isDark
        ? AppColorScheme.onSurface.withValues(alpha: 0.6)
        : const Color(0xFF5C7290);

    return Align(
      alignment: Alignment.centerRight,
      child: Material(
        color: backgroundColor,
        child: SizedBox(
          width: width,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: titleTextColor,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          widget.subtitle,
                          style: TextStyle(color: subtitleTextColor, fontSize: 13),
                        ),
                        const SizedBox(height: 16),
                        Expanded(
                          child: ListView.builder(
                            itemCount: widget.allGenres.length,
                            itemBuilder: (context, index) {
                              final genre = widget.allGenres[index];
                              final selected = _selected.contains(genre);
                              final isFirst = index == 0;
                              final isLast = index == widget.allGenres.length - 1;

                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4.0),
                                child: _GenreTile(
                                  title: widget.displayFn(genre),
                                  value: selected,
                                  focusNode: _genreFocusNodes[index],
                                  onChanged: (value) {
                                    setState(() {
                                      if (value == true) {
                                        _selected.add(genre);
                                      } else if (_selected.length > 1) {
                                        _selected.remove(genre);
                                      }
                                    });
                                  },
                                  onUpPressed: () {
                                    if (!isFirst) {
                                      _genreFocusNodes[index - 1].requestFocus();
                                    }
                                  },
                                  onDownPressed: () {
                                    if (!isLast) {
                                      _genreFocusNodes[index + 1].requestFocus();
                                    }
                                  },
                                  onRightPressed: () {
                                    if (index < 4) {
                                      _closeFocusNode.requestFocus();
                                    } else {
                                      _applyFocusNode.requestFocus();
                                    }
                                  },
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 20),
                  SizedBox(
                    width: 80,
                    child: Column(
                      children: [
                        _FocusableCloseButton(
                          focusNode: _closeFocusNode,
                          onPressed: () => Navigator.of(context).pop(),
                          onDownPressed: () => _applyFocusNode.requestFocus(),
                          onLeftPressed: () {
                            if (_genreFocusNodes.isNotEmpty) {
                              _genreFocusNodes[_lastFocusedGenreIndex].requestFocus();
                            }
                          },
                        ),
                        const Spacer(),
                        _ApplyButton(
                          focusNode: _applyFocusNode,
                          label: AppLocalizations.of(context).apply,
                          onPressed: () => Navigator.of(context).pop(_selected.toList()),
                          onUpPressed: () => _closeFocusNode.requestFocus(),
                          onLeftPressed: () {
                            if (_genreFocusNodes.isNotEmpty) {
                              _genreFocusNodes[_lastFocusedGenreIndex].requestFocus();
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FocusableCloseButton extends StatefulWidget {
  final VoidCallback onPressed;
  final FocusNode? focusNode;
  final VoidCallback? onDownPressed;
  final VoidCallback? onLeftPressed;

  const _FocusableCloseButton({
    required this.onPressed,
    this.focusNode,
    this.onDownPressed,
    this.onLeftPressed,
  });

  @override
  State<_FocusableCloseButton> createState() => _FocusableCloseButtonState();
}

class _FocusableCloseButtonState extends State<_FocusableCloseButton> {
  bool _focused = false;
  late final FocusNode _effectiveFocusNode;
  final FocusNode _parentFocusNode = FocusNode(debugLabel: 'CloseButtonParent');

  @override
  void initState() {
    super.initState();
    _effectiveFocusNode = widget.focusNode ?? FocusNode();
    _effectiveFocusNode.addListener(_handleFocusChange);
    _focused = _effectiveFocusNode.hasFocus;
  }

  @override
  void dispose() {
    _parentFocusNode.dispose();
    if (widget.focusNode == null) {
      _effectiveFocusNode.dispose();
    } else {
      _effectiveFocusNode.removeListener(_handleFocusChange);
    }
    super.dispose();
  }

  void _handleFocusChange() {
    if (mounted) {
      setState(() => _focused = _effectiveFocusNode.hasFocus);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = isDark ? AppColorScheme.onSurface : const Color(0xFF13233A);

    return Focus(
      focusNode: _parentFocusNode,
      onKeyEvent: (node, event) {
        if (event.isActionable) {
          if (event.logicalKey.isDownKey && widget.onDownPressed != null) {
            widget.onDownPressed!();
            return KeyEventResult.handled;
          }
          if (event.logicalKey.isLeftKey && widget.onLeftPressed != null) {
            widget.onLeftPressed!();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: _focused ? AppColorScheme.accent : Colors.transparent,
            width: 2.0,
          ),
        ),
        child: IconButton(
          focusNode: _effectiveFocusNode,
          onPressed: widget.onPressed,
          icon: AdaptiveIcon(Icons.close_rounded, color: color),
        ),
      ),
    );
  }
}

class _GenreTile extends StatefulWidget {
  final String title;
  final bool value;
  final ValueChanged<bool?> onChanged;
  final FocusNode? focusNode;
  final VoidCallback? onUpPressed;
  final VoidCallback? onDownPressed;
  final VoidCallback? onRightPressed;

  const _GenreTile({
    required this.title,
    required this.value,
    required this.onChanged,
    this.focusNode,
    this.onUpPressed,
    this.onDownPressed,
    this.onRightPressed,
  });

  @override
  State<_GenreTile> createState() => _GenreTileState();
}

class _GenreTileState extends State<_GenreTile> {
  bool _focused = false;
  final FocusNode _parentFocusNode = FocusNode(debugLabel: 'GenreTileParent');

  @override
  void dispose() {
    _parentFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tileBg = _focused
        ? (isDark ? AppColorScheme.accent.withValues(alpha: 0.15) : const Color(0xFFE3F2FD))
        : Colors.transparent;
    final titleColor = isDark ? AppColorScheme.onSurface : const Color(0xFF13233A);

    return Focus(
      focusNode: _parentFocusNode,
      onKeyEvent: (node, event) {
        if (event.isActionable) {
          if (event.logicalKey.isUpKey && widget.onUpPressed != null) {
            widget.onUpPressed!();
            return KeyEventResult.handled;
          }
          if (event.logicalKey.isDownKey && widget.onDownPressed != null) {
            widget.onDownPressed!();
            return KeyEventResult.handled;
          }
          if (event.logicalKey.isRightKey && widget.onRightPressed != null) {
            widget.onRightPressed!();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: InkWell(
        focusNode: widget.focusNode,
        onFocusChange: (f) {
          setState(() => _focused = f);
          if (f) {
            Scrollable.ensureVisible(
              context,
              duration: const Duration(milliseconds: 150),
              alignment: 0.5,
              curve: Curves.easeOutCubic,
            );
          }
        },
        onTap: () => widget.onChanged(!widget.value),
        focusColor: Colors.transparent,
        borderRadius: AppRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: tileBg,
            borderRadius: AppRadius.circular(12),
            border: Border.all(
              color: _focused ? AppColorScheme.accent : Colors.transparent,
              width: 2.0,
            ),
          ),
          child: Row(
            children: [
              Checkbox(
                value: widget.value,
                onChanged: widget.onChanged,
                activeColor: isDark ? AppColorScheme.accent : const Color(0xFF0D47A1),
                checkColor: Colors.white,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.title,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: titleColor,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ApplyButton extends StatefulWidget {
  final VoidCallback onPressed;
  final String label;
  final FocusNode? focusNode;
  final VoidCallback? onUpPressed;
  final VoidCallback? onLeftPressed;

  const _ApplyButton({
    required this.onPressed,
    required this.label,
    this.focusNode,
    this.onUpPressed,
    this.onLeftPressed,
  });

  @override
  State<_ApplyButton> createState() => _ApplyButtonState();
}

class _ApplyButtonState extends State<_ApplyButton> {
  bool _focused = false;
  final FocusNode _parentFocusNode = FocusNode(debugLabel: 'ApplyButtonParent');

  @override
  void dispose() {
    _parentFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final btnColor = isDark ? AppColorScheme.accent : const Color(0xFF0D47A1);

    return Focus(
      focusNode: _parentFocusNode,
      onKeyEvent: (node, event) {
        if (event.isActionable) {
          if (event.logicalKey.isUpKey && widget.onUpPressed != null) {
            widget.onUpPressed!();
            return KeyEventResult.handled;
          }
          if (event.logicalKey.isLeftKey && widget.onLeftPressed != null) {
            widget.onLeftPressed!();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: InkWell(
        focusNode: widget.focusNode,
        onFocusChange: (f) => setState(() => _focused = f),
        onTap: widget.onPressed,
        borderRadius: AppRadius.circular(16),
        focusColor: Colors.transparent,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: double.infinity,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: btnColor,
            borderRadius: AppRadius.circular(16),
            border: Border.all(
              color: _focused ? (isDark ? Colors.white : Colors.black) : Colors.transparent,
              width: 3.0,
            ),
            boxShadow: _focused
                ? [
                    BoxShadow(
                      color: btnColor.withValues(alpha: 0.4),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    )
                  ]
                : [],
          ),
          child: Text(
            widget.label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
        ),
      ),
    );
  }
}
