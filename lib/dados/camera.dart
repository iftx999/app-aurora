import 'package:image_picker/image_picker.dart';

/// Câmera do celular. A foto já sai reduzida (lado maior 1.600 px, JPEG 80%; 10.9.3).
abstract interface class Camera {
  /// Caminho do arquivo tirado, ou nulo se o agente desistiu.
  Future<String?> tirar();
}

class CameraDoAparelho implements Camera {
  final _seletor = ImagePicker();

  @override
  Future<String?> tirar() async {
    final foto = await _seletor.pickImage(
      source: ImageSource.camera,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 80,
      requestFullMetadata: false,
    );
    return foto?.path;
  }
}
