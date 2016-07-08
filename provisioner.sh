#!/bin/bash
# Reworked from https://github.com/snipe/snipe-it/blob/master/snipeit.sh (thank you Mike Tucker, mtucker6784@gmail.com)

set -x

### Variables ###

hosts="/etc/hosts"
name="snipeit"
fqdn=$DOMAIN
hostname=$fqdn
dbsetup=db_setup.sql
mysqluserpw=$RANDOM_PASSWORD
random32="$(echo `< /dev/urandom tr -dc _A-Za-z-0-9 | head -c32`)" # Snipe says we need a new 32bit key, so let's create one randomly and inject it into the file
apachefile=/etc/apache2/sites-available/$name.conf
webdir=/var/www

echo >> $dbsetup "CREATE DATABASE snipeit;"
echo >> $dbsetup "GRANT ALL PRIVILEGES ON snipeit.* TO snipeit@localhost IDENTIFIED BY '$mysqluserpw';"

#Let us make it so only root can read the file. Again, this isn't best practice, so please remove these after the install.
chown root:root $dbsetup
chmod 700 $dbsetup

#####################################  Install for Ubuntu  ##############################################

#Update/upgrade Debian/Ubuntu repositories, get the latest version of git.
echo ""
echo "##  Updating ubuntu in the background. Please be patient."
echo ""

export ROOT_MYSQL_PASSWORD=$(gen_password)
# Set the default root password - we should change this after installation
debconf-set-selections <<< "mysql-server mysql-server/root_password password ${ROOT_MYSQL_PASSWORD}"
debconf-set-selections <<< "mysql-server mysql-server/root_password_again password ${ROOT_MYSQL_PASSWORD}"

apt-get -y update
apt-get install -y git unzip php5 php5-mcrypt php5-curl php5-mysql php5-gd php5-ldap mysql-server

#Enable mcrypt and rewrite
echo "##  Enabling mcrypt and rewrite"
php5enmod mcrypt
a2enmod rewrite

#  Get files and extract to web dir
echo "##  Installing packages."
echo "##  Setting up LAMP."
apt-get install -y lamp-server^

# copy git repo into $webdir/$name
cp -R . $webdir/$name

apache2ctl restart

#Create a new virtual host for Apache.
echo "##  Create Virtual host for apache."
echo >> $apachefile ""
echo >> $apachefile ""
echo >> $apachefile "<VirtualHost *:80>"
echo >> $apachefile "ServerAdmin webmaster@localhost"
echo >> $apachefile "    <Directory $webdir/$name/public>"
echo >> $apachefile "        Require all granted"
echo >> $apachefile "        AllowOverride All"
echo >> $apachefile "   </Directory>"
echo >> $apachefile "    DocumentRoot $webdir/$name/public"
echo >> $apachefile "    ServerName $fqdn"
echo >> $apachefile "        ErrorLog /var/log/apache2/snipeIT.error.log"
echo >> $apachefile "        CustomLog /var/log/apache2/access.log combined"
echo >> $apachefile "</VirtualHost>"

echo "##  Setting up hosts file."
echo >> $hosts "127.0.0.1 $hostname $fqdn"
a2ensite $name.conf >> /var/log/snipeit-install.log 2>&1 

#Modify the Snipe-It files necessary for a production environment.
echo "##  Modify the Snipe-It files necessary for a production environment."
echo "	Setting up Timezone."
tzone=$(cat /etc/timezone);
sed -i "s,UTC,$tzone,g" $webdir/$name/app/config/app.php

echo "	Setting up bootstrap file."
sed -i "s,www.yourserver.com,$hostname,g" $webdir/$name/bootstrap/start.php

echo "	Setting up database file."
cp $webdir/$name/app/config/production/database.example.php $webdir/$name/app/config/production/database.php
sed -i "s,snipeit_laravel,snipeit,g" $webdir/$name/app/config/production/database.php
sed -i "s,travis,snipeit,g" $webdir/$name/app/config/production/database.php
sed -i "s,password'  => '',password'  => '$mysqluserpw',g" $webdir/$name/app/config/production/database.php

echo "	Setting up app file."
cp $webdir/$name/app/config/production/app.example.php $webdir/$name/app/config/production/app.php
sed -i "s,https://production.yourserver.com,http://$fqdn,g" $webdir/$name/app/config/production/app.php
sed -i "s,Change_this_key_or_snipe_will_get_ya,$random32,g" $webdir/$name/app/config/production/app.php

echo "	Setting up mail file."
cp $webdir/$name/app/config/production/mail.example.php $webdir/$name/app/config/production/mail.php


#Change permissions on directories
echo "##  Seting permissions on web directory."
sudo chmod -R 755 $webdir/$name/app/storage
sudo chmod -R 755 $webdir/$name/app/private_uploads
sudo chmod -R 755 $webdir/$name/public/uploads
sudo chown -R www-data:www-data /var/www/
# echo "##  Finished permission changes."

echo "##  Input your MySQL/MariaDB root password: "
sudo mysql -uroot -p"${ROOT_MYSQL_PASSWORD}" < $dbsetup

echo "##  Securing Mysql"

#Install / configure composer
echo "##  Installing and configuring composer"
curl -sS https://getcomposer.org/installer | php
mv composer.phar /usr/local/bin/composer
cd $webdir/$name/
composer install --no-dev --prefer-source
php artisan app:install --env=production

echo "##  Restarting apache."
service apache2 restart
