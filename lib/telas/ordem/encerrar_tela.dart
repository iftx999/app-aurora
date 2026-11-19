import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/dependencias.dart';
import '../../app/tema.dart';
import '../../dados/local/arquivos_de_foto.dart';
import '../../dados/modelos/dia.dart';
import '../../dados/modelos/evento.dart';
import '../../dados/modelos/foto.dart';
import '../../execucao/formulario.dart';
import '../../jornada/controle_do_dia.dart';
import '../../nucleo/datas.dart';

/// Encerrar a OS (J9, RN-22; protótipo `Encerrar`): executada, com os parâmetros da versão do serviço, a quantidade e
/// as fotos; ou não executada, com o motivo. Nada sai do celular até "Salvar encerramento".
class EncerrarTela extends ConsumerStatefulWidget {
  const EncerrarTela({super.key, required this.osId});

  final String osId;

  @override
  ConsumerState<EncerrarTela> createState() => _EncerrarTelaState();
}

class _EncerrarTelaState extends ConsumerState<EncerrarTela> {
  bool _executada = true;
  final Map<String, Object?> _valores = {};

  /// Fotos tiradas nesta tela, por id (ainda não estão na fila).
  final Map<String, FotoGuardada> _fotos = {};
  final _quantidade = TextEditingController();
  final _observacao = TextEditingController();
  String? _motivo;
  Map<String, String> _erros = const {};
  String? _erroGeral;
  bool _salvando = false;
  bool _salvo = false;

  late final OrdemDoDia _ordem;
  late final PacoteDoDia _pacote;
  late final Formulario _formulario;
  late final ArquivosDeFoto _arquivos;

  @override
  void initState() {
    super.initState();
    _pacote = ref.read(controleDoDiaProvider).pacote!;
    _ordem = _pacote.ordens.firstWhere((o) => o.id == widget.osId);
    _formulario = Formulario(_pacote.parametros(_ordem.servicoVersaoId));
    _quantidade.text = _texto(_ordem.quantidadePrevista);
    _arquivos = ref.read(arquivosDeFotoProvider);
  }

  @override
  void dispose() {
    _quantidade.dispose();
    _observacao.dispose();
    // Saiu sem salvar: as fotos tiradas não servem para nada.
    if (!_salvo) {
      for (final f in _fotos.values) {
        _arquivos.apagar(f.caminho);
      }
    }
    super.dispose();
  }

  static String _texto(num n) => (n == n.truncate() ? n.toInt().toString() : n.toString()).replaceAll('.', ',');

  static num? _numero(String s) => num.tryParse(s.trim().replaceAll('.', '').replaceAll(',', '.'));

  void _mudar(String chave, Object? valor) => setState(() {
    _valores[chave] = valor;
    _erros = {..._erros}..remove(chave);
    _erroGeral = null;
  });

  Future<void> _tirarFoto(ParametroDoServico p) async {
    final origem = await ref.read(cameraProvider).tirar();
    if (origem == null || !mounted) return;
    final foto = await ref.read(arquivosDeFotoProvider).guardar(origem, ref.read(relogioProvider)());
    _fotos[foto.id] = foto;
    _mudar(p.chave, <String>[...((_valores[p.chave] as List?)?.cast<String>() ?? const <String>[]), foto.id]);
  }

  void _tirarDaLista(ParametroDoServico p, String id) {
    final foto = _fotos.remove(id);
    if (foto != null) ref.read(arquivosDeFotoProvider).apagar(foto.caminho);
    _mudar(p.chave, <String>[...(_valores[p.chave] as List).cast<String>()]..remove(id));
  }

