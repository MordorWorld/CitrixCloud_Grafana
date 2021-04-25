#!/bin/bash
##########################################################################################
##      ===========================================================================
##       Created on:    03/11/2021
##       Created by:    GrumpyGon & Bujarron
##       Organization:  www.mordor.world
##       Version:   02.06
##      ===========================================================================
##      .DESCRIPTION
##         Script de recolección de Citrix Cloud con OData diseñado para telegraf e influxdb
##
##      .REQUERIMENTS
##   · Tener instalado snap "snap install jq"
##   · Una cuenta de Client API de nuestro Citrix Cloud
##   · Sera necesario tener permisos para la ejecución de los mismos
##         vi /etc/systemd/system/multi-user.target.wants/telegraf.service
##                Cambiar el usuario telegraf --> root
##          systemctl daemon-reload
##          service telegraf restart
##       For me the fix was changing /etc/passwd telegraf user shell from /bin/false to /bin/bash
##
##  .TELEGRAF Config
##   Fichero de configuración para telegraf
##    [[inputs.exec]]
##     commands = ["/etc/telegraf/CitrixCloud/File-IOPs.sh" ]
##     name_override = "Odata_ResourceGlobal"
##     timeout = "60s"
##     interval = "3600s"
##     data_format = "json"
##     tag_keys = ["MachineId","Machine_DnsName"]
##     json_time_key = "CollectedDate"
##     json_time_format = "2006-01-02T15:04:05Z"
##     json_string_fields = ["*"]
##
######################################################################################################
########################################CLIENT API####################################################
ClientName="Nombre Cliente"
CLIENTID="Cliente ID"   								##Rellenar por Cliente
CLIENTSECRET="Secret Key"       						##Rellenar Secret
CustomerID="Customer ID"             					##Codigo Cliente
Capture="IOPs-Latency"          								
Retry=3              									##Reintentos de Conexion Captura
FilePath="/etc/telegraf/CitrixCloud"     				#Path de Scripts
SiteIDFile="$FilePath/0-SiteID.$ClientName"       		#Fichero de SiteID
TokenFile="$FilePath/0-Token.$ClientName"      			#Fichero de Token
LogFile="/var/log/telegraf/$ClientName-CitrixCloud.log" #Fichero de Log
LogSize=1000000           								##Tamaño MAX. fichero logs
Time_capture="-180 minutes"
#################################################URLs#################################################
SiteMe="https://api.cloud.com/cvadapis/me"
trustUrl="https://api.cloud.com/cctrustoauth2/root/tokens/clients"
HeaderCustomerID="Citrix-CustomerId: $CustomerID"
j="Accept: application/json"
##############################################FUNCTIONS###############################################
function Write-Log(){ #Function Write File Logs
        savetime=$(date +%x-%X)
        if [ $(wc -c "$LogFile" | awk '{print $1}') -gt $LogSize ]
        then
                [ ! -f "$LogFile+1" ]  || rm "$LogFile+1"
                mv "$LogFile" "$LogFile+1"
        fi
        echo "$savetime - $Capture - $1" >> "$LogFile"
}

function Get_Token () {
        Write-Log "INFO - Generando Token"
        token=$(curl -s ${trustUrl} -d "grant_type=client_credentials&client_id=${CLIENTID}&client_secret=${CLIENTSECRET}" | jq -r .access_token)
        if [ "$?" -ne 0 ]; then
                Write-Log "ERRO - No se pudo generar el token - Authorization failed"
                exit
        fi
        echo "$token" > "$TokenFile"
}

function Get_SiteID () {
        Write-Log "INFO - Generando SiteID"
        Site=$(curl -s ${SiteMe} -H "${j}" -H "${1}" -H "${HeaderCustomerID}" | jq -r .Customers[0].Sites[0].Id)
        if [ "$Site" = "null" ]
        then
    Write-Log "ERRO - Al solicitar SiteID"
                Get_Token
                exit
        fi
        echo "$Site" > "$SiteIDFile"
}

