import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:ln_reader/novel/ln_isolate.dart';
import 'package:ln_reader/novel/struct/ln_preview.dart';
import 'package:ln_reader/novel/struct/ln_source.dart';
import 'package:ln_reader/scopes/global_scope.dart' as globals;
import 'package:ln_reader/util/net/connection_status.dart';
import 'package:ln_reader/util/ui/retry.dart';
import 'package:ln_reader/views/widget/loader.dart';
import 'package:ln_reader/views/sidebar_view.dart';
import 'package:ln_reader/views/widget/custom_tab_view.dart';

class HomeArgs {
  HomeArgs({
    this.poppable,
    this.source,
    this.html,
    this.isSearch = false,
  });

  final bool poppable;
  final LNSource source;
  final List<String> html;
  final bool isSearch;
}

class HomeView extends StatefulWidget {
  HomeView({
    Key key,
    this.source,
    this.html,
    this.isSearch = false,
  }) : super(key: key);

  final LNSource source;
  final List<String> html;
  final bool isSearch;

  @override
  _HomeView createState() => _HomeView();
}

class _HomeView extends State<HomeView> {
  bool searching = false;
  bool submitted = false;
  bool viewingPreview = false;

  Map<String, List<LNPreview>> previews;
  List<LNPreview> searchPreviews;

  bool get viewable => previews != null || searchPreviews != null;

  bool get offline => widget.html == null || globals.offline.val;

  @override
  void initState() {
    super.initState();

    globals.theme.bind(this);
    globals.source.bind(this);
    globals.source.val.selectedGenres.bind(this);
    globals.offline.bind(this);

    SchedulerBinding.instance.addPostFrameCallback((_) async {
      if (widget.html != null) {
        if (widget.isSearch) {
          // Retrieve search previews in the background
          // Note: search will only have one HTML entry
          final _searchPreviews = await LNIsolate.parseSearchPreviews(
            widget.source,
            widget.html.first,
          );
          // Update searchPreviews state
          setState(() {
            searchPreviews = _searchPreviews;
          });
        } else {
          // Retrieve previews in the background
          final _previews = await LNIsolate.parsePreviews(
            widget.source,
            widget.html,
          );

          // Update previews state
          setState(() {
            previews = _previews;
          });
        }
      }
    });
  }

  @override
  void dispose() {
    globals.theme.disposeAt(this);
    globals.source.disposeAt(this);
    globals.source.val.selectedGenres.disposeAt(this);
    globals.offline.disposeAt(this);
    super.dispose();
  }

  _refresh({String query, bool forceSearch = false}) async {
    if (globals.offline.val) {
      return;
    }

    if (query != null || forceSearch) {
      setState(() => viewingPreview = true);

      query = (query != null ? query.toLowerCase() : null);

      final genres = globals.source.val.selectedGenres.val;

      final html = await Retry.exec(context, () {
        return globals.source.val.search(query, genres);
      });

      if (html != null) {
        _renavigate(
          source: globals.source.val,
          html: [html],
          isSearch: true,
        );
      } else {
        print('failed to search, navigator#pop + alert?');
      }

      setState(() => viewingPreview = false);
    } else {
      setState(() => viewingPreview = true);

      final html = await Retry.exec(context, () {
        return globals.source.val.fetchPreviews();
      });

      if (html != null) {
        _renavigate(
          source: globals.source.val,
          html: html,
          isSearch: false,
          replace: true,
        );
      } else {
        print('failed to retrieve, navigate somewhere else...');
      }

      // may not be mounted if replace: true
      if (mounted) {
        setState(() => viewingPreview = false);
      }
    }
  }

  Future _renavigate({
    LNSource source,
    List<String> html,
    bool isSearch,
    bool replace = false,
  }) {
    if (widget.isSearch) {
      // Make it so that there's not various search pages
      Navigator.pop(context);
    }

    final pusher =
        replace ? Navigator.pushReplacementNamed : Navigator.pushNamed;

    return pusher(
      context,
      '/home',
      arguments: HomeArgs(
        poppable: widget.html != null,
        source: source,
        html: html,
        isSearch: isSearch,
      ),
    );
  }

  Widget _makeCategoryWidget(genre, setState) {
    final selectedGenres = globals.source.val.selectedGenres.val;
    if (globals.source.val.multiGenre) {
      return CheckboxListTile(
          title: Text(genre),
          value: selectedGenres.contains(genre),
          onChanged: (val) {
            setState(() {
              if (val) {
                selectedGenres.add(genre);
              } else {
                selectedGenres.remove(genre);
              }
            });
          });
    } else {
      return Card(
        color: Theme.of(context).primaryColor,
        child: ListTile(
          title: Text(
            'View $genre',
            style: Theme.of(context).textTheme.subhead,
          ),
          onTap: () {
            selectedGenres.clear();
            selectedGenres.add(genre);
            Navigator.of(context).pop();
            _refresh(forceSearch: true);
          },
        ),
      );
    }
  }

