/// Messagerie — modèles des routes `/list_conversations`,
/// `/list_conversation`, `/send_message` et `/mark_read`.
library;

/// Une conversation dans la liste : avec qui, le dernier mot, les non-lus.
final class Conversation {
  const Conversation({
    required this.pseudo,
    this.lastText = '',
    this.unread = 0,
    this.lastFromMe = false,
    this.photo = '',
  });

  final String pseudo;
  final String lastText;
  final int unread;

  /// Vrai si le dernier message est de moi : l'aperçu s'écrit « Vous : … ».
  final bool lastFromMe;

  final String photo;

  static Conversation fromJson(Map<String, dynamic> j) => Conversation(
    pseudo: '${j['pseudo'] ?? '?'}',
    lastText: '${j['last_text'] ?? ''}',
    unread: switch (j['unread']) {
      final int n => n,
      final num n => n.toInt(),
      _ => 0,
    },
    lastFromMe: j['last_de_moi'] == true,
    photo: '${j['photo'] ?? ''}',
  );
}

/// Un message d'une conversation.
final class ChatMessage {
  const ChatMessage({required this.text, required this.fromMe, this.pending});

  final String text;
  final bool fromMe;

  /// Message affiché avant la réponse du serveur : `true` tant qu'on attend,
  /// `false` si l'envoi a échoué. `null` pour un message confirmé.
  final bool? pending;

  static ChatMessage fromJson(Map<String, dynamic> j) =>
      ChatMessage(text: '${j['texte'] ?? ''}', fromMe: j['de_moi'] == true);
}

/// Photo à utiliser pour l'avatar d'un joueur — portage d'`avatar_photo_for`.
///
/// Deep Grey a la sienne ; pour les autres, la photo donnée (vide = pièce par
/// défaut au rendu).
String avatarPhotoFor(String? pseudo, [String photo = '']) {
  final name = (pseudo ?? '').trim().toLowerCase();
  return (name == 'deep grey' || name == 'deepgrey') ? 'deepgrey' : photo;
}
