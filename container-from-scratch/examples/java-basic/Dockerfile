FROM maven:3.9-eclipse-temurin-17 AS build
WORKDIR /app
COPY . .
RUN mvn package

FROM eclipse-temurin:17-jre-jammy
COPY --from=build /app/target/java-basic-1.0.jar /app/app.jar
CMD ["java", "-jar", "/app/app.jar"]
