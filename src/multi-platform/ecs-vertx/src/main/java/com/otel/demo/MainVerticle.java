package com.otel.demo;

import com.fasterxml.jackson.databind.ObjectMapper;
import io.opentelemetry.api.GlobalOpenTelemetry;
import io.opentelemetry.api.trace.Tracer;
import io.vertx.core.AbstractVerticle;
import io.vertx.core.Promise;
import io.vertx.core.Vertx;
import io.vertx.core.json.JsonObject;
import io.vertx.ext.web.Router;
import io.vertx.ext.web.RoutingContext;
import io.vertx.ext.web.client.WebClient;
import io.vertx.pgclient.PgConnectOptions;
import io.vertx.pgclient.PgPool;
import io.vertx.pgclient.SslMode;
import io.vertx.sqlclient.PoolOptions;
import io.vertx.sqlclient.Row;
import io.vertx.sqlclient.Tuple;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.dynamodb.DynamoDbClient;
import software.amazon.awssdk.services.dynamodb.model.AttributeValue;
import software.amazon.awssdk.services.dynamodb.model.PutItemRequest;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.GetObjectRequest;

import java.time.Instant;
import java.util.*;

/**
 * Vert.x Order Processor - tests OTel Java agent instrumentation of:
 * 1. Vert.x HTTP server (route detection)
 * 2. Vert.x reactive SQL client (DB spans via native client)
 * 3. Vert.x RxJava2 wrapped SQL client (DB spans via wrapper - customer issue)
 * 4. Vert.x WebClient (HTTP client spans)
 * 5. AWS SDK v2 (DynamoDB, S3)
 */
public class MainVerticle extends AbstractVerticle {

    private static final Logger log = LoggerFactory.getLogger(MainVerticle.class);
    private final Tracer tracer = GlobalOpenTelemetry.getTracer("order-processor-vertx");

    private PgPool pgPool;           // Native Vert.x PG client
    private io.vertx.reactivex.sqlclient.Pool rxPgPool;  // RxJava2 wrapped client (customer pattern)
    private WebClient webClient;
    private DynamoDbClient dynamodb;
    private S3Client s3;

    private final String tableName = env("DYNAMODB_TABLE_NAME", "otel-demo-orders");
    private final String bucketName = env("S3_BUCKET_NAME", "");
    private final String inventoryUrl = env("INVENTORY_SERVICE_URL", "");
    private final String region = env("AWS_REGION", "us-east-1");
    private final int port = Integer.parseInt(env("SERVICE_PORT", "8080"));

    public static void main(String[] args) {
        Vertx vertx = Vertx.vertx();
        vertx.deployVerticle(new MainVerticle());
    }

    @Override
    public void start(Promise<Void> startPromise) {
        // AWS SDK clients
        Region awsRegion = Region.of(region);
        dynamodb = DynamoDbClient.builder().region(awsRegion).build();
        s3 = S3Client.builder().region(awsRegion).build();
        webClient = WebClient.create(vertx);

        // Native Vert.x PG client (OTel should instrument this)
        String pgHost = env("PG_HOST", "");
        if (!pgHost.isEmpty()) {
            PgConnectOptions connectOptions = new PgConnectOptions()
                .setHost(pgHost)
                .setPort(Integer.parseInt(env("PG_PORT", "5432")))
                .setDatabase(env("PG_DATABASE", "otel"))
                .setUser(env("PG_USER", "otelu"))
                .setPassword(env("PG_PASSWORD", "otelpassword123"))
                .setSslMode(SslMode.REQUIRE)
                .setTrustAll(true);
            pgPool = PgPool.pool(vertx, connectOptions, new PoolOptions().setMaxSize(5));

            // RxJava2 wrapped pool (simulates customer's wrapper pattern)
            io.vertx.reactivex.core.Vertx rxVertx = io.vertx.reactivex.core.Vertx.newInstance(vertx);
            rxPgPool = io.vertx.reactivex.sqlclient.Pool.newInstance(pgPool);

            // Create table
            pgPool.query("""
                CREATE TABLE IF NOT EXISTS orders_vertx (
                    order_id VARCHAR(255) PRIMARY KEY,
                    status VARCHAR(50),
                    platform VARCHAR(50),
                    created_at TIMESTAMP DEFAULT NOW()
                )
            """).execute().onSuccess(r -> log.info("Aurora PG connected: {}", pgHost))
              .onFailure(e -> log.warn("Aurora PG setup failed: {}", e.getMessage()));
        }

        // Routes
        Router router = Router.router(vertx);
        router.get("/health").handler(this::health);
        router.get("/").handler(this::health);
        router.route("/order-vertx").handler(this::createOrder);
        router.route("/order-vertx-native-db").handler(this::orderWithNativeDb);
        router.route("/order-vertx-rx-db").handler(this::orderWithRxDb);
        router.route("/order-vertx-slow").handler(this::orderSlow);

        vertx.createHttpServer()
            .requestHandler(router)
            .listen(port)
            .onSuccess(s -> {
                log.info("Vert.x order processor started on port {}", port);
                startPromise.complete();
            })
            .onFailure(startPromise::fail);
    }

