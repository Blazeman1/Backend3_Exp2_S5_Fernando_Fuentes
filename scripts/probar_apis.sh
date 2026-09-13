#!/usr/bin/env bash
# Ejercita, con curl, los cuatro servicios del proyecto (core-service + los tres BFF) usando
# datos reales del dataset oficial (bank_legacy_data, semana_3, cuenta_id=101 y cuenta_id=105
# tras la validacion/upsert aplicada por CargaDatosService: ver README.md, tabla de
# "Credenciales de demostracion"). Se usa como evidencia de ejecucion en
# .github/workflows/evidencia-ejecucion.yml y tambien sirve para probar el proyecto en un
# entorno local.
#
# Requiere: curl, jq. Se asume que los 4 servicios ya estan arriba en los puertos por defecto
# (core-service:8080, bff-web:8081, bff-mobile:8082, bff-atm:8083), sirviendo HTTPS con
# certificados autofirmados (ver README, seccion "HTTPS y certificados"). Por eso todas las
# llamadas usan "curl -k": aceptan el certificado autofirmado sin validarlo contra una CA,
# exactamente lo mismo que hace un navegador cuando el usuario acepta la advertencia de
# "certificado no confiable" en un entorno de desarrollo/demo.
set -euo pipefail

CORE=https://localhost:8080
WEB=https://localhost:8081
MOBILE=https://localhost:8082
ATM=https://localhost:8083
CLAVE_INTERNA="clave-interna-banco-xyz-2026"
CURL="curl -k -s"

separador() { echo; echo "=== $1 ==="; }

separador "0. core-service NO debe responder sin la clave interna (principio central del BFF)"
$CURL -o /dev/null -w "GET /internal/cuentas SIN clave -> HTTP %{http_code} (se espera 403)\n" "$CORE/internal/cuentas"

separador "0.1 core-service SI responde con la clave interna (uso exclusivo de los BFF)"
$CURL -H "X-Internal-Api-Key: $CLAVE_INTERNA" "$CORE/internal/cuentas/101" | jq .