  Future<void> _salvar() async {
    final controle = ref.read(controleDoDiaProvider.notifier);
    if (!_executada) {
      final motivo = _pacote.motivosPara('NAO_EXECUCAO', _ordem).where((m) => m.id == _motivo).firstOrNull;
      final obs = _observacao.text.trim();
      if (motivo == null) return setState(() => _erroGeral = 'Escolha por que não foi executada.');
      if (motivo.exigeObservacao && obs.isEmpty) {
        return setState(() => _erroGeral = 'Escreva a observação para "${motivo.nome}".');
      }
      setState(() => _salvando = true);
      await controle.registrar(
        _ordem.id,
        AcaoDeCampo.encerrar,
        resultado: 'NAO_EXECUTADA',
        motivoId: motivo.id,
        observacao: obs.isEmpty ? null : obs,
      );
      return _concluir();
    }
    final erros = _formulario.erros(_valores);
    final quantidade = _numero(_quantidade.text);
    final erroQuantidade = quantidade == null || quantidade <= 0
        ? 'Informe a quantidade executada (maior que zero).'
        : null;
    if (erros.isNotEmpty || erroQuantidade != null) {
      final primeiro = erros.keys.isEmpty
          ? null
          : _formulario.parametros.firstWhere((p) => p.chave == erros.keys.first).rotulo;
      return setState(() {
        _erros = erros;
        _erroGeral = primeiro == null ? erroQuantidade : 'Corrija "$primeiro" para encerrar.';
      });
    }
    setState(() => _salvando = true);
    final valores = _formulario.paraEnvio(_valores);
    // Só as fotos de parâmetros que valem (um parâmetro escondido pela condição não leva as suas).
    final fotos = [
      for (final MapEntry(key: chave, value: ids) in valores.entries)
        if (_formulario.parametros.firstWhere((p) => p.chave == chave).tipo == 'FOTO')
          for (final id in (ids as List).cast<String>())
            FotoDaOs(
              id: id,
              osId: _ordem.id,
              parametro: chave,
              caminho: _fotos[id]!.caminho,
              tipoMidia: _fotos[id]!.tipoMidia,
              tamanho: _fotos[id]!.tamanho,
              sha256: _fotos[id]!.sha256,
              tiradaEm: _fotos[id]!.tiradaEm,
            ),
    ];
    final obs = _observacao.text.trim();
    await controle.registrar(
      _ordem.id,
      AcaoDeCampo.encerrar,
      resultado: 'EXECUTADA',
      quantidade: quantidade,
      valores: valores,
      observacao: obs.isEmpty ? null : obs,
      fotos: fotos,
    );
    // As que ficaram de fora (parâmetro escondido) saem do celular.
    final usadas = fotos.map((f) => f.id).toSet();
    _fotos.removeWhere((id, f) {
      if (!usadas.contains(id)) ref.read(arquivosDeFotoProvider).apagar(f.caminho);
      return !usadas.contains(id);
    });
    _concluir();
  }

