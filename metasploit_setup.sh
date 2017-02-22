#! /bin/bash
set -e

# Metasploit installer

#fedora packager:
#INSTALLER="dnf"

#debian packager
INSTALLER="apt-get"

git clone https://github.com/rapid7/metasploit-framework.git

cd metasploit-framework

sudo $INSTALLER install -y build-essential zlib1g zlib1g-dev \
libxml2 libxml2-dev libxslt-dev locate \
libreadline6-dev libcurl4-openssl-dev git-core \
libssl-dev libyaml-dev openssl autoconf libtool \
ncurses-dev bison curl wget xsel postgresql \
postgresql-contrib libpq-dev libapr1 libaprutil1 libsvn1 \
libpcap-dev libsqlite3-dev libgmp3-dev

sudo $INSTALLER install -y ruby ruby-dev #ruby2.3-dev ruby2.3
sudo gem install bundler

bundle install

#gems version
#GEMS_VER=$(gem -v)

# Fix some files that needs permissions
find "/var/lib/gems" -iname "robots.rb" | xargs sudo chmod +r

echo "Metasploit is installed. Now to set up the database"

#set up the database from base install
sudo systemctl enable postgresql
sudo systemctl start postgresql

#postgres version in form x.y for folder paths
PG_VER=`psql --version | awk '{print $3}' | cut -d. -f1,2`
echo "Found postgres version: $PG_VER"

#====== These values may be modified if desired ========

#metasploit paramaters
#db user
MSF_USER="msf"

#db
MSF_DB="msf_database"
DB_PORT=5432

#default postgres super user
POSTGRES_USER="postgres"

#random password so user will never need to know it
MSF_PASS=`cat /dev/urandom |base64 | head -c8`
POSTGRES_PASS=`cat /dev/urandom |base64 | head -c8`

#on debian
CONF_DIR="/etc/postgresql/$PG_VER/main/"
#on fedora
#CONF_DIR="/var/lib/pgsql/data/"


HBA_FILE="$CONF_DIR/pg_hba.conf"
PG_CONF="$CONF_DIR/postgresql.conf"

#====== Dont modify anything else =========

#create msf user, db and change password to the randomly generated one
#configure postgres to listen on localhost
#configure postgres to accept connections from the allowed users.
sudo -i -u $POSTGRES_USER << EOF
createuser $MSF_USER || true
psql -c "ALTER USER $MSF_USER WITH ENCRYPTED PASSWORD '$MSF_PASS';"
createdb --owner=$MSF_USER $MSF_DB || true

psql -c "ALTER USER $POSTGRES_USER WITH ENCRYPTED PASSWORD '$POSTGRES_PASS';"

echo "host    all    $POSTGRES_USER    127.0.0.1/32    md5" > "$HBA_FILE"
echo "host    $MSF_DB    $MSF_USER    127.0.0.1/32    md5" >> "$HBA_FILE"

echo "localhost:$DB_PORT:*:postgres:$POSTGRES_PASS" > ~/.pgpass
echo "localhost:$DB_PORT:$MSF_DB:$MSF_USER:$MSF_PASS" >> ~/.pgpass
chmod 0600 ~/.pgpass

echo "listen_addresses = 'localhost'" >> "$PG_CONF"

exit
EOF

#configure metaspolit to use the newly created database settings
cat > config/database.yml << EOF
production:
    adapter: postgresql
    database: $MSF_DB
    username: $MSF_USER
    password: $MSF_PASS
    host: 127.0.0.1
    port: $DB_PORT
    pool: 75
    timeout: 5
EOF

sudo systemctl restart postgresql

echo "Database configured."

