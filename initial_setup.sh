set -e
echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections
export DEBIAN_FRONTEND=noninteractive

apt-get update

# install misc tools
apt-get --yes --force-yes install git bc tsocks

sed -i "s/^server = .*$/server = 127.0.0.1/" /etc/tsocks.conf
sed -i "s/^server_port = .*$/server_port = 7072/" /etc/tsocks.conf

# install building dependencies for osm2pgsql
apt-get --yes --force-yes install make cmake g++ libboost-dev libboost-system-dev \
  libboost-filesystem-dev libexpat1-dev zlib1g-dev \
  libbz2-dev libpq-dev libgeos-dev libgeos++-dev libproj-dev lua5.2 \
  liblua5.2-dev

EBS_MOUNT="/mnt/g/work"
PG_MAJOR="9.5"
PG_DATA_DIR="/var/data/postgresql"
PG_CONFIG_FILE=/etc/postgresql/$PG_MAJOR/main/postgresql.conf
SOURCE_DIR="${EBS_MOUNT}/vector-datasource"
PGDATABASE="osm"
PGUSER="osm"
PGPASSWORD="osmpassword"
export EBS_MOUNT
export PG_DATA_DIR
export PG_CONFIG_FILE
export SOURCE_DIR
export PGDATABASE
export PGUSER
export PGPASSWORD
OSM2PGSQL_CACHE=$(free -m | grep -i 'mem:' | sed 's/[ \t]\+/ /g' | cut -f4,7 -d' ' | tr ' ' '+' | bc)
OSM2PGSQL_CACHE=$(( $OSM2PGSQL_CACHE > 33000 ? 33000 : $OSM2PGSQL_CACHE ))
OSM2PGSQL_PROCS=$(grep -c 'model name' /proc/cpuinfo)
OSMOSIS_WORKDIR="${EBS_MOUNT}/osmosis"
export OSM2PGSQL_CACHE
export OSM2PGSQL_PROCS

# install postgres / postgis
apt-get --yes --force-yes install unzip \
  postgresql postgresql-contrib postgis \
  postgresql-${PG_MAJOR}-postgis-2.2 \
  build-essential autoconf libtool pkg-config \
  python-dev python-virtualenv libgeos-dev \
  libpq-dev python-pip python-pil libmapnik3.0 \
  libmapnik-dev mapnik-utils python-mapnik \
  osmosis

sedeasy() {
  echo $1
  sed -i "s/${1}/$(echo $2 | sed -e 's/[\/&]/\\&/g')/g" $3
}

import_osm() {
  # Move the postgresql data to the EBS volume
  mkdir -p $PG_DATA_DIR
  sedeasy "^#\?data_directory = .*$" "data_directory = '/var/lib/postgresql/$PG_MAJOR/main'" $PG_CONFIG_FILE
  rm -rf /var/run/postgresql/
  mkdir -p /var/run/postgresql/
  /etc/init.d/postgresql stop

  # Update the postgresql config file
  sedeasy "^#\?data_directory = .*$" "data_directory = '${PG_DATA_DIR}/${PG_MAJOR}/main'" $PG_CONFIG_FILE
  sh -v config_postgresql.sh $PG_CONFIG_FILE

  rm -rf ${PG_DATA_DIR}/${PG_MAJOR}
  cp -a /var/lib/postgresql/$PG_MAJOR $PG_DATA_DIR
  chown -R postgres:postgres $PG_DATA_DIR
  rm -rf $EBS_MOUNT/postgresql
  mkdir -p $EBS_MOUNT/postgresql
  cd ${PG_DATA_DIR}/${PG_MAJOR}/main/
  mv base $EBS_MOUNT/postgresql/base
  ln -s $EBS_MOUNT/postgresql/base base
  mv global $EBS_MOUNT/postgresql/global
  ln -s $EBS_MOUNT/postgresql/global global
  /etc/init.d/postgresql start

  # Create database and user
  sudo -u postgres psql -c "CREATE ROLE ${PGUSER} WITH NOSUPERUSER LOGIN UNENCRYPTED PASSWORD '${PGPASSWORD}';"
  sudo -u postgres psql -c "CREATE DATABASE ${PGDATABASE} WITH OWNER ${PGUSER};"
  sudo -u postgres psql -d $PGDATABASE -c 'CREATE EXTENSION postgis; CREATE EXTENSION hstore;'

  # Download the planet
  tsocks wget --quiet --directory-prefix $EBS_MOUNT/data --timestamping http://s3.amazonaws.com/mapzen-tiles-assets/20161110/shapefiles.tar.gz
  tsocks wget --quiet --directory-prefix $EBS_MOUNT/data --timestamping https://s3.amazonaws.com/mapzen-tiles-assets/wof/dev/wof_neighbourhoods.pgdump
  tsocks wget --quiet --directory-prefix $EBS_MOUNT/data --timestamping https://s3.amazonaws.com/metro-extracts.mapzen.com/new-york_new-york.osm.pbf
  wget --quiet --directory-prefix $EBS_MOUNT/data --timestamping http://planet.openstreetmap.org/pbf/planet-latest.osm.pbf

  # Building osm2pgsql
  OSM2PGSQL_SOURCE_DIR="${EBS_MOUNT}/osm2pgsql"
  if [ ! -d "$OSM2PGSQL_SOURCE_DIR" ] ; then
    git clone https://github.com/lygstate/osm2pgsql.git $OSM2PGSQL_SOURCE_DIR
  fi

  cd $OSM2PGSQL_SOURCE_DIR
  git.exe checkout -f --track -B mz-integration remotes/origin/mz-integration
  mkdir -p build && cd build
  cmake ..
  make && make install

  # Import the planet
  if [ ! -d "$SOURCE_DIR" ] ; then
    git clone https://github.com/lygstate/vector-datasource.git $SOURCE_DIR
  fi
  ls $EBS_MOUNT/vector-datasource/osm2pgsql.style
  osm2pgsql --create --slim --cache $OSM2PGSQL_CACHE --hstore-all \
    --host localhost \
    --number-processes $OSM2PGSQL_PROCS \
    --style $EBS_MOUNT/vector-datasource/osm2pgsql.style \
    --flat-nodes /var/data/flatnodes \
    -d ${PGDATABASE} \
    $EBS_MOUNT/data/new-york_new-york.osm.pbf

}

import_shp() {
  # Download and import supporting data
  cd $SOURCE_DIR/data
  python bootstrap.py
  cp $EBS_MOUNT/data/shapefiles.tar.gz $SOURCE_DIR/data/
  make -f Makefile-import-data
  ./import-shapefiles.sh | psql -d $PGDATABASE -U $PGUSER -h localhost
  ./perform-sql-updates.sh -d $PGDATABASE -U $PGUSER -h localhost
  make -f Makefile-import-data clean
}

SOURCE_VENV="${SOURCE_DIR}/venv"
tsocks virtualenv $SOURCE_VENV
. "${SOURCE_VENV}/bin/activate"
tsocks pip -q install -U jinja2 pyaml

import_osm
import_shp

deactivate

# Downloading Who's on First neighbourhoods data
pg_restore --clean -d $PGDATABASE -U $PGUSER -h localhost -O "${EBS_MOUNT}/data/wof_neighbourhoods.pgdump"