  void _concluir() {
    final registrado = ref.read(controleDoDiaProvider).pacote?.ordens.where((o) => o.id == _ordem.id).firstOrNull;
    if (registrado?.status != StatusOrdem.encerrada) {
      // O controle recusou (situação mudou); o erro aparece na tela da OS.
      setState(() => _salvando = false);
      return;
    }
    _salvo = true;
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cores;
    final visiveis = _formulario.visiveis(_valores);
    return Scaffold(
      appBar: AppBar(title: Text('Encerrar OS ${_ordem.numero}')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('Executada'), icon: Icon(Icons.check_rounded)),
              ButtonSegment(value: false, label: Text('Não executada'), icon: Icon(Icons.block_rounded)),
            ],
            selected: {_executada},
            showSelectedIcon: false,
            style: const ButtonStyle(minimumSize: WidgetStatePropertyAll(Size.fromHeight(56))),
            onSelectionChanged: (s) => setState(() {
              _executada = s.single;
              _erroGeral = null;
            }),
          ),
          const SizedBox(height: 20),
          if (_executada) ...[
            for (final p in visiveis)
              Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: _CampoDoParametro(
                  parametro: p,
                  valor: _valores[p.chave],
                  erro: _erros[p.chave],
                  fotos: _fotos,
                  aoMudar: (v) => _mudar(p.chave, v),
                  aoTirarFoto: () => _tirarFoto(p),
                  aoTirarDaLista: (id) => _tirarDaLista(p, id),
                ),
              ),
            TextField(
              controller: _quantidade,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Quantidade executada *',
                suffixText: _ordem.unidadeMedida,
                helperText: 'Previsto: ${_texto(_ordem.quantidadePrevista)} ${_ordem.unidadeMedida}',
              ),
            ),
          ] else
            RadioGroup<String>(
              groupValue: _motivo,
              onChanged: (v) => setState(() {
                _motivo = v;
                _erroGeral = null;
              }),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Por que não foi executada?', style: Theme.of(context).textTheme.titleMedium),
                  for (final m in _pacote.motivosPara('NAO_EXECUCAO', _ordem))
                    RadioListTile<String>(
                      value: m.id,
                      title: Text(m.nome),
                      contentPadding: EdgeInsets.zero,
                      minTileHeight: 56,
                    ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          TextField(
            controller: _observacao,
            maxLength: 500,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(labelText: 'Observação'),
          ),
          if (_erroGeral case final e?)
            Semantics(
              liveRegion: true,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  e,
                  style: TextStyle(color: c.perigo, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _salvando ? null : _salvar,
            child: Text(_salvando ? 'Salvando…' : 'Salvar encerramento'),
          ),
          const SizedBox(height: 8),
          Text(
            'Fica guardado no celular e vai para o servidor assim que houver sinal.',
            textAlign: TextAlign.center,
            style: TextStyle(color: c.textoTerciario),
          ),
        ],
      ),
    );
  }
}

/// Um parâmetro do serviço, no controle certo para o tipo.
class _CampoDoParametro extends StatelessWidget {
  const _CampoDoParametro({
    required this.parametro,
    required this.valor,
    required this.erro,
    required this.fotos,
    required this.aoMudar,
    required this.aoTirarFoto,
    required this.aoTirarDaLista,
  });

  final ParametroDoServico parametro;
  final Object? valor;
  final String? erro;
  final Map<String, FotoGuardada> fotos;
  final ValueChanged<Object?> aoMudar;
  final VoidCallback aoTirarFoto;
  final ValueChanged<String> aoTirarDaLista;

  @override
  Widget build(BuildContext context) {
    final c = context.cores;
    final p = parametro;
    final rotulo = '${p.rotulo}${p.obrigatorio ? ' *' : ''}';
    final ajuda = [?p.ajuda, if (Formulario.faixa(p) case final f when f.isNotEmpty && p.tipo != 'FOTO') f].join(' · ');
    Widget titulo() => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(rotulo, style: Theme.of(context).textTheme.titleMedium),
    );
    Widget? rodape() => erro == null
        ? (ajuda.isEmpty ? null : Text(ajuda, style: TextStyle(color: c.textoSecundario)))
        : Text(
            erro!,
            style: TextStyle(color: c.perigo, fontWeight: FontWeight.w600),
          );

