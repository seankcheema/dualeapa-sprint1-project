### Sprint 1 Greeter App Dockerfile
### Multi-stage build for a small, secure Java runtime image

FROM maven:3.9.9-eclipse-temurin-21 AS build

WORKDIR /app

# Copy pom first for better dependency layer caching.
COPY pom.xml ./
RUN mvn -q -DskipTests dependency:go-offline

# Copy sources and build executable jar.
COPY src ./src
RUN mvn -q -DskipTests clean package


FROM eclipse-temurin:21-jre-alpine AS runtime

WORKDIR /app

# Run as a non-root user for better container security.
RUN addgroup -S app && adduser -S app -G app

COPY --from=build /app/target/sprint1-greeter-app.jar /app/app.jar

USER app

ENTRYPOINT ["java", "-jar", "/app/app.jar"]
