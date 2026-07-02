import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:moonfin_design/moonfin_design.dart';
import 'package:playback_core/playback_core.dart';
import 'package:server_core/server_core.dart';

import '../../../data/models/aggregated_item.dart';
import '../../../data/models/home_row.dart';
import '../../../data/services/row_data_source.dart';
import '../../../data/viewmodels/book_browse_view_model.dart';
import '../../../l10n/app_localizations.dart';
import '../../../preference/user_preferences.dart';
import '../../../util/focus/dpad_keys.dart';
import '../../navigation/destinations.dart';
import '../../widgets/book/book_segmented_control.dart';
import '../../widgets/book/book_stats_band.dart';
import '../../widgets/book/discover/book_discover_tab.dart';
import '../../widgets/focus/request_initial_focus.dart';
import '../../widgets/library_row.dart';
import '../../widgets/media_card.dart';
import '../../widgets/navigation_layout.dart';

class BookBrowseScreen extends StatefulWidget {
  final String libraryId;
  final String? collectionType;

  const BookBrowseScreen({
    super.key,
    required this.libraryId,
    this.collectionType,
  });

  @override
  State<BookBrowseScreen> createState() => _BookBrowseScreenState();
}

class _BookBrowseScreenState extends State<BookBrowseScreen> {
  late final BookBrowseViewModel _vm;
  int _tab = 0;
  final _scrollController = ScrollController();
  VoidCallback? _previousFocusContentFromNavbarCallback;

  final Map<String, ScrollController> _rowControllers = {};
  final Map<String, FocusNode> _rowFirstCardFocusNodes = {};

  final _firstResumeBookFocusNode = FocusNode(debugLabel: 'FirstResumeBook');
  final _libraryTabFocusNode = FocusNode(debugLabel: 'LibraryTab');
  final _discoverTabFocusNode = FocusNode(debugLabel: 'DiscoverTab');
  final _booksStatFocusNode = FocusNode(debugLabel: 'BooksStat');
  final _audiobooksStatFocusNode = FocusNode(debugLabel: 'AudiobooksStat');
  final _firstRecentBooksFocusNode = FocusNode(debugLabel: 'FirstRecentBooks');
  final _firstRecentAudiobooksFocusNode = FocusNode(debugLabel: 'FirstRecentAudiobooks');
  final _firstDiscoverFocusNode = FocusNode(debugLabel: 'FirstDiscover');
  final _discoverSettingsFocusNode = FocusNode(debugLabel: 'DiscoverSettings');

