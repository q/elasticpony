#!/usr/bin/env bash

SCRIPT_NAME=$0

usage() {
    cat <<EOF
Usage: $SCRIPT_NAME OPTIONS

Application:
 -n NAME                 set the NAME of the application - letters, numbers and underscore
                         
Database:        
 -H DATABASE_HOST        the database host
 -D DATABASE_NAME        the database name to use. Defaults to \${NAME}
 -U DATABASE_USER        the database user to use. Default to \${NAME}
 -P DATABASE_PASSWORD    the database password

Web:
 -w WEBSERVER            which webserver to use. apache only at the moment
 -u SITE_NAME            the SiteName to use in Apache. Defaults to \${NAME}.com
 -s STATIC_URL           the url for static assets. Defaults to /static/
                         
Local:                 
 -u LOCAL_USER           name of the unix user to create. Defaults to \${NAME}
 -p PROJECT_ROOT         name of the project root. Defaults to /home/\${LOCAL_USER}/\${NAME}
EOF
}

die() {
    message=$1
    error_code=$2

    echo "$SCRIPT_NAME: $message" 1>&2
    usage
    exit $error_code
}

get_options() {
    while getopts "hn:d:H:D:U:P:w:u:s:u:p:" opt; do
        case "$opt" in
            h)
                usage
                exit 0
                ;;
            n)
                export NAME="$OPTARG"
                ;;
            d)
                export DISTRIBUTION="$OPTARG"
                ;;
            H)
                export DATABASE_HOST="$OPTARG"
                ;;
            D)
                export DATABASE_NAME="$OPTARG"
                ;;
            U)
                export DATABASE_USER="$OPTARG"
                ;;
            P)
                export DATABASE_PASSWORD="$OPTARG"
                ;;
            w)
                export WEBSERVER="$OPTARG"
                ;;
            u)
                export SITE_NAME="$OPTARG"
                ;;
            s)
                export STATIC_URL="$OPTARG"
                ;;
            u)
                export LOCAL_USER="$OPTARG"="$OPTARG"
                ;;
            p)
                export PROJECT_ROOT="$OPTARG"
                ;;
            [?])
                die "unknown option $opt" 10
                ;;
        esac
    done
}


handle_defaults() {
    if [ -z "$NAME" ]; then
        die "NAME is required" 1
    fi
    
    if [ -z "$DATABASE_NAME" ]; then
        export DATABASE_NAME="$NAME"
    fi
    
    if [ -z "$DATABASE_HOST" ]; then
        export DATABASE_HOST="localhost"
    fi
    
    if [ -z "$DATABASE_USER" ]; then
        export DATABASE_USER="$NAME"
    fi
    
    if [ -z "$DATABASE_PASSWORD" ]; then
        export DATABASE_PASSWORD=`head -c 100 /dev/urandom | md5sum | awk '{print $1}'`
    fi

    if [ -z "$WEBSERVER" ]; then
        export WEBSERVER="apache"
    fi

    if [ -z "$SITE_NAME" ]; then
        export SITE_NAME="${NAME}.com"
    fi
    
    if [ -z "$STATIC_URL" ]; then
        export STATIC_URL="/static/"
    fi

    if [ -z "$ADMIN_EMAIL" ]; then
        export ADMIN_EMAIL="alerts@${SITE_NAME}"
    fi
    
    if [ -z "$LOCAL_USER" ]; then
        export LOCAL_USER="$NAME"
    fi
    
    if [ -z "$PROJECT_ROOT" ]; then
        export PROJECT_ROOT="/home/$LOCAL_USER/$NAME"
    fi
}

export DEBIAN_FRONTEND=noninteractive

# update the running machine
update_system() {
    aptitude update
    aptitude -y safe-upgrade
}

install_baseline() {
    apt-get install -y build-essential git curl
    apt-get install -y libjpeg-dev libjpeg62 libjpeg62-dev zlib1g-dev libfreetype6 libfreetype6-dev libpng-dev zlib1g-dev liblcms1-dev
}

install_python() {
    apt-get install -y python python-dev python-pip python-setuptools python-mysqldb 
    pip install virtualenv
}

install_nginx() {
    apt-get install -y nginx
    apt-get install -y python-flup
}

install_apache() {
    apt-get install -y apache2 libapache2-mod-wsgi 
}


configure_apache() {
    cat <<EOF | sudo tee /etc/apache2/sites-available/$NAME
<VirtualHost *:80>
    ServerName $SITE_NAME
    ServerAdmin $ADMIN_EMAIL
    LogLevel warn
    ErrorLog \${APACHE_LOG_DIR}/${SITE_NAME}_error.log
    CustomLog \${APACHE_LOG_DIR}/${SITE_NAME}_access.log combined

    WSGIDaemonProcess $NAME user=www-data group=www-data maximum-requests=10000 python-path=/home/$LOCAL_USER/env/lib/python2.7/site-packages
    WSGIProcessGroup $NAME

    WSGIScriptAlias / $PROJECT_ROOT/lolaws/apache/lolaws.wsgi

    <Directory $PROJECT_ROOT/>
        Order deny,allow
        Allow from all
    </Directory>

</VirtualHost>

EOF
}

activate_apache() {
    sudo a2dissite default
    sudo a2ensite $NAME
    sudo /etc/init.d/apache2 reload
}

install_webserver() {
    if [[ $WEBSERVER == "nginx" ]]; then
        install_nginx
        die "cannot yet configure nginx"
    else
        if [[ $WEBSERVER == "apache" ]]; then
            install_apache
            configure_apache
        else
            die "unknown webserver $WEBSERVER"
        fi
    fi
}

activate_webserver() {
    if [[ $WEBSERVER == "nginx" ]]; then
        die "cannot yet activate nginx"
    else 
        if [[ $WEBSERVER == "apache" ]]; then 
            activate_apache
        else
            die "unknown webserver $WEBSERVER"
        fi
    fi
}

bootstrap_project() {
    adduser --system --disabled-password --disabled-login $LOCAL_USER
    sudo -u $LOCAL_USER virtualenv /home/$LOCAL_USER/env
    sudo -u $LOCAL_USER mkdir $PROJECT_ROOT
}

configure_local_settings() {
    cat <<EOF | sudo -u $LOCAL_USER tee $PROJECT_ROOT/local_settings.py
BASE_URL="http://$SITE_NAME"
DEBUG = False
TEMPLATE_DEBUG = False
SERVE_MEDIA = False

DATABASES = {
    "default": {
       "ENGINE": "mysql",
       "NAME": "$DATABASE_NAME",
       "USER": "$DATABASE_USER",
       "PASSWORD": "$DATABASE_PASSWORD",
       "HOST": "$DATABASE_HOST",
    }
}

STATIC_URL = "$STATIC_URL"
STATIC_ROOT = "$PROJECT_ROOT/media"
TEMPLATE_DIRS = ["$PROJECT_ROOT/templates"]

EOF
}


print_launch_conf() {
    cat<<EOF

** To automate launching an instance like this one, put the following in your userdata script **

wget $CANONICAL_URL
sudo bash $SCRIPT_NAME -n $NAME -d $DISTRIBUTION -H $DATABASE_HOST -D $DATABASE_NAME -U $DATABASE_USER -P $DATABASE_PASSWORD -w $WEBSERVER -u $SITE_NAME -s $STATIC_URL -u $LOCAL_USER -p $PROJECT_ROOT"

EOF
}


get_options $*
handle_defaults

update_system
install_baseline
install_python
install_webserver

bootstrap_project
activate_webserver