    private void health(RoutingContext ctx) {
        ctx.json(new JsonObject()
            .put("status", "ok")
            .put("service", "multi-order-processor-vertx")
            .put("platform", "ecs")
            .put("framework", "vertx"));
    }

    /**
     * Full order flow: DynamoDB + S3 + native PG + inventory call
     */
    private void createOrder(RoutingContext ctx) {
        String orderId = UUID.randomUUID().toString();
        String timestamp = String.valueOf(Instant.now().getEpochSecond());
        List<String> steps = new ArrayList<>();

        // DynamoDB (sync - AWS SDK v2, instrumented by OTel agent)
        try {
            dynamodb.putItem(PutItemRequest.builder().tableName(tableName).item(Map.of(
                "orderId", AttributeValue.fromS(orderId),
                "status", AttributeValue.fromS("CREATED"),
                "platform", AttributeValue.fromS("ecs-vertx"),
                "timestamp", AttributeValue.fromS(timestamp)
            )).build());
            steps.add("dynamodb: order written");
        } catch (Exception e) {
            steps.add("dynamodb: " + e.getMessage());
        }

        // S3 (sync)
        if (!bucketName.isEmpty()) {
            try {
                s3.getObject(GetObjectRequest.builder().bucket(bucketName).key("catalog.json").build());
                steps.add("s3: catalog read");
            } catch (Exception e) {
                steps.add("s3: " + e.getMessage());
            }
        }

        // Native Vert.x PG client (async - should generate DB span)
        if (pgPool != null) {
            pgPool.preparedQuery("INSERT INTO orders_vertx (order_id, status, platform) VALUES ($1, $2, $3) ON CONFLICT (order_id) DO NOTHING")
                .execute(Tuple.of(orderId, "CREATED", "ecs-vertx"))
                .onSuccess(r -> log.info("Native PG insert OK"))
                .onFailure(e -> log.warn("Native PG insert failed: {}", e.getMessage()));
            steps.add("aurora-native: insert queued");
        }

        ctx.json(new JsonObject()
            .put("orderId", orderId)
            .put("platform", "ecs-vertx")
            .put("steps", steps));
    }

    /**
     * Test: Native Vert.x SQL client (should be instrumented by OTel agent)
     */
    private void orderWithNativeDb(RoutingContext ctx) {
        if (pgPool == null) {
            ctx.json(new JsonObject().put("error", "PG not configured"));
            return;
        }
        String orderId = UUID.randomUUID().toString();
        pgPool.preparedQuery("SELECT $1::text as order_id, NOW() as created_at")
            .execute(Tuple.of(orderId))
            .onSuccess(rows -> {
                List<String> results = new ArrayList<>();
                for (Row row : rows) {
                    results.add("order_id=" + row.getString("order_id") + " at=" + row.getTemporal("created_at"));
                }
                ctx.json(new JsonObject()
                    .put("method", "native-vertx-pg-client")
                    .put("orderId", orderId)
                    .put("results", results)
                    .put("note", "OTel agent should create a DB span for this query"));
            })
            .onFailure(e -> ctx.json(new JsonObject().put("error", e.getMessage())));
    }

    /**
     * Test: RxJava2 wrapped Vert.x SQL client (customer's pattern - may NOT generate DB span)
     */
    private void orderWithRxDb(RoutingContext ctx) {
        if (rxPgPool == null) {
            ctx.json(new JsonObject().put("error", "RxPG not configured"));
            return;
        }
        String orderId = UUID.randomUUID().toString();
        rxPgPool.preparedQuery("SELECT $1::text as order_id, NOW() as created_at")
            .rxExecute(io.vertx.reactivex.sqlclient.Tuple.of(orderId))
            .subscribe(
                rows -> {
                    List<String> results = new ArrayList<>();
                    for (io.vertx.reactivex.sqlclient.Row row : rows) {
                        results.add("order_id=" + row.getString("order_id") + " at=" + row.getTemporal("created_at"));
                    }
                    ctx.json(new JsonObject()
                        .put("method", "rxjava2-wrapped-vertx-pg-client")
                        .put("orderId", orderId)
                        .put("results", results)
                        .put("note", "RxJava2 wrapper - may bypass OTel instrumentation (customer issue)"));
                },
                e -> ctx.json(new JsonObject().put("error", e.getMessage()))
            );
    }

    /**
     * Test: Slow query simulation (pg_sleep)
     */
    private void orderSlow(RoutingContext ctx) {
        if (pgPool == null) {
            ctx.json(new JsonObject().put("error", "PG not configured"));
            return;
        }
        pgPool.query("SELECT pg_sleep(2)")
            .execute()
            .onSuccess(r -> ctx.json(new JsonObject()
                .put("method", "native-vertx-pg-client")
                .put("query", "SELECT pg_sleep(2)")
                .put("duration_ms", 2000)
                .put("note", "Slow query simulation on Aurora via Vert.x native client")))
            .onFailure(e -> ctx.json(new JsonObject().put("error", e.getMessage())));
    }

    private static String env(String key, String defaultValue) {
        String val = System.getenv(key);
        return (val != null && !val.isEmpty()) ? val : defaultValue;
    }
}
