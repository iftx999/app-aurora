import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/dependencias.dart';
import '../../app/tema.dart';
import '../../dados/local/arquivos_de_foto.dart';
import '../../dados/modelos/foto.dart';
import '../../nucleo/datas.dart';

/// No máximo, por ação (o mesmo limite do servidor; ADR 0053).
const maximoDeFotosPorAcao = 10;

/// Fotos de uma fase da OS (ADR 0053) ainda na tela: tiradas, guardadas cifradas e apagadas se o agente desistir.
class FotosDaAcao {
  /// Criar no `initState`: o descarte acontece no `dispose`, quando o [WidgetRef] já não pode ser usado.
  FotosDaAcao(this._ref) : _arquivos = _ref.read(arquivosDeFotoProvider);

  final WidgetRef _ref;
  final ArquivosDeFoto _arquivos;
  final lista = <FotoGuardada>[];
  bool _usadas = false;

  /// Abre a câmera; devolve se uma foto entrou.
  Future<bool> tirar() async {
    final origem = await _ref.read(cameraProvider).tirar();
    if (origem == null) return false;
    lista.add(await _arquivos.guardar(origem, _ref.read(relogioProvider)()));
    return true;
  }

  void remover(FotoGuardada foto) {
    lista.remove(foto);
    _arquivos.apagar(foto.caminho);
  }

  /// As fotos para a fila, sem parâmetro; depois disso não são mais apagadas ao sair.
  List<FotoDaOs> paraAFila(String osId) {
    _usadas = true;
    return [
      for (final f in lista)
        FotoDaOs(
          id: f.id,
          osId: osId,
          caminho: f.caminho,
          tipoMidia: f.tipoMidia,
          tamanho: f.tamanho,
          sha256: f.sha256,
          tiradaEm: f.tiradaEm,
        ),
    ];
  }

  /// Saiu sem registrar: as fotos não servem para nada.
  void descartar() {
    if (_usadas) return;
    for (final f in lista) {
      _arquivos.apagar(f.caminho);
    }
    lista.clear();
  }
}

/// Título, ajuda, miniaturas e o botão da câmera.
class CampoDeFotos extends StatelessWidget {
  const CampoDeFotos({
    super.key,
    required this.titulo,
    required this.fotos,
    required this.aoTirar,
    required this.aoRemover,
    this.ajuda,
    this.obrigatoria = true,
    this.maximo = maximoDeFotosPorAcao,
  });

  final String titulo;
  final String? ajuda;
  final bool obrigatoria;
  final int maximo;
  final List<FotoGuardada> fotos;
  final VoidCallback aoTirar;
  final void Function(FotoGuardada) aoRemover;

  @override
  Widget build(BuildContext context) {
    final c = context.cores;
    final texto = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '$titulo${obrigatoria ? ' *' : ''}',
                style: texto.labelLarge?.copyWith(color: c.textoSecundario),
              ),
            ),
            Text('${fotos.length} de até $maximo', style: TextStyle(color: c.textoSecundario)),
          ],
        ),
        if (ajuda case final a?) ...[
          const SizedBox(height: 4),
          Text(a, style: texto.bodySmall?.copyWith(color: c.textoTerciario)),
        ],
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final f in fotos) MiniaturaDeFoto(foto: f, aoTirar: () => aoRemover(f)),
            if (fotos.length < maximo)
              SizedBox(
                width: 96,
                height: 96,
                child: OutlinedButton(
                  onPressed: aoTirar,
                  style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [Icon(Icons.photo_camera_rounded), Text('Câmera')],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Miniatura de uma foto guardada, com o botão de remover.
class MiniaturaDeFoto extends ConsumerWidget {
  const MiniaturaDeFoto({super.key, required this.foto, required this.aoTirar});

  final FotoGuardada foto;
  final VoidCallback aoTirar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vazio = ColoredBox(
      color: context.cores.linha,
      child: Center(child: Text(hora(foto.tiradaEm))),
    );
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: 96,
            height: 96,
            // A foto fica criptografada no celular (ADR 0051): a miniatura é decifrada só na memória.
            child: FutureBuilder<Uint8List>(
              future: ref.read(arquivosDeFotoProvider).lerTudo(foto.caminho),
              builder: (_, lida) => lida.hasData
                  ? Image.memory(
                      lida.data!,
                      fit: BoxFit.cover,
                      cacheWidth: 192,
                      gaplessPlayback: true,
                      semanticLabel: 'Foto das ${hora(foto.tiradaEm)}',
                    )
                  : vazio,
            ),
          ),
        ),
        Positioned(
          right: 0,
          top: 0,
          child: IconButton.filledTonal(
            tooltip: 'Remover esta foto',
            icon: const Icon(Icons.close_rounded, size: 18),
            onPressed: aoTirar,
          ),
        ),
      ],
    );
  }
}
