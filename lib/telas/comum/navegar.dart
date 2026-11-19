import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../dados/modelos/dia.dart';

/// Abre o app de navegação escolhido no celular (Waze, Google Maps) no destino da OS.
Future<void> navegar(BuildContext context, OrdemDoDia ordem) async {
  final lat = ordem.latitude, lon = ordem.longitude;
  final destino = lat != null && lon != null
      ? Uri.parse('geo:$lat,$lon?q=$lat,$lon')
      : Uri(scheme: 'geo', path: '0,0', queryParameters: {'q': ordem.endereco});
  final mensageiro = ScaffoldMessenger.of(context);
  if (!await launchUrl(destino, mode: LaunchMode.externalApplication)) {
    mensageiro.showSnackBar(const SnackBar(content: Text('Nenhum app de mapa instalado.')));
  }
}
