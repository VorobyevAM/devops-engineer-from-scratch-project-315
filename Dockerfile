FROM node:24-bookworm-slim AS frontend-builder

WORKDIR /app

COPY frontend/package.json frontend/package-lock.json ./frontend/
RUN npm --prefix frontend ci

COPY frontend ./frontend
RUN npm --prefix frontend run build

FROM gradle:9.2.1-jdk21-jammy AS backend-builder

WORKDIR /app

ENV GRADLE_OPTS="-Dorg.gradle.internal.http.connectionTimeout=120000 -Dorg.gradle.internal.http.socketTimeout=120000"

COPY gradle ./gradle
COPY gradlew build.gradle.kts settings.gradle.kts ./
COPY src ./src
COPY public ./public
COPY --from=frontend-builder /app/frontend/dist /tmp/frontend-dist

RUN chmod +x gradlew \
    && rm -rf src/main/resources/static \
    && mkdir -p src/main/resources/static \
    && cp -r /tmp/frontend-dist/. src/main/resources/static/ \
    && for attempt in 1 2 3; do \
        ./gradlew --no-daemon test bootJar && exit 0; \
        if [ "$attempt" -eq 3 ]; then exit 1; fi; \
        echo "Gradle build failed, retrying in 5 seconds..."; \
        sleep 5; \
    done

FROM eclipse-temurin:21-jre-jammy AS runtime

WORKDIR /app

RUN groupadd --system spring && useradd --system --gid spring --create-home spring

COPY --from=backend-builder /app/build/libs/*.jar /app/app.jar

USER spring

EXPOSE 8080 9090

ENTRYPOINT ["sh", "-c", "exec java $JAVA_OPTS -jar /app/app.jar"]