separador "1. BFF WEB: login (cuenta 101, titular 'John Doe') y consulta completa de la cuenta"
TOKEN_WEB=$($CURL -X POST "$WEB/api/web/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"cuentaId":101,"nombre":"John Doe"}' | jq -r .token)
echo "Token web obtenido: ${TOKEN_WEB:0:24}..."

$CURL -H "Authorization: Bearer $TOKEN_WEB" "$WEB/api/web/cuentas/101" | jq .

separador "1.1 BFF WEB: historial de movimientos filtrado por tipo=deposito (interfaz compleja)"
$CURL -H "Authorization: Bearer $TOKEN_WEB" "$WEB/api/web/cuentas/101/movimientos?tipo=deposito" | jq .

separador "1.2 BFF WEB: un token valido NO puede consultar la cuenta de otra persona (autorizacion)"
$CURL -o /dev/null -w "GET /api/web/cuentas/105 con token de la cuenta 101 -> HTTP %{http_code} (se espera 403)\n" \
  -H "Authorization: Bearer $TOKEN_WEB" "$WEB/api/web/cuentas/105"

separador "2. BFF MOVIL: login (cuenta 101, PIN determinista) y resumen liviano"
TOKEN_MOBILE=$($CURL -X POST "$MOBILE/api/mobile/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"cuentaId":101,"pin":"7373"}' | jq -r .token)
echo "Token movil obtenido: ${TOKEN_MOBILE:0:24}..."

$CURL -H "Authorization: Bearer $TOKEN_MOBILE" "$MOBILE/api/mobile/cuentas/101/resumen" | jq .
echo "(Comparar el tamano de esta respuesta con la de BFF WEB del paso 1: no trae titular, edad ni historial completo)"

separador "3. BFF CAJERO: apertura de sesion con tarjeta+PIN (cuenta 105, 'Steve Rogers')"
SESION_JSON=$($CURL -X POST "$ATM/api/atm/sesion" \
  -H "Content-Type: application/json" \
  -d '{"numeroTarjeta":"4915000000000105","pin":"7665"}')
echo "$SESION_JSON" | jq .
TOKEN_ATM=$(echo "$SESION_JSON" | jq -r .sessionToken)

separador "3.1 BFF CAJERO: consulta de saldo (respuesta minima, sin nombre ni historial)"
$CURL -H "X-Atm-Session: $TOKEN_ATM" "$ATM/api/atm/cuentas/105/saldo" | jq .

separador "3.2 BFF CAJERO: retiro de \$1.000 (operacion critica)"
$CURL -X POST "$ATM/api/atm/cuentas/105/retiro" \
  -H "Content-Type: application/json" \
  -H "X-Atm-Session: $TOKEN_ATM" \
  -d '{"monto":1000}' | jq .

separador "3.3 BFF CAJERO: la sesion se invalida tras el retiro (debe fallar con HTTP 401)"
$CURL -o /dev/null -w "GET /api/atm/cuentas/105/saldo reusando la sesion ya usada -> HTTP %{http_code} (se espera 401)\n" \
  -H "X-Atm-Session: $TOKEN_ATM" "$ATM/api/atm/cuentas/105/saldo"

separador "3.4 BFF CAJERO: un retiro que excede el limite maximo por operacion debe rechazarse"
SESION_JSON_2=$($CURL -X POST "$ATM/api/atm/sesion" \
  -H "Content-Type: application/json" \
  -d '{"numeroTarjeta":"4915000000000105","pin":"7665"}')
TOKEN_ATM_3=$(echo "$SESION_JSON_2" | jq -r .sessionToken)
$CURL -X POST "$ATM/api/atm/cuentas/105/retiro" \
  -H "Content-Type: application/json" \
  -H "X-Atm-Session: $TOKEN_ATM_3" \
  -d '{"monto":999999}' | jq .

separador "4. Comparativa de optimizacion de respuestas por canal (mismo dato de origen: cuenta 101)"
echo "Se mide, con la MISMA cuenta consolidada en core-service, el tamano en bytes y el tiempo"
echo "de respuesta de la consulta representativa de cada canal: WEB (cuenta completa + historial"
echo "completo + agregados), MOVIL (resumen reducido, ultimos 3 movimientos) y CAJERO (solo saldo,"
echo "sin historial ni datos personales). Esto evidencia de forma objetiva la optimizacion de"
echo "payload exigida por canal, no solo la personalizacion funcional."

# Nueva sesion de ATM sobre la cuenta 101 (las anteriores eran sobre la 105 y ya se invalidaron/no
# aplican a esta cuenta). El PIN es el mismo generador determinista documentado en el README.
SESION_101_JSON=$($CURL -X POST "$ATM/api/atm/sesion" \
  -H "Content-Type: application/json" \
  -d '{"numeroTarjeta":"4915000000000101","pin":"7373"}')
TOKEN_ATM_101=$(echo "$SESION_101_JSON" | jq -r .sessionToken)

MEDICION_WEB=$($CURL -o /tmp/resp_web.json -w "%{size_download} %{time_total}" \
  -H "Authorization: Bearer $TOKEN_WEB" "$WEB/api/web/cuentas/101")
MEDICION_MOBILE=$($CURL -o /tmp/resp_mobile.json -w "%{size_download} %{time_total}" \
  -H "Authorization: Bearer $TOKEN_MOBILE" "$MOBILE/api/mobile/cuentas/101/resumen")
MEDICION_ATM=$($CURL -o /tmp/resp_atm.json -w "%{size_download} %{time_total}" \
  -H "X-Atm-Session: $TOKEN_ATM_101" "$ATM/api/atm/cuentas/101/saldo")

BYTES_WEB=$(echo "$MEDICION_WEB" | awk '{print $1}')
TIEMPO_WEB=$(echo "$MEDICION_WEB" | awk '{print $2}')
BYTES_MOBILE=$(echo "$MEDICION_MOBILE" | awk '{print $1}')
TIEMPO_MOBILE=$(echo "$MEDICION_MOBILE" | awk '{print $2}')
BYTES_ATM=$(echo "$MEDICION_ATM" | awk '{print $1}')
TIEMPO_ATM=$(echo "$MEDICION_ATM" | awk '{print $2}')

printf "\n%-10s %15s %15s %20s\n" "Canal" "Bytes" "Tiempo (s)" "Reduccion vs WEB"
printf "%-10s %15s %15s %20s\n" "WEB" "$BYTES_WEB" "$TIEMPO_WEB" "0% (linea base)"
awk -v b="$BYTES_MOBILE" -v bw="$BYTES_WEB" -v t="$TIEMPO_MOBILE" \
  'BEGIN{printf "%-10s %15s %15s %19.1f%%\n", "MOVIL", b, t, (1-(b/bw))*100}'
awk -v b="$BYTES_ATM" -v bw="$BYTES_WEB" -v t="$TIEMPO_ATM" \
  'BEGIN{printf "%-10s %15s %15s %19.1f%%\n", "CAJERO", b, t, (1-(b/bw))*100}'

echo
echo "=== Fin de las pruebas ==="
