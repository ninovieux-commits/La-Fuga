// Le démarrage du site, écrit à la main plutôt que laissé au modèle.
//
// CANVASKIT EST SERVI PAR NOUS, et non par gstatic.com. Par défaut, Flutter
// va chercher son moteur de dessin chez Google à chaque chargement : le site
// ne s'afficherait pas derrière un pare-feu qui bloque ce domaine, et chaque
// visite s'y annoncerait. `flutter build web` copie de toute façon le moteur
// dans `canvaskit/` — autant le servir.
//
// Les trois accolades doubles sont remplies par `flutter build web` : le
// chargeur, la configuration de la compilation, et le numéro du cache.
{{flutter_js}}
{{flutter_build_config}}

_flutter.loader.load({
  config: { canvasKitBaseUrl: "canvaskit/" },
  serviceWorkerSettings: {
    serviceWorkerVersion: {{flutter_service_worker_version}},
  },
});
