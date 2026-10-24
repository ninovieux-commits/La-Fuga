/// Bandeau du haut d'une partie — portage de `top_bar` (main.py).
///
/// Toujours les mêmes touches, dans le même ordre : retourner le plateau et
/// revenir au menu à gauche, puis, poussées à droite, celles que le mode en
/// cours autorise, et la pause tout au bout.
///
/// Comme en Kivy, « Retour au menu » reste caché tant que la partie n'est pas
/// finie : on quitte une partie en cours par la pause, pas par mégarde.
///
/// ## Deux moitiés, et un trou au milieu
///
/// Le centre du bandeau n'appartient à personne : l'appareil photo selfie des
/// téléphones récents y est percé, et passe devant tout ce qu'on y pose. Les
/// touches de gauche restent donc collées à gauche, celles de droite à
/// droite, et [kTrouCamera] les sépare.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../i18n/translations.dart';
import '../../theme/themes.dart';
import '../scale.dart';
import 'boule_dialog.dart';
import 'picto_touche.dart';
import 'unread_dot.dart';

/// Largeur laissée LIBRE au centre du bandeau.
///
/// L'appareil photo selfie des téléphones récents est percé là, dans la
/// barre d'état, et passe devant tout ce qu'on y pose. Nino : « il faudrait
/// éviter qu'il y ait de bouton au centre de ce bandeau. »
const double kTrouCamera = 96;

/// Fond des touches rondes du bandeau — le `(0.15, 0.15, 0.15)` de Kivy.
const Color kBarButtonDark = Color.fromRGBO(38, 38, 38, 1);

/// Fond de la touche « Deep Grey » — `(0.30, 0.30, 0.34)`.
const Color kBarButtonDeepGrey = Color.fromRGBO(77, 77, 87, 1);

class GameTopBar extends StatelessWidget {
  const GameTopBar({
    super.key,
    required this.palette,
    required this.color,
    required this.onFlip,
    required this.onPause,
    this.pauseLabel = '| |',
    this.onMenu,
    this.onChat,
    this.unreadChat = 0,
    this.onCopyNmc,
    this.onCopyFug,
    this.onAnalyse,
    this.onPremove,
    this.raisonPremove,
    this.onAutoPlay,
    this.autoPlayOn = false,
    this.onDeepGrey,
    this.aiDeepMode,
    this.onToggleAiMode,
  });

  final ThemePalette palette;

  /// Couleur du camp affiché EN HAUT, vive quand il a le trait : chez Kivy,
  /// ce bandeau et celui des coups sont les deux témoins du tour.
  final Color color;

  final VoidCallback onFlip;
  final VoidCallback onPause;

  /// En relecture et en analyse, Kivy remplace la pause par `<<`, qui ramène
  /// d'où l'on vient : il n'y a pas de partie à suspendre.
  final String pauseLabel;

  /// Non nul quand la partie est finie : la touche apparaît alors.
  final VoidCallback? onMenu;

  /// En ligne seulement.
  final VoidCallback? onChat;

  /// Messages non lus : Kivy écrit « Chat (2) ».
  /// Nombre de messages non lus de l'adversaire de cette partie : chat de la
  /// partie et messages privés reçus de lui. Seul le fait qu'il y en ait
  /// compte — la pastille ne montre pas de nombre.
  final int unreadChat;

  /// En relecture : copier le `.nmc` de la partie qu'on est en train de
  /// relire, sans avoir à ressortir jusqu'à l'historique pour le faire.
  final VoidCallback? onCopyNmc;

  /// Copier la POSITION affichée, au format `.fug`. En analyse, où il y a la
  /// place ; en relecture, la touche « Copier » propose les deux.
  final VoidCallback? onCopyFug;

  /// En relecture et en correspondance — derrière la boule.
  final VoidCallback? onAnalyse;

  /// Relecture : ouvrir (ou refermer) la lecture automatique. Une touche
  /// RONDE, à gauche : les larges du bandeau sont déjà au bord du débordement
  /// sur un petit écran, et le côté gauche est libre en relecture.
  final VoidCallback? onAutoPlay;

  /// Vraie quand la lecture automatique est ouverte : la touche s'allume.
  final bool autoPlayOn;

  /// Correspondance, et seulement quand c'est à l'adversaire de jouer :
  /// préparer ses pré-coups. Derrière la boule, qu'elle partage avec
  /// « Analyser » : la touche pâlit dans le popup plutôt que de s'en aller.
  final VoidCallback? onPremove;

  /// Pourquoi les pré-coups ne sont pas ouvrables, quand ils ne le sont pas.
  ///
  /// Écrite dans le popup de la boule, au-dessus de la touche pâlie : c'est
  /// à vous de jouer, ou vous ne faites que regarder.
  final String? raisonPremove;

  /// En analyse et en relecture : reprendre la position contre Deep Grey.
  final VoidCallback? onDeepGrey;

  /// Contre Deep Grey : `true` en mode profond.
  final bool? aiDeepMode;
  final VoidCallback? onToggleAiMode;

