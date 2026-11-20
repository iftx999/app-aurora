package dev.aurora.campo

import android.Manifest
import android.content.Context
import android.content.RestrictionsManager
import android.content.pm.PackageManager
import android.os.BatteryManager
import android.os.Build
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FlutterFragmentActivity: exigida pela biometria (local_auth).
class MainActivity : FlutterFragmentActivity() {

    // Bateria e permissão de notificação sem plugin (o battery_plus traz dependências MPL para o Linux).
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dev.aurora.campo/aparelho")
            .setMethodCallHandler { chamada, resposta ->
                when (chamada.method) {
                    "bateria" -> {
                        val bateria = getSystemService(BATTERY_SERVICE) as BatteryManager
                        resposta.success(
                            mapOf(
                                "nivel" to bateria.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY),
                                "carregando" to bateria.isCharging,
                            )
                        )
                    }
                    "pedirNotificacoes" -> {
                        // Android 13+: sem a permissão, a notificação da jornada (RN-27) não aparece.
                        val falta = Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
                            PackageManager.PERMISSION_GRANTED
                        if (falta) requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 7301)
                        resposta.success(!falta)
                    }
                    "configuracaoGerenciada" -> {
                        // Android Enterprise: só os textos definidos pelo MDM (vazio quando não há MDM).
                        val restricoes = (getSystemService(Context.RESTRICTIONS_SERVICE) as RestrictionsManager)
                            .applicationRestrictions
                        resposta.success(
                            restricoes.keySet()
                                .mapNotNull { chave -> restricoes.getString(chave)?.let { chave to it } }
                                .toMap()
                        )
                    }
                    else -> resposta.notImplemented()
                }
            }
    }
}
