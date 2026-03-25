package com.otel.demo;

import io.opentelemetry.api.GlobalOpenTelemetry;
import io.opentelemetry.api.trace.Span;
import io.opentelemetry.api.trace.Tracer;
import org.apache.kafka.clients.producer.KafkaProducer;
import org.apache.kafka.clients.producer.ProducerConfig;
import org.apache.kafka.clients.producer.ProducerRecord;
import org.apache.kafka.clients.admin.AdminClient;
import org.apache.kafka.clients.admin.AdminClientConfig;
import org.apache.kafka.clients.admin.NewTopic;
import org.apache.kafka.common.serialization.StringSerializer;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.reactive.function.client.WebClient;
import software.amazon.awssdk.core.SdkBytes;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.dynamodb.DynamoDbClient;
import software.amazon.awssdk.services.dynamodb.model.AttributeValue;
import software.amazon.awssdk.services.dynamodb.model.PutItemRequest;
import software.amazon.awssdk.services.kinesis.KinesisClient;
import software.amazon.awssdk.services.kinesis.model.PutRecordRequest;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.GetObjectRequest;
import software.amazon.awssdk.services.sns.SnsClient;
import software.amazon.awssdk.services.sns.model.PublishRequest;
import software.amazon.awssdk.services.sqs.SqsClient;
import software.amazon.awssdk.services.sqs.model.SendMessageRequest;

import jakarta.annotation.PostConstruct;
import java.nio.charset.StandardCharsets;
import java.sql.*;
import java.time.Instant;
import java.util.*;

@RestController
public class OrderController {

    private static final Logger log = LoggerFactory.getLogger(OrderController.class);
    private final Tracer tracer = GlobalOpenTelemetry.getTracer("order-processor-java");

    private final String tableName = env("DYNAMODB_TABLE_NAME", "otel-demo-orders");
    private final String bucketName = env("S3_BUCKET_NAME", "");
    private final String paymentUrl = env("PAYMENT_PROCESSOR_URL", "");
    private final String inventoryUrl = env("INVENTORY_SERVICE_URL", "");
    private final String snsTopicArn = env("SNS_TOPIC_ARN", "");
    private final String sqsQueueUrl = env("SQS_QUEUE_URL", "");
    private final String kinesisStream = env("KINESIS_STREAM_NAME", "");
    private final String region = env("AWS_REGION", "us-east-1");
    private final String pgHost = env("PG_HOST", "");
    private final String pgPort = env("PG_PORT", "5432");
    private final String pgUser = env("PG_USER", "otelu");
    private final String pgPassword = env("PG_PASSWORD", "otelpassword123");
    private final String pgDatabase = env("PG_DATABASE", "otel");
    private final String mskBootstrap = env("MSK_BOOTSTRAP", "");

    private DynamoDbClient dynamodb;
    private S3Client s3;
    private SnsClient sns;
    private SqsClient sqs;
    private KinesisClient kinesis;
    private WebClient webClient;
    private Connection pgConn;
    private KafkaProducer<String, String> kafkaProducer;

