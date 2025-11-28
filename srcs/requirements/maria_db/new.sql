-- Create the database
CREATE DATABASE IF NOT EXISTS ${DB_NAME};

-- Create the user and set password
CREATE USER IF NOT EXISTS '${DB_USR}'@'%' IDENTIFIED BY '${DB_PASSWORD}';

-- Give that user full access to the database
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USR}'@'%';

-- Set the root user password
ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';

-- Apply changes
FLUSH PRIVILEGES;