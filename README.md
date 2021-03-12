# Captura de datos Citrix Cloud VAAD para mostrarlos en Grafana con InfluxDB
Los script capturaran la información de Citrix VAADs y la adapta para importar a InfluxDB

1- Accedemos a nuestra cuenta de Citrix Cloud y nos dirigimos a "Identity and Access Management" a la pestaña de API Access.

2- Podremos ver nuestro Customer ID.

3- Introducimos un nombre para nuestro cliente API y "Create Client".

![image](https://user-images.githubusercontent.com/80542322/110987618-a521db00-836f-11eb-8ebf-3834f20f381b.png)

4- No falicitara el ID y Secret

![image](https://user-images.githubusercontent.com/80542322/110987928-21b4b980-8370-11eb-8033-557d698a50b0.png)

5- Introducimos los datos en el Script.
CLIENTID="Cliente ID"   		
CLIENTSECRET="Secret Ke"    
CustomerID="Customer ID"    

6- Copiamos el Script en la maquina linux con telegraf.

7- Para el Script de Api Service, duplicaremos el script para cada tipo de captura de (Applications, Machines, DeliveryGroups, MachineCatalogs, Sessions)

8- Editamos la linea de (Capture="Applications") para especificar la captura, de la URL https://api.cloud.com/cvadapis/$Site/$Capture

En la Web https://developer.cloud.com/citrixworkspace/virtual-apps-and-desktops/cvad-rest-apis/docs/overview podremos ver las URL de captura de datos.

