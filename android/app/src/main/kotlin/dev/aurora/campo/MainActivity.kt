package dev.aurora.campo

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
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
                    "avisar" -> {
                        // Nova ordem das OS para confirmar (ADR 0050): toque abre o app na tela Hoje.
                        avisar(
                            chamada.argument<Int>("id") ?: 1,
                            chamada.argument<String>("titulo") ?: "",
                            chamada.argument<String>("texto") ?: "",
                        )
                        resposta.success(null)
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

    private fun avisar(id: Int, titulo: String, texto: String) {
        val gerenciador = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        if (!gerenciador.areNotificationsEnabled()) return
        gerenciador.createNotificationChannel(
            NotificationChannel(CANAL_DA_ROTA, "Rota do dia", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Nova ordem das OS para conferir e confirmar"
            }
        )
        val abrir = PendingIntent.getActivity(
            this,
            id,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val aviso = android.app.Notification.Builder(this, CANAL_DA_ROTA)
            .setSmallIcon(R.drawable.ic_aviso_rota)
            .setContentTitle(titulo)
            .setContentText(texto)
            .setStyle(android.app.Notification.BigTextStyle().bigText(texto))
            .setContentIntent(abrir)
            .setAutoCancel(true)
            .setCategory(android.app.Notification.CATEGORY_REMINDER)
            .build()
        gerenciador.notify(id, aviso)
    }

    private companion object {
        const val CANAL_DA_ROTA = "rota"
    }
}
