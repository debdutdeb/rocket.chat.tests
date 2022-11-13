#!/bin/bash

load "../common.bash"

# bats test_tags=pre
@test "Should install previous stable version" {
	run sudo snap install rocketchat-server --stable
	assert_success
}

# bats test_tags=pre
@test "Should upgrade successfully to new snap dangerously" {
	assert_not_equal "$ROCKETCHAT_SNAP"
	run sudo snap install "$ROCKETCHAT_SNAP" --dangerous
	assert_success
}

# bats test_tags=post
@test "Should back up db successfully" {
	run --separate-stderr rocketchat-server.backupdb
	assert_success
	local backup_file="$(awk '{ print $NF }' <<<"${lines[$((${#lines[@]} - 1))]}")"
	assert_file_exists "$backup_file"
	mv "$backup_file" /tmp/rocketchat.backup.tar.gz
}

# bats test_tags=post
@test "Should be able to restore database successfully" {
	run rocketchat-server.restoredb /tmp/rocketchat.backup.tar.gz
	assert_success
}

# bats test_tags=post
@test "Should have mongodb-tools installed" {
	for binary in mongodump mongorestore; do
		assert_file_executable "/snap/rocketchat-server/current/bin/$binary"
	done
}

# bats test_tags=post
@test "Should be able to change settings with *.env files" {
	echo "OVERWRITE_SETTING_Accounts_TwoFactorAuthentication_Enabled=false" |
		sudo tee /var/snap/rocketchat-server/common/test.env >/dev/null
	run sudo snap restart rocketchat-server
	assert_success
	wait_for_server
	run --separate-stderr /snap/rocketchat-server/current/bin/mongo --quiet --eval '
		printjson(db.getSiblingDB("partial").rocketchat_settings.findOne({
			_id: "Accounts_TwoFactorAuthenticationEnabled"
		}, {
			value: 1,
			valueSource: 1,
			processEnvValue: 1
			_id: 0
		}))
	'
	assert_success
	assert_field_equal value 'false'
	assert_field_equal processEnvValue 'false'
	assert_field_equal valueSource 'processEnvValue'
}

# bats test_tags=post
@test "MongoDb should run on changed port via config" {
	run sudo sed -Ei 's/( +port:) 27017/\1 27018/' /var/snap/rocketchat-server/current/mongod.conf
	assert_success
	run snap restart rocketchat-server.rocketchat-mongo
	assert_success
	run --separate-stderr /snap/rocketchat-server/current/bin/mongo --quiet --eval \
		'db.serverCmdLineOpts().parsed.net.port'
	assert_output 27018
}

# bats test_tags=post
@test "Should start successfully once new mongo-*urls are set" {
	run sudo snap set 'mongo-url=mongodb://localhost:27018/parties?replicaSet=rs0'
	assert_success
	run sudo snap set 'mongo-oplog-url=mongodb://localhost:27018/local?replicaSet=rs0'
	assert_success
	run snap restart rocketchat-server.rocketchat-server
	assert_success
	wait_for_server
}

teardown_file() {
	echo "# Removing backup file" >&3
	rm -f /tmp/rocketchat.backup.tar.gz
}