    @PostConstruct
    public void init() {
        Region awsRegion = Region.of(region);
        dynamodb = DynamoDbClient.builder().region(awsRegion).build();
        s3 = S3Client.builder().region(awsRegion).build();
        sns = SnsClient.builder().region(awsRegion).build();
        sqs = SqsClient.builder().region(awsRegion).build();
        kinesis = KinesisClient.builder().region(awsRegion).build();
        webClient = WebClient.create();

        // Aurora PostgreSQL
        if (!pgHost.isEmpty()) {
            try {
                String jdbcUrl = String.format("jdbc:postgresql://%s:%s/%s?sslmode=require", pgHost, pgPort, pgDatabase);
                pgConn = DriverManager.getConnection(jdbcUrl, pgUser, pgPassword);
                pgConn.setAutoCommit(true);
                try (Statement stmt = pgConn.createStatement()) {
                    stmt.execute("""
                        CREATE TABLE IF NOT EXISTS orders_java (
                            order_id VARCHAR(255) PRIMARY KEY,
                            status VARCHAR(50),
                            platform VARCHAR(50),
                            created_at TIMESTAMP DEFAULT NOW()
                        )
                    """);
                }
                log.info("Aurora PostgreSQL connected: {}", pgHost);
            } catch (Exception e) {
                log.warn("Aurora PostgreSQL setup failed: {}", e.getMessage());
            }
        }

        // MSK Kafka producer
        if (!mskBootstrap.isEmpty()) {
            try {
                Properties props = new Properties();
                props.put(ProducerConfig.BOOTSTRAP_SERVERS_CONFIG, mskBootstrap);
                props.put(ProducerConfig.KEY_SERIALIZER_CLASS_CONFIG, StringSerializer.class.getName());
                props.put(ProducerConfig.VALUE_SERIALIZER_CLASS_CONFIG, StringSerializer.class.getName());
                props.put("security.protocol", "SASL_SSL");
                props.put("sasl.mechanism", "AWS_MSK_IAM");
                props.put("sasl.jaas.config", "software.amazon.msk.auth.iam.IAMLoginModule required;");
                props.put("sasl.client.callback.handler.class", "software.amazon.msk.auth.iam.IAMClientCallbackHandler");
                props.put(ProducerConfig.REQUEST_TIMEOUT_MS_CONFIG, 10000);
                props.put("allow.auto.create.topics", "true");
                props.put("client.dns.lookup", "use_all_dns_ips");

                // Ensure topic exists via AdminClient
                try {
                    Properties adminProps = new Properties();
                    adminProps.put(AdminClientConfig.BOOTSTRAP_SERVERS_CONFIG, mskBootstrap);
                    adminProps.put("security.protocol", "SASL_SSL");
                    adminProps.put("sasl.mechanism", "AWS_MSK_IAM");
                    adminProps.put("sasl.jaas.config", "software.amazon.msk.auth.iam.IAMLoginModule required;");
                    adminProps.put("sasl.client.callback.handler.class", "software.amazon.msk.auth.iam.IAMClientCallbackHandler");
                    adminProps.put(AdminClientConfig.REQUEST_TIMEOUT_MS_CONFIG, 15000);
                    try (AdminClient admin = AdminClient.create(adminProps)) {
                        if (!admin.listTopics().names().get(15, java.util.concurrent.TimeUnit.SECONDS).contains("otel-demo-orders")) {
                            admin.createTopics(List.of(new NewTopic("otel-demo-orders", 1, (short) 1)))
                                 .all().get(15, java.util.concurrent.TimeUnit.SECONDS);
                            log.info("MSK topic 'otel-demo-orders' created");
                        } else {
                            log.info("MSK topic 'otel-demo-orders' already exists");
                        }
                    }
                } catch (Exception e) {
                    log.warn("MSK topic creation check failed (will try producing anyway): {}", e.getMessage());
                }

                kafkaProducer = new KafkaProducer<>(props);
                log.info("MSK Kafka connected: {}", mskBootstrap);
            } catch (Exception e) {
                log.warn("MSK Kafka setup failed: {}", e.getMessage());
            }
        }
    }

    @GetMapping({"/health", "/"})
    public Map<String, String> health() {
        return Map.of("status", "ok", "service", "multi-order-processor-java", "platform", "ecs");
    }

    @RequestMapping(value = {"/order", "/order-java"}, method = {RequestMethod.GET, RequestMethod.POST})
    public ResponseEntity<Map<String, Object>> createOrder() {
        return processOrder(false);
    }

    @RequestMapping(value = {"/order-slow", "/order-java-slow"}, method = {RequestMethod.GET, RequestMethod.POST})
    public ResponseEntity<Map<String, Object>> createOrderSlow() {
        return processOrder(true);
    }

