#!/bin/bash

function software_check() {
    which "$1" | grep -o "$1" > /dev/null &&  return 0 || return 1
}
function mariadbserver_check() {
    which "mariadb-secure-installation" | grep -o "mariadb-secure-installation" > /dev/null &&  return 0 || return 1
}
function software_install() {
    apt -y install $1
}

rootmdp=$(echo $RANDOM | md5sum | head -c 20; echo;)
echo "mot de passe root mysql: $rootmdp" > /temp/nextcloud.txt
nextcloudmdp=$(echo $RANDOM | md5sum | head -c 20; echo;)
function install_BDD() {
    if mariadbserver_check == 0 ; then 
        echo "mariadb-server est deja installer sur le disque !";
    else 
        software_install "mariadb-server";
    fi
    software_install "mariadb-client"; 
   
    echo "ALTER USER root@localhost identified by '"$rootmdp"';" > mysql_secure_installation.sql
    echo "DELETE FROM mysql.user WHERE User='';" >> mysql_secure_installation.sql
    echo "DROP DATABASE IF EXISTS test;" >> mysql_secure_installation.sql
    echo "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';" >> mysql_secure_installation.sql
    echo "FLUSH PRIVILEGES;" >> mysql_secure_installation.sql

    mysql -u root -p$rootmdp < mysql_secure_installation.sql
    echo "mot de passe root pour la connexion au server bdd: '"$rootmdp"'"

    echo "CREATE USER nextcloud@localhost IDENTIFIED BY '"$nextcloudmdp"';" > nextcloudbdd.sql
    echo "CREATE USER nextcloud IDENTIFIED BY '"$nextcloudmdp"';" >> nextcloudbdd.sql
    echo "CREATE DATABASE nextcloud;" >> nextcloudbdd.sql
    echo "GRANT ALL PRIVILEGES ON nextcloud.* TO nextcloud@localhost;" >> nextcloudbdd.sql
    echo "GRANT ALL PRIVILEGES ON nextcloud.* TO nextcloud;" >> nextcloudbdd.sql
    echo "FLUSH PRIVILEGES;" >> nextcloudbdd.sql
    mysql -u root -p$rootmdp < nextcloudbdd.sql
}

function install_web() {
    apt -y install php php-{cli,xml,zip,curl,gd,cgi,mysql,mbstring} 
    apt -y install apache2 libapache2-mod-php

    sed -i 's/\date.timezone/;date.timezone/g' /etc/php/*/apache2/php.ini
    sed -i 's/\memory_limit/;memory_limit/g' /etc/php/*/apache2/php.ini
    sed -i 's/\upload_max_filesize/;upload_max_filesize/g' /etc/php/*/apache2/php.ini
    sed -i 's/\post_max_size/;post_max_size/g' /etc/php/*/apache2/php.ini
    sed -i 's/\max_execution_time/;max_execution_time/g' /etc/php/*/apache2/php.ini
    echo "date.timezone = Europe/Paris" >> /etc/php/*/apache2/php.ini
    echo "memory_limit = 512M" >> /etc/php/*/apache2/php.ini
    echo "upload_max_filesize = 500M" >> /etc/php/*/apache2/php.ini
    echo "post_max_size = 500M" >> /etc/php/*/apache2/php.ini
    echo "max_execution_time = 300" >> /etc/php/*/apache2/php.ini

    systemctl restart apache2
}

