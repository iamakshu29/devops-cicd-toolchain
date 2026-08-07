# Stage 1 — build the JAR
FROM maven:3.9-eclipse-temurin-17 AS builder
WORKDIR /app
COPY pom.xml .
# Download dependencies separately so Docker cache reuses this layer on code-only changes
RUN mvn dependency:go-offline -q
COPY src/ ./src/
RUN mvn clean package -DskipTests -q

# Stage 2 — minimal runtime image
FROM eclipse-temurin:17-jre-alpine
RUN addgroup -S app && adduser -S app -G app
WORKDIR /app
COPY --from=builder --chown=app:app /app/target/*.jar app.jar
USER app
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]