    private ResponseEntity<Map<String, Object>> processOrder(boolean simulateSlow) {
        String orderId = UUID.randomUUID().toString();
        String timestamp = String.valueOf(Instant.now().getEpochSecond());
        List<String> steps = new ArrayList<>();

        String orderJson = String.format(
            "{\"orderId\":\"%s\",\"status\":\"CREATED\",\"platform\":\"ecs-java\",\"timestamp\":\"%s\"}",
            orderId, timestamp);

        // DynamoDB
        try {
            Map<String, AttributeValue> item = Map.of(
                "orderId", AttributeValue.fromS(orderId),
                "status", AttributeValue.fromS("CREATED"),
                "platform", AttributeValue.fromS("ecs-java"),
                "timestamp", AttributeValue.fromS(timestamp)
            );
            dynamodb.putItem(PutItemRequest.builder().tableName(tableName).item(item).build());
            steps.add("dynamodb: order written");
        } catch (Exception e) {
            steps.add("dynamodb: " + e.getMessage());
        }

        // S3
        if (!bucketName.isEmpty()) {
            try {
                s3.getObject(GetObjectRequest.builder().bucket(bucketName).key("catalog.json").build());
                steps.add("s3: catalog read");
            } catch (Exception e) {
                steps.add("s3: " + e.getMessage());
            }
        }

        // Lambda via API Gateway
        if (!paymentUrl.isEmpty()) {
            try {
                String resp = webClient.post().uri(paymentUrl)
                    .bodyValue(Map.of("order_id", orderId, "amount", 42.99))
                    .retrieve().bodyToMono(String.class)
                    .block(java.time.Duration.ofSeconds(10));
                steps.add("payment: 200");
            } catch (Exception e) {
                steps.add("payment: " + e.getMessage());
            }
        }

        // Inventory via ALB
        if (!inventoryUrl.isEmpty()) {
            try {
                String resp = webClient.get()
                    .uri(inventoryUrl + "/inventory?product_id=OLJCESPC7Z")
                    .retrieve().bodyToMono(String.class)
                    .block(java.time.Duration.ofSeconds(10));
                steps.add("inventory: 200");
            } catch (Exception e) {
                steps.add("inventory: " + e.getMessage());
            }
        }

        // SNS
        if (!snsTopicArn.isEmpty()) {
            try {
                sns.publish(PublishRequest.builder()
                    .topicArn(snsTopicArn).message(orderJson).subject("OrderCreated").build());
                steps.add("sns: published");
            } catch (Exception e) {
                steps.add("sns: " + e.getMessage());
            }
        }

        // SQS
        if (!sqsQueueUrl.isEmpty()) {
            try {
                sqs.sendMessage(SendMessageRequest.builder()
                    .queueUrl(sqsQueueUrl).messageBody(orderJson).build());
                steps.add("sqs: sent");
            } catch (Exception e) {
                steps.add("sqs: " + e.getMessage());
            }
        }

        // Kinesis
        if (!kinesisStream.isEmpty()) {
            try {
                kinesis.putRecord(PutRecordRequest.builder()
                    .streamName(kinesisStream)
                    .data(SdkBytes.fromString(orderJson, StandardCharsets.UTF_8))
                    .partitionKey(orderId).build());
                steps.add("kinesis: put record");
            } catch (Exception e) {
                steps.add("kinesis: " + e.getMessage());
            }
        }

        // Aurora PostgreSQL
        if (pgConn != null) {
            // Simulate slow query on managed PostgreSQL (Aurora)
            if (simulateSlow) {
                try (Statement stmt = pgConn.createStatement()) {
                    stmt.execute("SELECT pg_sleep(2)");
                    steps.add("aurora: slow query (2s pg_sleep)");
                } catch (Exception e) {
                    steps.add("aurora-slow: " + e.getMessage());
                }
            }
            try (PreparedStatement ps = pgConn.prepareStatement(
                    "INSERT INTO orders_java (order_id, status, platform) VALUES (?, ?, ?) ON CONFLICT (order_id) DO NOTHING")) {
                ps.setString(1, orderId);
                ps.setString(2, "CREATED");
                ps.setString(3, "ecs-java");
                ps.executeUpdate();
                steps.add("aurora: order inserted");
            } catch (Exception e) {
                steps.add("aurora: " + e.getMessage());
            }
        }

        // MSK Kafka
        if (kafkaProducer != null) {
            try {
                kafkaProducer.send(new ProducerRecord<>("otel-demo-orders", orderId, orderJson)).get();
                steps.add("msk: message sent");
            } catch (Exception e) {
                steps.add("msk: " + e.getMessage());
            }
        }

        Map<String, Object> response = new LinkedHashMap<>();
        response.put("orderId", orderId);
        response.put("platform", "ecs-java");
        response.put("steps", steps);
        return ResponseEntity.ok(response);
    }

    private static String env(String key, String defaultValue) {
        String val = System.getenv(key);
        return (val != null && !val.isEmpty()) ? val : defaultValue;
    }
}
