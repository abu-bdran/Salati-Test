import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qvp_flutter/qvp_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class QuranReaderPage extends StatefulWidget {
  const QuranReaderPage({
    super.key,
    this.initialPage,
  });

  final int? initialPage;

  @override
  State<QuranReaderPage> createState() => _QuranReaderPageState();
}

class _QuranReaderPageState extends State<QuranReaderPage> {
  static const int _firstPage = 1;
  static const int _lastPage = 604;

  static const String _savedPageKey = 'salati_quran_last_page';

  QvpEngine? _engine;
  QvpAtlas? _atlas;
  QvpPage? _page;

  final QvpViewController _viewController =
      QvpViewController();

  int _currentPage = 1;

  bool _loading = true;
  bool _changingPage = false;

  String? _errorMessage;

  @override
  void initState() {
    super.initState();

    _currentPage =
        _clampPage(widget.initialPage ?? _firstPage);

    _enterFullscreen();
    _initializeQuran();
  }

  int _clampPage(int page) {
    if (page < _firstPage) {
      return _firstPage;
    }

    if (page > _lastPage) {
      return _lastPage;
    }

    return page;
  }

  Future<void> _enterFullscreen() async {
    try {
      await SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.immersiveSticky,
      );

      await SystemChrome.setPreferredOrientations(
        const [
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ],
      );
    } catch (e) {
      debugPrint(
        'Quran fullscreen/orientation error: $e',
      );
    }
  }

  Future<void> _restoreSystemUi() async {
    try {
      await SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.edgeToEdge,
      );

      await SystemChrome.setPreferredOrientations(
        const [
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ],
      );
    } catch (e) {
      debugPrint(
        'Quran system UI restore error: $e',
      );
    }
  }

  Future<void> _initializeQuran() async {
    try {
      final prefs =
          await SharedPreferences.getInstance();

      if (widget.initialPage == null) {
        final savedPage =
            prefs.getInt(_savedPageKey);

        if (savedPage != null) {
          _currentPage =
              _clampPage(savedPage);
        }
      }

      final engine =
          QvpEngine.open();

      QvpAtlas? atlas;

      try {
        final atlasData = await rootBundle.load(
          'assets/quran/pages/atlas.qva',
        );

        atlas = engine.loadAtlas(
          atlasData.buffer.asUint8List(),
        );
      } catch (e) {
        debugPrint(
          'Quran atlas loading warning: $e',
        );
      }

      if (!mounted) {
        atlas?.dispose();
        engine.dispose();
        return;
      }

      setState(() {
        _engine = engine;
        _atlas = atlas;
        _loading = true;
        _errorMessage = null;
      });

      await _loadPage(
        _currentPage,
        savePage: false,
      );
    } catch (e, stackTrace) {
      debugPrint(
        'Quran initialization error: $e',
      );

      debugPrintStack(
        stackTrace: stackTrace,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
        _errorMessage =
            'تعذر تشغيل محرك المصحف.\n\n$e';
      });
    }
  }

  Future<void> _loadPage(
    int requestedPage, {
    bool savePage = true,
  }) async {
    final engine = _engine;

    if (engine == null) {
      return;
    }

    final targetPage =
        _clampPage(requestedPage);

    if (_changingPage) {
      return;
    }

    setState(() {
      _changingPage = true;
      _errorMessage = null;
    });

    try {
      final pageNumber =
          targetPage.toString().padLeft(3, '0');

      final pageData =
          await rootBundle.load(
        'assets/quran/pages/$pageNumber.qvp',
      );

      final bytes =
          pageData.buffer.asUint8List();

      final newPage =
          engine.loadPage(bytes);

      try {
        final wordsJson =
            await rootBundle.loadString(
          'assets/quran/pages/$pageNumber.words.json',
        );

        newPage.attachWords(
          wordsJson,
        );
      } catch (e) {
        debugPrint(
          'Words sidecar warning for page '
          '$targetPage: $e',
        );
      }

      final oldPage = _page;

      if (!mounted) {
        newPage.dispose();
        return;
      }

      setState(() {
        _page = newPage;
        _currentPage = targetPage;
        _loading = false;
        _changingPage = false;
      });

      WidgetsBinding.instance
          .addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }

        _viewController.fit();
      });

      if (oldPage != null) {
        WidgetsBinding.instance
            .addPostFrameCallback((_) {
          oldPage.dispose();
        });
      }

      if (savePage) {
        final prefs =
            await SharedPreferences.getInstance();

        await prefs.setInt(
          _savedPageKey,
          targetPage,
        );
      }
    } catch (e, stackTrace) {
      debugPrint(
        'Quran page loading error: $e',
      );

      debugPrintStack(
        stackTrace: stackTrace,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
        _changingPage = false;
        _errorMessage =
            'تعذر تحميل صفحة المصحف رقم '
            '$targetPage.\n\n$e';
      });
    }
  }

  Future<void> _nextPage() async {
    if (_currentPage >= _lastPage) {
      return;
    }

    await _loadPage(
      _currentPage + 1,
    );
  }

  Future<void> _previousPage() async {
    if (_currentPage <= _firstPage) {
      return;
    }

    await _loadPage(
      _currentPage - 1,
    );
  }

  Future<void> _showPageSelector() async {
    final controller =
        TextEditingController(
      text: '$_currentPage',
    );

    final selected =
        await showDialog<int>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text(
            'الانتقال إلى صفحة',
            textAlign: TextAlign.right,
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType:
                TextInputType.number,
            textAlign: TextAlign.center,
            decoration:
                const InputDecoration(
              hintText: '1 - 604',
              border:
                  OutlineInputBorder(),
            ),
            onSubmitted: (_) {
              final value =
                  int.tryParse(
                controller.text.trim(),
              );

              if (value != null &&
                  value >= _firstPage &&
                  value <= _lastPage) {
                Navigator.of(context)
                    .pop(value);
              }
            },
          ),
          actionsAlignment:
              MainAxisAlignment.spaceBetween,
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () {
                final value =
                    int.tryParse(
                  controller.text.trim(),
                );

                if (value == null ||
                    value < _firstPage ||
                    value > _lastPage) {
                  return;
                }

                Navigator.of(context)
                    .pop(value);
              },
              child: const Text(
                'انتقال',
              ),
            ),
          ],
        );
      },
    );

    controller.dispose();

    if (selected != null) {
      await _loadPage(selected);
    }
  }

  void _handleWordTap(
    int word,
    QvpHit hit,
  ) {
    final page = _page;

    if (page == null) {
      return;
    }

    final ayahKey =
        hit.ayahKey ??
        (word >= 0 &&
                word < page.words.length
            ? page.wordKey(word)
            : null);

    _showAyahActions(
      ayahKey: ayahKey,
      word: word,
    );
  }

  Future<void> _showAyahActions({
    required String? ayahKey,
    required int word,
  }) async {
    final key =
        ayahKey ?? 'الآية';

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        final scheme =
            Theme.of(context).colorScheme;

        return Directionality(
          textDirection:
              TextDirection.rtl,
          child: Container(
            decoration:
                BoxDecoration(
              color: scheme.surface,
              borderRadius:
                  const BorderRadius.vertical(
                top: Radius.circular(30),
              ),
            ),
            padding:
                const EdgeInsets.fromLTRB(
              18,
              12,
              18,
              24,
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize:
                    MainAxisSize.min,
                children: [
                  Container(
                    width: 46,
                    height: 5,
                    decoration:
                        BoxDecoration(
                      color: scheme
                          .outlineVariant,
                      borderRadius:
                          BorderRadius.circular(
                        20,
                      ),
                    ),
                  ),
                  const SizedBox(
                    height: 18,
                  ),
                  Row(
                    children: [
                      Container(
                        width: 50,
                        height: 50,
                        decoration:
                            BoxDecoration(
                          color: scheme
                              .primaryContainer,
                          borderRadius:
                              BorderRadius.circular(
                            16,
                          ),
                        ),
                        child: Icon(
                          Icons.menu_book_rounded,
                          color:
                              scheme.primary,
                        ),
                      ),
                      const SizedBox(
                        width: 12,
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'الآية المحددة',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight:
                                    FontWeight.w900,
                              ),
                            ),
                            const SizedBox(
                              height: 4,
                            ),
                            Text(
                              key,
                              style: TextStyle(
                                color: scheme
                                    .onSurfaceVariant,
                                fontSize: 12,
                                fontWeight:
                                    FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(
                    height: 18,
                  ),
                  _ayahActionTile(
                    icon:
                        Icons.play_circle_fill_rounded,
                    title:
                        'تشغيل الآية فقط',
                    subtitle:
                        'سنربطها بالقراء في المرحلة التالية',
                    color:
                        scheme.primary,
                    onTap: () {
                      Navigator.of(context)
                          .pop();

                      ScaffoldMessenger.of(
                        this.context,
                      ).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'تشغيل الآية سيُضاف في المرحلة التالية.',
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(
                    height: 8,
                  ),
                  _ayahActionTile(
                    icon:
                        Icons.headphones_rounded,
                    title:
                        'اختيار القارئ',
                    subtitle:
                        'قائمة القراء والتحكم بالتلاوة',
                    color:
                        scheme.secondary,
                    onTap: () {
                      Navigator.of(context)
                          .pop();

                      ScaffoldMessenger.of(
                        this.context,
                      ).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'نافذة القراء سنربطها بعد نجاح شاشة المصحف.',
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(
                    height: 8,
                  ),
                  _ayahActionTile(
                    icon:
                        Icons.download_rounded,
                    title:
                        'تحميل الآية',
                    subtitle:
                        'للاستماع إليها بدون إنترنت',
                    color:
                        scheme.tertiary,
                    onTap: () {
                      Navigator.of(context)
                          .pop();

                      ScaffoldMessenger.of(
                        this.context,
                      ).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'تحميل الصوت سيُضاف بعد ربط القراء.',
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(
                    height: 8,
                  ),
                  _ayahActionTile(
                    icon:
                        Icons.repeat_rounded,
                    title:
                        'تكرار الآية',
                    subtitle:
                        'تحديد عدد مرات التكرار',
                    color:
                        scheme.primary,
                    onTap: () {
                      Navigator.of(context)
                          .pop();

                      ScaffoldMessenger.of(
                        this.context,
                      ).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'نظام التكرار سيُضاف مع مشغل التلاوة.',
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _ayahActionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: color.withValues(
        alpha: 0.08,
      ),
      borderRadius:
          BorderRadius.circular(18),
      child: InkWell(
        borderRadius:
            BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding:
              const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 13,
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration:
                    BoxDecoration(
                  color: color.withValues(
                    alpha: 0.13,
                  ),
                  borderRadius:
                      BorderRadius.circular(
                    14,
                  ),
                ),
                child: Icon(
                  icon,
                  color: color,
                  size: 23,
                ),
              ),
              const SizedBox(
                width: 12,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style:
                          const TextStyle(
                        fontSize: 14,
                        fontWeight:
                            FontWeight.w900,
                      ),
                    ),
                    const SizedBox(
                      height: 3,
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(
                          context,
                        )
                            .colorScheme
                            .onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_left_rounded,
                color: Theme.of(context)
                    .colorScheme
                    .onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showReaderInfo() async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return Directionality(
          textDirection:
              TextDirection.rtl,
          child: AlertDialog(
            title: const Row(
              children: [
                Icon(
                  Icons.auto_stories_rounded,
                ),
                SizedBox(width: 8),
                Text('المصحف الشريف'),
              ],
            ),
            content: const Text(
              'مصحف حفص عن عاصم، يعمل بصفحات QVP المحلية داخل التطبيق. '
              'يمكنك التكبير والتحريك والتدوير، وسيتم حفظ آخر صفحة وصلت إليها.',
            ),
            actions: [
              TextButton(
                onPressed: () =>
                    Navigator.of(context).pop(),
                child: const Text('تم'),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _saveCurrentPage();

    _page?.dispose();
    _atlas?.dispose();
    _engine?.dispose();

    _viewController.dispose();

    _restoreSystemUi();

    super.dispose();
  }

  Future<void> _saveCurrentPage() async {
    try {
      final prefs =
          await SharedPreferences.getInstance();

      await prefs.setInt(
        _savedPageKey,
        _currentPage,
      );
    } catch (e) {
      debugPrint(
        'Quran last page save error: $e',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme =
        Theme.of(context);

    final scheme =
        theme.colorScheme;

    final page =
        _page;

    return Directionality(
      textDirection:
          TextDirection.rtl,
      child: Scaffold(
        backgroundColor:
            const Color(0xFF101513),
        body: SafeArea(
          child: Stack(
            children: [
              Positioned.fill(
                child: page == null
                    ? _buildLoadingOrError(
                        scheme,
                      )
                    : Container(
                        color:
                            const Color(
                          0xFFFDFBF4,
                        ),
                        child:
                            QvpPageView(
                          page: page,
                          controller:
                              _viewController,
                          layout:
                              const QvpViewLayout(
                            padTop: 20,
                            padBottom: 20,
                            padSide: 14,
                            lineSpacing: 1,
                            fillHeight: false,
                          ),
                          paper:
                              const Color(
                            0xFFFDFBF4,
                          ),
                          defaultInk:
                              '#231F20',
                          selectionEnabled:
                              false,
                          panZoomEnabled:
                              true,
                          paperShadow:
                              false,
                          onWordTap:
                              _handleWordTap,
                          onDecorationTap:
                              (decoration) {
                            if (decoration
                                    .ayah >
                                0) {
                              final key =
                                  '${decoration.surah}:${decoration.ayah}';

                              _showAyahActions(
                                ayahKey: key,
                                word: -1,
                              );
                            }
                          },
                          onEmptyTap: () {},
                        ),
                      ),
              ),

              if (_loading ||
                  _changingPage)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Container(
                      color: Colors.black
                          .withValues(
                        alpha:
                            _page == null
                                ? 0.12
                                : 0.04,
                      ),
                      child: Center(
                        child: Container(
                          padding:
                              const EdgeInsets
                                  .symmetric(
                            horizontal: 20,
                            vertical: 14,
                          ),
                          decoration:
                              BoxDecoration(
                            color: Colors.black
                                .withValues(
                              alpha: 0.72,
                            ),
                            borderRadius:
                                BorderRadius
                                    .circular(
                              18,
                            ),
                          ),
                          child: Row(
                            mainAxisSize:
                                MainAxisSize.min,
                            children: [
                              const SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                  color:
                                      Colors.white,
                                ),
                              ),
                              const SizedBox(
                                width: 10,
                              ),
                              Text(
                                'جاري تحميل الصفحة...',
                                style:
                                    const TextStyle(
                                  color:
                                      Colors.white,
                                  fontWeight:
                                      FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

              _buildTopBar(
                scheme,
              ),

              _buildBottomControls(
                scheme,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingOrError(
    ColorScheme scheme,
  ) {
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding:
              const EdgeInsets.all(24),
          child: Column(
            mainAxisSize:
                MainAxisSize.min,
            children: [
              Container(
                width: 70,
                height: 70,
                decoration:
                    BoxDecoration(
                  color: scheme.error
                      .withValues(
                    alpha: 0.10,
                  ),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.error_outline_rounded,
                  size: 38,
                  color: scheme.error,
                ),
              ),
              const SizedBox(
                height: 16,
              ),
              const Text(
                'تعذر فتح المصحف',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight:
                      FontWeight.w900,
                ),
              ),
              const SizedBox(
                height: 10,
              ),
              Text(
                _errorMessage!,
                textAlign:
                    TextAlign.center,
                style: const TextStyle(
                  color:
                      Colors.white70,
                  fontSize: 12,
                  height: 1.6,
                ),
              ),
              const SizedBox(
                height: 18,
              ),
              FilledButton.icon(
                onPressed:
                    _initializeQuran,
                icon: const Icon(
                  Icons.refresh_rounded,
                ),
                label:
                    const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      );
    }

    return const Center(
      child:
          CircularProgressIndicator(
        color: Color(0xFFE2BD63),
      ),
    );
  }

  Widget _buildTopBar(
    ColorScheme scheme,
  ) {
    return Positioned(
      top: 10,
      left: 10,
      right: 10,
      child: Row(
        children: [
          _readerIconButton(
            icon:
                Icons.arrow_back_rounded,
            tooltip: 'العودة',
            onPressed: () =>
                Navigator.of(context).pop(),
          ),
          const SizedBox(
            width: 7,
          ),
          Expanded(
            child: Container(
              height: 48,
              padding:
                  const EdgeInsets.symmetric(
                horizontal: 14,
              ),
              decoration:
                  BoxDecoration(
                color: Colors.black
                    .withValues(
                  alpha: 0.60,
                ),
                borderRadius:
                    BorderRadius.circular(
                  17,
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.menu_book_rounded,
                    color:
                        Color(0xFFE2BD63),
                    size: 20,
                  ),
                  const SizedBox(
                    width: 8,
                  ),
                  const Expanded(
                    child: Text(
                      'المصحف الشريف',
                      style: TextStyle(
                        color:
                            Colors.white,
                        fontWeight:
                            FontWeight.w900,
                      ),
                    ),
                  ),
                  Text(
                    'صفحة $_currentPage / $_lastPage',
                    style:
                        const TextStyle(
                      color:
                          Colors.white70,
                      fontSize: 11,
                      fontWeight:
                          FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(
            width: 7,
          ),
          _readerIconButton(
            icon:
                Icons.info_outline_rounded,
            tooltip: 'معلومات',
            onPressed:
                _showReaderInfo,
          ),
        ],
      ),
    );
  }

  Widget _buildBottomControls(
    ColorScheme scheme,
  ) {
    return Positioned(
      left: 12,
      right: 12,
      bottom: 12,
      child: Row(
        children: [
          _readerIconButton(
            icon:
                Icons.chevron_left_rounded,
            tooltip: 'الصفحة التالية',
            onPressed:
                _currentPage < _lastPage
                    ? _nextPage
                    : null,
          ),
          const SizedBox(
            width: 7,
          ),
          Expanded(
            child: Container(
              height: 52,
              padding:
                  const EdgeInsets.symmetric(
                horizontal: 7,
              ),
              decoration:
                  BoxDecoration(
                color: Colors.black
                    .withValues(
                  alpha: 0.62,
                ),
                borderRadius:
                    BorderRadius.circular(
                  18,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _bottomAction(
                      icon:
                          Icons.first_page_rounded,
                      label: 'الأولى',
                      onTap: _currentPage >
                              _firstPage
                          ? () => _loadPage(
                                _firstPage,
                              )
                          : null,
                    ),
                  ),
                  Expanded(
                    child: _bottomAction(
                      icon:
                          Icons.format_list_numbered_rounded,
                      label: 'انتقال',
                      onTap:
                          _showPageSelector,
                    ),
                  ),
                  Expanded(
                    child: _bottomAction(
                      icon:
                          Icons.last_page_rounded,
                      label: 'الأخيرة',
                      onTap: _currentPage <
                              _lastPage
                          ? () => _loadPage(
                                _lastPage,
                              )
                          : null,
                    ),
                  ),
                  Expanded(
                    child: _bottomAction(
                      icon:
                          Icons.fit_screen_rounded,
                      label: 'ملاءمة',
                      onTap: () =>
                          _viewController
                              .fit(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(
            width: 7,
          ),
          _readerIconButton(
            icon:
                Icons.chevron_right_rounded,
            tooltip:
                'الصفحة السابقة',
            onPressed:
                _currentPage > _firstPage
                    ? _previousPage
                    : null,
          ),
        ],
      ),
    );
  }

  Widget _bottomAction({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
  }) {
    final enabled =
        onTap != null;

    return InkWell(
      onTap: onTap,
      borderRadius:
          BorderRadius.circular(14),
      child: SizedBox(
        height: 48,
        child: Column(
          mainAxisAlignment:
              MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 19,
              color: enabled
                  ? Colors.white
                  : Colors.white30,
            ),
            const SizedBox(
              height: 2,
            ),
            Text(
              label,
              style: TextStyle(
                color: enabled
                    ? Colors.white70
                    : Colors.white24,
                fontSize: 8.5,
                fontWeight:
                    FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _readerIconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
  }) {
    final enabled =
        onPressed != null;

    return Material(
      color: Colors.black
          .withValues(
        alpha: 0.62,
      ),
      borderRadius:
          BorderRadius.circular(16),
      child: InkWell(
        onTap: onPressed,
        borderRadius:
            BorderRadius.circular(16),
        child: Tooltip(
          message: tooltip,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Icon(
              icon,
              color: enabled
                  ? Colors.white
                  : Colors.white30,
              size: 23,
            ),
          ),
        ),
      ),
    );
  }
}
