https://dontpad.com/NeevDemo

docker-compose.yml

services:
  zookeeper:
    image: confluentinc/cp-zookeeper:7.6.1
    environment:
      ZOOKEEPER_CLIENT_PORT: 2181
      ZOOKEEPER_TICK_TIME: 2000
    ports: ["2181:2181"]

  broker:
    image: confluentinc/cp-kafka:7.6.1
    mem_limit: 2g
    depends_on: [zookeeper]
    ports:
      - "9092:9092"    # internal client access
      - "29092:29092"  # host access
    environment:
      KAFKA_BROKER_ID: 1
      KAFKA_ZOOKEEPER_CONNECT: zookeeper:2181
      KAFKA_ADVERTISED_LISTENERS: PLAINTEXT://broker:9092,PLAINTEXT_HOST://localhost:29092
      KAFKA_LISTENER_SECURITY_PROTOCOL_MAP: PLAINTEXT:PLAINTEXT,PLAINTEXT_HOST:PLAINTEXT
      KAFKA_INTER_BROKER_LISTENER_NAME: PLAINTEXT
      KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR: 1

  schema-registry:
    image: confluentinc/cp-schema-registry:7.6.1
    depends_on: [broker]
    ports: ["8081:8081"]
    environment:
      SCHEMA_REGISTRY_HOST_NAME: schema-registry
      SCHEMA_REGISTRY_KAFKASTORE_BOOTSTRAP_SERVERS: broker:9092

  connect:
    image: confluentinc/cp-kafka-connect:7.6.1
    mem_limit: 2g
    depends_on: [broker, schema-registry]
    ports: ["8083:8083"]
    environment:
      CONNECT_BOOTSTRAP_SERVERS: kafka:9092
      CONNECT_REST_ADVERTISED_HOST_NAME: connect
      CONNECT_GROUP_ID: connect-group
      CONNECT_CONFIG_STORAGE_TOPIC: connect-configs
      CONNECT_OFFSET_STORAGE_TOPIC: connect-offsets
      CONNECT_STATUS_STORAGE_TOPIC: connect-status
      CONNECT_CONFIG_STORAGE_REPLICATION_FACTOR: 1
      CONNECT_OFFSET_STORAGE_REPLICATION_FACTOR: 1
      CONNECT_STATUS_STORAGE_REPLICATION_FACTOR: 1
      # For beginner demos we’ll use String, but you can switch to Avro/Protobuf easily.
      CONNECT_KEY_CONVERTER: org.apache.kafka.connect.storage.StringConverter
      CONNECT_VALUE_CONVERTER: org.apache.kafka.connect.storage.StringConverter
      CONNECT_PLUGIN_PATH: /usr/share/java,/usr/share/confluent-hub-components
    # Install JDBC & Debezium connectors, then start Connect
    command:
      - bash
      - -c
      - |
        confluent-hub install --no-prompt confluentinc/kafka-connect-jdbc:10.7.6
        confluent-hub install --no-prompt debezium/debezium-connector-postgresql:2.6.1
        /etc/confluent/docker/run

  postgres:
    image: postgres:15
    environment:
      POSTGRES_USER: bank
      POSTGRES_PASSWORD: bankpw
      POSTGRES_DB: bankdb
    ports: ["5432:5432"]

  kcat:
    image: edenhill/kcat:1.7.1
    platform: linux/amd64 
    depends_on: [broker]
    entrypoint: ["sh","-c","sleep infinity"]
    #command: ["kcat", "-b", "broker:9092", "-L"]


connect/Dockerfile:

FROM confluentinc/cp-kafka-connect:7.6.1

# Debezium PostgreSQL source connector (note the .Final suffix)
RUN confluent-hub install --no-prompt debezium/debezium-connector-postgresql:latest

# Confluent JDBC sink connector
RUN confluent-hub install --no-prompt confluentinc/kafka-connect-jdbc:10.7.5

