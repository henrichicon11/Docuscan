import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/kit.dart';
import 'page_editor.dart';

/// Full-screen, zoomable page reader with swipe navigation.
class PageViewerScreen extends StatefulWidget {
  final String docId;
  final int initialIndex;

  const PageViewerScreen({
    super.key,
    required this.docId,
    this.initialIndex = 0,
  });

  @override
  State<PageViewerScreen> createState() => _PageViewerScreenState();
}

class _PageViewerScreenState extends State<PageViewerScreen> {
  late PageController _ctl;
  late int _index;
  bool _chromeVisible = true;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _ctl = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final doc = state.docById(widget.docId);

    if (doc == null || doc.pages.isEmpty) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(
          icon: Icons.delete_outline,
          title: 'Nothing to show',
          message: 'This document no longer exists.',
        ),
      );
    }

    final safeIndex = _index.clamp(0, doc.pageCount - 1);

    return Scaffold(
      backgroundColor: const Color(0xFF08090B),
      body: Stack(
        children: [
          GestureDetector(
            onTap: () => setState(() => _chromeVisible = !_chromeVisible),
            child: PageView.builder(
              controller: _ctl,
              itemCount: doc.pageCount,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (context, i) {
                final page = doc.pages[i];
                return InteractiveViewer(
                  minScale: 1,
                  maxScale: 5,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(T.s12),
                      child: Hero(
                        tag: i == widget.initialIndex
                            ? 'page_${page.id}'
                            : 'viewer_${page.id}',
                        child: Image.memory(
                          page.processed,
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.high,
                          gaplessPlayback: true,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // Top chrome
          AnimatedPositioned(
            duration: T.med,
            curve: T.ease,
            top: _chromeVisible ? 0 : -120,
            left: 0,
            right: 0,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.78),
                    Colors.transparent,
                  ],
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(T.s4, T.s4, T.s16, T.s20),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        iconSize: 21,
                        onPressed: () => Navigator.pop(context),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              doc.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.t.titleMedium?.copyWith(
                                color: Colors.white,
                              ),
                            ),
                            Text(
                              'Page ${safeIndex + 1} of ${doc.pageCount}'
                              '  ·  ${doc.pages[safeIndex].filter.label}',
                              style: context.t.bodySmall?.copyWith(
                                color: Colors.white70,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.tune, color: Colors.white),
                        iconSize: 20,
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => PageEditorScreen(
                              docId: doc.id,
                              pageId: doc.pages[safeIndex].id,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Bottom page rail
          AnimatedPositioned(
            duration: T.med,
            curve: T.ease,
            bottom: _chromeVisible ? 0 : -140,
            left: 0,
            right: 0,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.8),
                    Colors.transparent,
                  ],
                ),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.only(top: T.s24, bottom: T.s12),
                  child: SizedBox(
                    height: 62,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: T.s16),
                      itemCount: doc.pageCount,
                      separatorBuilder: (_, __) => const SizedBox(width: T.s8),
                      itemBuilder: (context, i) {
                        final active = i == safeIndex;
                        return GestureDetector(
                          onTap: () => _ctl.animateToPage(
                            i,
                            duration: T.med,
                            curve: T.ease,
                          ),
                          child: AnimatedContainer(
                            duration: T.fast,
                            width: 42,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(T.s4),
                              border: Border.all(
                                color: active
                                    ? context.c.accent
                                    : Colors.white24,
                                width: active ? 2 : 1,
                              ),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(3),
                              child: Image.memory(
                                doc.pages[i].processed,
                                fit: BoxFit.cover,
                                gaplessPlayback: true,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