  _showCategoryDialog() {
    final isMulti = globals.source.val.multiGenre;
    return showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
            backgroundColor: Theme.of(context).accentColor,
            title: Text('Categories'),
            content: SingleChildScrollView(
              child: Column(
                children: globals.source.val.genres
                    .map(
                      (g) => StatefulBuilder(
                            builder: (ctx, setState) =>
                                _makeCategoryWidget(g, setState),
                          ),
                    )
                    .toList(),
              ),
            ),
          ),
    ).then((_) {
      if (isMulti) {
        _refresh(forceSearch: true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    globals.homeContext.val = context;
    return viewingPreview || (widget.html != null && !viewable)
        ? Loader.create(context)
        : Scaffold(
            backgroundColor: Theme.of(context).backgroundColor,
            // only show the drawer if it isn't a search
            drawer: !widget.isSearch ? SidebarView() : null,
            appBar: PreferredSize(
              preferredSize: Size.fromHeight(50.0),
              child: AppBar(
                elevation: 0.0,
                title: offline
                    ? Text(
                        'Offline',
                        style: Theme.of(context).textTheme.title,
                      )
                    : (searching
                        ? PreferredSize(
                            preferredSize: Size.fromHeight(48.0),
                            child: TextField(
                              autofocus: true,
                              decoration:
                                  InputDecoration(hintText: 'Search...'),
                              onSubmitted: (String text) {
                                submitted = true;
                                _refresh(query: text);
                                searching = false;
                              },
                            ),
                          )
                        : Container(
                            height: kToolbarHeight,
                            child: ListTile(
                              contentPadding: EdgeInsets.all(0),
                              title: Row(children: [
                                Flexible(
                                  child: Text(
                                    globals.source.val.name,
                                    softWrap: true,
                                    maxLines: 2,
                                  ),
                                ),
                                Padding(
                                  padding: EdgeInsets.only(left: 2.0, top: 2.0),
                                  child: Icon(
                                    Icons.keyboard_arrow_down,
                                    size: 16.0,
                                  ),
                                ),
                              ]),
                              onTap: () {
                                Navigator.of(context).pushReplacementNamed(
                                  '/',
                                  arguments: {
                                    'force_choose': true,
                                  },
                                );
                              },
                            ),
                          )),
                actions: offline
                    ? [
                        IconButton(
                          icon: Icon(Icons.refresh),
                          onPressed: () => _refresh(),
                        ),
                      ]
                    : [
                        globals.source.val.genres.isEmpty
                            ? null
                            : IconButton(
                                icon: Icon(Icons.filter_list),
                                onPressed: () => _showCategoryDialog(),
                              ),
                        IconButton(
                          icon: Icon(searching ? Icons.close : Icons.search),
                          onPressed: () {
                            setState(() {
                              searching = !searching;
                              if (!searching && submitted) {
                                _refresh();
                              }
                              submitted = false;
                            });
                          },
                        ),
                      ].where((child) => child != null).toList(),
                iconTheme: IconThemeData(
                  color: Theme.of(context).textTheme.headline.color,
                ),
                actionsIconTheme: IconThemeData(
                  color: Theme.of(context).textTheme.headline.color,
                ),
              ),
            ),
            body: offline
                ? ConnectionStatus.createOfflineWidget(context)
                : (searchPreviews != null
                    ? globals.source.val.makePreviewList(
                        context,
                        searchPreviews,
                        onEntryTap: () => setState(() => viewingPreview = true),
                        onEntryNavPush: () =>
                            setState(() => viewingPreview = false),
                        offline: globals.offline.val,
                      )
                    : CustomTabView(
                        itemCount: previews != null ? previews.length : 0,
                        tabBuilder: (ctx, i) => Tab(
                              child: Text(previews.keys.elementAt(i)),
                            ),
                        pageBuilder: (ctx, i) => Center(
                              child: globals.source.val.makePreviewList(
                                context,
                                previews.values.elementAt(i),
                                onEntryTap: () =>
                                    setState(() => viewingPreview = true),
                                onEntryNavPush: () =>
                                    setState(() => viewingPreview = false),
                                offline: globals.offline.val,
                              ),
                            ),
                      )),
          );
  }
}