# PostgreSQL JDBC driver
RUN curl -fsSL -o /usr/share/confluent-hub-components/confluentinc-kafka-connect-jdbc/lib/postgresql-42.7.3.jar \
    https://jdbc.postgresql.org/download/postgresql-42.7.3.jar

jdbc-sink.json

{
  "name": "banking-jdbc-sink",
  "config": {
    "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
    "tasks.max": "1",

    "topics.regex": "banking\\.public\\.(accounts|transactions)",

    "connection.url": "jdbc:postgresql://postgres:5432/banking",
    "connection.user": "postgres",
    "connection.password": "postgres",

    "auto.create": "true",
    "auto.evolve": "true",

    "insert.mode": "upsert",
    "pk.mode": "record_key",
    "delete.enabled": "false",

    "transforms": "unwrap,route",
    "transforms.unwrap.type": "io.debezium.transforms.ExtractNewRecordState",
    "transforms.unwrap.drop.tombstones": "true",
    "transforms.unwrap.delete.handling.mode": "rewrite",

    "transforms.route.type": "org.apache.kafka.connect.transforms.RegexRouter",
    "transforms.route.regex": "banking\\.public\\.(.*)",
    "transforms.route.replacement": "$1",

    "table.name.format": "analytics.${topic}"
  }
}

postgres-source.json


{
  "name": "banking-pg-source",
  "config": {
    "connector.class": "io.debezium.connector.postgresql.PostgresConnector",
    "tasks.max": "1",
    "database.hostname": "postgres",
    "database.port": "5432",
    "database.user": "postgres",
    "database.password": "postgres",
    "database.dbname": "banking",

    "topic.prefix": "banking",
    "plugin.name": "pgoutput",
    "schema.include.list": "public",
    "table.include.list": "public.accounts,public.transactions",

    "slot.name": "debezium_banking",
    "publication.autocreate.mode": "filtered",
    "snapshot.mode": "initial",

    "decimal.handling.mode": "string",
    "tombstones.on.delete": "false",
    "tombstone.handling.mode": "none",

    "key.converter": "org.apache.kafka.connect.json.JsonConverter",
    "key.converter.schemas.enable": "false",
    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
    "value.converter.schemas.enable": "false"
  }
}

sql/init.sql

CREATE SCHEMA IF NOT EXISTS analytics;

