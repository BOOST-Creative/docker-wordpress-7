#! /bin/bash

# terminate on errors
# set -e

# install wordpress if necessary
CONFIG=/usr/src/wordpress/wp-config.php
SAMPLE=/usr/src/wordpress/wp-config-sample.php

if [ "$(ls -A /usr/src/wordpress)" ]; then
	echo "Wordpress folder is not empty. Skipping install..."
else
	echo "Wordpress files do not exist. Installing..."
	if [[ ! -f "$SAMPLE" ]]; then
		# download & extract wordpress
		wget -q https://wordpress.org/latest.tar.gz \
			&& tar -xzkf latest.tar.gz -C /usr/src/ \
			&& rm latest.tar.gz \
			&& chown -R nobody: /usr/src/wordpress
	fi
	echo "*** Please restart container after Wordpress setup ***"
	exec "$@"
fi

# exit if no wp-config.php
if [[ ! -f "$CONFIG" ]]; then
	echo "*** Config file not found. Please restart after installing Wordpress. ***"
	exec "$@"
fi

# good default wp config settings
if [[ ! -f "/usr/src/wordpress/.config-configured" ]]; then
	# disable cron - handled by healthcheck
	cd /usr/src/wordpress && wp config set DISABLE_WP_CRON true --raw --skip-themes --skip-plugins
	# limit post revisions
	cd /usr/src/wordpress && wp config set WP_POST_REVISIONS 5 --raw --skip-themes --skip-plugins
	# add file to prevent this from running again
	touch /usr/src/wordpress/.config-configured
fi

# install vips image editor
if [ ! "$(ls -A "/usr/src/wordpress/wp-content/plugins/vips-image-editor" 2>/dev/null)" ]; then
	echo 'Adding plugin: vips-image-editor'
	cd /usr/src/wordpress && wp --skip-themes plugin install --activate https://github.com/henrygd/vips-image-editor/releases/latest/download/vips-image-editor.zip
fi

# install additional plugins
for PLUGIN in $ADDITIONAL_PLUGINS; do
	if [ ! "$(ls -A "/usr/src/wordpress/wp-content/plugins/$PLUGIN" 2>/dev/null)" ]; then
		echo "Adding plugin: $PLUGIN"
		cd /usr/src/wordpress && wp plugin --skip-themes install --activate "$PLUGIN"
	fi
done

# auto setup w3 total cache
if [ "$REDIS_HOST" ] && [[ ! -f "/usr/src/wordpress/.cache-configured" ]]; then
	if wp plugin --skip-themes is-active litespeed-cache; then
		wp plugin--skip-themes --uninstall deactivate litespeed-cache
	fi
	if wp plugin --skip-themes is-active w3-total-cache; then
		echo "Updating cache options..."
		cd /usr/src/wordpress && wp --skip-themes w3-total-cache option set dbcache.engine "redis"
		cd /usr/src/wordpress && wp --skip-themes w3-total-cache option set objectcache.engine "redis"
		cd /usr/src/wordpress && wp --skip-themes w3-total-cache option set pgcache.engine "redis"

		cd /usr/src/wordpress && wp --skip-themes w3-total-cache option set dbcache.redis.servers "$REDIS_HOST" --type=array
		cd /usr/src/wordpress && wp --skip-themes w3-total-cache option set objectcache.redis.servers "$REDIS_HOST" --type=array
		cd /usr/src/wordpress && wp --skip-themes w3-total-cache option set pgcache.redis.servers "$REDIS_HOST" --type=array

		cd /usr/src/wordpress && wp --skip-themes w3-total-cache option set dbcache.enabled true --type=boolean
		cd /usr/src/wordpress && wp --skip-themes w3-total-cache option set objectcache.enabled true --type=boolean
		cd /usr/src/wordpress && wp --skip-themes w3-total-cache option set pgcache.enabled true --type=boolean
		cd /usr/src/wordpress && wp --skip-themes w3-total-cache option set browsercache.enabled true --type=boolean
		
		# cache unchanged pages for 24 hours
		cd /usr/src/wordpress && wp --skip-themes w3-total-cache option set pgcache.lifetime 86400 --type=integer

		# browser cache html for 20 min
		cd /usr/src/wordpress && wp --skip-themes w3-total-cache option set browsercache.html.lifetime 1200 --type=integer
		cd /usr/src/wordpress && wp --skip-themes w3-total-cache option set browsercache.html.expires true --type=boolean
		cd /usr/src/wordpress && wp --skip-themes w3-total-cache option set browsercache.html.cache.control true --type=boolean

		# add file to prevent this from running again
		touch /usr/src/wordpress/.cache-configured
	fi
fi

# handle cron
if [ -z "$CRON" ]; then
  echo "No cron commands specified..."
else
	# add commands
	echo "$CRON" > /tmp/newcron
	crontab /tmp/newcron
  rm /tmp/newcron

	echo "Starting cron daemon..."
	/usr/sbin/crond
fi

# make sure plugins have correct permissions
chown -R nobody: /usr/src/wordpress/wp-content

exec "$@"