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
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
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
                    // ADR 0051: fotos criptografadas à parte (AES-256-GCM, chave no Android Keystore).
                    "cifrar" -> {
                        val cifra = Cipher.getInstance(TRANSFORMACAO)
                        cifra.init(Cipher.ENCRYPT_MODE, chaveDasFotos())
                        resposta.success(cifra.iv + cifra.doFinal(chamada.arguments as ByteArray))
                    }
                    "decifrar" -> {
                        val dados = chamada.arguments as ByteArray
                        try {
                            val cifra = Cipher.getInstance(TRANSFORMACAO)
                            cifra.init(
                                Cipher.DECRYPT_MODE,
                                chaveDasFotos(),
                                GCMParameterSpec(128, dados, 0, TAMANHO_DO_IV),
                            )
                            resposta.success(cifra.doFinal(dados, TAMANHO_DO_IV, dados.size - TAMANHO_DO_IV))
                        } catch (erro: Exception) {
                            resposta.error("FOTO_ILEGIVEL", erro.message, null)
                        }
                    }
                    "apagarChaveDasFotos" -> {
                        KeyStore.getInstance(KEYSTORE).apply { load(null) }.deleteEntry(CHAVE_DAS_FOTOS)
                        resposta.success(null)
                    }
                    "avisar" -> {
                        // Nova ordem das OS para confirmar (ADR 0050): toque abre o app na tela Hoje.
                        avisar(
                            chamada.argument<Int>("id") ?: 1,
                            chamada.argument<String>("titulo") ?: "",
                            chamada.argument<String>("texto") ?: "",
                            chamada.argument<String>("canal") == "emergencial",
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

    private fun avisar(id: Int, titulo: String, texto: String, emergencial: Boolean) {
        val gerenciador = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        if (!gerenciador.areNotificationsEnabled()) return
        val canal = if (emergencial) CANAL_EMERGENCIAL else CANAL_DA_ROTA
        gerenciador.createNotificationChannel(
            NotificationChannel(CANAL_DA_ROTA, "Rota do dia", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Nova ordem das OS para conferir e confirmar"
            }
        )
        // ADR 0051: emergencial toca e vibra forte (o agente pode ajustar o som nas configurações do Android).
        gerenciador.createNotificationChannel(
            NotificationChannel(CANAL_EMERGENCIAL, "OS emergencial", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "OS emergencial nova na programação da equipe"
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 700, 250, 700, 250, 700)
                enableLights(true)
            }
        )
        val abrir = PendingIntent.getActivity(
            this,
            id,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val aviso = android.app.Notification.Builder(this, canal)
            .setSmallIcon(R.drawable.ic_aviso_rota)
            .setContentTitle(titulo)
            .setContentText(texto)
            .setStyle(android.app.Notification.BigTextStyle().bigText(texto))
            .setContentIntent(abrir)
            .setAutoCancel(true)
            .setCategory(
                if (emergencial) android.app.Notification.CATEGORY_ALARM
                else android.app.Notification.CATEGORY_REMINDER
            )
            .build()
        gerenciador.notify(id, aviso)
    }

    /** Chave AES-256 do Keystore (criada no primeiro uso; nunca sai do aparelho). */
    private fun chaveDasFotos(): SecretKey {
        val keystore = KeyStore.getInstance(KEYSTORE).apply { load(null) }
        (keystore.getKey(CHAVE_DAS_FOTOS, null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE).run {
            init(
                KeyGenParameterSpec.Builder(
                    CHAVE_DAS_FOTOS,
                    KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
                )
                    .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                    .setKeySize(256)
                    .build()
            )
            generateKey()
        }
    }

    private companion object {
        const val CANAL_DA_ROTA = "rota"
        const val CANAL_EMERGENCIAL = "emergencial"
        const val KEYSTORE = "AndroidKeyStore"
        const val CHAVE_DAS_FOTOS = "aurora_fotos"
        const val TRANSFORMACAO = "AES/GCM/NoPadding"
        const val TAMANHO_DO_IV = 12
    }
}
