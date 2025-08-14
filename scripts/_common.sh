#!/bin/bash

#=================================================
# COMMON VARIABLES AND CUSTOM HELPERS
#=================================================

# PostgreSQL required version
app_psql_version() {
	ynh_read_manifest "resources.apt.extras.postgresql.packages" \
	| grep -o 'postgresql-[0-9][0-9]-pgvector' \
	| head -n1 \
	| cut -d'-' -f2
}
app_psql_port() {
	pg_lsclusters --no-header \
	| grep "^$(app_psql_version)" \
	| cut -d' ' -f3
}

# Execute a psql command as root user
# usage: myynh_execute_psql_as_root --sql=sql [--options=options] [--database=database]
# | arg: -s, --sql=         - the SQL command to execute
# | arg: -o, --options=     - the options to add to psql
# | arg: -d, --database=    - the database to connect to
myynh_execute_psql_as_root() {
	# Declare an array to define the options of this helper.
	local legacy_args=sod
	local -A args_array=([s]=sql= [o]=options= [d]=database=)
	local sql
	local options
	local database
	# Manage arguments with getopts
	ynh_handle_getopts_args "$@"
	options="${options:-}"
	database="${database:-}"
	if [ -n "$database" ]
	then
		database="--dbname=$database"
	fi

	LC_ALL=C sudo --login --user=postgres PGUSER=postgres PGPASSWORD="$(cat $PSQL_ROOT_PWD_FILE)" \
		psql --cluster="$(app_psql_version)/main" $options "$database" --command="$sql"
}

# Drop default db & user created by [resources.database] in manifest
myynh_deprovision_default() {
	ynh_psql_database_exists $app && ynh_psql_drop_db $app || true
	ynh_psql_user_exists $app && ynh_psql_drop_user $app || true
}

# Create the cluster
myynh_create_psql_cluster() {
	if [[ -z `pg_lsclusters | grep $(app_psql_version)` ]]
	then
		pg_createcluster $(app_psql_version) main --start
	fi
}

# Install the database
myynh_create_psql_db() {
	myynh_execute_psql_as_root --sql="CREATE DATABASE $app;"
	myynh_execute_psql_as_root --sql="CREATE USER $app WITH ENCRYPTED PASSWORD '$db_pwd';" --database="$app"
	myynh_execute_psql_as_root --sql="GRANT ALL PRIVILEGES ON DATABASE $app TO $app;" --database="$app"
	myynh_execute_psql_as_root --sql="ALTER USER $app WITH SUPERUSER;" --database="$app"
	myynh_execute_psql_as_root --sql="CREATE EXTENSION IF NOT EXISTS vector;" --database="$app"
}

# Update the database
myynh_update_psql_db() {
	databases=$(myynh_execute_psql_as_root --sql="SELECT datname FROM pg_database WHERE datistemplate = false OR datname = 'template1';" \
		--options="--tuples-only --no-align" --database="postgres")

	for db in $databases
	do
		if ynh_hide_warnings myynh_execute_psql_as_root --sql=";" --database="$db" \
		   | grep -q "collation version mismatch"
		then
			ynh_hide_warnings myynh_execute_psql_as_root --sql="REINDEX DATABASE $db;" --database="$db"
			myynh_execute_psql_as_root --sql="ALTER DATABASE $db REFRESH COLLATION VERSION;" --database="$db"
		fi
	done
}

# Remove the database
myynh_drop_psql_db() {
	myynh_execute_psql_as_root --sql="REVOKE CONNECT ON DATABASE $app FROM public;"
	myynh_execute_psql_as_root --sql="SELECT pg_terminate_backend (pg_stat_activity.pid) FROM pg_stat_activity \
										WHERE pg_stat_activity.datname = '$app' AND pid <> pg_backend_pid();"
	myynh_execute_psql_as_root --sql="DROP DATABASE $app;"
	myynh_execute_psql_as_root --sql="DROP USER $app;"
}

# Dump the database
myynh_dump_psql_db() {
	sudo --login --user=postgres pg_dump --cluster="$(app_psql_version)/main" --dbname="$app" > db.sql
}

# Restore the database
myynh_restore_psql_db() {
	# https://github.com/immich-app/immich/issues/5630#issuecomment-1866581570
	ynh_replace --match="SELECT pg_catalog.set_config('search_path', '', false);" \
		--replace="SELECT pg_catalog.set_config('search_path', 'public, pg_catalog', true);" --file="db.sql"

	sudo --login --user=postgres PGUSER=postgres PGPASSWORD="$(cat $PSQL_ROOT_PWD_FILE)" \
		psql --cluster="$(app_psql_version)/main" --dbname="$app" < ./db.sql
}

myynh_set_default_psql_cluster_to_debian_default() {
	local default_port=5432
	local config_file="/etc/postgresql-common/user_clusters"

	#retrieve informations about default psql cluster
	default_psql_version=$(pg_lsclusters --no-header | grep "$default_port" | cut -d' ' -f1)
	default_psql_cluster=$(pg_lsclusters --no-header | grep "$default_port" | cut -d' ' -f2)
	default_psql_database=$(pg_lsclusters --no-header | grep "$default_port" | cut -d' ' -f5)

	# Remove non commented lines
	sed -i'.bak' -e '/^#/!d' "$config_file"

	# Add new line USER  GROUP   VERSION CLUSTER DATABASE
	echo -e "* * $default_psql_version $default_psql_cluster $default_psql_database" >> "$config_file"

	# Remove the autoprovisionned db if not on right cluster
	if [ "$(app_psql_port)" -ne "$default_port" ]
	then
		if ynh_psql_database_exists "$app"
		then
			ynh_psql_drop_db "$app"
		fi
		if ynh_psql_user_exists "$app"
		then
			ynh_psql_drop_user "$app"
		fi
	fi
}