function Get_Code () {
 URLCode=$(echo "$1" | tail -n1 )
 case $URLCode in
                "200")
                        ;;
                "400")
                        Write-Log "ERRO - URL Incorrect"
                        exit
                        ;;
                "401")
                        Get_Token
                        exit
                        ;;
                "404")
                        Write-Log "ERRO - Error de Page"
                        exit
                        ;;
                "503" | "429")
                        counter=0
                        while [ $URLCode != "200" ] && [ $counter -lt $Retry ]; do
                                Write-Log "RETR - Intento $counter URL not access $URLCode"
                                Info=$(curl -s --write-out "\n%{http_code}\n" ${2} -H "${j}" -H "${1}" -H "${HeaderCustomerID}" )
                                URLCode=$(echo "$Info" | tail -n1 )
                                counter=$[$counter +1]
                                sleep 5
                        done
                        if [ $URLCode != "200" ]
                        then
                                Write-Log "RETR - No se pudo contactar Error $URLCode"
                                exit
                        fi
                        ;;
                *)
                        Write-Log "ERRO - Unknown $URLCode"
                        exit
                        ;;
    esac
}

function Get_Info () {
    Write-Log "INFO - Generando OData Json"
    timeconsulta=$(date +%Y-%m-%dT%T --date="$Time_capture")            #Tiempo de Captura
    timeconsulta=$(echo $timeconsulta | sed -r 's/[:]+/%3A/g' )        #Cambia los : por -
    select='?$expand=Machine($select=DnsName)&'                        #expandir a otra tabla para capturar datos
    filter='$apply=filter%28CollectedDate%20ge%20'$timeconsulta'Z%29&' #Filtro de fechas para la captura
	UrlGWEDP="https://api-ap-s.cloud.com/monitorodata/MachineMetric$select$filter"
    Info=$(curl -s --write-out "\n%{http_code}\n" ${UrlGWEDP} -H "${j}" -H "${1}" -H "${HeaderCustomerID}" )
    Get_Code "$Info" "$UrlGWEDP" 										#Ver codigos de error
    Info=$(echo "$Info" | sed '$d' )     								#Borra la ultima linea Error Code
    Info=$(echo "$Info" | jq -r '.[]' )									#Cambiar formato a json
    NextLink=$(echo "$Info" | tail -n1 )								#Capturar ultima linea
    Info=$(echo "$Info" | sed '/^http/d') 								#Delete all line with "http"
    Info=$(echo "$Info" | sed '$d' ) 									#Borra la ultima linea (contiene "]")
    FullInfo=$(echo "$Info")
    while [ "$NextLink" != ']' ] ; do
		FullInfo=$(echo "$FullInfo,")									#Agregar "," al final
        Info=$(curl -s --write-out "\n%{http_code}\n" ${NextLink} -H "${j}" -H "${1}" -H "${HeaderCustomerID}" )
        Get_Code "$Info" "$NextLink" 									#Ver codigos de error
        Info=$(echo "$Info" | sed '$d' )     							#Borra la ultima linea Error Code
        Info=$(echo "$Info" | jq -r '.[]' )								#Cambiar formato a json
        NextLink=$(echo "$Info" | tail -n1 )							#Capturar ultima linea
        Info=$(echo "$Info" | sed '/^http/d') 							#Delete all line with "http"
        Info=$(echo "$Info" | sed '$d' ) 								#Borra la ultima linea (contiene "]")
		Info=$(echo "$Info" | sed "1,1d" )								#Delete first line
        FullInfo=$(echo "$FullInfo$Info")
    done
    echo "$FullInfo]"
    
}
############################################END FUNCTIONS############################################

#Generate Token
[ -s $TokenFile ] && token=$(cat "$TokenFile")
if [ "$TokenFile" = "" ] || [ "$TokenFile" = "null" ]
then
       Get_Token
fi
#echo "Token: $token"
authorization="Authorization: CwsAuth Bearer=${token}"

#Generate SITE ID
[ -s "$SiteIDFile" ] && Site=$(cat "$SiteIDFile")
if [ "$Site" = "" ] || [ "$Site" = "null" ]
then
       Get_SiteID "$authorization"
fi
#echo "SiteID: $Site"

Get_Info "$authorization"