  void _onStatsBandFocusChange() {
    if (_booksStatFocusNode.hasFocus || _audiobooksStatFocusNode.hasFocus) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0.0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
        );
      }
    }
  }

  void _onSettingsFocusChange() {
    if (_discoverSettingsFocusNode.hasFocus && _tab == 1 && _scrollController.hasClients) {
      final resumeRow = _vm.rows.firstWhere(
        (r) => r.rowType == HomeRowType.resume,
        orElse: () => HomeRow(id: '', title: '', items: [], rowType: HomeRowType.resume),
      );
      final topReserve = MediaQuery.paddingOf(context).top + 56;
      final topHeight = resumeRow.items.isNotEmpty ? (topReserve + 256.0) : topReserve;
      final targetOffset = topHeight + 110.0;
      _scrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _vm = BookBrowseViewModel(
      libraryId: widget.libraryId,
      dataSource: GetIt.instance<RowDataSource>(),
      client: GetIt.instance<MediaServerClient>(),
      collectionType: widget.collectionType,
    );
    _vm.addListener(_onChanged);
    _vm.load();

    _booksStatFocusNode.addListener(_onStatsBandFocusChange);
    _audiobooksStatFocusNode.addListener(_onStatsBandFocusChange);
    _discoverSettingsFocusNode.addListener(_onSettingsFocusChange);

    _previousFocusContentFromNavbarCallback =
        NavigationLayout.focusContentFromNavbarNotifier.value;
    NavigationLayout.focusContentFromNavbarNotifier.value =
        _focusContentFromNavbar;
  }

  @override
  void dispose() {
    _booksStatFocusNode.removeListener(_onStatsBandFocusChange);
    _audiobooksStatFocusNode.removeListener(_onStatsBandFocusChange);
    _discoverSettingsFocusNode.removeListener(_onSettingsFocusChange);
    for (final controller in _rowControllers.values) {
      controller.dispose();
    }
    for (final node in _rowFirstCardFocusNodes.values) {
      node.dispose();
    }
    _firstResumeBookFocusNode.dispose();
    _libraryTabFocusNode.dispose();
    _discoverTabFocusNode.dispose();
    _booksStatFocusNode.dispose();
    _audiobooksStatFocusNode.dispose();
    _firstRecentBooksFocusNode.dispose();
    _firstRecentAudiobooksFocusNode.dispose();
    _firstDiscoverFocusNode.dispose();
    _discoverSettingsFocusNode.dispose();
    _scrollController.dispose();
    if (NavigationLayout.focusContentFromNavbarNotifier.value ==
        _focusContentFromNavbar) {
      NavigationLayout.focusContentFromNavbarNotifier.value =
          _previousFocusContentFromNavbarCallback;
    }
    _vm.removeListener(_onChanged);
    _vm.dispose();
    super.dispose();
  }

  void _focusContentFromNavbar() {
    if (!mounted) return;
    final resumeRow = _vm.rows.firstWhere(
      (r) => r.rowType == HomeRowType.resume,
      orElse: () => HomeRow(id: '', title: '', items: [], rowType: HomeRowType.resume),
    );
    final targetNode = resumeRow.items.isNotEmpty ? _firstResumeBookFocusNode : _libraryTabFocusNode;
    targetNode.requestFocus();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  List<String> get _itemTypes =>
      _vm.isAudiobookLibrary ? const ['AudioBook', 'Audio'] : const ['Book'];

  void _onItemTap(AggregatedItem item, HomeRow row) async {
    if (row.rowType == HomeRowType.genres) {
      context.push(
        Destinations.genre(
          item.name,
          genreId: item.id,
          parentId: widget.libraryId,
          includeType: _vm.isAudiobookLibrary ? 'AudioBook' : 'Book',
        ),
      );
      return;
    }

    if (row.rowType == HomeRowType.resume) {
      final isAudiobook = item.type == 'AudioBook' || item.type == 'Audio';
      if (isAudiobook) {
        final manager = GetIt.instance<PlaybackManager>();
        final client = GetIt.instance<MediaServerClient>();
        final startPosition = item.playbackPosition ?? Duration.zero;

        if (item.type == 'AudioBook') {
          const audioChildFields = 'BasicSyncInfo,PrimaryImageAspectRatio,RunTimeTicks,MediaSources,MediaSourceCount,MediaType,IndexNumber,ParentIndexNumber,Artists,AlbumArtist,Genres,Chapters';
          bool isAudioChild(dynamic e) {
            final childType = e is Map ? e['Type']?.toString() : null;
            return childType == 'Audio' || childType == 'AudioBook';
          }

          try {
            final data = await client.itemsApi.getItems(
              parentId: item.id,
              includeItemTypes: const ['Audio', 'AudioBook'],
              sortBy: 'ParentIndexNumber,IndexNumber,SortName',
              fields: audioChildFields,
            );
            final rawChildren = (data['Items'] as List?) ?? const [];
            final childItems = rawChildren.where(isAudioChild).toList();
            if (childItems.isNotEmpty) {
              final siblings = childItems.map((i) => AggregatedItem(id: i['Id']?.toString() ?? '', serverId: item.serverId, rawData: i as Map<String, dynamic>)).toList();
              int startIndex = 0;
              Duration childPosition = Duration.zero;
              final idx = siblings.indexWhere((t) => (t.playbackPosition ?? Duration.zero) > Duration.zero && !t.isPlayed);
              if (idx >= 0) {
                startIndex = idx;
                childPosition = siblings[idx].playbackPosition ?? Duration.zero;
              } else {
                final firstUnplayed = siblings.indexWhere((t) => !t.isPlayed);
                startIndex = firstUnplayed >= 0 ? firstUnplayed : 0;
                childPosition = Duration.zero;
              }
              final playItemsFuture = manager.playItems(
                siblings,
                startIndex: startIndex,
                startPosition: childPosition,
              );
              if (mounted) {
                await context.push('${Destinations.audioPlayer}?isAudiobook=true');
              }
              await playItemsFuture;
              if (mounted) {
                _vm.load();
              }
              return;
            }
          } catch (_) {}
        }

        // Sibling queue for leaf audiobook
        final parentId = item.rawData['ParentId']?.toString();
        if (parentId != null && parentId.isNotEmpty) {
          const audioChildFields = 'BasicSyncInfo,PrimaryImageAspectRatio,RunTimeTicks,MediaSources,MediaSourceCount,MediaType,IndexNumber,ParentIndexNumber,Artists,AlbumArtist,Genres,Chapters';
          bool isAudioChild(dynamic e) {
            final childType = e is Map ? e['Type']?.toString() : null;
            return childType == 'Audio' || childType == 'AudioBook';
          }

          try {
            final siblingData = await client.itemsApi.getItems(
              parentId: parentId,
              includeItemTypes: const ['Audio', 'AudioBook'],
              sortBy: 'ParentIndexNumber,IndexNumber,SortName',
              fields: audioChildFields,
            );
            final siblingsRaw = (siblingData['Items'] as List?) ?? const [];
            final siblings = siblingsRaw.where(isAudioChild).map((i) => AggregatedItem(id: i['Id']?.toString() ?? '', serverId: item.serverId, rawData: i as Map<String, dynamic>)).toList();
            final startIndex = siblings.indexWhere((t) => t.id == item.id);
            if (siblings.isNotEmpty && startIndex >= 0) {
              final playItemsFuture = manager.playItems(
                siblings,
                startIndex: startIndex,
                startPosition: startPosition,
              );
              if (mounted) {
                await context.push('${Destinations.audioPlayer}?isAudiobook=true');
              }
              await playItemsFuture;
              if (mounted) {
                _vm.load();
              }
              return;
            }
          } catch (_) {}
        }

        // Default audio playback fallback
        final playItemsFuture = manager.playItems(
          [item],
          startPosition: startPosition,
        );
        if (mounted) {
          await context.push('${Destinations.audioPlayer}?isAudiobook=true');
        }
        await playItemsFuture;
        if (mounted) {
          _vm.load();
        }
        return;
      } else {
        // Book reader straight into reading
        context.push(Destinations.book(item.id, serverId: item.serverId)).then((_) {
          if (mounted) {
            _vm.load();
          }
        });
        return;
      }
    }

    context.push(
      Destinations.itemOrPhoto(
        item.id,
        serverId: item.serverId,
        type: item.type,
      ),
    ).then((result) {
      if (result == true && mounted) {
        _vm.load();
      }
    });
  }

  List<BookStat> _stats(AppLocalizations l10n) {
    return [
      BookStat(
        label: l10n.books,
        count: _vm.bookCount,
        onTap: () => context.push(
          Destinations.library(widget.libraryId, includeItemTypes: const ['Book']),
        ),
      ),
      BookStat(
        label: l10n.audiobooks,
        count: _vm.audiobookCount,
        onTap: () => context.push(
          Destinations.library(widget.libraryId, includeItemTypes: const ['AudioBook', 'Audio']),
        ),
      ),
      BookStat(
        label: l10n.series,
        count: _vm.seriesCount,
        onTap: () => context.push(
          Destinations.library(widget.libraryId, includeItemTypes: _itemTypes),
        ),
      ),
      BookStat(
        label: l10n.genres,
        count: _vm.genreCount,
        onTap: () => context.push(Destinations.libraryGenresOf(widget.libraryId)),
      ),
    ];
  }

  FocusNode _getFirstCardFocusNode(String rowId) {
    if (rowId == 'recently_added_books') {
      return _firstRecentBooksFocusNode;
    }
    if (rowId == 'recently_added_audiobooks') {
      return _firstRecentAudiobooksFocusNode;
    }
    return _rowFirstCardFocusNodes.putIfAbsent(
      rowId,
      () => FocusNode(debugLabel: 'FirstCard_$rowId'),
    );
  }

  void _focusRowFirstCard(String destinationRowId, FocusNode node) {
    final controller = _rowControllers[destinationRowId];
    if (controller != null && controller.hasClients) {
      controller.jumpTo(0.0);
    }
    node.requestFocus();
  }

  KeyEventResult _handleRowKeyEvent(KeyEvent event, String rowId, int index, int totalCount) {
    if (!event.isActionable) return KeyEventResult.ignored;

    if (event.logicalKey.isLeftKey) {
      if (index == 0) {
        return KeyEventResult.handled;
      }
    } else if (event.logicalKey.isRightKey) {
      if (index == totalCount - 1) {
        return KeyEventResult.handled;
      }
    } else if (event.logicalKey.isDownKey) {
      if (rowId == 'resume') {
        _libraryTabFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
      final rows = _vm.rows;
      final currentIdx = rows.indexWhere((r) => r.id == rowId || (rowId == 'resume' && r.rowType == HomeRowType.resume));
      if (currentIdx >= 0 && currentIdx < rows.length - 1) {
        final nextRow = rows[currentIdx + 1];
        final targetNode = _getFirstCardFocusNode(nextRow.id);
        _focusRowFirstCard(nextRow.id, targetNode);
        return KeyEventResult.handled;
      } else {
        return KeyEventResult.handled; // Cap at the bottom row
      }
    } else if (event.logicalKey.isUpKey) {
      if (rowId == 'resume') {
        NavigationLayout.focusNavbarNotifier.value?.call();
        return KeyEventResult.handled;
      }
      final rows = _vm.rows;
      final currentIdx = rows.indexWhere((r) => r.id == rowId || (rowId == 'resume' && r.rowType == HomeRowType.resume));
      if (currentIdx > 0) {
        final prevRow = rows[currentIdx - 1];
        final targetNode = prevRow.rowType == HomeRowType.resume
            ? _firstResumeBookFocusNode
            : _getFirstCardFocusNode(prevRow.id);
        _focusRowFirstCard(prevRow.id, targetNode);
        return KeyEventResult.handled;
      } else {
        // First non-resume row goes UP to the stats band
        _booksStatFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final resumeRow = _vm.rows.firstWhere(
      (r) => r.rowType == HomeRowType.resume,
      orElse: () => HomeRow(id: '', title: '', items: [], rowType: HomeRowType.resume),
    );
    final targetNode = resumeRow.items.isNotEmpty ? _firstResumeBookFocusNode : _libraryTabFocusNode;

    return RequestInitialFocus(
      targetNode: targetNode,
      child: _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColorScheme.background,
      body: NavigationLayout(
        showBackButton: true,
        activeRoute: Destinations.bookLibrary(widget.libraryId, collectionType: widget.collectionType),
        child: _vm.isLoading
            ? Center(
                child: CircularProgressIndicator(color: AppColorScheme.accent),
              )
            : RefreshIndicator(
                onRefresh: _vm.refresh,
                child: ListView(
                  controller: _scrollController,
                  padding: const EdgeInsets.only(bottom: 120),
                  children: _buildSlivers(context),
                ),
              ),
      ),
    );
  }

  List<Widget> _buildSlivers(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final topReserve = MediaQuery.paddingOf(context).top + 56;
    final desktopScale = GetIt.instance<UserPreferences>()
        .get(UserPreferences.desktopUiScale)
        .scaleFactor;
    final leftPadding = 60.0 * desktopScale;

    final resumeRow = _vm.rows.firstWhere(
      (r) => r.rowType == HomeRowType.resume,
      orElse: () => HomeRow(id: '', title: '', items: [], rowType: HomeRowType.resume),
    );
    final otherRows = _vm.rows.where((r) => r.rowType != HomeRowType.resume).toList();

    return [
      if (resumeRow.items.isNotEmpty)
        Padding(
          padding: EdgeInsets.only(top: topReserve),
            child: _buildRow(resumeRow, l10n),
        )
      else
        SizedBox(height: topReserve),
      FocusTraversalGroup(
        child: Padding(
          padding: EdgeInsets.fromLTRB(leftPadding, 6, leftPadding, 10),
          child: BookSegmentedControl(
            labels: [l10n.library, l10n.discover],
            selectedIndex: _tab,
            libraryFocusNode: _libraryTabFocusNode,
            discoverFocusNode: _discoverTabFocusNode,
            onUpPressed: () {
              if (resumeRow.items.isNotEmpty) {
                _firstResumeBookFocusNode.requestFocus();
              } else {
                NavigationLayout.focusNavbarNotifier.value?.call();
              }
            },
            onLibraryDownPressed: () {
              _booksStatFocusNode.requestFocus();
            },
            onDiscoverDownPressed: () {
              _audiobooksStatFocusNode.requestFocus();
            },
            onChanged: (v) {
              setState(() => _tab = v);
              if (v == 0 && _scrollController.hasClients) {
                _scrollController.animateTo(
                  0.0,
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOutCubic,
                );
              }
            },
          ),
        ),
      ),
      FocusTraversalGroup(
        child: BookStatsBand(
          stats: _stats(l10n),
          booksFocusNode: _booksStatFocusNode,
          audiobooksFocusNode: _audiobooksStatFocusNode,
          onBooksUpPressed: () {
            _libraryTabFocusNode.requestFocus();
          },
          onAudiobooksUpPressed: () {
            _discoverTabFocusNode.requestFocus();
          },
          onBooksDownPressed: () {
            if (_tab == 0) {
              final hasBooksRow = _vm.rows.any((r) => r.id == 'recently_added_books');
              final hasAudiobooksRow = _vm.rows.any((r) => r.id == 'recently_added_audiobooks');
              if (hasBooksRow) {
                _firstRecentBooksFocusNode.requestFocus();
              } else if (hasAudiobooksRow) {
                _firstRecentAudiobooksFocusNode.requestFocus();
              }
            } else if (_tab == 1) {
              _discoverSettingsFocusNode.requestFocus();
            }
          },
          onAudiobooksDownPressed: () {
            if (_tab == 0) {
              final hasBooksRow = _vm.rows.any((r) => r.id == 'recently_added_books');
              final hasAudiobooksRow = _vm.rows.any((r) => r.id == 'recently_added_audiobooks');
              if (hasAudiobooksRow) {
                _firstRecentAudiobooksFocusNode.requestFocus();
              } else if (hasBooksRow) {
                _firstRecentBooksFocusNode.requestFocus();
              }
            } else if (_tab == 1) {
              _discoverSettingsFocusNode.requestFocus();
            }
          },
        ),
      ),
      if (_tab == 0)
        ...otherRows.map((row) => _buildRow(row, l10n))
      else
        BookDiscoverTab(
          libraryId: widget.libraryId,
          isAudiobook: _vm.isAudiobookLibrary,
          firstFocusNode: _firstDiscoverFocusNode,
          settingsMenuFocusNode: _discoverSettingsFocusNode,
          leftPadding: leftPadding,
          onSettingsUpPressed: () {
            if (_vm.isAudiobookLibrary) {
              _audiobooksStatFocusNode.requestFocus();
            } else {
              _booksStatFocusNode.requestFocus();
            }
          },
        ),
    ];
  }

  Widget _buildRow(HomeRow row, AppLocalizations l10n) {
    final isResume = row.rowType == HomeRowType.resume;
    final desktopScale = GetIt.instance<UserPreferences>()
        .get(UserPreferences.desktopUiScale)
        .scaleFactor;
    final leftPadding = 60.0 * desktopScale;

    final controller = _rowControllers.putIfAbsent(
      row.id,
      () => ScrollController(debugLabel: 'RowScrollController_${row.id}'),
    );

    return LibraryRow(
      key: ValueKey(row.id),
      title: row.title,
      rowHeight: 256,
      leftPadding: leftPadding,
      scrollController: controller,
      onSeeAll: null, // Remove all See All links from this screen
      children: [
        for (var i = 0; i < row.items.length; i++) ...[
          (() {
            final item = row.items[i];
            final rawRatio = item.rawData['PrimaryImageAspectRatio'] as num?;
            final fallbackRatio = (item.type == 'AudioBook' || item.type == 'Audio') ? 1.0 : 2 / 3;
            final ratio = rawRatio != null ? rawRatio.toDouble() : fallbackRatio;

            final cardExpansion = GetIt.instance<UserPreferences>()
                .get(UserPreferences.cardFocusExpansion);

            return MediaCard(
              width: 132,
              aspectRatio: ratio,
              title: item.name,
              subtitle: _vm.bookSubtitle(item),
              imageUrl: _vm.bookImageUrl(item),
              itemType: item.type,
              isFavorite: item.isFavorite,
              isPlayed: item.isPlayed,
              playedPercentage: item.playedPercentage,
              suppressFocusGlow: true,
              cardFocusExpansion: cardExpansion,
              focusNode: (isResume && i == 0)
                  ? _firstResumeBookFocusNode
                  : (i == 0)
                      ? _getFirstCardFocusNode(row.id)
                      : null,
              onKeyEvent: (node, event) => _handleRowKeyEvent(event, isResume ? 'resume' : row.id, i, row.items.length),
              onTap: () => _onItemTap(item, row),
            );
          })(),
        ],
      ],
    );
  }
}
