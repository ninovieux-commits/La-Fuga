/// Un écran qui SUIT les réglages visibles.
///
/// Nino : « quand on valide un nouveau thème, la différence doit se charger
/// dans toute l'app directement, les pages ne doivent pas créer la modif une
/// par une quand elles sont rechargées. »
///
/// À poser sur l'état d'un écran qui lit le thème ou la langue au moment de
/// se dessiner : `class _MonEcranState extends State&lt;MonEcran&gt; with
/// SuitLesReglages`. Il se repeint dès qu'un de ces réglages change, qu'il
/// soit à l'écran ou DESSOUS — reconstruire la racine ne suffirait pas :
/// mesuré, un écran empilé ne se reconstruit pas pour autant, chaque route
/// ayant sa propre portée de construction.
library;

import 'package:flutter/widgets.dart';

import '../state/settings.dart';

mixin SuitLesReglages<T extends StatefulWidget> on State<T> {
  @override
  void initState() {
    super.initState();
    reglagesVisibles.addListener(_repeins);
  }

  @override
  void dispose() {
    reglagesVisibles.removeListener(_repeins);
    super.dispose();
  }

  void _repeins() {
    if (mounted) setState(() {});
  }
}