    switch (p.tipo) {
      case 'INTEIRO' || 'DECIMAL' || 'TEXTO':
        final numerico = p.tipo != 'TEXTO';
        return TextFormField(
          initialValue: valor == null ? null : (valor is num ? '$valor'.replaceAll('.', ',') : '$valor'),
          keyboardType: numerico
              ? TextInputType.numberWithOptions(decimal: p.tipo == 'DECIMAL', signed: (p.minimo ?? 0) < 0)
              : TextInputType.multiline,
          maxLines: numerico ? 1 : 4,
          minLines: 1,
          maxLength: numerico ? null : (p.maximo?.toInt() ?? Formulario.maximoDeTexto),
          decoration: InputDecoration(
            labelText: rotulo,
            suffixText: p.unidade,
            helperText: erro == null && ajuda.isNotEmpty ? ajuda : null,
            errorText: erro,
          ),
          onChanged: (t) =>
              aoMudar(numerico ? (t.trim().isEmpty ? null : (num.tryParse(t.trim().replaceAll(',', '.')) ?? t)) : t),
        );
      case 'SIM_NAO':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            titulo(),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('Sim')),
                ButtonSegment(value: false, label: Text('Não')),
              ],
              selected: {if (valor is bool) valor as bool},
              emptySelectionAllowed: true,
              showSelectedIcon: false,
              style: const ButtonStyle(minimumSize: WidgetStatePropertyAll(Size(120, 56))),
              onSelectionChanged: (s) => aoMudar(s.isEmpty ? null : s.single),
            ),
            ?rodape(),
          ],
        );
      case 'LISTA' || 'LISTA_MULTIPLA':
        final multipla = p.tipo == 'LISTA_MULTIPLA';
        final escolhidas = multipla
            ? ((valor as List?)?.cast<String>() ?? const <String>[])
            : [if (valor is String) valor as String];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            titulo(),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final o in p.opcoes)
                  FilterChip(
                    label: Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Text(o)),
                    selected: escolhidas.contains(o),
                    showCheckmark: multipla,
                    onSelected: (marcar) => aoMudar(
                      multipla
                          ? (marcar ? [...escolhidas, o] : [...escolhidas]
                              ..remove(o))
                          : (marcar ? o : null),
                    ),
                  ),
              ],
            ),
            ?rodape(),
          ],
        );
      case 'DATA_HORA':
        final d = valor as DateTime?;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            titulo(),
            OutlinedButton.icon(
              icon: const Icon(Icons.event_rounded),
              label: Text(d == null ? 'Escolher data e hora' : '${diaCurto(d)} às ${hora(d)}'),
              onPressed: () async {
                final agora = DateTime.now();
                final dia = await showDatePicker(
                  context: context,
                  initialDate: d ?? agora,
                  firstDate: agora.subtract(const Duration(days: 365)),
                  lastDate: agora.add(const Duration(days: 365)),
                );
                if (dia == null || !context.mounted) return;
                final h = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(d ?? agora));
                if (h == null) return;
                aoMudar(DateTime(dia.year, dia.month, dia.day, h.hour, h.minute));
              },
            ),
            ?rodape(),
          ],
        );
      case 'FOTO':
        final ids = (valor as List?)?.cast<String>() ?? const <String>[];
        final min = p.minimo?.toInt() ?? (p.obrigatorio ? 1 : 0);
        final max = p.maximo?.toInt();
        final conta = '${ids.length} de ${max == null ? 'ao menos $min' : '$min a $max'}';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: titulo()),
                Text(conta, style: TextStyle(color: c.textoSecundario)),
              ],
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final id in ids)
                  if (fotos[id] case final f?) _Miniatura(foto: f, aoTirar: () => aoTirarDaLista(id)),
                if (max == null || ids.length < max)
                  SizedBox(
                    width: 96,
                    height: 96,
                    child: OutlinedButton(
                      onPressed: aoTirarFoto,
                      style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [Icon(Icons.photo_camera_rounded), Text('Câmera')],
                      ),
                    ),
                  ),
              ],
            ),
            ?rodape(),
          ],
        );
    }
    return Text('${p.rotulo}: tipo ${p.tipo} não suportado nesta versão do app.');
  }
}

class _Miniatura extends StatelessWidget {
  const _Miniatura({required this.foto, required this.aoTirar});

  final FotoGuardada foto;
  final VoidCallback aoTirar;

  @override
  Widget build(BuildContext context) {
    final arquivo = File(foto.caminho);
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: 96,
            height: 96,
            child: arquivo.existsSync()
                ? Image.file(
                    arquivo,
                    fit: BoxFit.cover,
                    cacheWidth: 192,
                    semanticLabel: 'Foto das ${hora(foto.tiradaEm)}',
                  )
                : ColoredBox(
                    color: context.cores.linha,
                    child: Center(child: Text(hora(foto.tiradaEm))),
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