  @override
  Widget build(BuildContext context) => Container(
    // La hauteur vient de la pile (7 % de l'écran), comme le `size_hint` de
    // Kivy : on ne la fixe pas ici.
    color: color,
    // Marge verticale réduite : les touches rondes suivent la hauteur du
    // bandeau, moins de marge veut dire des touches plus grosses.
    padding: EdgeInsets.symmetric(horizontal: S(12), vertical: S(2)),
    child: Row(
      children: [
        // DEUX MOITIÉS, ET UN TROU AU MILIEU. Nino : « il faudrait aussi
        // éviter qu'il y ait de bouton au centre de ce bandeau, car sinon
        // l'appareil photo selfie est devant le bouton. » Les touches de
        // gauche restent collées à gauche, celles de droite à droite, et le
        // centre n'appartient à personne.
        //
        // Deux moitiés plutôt qu'un simple écart : avec un `Spacer`, les
        // deux groupes se rejoignent au milieu dès qu'ils s'allongent, et le
        // trou disparaît au moment où l'on en a le plus besoin.
        Expanded(
          child: Row(
            children: [
              _round(
                '< >',
                onFlip,
                fontSize: SF(21),
                tooltip: T('Retourner le plateau'),
              ),
              if (onAutoPlay != null) ...[
                SizedBox(width: S(6)),
                _button(
                  '▶',
                  onAutoPlay!,
                  width: null,
                  color: autoPlayOn ? palette.clair : kBarButtonDark,
                  radius: S(20),
                  fontSize: SF(19),
                  tooltip: T('Lecture automatique'),
                ),
              ],
              if (onMenu != null) ...[
                SizedBox(width: S(6)),
                _flex(
                  _wide(
                    T('Retour au menu'),
                    onMenu!,
                    width: S(178),
                    color: palette.clair,
                    fontSize: SF(13),
                  ),
                ),
              ],
            ],
          ),
        ),
        SizedBox(width: S(kTrouCamera)),
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (onChat != null) ...[
                // Pastille plutôt que compteur, et elle ne s'allume que pour un
                // message de l'adversaire de cette partie.
                _flex(
                  UnreadDot(
                    show: unreadChat > 0,
                    child: _wide(
                      T('Chat'),
                      onChat!,
                      width: S(104),
                      color: kBarButtonDark,
                    ),
                  ),
                ),
                SizedBox(width: S(6)),
              ],
              if (onToggleAiMode != null) ...[
                _flex(
                  _wide(
                    aiDeepMode == true ? T('Profond') : T('Rapide'),
                    onToggleAiMode!,
                    width: S(128),
                    color: kBarButtonDark,
                    fontSize: SF(17),
                    tooltip: T('Deep Grey'),
                  ),
                ),
                SizedBox(width: S(6)),
              ],
              if (onCopyNmc != null) ...[
                _flex(
                  _wide(
                    T('Copier'),
                    onCopyNmc!,
                    width: S(104),
                    color: kBarButtonDark,
                    tooltip: T('Contenu .nmc'),
                  ),
                ),
                SizedBox(width: S(6)),
              ],
              if (onCopyFug != null) ...[
                _flex(
                  _wide(
                    T('Position'),
                    onCopyFug!,
                    width: S(118),
                    color: kBarButtonDark,
                    tooltip: T('Copier au format .fug'),
                  ),
                ),
                SizedBox(width: S(6)),
              ],
              // LA BOULE réunit « Analyser » et « Pré-coups ». Nino : « analyse et
              // pré-coups doivent être réunis sur ce bouton, et quand on clique
              // dessus ça fait apparaître un popup qui demande si on veut aller en
              // analyse ou en pré-coups. »
              //
              // Elle est TOUJOURS là dès que l'une des deux existe : une touche qui
              // va et vient déplace ses voisines, et c'était le défaut du
              // « Pré-coups » qui disparaissait dès qu'on avait le trait.
              if (onAnalyse != null || onPremove != null) ...[
                _rondImage(
                  'assets/images/boule.webp',
                  () => unawaited(
                    ouvrirBoule(
                      context,
                      palette: palette,
                      onAnalyse: onAnalyse,
                      onPremove: onPremove,
                      raisonPremove: raisonPremove,
                    ),
                  ),
                  // L'infobulle dit ce que la touche fait vraiment : dans un
                  // mode sans pré-coups, elle ouvre l'analyse tout droit.
                  tooltip:
                      bouleSansChoix(
                        onPremove: onPremove,
                        raisonPremove: raisonPremove,
                      )
                      ? T('Analyser')
                      : T('Analyser ou préparer ses coups ?'),
                ),
                SizedBox(width: S(6)),
              ],
              if (onDeepGrey != null) ...[
                _flex(
                  _wide(
                    'Deep Grey',
                    onDeepGrey!,
                    width: S(130),
                    color: kBarButtonDeepGrey,
                  ),
                ),
                SizedBox(width: S(6)),
              ],
              if (pauseLabel == '| |')
                Tooltip(
                  message: T('Pause'),
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: Material(
                      color: kBarButtonDark,
                      borderRadius: BorderRadius.circular(S(20)),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(S(20)),
                        onTap: onPause,
                        // Deux barres dessinées plutôt que le texte « | | » : à
                        // cette taille, le glyphe débordait de la touche et
                        // tombait de travers.
                        child: const Center(
                          child: FractionallySizedBox(
                            widthFactor: 0.30,
                            heightFactor: 0.40,
                            child: CustomPaint(painter: _PausePainter()),
                          ),
                        ),
                      ),
                    ),
                  ),
                )
              else
                _round(
                  pauseLabel,
                  onPause,
                  fontSize: SF(25),
                  tooltip: T('Retour'),
                ),
            ],
          ),
        ),
      ],
    ),
  );

  /// Touche carrée portant un DESSIN plutôt qu'un libellé.
  ///
  /// Le dessin suit le thème, comme les instruments des réglages : un fichier
  /// blanc sur fond transparent, teinté ici. Il n'occupe que la part d'une
  /// lettre — c'est ce qui laisse voir le carré de la touche (cf.
  /// [PictoTouche]). Sans dessin, le libellé de secours la garde utilisable.
  Widget _rondImage(
    String asset,
    VoidCallback onPressed, {
    required String tooltip,
    String secours = '?',
  }) => Tooltip(
    message: tooltip,
    child: AspectRatio(
      aspectRatio: 1,
      child: Material(
        color: kBarButtonDark,
        borderRadius: BorderRadius.circular(S(20)),
        child: InkWell(
          borderRadius: BorderRadius.circular(S(20)),
          onTap: onPressed,
          child: Center(
            child: PictoTouche(
              asset: asset,
              couleur: palette.clair,
              secours: secours,
            ),
          ),
        ),
      ),
    ),
  );

  /// Touche ronde, carrée : la hauteur du bandeau fait sa largeur —
  /// `bind(height=lambda b, h: setattr(b, "width", h))`.
  Widget _round(
    String label,
    VoidCallback onPressed, {
    required double fontSize,
    required String tooltip,
  }) => _button(
    label,
    onPressed,
    width: null,
    color: kBarButtonDark,
    radius: S(20),
    fontSize: fontSize,
    tooltip: tooltip,
  );

  Widget _wide(
    String label,
    VoidCallback onPressed, {
    required double width,
    required Color color,
    double? fontSize,
    String? tooltip,
  }) => _button(
    label,
    onPressed,
    width: width,
    color: color,
    radius: S(14),
    fontSize: fontSize ?? SF(16),
    tooltip: tooltip,
  );

  /// [width] nul : la touche est carrée et suit la hauteur du bandeau.
  Widget _button(
    String label,
    VoidCallback onPressed, {
    required double? width,
    required Color color,
    required double radius,
    required double fontSize,
    String? tooltip,
  }) {
    final Widget inner = Material(
      color: color,
      borderRadius: BorderRadius.circular(radius),
      child: InkWell(
        borderRadius: BorderRadius.circular(radius),
        onTap: onPressed,
        child: Center(
          // Le texte RÉTRÉCIT plutôt que d'être coupé. Les touches ont une
          // largeur fixe, et un texte trop long n'y lève aucune erreur :
          // Flutter le tranche en silence. Une traduction plus longue que le
          // français — « Vorauszüge », « Premovidas » — partait donc amputée
          // sans que rien ne le dise. Elle se réduit maintenant du strict
          // nécessaire, et pas d'un point quand elle tient déjà.
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: S(6)),
            // La marge reste en dehors : seules les lettres se réduisent.
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: fontSize,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (width == null) {
      final rond = AspectRatio(aspectRatio: 1, child: inner);
      return tooltip == null ? rond : Tooltip(message: tooltip, child: rond);
    }
    final large = SizedBox(width: width, height: double.infinity, child: inner);
    return tooltip == null ? large : Tooltip(message: tooltip, child: large);
  }

  /// Une touche large, rendue réductible.
  ///
  /// Les touches larges RÉTRÉCISSENT quand la rangée est pleine, au lieu de
  /// déborder. Leur largeur est fixe et la rangée aussi : il suffit d'un
  /// bouton de plus, ou d'un écran un peu étroit, pour que la somme passe
  /// devant — mesuré à 4,3 pixels de trop sur un 21:9 le jour où la lecture
  /// automatique a ajouté le sien. `Flexible` laisse chacune prendre sa
  /// largeur tant qu'elle y tient, et la réduit à sa part sinon ; le texte,
  /// lui, est déjà protégé du rognage.
  ///
  /// L'enveloppe est posée ICI, à l'endroit où la rangée reçoit la touche, et
  /// non dans [_button] : `Flexible` n'a de sens que comme fille directe d'un
  /// `Flex`. Caché sous la pile de la pastille des messages non lus, il
  /// faisait tomber tout le bandeau.
  Widget _flex(Widget touche) => Flexible(child: touche);
}

/// Les deux barres de la pause, centrées à coup sûr.
final class _PausePainter extends CustomPainter {
  const _PausePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final barWidth = size.width * 0.32;
    final paint = Paint()..color = Colors.white;
    final radius = Radius.circular(barWidth / 2);
    for (final left in [0.0, size.width - barWidth]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, 0, barWidth, size.height),
          radius,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_PausePainter old) => false;
}
