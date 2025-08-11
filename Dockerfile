FROM eclipse-temurin:17-jdk-alpine

WORKDIR /app

COPY pom.xml mvnw ./
COPY .mvn .mvn
COPY src src

RUN ./mvnw clean package -DskipTests

EXPOSE 8080

ENTRYPOINT ["java","-jar","target/backend-java-player-service.jar"]
