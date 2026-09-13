package com.bancoxyz.bff.mobile.config;

import javax.net.ssl.HttpsURLConnection;
import javax.net.ssl.SSLContext;
import javax.net.ssl.TrustManager;
import javax.net.ssl.X509TrustManager;
import java.security.SecureRandom;
import java.security.cert.X509Certificate;

/**
 * Instala, para toda la JVM de este BFF, un SSLContext que confia en el certificado
 * autofirmado de core-service al momento de validar las conexiones HTTPS salientes.
 *
 * <p><b>Simplificacion academica deliberada (ver README, seccion "HTTPS y certificados"):</b>
 * los 4 servicios de este proyecto usan certificados autofirmados generados con
 * {@code keytool}, porque no existe una CA real ni un dominio publico para este ejercicio.
 * Un cliente HTTP que use el almacen de confianza por defecto de la JVM (cacerts) rechazaria
 * SIEMPRE esas conexiones con "PKIX path building failed", sin importar que el certificado sea
 * legitimo para este entorno cerrado (todos los servicios corren en localhost, ya sea en el
 * equipo del desarrollador o en el runner de GitHub Actions).</p>
 *
 * <p>Por eso este BFF instala un {@link X509TrustManager} permisivo para sus llamadas
 * salientes hacia core-service. En un entorno productivo real la alternativa correcta seria
 * una de estas dos: (a) usar certificados firmados por una CA publica si los servicios son
 * accesibles por internet, o (b) mantener certificados autofirmados pero importar el
 * certificado publico de core-service a un truststore especifico del BFF ("certificate
 * pinning"), en vez de confiar en cualquier certificado como se hace aqui. Ninguna de las dos
 * aplica de forma practica a este ejercicio academico: no hay CA ni dominio publico, y un
 * truststore por servicio agregaria complejidad de gestion de certificados que no aporta a los
 * objetivos de aprendizaje de esta actividad (el patron BFF en si mismo, no la gestion de PKI).</p>
 */
public final class TrustAllSslConfig {

    private TrustAllSslConfig() {
    }

    public static void instalarConfianzaLocalDeCertificadosAutofirmados() {
        try {
            TrustManager[] confiaEnTodos = new TrustManager[]{
                    new X509TrustManager() {
                        @Override
                        public X509Certificate[] getAcceptedIssuers() {
                            return new X509Certificate[0];
                        }

                        @Override
                        public void checkClientTrusted(X509Certificate[] certs, String authType) {
                        }

                        @Override
                        public void checkServerTrusted(X509Certificate[] certs, String authType) {
                        }
                    }
            };
            SSLContext sslContext = SSLContext.getInstance("TLS");
            sslContext.init(null, confiaEnTodos, new SecureRandom());
            HttpsURLConnection.setDefaultSSLSocketFactory(sslContext.getSocketFactory());
            HttpsURLConnection.setDefaultHostnameVerifier((hostname, session) -> true);
        } catch (Exception e) {
            throw new IllegalStateException(
                    "No se pudo instalar la configuracion TLS para certificados autofirmados", e);
        }
    }
}
