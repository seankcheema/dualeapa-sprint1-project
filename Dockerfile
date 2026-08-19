FROM maven:3.9-eclipse-temurin-21 AS build


WORKDIR /app
COPY pom.xml .
COPY src ./src
RUN mvn -B package -DskipTests

FROM eclipse-temurin:21-jre-alpine AS runtime

WORKDIR /app

# Run as a non-root user for better container security.
RUN addgroup -S app && adduser -S app -G app

COPY --from=build /app/target/sprint1-greeter-app.jar /app/app.jar

USER app

ENTRYPOINT ["java", "-jar", "/app/app.jar"]