CREATE TABLE IF NOT EXISTS public.accounts (
  account_id SERIAL PRIMARY KEY,
  customer_name TEXT NOT NULL,
  account_type TEXT NOT NULL CHECK (account_type IN ('SAVINGS','CURRENT')),
  balance NUMERIC(14,2) NOT NULL DEFAULT 0,
  opened_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.transactions (
  tx_id BIGSERIAL PRIMARY KEY,
  account_id INT NOT NULL REFERENCES public.accounts(account_id),
  amount NUMERIC(14,2) NOT NULL,
  currency CHAR(3) NOT NULL DEFAULT 'INR',
  merchant TEXT,
  channel TEXT CHECK (channel IN ('UPI','CARD','IMPS','NEFT','RTGS','ATM')),
  direction TEXT CHECK (direction IN ('DEBIT','CREDIT')),
  event_time TIMESTAMP NOT NULL DEFAULT NOW()
);



-- Seed customers & a few transactions
INSERT INTO public.accounts (customer_name, account_type, balance)
VALUES ('Asha Rao','SAVINGS',50000.00),
       ('Vikram Singh','CURRENT',250000.00);	

INSERT INTO public.transactions (account_id, amount, currency, merchant, channel, direction, event_time)
VALUES (1, -1500.00, 'INR', 'BigBazaar', 'CARD', 'DEBIT', NOW() - INTERVAL '1 day'),
       (1,  20000.00, 'INR', 'Salary',    'NEFT', 'CREDIT', NOW() - INTERVAL '20 hours'),
       (2,  -5000.00, 'INR', 'Amazon',    'CARD', 'DEBIT', NOW() - INTERVAL '2 hours');

Output:

[+] Running 8/8
 ✔ Network neev_default                                                                                                                                Created                                                                                 0.0s 
 ✔ Container neev-postgres-1                                                                                                                           Started                                                                                 0.4s 
 ✔ Container neev-zookeeper-1                                                                                                                          Started                                                                                 0.4s 
 ✔ Container neev-broker-1                                                                                                                             Started                                                                                 0.4s 
 ✔ Container neev-kcat-1                                                                                                                               Started                                                                                 0.5s 
 ✔ Container neev-schema-registry-1                                                                                                                    Started                                                                                 0.6s 
 ✔ Container neev-connect-1                                                                                                                            Started                                                                                 0.8s 


To Start Containers:

docker compose build
docker compose up -d


To Verify:

docker compose exec connect kcat --version

docker compose ps

curl -s http://localhost:8083/connector-plugins | jq

Open a shell in the broker container and create topics:

docker exec -it $(docker ps --filter "ancestor=confluentinc/cp-kafka:7.6.1" -q) bash

Create Topics:

kafka-topics --bootstrap-server broker:9092 --create --topic bank.transfers --partitions 3 --replication-factor 1

kafka-topics --bootstrap-server broker:9092 --create --topic bank.notifications --partitions 3 --replication-factor 1

kafka-topics --bootstrap-server broker:9092 --create --topic bank.dlq --partitions 3 --replication-factor 1

List Topics:

kafka-topics --bootstrap-server broker:9092 --list


Quick Test from Console:

brew install kcat

Produce and consume a test event using kcat:

kcat -b localhost:29092 -t bank.transfers -L


Kafka Connect – Example A (File ➜ Kafka ➜ File)

# Create input file
docker exec -it connect bash -lc "printf 'txn-100,{\"from\":\"john\",\"to\":\"jane\",\"amount\":250}\n' >> /tmp/input.txt"

# Create source connector
curl -s -X POST http://localhost:8083/connectors \
  -H 'Content-Type: application/json' \
  -d '{
    "name": "file-source-1",
    "config": {
      "connector.class": "FileStreamSource",
      "tasks.max": "1",
      "file": "/tmp/input.txt",
      "topic": "bank.transfers"
    }
  }' | jq .

Append new lines to /tmp/input.txt and watch them appear in the topic.

docker exec -it connect bash -lc "echo 'txn-101,{\"from\":\"anil\",\"to\":\"sunita\",\"amount\":500}' >> /tmp/input.txt"

Verify:

docker exec -it $(docker ps --filter "ancestor=edenhill/kcat:1.7.1" -q) \
  kcat -b broker:9092 -t bank.transfers -C -o end

Kafka ➜ File (Sink)

curl -s -X POST http://localhost:8083/connectors \
  -H 'Content-Type: application/json' \
  -d '{
    "name": "file-sink-1",
    "config": {
      "connector.class": "FileStreamSink",
      "tasks.max": "1",
      "topics": "bank.transfers",
      "file": "/tmp/output.txt"
    }z
  }' | jq .f

# Read sink output
docker exec -it connect bash -lc "tail -n +1 /tmp/output.txt"

This demo shows publish/subscribe with a source and sink connector without writing any code.

Kafka Connect – Example B (Postgres ➜ Kafka using JDBC Source)

# Create table & seed rows
docker exec -it $(docker ps --filter "ancestor=postgres:15" -q) psql -U bank -d bankdb -c "
CREATE TABLE IF NOT EXISTS transfers (
  id SERIAL PRIMARY KEY,
  from_acct VARCHAR(50),
  to_acct   VARCHAR(50),
  amount    NUMERIC(12,2),
  created_at TIMESTAMP DEFAULT NOW()
);
INSERT INTO transfers(from_acct,to_acct,amount) VALUES
  ('alice','bob',100.00),('geeta','rahul',300.50);
"



				