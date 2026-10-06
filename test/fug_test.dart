/// Le format `.fug` : une position, pas une partie.
///
/// Nino : « Le nmc décrit une partie depuis une position de départ connue.
/// Ici, il nous faut un type de fichier qui décrit une position. […] h=héritier
/// n=nurse c=chevalier g=garde s=soldat, quand la pièce est noire elle est en
/// majuscule, blanche en minuscule. -=case vide. On lit sans décrire les
/// cases, en partant de do1 jusqu'à si1, puis do2 jusqu'à si2 et ainsi de
/// suite jusque si8. »
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lafuga/engine/board.dart';
import 'package:lafuga/engine/fug.dart';
import 'package:lafuga/engine/piece.dart';

void main() {
  group('Écrire une position', () {
    test('la position standard tient en huit rangées de sept', () {
      final texte = fugEcrire(Board.initial(), Camp.blanc);
      final lignes = texte.split('\n');
      expect(lignes.first, 'B', reason: 'les Blancs sont au trait');
      expect(lignes.length, kRows + 1);
      for (final l in lignes.skip(1)) {
        expect(l.length, kCols, reason: 'sept colonnes, une par note : « $l »');
      }
    });

    test('les Noirs au trait s écrivent N', () {
      expect(fugEcrire(Board.initial(), Camp.noir).split('\n').first, 'N');
    });

    test('minuscule pour les Blancs, majuscule pour les Noirs', () {
      final b = Board.empty();
      b.set(0, 0, Piece.blancHeritier);
      b.set(0, 7, Piece.noirHeritier);
      final lignes = fugEcrire(b, Camp.blanc).split('\n');
      expect(lignes[1][0], 'h', reason: 'do1 : un Héritier blanc');
      expect(lignes[8][0], 'H', reason: 'do8 : un Héritier noir');
    });

    test('la première rangée écrite est do1, pas do8', () {
      final b = Board.empty();
      b.set(0, 0, Piece.blancSoldat);
      final lignes = fugEcrire(b, Camp.blanc).split('\n');
      expect(lignes[1], 's------', reason: 'do1 ouvre le texte');
      expect(lignes[8], '-------');
    });

    test('une case vide s écrit -', () {
      expect(fugEcrire(Board.empty(), Camp.blanc).split('\n')[1], '-------');
    });
  });

  group('Relire ce qu on a écrit', () {
    test('la position standard revient à l identique', () {
      final depart = Board.initial();
      final relu = fugLire(fugEcrire(depart, Camp.blanc));
      expect(relu.erreur, isNull);
      expect(
        relu.position!.board.positionKey(Camp.blanc),
        depart.positionKey(Camp.blanc),
        reason: 'l aller-retour a changé la position',
      );
      expect(relu.position!.turn, Camp.blanc);
    });

    test('chaque pièce de chaque camp survit à l aller-retour', () {
      final b = Board.empty();
      var c = 0;
      for (final type in PieceType.values) {
        b.set(c, 0, Piece.of(type, Camp.blanc));
        b.set(c, 7, Piece.of(type, Camp.noir));
        c++;
      }
      final relu = fugLire(fugEcrire(b, Camp.noir)).position!;
      for (var i = 0; i < PieceType.values.length; i++) {
        expect(relu.board.at(i, 0), Piece.of(PieceType.values[i], Camp.blanc));
        expect(relu.board.at(i, 7), Piece.of(PieceType.values[i], Camp.noir));
      }
      expect(relu.turn, Camp.noir);
    });

    test('on tolère les blancs autour sans changer le sens', () {
      final propre = fugEcrire(Board.initial(), Camp.blanc);
      final sale = '\n  $propre  \n\n'.replaceAll('\n', '\r\n');
      final relu = fugLire(sale);
      expect(relu.erreur, isNull);
      expect(
        relu.position!.board.positionKey(Camp.blanc),
        Board.initial().positionKey(Camp.blanc),
      );
    });
  });

  group('Ce qui n est pas lisible est refusé, et dit où', () {
    test('un texte vide', () {
      expect(fugLire('').erreur, FugErreur.vide);
      expect(fugLire('   \n\n ').erreur, FugErreur.vide);
    });

    test('un trait inconnu', () {
      final mauvais = fugLire('X\n${'-------\n' * 8}');
      expect(mauvais.erreur, FugErreur.traitInconnu);
      expect(mauvais.ligne, 1);
    });

    test('sept rangées au lieu de huit', () {
      expect(fugLire('B\n${'-------\n' * 7}').erreur, FugErreur.rangees);
      expect(fugLire('B\n${'-------\n' * 9}').erreur, FugErreur.rangees);
    });

    test('une rangée trop courte, et on dit laquelle', () {
      final mauvais = fugLire('B\n-------\n------\n${'-------\n' * 6}');
      expect(mauvais.erreur, FugErreur.colonnes);
      expect(mauvais.ligne, 3, reason: 'la deuxième rangée, ligne 3 du texte');
    });

    test('une lettre qui ne veut rien dire', () {
      final mauvais = fugLire('B\n-------\n--x----\n${'-------\n' * 6}');
      expect(mauvais.erreur, FugErreur.lettre);
      expect(mauvais.ligne, 3);
    });

    test('rien de tout cela ne fait tomber', () {
      for (final texte in ['é', 'B', 'B\n', '\u0000', 'B\n' * 40]) {
        expect(() => fugLire(texte), returnsNormally, reason: texte);
      }
    });
  });

  group('Une position peut-elle servir de départ ?', () {
    /// Un camp avec son Héritier et deux carrées qui se touchent.
    void poser(Board b, Camp camp, int row) {
      b.set(0, row, Piece.of(PieceType.heritier, camp));
      b.set(2, row, Piece.of(PieceType.soldat, camp));
      b.set(3, row, Piece.of(PieceType.garde, camp));
    }

    test('la position standard convient', () {
      expect(fugRefus(Board.initial()), isNull);
    });

    test('il faut un Héritier par camp, ni plus ni moins', () {
      final b = Board.empty();
      poser(b, Camp.blanc, 0);
      poser(b, Camp.noir, 7);
      expect(fugRefus(b), isNull);

      final sans = Board.empty();
      poser(sans, Camp.blanc, 0);
      sans.set(2, 7, Piece.noirSoldat);
      sans.set(3, 7, Piece.noirGarde);
      expect(
        fugRefus(sans),
        FugRefus.heritier,
        reason: 'les Noirs n ont pas d Héritier',
      );

      final deux = Board.empty();
      poser(deux, Camp.blanc, 0);
      poser(deux, Camp.noir, 7);
      deux.set(5, 7, Piece.noirHeritier);
      expect(
        fugRefus(deux),
        FugRefus.heritier,
        reason: 'deux Héritiers noirs, c est un de trop',
      );
    });

    test('chaque camp doit avoir une carrée qui peut bouger', () {
      // Les Noirs n'ont qu'une seule carrée, sans voisine : elle est figée.
      final b = Board.empty();
      poser(b, Camp.blanc, 0);
      b.set(0, 7, Piece.noirHeritier);
      b.set(2, 7, Piece.noirSoldat);
      expect(fugRefus(b), FugRefus.carreesBloquees);

      // On lui donne une voisine : la position redevient jouable.
      b.set(3, 7, Piece.noirGarde);
      expect(fugRefus(b), isNull);
    });

    test('une carrée adossée à une carrée ADVERSE peut bouger', () {
      // La règle dit « une autre carrée, n importe quel camp ».
      final b = Board.empty();
      b.set(0, 0, Piece.blancHeritier);
      b.set(0, 7, Piece.noirHeritier);
      b.set(3, 3, Piece.blancSoldat);
      b.set(3, 4, Piece.noirSoldat);
      expect(fugRefus(b), isNull);
    });

    test('dix Gardes d un côté, c est permis', () {
      final b = Board.empty();
      b.set(0, 0, Piece.blancHeritier);
      b.set(0, 7, Piece.noirHeritier);
      b.set(1, 7, Piece.noirSoldat);
      b.set(2, 7, Piece.noirGarde);
      var poses = 0;
      for (var r = 2; r < 5 && poses < 10; r++) {
        for (var c = 0; c < kCols && poses < 10; c++) {
          b.set(c, r, Piece.blancGarde);
          poses++;
        }
      }
      expect(poses, 10);
      expect(
        fugRefus(b),
        isNull,
        reason: 'rien n interdit d entasser des pièces',
      );
    });

    test('compter les Héritiers d un camp', () {
      expect(fugHeritiers(Board.initial(), Camp.blanc), 1);
      expect(fugHeritiers(Board.empty(), Camp.noir), 0);
    });
  });

  group('La forme d en-tête, sur une ligne', () {
    test('aller et retour', () {
      final fug = fugEcrire(Board.initial(), Camp.noir);
      final ligne = fugEnUneLigne(fug);
      expect(
        ligne.contains('\n'),
        isFalse,
        reason: 'un en-tête .nmc tient sur une ligne',
      );
      expect(ligne.split('/').length, kRows + 1);
      expect(fugDepuisUneLigne(ligne), fug);
      expect(
        fugLire(
          fugDepuisUneLigne(ligne),
        ).position!.board.positionKey(Camp.blanc),
        Board.initial().positionKey(Camp.blanc),
      );
    });

    test('un texte illisible ne donne pas de ligne', () {
      expect(fugEnUneLigne('n importe quoi'), '');
    });
  });
}
