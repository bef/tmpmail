-- create database tmpmail;
-- create user 'tmpmail'@'%' IDENTIFIED BY 'tmpmail';
-- grant all privileges on tmpmail.* to 'tmpmail'@'%';
-- flush privileges;

CREATE TABLE IF NOT EXISTS msgs (
id BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
frm VARCHAR(1024) DEFAULT '',
rcpt VARCHAR(1024) DEFAULT '',
ts TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
valid_until TIMESTAMP NULL DEFAULT NULL,
data_id BIGINT UNSIGNED
);
ALTER TABLE msgs ADD COLUMN remote VARCHAR(64) DEFAULT '' AFTER valid_until;

CREATE TABLE IF NOT EXISTS data (
id BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
data BLOB DEFAULT ''
);