function download_nextcloud() {
    apt -y install wget curl unzip
    if [ -d "/temp" ] ; then
        rm -rf /temp/*
    else
        mkdir /temp
    fi
    #wget https://download.nextcloud.com/server/releases/latest.zip -O /temp/latest.zip
    cp /root/latest.zip /temp/latest.zip

    unzip /temp/latest.zip -d /temp
    rm -f /temp/latest.zip

    mv /temp/nextcloud /var/www/nextcloud
    chown -R www-data:www-data /var/www/nextcloud 
    chmod -R 755 /var/www/nextcloud
}

function configure_web() {
    echo "1) Installation de Nextcloud avec alias (http://test.com/nextcloud)(uniquement http)"
    echo "2) Installation de Nextcloud avec nom de domaine (https://nextcloud.test.com)"
    choisir_configure_web
}
function choisir_configure_web() {
    read -n1 -p "Choose action (1-2) : " Action_web
    if [ "$Action_web" == "1" ]; then
        configure_web_alias
    elif [ "$Action_web" == "2" ]; then
        configure_web_servername
    else
        echo "entrer incorrect, veuillez entrez votre selection (1-2) !"
        choisir_configure_web
    fi
}
function configure_web_alias() {
    echo "Alias	/nextcloud /var/www/nextcloud" > /etc/apache2/conf-available/nextcloud.conf
    echo "<Directory /var/www/nextcloud>" >> /etc/apache2/conf-available/nextcloud.conf
    echo "require all granted" >> /etc/apache2/conf-available/nextcloud.conf
    echo "</Directory>" >> /etc/apache2/conf-available/nextcloud.conf

    a2enconf nextcloud.conf
    systemctl restart apache2
}
function configure_web_servername() {
    a2enmod ssl
    apt-get install -y openssl 
    mkdir -p /etc/ssl/private 
    mkdir -p /etc/ssl/certs
    read -p "veuiller saisir ici le serverName pour nextcloud (exemple : nextcloud.test.com) !" Action_sn
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/ssl/private/nextcloud-selfsigned.key -out /etc/ssl/certs/nextcloud-selfsigned.crt -subj "/C=FR/ST=France/L=Paris/O=Nextcloud/OU=Nextcloud/CN=$Action_sn"

    echo "<VirtualHost *:443>" > /etc/apache2/sites-available/$Action_sn.conf
    echo "ServerName $Action_sn" >> /etc/apache2/sites-available/$Action_sn.conf
    echo "DocumentRoot /var/www/nextcloud" >> /etc/apache2/sites-available/$Action_sn.conf
    echo "SSLEngine on" >> /etc/apache2/sites-available/$Action_sn.conf
    echo "SSLCertificateFile /etc/ssl/certs/nextcloud-selfsigned.crt" >> /etc/apache2/sites-available/$Action_sn.conf
    echo "SSLCertificateKeyFile /etc/ssl/private/nextcloud-selfsigned.key" >> /etc/apache2/sites-available/$Action_sn.conf
    echo "</VirtualHost>" >> /etc/apache2/sites-available/$Action_sn.conf 
    a2ensite $Action_sn.conf
    systemctl restart apache2

    echo "<VirtualHost *:80>" > /etc/apache2/sites-available/$Action_sn-80.conf
    echo "ServerName $Action_sn" >> /etc/apache2/sites-available/$Action_sn-80.conf
    echo "Redirect / https://$Action_sn" >> /etc/apache2/sites-available/$Action_sn-80.conf
    echo "</VirtualHost>" >> /etc/apache2/sites-available/$Action_sn-80.conf
    a2ensite $Action_sn-80.conf
    systemctl restart apache2
}

function save() {
    echo "vos mots de passe et chemin d'accés son stocker dans le fichier /temp/nextcloud.txt, veuiller securiser les données et supprimer le fichier apres utilisation"
    echo "veuiller securiser les données et supprimer ce fichier apres utilisation" > /temp/nextcloud.txt
    echo "mot de passe root mysql: $rootmdp" >> /temp/nextcloud.txt
    echo "mot de passe de l'utilisateur nextcloud: $nextcloudmdp" >> /temp/nextcloud.txt
    echo "chemin d'accés nextcloud: /var/www/nextcloud" >> /temp/nextcloud.txt
    echo "" >> /temp/nextcloud.txt
    echo "------------------------si l'accès à nextcloud est configurer par alias------------------------" >> /temp/nextcloud.txt
    echo "chemin de la config : /etc/apache2/conf-available/nextcloud.conf" >> /temp/nextcloud.txt
    echo "" >> /temp/nextcloud.txt
    echo "------------------------si l'accès à nextcloud est configurer par serverName------------------------" >> /temp/nextcloud.txt
    echo "chemin du fichier de certificat ssl pour ce servername : /etc/ssl/certs/nextcloud-selfsigned.crt" >> /temp/nextcloud.txt
    echo "chemin de la clé de certificat ssl pour ce servername : /etc/ssl/private/nextcloud-selfsigned.key" >> /temp/nextcloud.txt
    echo "chemin de la vhost https de ce servername : /etc/apache2/sites-available/[servername].conf" >> /temp/nextcloud.txt
    echo "chemin de la vhost http de ce servername : /etc/apache2/sites-available/[servername]-80.conf" >> /temp/nextcloud.txt
    echo "" >> /temp/nextcloud.txt
    echo "[servername] est à changer par votre serverName" >> /temp/nextcloud.txt
}

apt -y update 
apt -y upgrade

install_BDD
install_web
download_nextcloud
configure_web
save