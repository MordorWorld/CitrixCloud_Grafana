#!/bin/bash
##########################################################################################
##      ===========================================================================
##       Created on:   	03/11/2021 
##       Created by:   	GrumpyGon & Bujarron
##       Organization: 	www.mordor.world
##		 Version: 		02.02
##      ===========================================================================
##      .DESCRIPTION
##         Script de recolección de Citrix Cloud con API Service diseñado para telegraf e influxdb
##
##      .REQUERIMENTS
##			· Tener instalado snap "snap install jq"
##			· Una cuenta de Client API de nuestro Citrix Cloud
##			· Sera necesario tener permisos para la ejecución de los mismos      
##      			vi /etc/systemd/system/multi-user.target.wants/telegraf.service
##              		Cambiar el usuario telegraf --> root
##      				systemctl daemon-reload
##      				service telegraf restart
##      	For me the fix was changing /etc/passwd telegraf user shell from /bin/false to /bin/bash
##
##		.TELEGRAF Config
##			Fichero de configuración para telegraf
##			[[inputs.exec]]
##			   commands = ["/etc/telegraf/CitrixCloud/File-script.sh"]
##			   name_override = "CTX_Applications"
##			   timeout = "30s"
##			   data_format = "json"
##			   tag_keys = ["Id","Uid"]
##			   json_string_fields = ["*"]
##########################################################################################
########################################CLIENT API########################################
ClientName="Nombre Cliente"
CLIENTID="Cliente ID"							  		#ID Cliente API Citrix Cloud
CLIENTSECRET="Secret Key"				      			#Secret API Citrix Cloud
CustomerID="Customer ID"            					#ID Cliente
FilePath="/etc/telegraf/CitrixCloud"					#Ubicación de Scripts
SiteIDFile="$FilePath/0-SiteID.$ClientName"      		#Fichero de SiteID
TokenFile="$FilePath/0-Token.$ClientName"     			#Fichero de Token
LogFile="/var/log/telegraf/$ClientName-CitrixCloud.log"	#Fichero de Logs
LogSize=1000000
Capture="Applications"									#Tipo de Captura (Applications, Machines, DeliveryGroups, MachineCatalogs, Sessions)
Retry=3
###########################################URLs###########################################
SiteMe="https://api.cloud.com/cvadapis/me"
trustUrl="https://api.cloud.com/cctrustoauth2/root/tokens/clients"
HeaderCustomerID="Citrix-CustomerId: $CustomerID"
j="Accept: application/json"
########################################FUNCTIONS########################################
function Write-Log(){
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

function Get_Info () {
        Write-Log "INFO - Generando Json"
        UrlInfo="https://api.cloud.com/cvadapis/$Site/$Capture"		#URL de Captura
        Info=$(curl -s --write-out "\n%{http_code}\n" ${UrlInfo} -H "${j}" -H "${1}" -H "${HeaderCustomerID}" )
        URLCode=$(echo "$Info" | tail -n1 )
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
                                Info=$(curl -s --write-out "\n%{http_code}\n" ${UrlInfo} -H "${j}" -H "${1}" -H "${HeaderCustomerID}" )
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
                Info=$(echo "$Info" | sed '$d' )     #Borra la ultima linea Error Code
                Info=$(echo "$Info" | jq -r '.Items[] | del(.ContainerScopes,.AppVAppProperties)')
                Info=$(echo "$Info" | tr -d '\n\t' )
                Info=$(echo "$Info" | sed -r 's/\}\{/\}\,\{/g')
                Info=$(echo "$Info" | sed '1 s/./[&/')
                echo "$Info]"
}




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
