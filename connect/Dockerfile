FROM confluentinc/cp-kafka-connect:7.6.1

# Debezium PostgreSQL source connector (note the .Final suffix)
RUN confluent-hub install --no-prompt debezium/debezium-connector-postgresql:latest

# Confluent JDBC sink connector
RUN confluent-hub install --no-prompt confluentinc/kafka-connect-jdbc:10.7.5

# PostgreSQL JDBC driver
RUN curl -fsSL -o /usr/share/confluent-hub-components/confluentinc-kafka-connect-jdbc/lib/postgresql-42.7.3.jar \
    https://jdbc.postgresql.org/download/postgresql-42.7.3.jar