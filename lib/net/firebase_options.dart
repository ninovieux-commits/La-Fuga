/// Identité de l'application auprès de Firebase.
///
/// Kivy ne passe pas par un `google-services.json` : il donne les quatre
/// mêmes valeurs à `FirebaseOptions.Builder` au démarrage (main.py). On fait
/// pareil — rien à générer, rien à tenir à jour en double.
///
/// Ces valeurs ne sont pas des secrets : elles voyagent dans chaque APK, et
/// n'autorisent qu'à **recevoir** des notifications. La clé qui permet d'en
/// **envoyer** vit sur le serveur, et nulle part ailleurs.
library;

import 'package:firebase_core/firebase_core.dart';

/// Les options de l'application Android `org.lafuga.lafuga`.
const FirebaseOptions kFirebaseOptions = FirebaseOptions(
  apiKey: 'AIzaSyDNW5ItqLtnErX-fwQuQq4Khz_0JPKthgk',
  appId: '1:330422289771:android:d56fd9ab3c9e32ab1cb82e',
  messagingSenderId: '330422289771',
  projectId: 'la-fuga-f9df7',
);
